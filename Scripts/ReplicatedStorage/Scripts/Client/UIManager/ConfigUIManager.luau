--!strict
local ConfigUIManager = {}

local players = game:GetService("Players")
local runService = game:GetService("RunService")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local localPlayer = players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local configGui: ScreenGui?
local mainFrame: Frame?
local scrollingFrame: ScrollingFrame?
local rowTemplate: Frame?
local cooldownDemoFrame: Frame?
local ringRootFrame: Frame?
local centerMaskFrame: Frame?
local cooldownText: TextLabel?
local segmentFrameList: { Frame } = {}
local cooldownLoopConnection: RBXScriptConnection?
local cooldownDurationSeconds: number = 1.5
local cooldownElapsedSeconds: number = 0
local isFireCooldownActive: boolean = false
local completeHighlightRemainingSeconds: number = 0

-- 存储待定配置（下一局生效）
local pendingOverrides: { [string]: any } = {}

local DemoSegmentCount: number = 24
local RingRadiusScale: number = 0.40
local SegmentWidthScale: number = 0.08
local SegmentHeightScale: number = 0.12
local RingColorOn: Color3 = Color3.fromRGB(255, 170, 0)
local RingColorOff: Color3 = Color3.fromRGB(70, 70, 70)
local RingTransparencyOn: number = 0.05
local RingTransparencyOff: number = 0.35
local RingReadyColor: Color3 = Color3.fromRGB(60, 255, 120)
local RingHighlightColor: Color3 = Color3.fromRGB(170, 255, 190)
local RingHighlightDurationSeconds: number = 0.25

local function SetRingToReadyState(useHighlight: boolean)
	local targetColor = if useHighlight then RingHighlightColor else RingReadyColor
	local targetTransparency = if useHighlight then 0 else RingTransparencyOn
	for _, segmentFrame in ipairs(segmentFrameList) do
		segmentFrame.BackgroundColor3 = targetColor
		segmentFrame.BackgroundTransparency = targetTransparency
	end
end

local function SetCooldownProgress(progress: number)
	local clampedProgress = math.clamp(progress, 0, 1)
	local activeCount = math.floor(clampedProgress * DemoSegmentCount + 0.5)

	for index, segmentFrame in ipairs(segmentFrameList) do
		local isActive = index <= activeCount
		segmentFrame.BackgroundColor3 = if isActive then RingColorOn else RingColorOff
		segmentFrame.BackgroundTransparency = if isActive then RingTransparencyOn else RingTransparencyOff
	end

	if cooldownText then
		local remainSeconds = cooldownDurationSeconds * (1 - clampedProgress)
		if isFireCooldownActive then
			cooldownText.Text = string.format("开火冷却\n%.1fs", remainSeconds)
		else
			cooldownText.Text = "可开火\nREADY"
		end
	end
end

local function StartFireCooldown(seconds: number)
	cooldownDurationSeconds = math.max(seconds, 0.1)
	cooldownElapsedSeconds = 0
	isFireCooldownActive = true
	completeHighlightRemainingSeconds = 0
	SetCooldownProgress(0)
end

local function BuildCooldownSegments()
	if not ringRootFrame then
		return
	end

	table.clear(segmentFrameList)
	for index = 1, DemoSegmentCount do
		local angleRad = -((index - 1) / DemoSegmentCount) * math.pi * 2 - (math.pi / 2)
		local segmentFrame = Instance.new("Frame")
		segmentFrame.Name = string.format("SegmentFrame_%02d", index)
		segmentFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		segmentFrame.Size = UDim2.fromScale(SegmentWidthScale, SegmentHeightScale)
		segmentFrame.Position = UDim2.fromScale(0.5 + math.cos(angleRad) * RingRadiusScale, 0.5 + math.sin(angleRad) * RingRadiusScale)
		segmentFrame.Rotation = math.deg(angleRad) + 90
		segmentFrame.BackgroundColor3 = RingColorOn
		segmentFrame.BackgroundTransparency = RingTransparencyOn
		segmentFrame.BorderSizePixel = 0
		segmentFrame.Parent = ringRootFrame

		local segmentCorner = Instance.new("UICorner")
		segmentCorner.CornerRadius = UDim.new(0.5, 0)
		segmentCorner.Parent = segmentFrame
		table.insert(segmentFrameList, segmentFrame)
	end
