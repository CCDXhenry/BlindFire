--!strict
local MatchManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local players = game:GetService("Players")

local scripts = replicatedStorage:WaitForChild("Scripts")
local serverScripts = serverStorage:WaitForChild("Scripts")
local CombatManager = require(serverScripts:WaitForChild("CombatManager"))
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local PlayerStateManager = require(serverScripts:WaitForChild("PlayerStateManager"))
local ConfigManager = require(serverScripts:WaitForChild("ConfigManager"))
local ArenaManager = require(serverScripts:WaitForChild("ArenaManager"))
local LeaderboardManager = require(serverScripts:WaitForChild("LeaderboardManager"))

type OnRoundStartCallback = (participantIds: { number }) -> ()

-- local MIN_PLAYER_TO_START = GameConfig.MinPlayerToStart
local LOBBY_SPAWN_NAME = "LobbySpawnArea"
local LOBBY_SPAWN_POINTS_FOLDER_NAME = "SpawnPoints"
local ARENA_SPAWN_FOLDER_NAME = "ArenaSpawnPoints"
local LOG_PREFIX = "[MatchManager]"
local VEHICLE_MODEL_NAME_PREFIX = "Vehicle_"
-- local MAX_SEAT_RETRY = 30
-- local SEAT_RETRY_INTERVAL = 0.2
-- local MAX_FORCE_SIT_RETRY = 20
-- local RETURN_TO_LOBBY_UNSEAT_WAIT_SEC = 0.1
-- local ARENA_SEAT_PREPARE_DELAY_SEC = 0.22

local seatRetryCountMap: { [number]: number } = {}
local arenaTargetPositionMap: { [number]: Vector3 } = {}

local currentMatchState: GameConfig.MatchState = "InLobby"
local roundWorkerThread: thread? = nil
local roundStartCallback: OnRoundStartCallback? = nil
local isStopRequested: boolean = false

local function GetNonAfkPlayers(): { Player }
	local result: { Player } = {}
	for _, player in players:GetPlayers() do
		if not PlayerStateManager.IsPlayerAfk(player.UserId) then
			table.insert(result, player)
		end
	end
	return result
end

local function OnRequestSetAfkState(player: Player, isAfk: boolean)
	if currentMatchState == "GameStartCountdown" or currentMatchState == "Fighting" then
		local roundInfo = PlayerStateManager.EnsurePlayerRoundInfo(player)
		if roundInfo.isParticipant and roundInfo.isAlive then
			return
		end
	end
	PlayerStateManager.SetPlayerAfk(player.UserId, isAfk == true)
	NetMsg.FireNotifyAfkState(player.UserId, isAfk == true)
end

local function OnRequestSyncAfkState(player: Player)
	for _, otherPlayer in players:GetPlayers() do
		local otherId = otherPlayer.UserId
		NetMsg.FireNotifyAfkStateToPlayer(player, otherId, PlayerStateManager.IsPlayerAfk(otherId))
	end
end

local function LogInfo(message: string)
	--print(string.format("%s %s", LOG_PREFIX, message))
end

local function FormatVector3(vector: Vector3): string
	return string.format("(%.1f, %.1f, %.1f)", vector.X, vector.Y, vector.Z)
end

local function MoveModelKeepRotation(model: Model, targetPosition: Vector3)
	local pivot = model:GetPivot()
	local rotationOnly = pivot - pivot.Position
	model:PivotTo(CFrame.new(targetPosition) * rotationOnly)
end

local function GetArenaSpawnPositionList(): { Vector3 }
	local arenaSpawnFolder = workspace:FindFirstChild(ARENA_SPAWN_FOLDER_NAME, true)
	if arenaSpawnFolder == nil or not arenaSpawnFolder:IsA("Instance") then
		LogInfo("ArenaSpawnPoints folder not found recursively")
		return {}
	end
	local spawnPositionList: { Vector3 } = {}
	for _, child in arenaSpawnFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(spawnPositionList, Vector3.new(child.Position.X, GameConfig.UnitY, child.Position.Z))
		end
	end
	return spawnPositionList
end

