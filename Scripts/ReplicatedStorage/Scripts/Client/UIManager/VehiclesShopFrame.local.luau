--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local scriptsFolder = replicatedStorage:FindFirstChild("Scripts")
local sharedScripts = scriptsFolder:FindFirstChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local clientScripts = scriptsFolder:FindFirstChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local core = replicatedStorage:FindFirstChild("Core")
local coreScripts = core:FindFirstChild("Scripts")
local coreClientScripts = coreScripts:FindFirstChild("Client")
local sharedScripts2 = coreScripts:FindFirstChild("Shared")
local NumberExtension = require(sharedScripts2:FindFirstChild("NumberExtension"))
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

if players.LocalPlayer == nil then
	return
end

local thisFrame: Frame = script.Parent
local closeButton: ImageButton = thisFrame:FindFirstChild("CloseButton") :: ImageButton
local vehiclesFrames: ScrollingFrame = thisFrame:FindFirstChild("VehiclesFrame") :: ScrollingFrame
local vehiclesBtnPre: ImageButton = vehiclesFrames:FindFirstChild("VehiclesBtn") :: ImageButton
local vehiclesUIGridLayout: UIGridLayout = vehiclesFrames:FindFirstChild("UIGridLayout") :: UIGridLayout

local vehicleIdLookAt: number
local selectImg: ImageLabel

local firstOpenFrame: boolean = true

local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
if localPlayerInfo == nil then
	return
end

local function IsVehicleAffordable(vehicleData: GameConfig.VehicleData): boolean
	local coinCount = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
	local rbCount = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Rb)] or 0
	local rbCost = vehicleData.costRb or vehicleData.costCoin

	if vehicleData.costType == GameConfig.CostType.Coin then
		return coinCount >= vehicleData.costCoin
	elseif vehicleData.costType == GameConfig.CostType.Rb then
		return rbCount >= rbCost
	elseif vehicleData.costType == GameConfig.CostType.CoinOrRb then
		return coinCount >= vehicleData.costCoin or rbCount >= rbCost
	elseif vehicleData.costType == GameConfig.CostType.GroupReward then
		return localPlayerInfo.isInGroup and not localPlayerInfo.hasClaimedGroupReward
	end

	return false
end

local function PlayBuyBtnIntroAnim(buyBtn: ImageButton)
	-- 防止重复播放
	if buyBtn:GetAttribute("IntroPlayed") then
		return
	end
	buyBtn:SetAttribute("IntroPlayed", true)
	local scale: UIScale = buyBtn:FindFirstChildOfClass("UIScale") :: UIScale

	local tween1 = tweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Scale = 1.1 })
	tween1:Play()
end

