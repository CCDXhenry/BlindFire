--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local players: Players = game:GetService("Players")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local VehicleManager = require(serverScripts:FindFirstChild("VehicleManager"))

local function OnPromptGamePassPurchaseFinished(player: Instance, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased then
		return
	end
	if not player:IsA("Player") then
		return
	end
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.ownedGamePassMap[gamePassId] then
		return
	end
	ServerGameInfo.SetPlayerGamePassAcquired(player, gamePassId)
	AnalyticsTool.AddPassPurchaseEvent(player, gamePassId, GameConfig.GamePassPrice[gamePassId])
end

--处理购买商品收据
local function ProcessReceipt(receiptInfo: GameConfig.ReceiptInfo): Enum.ProductPurchaseDecision
	local player: Player? = players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 查找产品对应的载具
	local vehicleId: number? = nil
	local vehicleDataFound: GameConfig.VehicleData? = nil
	for id, data in pairs(GameConfig.VehicleDataMap) do
		if data.productId == receiptInfo.ProductId then
			vehicleId = id
			vehicleDataFound = data
			break
		end
	end

	if vehicleId and vehicleDataFound then
		local vehicleIdStr = tostring(vehicleId)
		if not playerInfo.vehicleInventory.ownedList[vehicleIdStr] then
			ServerGameInfo.AddPlayerVehicle(player, vehicleIdStr)
			AnalyticsTool.AddPassPurchaseEvent(player, vehicleId, vehicleDataFound.costRb or vehicleDataFound.costCoin) -- 借用 Pass 事件记录，或者根据项目规范增加 Product 事件
			print(string.format("[MarketplaceManager] Vehicle purchased: userId=%d vehicleId=%d", player.UserId, vehicleId))
			
			-- 自动装备
			VehicleManager.OnRequestUpdateVehicleUsing(player, vehicleId)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

marketplaceService.PromptGamePassPurchaseFinished:Connect(OnPromptGamePassPurchaseFinished)
marketplaceService.ProcessReceipt = ProcessReceipt