local function GetRandomArenaPosition(excludedPositions: { Vector3 }?): Vector3
	local arenaCenter, arenaSize = ArenaManager.GetArenaFloorInfo()
	local halfSize = (arenaSize.X / 2) - GameConfig.ArenaSpawnMargin
	local maxAttempts = 20
	local bestPos = arenaCenter

	for i = 1, maxAttempts do
		local randomX = (math.random() * 2 - 1) * halfSize
		local randomZ = (math.random() * 2 - 1) * halfSize
		local pos = arenaCenter + Vector3.new(randomX, GameConfig.UnitY - arenaCenter.Y, randomZ)

		local tooClose = false
		if excludedPositions then
			for _, otherPos in excludedPositions do
				local dist = (otherPos * Vector3.new(1, 0, 1) - pos * Vector3.new(1, 0, 1)).Magnitude
				if dist < GameConfig.MinSpawnSeparation then
					tooClose = true
					break
				end
			end
		end

		if not tooClose then
			return pos
		end
		bestPos = pos
		if i == maxAttempts then
			LogInfo(string.format("GetRandomArenaPosition warning: could not find separated position after %d attempts", maxAttempts))
		end
	end
	return bestPos
end

local function TeleportPlayerToPosition(player: Player, targetPosition: Vector3)
	local character = player.Character
	if character == nil then
		LogInfo(string.format("Wait teleport userId=%d reason=no_character", player.UserId))
		player.CharacterAdded:Once(function()
			if player.Parent ~= players then
				return
			end
			TeleportPlayerToPosition(player, targetPosition)
		end)
		return
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart == nil or not humanoidRootPart:IsA("BasePart") then
		LogInfo(string.format("Skip teleport userId=%d reason=no_hrp", player.UserId))
		return
	end
	character:PivotTo(CFrame.new(targetPosition))
	LogInfo(string.format("Teleport userId=%d target=%s", player.UserId, FormatVector3(targetPosition)))
	NetMsg.FireNotifyTeleport(player.UserId, targetPosition)
end

local function SeatPlayerOnVehicle(player: Player, targetPosition: Vector3)
	if players:GetPlayerByUserId(player.UserId) == nil then
		return
	end
	local vehicleModel: Model? = nil
	local unitInfoMap = CombatManager.GetUnitInfoMap()
	local unitInfo = unitInfoMap[player.UserId]
	if unitInfo ~= nil then
		vehicleModel = unitInfo.unitModel
	end

	if vehicleModel == nil or vehicleModel.Parent == nil then
		local vehicleName = VEHICLE_MODEL_NAME_PREFIX .. tostring(player.UserId)
		vehicleModel = workspace:FindFirstChild(vehicleName) :: Model?
	end

	if vehicleModel == nil or not vehicleModel:IsA("Model") then
		local retryCount = (seatRetryCountMap[player.UserId] or 0) + 1
		seatRetryCountMap[player.UserId] = retryCount
		if retryCount <= GameConfig.MaxSeatRetry then
			task.delay(GameConfig.SeatRetryInterval, function()
				if players:GetPlayerByUserId(player.UserId) == nil then
					return
				end
				SeatPlayerOnVehicle(player, targetPosition)
			end)
			return
		end
		LogInfo(string.format("Skip SeatPlayerOnVehicle userId=%d reason=vehicle_missing retry=%d", player.UserId, retryCount))
		return
	end
	seatRetryCountMap[player.UserId] = nil
	local seatInstance = vehicleModel:FindFirstChild("Seat", true)
	if seatInstance == nil or not seatInstance:IsA("Seat") then
		local primaryForUnanchor = vehicleModel.PrimaryPart
		if primaryForUnanchor ~= nil and primaryForUnanchor:IsA("BasePart") then
			primaryForUnanchor.Anchored = false
		end
		warn(string.format("%s Seat missing; unanchored PrimaryPart userId=%d vehicle=%s", LOG_PREFIX, player.UserId, vehicleModel.Name))
		LogInfo(string.format("Skip SeatPlayerOnVehicle userId=%d reason=seat_missing vehicle=%s", player.UserId, vehicleModel.Name))
		return
	end

	local primaryPart = vehicleModel.PrimaryPart
	if primaryPart ~= nil then
		primaryPart.Anchored = false
	end
	MoveModelKeepRotation(vehicleModel, targetPosition)
	if primaryPart ~= nil then
		primaryPart.AssemblyLinearVelocity = Vector3.zero
		primaryPart.AssemblyAngularVelocity = Vector3.zero
	end
	NetMsg.FireNotifyTeleport(player.UserId, targetPosition)

	local character = player.Character
	if character == nil then
		LogInfo(string.format("Wait SeatPlayerOnVehicle userId=%d reason=no_character", player.UserId))
		player.CharacterAdded:Once(function()
			if player.Parent ~= players then
				return
			end
			SeatPlayerOnVehicle(player, targetPosition)
		end)
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoidRootPart == nil or not humanoidRootPart:IsA("BasePart") then
		LogInfo(string.format("Skip SeatPlayerOnVehicle userId=%d reason=humanoid_or_hrp_missing", player.UserId))
		return
	end

	local function TryForceSeat(tryIndex: number)
		if tryIndex > GameConfig.MaxForceSitRetry then
			LogInfo(string.format("Skip SeatPlayerOnVehicle userId=%d reason=force_sit_retry_exhausted", player.UserId))
			return
		end
		if seatInstance.Occupant == humanoid then
			LogInfo(string.format("SeatPlayerOnVehicle userId=%d seatPos=%s retry=%d", player.UserId, FormatVector3(seatInstance.Position), tryIndex))
			return
		end
		character:PivotTo(seatInstance.CFrame + Vector3.new(0, 2.5, 0))
		humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
		humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
		humanoid.Sit = false
		task.defer(function()
			seatInstance:Sit(humanoid)
		end)
		task.delay(0.15, function()
			if players:GetPlayerByUserId(player.UserId) == nil then
				return
			end
			TryForceSeat(tryIndex + 1)
		end)
	end

	TryForceSeat(1)