local function RefreshInfoFrame()
	if vehicleIdLookAt == nil then
		return
	end
	local vehicleData = GameConfig.VehicleDataMap[vehicleIdLookAt]
	if not vehicleData then
		return
	end

	local infoFrame: Frame = thisFrame:FindFirstChild("InfoFrame") :: Frame
	local vehiclesName: TextLabel = infoFrame:FindFirstChild("VehiclesName") :: TextLabel
	vehiclesName.Text = vehicleData.labelName_t
	local icon: ImageLabel = infoFrame:FindFirstChild("Icon") :: ImageLabel
	icon.Image = vehicleData.iconImage
	local speedValue: TextLabel = infoFrame:FindFirstChild("SpeedValue") :: TextLabel
	if speedValue then
		speedValue.Text = tostring(vehicleData.moveSpeed)
	end

	--刷新购买按钮
	local buyBtn: ImageButton = infoFrame:FindFirstChild("BuyBtn") :: ImageButton
	local buyBtn31: ImageButton = infoFrame:FindFirstChild("BuyBtn3-1") :: ImageButton
	local buyBtn32: ImageButton = infoFrame:FindFirstChild("BuyBtn3-2") :: ImageButton
	local groupRewardText: TextLabel = infoFrame:FindFirstChild("GroupRewardText") :: TextLabel
	local groupRewardBtn: ImageButton = infoFrame:FindFirstChild("GroupRewardBtn") :: ImageButton
	local equipBtn: ImageButton = infoFrame:FindFirstChild("EquipBtn") :: ImageButton
	local equip: ImageLabel = equipBtn:FindFirstChild("Equip") :: ImageLabel
	local equipped: ImageLabel = equipBtn:FindFirstChild("Equipped") :: ImageLabel

	local isOwned = localPlayerInfo.vehicleInventory.ownedList[tostring(vehicleIdLookAt)]

	if not isOwned then
		if vehicleData.costType == GameConfig.CostType.GroupReward then
			buyBtn.Visible = false
			buyBtn31.Visible = false
			buyBtn32.Visible = false
			groupRewardText.Visible = true
			groupRewardBtn.Visible = true
		elseif vehicleData.costType == GameConfig.CostType.CoinOrRb then
			buyBtn.Visible = false
			buyBtn31.Visible = true
			buyBtn32.Visible = true
			groupRewardText.Visible = false
			groupRewardBtn.Visible = false

			local priceText31: TextLabel = buyBtn31:FindFirstChild("Price") :: TextLabel
			local priceText32: TextLabel = buyBtn32:FindFirstChild("Price") :: TextLabel
			priceText31.Text = NumberExtension.FormatBigNumberAA(vehicleData.costCoin)
			priceText32.Text = NumberExtension.FormatBigNumberAA(vehicleData.costRb or vehicleData.costCoin)

			PlayBuyBtnIntroAnim(buyBtn31)
			PlayBuyBtnIntroAnim(buyBtn32)
		else
			buyBtn.Visible = true
			buyBtn31.Visible = false
			buyBtn32.Visible = false
			groupRewardText.Visible = false
			groupRewardBtn.Visible = false

			local rb: ImageLabel = buyBtn:FindFirstChild("Rb") :: ImageLabel
			local coin: ImageLabel = buyBtn:FindFirstChild("Coin") :: ImageLabel
			local priceText: TextLabel = buyBtn:FindFirstChild("Price") :: TextLabel

			rb.Visible = (vehicleData.costType == GameConfig.CostType.Rb)
			coin.Visible = (vehicleData.costType == GameConfig.CostType.Coin)
			if vehicleData.costType == GameConfig.CostType.Coin then
				coin.Image = GameConfig.CoinIconImage
				priceText.Text = NumberExtension.FormatBigNumberAA(vehicleData.costCoin)
			else
				coin.Image = GameConfig.RbIconImage
				priceText.Text = NumberExtension.FormatBigNumberAA(vehicleData.costRb or 0)
			end

			PlayBuyBtnIntroAnim(buyBtn)
		end
	else
		buyBtn.Visible = false
		buyBtn31.Visible = false
		buyBtn32.Visible = false
		groupRewardText.Visible = false
		groupRewardBtn.Visible = false
		buyBtn:SetAttribute("IntroPlayed", false)
		if buyBtn31 then buyBtn31:SetAttribute("IntroPlayed", false) end
		if buyBtn32 then buyBtn32:SetAttribute("IntroPlayed", false) end

		-- 重置缩放
		local function ResetScale(btn: ImageButton)
			local s = btn:FindFirstChildOfClass("UIScale")
			if s then s.Scale = 1 end
		end
		ResetScale(buyBtn)
		if buyBtn31 then ResetScale(buyBtn31) end
		if buyBtn32 then ResetScale(buyBtn32) end
	end

	-- 刷新生命值与冷却时间显示
	local healthValue: TextLabel = infoFrame:FindFirstChild("HealthValue") :: TextLabel
	local fireCooldownValue: TextLabel = infoFrame:FindFirstChild("FireCooldownValue") :: TextLabel
	if healthValue then
		healthValue.Text = tostring(vehicleData.maxHits)
	end
	if fireCooldownValue then
		fireCooldownValue.Text = string.format("%.1fs", vehicleData.fireCooldown)
	end

	--刷新装备按钮
	local tip: TextLabel = infoFrame:FindFirstChild("Tip") :: TextLabel
	tip.Visible = false
	if not isOwned then
		equipBtn.Visible = false
		equipBtn.Active = false
	elseif localPlayerInfo.vehicleInventory.currentId == tostring(vehicleIdLookAt) then
		--已装备
		equipBtn.Visible = true
		equipBtn.Active = false
		equip.Visible = false
		equipped.Visible = true
	else
		equipBtn.Visible = true
		equipBtn.Active = true
		equip.Visible = true
		equipped.Visible = false
	end