end

local function CreateCooldownDemoUI()
	if not mainFrame then
		return
	end

	cooldownDemoFrame = Instance.new("Frame")
	cooldownDemoFrame.Name = "CooldownDemoFrame"
	cooldownDemoFrame.Size = UDim2.fromOffset(160, 220)
	cooldownDemoFrame.Position = UDim2.new(1, -180, 0, 70)
	cooldownDemoFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
	cooldownDemoFrame.BackgroundTransparency = 0.1
	cooldownDemoFrame.BorderSizePixel = 0
	cooldownDemoFrame.Parent = mainFrame

	local demoCorner = Instance.new("UICorner")
	demoCorner.CornerRadius = UDim.new(0, 8)
	demoCorner.Parent = cooldownDemoFrame

	local demoTitleText = Instance.new("TextLabel")
	demoTitleText.Name = "DemoTitleText"
	demoTitleText.Size = UDim2.new(1, 0, 0, 24)
	demoTitleText.Position = UDim2.fromOffset(0, 8)
	demoTitleText.BackgroundTransparency = 1
	demoTitleText.Text = "Fire Cooldown Demo"
	demoTitleText.TextColor3 = Color3.fromRGB(255, 255, 255)
	demoTitleText.TextSize = 13
	demoTitleText.Font = Enum.Font.GothamBold
	demoTitleText.Parent = cooldownDemoFrame

	ringRootFrame = Instance.new("Frame")
	ringRootFrame.Name = "RingRootFrame"
	ringRootFrame.Size = UDim2.fromScale(0.84, 0.52)
	ringRootFrame.Position = UDim2.fromScale(0.5, 0.18)
	ringRootFrame.AnchorPoint = Vector2.new(0.5, 0)
	ringRootFrame.BackgroundTransparency = 1
	ringRootFrame.BorderSizePixel = 0
	ringRootFrame.Parent = cooldownDemoFrame

	local ringAspectConstraint = Instance.new("UIAspectRatioConstraint")
	ringAspectConstraint.AspectRatio = 1
	ringAspectConstraint.Parent = ringRootFrame

	centerMaskFrame = Instance.new("Frame")
	centerMaskFrame.Name = "CenterMaskFrame"
	centerMaskFrame.Size = UDim2.fromScale(0.56, 0.56)
	centerMaskFrame.Position = UDim2.fromScale(0.5, 0.5)
	centerMaskFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	centerMaskFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
	centerMaskFrame.BorderSizePixel = 0
	centerMaskFrame.Parent = ringRootFrame

	local centerMaskCorner = Instance.new("UICorner")
	centerMaskCorner.CornerRadius = UDim.new(0.5, 0)
	centerMaskCorner.Parent = centerMaskFrame

	cooldownText = Instance.new("TextLabel")
	cooldownText.Name = "CooldownText"
	cooldownText.Size = UDim2.fromScale(0.8, 0.8)
	cooldownText.Position = UDim2.fromScale(0.5, 0.5)
	cooldownText.AnchorPoint = Vector2.new(0.5, 0.5)
	cooldownText.BackgroundTransparency = 1
	cooldownText.TextColor3 = Color3.fromRGB(230, 230, 230)
	cooldownText.TextSize = 15
	cooldownText.Font = Enum.Font.GothamBold
	cooldownText.Parent = centerMaskFrame

	local helperText = Instance.new("TextLabel")
	helperText.Name = "HelperText"
	helperText.Size = UDim2.new(1, -16, 0, 34)
	helperText.Position = UDim2.new(0, 8, 1, -40)
	helperText.BackgroundTransparency = 1
	helperText.Text = "按 F 触发开火冷却\n12点起点 由暗到亮"
	helperText.TextColor3 = Color3.fromRGB(150, 150, 150)
	helperText.TextSize = 11
	helperText.Font = Enum.Font.Gotham
	helperText.TextWrapped = true
	helperText.Parent = cooldownDemoFrame

	BuildCooldownSegments()
	SetCooldownProgress(1)
end

