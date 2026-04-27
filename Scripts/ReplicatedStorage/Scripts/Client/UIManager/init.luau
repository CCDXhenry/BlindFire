--!strict
local UIManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UserInutExtension = require(coreClientScripts:FindFirstChild("UserInutExtension"))
local uiOriginsFolder: Folder = replicatedStorage:FindFirstChild("UI") :: Folder
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")
local BillboardManager = require(clientScripts:WaitForChild("BillboardManager"))
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local PlayerInfoUIManager = require(script:WaitForChild("PlayerInfoUIManager"))
local ConfigUIManager = require(script:WaitForChild("ConfigUIManager"))
local KillFeedManager = require(script:WaitForChild("KillFeedManager"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local tweenService: TweenService = game:GetService("TweenService")

local ModalTransparency = 0.3
local ButtonHoveredScale: number = 1.1 --按钮鼠标移入放大
local ButtonPressedScale: number = 0.9 --按钮按下缩小
local ButtonInteractionTweenInfo: TweenInfo = TweenInfo.new(0.1) --按钮交互动画缓动信息

UIManager.WindowId = {
	VehiclesShop = "VehiclesShop",
}

type WindowConfig = {
	FrameName: string,
	scriptName: string,
	isModal: boolean,
}
local WindowConfigs: { [string]: WindowConfig } = {
	[UIManager.WindowId.VehiclesShop] = {
		FrameName = "VehiclesShopFrame",
		scriptName = "VehiclesShopFrame",
		isModal = true,
	},
}

local addedWindows: { [string]: Frame } = {}
local gameScreenGui: ScreenGui?
local modalButton: ImageButton

local function CheckModalButtonVisible()
	local topModalWindow: Frame?
	for windowId: string, window: Frame in addedWindows do
		if WindowConfigs[windowId].isModal and (topModalWindow == nil or window.ZIndex > topModalWindow.ZIndex) then
			topModalWindow = window
		end
	end
	if topModalWindow == nil then
		modalButton.Visible = false
	else
		modalButton.Visible = true
		modalButton.ZIndex = topModalWindow.ZIndex - 1
	end
end

--给按钮加点击和悬停缩放效果
local function ApplyButtonEffects(button: GuiButton)
	--如果按钮不需要交互效果
	if not button:GetAttribute("HasInteractionEffect") then
		return
	end
	--确保按钮有UIScale
	local uiScale: UIScale? = button:FindFirstChildOfClass("UIScale") :: UIScale?
	if uiScale == nil then
		return
	end
	local normalScale: number = uiScale.Scale
	local hoveredScale: number = ButtonHoveredScale * normalScale
	local pressedScale: number = ButtonPressedScale * normalScale
	local mouseEnterTween: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = hoveredScale })
	local mouseLeaveTween: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = normalScale })
	local clickTween1: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = pressedScale })
	local clickTween2: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = normalScale })
	clickTween1.Completed:Connect(function(playbackState: Enum.PlaybackState)
		clickTween2:Play()
	end)
	button.MouseEnter:Connect(function()
		if not button.Active then
			return
		end
		local inputTypeString: string?, _: Enum.UserInputType = UserInutExtension.GetInputType()
		if inputTypeString == UserInutExtension.InputTypeString.Keyboard_Mouse then
			mouseEnterTween:Play()
		end
	end)
	button.MouseLeave:Connect(function()
		local inputTypeString: string?, _: Enum.UserInputType = UserInutExtension.GetInputType()
		if inputTypeString == UserInutExtension.InputTypeString.Keyboard_Mouse then
			mouseLeaveTween:Play()
		end
	end)
	button.Activated:Connect(function(inputObject: InputObject, clickCount: number)
		clickTween1:Play()
	end)
end

--初始化
function UIManager.Init(gameScreenGuiNew: ScreenGui)
	gameScreenGui = gameScreenGuiNew
	if gameScreenGui == nil then
		return
	end
	--模态按钮
	modalButton = Instance.new("ImageButton")
	modalButton.Name = "ModalButton"
	modalButton.Modal = true
	modalButton.BackgroundColor3 = Color3.new(0, 0, 0)
	modalButton.BackgroundTransparency = ModalTransparency
	modalButton.AutoButtonColor = false
	modalButton.Size = UDim2.fromScale(1, 1)
	modalButton.Parent = gameScreenGui
	modalButton.Visible = false
	--按钮交互效果
	local uiParents: { Instance } = { workspace, gameScreenGui }
	for uiParentIndex: number, uiParent: Instance in uiParents do
		uiParent.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("GuiButton") then
				ApplyButtonEffects(descendant)
			end
		end)
		for descendantIndex: number, descendant: Instance in uiParent:GetDescendants() do
			if descendant:IsA("GuiButton") then
				ApplyButtonEffects(descendant)
			end
		end
	end
	--玩家血条管理
	PlayerInfoUIManager.Init()
	--参数配置 UI 管理
	if game.GameId ~= GameConfig.GameId then
		ConfigUIManager.Init()
	end
	--角落击败显示栏 UI 管理
	KillFeedManager.Init(gameScreenGui)
end

--非窗口方式创建界面
function UIManager.CreateFrame(frameName: string, scriptName: string?, frameParent: GuiBase2d?, ZIndex: number?): Frame
	local frame: Frame = (uiOriginsFolder:FindFirstChild(frameName) :: Frame):Clone()
	if scriptName ~= nil then
		local frameScrip: LocalScript = script:FindFirstChild(scriptName):Clone()
		frameScrip.Parent = frame
	end
	if frameParent == nil then
		frame.Parent = gameScreenGui
	else
		frame.Parent = frameParent
	end
	if ZIndex ~= nil then
		frame.ZIndex = ZIndex
	end
	return frame
end

--打开窗口
function UIManager.OpenWindow(windowId: string)
	if gameScreenGui == nil then
		return
	end
	local window: Frame? = addedWindows[windowId]
	if window == nil then
		local windowConfig: WindowConfig = WindowConfigs[windowId]
		window = (uiOriginsFolder:FindFirstChild(windowConfig.FrameName) :: Frame):Clone()
		if window == nil then
			return
		end
		window.Parent = gameScreenGui
		window:SetAttribute("WindowId", windowId)
		local windowScript: LocalScript = script:FindFirstChild(windowConfig.scriptName):Clone()
		windowScript.Parent = window
		addedWindows[windowId] = window
		local addedWindowCount: number = 0
		for windowId: string, window: Frame in addedWindows do
			addedWindowCount += 1
		end
		window.ZIndex = 100 + addedWindowCount * 2
		CheckModalButtonVisible()
	end
end

--窗口是否展示中
function UIManager.IsWindowShowing(windowId: string): boolean
	local window: Frame? = addedWindows[windowId]
	return window ~= nil
end

--关闭窗口
function UIManager.CloseWindow(windowId: string)
	local window = addedWindows[windowId]
	if window then
		ClientMsg.FireCloseWindow(windowId)
		addedWindows[windowId] = nil
		CheckModalButtonVisible()
	end
end

--关闭所有窗口
function UIManager.CloseAllWindow()
	for windowId: string, window: Frame in pairs(addedWindows) do
		ClientMsg.FireCloseWindow(windowId)
	end
	table.clear(addedWindows)
	CheckModalButtonVisible()
end

return UIManager
