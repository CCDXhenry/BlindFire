--!strict
local PlayerStateManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

export type PlayerRoundInfo = {
	userId: number,
	isAlive: boolean,
	isParticipant: boolean,
	isAfk: boolean,
	hitCount: number,
	lastFireTime: number,
}

local DEFAULT_LAST_FIRE_TIME = -math.huge

local playerRoundInfoMap: {[number]: PlayerRoundInfo} = {}

local function CreateDefaultPlayerRoundInfo(player: Player): PlayerRoundInfo
	return {
		userId = player.UserId,
		isAlive = true,
		isParticipant = false,
		isAfk = false,
		hitCount = 0,
		lastFireTime = DEFAULT_LAST_FIRE_TIME,
	}
end

function PlayerStateManager.Init()
	playerRoundInfoMap = {}
end

function PlayerStateManager.EnsurePlayerRoundInfo(player: Player): PlayerRoundInfo
	local playerRoundInfo = playerRoundInfoMap[player.UserId]
	if playerRoundInfo == nil then
		playerRoundInfo = CreateDefaultPlayerRoundInfo(player)
		playerRoundInfoMap[player.UserId] = playerRoundInfo
	end
	return playerRoundInfo
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

function PlayerStateManager.GetNonAfkOnlinePlayerCount(): number
	local count = 0
	for _, playerRoundInfo in playerRoundInfoMap do
		if playerRoundInfo.isAfk ~= true then
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