local function OnInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F4 then
		if configGui then
			configGui.Enabled = not configGui.Enabled
		end
	elseif input.KeyCode == Enum.KeyCode.F then
		StartFireCooldown(1.5)
	end
end

local function OnCooldownLoopStep(deltaTime: number)
	if not isFireCooldownActive then
		if completeHighlightRemainingSeconds > 0 then
			completeHighlightRemainingSeconds = math.max(completeHighlightRemainingSeconds - deltaTime, 0)
			SetRingToReadyState(true)
		else
			SetRingToReadyState(false)
		end
		return
	end

	cooldownElapsedSeconds += deltaTime
	local progress = math.clamp(cooldownElapsedSeconds / cooldownDurationSeconds, 0, 1)
	SetCooldownProgress(progress)
	if cooldownElapsedSeconds >= cooldownDurationSeconds then
		isFireCooldownActive = false
		completeHighlightRemainingSeconds = RingHighlightDurationSeconds
		SetRingToReadyState(true)
		SetCooldownProgress(1)
	end
end

-- 创建 UI 结构
local function CreateUI()
	configGui = Instance.new("ScreenGui")
	configGui.Name = "ConfigGui"
	configGui.ResetOnSpawn = false
	configGui.DisplayOrder = 999 
	configGui.Enabled = false 
	configGui.Parent = playerGui

	mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromOffset(620, 450)
	mainFrame.Position = UDim2.new(1, -640, 0.5, -225)
	mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	mainFrame.BackgroundTransparency = 0.15
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = configGui

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 10)
	uiCorner.Parent = mainFrame

	local titleLine = Instance.new("TextLabel")
	titleLine.Name = "Title"
	titleLine.Size = UDim2.new(1, 0, 0, 40)
	titleLine.BackgroundTransparency = 1
	titleLine.Text = " 游戏参数配置 (Beta)"
	titleLine.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLine.TextSize = 18
	titleLine.Font = Enum.Font.GothamBold
	titleLine.TextXAlignment = Enum.TextXAlignment.Left
	titleLine.Position = UDim2.fromOffset(10, 0)
	titleLine.Parent = mainFrame

	-- 表头
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(0, 430, 0, 20)
	header.Position = UDim2.fromOffset(10, 40)
	header.BackgroundTransparency = 1
	header.Parent = mainFrame
	
	local function CreateHeaderLabel(text, pos, size, align)
		local l = Instance.new("TextLabel")
		l.Text = text
		l.Size = size
		l.Position = pos
		l.BackgroundTransparency = 1
		l.TextColor3 = Color3.fromRGB(150, 150, 150)
		l.TextSize = 12
		l.Font = Enum.Font.GothamBold
		l.TextXAlignment = align
		l.Parent = header
	end
	CreateHeaderLabel("参数名称", UDim2.fromScale(0, 0), UDim2.fromScale(0.45, 1), Enum.TextXAlignment.Left)
	CreateHeaderLabel("当前值", UDim2.fromScale(0.45, 0), UDim2.fromScale(0.25, 1), Enum.TextXAlignment.Center)
	CreateHeaderLabel("下一局", UDim2.fromScale(0.7, 0), UDim2.fromScale(0.3, 1), Enum.TextXAlignment.Right)

	scrollingFrame = Instance.new("ScrollingFrame")
	scrollingFrame.Name = "ConfigList"
	scrollingFrame.Size = UDim2.new(0, 430, 1, -80)
	scrollingFrame.Position = UDim2.fromOffset(10, 70)
	scrollingFrame.BackgroundTransparency = 1
	scrollingFrame.ScrollBarThickness = 4
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollingFrame.Parent = mainFrame

	local uiListLayout = Instance.new("UIListLayout")
	uiListLayout.Padding = UDim.new(0, 5)
	uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	uiListLayout.Parent = scrollingFrame

	-- 行模板
	rowTemplate = Instance.new("Frame")
	rowTemplate.Name = "RowTemplate"
	rowTemplate.Size = UDim2.new(1, 0, 0, 32)
	rowTemplate.BackgroundTransparency = 0.85
	rowTemplate.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
	
	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 4)
	rowCorner.Parent = rowTemplate

	local aliasLabel = Instance.new("TextLabel")
	aliasLabel.Name = "Alias"
	aliasLabel.Size = UDim2.new(0.45, 0, 1, 0)
	aliasLabel.Position = UDim2.fromOffset(5, 0)
	aliasLabel.BackgroundTransparency = 1
	aliasLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	aliasLabel.TextSize = 13
	aliasLabel.Font = Enum.Font.Gotham
	aliasLabel.TextXAlignment = Enum.TextXAlignment.Left
	aliasLabel.Parent = rowTemplate

	local currentValueLabel = Instance.new("TextLabel")
	currentValueLabel.Name = "CurrentValue"
	currentValueLabel.Size = UDim2.new(0.25, 0, 1, 0)
	currentValueLabel.Position = UDim2.fromScale(0.45, 0)
	currentValueLabel.BackgroundTransparency = 1
	currentValueLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	currentValueLabel.TextSize = 13
	currentValueLabel.Font = Enum.Font.Gotham
	currentValueLabel.TextXAlignment = Enum.TextXAlignment.Center
	currentValueLabel.Parent = rowTemplate

	local nextValueLabel = Instance.new("TextLabel")
	nextValueLabel.Name = "NextValue"
	nextValueLabel.Size = UDim2.new(0.3, -5, 1, 0)
	nextValueLabel.Position = UDim2.fromScale(0.7, 0)
	nextValueLabel.BackgroundTransparency = 1
	nextValueLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
	nextValueLabel.TextSize = 13
	nextValueLabel.Font = Enum.Font.GothamBold
	nextValueLabel.TextXAlignment = Enum.TextXAlignment.Right
	nextValueLabel.Parent = rowTemplate

	CreateCooldownDemoUI()