end

--请求更改车
local function ChangeVehicle()
	if vehicleIdLookAt == nil then
		return
	end
	if localPlayerInfo.vehicleInventory.currentId == tostring(vehicleIdLookAt) then
		return
	end
	NetMsg.FireRequestUpdateVehicleUsing(vehicleIdLookAt)
end

--更新选择框
local function RefreshSelectImage(vehicleId: number, vehicleBtn: ImageButton)
	if vehicleIdLookAt == vehicleId then
		if selectImg then
			selectImg.Visible = false
		end
		selectImg = vehicleBtn:FindFirstChild("SelectImg") :: ImageLabel
		if selectImg then
			selectImg.Visible = true
		end
	end
end

--生成选择车按钮
local function CreateSelectVehicleBtn(vehicleId: number, vehicleData: GameConfig.VehicleData)
	local vehicleBtn = vehiclesBtnPre:Clone()
	vehicleBtn.Parent = vehiclesFrames
	vehicleBtn.Visible = true
	local usingVehicleId = localPlayerInfo.vehicleInventory.currentId
	local equipImg: ImageLabel = vehicleBtn:FindFirstChild("EquipImg") :: ImageLabel

	--刷新背景/装备标志
	if usingVehicleId ~= tostring(vehicleId) then
		equipImg.Visible = false
	else
		equipImg.Visible = true
	end

	--刷新锁定标签
	local lockImg: ImageLabel = vehicleBtn:FindFirstChild("LockImg") :: ImageLabel
	local isOwned = localPlayerInfo.vehicleInventory.ownedList[tostring(vehicleId)]

	if not isOwned then
		lockImg.Visible = true
	else
		lockImg.Visible = false
	end

	local name: TextLabel = vehicleBtn:FindFirstChild("Name") :: TextLabel
	name.Text = vehicleData.labelName_t
	local icon: ImageLabel = vehicleBtn:FindFirstChild("Icon") :: ImageLabel
	icon.Image = vehicleData.iconImage
	local costFrame: Frame = vehicleBtn:FindFirstChild("CostFrame") :: Frame
	if costFrame then
		local coin: ImageLabel = costFrame:FindFirstChild("Coin") :: ImageLabel
		local rb: ImageLabel = costFrame:FindFirstChild("Rb") :: ImageLabel
		local price: TextLabel = costFrame:FindFirstChild("Price") :: TextLabel
		local groupReward: TextLabel = costFrame:FindFirstChild("GroupReward") :: TextLabel

		costFrame.Visible = not isOwned
		if not isOwned then
			coin.Visible = false
			rb.Visible = false
			price.Visible = false
			groupReward.Visible = false

			if vehicleData.costType == GameConfig.CostType.Coin then
				coin.Visible = true
				price.Visible = true
				price.Text = NumberExtension.FormatBigNumberAA(vehicleData.costCoin)
			elseif vehicleData.costType == GameConfig.CostType.Rb then
				rb.Visible = true
				price.Visible = true
				price.Text = NumberExtension.FormatBigNumberAA(vehicleData.costRb or 0)
			elseif vehicleData.costType == GameConfig.CostType.GroupReward then
				groupReward.Visible = true
			else
				coin.Visible = true
				price.Visible = true
				price.Text = NumberExtension.FormatBigNumberAA(vehicleData.costCoin)
			end
		end
	end

	vehicleBtn.Activated:Connect(function()
		vehicleIdLookAt = vehicleId
		RefreshInfoFrame()
		RefreshSelectImage(vehicleId, vehicleBtn)
	end)

	--更新选择框
	RefreshSelectImage(vehicleId, vehicleBtn)

	return vehicleBtn
end

