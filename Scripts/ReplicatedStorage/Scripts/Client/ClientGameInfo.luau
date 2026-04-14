--!strict
local ClientGameInfo = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local localPlayerInfo: GameConfig.ClientLocalPlayerInfo?
local otherPlayerInfoMap: {[number]: GameConfig.ClientOtherPlayerInfo} = {}

--初始化玩家信息
function ClientGameInfo.InitPlayerInfo(localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: {[string]: GameConfig.ClientOtherPlayerSyncInfo}, playerConfigInfo: GameConfig.PlayerConfigInfo)
	--初始化自己的玩家信息
	localPlayerInfo = {
		settingInfo = localPlayerSaveInfo.settingInfo,
		ownedGamePassList = localPlayerSaveInfo.ownedGamePassList,
		ownedGamePassMap = {},
		playerConfigInfo = playerConfigInfo,
	}
	if localPlayerInfo == nil then
		return
	end
	for ownedGamePassIndex: number, ownedGamePassId: number in localPlayerInfo.ownedGamePassList do
		localPlayerInfo.ownedGamePassMap[ownedGamePassId] = true
	end
	--初始化其他玩家的玩家信息
	for otherPlayerIdKey: string, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo in otherPlayerSaveInfoMap do
		local otherPlayerId: number? = tonumber(otherPlayerIdKey)
		if otherPlayerId == nil then
			continue
		end
		local otherPlayerInfo: GameConfig.ClientOtherPlayerInfo = {
			
		}
		otherPlayerInfoMap[otherPlayerId] = otherPlayerInfo
	end
	--发送消息
	ClientMsg.FireLocalPlayerInfoInit()
end

--初始化其他玩家信息
function ClientGameInfo.InitOtherPlayerInfo(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo)
	local otherPlayerInfo: GameConfig.ClientOtherPlayerInfo = {
		
	}
	otherPlayerInfoMap[playerId] = otherPlayerInfo
	ClientMsg.FireOtherPlayerInfoInit(playerId)
end

--获取自己的玩家信息
function ClientGameInfo.GetLocalPlayerInfo(): GameConfig.ClientLocalPlayerInfo?
	return localPlayerInfo
end

--获取其他玩家的玩家信息
function ClientGameInfo.GetOtherPlayerInfo(playerId: number): GameConfig.ClientOtherPlayerInfo?
	if otherPlayerInfoMap == nil then
		return nil
	end
	return otherPlayerInfoMap[playerId]
end

--自己获得了通行证
function ClientGameInfo.SetLocalPlayerGamePassAcquired(gamePassId: number)
	if localPlayerInfo == nil or localPlayerInfo.ownedGamePassMap[gamePassId] then
		return
	end
	table.insert(localPlayerInfo.ownedGamePassList, gamePassId)
	localPlayerInfo.ownedGamePassMap[gamePassId] = true
	ClientMsg.FireLocalPlayerAcquiredGamePass(gamePassId)
end

return ClientGameInfo