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

type OnRoundStartCallback = () -> ()

local MIN_PLAYER_TO_START = GameConfig.MinPlayerToStart
local LOBBY_SPAWN_NAME = "LobbySpawnArea"
local ARENA_SPAWN_FOLDER_NAME = "ArenaSpawnPoints"
local LOG_PREFIX = "[MatchManager]"
local VEHICLE_MODEL_NAME_PREFIX = "Vehicle_"
local MAX_SEAT_RETRY = 30
local SEAT_RETRY_INTERVAL = 0.2
local MAX_FORCE_SIT_RETRY = 20
local RETURN_TO_LOBBY_UNSEAT_WAIT_SEC = 0.1
local ARENA_SEAT_PREPARE_DELAY_SEC = 0.22

local seatRetryCountMap: {[number]: number} = {}
local arenaTargetPositionMap: {[number]: Vector3} = {}

local currentMatchState: GameConfig.MatchState = "InLobby"
local roundWorkerThread: thread? = nil
local roundStartCallback: OnRoundStartCallback? = nil

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
end

local function FormatVector3(vector: Vector3): string
	return string.format("(%.1f, %.1f, %.1f)", vector.X, vector.Y, vector.Z)
end

local function MoveModelKeepRotation(model: Model, targetPosition: Vector3)
	local pivot = model:GetPivot()
	local rotationOnly = pivot - pivot.Position
	model:PivotTo(CFrame.new(targetPosition) * rotationOnly)
end

local function GetArenaSpawnPositionList(): {Vector3}
	local arenaSpawnFolder = workspace:FindFirstChild(ARENA_SPAWN_FOLDER_NAME)
	if arenaSpawnFolder == nil or not arenaSpawnFolder:IsA("Folder") then
		return {}
	end
	local spawnPositionList: {Vector3} = {}
	for _, child in arenaSpawnFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(spawnPositionList, child.Position + Vector3.new(0, 3, 0))
		end
	end
	return spawnPositionList
end

local function GetRandomArenaPosition(): Vector3
	local halfSize = GameConfig.ArenaHalfSize - GameConfig.ArenaSpawnMargin
	local randomX = math.random() * (halfSize * 2) - halfSize
	local randomZ = math.random() * (halfSize * 2) - halfSize
	return Vector3.new(randomX, GameConfig.UnitY + 1, randomZ)
end

