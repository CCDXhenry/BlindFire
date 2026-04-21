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
		currencies = localPlayerSaveInfo.currencies,
		currentGuideType = GameConfig.GuideType.None,
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

--更新货币数量
function ClientGameInfo.UpdateCurrency(currencyType: number, totalAmount: number, lastChange: number, reason: number)
	if localPlayerInfo == nil then
		return
	end

	local currencyKey: string = tostring(currencyType)
	localPlayerInfo.currencies[currencyKey] = totalAmount

	--如果是增加且金额大于0，弹出获得提示
	if lastChange > 0 then
		local rewardInfo: GameConfig.RewardInfo = {
			rewardType = GameConfig.RewardType.Currency,
			rewardId = currencyType,
			rewardCount = lastChange,
			rewardSource = reason,
		}
		ClientMsg.FireShowAddRewardsTip({ rewardInfo })
	end

	--通知界面刷新
	ClientMsg.FireLocalPlayerCurrencyUpdate()
end

function ClientGameInfo.GetCurrentGuideType(): number
	if localPlayerInfo == nil then
		return GameConfig.GuideType.None
	end
	return localPlayerInfo.currentGuideType
end

function ClientGameInfo.SetCurrentGuideType(guideType: number)
	if localPlayerInfo == nil then
		return
	end
	if localPlayerInfo.currentGuideType == guideType then
		return
	end
	localPlayerInfo.currentGuideType = guideType
	ClientMsg.FireCurrentGuideTypeChanged()
end

return ClientGameInfo