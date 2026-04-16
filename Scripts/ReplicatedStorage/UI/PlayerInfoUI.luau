--!strict
local PlayerInfoUI = {}

function PlayerInfoUI.Create(): BillboardGui
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "PlayerInfoUI"
	billboardGui.Size = UDim2.new(6, 0, 1.2, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.ExtentsOffsetWorldSpace = Vector3.new(0, 3, 0)
	billboardGui.MaxDistance = 150

	local controllerFrame = Instance.new("Frame")
	controllerFrame.Name = "ControllerFrame"
	controllerFrame.Size = UDim2.new(0, 200, 0, 40)
	controllerFrame.BackgroundTransparency = 1
	controllerFrame.BorderSizePixel = 0
	controllerFrame.Parent = billboardGui

	-- Add UIScale for BillboardManager
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "UIScale"
	uiScale.Parent = controllerFrame

	local healthBar = Instance.new("Frame")
	healthBar.Name = "HealthBar"
	healthBar.Size = UDim2.new(0.8, 0, 0.4, 0)
	healthBar.Position = UDim2.new(0.1, 0, 0.3, 0)
	healthBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	healthBar.BorderSizePixel = 0
	healthBar.Parent = controllerFrame

	local scaleBar = Instance.new("Frame")
	scaleBar.Name = "ScaleBar"
	scaleBar.Size = UDim2.new(1, 0, 1, 0)
	scaleBar.BackgroundTransparency = 1
	scaleBar.BorderSizePixel = 0
	scaleBar.Parent = healthBar

	local scale = Instance.new("Frame")
	scale.Name = "Scale"
	scale.Size = UDim2.new(1, 0, 1, 0)
	scale.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
	scale.BorderSizePixel = 0
	scale.Parent = scaleBar

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextLabel"
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextSize = 14
	textLabel.Font = Enum.Font.GothamBold
	textLabel.Text = "3/3"
	textLabel.Parent = healthBar

	-- Optional: Smooth corner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = healthBar

	local cornerScale = Instance.new("UICorner")
	cornerScale.CornerRadius = UDim.new(0.2, 0)
	cornerScale.Parent = scale

	return billboardGui
end

return PlayerInfoUI
