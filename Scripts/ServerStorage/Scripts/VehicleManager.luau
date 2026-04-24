--!strict
local VehicleManager = {}

local serverStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local CombatManager = require(serverScripts:FindFirstChild("CombatManager"))
local MatchManager = require(serverScripts:FindFirstChild("MatchManager"))

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
	local rbKey = tostring(GameConfig.CurrencyType.Rb)
	local currentCoins = playerInfo.currencies[coinKey] or 0
	local currentRb = playerInfo.currencies[rbKey] or 0
	local coinCost = vehicleData.cost
	local rbCost = vehicleData.costRb or vehicleData.cost

	if vehicleData.costType == GameConfig.CostType.Coin then
		return currentCoins >= coinCost
	elseif vehicleData.costType == GameConfig.CostType.Rb then
		return currentRb >= coinCost
	elseif vehicleData.costType == GameConfig.CostType.CoinOrRb then
		return currentCoins >= coinCost or currentRb >= rbCost
	end

	return false
end

local function SpendVehicleCost(player: Player, vehicleData: GameConfig.VehicleData)
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return
	end

	local coinKey = tostring(GameConfig.CurrencyType.Coin)
	local rbKey = tostring(GameConfig.CurrencyType.Rb)
	local currentCoins = playerInfo.currencies[coinKey] or 0
	local currentRb = playerInfo.currencies[rbKey] or 0
	local rbCost = vehicleData.costRb or vehicleData.cost

	if vehicleData.costType == GameConfig.CostType.Coin then
		ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, -vehicleData.cost, GameConfig.ItemCountChangeReason.SpendOnUpgrade)
	elseif vehicleData.costType == GameConfig.CostType.Rb then
		ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Rb, -vehicleData.cost, GameConfig.ItemCountChangeReason.SpendOnUpgrade)
	elseif vehicleData.costType == GameConfig.CostType.CoinOrRb then
		if currentCoins >= vehicleData.cost then
			ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Coin, -vehicleData.cost, GameConfig.ItemCountChangeReason.SpendOnUpgrade)
		elseif currentRb >= rbCost then
			ServerGameInfo.UpdatePlayerCurrency(player, GameConfig.CurrencyType.Rb, -rbCost, GameConfig.ItemCountChangeReason.SpendOnUpgrade)
		end
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
		LogInfo(string.format("BuyAccepted userId=%d vehicleId=%d coinCost=%d rbCost=%d costType=%d", player.UserId, vehicleId, vehicleData.cost, vehicleData.costRb or 0, vehicleData.costType))
		SpendVehicleCost(player, vehicleData)
		-- 添加载具
		ServerGameInfo.AddPlayerVehicle(player, vehicleIdStr)
		-- 自动装备
		VehicleManager.OnRequestUpdateVehicleUsing(player, vehicleId)
	else
		LogInfo(string.format("BuyRejected userId=%d reason=insufficient_currency vehicleId=%d", player.UserId, vehicleId))
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

	-- 检查是否未入座（人物没坐到载具上前都能切换并即时刷新）
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local isSeated = if humanoid then (humanoid.Sit and humanoid.SeatPart ~= nil) else false

	if not isSeated then
		CombatManager.DestroyUnitForPlayer(player.UserId)
		CombatManager.OnPlayerAdded(player)
	end
end

function VehicleManager.Init()
	NetMsg.ConnectRequestBuyVehicle(VehicleManager.OnRequestBuyVehicle)
	NetMsg.ConnectRequestUpdateVehicleUsing(VehicleManager.OnRequestUpdateVehicleUsing)
	LogInfo("Init success")
end

return VehicleManager
