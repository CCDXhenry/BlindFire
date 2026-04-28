--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local TOOLBAR_NAME = "BlindFire Tools"
local BUTTON_NAME = "Wrap Sphere"
local BUTTON_TOOLTIP = "Create a sphere part that wraps the selected model"
local WRAP_PART_NAME = "WrapSphere"

local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
local wrapButton = toolbar:CreateButton(BUTTON_NAME, BUTTON_TOOLTIP, "")

local function getSelectedModel(): Model?
	local selectedList = Selection:Get()
	if #selectedList == 0 then
		warn("No selection found. Please select a model first.")
		return nil
	end

	local selectedInstance = selectedList[1]
	if selectedInstance:IsA("Model") then
		return selectedInstance
	end

	local selectedModel = selectedInstance:FindFirstAncestorOfClass("Model")
	if selectedModel then
		return selectedModel
	end

	warn("Selection is not a model or inside a model.")
	return nil
end

local function createWrapSphere(targetModel: Model): Part?
	if #targetModel:GetDescendants() == 0 then
		warn("Selected model is empty.")
		return nil
	end

	local success, boundingBoxCFrame, boundingBoxSize = pcall(function()
		return targetModel:GetBoundingBox()
	end)

	if not success then
		warn("Failed to calculate model bounding box.")
		return nil
	end

	local sphereDiameter = boundingBoxSize.Magnitude
	local spherePart = Instance.new("Part")
	spherePart.Name = WRAP_PART_NAME
	spherePart.Shape = Enum.PartType.Ball
	spherePart.Size = Vector3.new(sphereDiameter, sphereDiameter, sphereDiameter)
	spherePart.CFrame = boundingBoxCFrame
	spherePart.Anchored = true
	spherePart.CanCollide = false
	spherePart.Transparency = 0.5
	spherePart.Material = Enum.Material.Neon
	spherePart.Color = Color3.fromRGB(0, 170, 255)

	local targetParent = targetModel.Parent
	if not targetParent then
		warn("Selected model has no parent.")
		spherePart:Destroy()
		return nil
	end

	spherePart.Parent = targetParent
	return spherePart
end

local function onWrapButtonClicked()
	local targetModel = getSelectedModel()
	if not targetModel then
		return
	end

	ChangeHistoryService:SetWaypoint("BeforeCreateWrapSphere")

	local spherePart = createWrapSphere(targetModel)
	if not spherePart then
		return
	end

	Selection:Set({ spherePart })
	ChangeHistoryService:SetWaypoint("AfterCreateWrapSphere")
end

wrapButton.Click:Connect(onWrapButtonClicked)