end

local function TeleportAllPlayersToArena(participantPlayers: { Player })
	local arenaCenter, arenaSize = ArenaManager.GetArenaFloorInfo()
	LogInfo(string.format("TeleportAllPlayersToArena: Current Arena Center=%s HalfSize=%.1f", tostring(arenaCenter), arenaSize.X / 2))

	local spawnPositionList = GetArenaSpawnPositionList()
	LogInfo(string.format("Found %d spawn points after scaling", #spawnPositionList))

	-- Shuffle the predefined spawn points to ensure variety
	for i = #spawnPositionList, 2, -1 do
		local j = math.random(1, i)
		spawnPositionList[i], spawnPositionList[j] = spawnPositionList[j], spawnPositionList[i]
	end

	local chosenPositions: { Vector3 } = {}
	LogInfo(string.format("TeleportAllPlayersToArena playerCount=%d spawnPointCount=%d", #participantPlayers, #spawnPositionList))
	for index, player in ipairs(participantPlayers) do
		local initialTarget = spawnPositionList[index]
		local targetPosition: Vector3? = nil

		if initialTarget then
			-- Ensure predefined point doesn't conflict with already chosen ones
			local conflict = false
			for _, otherPos in chosenPositions do
				local dist = (otherPos * Vector3.new(1, 0, 1) - initialTarget * Vector3.new(1, 0, 1)).Magnitude
				if dist < GameConfig.MinSpawnSeparation then
					conflict = true
					break
				end
			end
			if not conflict then
				targetPosition = initialTarget
			else
				LogInfo(string.format("TeleportAllPlayersToArena: Predefined point index %d conflicts, falling back to random", index))
			end
		end

		if targetPosition == nil then
			targetPosition = GetRandomArenaPosition(chosenPositions)
		end

		table.insert(chosenPositions, targetPosition)
		arenaTargetPositionMap[player.UserId] = targetPosition
		SeatPlayerOnVehicle(player, targetPosition)
	end
end

local function StabilizeArenaPlayers()
	for _, player in players:GetPlayers() do
		local targetPosition = arenaTargetPositionMap[player.UserId]
		if targetPosition ~= nil then
			SeatPlayerOnVehicle(player, targetPosition)
		end
	end
end

local function TeleportPlayerToLobby(player: Player, reloadCharacter: boolean?)
	local targetPosition: Vector3? = nil

	-- Try fixed spawn points first
	local spawnPointsFolder = workspace:FindFirstChild(LOBBY_SPAWN_POINTS_FOLDER_NAME)
	if spawnPointsFolder then
		local points = {}
		for _, child in spawnPointsFolder:GetChildren() do
			if child:IsA("BasePart") and string.find(child.Name, "Spawn_") then
				table.insert(points, child)
			end
		end

		if #points > 0 then
			local chosenPart = points[math.random(1, #points)]
			targetPosition = chosenPart.Position + Vector3.new(0, 4, 0)
			LogInfo(string.format("Using fixed lobby spawn point: %s", chosenPart.Name))
		end
	end

	-- Fallback to random area if no fixed points found
	if targetPosition == nil then
		local lobbySpawnPart = workspace:FindFirstChild(LOBBY_SPAWN_NAME)
		if lobbySpawnPart == nil or not lobbySpawnPart:IsA("BasePart") then
			LogInfo("Skip TeleportPlayerToLobby reason=LobbySpawnArea_missing")
			return
		end

		local size = lobbySpawnPart.Size
		local randomX = (math.random() - 0.5) * size.X * 0.8
		local randomZ = (math.random() - 0.5) * size.Z * 0.8
		targetPosition = lobbySpawnPart.Position + Vector3.new(randomX, 4, randomZ)
		LogInfo("Using random lobby spawn area")
	end

	if reloadCharacter == true then
		player.CharacterAdded:Once(function()
			if player.Parent ~= players then
				return
			end
			TeleportPlayerToPosition(player, targetPosition)
		end)

		local success, err = pcall(function()
			player:LoadCharacterAsync()
		end)
		if not success then
			LogInfo(string.format("LoadCharacterAsync failed for userId=%d: %s", player.UserId, tostring(err)))
		end
		return
	end
	TeleportPlayerToPosition(player, targetPosition)
end

local function TeleportAllPlayersToLobby()
	CombatManager.DestroyAllUnits()
	for _, player in players:GetPlayers() do
		task.spawn(function()
			arenaTargetPositionMap[player.UserId] = nil
			TeleportPlayerToLobby(player, true)
		end)
	end
end

local function BroadcastMatchState(matchState: GameConfig.MatchState, countdown: number)
	currentMatchState = matchState
	CombatManager.SetMatchState(matchState)
	LogInfo(string.format("StateChanged state=%s countdown=%d", matchState, countdown))
	NetMsg.FireNotifyMatchState(matchState, countdown)
end

local function RunMatchLoop()
	LogInfo("RunMatchLoop started")
	while true do
		-- 每局开始前，重置停止请求，应用并同步参数配置
		isStopRequested = false
		ConfigManager.ApplyAndSync()

		local nonAfkPlayerCount = PlayerStateManager.GetNonAfkOnlinePlayerCount()
		if nonAfkPlayerCount < GameConfig.MinPlayerToStart then
			LogInfo(string.format("WaitingPlayers current=%d required=%d", nonAfkPlayerCount, GameConfig.MinPlayerToStart))
			CombatManager.SetAllVehiclesAnchored(true)
			BroadcastMatchState("InLobby", 0)
			task.wait(1)
			continue
		end

		LogInfo(string.format("MatchCountdown start seconds=%d", GameConfig.MatchCountdown))
		CombatManager.SetAllVehiclesAnchored(true)
		local matchAborted = false
		for countdown = GameConfig.MatchCountdown, 1, -1 do
			if PlayerStateManager.GetNonAfkOnlinePlayerCount() < GameConfig.MinPlayerToStart then
				LogInfo("MatchCountdown aborted: player count below minimum")
				matchAborted = true
				break
			end
			BroadcastMatchState("MatchCountdown", countdown)
			task.wait(1)
		end
		if matchAborted then
			continue
		end

		local roundParticipantPlayers = GetNonAfkPlayers()
		if #roundParticipantPlayers < GameConfig.MinPlayerToStart then
			LogInfo("Match start aborted: non-afk player count below minimum")
			BroadcastMatchState("InLobby", 0)
			task.wait(1)
			continue
		end
		LogInfo(string.format("ArenaSeatPrepare participants=%d", #roundParticipantPlayers))
		NetMsg.FireNotifyArenaSeatPrepare(roundParticipantPlayers)
		ArenaManager.PrepareArena(#roundParticipantPlayers)

		if roundStartCallback ~= nil then
			LogInfo("Invoke roundStartCallback (Early)")
			local participantIds = {}
			for _, p in ipairs(roundParticipantPlayers) do
				table.insert(participantIds, p.UserId)
			end
			roundStartCallback(participantIds)
		end

		task.wait(GameConfig.ArenaSeatPrepareDelay)
		TeleportAllPlayersToArena(roundParticipantPlayers)
		-- 入场后只稳定一次，避免每秒 Stabilize 反复 Sit / 挪车导致角色反复「落地」
		task.wait(0.35)
		StabilizeArenaPlayers()
		-- 入座失败等路径可能未解锚；开局倒计时前统一解锚，避免整局 BaseDisk 仍 Anchored
		CombatManager.SetAllVehiclesAnchored(false)

		LogInfo(string.format("GameStartCountdown start seconds=%d", GameConfig.RoundStartCountdown))
		local gameStartAborted = false
		for countdown = GameConfig.RoundStartCountdown, 1, -1 do
			if #GetNonAfkPlayers() <= 1 then
				LogInfo("GameStartCountdown aborted: not enough players")
				gameStartAborted = true
				break
			end
			BroadcastMatchState("GameStartCountdown", countdown)
			task.wait(1)
		end

		if gameStartAborted then
			LogInfo("GameStart aborted, returning players to lobby")
			BroadcastMatchState("InLobby", 0)
			for _, player in players:GetPlayers() do
				CombatManager.UnseatPlayerFromOwnedVehicle(player)
			end
			task.wait(GameConfig.ReturnToLobbyWait)
			TeleportAllPlayersToLobby()
			continue
		end

		BroadcastMatchState("Fighting", 0)
		ArenaManager.StartShrinking(GameConfig.RoundFightDuration)
		LogInfo(string.format("FightPhase start seconds=%d", GameConfig.RoundFightDuration))
		-- 与 MatchCountdown / GameStartCountdown 一致：先广播再 wait，避免首秒无数字、客户端慢约 1s
		local fightEndedEarly = false
		for remain = GameConfig.RoundFightDuration, 1, -1 do
			if isStopRequested then
				fightEndedEarly = true
				LogInfo("Fighting phase ended early: stop requested via command.")
				break
			end
			if PlayerStateManager.GetAlivePlayerCount() <= 1 then
				fightEndedEarly = true
				LogInfo("Fighting phase ended early: at most one player remains alive.")
				break
			end
			BroadcastMatchState("Fighting", remain)
			task.wait(1)
		end

		local endReason: GameConfig.RoundEndReason = if fightEndedEarly then "LastStanding" else "TimeExpired"
		local aliveUserIds: { number } = PlayerStateManager.GetAliveUserIdList()
		NetMsg.FireNotifyRoundOutcome(endReason, aliveUserIds)

		-- 统计胜利
		for _, winnerId in ipairs(aliveUserIds) do
			local winner = players:GetPlayerByUserId(winnerId)
			if winner then
				LeaderboardManager.AddStat(winner, GameConfig.LeaderboardCategory.WeeklyWins, 1)
			end
		end

		-- 新增结算阶段：优胜者留在场内展示 2 秒
		BroadcastMatchState("Settlement", GameConfig.SettlementDuration)
		task.wait(GameConfig.SettlementDuration)

		ArenaManager.ResetArena()
		LogInfo("FightPhase ended returning players to lobby")
		BroadcastMatchState("InLobby", 0)
		for _, player in players:GetPlayers() do
			CombatManager.UnseatPlayerFromOwnedVehicle(player)
		end
		task.wait(GameConfig.ReturnToLobbyWait)
		TeleportAllPlayersToLobby()
	end
end

function MatchManager.Init(onRoundStart: OnRoundStartCallback)
	roundStartCallback = onRoundStart
	ArenaManager.Init()
	NetMsg.ConnectRequestSetAfkState(OnRequestSetAfkState)
	NetMsg.ConnectRequestSyncAfkState(OnRequestSyncAfkState)
	if roundWorkerThread ~= nil then
		LogInfo("Init skipped reason=already_initialized")
		return
	end
	LogInfo("Init success")
	roundWorkerThread = task.spawn(RunMatchLoop)
end

function MatchManager.GetCurrentMatchState(): GameConfig.MatchState
	return currentMatchState
end

function MatchManager.OnPlayerAdded(player: Player)
	task.spawn(function()
		LogInfo(string.format("OnPlayerAdded userId=%d state=%s", player.UserId, currentMatchState))
		PlayerStateManager.EnsurePlayerRoundInfo(player)
		PlayerStateManager.SetPlayerAfk(player.UserId, false)
		NetMsg.FireNotifyAfkState(player.UserId, false)
		-- 无论当前处于什么阶段，新加入的玩家都先传送到大厅
		TeleportPlayerToLobby(player)
	end)
end

function MatchManager.OnPlayerDead(player: Player, isDisconnect: boolean?, hitDirection: Vector3?)
	LogInfo(string.format("OnPlayerDead userId=%d isDisconnect=%s", player.UserId, tostring(isDisconnect == true)))
	arenaTargetPositionMap[player.UserId] = nil
	if isDisconnect == true then
		LogInfo(string.format("OnPlayerDead skip teleport userId=%d reason=disconnect", player.UserId))
		return
	end
	CombatManager.UnseatPlayerFromOwnedVehicle(player)

	-- 确保人物留在原地，不随载具消失
	local character = player.Character
	if character ~= nil then
		if character.PrimaryPart ~= nil then
			local deathPos = character.PrimaryPart.Position
			character:PivotTo(CFrame.new(deathPos))
		end

		CombatManager.DestroyUnitForPlayer(player.UserId)

		-- 死亡表现：人物肢体受力爆开并逐渐淡出
		--character:BreakJoints() -- 显式断开关节，确保肢体能分离
		local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
		if humanoid then
			humanoid.Health = 0
		end

		local explosionPower = 60
		local upwardPower = 40
		local spreadPower = 50

		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				-- 保持 CanCollide = true 以便人物能落在地上（解体），但关闭 Touch 和 Query 以免干扰战斗
				part.CanTouch = false
				part.CanQuery = false

				-- 应用爆炸冲量
				local randomSpread = Vector3.new((math.random() - 0.5) * spreadPower, math.random() * upwardPower, (math.random() - 0.5) * spreadPower)
				local hitImpulse = if hitDirection and hitDirection.Magnitude > 0 then hitDirection.Unit * explosionPower else Vector3.zero
				part.AssemblyLinearVelocity = hitImpulse + randomSpread

				-- 确保服务器拥有物理所有权，以便力能正确应用并同步给所有人
				if not part.Anchored then
					pcall(function()
						part:SetNetworkOwner(nil)
					end)
				end
			end
		end

		task.spawn(function()
			local fadeDuration = 2.0
			local steps = 20
			for i = 1, steps do
				task.wait(fadeDuration / steps)
				if player.Parent ~= players or player.Character ~= character then
					break
				end
				local transparency = i / steps
				for _, part in character:GetDescendants() do
					if part:IsA("BasePart") then
						if part.Name ~= "HumanoidRootPart" then
							part.Transparency = transparency
						end
					elseif part:IsA("Decal") then
						part.Transparency = transparency
					end
				end
			end
			-- 退场表现结束后再回大厅重置
			TeleportPlayerToLobby(player, true)
		end)
	else
		TeleportPlayerToLobby(player, true)
	end
end

function MatchManager.OnPlayerRemoving(player: Player)
	LogInfo(string.format("OnPlayerRemoving userId=%d", player.UserId))
	arenaTargetPositionMap[player.UserId] = nil
	seatRetryCountMap[player.UserId] = nil
end

function MatchManager.ForceResetToLobby()
	LogInfo("ForceResetToLobby invoked")
	BroadcastMatchState("InLobby", 0)
	TeleportAllPlayersToLobby()
end

-- 请求强制结束当前场次
function MatchManager.RequestStopMatch()
	if currentMatchState == "Fighting" then
		isStopRequested = true
		LogInfo("RequestStopMatch registered")
	else
		warn(string.format("%s RequestStopMatch ignored, current state is %s", LOG_PREFIX, currentMatchState))
	end
end

return MatchManager