--刷新选择按钮
local function RefreshSelectFrame()
	for _, child in vehiclesFrames:GetChildren() do
		if child:IsA("ImageButton") then
			child:Destroy()
		end
	end

	local sortedVehicles = {} :: { { vehicleId: number, vehicleData: GameConfig.VehicleData } }
	for vehicleId, vehicleData in pairs(GameConfig.VehicleDataMap) do
		table.insert(sortedVehicles, {
			vehicleId = vehicleId,
			vehicleData = vehicleData,
		})
	end
	table.sort(sortedVehicles, function(a, b)
		if a.vehicleData.sortId ~= b.vehicleData.sortId then
			return a.vehicleData.sortId < b.vehicleData.sortId
		end
		return a.vehicleId < b.vehicleId
	end)

	local vehicleCount: number = 0
	local selectedBtn: ImageButton = nil
	local usingVehicleId = localPlayerInfo.vehicleInventory.currentId

	for _, sortedVehicle in ipairs(sortedVehicles) do
		local vehicleId = sortedVehicle.vehicleId
		local vehicleData = sortedVehicle.vehicleData
		-- Robux车辆且未拥有则不显示（根据原逻辑）
		-- if vehicleData.costType == 2 and not localPlayerInfo.vehicleInventory.ownedList[tostring(vehicleData.id)] then
		-- 	continue
		-- end

		local btn: ImageButton = CreateSelectVehicleBtn(vehicleId, vehicleData)
		vehicleCount += 1
		--找到当前使用中的车
		if tostring(vehicleId) == usingVehicleId then
			selectedBtn = btn
		end
	end

	--手动更新滑动框尺寸以适配各种屏幕
	vehiclesFrames.CanvasSize =
		UDim2.new(0, 0, 0, math.ceil(vehicleCount / 3) * (vehiclesUIGridLayout.CellSize.Y.Offset + vehiclesUIGridLayout.CellPadding.Y.Offset))

	--自动滚动到当前车按钮
	if selectedBtn then
		if firstOpenFrame then
			firstOpenFrame = false
			task.wait() -- 等 UI 排列完成

			-- 计算按钮相对 ScrollFrame 的真实 local Y
			local localY: number = selectedBtn.AbsolutePosition.Y - vehiclesFrames.AbsolutePosition.Y + vehiclesFrames.CanvasPosition.Y - 200

			-- 防止滚动超出内容
			local maxY = vehiclesFrames.CanvasSize.Y.Offset - vehiclesFrames.AbsoluteWindowSize.Y
			local targetY = math.clamp(localY, 0, math.max(maxY, 0))

			-- Tween 滚到正确位置
			local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = tweenService:Create(vehiclesFrames, tweenInfo, { CanvasPosition = Vector2.new(0, targetY) })
			tween:Play()
		end
	end
end

local function RefreshFrame()
	RefreshSelectFrame()
	RefreshInfoFrame()
end

