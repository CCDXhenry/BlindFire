--!strict
local VehicleManager = {}

local serverStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local CombatManager = require(serverScripts:FindFirstChild("CombatManager"))
local PlayerStateManager = require(serverScripts:FindFirstChild("PlayerStateManager"))

local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local LOG_PREFIX = "[VehicleManager]"

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
end

local function CanAffordVehicle(playerInfo: GameConfig.PlayerInfo, vehicleData: GameConfig.VehicleData): boolean
	local coinKey = tostring(GameConfig.CurrencyType.Coin)
	local currentCoins = playerInfo.currencies[coinKey] or 0
	local coinCost = vehicleData.costCoin

	-- 服务端仅处理金币购买请求（Rb 通过 MarketplaceService 走 ProcessReceipt）
	if vehicleData.costType == GameConfig.CostType.Coin or vehicleData.costType == GameConfig.CostType.CoinOrRb then
		return currentCoins >= coinCost
	end
	return false
end

local function SpendVehicleCost(player: Player, vehicleData: GameConfig.VehicleData)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local coinKey = tostring(GameConfig.CurrencyType.Coin)
	local currentCoins = playerInfo.currencies[coinKey] or 0
	local coinCost = vehicleData.costCoin

	if
		(vehicleData.costType == GameConfig.CostType.Coin or vehicleData.costType == GameConfig.CostType.CoinOrRb)
		and currentCoins >= coinCost
	then
		ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, -coinCost, GameConfig.ItemCountChangeReason.SpendOnUpgrade)
	end
end

-- 处理客户端购买载具请求
function VehicleManager.OnRequestBuyVehicle(player: Player, vehicleId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local vehicleData = GameConfig.VehicleDataMap[vehicleId]
	if vehicleData == nil then
		warn(string.format("%s Vehicle data not found for id: %d", LOG_PREFIX, vehicleId))
		return
	end

	local vehicleIdStr = tostring(vehicleId)
	if playerInfo.vehicleInventory.ownedList[vehicleIdStr] then
		LogInfo(string.format("BuyRejected userId=%d reason=already_owned vehicleId=%d", player.UserId, vehicleId))
		return
	end

	if CanAffordVehicle(playerInfo, vehicleData) then
		LogInfo(string.format("BuyAccepted userId=%d vehicleId=%d coinCost=%d costType=%d", player.UserId, vehicleId, vehicleData.costCoin, vehicleData.costType))
		SpendVehicleCost(player, vehicleData)
		-- 添加载具
		ServerGameInfo.AddPlayerVehicle(player, vehicleIdStr)
		-- 自动装备
		VehicleManager.OnRequestUpdateVehicleUsing(player, vehicleId)
	else
		local rejectReason = "insufficient_currency"
		if vehicleData.costType == GameConfig.CostType.Rb then
			rejectReason = "rb_purchase_only"
		elseif vehicleData.costType == GameConfig.CostType.GroupReward then
			rejectReason = "group_reward_only"
		end
		LogInfo(string.format("BuyRejected userId=%d reason=%s vehicleId=%d", player.UserId, rejectReason, vehicleId))
	end
end

-- 处理客户端更换载具请求
function VehicleManager.OnRequestUpdateVehicleUsing(player: Player, vehicleId: number)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local vehicleIdStr = tostring(vehicleId)
	if not playerInfo.vehicleInventory.ownedList[vehicleIdStr] then
		warn(string.format("%s EquipRejected userId=%d reason=not_owned vehicleId=%d", LOG_PREFIX, player.UserId, vehicleId))
		return
	end

	LogInfo(string.format("EquipAccepted userId=%d vehicleId=%d", player.UserId, vehicleId))
	ServerGameInfo.SetPlayerCurrentVehicle(player, vehicleIdStr)

	local roundInfoMap = PlayerStateManager.GetAllPlayerRoundInfoMap()
	local roundInfo = roundInfoMap[player.UserId]
	local isRoundLocked = roundInfo ~= nil and roundInfo.isParticipant == true
	if isRoundLocked then
		LogInfo(string.format("EquipDeferred userId=%d vehicleId=%d reason=round_locked", player.UserId, vehicleId))
		return
	end

	-- 检查是否未入座（人物没坐到载具上前都能切换并即时刷新）
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local isSeated = if humanoid then (humanoid.Sit and humanoid.SeatPart ~= nil) else false

	if not isSeated then
		CombatManager.DestroyUnitForPlayer(player.UserId)
		CombatManager.OnPlayerAdded(player)
	end
end

-- 处理客户端领取群组奖励请求
function VehicleManager.OnRequestClaimGroupReward(player: Player, isInGroup: boolean)
	if not isInGroup then
		return
	end

	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	if playerInfo.hasClaimedGroupReward then
		-- 已经领取过
		return
	end

	-- 如果玩家尚未领取过群组奖励，则更新状态并补发奖励
	if not playerInfo.hasClaimedGroupReward then
		local groupRewardVehicleIdList = GameConfig.GetGroupRewardVehicleIdList()
		if #groupRewardVehicleIdList == 0 then
			warn(string.format("%s Group reward vehicle list is empty", LOG_PREFIX))
			return
		end

		playerInfo.hasClaimedGroupReward = true
		for _, rewardVehicleId in ipairs(groupRewardVehicleIdList) do
			ServerGameInfo.AddPlayerVehicle(player, tostring(rewardVehicleId))
		end
		NetMsg.FireNotifyPlayerClaimedGroupReward(player)
		LogInfo(string.format("RewardClaimed userId=%d", player.UserId))
	end
end

function VehicleManager.Init()
	NetMsg.ConnectRequestBuyVehicle(VehicleManager.OnRequestBuyVehicle)
	NetMsg.ConnectRequestUpdateVehicleUsing(VehicleManager.OnRequestUpdateVehicleUsing)
	NetMsg.ConnectRequestClaimGroupReward(VehicleManager.OnRequestClaimGroupReward)
	LogInfo("Init success")
end

return VehicleManager
