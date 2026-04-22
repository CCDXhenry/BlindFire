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

local function PlayBuyBtnIntroAnim(buyBtn: ImageButton)
	-- 防止重复播放
	if buyBtn:GetAttribute("IntroPlayed") then
		return
	end
	buyBtn:SetAttribute("IntroPlayed", true)
	local scale: UIScale = buyBtn:FindFirstChildOfClass("UIScale") :: UIScale

	local tween1 = tweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Scale = 1.3 })
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

	--刷新购买按钮
	local buyBtn: ImageButton = infoFrame:FindFirstChild("BuyBtn") :: ImageButton
	local equipBtn: ImageButton = infoFrame:FindFirstChild("EquipBtn") :: ImageButton
	local equip: ImageLabel = equipBtn:FindFirstChild("Equip") :: ImageLabel
	local equipped: ImageLabel = equipBtn:FindFirstChild("Equipped") :: ImageLabel
	local rb: ImageLabel = buyBtn:FindFirstChild("Rb") :: ImageLabel
	local coin: ImageLabel = buyBtn:FindFirstChild("Coin") :: ImageLabel
	local priceText: TextLabel = buyBtn:FindFirstChild("Price") :: TextLabel

	local isOwned = localPlayerInfo.vehicleInventory.ownedList[tostring(vehicleIdLookAt)]

	--修改花费类型icon
	if vehicleData.costType == GameConfig.CurrencyType.Coin then
		coin.Image = GameConfig.CoinIconImage
	elseif vehicleData.costType == GameConfig.CurrencyType.Rb then
		coin.Image = GameConfig.RbIconImage
	end

	if not isOwned then
		buyBtn.Visible = true
		PlayBuyBtnIntroAnim(buyBtn)
		rb.Visible = (vehicleData.costType == GameConfig.CurrencyType.Rb)
		coin.Visible = (vehicleData.costType == GameConfig.CurrencyType.Coin)
		priceText.Text = NumberExtension.FormatBigNumberAA(vehicleData.cost)
	else
		buyBtn.Visible = false
		buyBtn:SetAttribute("IntroPlayed", false)
	end

	--刷新装备按钮
	local tip: TextLabel = infoFrame:FindFirstChild("Tip") :: TextLabel
	tip.Visible = false
	if not isOwned then
		equipBtn.Visible = false
	elseif localPlayerInfo.vehicleInventory.currentId == tostring(vehicleIdLookAt) then
		--已装备
		equipBtn.Visible = true
		equip.Visible = false
		equipped.Visible = true
	else
		equipBtn.Visible = true
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

	local sortedVehicles = {}
	for _, data in pairs(GameConfig.VehicleDataMap) do
		table.insert(sortedVehicles, data)
	end
	table.sort(sortedVehicles, function(a, b)
		return a.sortId < b.sortId
	end)

	local vehicleCount: number = 0
	local selectedBtn: ImageButton = nil
	local usingVehicleId = localPlayerInfo.vehicleInventory.currentId

	for _, vehicleData in ipairs(sortedVehicles) do
		-- Robux车辆且未拥有则不显示（根据原逻辑）
		-- if vehicleData.costType == 2 and not localPlayerInfo.vehicleInventory.ownedList[tostring(vehicleData.id)] then
		-- 	continue
		-- end

		local btn: ImageButton = CreateSelectVehicleBtn(vehicleData.id, vehicleData)
		vehicleCount += 1
		--找到当前使用中的车
		if tostring(vehicleData.id) == usingVehicleId then
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
	local equipBtn: ImageButton = infoFrame:FindFirstChild("EquipBtn") :: ImageButton

	--请求改变当前车辆
	equipBtn.Activated:Connect(function()
		ChangeVehicle()
	end)

	buyBtn.Activated:Connect(function()
		if vehicleIdLookAt == nil then
			return
		end
		local vehicleData = GameConfig.VehicleDataMap[vehicleIdLookAt]
		if vehicleData.costType == GameConfig.CurrencyType.Coin then
			local coinCount = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
			if coinCount >= vehicleData.cost then
				NetMsg.FireRequestBuyVehicle(vehicleIdLookAt)
			else
				ClientMsg.FireShowGameTip(GameTexts.InsufficientCoin.source, GameConfig.GameTipTweenType.FlyUp)
			end
		elseif vehicleData.costType == GameConfig.CurrencyType.Rb then
			marketplaceService:PromptProductPurchase(players.LocalPlayer, vehicleData.productId)
		end
	end)

	vehiclesBtnPre.Visible = false
	vehiclesBtnPre.Parent = nil
	vehicleIdLookAt = tonumber(localPlayerInfo.vehicleInventory.currentId) or 1
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
