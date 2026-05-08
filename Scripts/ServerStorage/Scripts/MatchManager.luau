--!strict
local MatchManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local players = game:GetService("Players")

local scripts = replicatedStorage:WaitForChild("Scripts")
local serverScripts = serverStorage:WaitForChild("Scripts")
local CombatManager = require(serverScripts:WaitForChild("CombatManager"))
local BotLobbyRoamManager = require(serverScripts:WaitForChild("BotLobbyRoamManager"))
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local PlayerStateManager = require(serverScripts:WaitForChild("PlayerStateManager"))
local ConfigManager = require(serverScripts:WaitForChild("ConfigManager"))
local ArenaManager = require(serverScripts:WaitForChild("ArenaManager"))
local LeaderboardManager = require(serverScripts:WaitForChild("LeaderboardManager"))
local ServerGameInfo = require(serverScripts:WaitForChild("ServerGameInfo"))
local AnalyticsTool = require(serverScripts:WaitForChild("AnalyticsTool"))

type OnRoundStartCallback = (participantIds: { number }) -> ()

-- local MIN_PLAYER_TO_START = GameConfig.MinPlayerToStart
local LOBBY_SPAWN_NAME = "LobbySpawnArea"
local LOBBY_SPAWN_POINTS_FOLDER_NAME = "SpawnPoints"
local ARENA_SPAWN_FOLDER_NAME = "ArenaSpawnPoints"
local LOG_PREFIX = "[MatchManager]"
local BOT_DEBUG_LOG = true
local VEHICLE_MODEL_NAME_PREFIX = "Vehicle_"
-- local MAX_SEAT_RETRY = 30
-- local SEAT_RETRY_INTERVAL = 0.2
-- local MAX_FORCE_SIT_RETRY = 20
-- local RETURN_TO_LOBBY_UNSEAT_WAIT_SEC = 0.1
-- local ARENA_SEAT_PREPARE_DELAY_SEC = 0.22

local seatRetryCountMap: { [number]: number } = {}
local arenaTargetPositionMap: { [number]: Vector3 } = {}
local botLobbyTargetPositionMap: { [number]: Vector3? } = {}

local currentMatchState: GameConfig.MatchState = GameConfig.MatchState.InLobby
-- 与 currentMatchState 解耦：避免「等待玩家」循环中重复 Fire InLobby
local lastBroadcastMatchState: GameConfig.MatchState? = nil
local currentPhaseDuration: number = 0
local currentPhaseStartClock: number = 0
local lastLobbySpawnIndex = 0
local roundWorkerThread: thread? = nil
local roundStartCallback: OnRoundStartCallback? = nil
local isStopRequested: boolean = false
local LogBotDebug: (message: string) -> ()

local function _GetNonAfkPlayers(): { Player }
	local result: { Player } = {}
	for _, player in players:GetPlayers() do
		if not PlayerStateManager.IsPlayerAfk(player.UserId) then
			table.insert(result, player)
		end
	end
	return result
end

local function _GetOnlinePlayers(): { Player }
	local result: { Player } = {}
	for _, player in players:GetPlayers() do
		table.insert(result, player)
	end
	return result
end

local function GetRealtimeNonAfkOnlinePlayerCount(): number
	local count = 0
	for _, player in players:GetPlayers() do
		PlayerStateManager.EnsurePlayerRoundInfo(player)
		if not PlayerStateManager.IsPlayerAfk(player.UserId) then
			count += 1
		end
	end
	return count
end

local function GetRealtimeOnlinePlayerCount(): number
	return #players:GetPlayers()
end

local function RefreshBotFillByRealPlayerCount(realPlayerCount: number, onlinePlayerCount: number)
	if not GameConfig.EnableAIBotFill then
		CombatManager.EnsureBotCount(0)
		return
	end
	local requiredBots = 0
	-- 规则1：仅 1 名非 AFK 真人时补 1 个 bot
	if realPlayerCount == 1 then
		requiredBots = 1
	end
	-- 规则2：仅 1 名玩家且该玩家 AFK 时补 2 个 bot，满足开局
	if onlinePlayerCount == 1 and realPlayerCount == 0 then
		requiredBots = 2
	end
	CombatManager.EnsureBotCount(requiredBots)
end

