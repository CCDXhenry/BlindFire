--!strict
local ConfigUIManager = {}

local players = game:GetService("Players")
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

-- 存储待定配置（下一局生效）
local pendingOverrides: { [string]: any } = {}

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
	mainFrame.Size = UDim2.fromOffset(400, 450) -- 变宽一点展示两列
	mainFrame.Position = UDim2.new(1, -420, 0.5, -225)
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
	header.Size = UDim2.new(1, -20, 0, 20)
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
	scrollingFrame.Size = UDim2.new(1, -20, 1, -80)
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
	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.F4 then
			if configGui then
				configGui.Enabled = not configGui.Enabled
			end
		end
	end)

	print("[ConfigUIManager] Upgraded UI Init completed. Press F4 to toggle.")
end

return ConfigUIManager