local function TeleportPlayerToPosition(player: Player, targetPosition: Vector3)
	local character = player.Character
	if character == nil then
		LogInfo(string.format("Wait teleport userId=%d reason=no_character", player.UserId))
		player.CharacterAdded:Once(function()
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
	local vehicleName = VEHICLE_MODEL_NAME_PREFIX .. tostring(player.UserId)
	local vehicleModel = workspace:FindFirstChild(vehicleName)
	if vehicleModel == nil or not vehicleModel:IsA("Model") then
		local retryCount = (seatRetryCountMap[player.UserId] or 0) + 1
		seatRetryCountMap[player.UserId] = retryCount
		if retryCount <= MAX_SEAT_RETRY then
			task.delay(SEAT_RETRY_INTERVAL, function()
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
		if tryIndex > MAX_FORCE_SIT_RETRY then
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
			TryForceSeat(tryIndex + 1)
		end)
	end

	TryForceSeat(1)
end

local function TeleportAllPlayersToArena(participantPlayers: { Player })
	local spawnPositionList = GetArenaSpawnPositionList()
	LogInfo(string.format("TeleportAllPlayersToArena playerCount=%d spawnPointCount=%d", #participantPlayers, #spawnPositionList))
	for index, player in ipairs(participantPlayers) do
		local targetPosition = spawnPositionList[index]
		if targetPosition == nil then
			targetPosition = GetRandomArenaPosition()
		end
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
	local lobbySpawnPart = workspace:FindFirstChild(LOBBY_SPAWN_NAME)
	if lobbySpawnPart == nil or not lobbySpawnPart:IsA("BasePart") then
		LogInfo("Skip TeleportPlayerToLobby reason=LobbySpawnArea_missing")
		return
	end
	local targetPosition = lobbySpawnPart.Position + Vector3.new(0, 4, 0)
	if reloadCharacter == true then
		player.CharacterAdded:Once(function()
			TeleportPlayerToPosition(player, targetPosition)
		end)
		player:LoadCharacter()
		return
	end
	TeleportPlayerToPosition(player, targetPosition)
end

local function TeleportAllPlayersToLobby()
	for _, player in players:GetPlayers() do
		arenaTargetPositionMap[player.UserId] = nil
		CombatManager.SetVehicleAnchoredForPlayer(player.UserId, true)
		TeleportPlayerToLobby(player, true)
	end
end

local function BroadcastMatchState(matchState: GameConfig.MatchState, countdown: number)
	currentMatchState = matchState
	LogInfo(string.format("StateChanged state=%s countdown=%d", matchState, countdown))
	NetMsg.FireNotifyMatchState(matchState, countdown)
end

local function RunMatchLoop()
	LogInfo("RunMatchLoop started")
	while true do
		local playerCount = #players:GetPlayers()
		if playerCount < MIN_PLAYER_TO_START then
			LogInfo(string.format("WaitingPlayers current=%d required=%d", playerCount, MIN_PLAYER_TO_START))
			CombatManager.SetAllVehiclesAnchored(true)
			BroadcastMatchState("InLobby", 0)
			task.wait(1)
			continue
		end

		LogInfo(string.format("MatchCountdown start seconds=%d", GameConfig.MatchCountdown))
		CombatManager.SetAllVehiclesAnchored(true)
		for countdown = GameConfig.MatchCountdown, 1, -1 do
			BroadcastMatchState("MatchCountdown", countdown)
			task.wait(1)
		end

		local roundParticipantPlayers = players:GetPlayers()
		LogInfo(string.format("ArenaSeatPrepare participants=%d", #roundParticipantPlayers))
		NetMsg.FireNotifyArenaSeatPrepare(roundParticipantPlayers)
		task.wait(ARENA_SEAT_PREPARE_DELAY_SEC)
		TeleportAllPlayersToArena(roundParticipantPlayers)
		-- 入场后只稳定一次，避免每秒 Stabilize 反复 Sit / 挪车导致角色反复「落地」
		task.wait(0.35)
		StabilizeArenaPlayers()
		-- 入座失败等路径可能未解锚；开局倒计时前统一解锚，避免整局 BaseDisk 仍 Anchored
		CombatManager.SetAllVehiclesAnchored(false)
		LogInfo(string.format("GameStartCountdown start seconds=%d", GameConfig.RoundStartCountdown))
		for countdown = GameConfig.RoundStartCountdown, 1, -1 do
			BroadcastMatchState("GameStartCountdown", countdown)
			task.wait(1)
		end

		BroadcastMatchState("Fighting", 0)
		if roundStartCallback ~= nil then
			LogInfo("Invoke roundStartCallback")
			roundStartCallback()
		end
		LogInfo(string.format("FightPhase start seconds=%d", GameConfig.RoundFightDuration))
		-- 与 MatchCountdown / GameStartCountdown 一致：先广播再 wait，避免首秒无数字、客户端慢约 1s
		local fightEndedEarly = false
		for remain = GameConfig.RoundFightDuration, 1, -1 do
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

		LogInfo("FightPhase ended returning players to lobby")
		BroadcastMatchState("InLobby", 0)
		for _, player in players:GetPlayers() do
			CombatManager.UnseatPlayerFromOwnedVehicle(player)
		end
		task.wait(RETURN_TO_LOBBY_UNSEAT_WAIT_SEC)
		TeleportAllPlayersToLobby()
	end
end

function MatchManager.Init(onRoundStart: OnRoundStartCallback)
	roundStartCallback = onRoundStart
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
	LogInfo(string.format("OnPlayerAdded userId=%d state=%s", player.UserId, currentMatchState))
	if currentMatchState == "InLobby" or currentMatchState == "MatchCountdown" then
		TeleportPlayerToLobby(player)
	end
end

function MatchManager.OnPlayerDead(player: Player)
	LogInfo(string.format("OnPlayerDead userId=%d", player.UserId))
	arenaTargetPositionMap[player.UserId] = nil
	CombatManager.UnseatPlayerFromOwnedVehicle(player)
	CombatManager.SetVehicleAnchoredForPlayer(player.UserId, true)
	TeleportPlayerToLobby(player, true)
end

function MatchManager.OnPlayerRemoving(player: Player)
	LogInfo(string.format("OnPlayerRemoving userId=%d", player.UserId))
	arenaTargetPositionMap[player.UserId] = nil
end

function MatchManager.ForceResetToLobby()
	LogInfo("ForceResetToLobby invoked")
	BroadcastMatchState("InLobby", 0)
	TeleportAllPlayersToLobby()
end

return MatchManager