local function InitFrame()
	local infoFrame: Frame = thisFrame:FindFirstChild("InfoFrame") :: Frame
	local buyBtn: ImageButton = infoFrame:FindFirstChild("BuyBtn") :: ImageButton
	local buyBtn31: ImageButton = infoFrame:FindFirstChild("BuyBtn3-1") :: ImageButton
	local buyBtn32: ImageButton = infoFrame:FindFirstChild("BuyBtn3-2") :: ImageButton
	local groupRewardBtn: ImageButton = infoFrame:FindFirstChild("GroupRewardBtn") :: ImageButton
	local equipBtn: ImageButton = infoFrame:FindFirstChild("EquipBtn") :: ImageButton

	--请求改变当前车辆
	equipBtn.Activated:Connect(function()
		ChangeVehicle()
	end)

	local function OnBuyBtnActivated(currencyType: number)
		if vehicleIdLookAt == nil then
			return
		end
		local vehicleData = GameConfig.VehicleDataMap[vehicleIdLookAt]
		if not vehicleData then
			return
		end

		if currencyType == GameConfig.CurrencyType.Coin then
			if localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] >= vehicleData.costCoin then
				NetMsg.FireRequestBuyVehicle(vehicleIdLookAt)
			else
				ClientMsg.FireShowGameTip(GameTexts.InsufficientCoin.source, GameConfig.GameTipTweenType.FlyUp)
			end
		elseif currencyType == GameConfig.CurrencyType.Rb then
			if vehicleData.productId and vehicleData.productId > 0 then
				marketplaceService:PromptProductPurchase(players.LocalPlayer, vehicleData.productId)
			else
				warn("No productId for vehicle", vehicleIdLookAt)
			end
		end
	end

	local function OnGroupRewardBtnActivated()
		if vehicleIdLookAt == nil then
			return
		end
		local vehicleData = GameConfig.VehicleDataMap[vehicleIdLookAt]
		if not vehicleData or vehicleData.costType ~= GameConfig.CostType.GroupReward then
			return
		end

		task.spawn(function()
			local success, isInGroup = pcall(function()
				return players.LocalPlayer:IsInGroupAsync(GameConfig.SixcubeGroupId)
			end)
			local canClaim = success and isInGroup
			NetMsg.FireRequestClaimGroupReward(canClaim)
			if not canClaim then
				ClientMsg.FireShowGameTip(GameTexts.GroupRewardJoinHint.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.GroupRewardJoinHint.key)
			end
		end)
	end

	buyBtn.Activated:Connect(function()
		if vehicleIdLookAt == nil then
			return
		end
		local vehicleData = GameConfig.VehicleDataMap[vehicleIdLookAt]
		if not vehicleData then
			return
		end
		if vehicleData.costType == GameConfig.CostType.Coin then
			OnBuyBtnActivated(GameConfig.CurrencyType.Coin)
		elseif vehicleData.costType == GameConfig.CostType.Rb then
			OnBuyBtnActivated(GameConfig.CurrencyType.Rb)
		end
	end)

	if buyBtn31 then
		buyBtn31.Activated:Connect(function()
			OnBuyBtnActivated(GameConfig.CurrencyType.Coin)
		end)
	end

	if buyBtn32 then
		buyBtn32.Activated:Connect(function()
			OnBuyBtnActivated(GameConfig.CurrencyType.Rb)
		end)
	end

	if groupRewardBtn then
		groupRewardBtn.Activated:Connect(OnGroupRewardBtnActivated)
	end

	vehiclesBtnPre.Visible = false
	vehiclesBtnPre.Parent = nil

	-- 自动跳转到能够购买的车辆（比自己最强车强且是能够购买中id最小的）
	local maxOwnedId = 0
	for idStr, owned in pairs(localPlayerInfo.vehicleInventory.ownedList) do
		if owned then
			local id = tonumber(idStr)
			if id and id > maxOwnedId then
				maxOwnedId = id
			end
		end
	end

	local coinAmount = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
	local bestAffordableId: number? = nil

	for id, vehicleData in pairs(GameConfig.VehicleDataMap) do
		if id > maxOwnedId then
			-- 检查金币是否足够
			if (vehicleData.costType == GameConfig.CostType.Coin or vehicleData.costType == GameConfig.CostType.CoinOrRb) and coinAmount >= vehicleData.costCoin then
				if bestAffordableId == nil or id < bestAffordableId then
					bestAffordableId = id
				end
			end
		end
	end

	vehicleIdLookAt = bestAffordableId or (tonumber(localPlayerInfo.vehicleInventory.currentId) or 1)
	RefreshFrame()
end

local function OnCloseWindow(windowId: string)
	if windowId == thisFrame:GetAttribute("WindowId") then
		UIAdapter.RemoveAdaptiveFrame(thisFrame)
		thisFrame:Destroy()
	end
end

local function OnCloseButtonActivated(inputObject: InputObject, clickCount: number)
	UIManager.CloseWindow(UIManager.WindowId.VehiclesShop)
end

local function OnPurchaseFinished(userId, productId, isPurchased)
	if userId ~= players.LocalPlayer.UserId then
		return
	end
end

UIAdapter.AddAdaptiveFrame(thisFrame, UIAdapter.AdaptiveType.Center)
ClientMsg.ConnectCloseWindow(OnCloseWindow)
closeButton.Activated:Connect(OnCloseButtonActivated)
ClientMsg.ConnectLocalPlayerVehicleInventoryUpdate(RefreshFrame)
InitFrame()
marketplaceService.PromptProductPurchaseFinished:Connect(OnPurchaseFinished)