local function CalculateRequiredBotCount(realPlayerCount: number, onlinePlayerCount: number): number
	local requiredBots = 0
	if realPlayerCount == 1 then
		requiredBots = 1
	end
	if onlinePlayerCount == 1 and realPlayerCount == 0 then
		requiredBots = 2
	end
	return requiredBots
end

local function CollectLobbySpawnBaseParts(): { BasePart }
	local result: { BasePart } = {}
	local spawnPointsFolder = workspace:FindFirstChild(LOBBY_SPAWN_POINTS_FOLDER_NAME)
	if spawnPointsFolder then
		for _, child in spawnPointsFolder:GetChildren() do
			if child:IsA("BasePart") and string.find(child.Name, "Spawn_") then
				table.insert(result, child)
			end
		end
	end
	return result
end

-- 补位机器人生成在场地地下，需与真玩家一样挪到大厅 Spawn_ 点附近，否则备战/开局阶段看不见
local function RepositionFillBotsToLobbySpawns()
	if not GameConfig.EnableAIBotFill then
		return
	end
	local botIds = CombatManager.GetBotIds()
	if #botIds == 0 then
		table.clear(botLobbyTargetPositionMap)
		return
	end
	local activeBotIdMap: { [number]: boolean } = {}
	for _, botId in botIds do
		activeBotIdMap[botId] = true
	end
	for existingBotId in botLobbyTargetPositionMap do
		if not activeBotIdMap[existingBotId] then
			botLobbyTargetPositionMap[existingBotId] = nil
		end
	end

	local lobbyParts = CollectLobbySpawnBaseParts()
	if #lobbyParts == 0 then
		return
	end
	for i = #lobbyParts, 2, -1 do
		local j = math.random(1, i)
		lobbyParts[i], lobbyParts[j] = lobbyParts[j], lobbyParts[i]
	end

	local occupiedPositions: { Vector3 } = {}
	for _, player in players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp ~= nil and hrp:IsA("BasePart") then
				table.insert(occupiedPositions, hrp.Position)
			end
		end
	end

	local minSeparation = math.max(2, GameConfig.MinSpawnSeparation * 0.4)
	local function isPositionAvailable(candidate: Vector3): boolean
		for _, occupied in occupiedPositions do
			local dist = (candidate * Vector3.new(1, 0, 1) - occupied * Vector3.new(1, 0, 1)).Magnitude
			if dist < minSeparation then
				return false
			end
		end
		return true
	end

	table.sort(botIds)
	-- 已有 bot 保持原位，避免新增/删减 bot 时把老 bot 也重排
	for _, botId in botIds do
		local existingPosition = botLobbyTargetPositionMap[botId]
		if existingPosition ~= nil then
			table.insert(occupiedPositions, existingPosition)
		end
	end

	for index, botId in ipairs(botIds) do
		local existingPosition = botLobbyTargetPositionMap[botId]
		if existingPosition ~= nil then
			-- bot 可能在被销毁重建后回到地下；若偏离缓存大厅点则拉回缓存位置
			local unitInfo = CombatManager.GetUnitInfoMap()[botId]
			if unitInfo ~= nil then
				local currentPos = unitInfo.rootPart.Position
				local horizontalDelta = (currentPos * Vector3.new(1, 0, 1) - existingPosition * Vector3.new(1, 0, 1)).Magnitude
				local isUnderground = currentPos.Y < (GameConfig.UnitY - 20)
				if isUnderground or horizontalDelta > 2 then
					CombatManager.TeleportBotVehicleToLobbySpawn(botId, existingPosition)
				end
			end
			continue
		end
		local targetPosition: Vector3? = nil
		local fallbackPart = lobbyParts[(index - 1) % #lobbyParts + 1]
		for _, part in lobbyParts do
			local offset = Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
			local candidate = Vector3.new(part.Position.X + offset.X, part.Position.Y + GameConfig.UnitY, part.Position.Z + offset.Z)
			if isPositionAvailable(candidate) then
				targetPosition = candidate
				break
			end
		end
		if targetPosition == nil then
			-- 没有可直接使用的 Spawn_ 点时，围绕 fallback 做多次随机避让，尽量不与真人重叠
			for _ = 1, 8 do
				local offset = Vector3.new((math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 6)
				local candidate = Vector3.new(
					fallbackPart.Position.X + offset.X,
					fallbackPart.Position.Y + GameConfig.UnitY,
					fallbackPart.Position.Z + offset.Z
				)
				if isPositionAvailable(candidate) then
					targetPosition = candidate
					break
				end
			end
			if targetPosition == nil then
				local offset = Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
				targetPosition = Vector3.new(
					fallbackPart.Position.X + offset.X,
					fallbackPart.Position.Y + GameConfig.UnitY,
					fallbackPart.Position.Z + offset.Z
				)
			end
		end
		if targetPosition == nil then
			continue
		end
		local targetPositionNotNil = targetPosition :: Vector3
		CombatManager.TeleportBotVehicleToLobbySpawn(botId, targetPositionNotNil)
		table.insert(occupiedPositions, targetPositionNotNil)
		botLobbyTargetPositionMap[botId] = targetPositionNotNil
	end
end

local function BuildRoundParticipantIds(realPlayers: { Player }): { number }
	local participantIds: { number } = {}
	for _, player in ipairs(realPlayers) do
		table.insert(participantIds, player.UserId)
	end
	for _, botId in CombatManager.GetBotIds() do
		table.insert(participantIds, botId)
	end
	LogBotDebug(string.format("BuildRoundParticipantIds real=%d bot=%d total=%d", #realPlayers, #CombatManager.GetBotIds(), #participantIds))
	return participantIds
end

local function OnRequestSetAfkState(player: Player, isAfk: boolean)
	if currentMatchState == GameConfig.MatchState.GameStartCountdown or currentMatchState == GameConfig.MatchState.Fighting then
		local roundInfo = PlayerStateManager.EnsurePlayerRoundInfo(player)
		if roundInfo.isParticipant and roundInfo.isAlive then
			return
		end
	end
	PlayerStateManager.SetPlayerAfk(player.UserId, isAfk == true)
	NetMsg.FireNotifyAfkState(player.UserId, isAfk == true)
	AnalyticsTool.AddAfkTurnEvent(player, isAfk == true)
end

local function OnRequestSyncAfkState(player: Player)
	for _, otherPlayer in players:GetPlayers() do
		local otherId = otherPlayer.UserId
		NetMsg.FireNotifyAfkStateToPlayer(player, otherId, PlayerStateManager.IsPlayerAfk(otherId))
	end
end

local function OnRequestSyncMatchState(player: Player)
	local remainRaw = currentPhaseDuration - (os.clock() - currentPhaseStartClock)
	local remainSec = math.ceil(math.max(remainRaw, 0))
	NetMsg.FireNotifyMatchStateToPlayer(player, currentMatchState, remainSec)
end

local function LogInfo(message: string)
	--print(string.format("%s %s", LOG_PREFIX, message))
end

function LogBotDebug(message: string)
	if not BOT_DEBUG_LOG then
		return
	end
	print(string.format("%s[BotDebug] %s", LOG_PREFIX, message))
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

	local primaryPart: BasePart? = vehicleModel.PrimaryPart
	if primaryPart ~= nil then
		primaryPart.Anchored = false
		pcall(function()
			primaryPart:SetNetworkOwner(player)
		end)
	end
	MoveModelKeepRotation(vehicleModel, targetPosition)
	if primaryPart ~= nil then
		local rotationOnly = primaryPart.CFrame - primaryPart.Position
		primaryPart.CFrame = CFrame.new(targetPosition) * rotationOnly
		primaryPart.AssemblyLinearVelocity = Vector3.zero
		primaryPart.AssemblyAngularVelocity = Vector3.zero
	end
	if unitInfo ~= nil then
		local proxyPart = unitInfo.rootPart
		local proxyRotation = proxyPart.CFrame - proxyPart.Position
		proxyPart.CFrame = CFrame.new(targetPosition) * proxyRotation
		proxyPart.AssemblyLinearVelocity = Vector3.zero
		proxyPart.AssemblyAngularVelocity = Vector3.zero
		pcall(function()
			proxyPart:SetNetworkOwner(nil)
		end)
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

	local botIds = CombatManager.GetBotIds()
	table.sort(botIds)

	-- Shuffle the predefined spawn points to ensure variety
	for i = #spawnPositionList, 2, -1 do
		local j = math.random(1, i)
		spawnPositionList[i], spawnPositionList[j] = spawnPositionList[j], spawnPositionList[i]
	end

	local chosenPositions: { Vector3 } = {}
	LogInfo(
		string.format(
			"TeleportAllPlayersToArena playerCount=%d botCount=%d spawnPointCount=%d",
			#participantPlayers,
			#botIds,
			#spawnPositionList
		)
	)

	local function assignSpawnForSlot(slotIndex: number): Vector3
		local initialTarget = spawnPositionList[slotIndex]
		local targetPosition: Vector3? = nil
		if initialTarget then
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
				LogInfo(string.format("TeleportAllPlayersToArena: Predefined point index %d conflicts, falling back to random", slotIndex))
			end
		end
		if targetPosition == nil then
			targetPosition = GetRandomArenaPosition(chosenPositions)
		end
		return targetPosition
	end

	for index, player in ipairs(participantPlayers) do
		local targetPosition = assignSpawnForSlot(index)
		table.insert(chosenPositions, targetPosition)
		arenaTargetPositionMap[player.UserId] = targetPosition
		SeatPlayerOnVehicle(player, targetPosition)
	end

	for i, botId in ipairs(botIds) do
		local slotIndex = #participantPlayers + i
		local targetPosition = assignSpawnForSlot(slotIndex)
		table.insert(chosenPositions, targetPosition)
		arenaTargetPositionMap[botId] = targetPosition
		CombatManager.TeleportBotVehicleToArenaPosition(botId, targetPosition)
	end
end

local function StabilizeArenaPlayers()
	for _, player in players:GetPlayers() do
		local targetPosition = arenaTargetPositionMap[player.UserId]
		if targetPosition ~= nil then
			SeatPlayerOnVehicle(player, targetPosition)
		end
	end
	for _, botId in CombatManager.GetBotIds() do
		local targetPosition = arenaTargetPositionMap[botId]
		if targetPosition ~= nil then
			CombatManager.TeleportBotVehicleToArenaPosition(botId, targetPosition)
		end
	end
end

local function TeleportPlayerToLobby(player: Player, reloadCharacter: boolean?, forcedTargetPosition: Vector3?)
	local targetPosition: Vector3? = forcedTargetPosition

	if targetPosition == nil then
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
				-- Use cycling index instead of pure random for better distribution
				lastLobbySpawnIndex = (lastLobbySpawnIndex % #points) + 1
				local chosenPart = points[lastLobbySpawnIndex]
				-- Add a small random offset to prevent perfect overlap even if multiple players spawn on the same point
				local offset = Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
				targetPosition = chosenPart.Position + Vector3.new(0, 4, 0) + offset
				LogInfo(string.format("Using fixed lobby spawn point: %s (cycled index %d)", chosenPart.Name, lastLobbySpawnIndex))
			end
		end
	end

	-- Fallback to random area if no fixed points found and no target position
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
	local staleBotIds = CombatManager.GetBotIds()
	CombatManager.DestroyAllHumanUnits()
	-- 每轮结束回大厅时重置 bot 大厅位置缓存，确保所有 bot 都会重新传送回大厅
	table.clear(botLobbyTargetPositionMap)
	for _, botId in staleBotIds do
		arenaTargetPositionMap[botId] = nil
	end

	local lobbyPoints: { BasePart } = {}
	local spawnPointsFolder = workspace:FindFirstChild(LOBBY_SPAWN_POINTS_FOLDER_NAME)
	if spawnPointsFolder then
		for _, child in spawnPointsFolder:GetChildren() do
			if child:IsA("BasePart") and string.find(child.Name, "Spawn_") then
				table.insert(lobbyPoints, child)
			end
		end
	end

	-- Shuffle lobby points if available for variety
	if #lobbyPoints > 0 then
		for i = #lobbyPoints, 2, -1 do
			local j = math.random(1, i)
			lobbyPoints[i], lobbyPoints[j] = lobbyPoints[j], lobbyPoints[i]
		end
	end

	local playerList = players:GetPlayers()
	local lobbySpawnPart = workspace:FindFirstChild(LOBBY_SPAWN_NAME)
	local roundInfoMap = PlayerStateManager.GetAllPlayerRoundInfoMap()
	local function IsPositionInsideLobbyArea(position: Vector3): boolean
		if lobbySpawnPart == nil or not lobbySpawnPart:IsA("BasePart") then
			return false
		end
		local relative = lobbySpawnPart.CFrame:PointToObjectSpace(position)
		local halfSize = lobbySpawnPart.Size * 0.5
		return math.abs(relative.X) <= halfSize.X and math.abs(relative.Y) <= halfSize.Y + 8 and math.abs(relative.Z) <= halfSize.Z
	end

	local function ShouldSkipLobbyReset(targetPlayer: Player): boolean
		local isAfk = PlayerStateManager.IsPlayerAfk(targetPlayer.UserId)
		local roundInfo = roundInfoMap[targetPlayer.UserId]
		local character = targetPlayer.Character
		if character == nil or character.PrimaryPart == nil then
			return false
		end
		local isInLobbyArea = IsPositionInsideLobbyArea(character.PrimaryPart.Position)
		if isAfk then
			return isInLobbyArea
		end
		if roundInfo == nil or roundInfo.isAlive then
			return false
		end
		return isInLobbyArea
	end

	for i, player in ipairs(playerList) do
		local playerIndex = i
		local targetPlayer = player
		task.spawn(function()
			arenaTargetPositionMap[targetPlayer.UserId] = nil
			if ShouldSkipLobbyReset(targetPlayer) then
				LogBotDebug(string.format("SkipLobbyReset userId=%d afkOrDeadInLobby=true", targetPlayer.UserId))
				return
			end

			local targetPos: Vector3? = nil
			if #lobbyPoints > 0 then
				local point = lobbyPoints[(playerIndex - 1) % #lobbyPoints + 1]
				local offset = Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
				targetPos = point.Position + Vector3.new(0, 4, 0) + offset
			end

			TeleportPlayerToLobby(targetPlayer, true, targetPos)
		end)
	end
end

local function BroadcastMatchState(matchState: GameConfig.MatchState, countdown: number)
	if matchState == GameConfig.MatchState.InLobby and lastBroadcastMatchState == GameConfig.MatchState.InLobby then
		return
	end
	lastBroadcastMatchState = matchState
	currentMatchState = matchState
	currentPhaseDuration = countdown
	currentPhaseStartClock = os.clock()
	CombatManager.SetMatchState(matchState)
	LogInfo(string.format("StateChanged state=%s countdown=%d", matchState, countdown))
	NetMsg.FireNotifyMatchState(matchState, countdown)
end

-- 仅按秒轮询是否应提前结束本阶段，不再次广播 MatchState
local function RunPhaseWithAbortPolling(durationSec: number, shouldAbort: () -> boolean): boolean
	for _ = 1, durationSec do
		if shouldAbort() then
			return true
		end
		task.wait(1)
	end
	return false
end

local function RunMatchLoop()
	LogInfo("RunMatchLoop started")
	while true do
		-- 每局开始前，重置停止请求，应用并同步参数配置
		isStopRequested = false
		ConfigManager.ApplyAndSync()
		local lockedBotCountForRound = 0

		-- InLobby 阶段每秒判断一次补位机器人创建条件与开局条件
		while true do
			local nonAfkPlayerCount = GetRealtimeNonAfkOnlinePlayerCount()
			local onlinePlayerCount = GetRealtimeOnlinePlayerCount()
			RefreshBotFillByRealPlayerCount(nonAfkPlayerCount, onlinePlayerCount)
			RepositionFillBotsToLobbySpawns()
			local participantCount = nonAfkPlayerCount + #CombatManager.GetBotIds()
			LogBotDebug(string.format(
				"InLobbyTick state=%s online=%d real=%d bot=%d participant=%d minStart=%d",
				tostring(currentMatchState),
				onlinePlayerCount,
				nonAfkPlayerCount,
				#CombatManager.GetBotIds(),
				participantCount,
				GameConfig.MinPlayerToStart
			))
			if participantCount >= GameConfig.MinPlayerToStart then
				lockedBotCountForRound = #CombatManager.GetBotIds()
				LogBotDebug("InLobbyTick satisfied start condition, entering MatchCountdown")
				break
			end
			LogInfo(string.format("WaitingPlayers current=%d required=%d", nonAfkPlayerCount, GameConfig.MinPlayerToStart))
			CombatManager.SetAllVehiclesAnchored(true)
			BroadcastMatchState(GameConfig.MatchState.InLobby, 0)
			task.wait(1)
		end

		LogInfo(string.format("MatchCountdown start seconds=%d", GameConfig.MatchCountdown))
		CombatManager.SetAllVehiclesAnchored(true)
		BroadcastMatchState(GameConfig.MatchState.MatchCountdown, GameConfig.MatchCountdown)
		-- MatchCountdown 期间按实时 AFK 状态补位（例如 1 真人切 AFK 时补到 2 bot）
		local matchAborted = RunPhaseWithAbortPolling(GameConfig.MatchCountdown, function(): boolean
			local botCountBeforeRefresh = #CombatManager.GetBotIds()
			local currentOnlineCount = GetRealtimeOnlinePlayerCount()
			local currentNonAfkCount = GetRealtimeNonAfkOnlinePlayerCount()
			local requiredBotCount = CalculateRequiredBotCount(currentNonAfkCount, currentOnlineCount)
			-- MatchCountdown 期间只补位不删位，避免玩家 AFK 状态波动导致已创建 bot 被删除
			if requiredBotCount > botCountBeforeRefresh then
				CombatManager.EnsureBotCount(requiredBotCount)
			end
			local botCountAfterRefresh = #CombatManager.GetBotIds()
			-- 避免 MatchCountdown 每秒随机挪位：仅在 bot 数量发生变化时重排一次大厅位置
			if botCountAfterRefresh ~= botCountBeforeRefresh then
				RepositionFillBotsToLobbySpawns()
			end
			local currentParticipantCount = currentOnlineCount + #CombatManager.GetBotIds()
			LogBotDebug(string.format(
				"MatchCountdownTick online=%d real=%d bot=%d participant=%d minStart=%d",
				currentOnlineCount,
				currentNonAfkCount,
				#CombatManager.GetBotIds(),
				currentParticipantCount,
				GameConfig.MinPlayerToStart
			))
			if currentParticipantCount < GameConfig.MinPlayerToStart then
				LogInfo("MatchCountdown aborted: player count below minimum")
				LogBotDebug("MatchCountdown aborted: participant below min")
				return true
			end
			return false
		end)
		if matchAborted then
			continue
		end

		-- MatchCountdown 结束前只做“补位不删位”的最后校正
		local onlinePlayerCountAtLock = GetRealtimeOnlinePlayerCount()
		local nonAfkPlayerCountAtLock = GetRealtimeNonAfkOnlinePlayerCount()
		local requiredBotCountAtLock = CalculateRequiredBotCount(nonAfkPlayerCountAtLock, onlinePlayerCountAtLock)
		if requiredBotCountAtLock > #CombatManager.GetBotIds() then
			CombatManager.EnsureBotCount(requiredBotCountAtLock)
		end
		lockedBotCountForRound = #CombatManager.GetBotIds()
		-- 本局 bot 数在这里最终锁定；直到对局结束前不再增删
		CombatManager.EnsureBotCount(lockedBotCountForRound)
		RepositionFillBotsToLobbySpawns()
		local roundParticipantPlayers = _GetNonAfkPlayers()
		local participantIds = BuildRoundParticipantIds(roundParticipantPlayers)
		if #participantIds < GameConfig.MinPlayerToStart then
			LogInfo("Match start aborted: non-afk player count below minimum")
			LogBotDebug(string.format("MatchStart aborted participants=%d minStart=%d", #participantIds, GameConfig.MinPlayerToStart))
			BroadcastMatchState(GameConfig.MatchState.InLobby, 0)
			task.wait(1)
			continue
		end
		LogInfo(string.format("ArenaSeatPrepare participants=%d", #roundParticipantPlayers))
		NetMsg.FireNotifyArenaSeatPrepare(roundParticipantPlayers)
		ArenaManager.PrepareArena(#participantIds)

		if roundStartCallback ~= nil then
			LogInfo("Invoke roundStartCallback (Early)")
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
		BroadcastMatchState(GameConfig.MatchState.GameStartCountdown, GameConfig.RoundStartCountdown)
		local gameStartAborted = RunPhaseWithAbortPolling(GameConfig.RoundStartCountdown, function(): boolean
			local currentOnlineCount = GetRealtimeOnlinePlayerCount()
			local participantCount = currentOnlineCount + #CombatManager.GetBotIds()
			LogBotDebug(string.format(
				"GameStartCountdownTick online=%d bot=%d participant=%d",
				currentOnlineCount,
				#CombatManager.GetBotIds(),
				participantCount
			))
			if participantCount <= 1 then
				LogInfo("GameStartCountdown aborted: not enough players")
				LogBotDebug("GameStartCountdown aborted: participant <= 1")
				return true
			end
			return false
		end)

		if gameStartAborted then
			LogInfo("GameStart aborted, returning players to lobby")
			BroadcastMatchState(GameConfig.MatchState.InLobby, 0)
			for _, player in players:GetPlayers() do
				CombatManager.UnseatPlayerFromOwnedVehicle(player)
			end
			task.wait(GameConfig.ReturnToLobbyWait)
			TeleportAllPlayersToLobby()
			continue
		end

		BroadcastMatchState(GameConfig.MatchState.Fighting, GameConfig.RoundFightDuration)
		local roundInfoMap = PlayerStateManager.GetAllPlayerRoundInfoMap()
		for _, participantPlayer in players:GetPlayers() do
			local roundInfo = roundInfoMap[participantPlayer.UserId]
			if roundInfo ~= nil and roundInfo.isParticipant then
				local playerInfo = ServerGameInfo.GetPlayerInfo(participantPlayer)
				if playerInfo ~= nil then
					AnalyticsTool.AddGameStartEvent(participantPlayer, playerInfo.vehicleInventory.currentId)
				end
			end
		end
		ArenaManager.StartShrinking(GameConfig.RoundFightDuration)
		LogInfo(string.format("FightPhase start seconds=%d", GameConfig.RoundFightDuration))
		local fightEndedEarly = RunPhaseWithAbortPolling(GameConfig.RoundFightDuration, function(): boolean
			if isStopRequested then
				LogInfo("Fighting phase ended early: stop requested via command.")
				return true
			end
			if PlayerStateManager.GetAlivePlayerCount() <= 1 then
				LogInfo("Fighting phase ended early: at most one player remains alive.")
				return true
			end
			return false
		end)

		local endReason: GameConfig.RoundEndReason = if fightEndedEarly
			then GameConfig.RoundEndReason.LastStanding
			else GameConfig.RoundEndReason.TimeExpired
		local aliveUserIds: { number } = PlayerStateManager.GetAliveUserIdList()
		NetMsg.FireNotifyRoundOutcome(endReason, aliveUserIds)

		-- 统计胜利
		for _, winnerId in ipairs(aliveUserIds) do
			local winner = players:GetPlayerByUserId(winnerId)
			if winner then
				local playerInfo = ServerGameInfo.GetPlayerInfo(winner)
				local roundHitCount, roundKillCount, roundCoinEarned = PlayerStateManager.GetRoundStats(winnerId)
				if playerInfo ~= nil then
					AnalyticsTool.AddGameWinEvent(
						winner,
						playerInfo.vehicleInventory.currentId,
						roundHitCount,
						roundKillCount,
						roundCoinEarned
					)
				end
				LeaderboardManager.AddStat(winner, GameConfig.LeaderboardCategory.WeeklyWins, 1)
			end
		end

		-- 新增结算阶段：优胜者留在场内展示 2 秒
		BroadcastMatchState(GameConfig.MatchState.Settlement, GameConfig.SettlementDuration)
		task.wait(GameConfig.SettlementDuration)

		ArenaManager.ResetArena()
		LogInfo("FightPhase ended returning players to lobby")
		BroadcastMatchState(GameConfig.MatchState.InLobby, 0)
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
	BotLobbyRoamManager.Init()
	NetMsg.ConnectRequestSetAfkState(OnRequestSetAfkState)
	NetMsg.ConnectRequestSyncAfkState(OnRequestSyncAfkState)
	NetMsg.ConnectRequestSyncMatchState(OnRequestSyncMatchState)
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

		CombatManager.PlayVehicleDeathEffect(player.UserId, hitDirection)

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
			local fadeDuration = 3.0
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
	BroadcastMatchState(GameConfig.MatchState.InLobby, 0)
	TeleportAllPlayersToLobby()
end

-- 请求强制结束当前场次
function MatchManager.RequestStopMatch()
	if currentMatchState == GameConfig.MatchState.Fighting then
		isStopRequested = true
		LogInfo("RequestStopMatch registered")
	else
		warn(string.format("%s RequestStopMatch ignored, current state is %s", LOG_PREFIX, currentMatchState))
	end
end

return MatchManager
