--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local BulletClientManager = require(clientScripts:FindFirstChild("BulletClientManager"))

local gameFrame: Frame = script.Parent

local FIRE_BUTTON_SIZE = UDim2.new(0, 160, 0, 160)
local FIRE_BUTTON_POS = UDim2.new(1, -180, 1, -180)

local fireButton: TextButton? = nil
local tipTextLabel: TextLabel? = nil
local hpTextLabel: TextLabel? = nil
local cooldownTextLabel: TextLabel? = nil

local function CreateLabel(name: string, position: UDim2, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(0, 360, 0, 40)
	label.Position = position
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = 20
	label.Font = Enum.Font.GothamMedium
	label.Text = text
	label.BorderSizePixel = 0
	label.Parent = gameFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	return label
end

local function CreateFireButton(): TextButton
	local button = Instance.new("TextButton")
	button.Name = "FireButton"
	button.Size = FIRE_BUTTON_SIZE
	button.Position = FIRE_BUTTON_POS
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	button.Text = "Fire"
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 26
	button.BorderSizePixel = 0
	button.ZIndex = 10
	button.Parent = gameFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 120, 120)
	stroke.Thickness = 3
	stroke.Transparency = 0.3
	stroke.Parent = button

	return button
end

local function UpdateGameFrame()
	if tipTextLabel == nil or hpTextLabel == nil or cooldownTextLabel == nil then
		return
	end

	local hitCount, maxHits = BulletClientManager.GetLocalHpInfo()
	local cooldownLeft = BulletClientManager.GetLocalFireCooldownLeft()
	local matchState = BulletClientManager.GetMatchState()
	local hpLeft = math.max(0, maxHits - hitCount)

	tipTextLabel.Text = string.format("State: %s  |  Fire: button (Space in vehicle = fire, no exit)", matchState)
	hpTextLabel.Text = string.format("HP: %d/%d", hpLeft, maxHits)
	cooldownTextLabel.Text = string.format("Fire CD: %.1fs", cooldownLeft)
end

local function OnFireButtonPressed()
	if fireButton == nil then
		return
	end
	fireButton.BackgroundColor3 = Color3.fromRGB(160, 30, 30)
	fireButton.Size = UDim2.new(0, 148, 0, 148)
end

local function OnFireButtonReleased()
	if fireButton == nil then
		return
	end
	fireButton.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	fireButton.Size = FIRE_BUTTON_SIZE
end

local function OnFireButtonClicked()
	BulletClientManager.FireShot()
end

local function InitUI()
	UIAdapter.AddAdaptiveFrame(gameFrame, UIAdapter.AdaptiveType.FullScreen)
	tipTextLabel = CreateLabel("TipLabel", UDim2.new(0, 20, 0, 20), "State: InLobby")
	hpTextLabel = CreateLabel("HpLabel", UDim2.new(0, 20, 0, 70), "HP: 3/3")
	cooldownTextLabel = CreateLabel("CooldownLabel", UDim2.new(0, 20, 0, 120), "Fire CD: 0.0s")

	fireButton = CreateFireButton()
	fireButton.MouseButton1Down:Connect(OnFireButtonPressed)
	fireButton.MouseButton1Up:Connect(OnFireButtonReleased)
	fireButton.MouseButton1Click:Connect(OnFireButtonClicked)
end

InitUI()
runService.RenderStepped:Connect(UpdateGameFrame)