end

-- 刷新 UI 内容
function ConfigUIManager.Refresh()
	if not scrollingFrame then return end

	-- 清理旧行
	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local visibleParams = GameConfig.VisibleParameters or {}
	for _, configInfo in ipairs(visibleParams) do
		local key = configInfo.key
		local alias = configInfo.alias
		local currentValue = GameConfig[key]
		local nextValue = pendingOverrides[key]
		
		if currentValue == nil then continue end

		local row = rowTemplate:Clone()
		row.Name = key
		row:FindFirstChild("Alias").Text = alias
		row:FindFirstChild("CurrentValue").Text = tostring(currentValue)
		
		local nextValueLabel = row:FindFirstChild("NextValue") :: TextLabel
		if nextValue ~= nil then
			nextValueLabel.Text = tostring(nextValue)
			nextValueLabel.TextColor3 = Color3.fromRGB(0, 255, 255) -- 青色表示有待定修改
		else
			nextValueLabel.Text = tostring(currentValue)
			nextValueLabel.TextColor3 = Color3.fromRGB(255, 255, 0) -- 黄色表示跟随当前
		end
		
		row.Parent = scrollingFrame
	end
	
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, #visibleParams * 37)
end

-- 初始化
function ConfigUIManager.Init()
	CreateUI()
	ConfigUIManager.Refresh()
	SetCooldownProgress(1)

	-- 监听正式应用同步消息 (每局开始时)
	NetMsg.ConnectNotifyGameConfigSync(function(overrides)
		-- 更新本地 GameConfig
		for key, value in pairs(overrides) do
			GameConfig[key] = value
		end
		-- 正式应用后，待定列表可以清空，或者说这些待定已变成当前
		-- 这里我们选择清空 pending，因为下局的初始 pending 应该是空的或者与当前一致
		pendingOverrides = {}
		ConfigUIManager.Refresh()
	end)

	-- 监听实时待定同步消息 (指令修改后立即触发)
	NetMsg.ConnectNotifyPendingConfigSync(function(overrides)
		pendingOverrides = overrides
		ConfigUIManager.Refresh()
	end)

	-- 监听 F4 开关
	game:GetService("UserInputService").InputBegan:Connect(OnInputBegan)
	cooldownLoopConnection = runService.RenderStepped:Connect(OnCooldownLoopStep)

	print("[ConfigUIManager] Upgraded UI Init completed. Press F4 to toggle, F to fire cooldown.")
end

return ConfigUIManager
