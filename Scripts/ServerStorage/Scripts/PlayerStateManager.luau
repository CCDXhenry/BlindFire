--!strict
local PlayerStateManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

export type PlayerRoundInfo = {
	userId: number,
	isAlive: boolean,
	isParticipant: boolean,
	isAfk: boolean,
	clientCharacterReady: boolean,
	clientInitReady: boolean,
	clientReadyTimestamp: number?,
	hitCount: number,
	roundDealtHitCount: number,
	roundKillCount: number,
	roundCoinEarned: number,
	lastFireTime: number,
}

local DEFAULT_LAST_FIRE_TIME = -math.huge

local playerRoundInfoMap: {[number]: PlayerRoundInfo} = {}

local function CreateDefaultPlayerRoundInfoByUserId(userId: number): PlayerRoundInfo
	return {
		userId = userId,
		isAlive = true,
		isParticipant = false,
		isAfk = false,
		clientCharacterReady = false,
		clientInitReady = false,
		clientReadyTimestamp = nil,
		hitCount = 0,
		roundDealtHitCount = 0,
		roundKillCount = 0,
		roundCoinEarned = 0,
		lastFireTime = DEFAULT_LAST_FIRE_TIME,
	}
end

local function CreateDefaultPlayerRoundInfo(player: Player): PlayerRoundInfo
	return CreateDefaultPlayerRoundInfoByUserId(player.UserId)
end

function PlayerStateManager.Init()
	playerRoundInfoMap = {}
end

function PlayerStateManager.EnsurePlayerRoundInfoByUserId(userId: number): PlayerRoundInfo
	local playerRoundInfo = playerRoundInfoMap[userId]
	if playerRoundInfo == nil then
		playerRoundInfo = CreateDefaultPlayerRoundInfoByUserId(userId)
		playerRoundInfoMap[userId] = playerRoundInfo
	end
	return playerRoundInfo
end

function PlayerStateManager.EnsurePlayerRoundInfo(player: Player): PlayerRoundInfo
	return PlayerStateManager.EnsurePlayerRoundInfoByUserId(player.UserId)
end

function PlayerStateManager.RemovePlayerRoundInfo(playerId: number)
	playerRoundInfoMap[playerId] = nil
end

function PlayerStateManager.ResetAllPlayerRoundInfo(participantIds: { number }?)
	local idMap = {}
	if participantIds then
		for _, id in participantIds do
			idMap[id] = true
		end
	end

	for playerId, playerRoundInfo in playerRoundInfoMap do
		local isParticipant = if participantIds then (idMap[playerId] == true) else true
		playerRoundInfo.isParticipant = isParticipant
		playerRoundInfo.isAlive = isParticipant
		playerRoundInfo.hitCount = 0
		playerRoundInfo.roundDealtHitCount = 0
		playerRoundInfo.roundKillCount = 0
		playerRoundInfo.roundCoinEarned = 0
		playerRoundInfo.lastFireTime = DEFAULT_LAST_FIRE_TIME
	end
end

function PlayerStateManager.SetLastFireTime(playerId: number, fireTime: number)
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return
	end
	playerRoundInfo.lastFireTime = fireTime
end

function PlayerStateManager.SetPlayerAfk(playerId: number, isAfk: boolean)
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return
	end
	playerRoundInfo.isAfk = isAfk
end

function PlayerStateManager.IsPlayerAfk(playerId: number): boolean
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return false
	end
	return playerRoundInfo.isAfk == true
end

function PlayerStateManager.SetClientReadyState(playerId: number, clientCharacterReady: boolean, clientInitReady: boolean)
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return
	end
	playerRoundInfo.clientCharacterReady = clientCharacterReady == true
	playerRoundInfo.clientInitReady = clientInitReady == true
	if playerRoundInfo.clientCharacterReady and playerRoundInfo.clientInitReady then
		if playerRoundInfo.clientReadyTimestamp == nil then
			playerRoundInfo.clientReadyTimestamp = os.clock()
		end
	else
		playerRoundInfo.clientReadyTimestamp = nil
	end
end

function PlayerStateManager.GetClientReadyState(playerId: number): (boolean, boolean, number?)
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return false, false, nil
	end
	return playerRoundInfo.clientCharacterReady, playerRoundInfo.clientInitReady, playerRoundInfo.clientReadyTimestamp
end

function PlayerStateManager.GetNonAfkOnlinePlayerCount(): number
	local count = 0
	for _, player in players:GetPlayers() do
		local userId = player.UserId
		local playerRoundInfo = playerRoundInfoMap[userId]
		-- 初始化尚未写入 playerRoundInfoMap 时，按在线真人计入，避免分服测试卡在 InLobby
		if playerRoundInfo == nil or playerRoundInfo.isAfk ~= true then
			count += 1
		end
	end
	return count
end

function PlayerStateManager.CanFire(playerId: number, nowTime: number, cooldown: number?): boolean
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return false
	end
	if not playerRoundInfo.isAlive then
		return false
	end
	local cd = cooldown or GameConfig.FireCooldown
	return nowTime - playerRoundInfo.lastFireTime >= cd
end

function PlayerStateManager.AddPlayerHit(playerId: number, maxHits: number?): (number, boolean)
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return 0, false
	end
	playerRoundInfo.hitCount += 1
	local limit = maxHits or GameConfig.MaxHits
	if playerRoundInfo.hitCount >= limit then
		playerRoundInfo.isAlive = false
		return playerRoundInfo.hitCount, true
	end
	return playerRoundInfo.hitCount, false
end

function PlayerStateManager.GetPlayerHitCount(playerId: number): number
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return 0
	end
	return playerRoundInfo.hitCount
end

function PlayerStateManager.AddRoundDealtHit(playerId: number)
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return
	end
	playerRoundInfo.roundDealtHitCount += 1
end

function PlayerStateManager.AddRoundKill(playerId: number)
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return
	end
	playerRoundInfo.roundKillCount += 1
end

function PlayerStateManager.AddRoundCoinEarned(playerId: number, amount: number)
	if amount <= 0 then
		return
	end
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil or not playerRoundInfo.isParticipant then
		return
	end
	playerRoundInfo.roundCoinEarned += amount
end

function PlayerStateManager.GetRoundStats(playerId: number): (number, number, number)
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return 0, 0, 0
	end
	return playerRoundInfo.roundDealtHitCount, playerRoundInfo.roundKillCount, playerRoundInfo.roundCoinEarned
end

function PlayerStateManager.GetAllPlayerRoundInfoMap(): {[number]: PlayerRoundInfo}
	return playerRoundInfoMap
end

function PlayerStateManager.GetAlivePlayerCount(): number
	local aliveCount = 0
	for _, playerRoundInfo in playerRoundInfoMap do
		if playerRoundInfo.isParticipant and playerRoundInfo.isAlive then
			aliveCount += 1
		end
	end
	return aliveCount
end

function PlayerStateManager.GetAliveUserIdList(): { number }
	local list: { number } = {}
	for _, playerRoundInfo in playerRoundInfoMap do
		if playerRoundInfo.isParticipant and playerRoundInfo.isAlive then
			table.insert(list, playerRoundInfo.userId)
		end
	end
	return list
end

return PlayerStateManager
