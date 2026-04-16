--!strict
local PlayerStateManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

export type PlayerRoundInfo = {
	userId: number,
	isAlive: boolean,
	hitCount: number,
	lastFireTime: number,
}

local DEFAULT_LAST_FIRE_TIME = -math.huge

local playerRoundInfoMap: {[number]: PlayerRoundInfo} = {}

local function CreateDefaultPlayerRoundInfo(player: Player): PlayerRoundInfo
	return {
		userId = player.UserId,
		isAlive = true,
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

function PlayerStateManager.ResetAllPlayerRoundInfo()
	for _, playerRoundInfo in playerRoundInfoMap do
		playerRoundInfo.isAlive = true
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

function PlayerStateManager.CanFire(playerId: number, nowTime: number): boolean
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return false
	end
	if not playerRoundInfo.isAlive then
		return false
	end
	return nowTime - playerRoundInfo.lastFireTime >= GameConfig.FireCooldown
end

function PlayerStateManager.AddPlayerHit(playerId: number): (number, boolean)
	local playerRoundInfo = playerRoundInfoMap[playerId]
	if playerRoundInfo == nil then
		return 0, false
	end
	playerRoundInfo.hitCount += 1
	if playerRoundInfo.hitCount >= GameConfig.MaxHits then
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
		if playerRoundInfo.isAlive then
			aliveCount += 1
		end
	end
	return aliveCount
end

function PlayerStateManager.GetAliveUserIdList(): { number }
	local list: { number } = {}
	for _, playerRoundInfo in playerRoundInfoMap do
		if playerRoundInfo.isAlive then
			table.insert(list, playerRoundInfo.userId)
		end
	end
	return list
end

return PlayerStateManager
