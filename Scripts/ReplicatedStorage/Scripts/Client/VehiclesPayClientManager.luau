--!strict
local VehiclesPayClientManager = {}

local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local players: Players = game:GetService("Players")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService: RunService = game:GetService("RunService")
local workspaceService: Workspace = game:GetService("Workspace")

local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local BillboardManager = require(clientScripts:FindFirstChild("BillboardManager"))

local HINT_DISTANCE = 10
local ROTATION_SPEED = math.rad(30)
local RENDER_STEP_NAME = "VehiclesPayClientManager.RenderStepped"
local DEFAULT_COST_VALUE = "x0"

local vehiclesPayModel: Model?
local vehicleModel: Model?
local rootPart: BasePart?
local billboardGui: BillboardGui?
local originModelCFrame: CFrame?
local hasPromptedInCurrentRange = false

local costTextLabel: TextLabel?
local nameTextLabel: TextLabel?
local fireCooldownValueLabel: TextLabel?
local healthValueLabel: TextLabel?
local speedValueLabel: TextLabel?

local function GetCurrentVehicleId(): number?
	if vehiclesPayModel == nil then
		return nil
	end
	local vehicleIdRaw = vehiclesPayModel:GetAttribute("id")
	if typeof(vehicleIdRaw) == "number" then
		return vehicleIdRaw
	end
	if typeof(vehicleIdRaw) == "string" then
		return tonumber(vehicleIdRaw)
	end
	return nil
end

local function ReplaceDisplayModelByVehicleData(vehicleData: GameConfig.VehicleData)
	if vehiclesPayModel == nil or vehicleModel == nil then
		return
	end
	local modelsFolder = replicatedStorage:FindFirstChild("Models") :: Folder?
	if modelsFolder == nil then
		warn("[VehiclesPayClientManager] Models folder missing in ReplicatedStorage")
		return
	end
	local vehiclesFolder = modelsFolder:FindFirstChild("Vehicles") :: Folder?
	if vehiclesFolder == nil then
		warn("[VehiclesPayClientManager] Vehicles folder missing in ReplicatedStorage.Models")
		return
	end
	local sourceModel = vehiclesFolder:FindFirstChild(vehicleData.resourceName)
	if sourceModel == nil or not sourceModel:IsA("Model") then
		warn("[VehiclesPayClientManager] Source vehicle model not found:", vehicleData.resourceName)
		return
	end
	local oldPivot = vehicleModel:GetPivot()
	local newModel = sourceModel:Clone()
	newModel.Name = "VehicleModel"
	newModel.Parent = vehiclesPayModel
	newModel:PivotTo(oldPivot)
	vehicleModel:Destroy()
	vehicleModel = newModel
	originModelCFrame = oldPivot

	for _, desc in ipairs(newModel:GetDescendants()) do
		if desc:IsA("Seat") then
			desc.Disabled = true
			desc.Anchored = true
		elseif desc:IsA("VehicleSeat") then
			desc.Disabled = true
			desc.Anchored = true
		end
	end
end

local function RefreshBillboardTextByVehicleData(vehicleData: GameConfig.VehicleData)
	if nameTextLabel ~= nil then
		nameTextLabel.Text = vehicleData.labelName_t
	end
	if costTextLabel ~= nil then
		costTextLabel.Text = string.format("x%d", math.max(0, math.floor(vehicleData.costRb or 0)))
	end
	if fireCooldownValueLabel ~= nil then
		fireCooldownValueLabel.Text = string.format("%.1fs", vehicleData.fireCooldown)
	end
	if healthValueLabel ~= nil then
		healthValueLabel.Text = tostring(vehicleData.maxHits)
	end
	if speedValueLabel ~= nil then
		speedValueLabel.Text = tostring(vehicleData.moveSpeed)
	end
end

local function RefreshDisplay()
	local vehicleId = GetCurrentVehicleId()
	if vehicleId == nil then
		warn("[VehiclesPayClientManager] Invalid or missing id attribute on Workspace.VehiclesPayModel")
		if costTextLabel ~= nil then
			costTextLabel.Text = DEFAULT_COST_VALUE
		end
		return
	end
	local vehicleData = GameConfig.VehicleDataMap[vehicleId]
	if vehicleData == nil then
		warn("[VehiclesPayClientManager] VehicleData not found for id:", vehicleId)
		if costTextLabel ~= nil then
			costTextLabel.Text = DEFAULT_COST_VALUE
		end
		return
	end

	ReplaceDisplayModelByVehicleData(vehicleData)
	RefreshBillboardTextByVehicleData(vehicleData)
end

local function PromptPurchaseIfNeeded()
	if rootPart == nil then
		return
	end
	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if character == nil then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp == nil or not hrp:IsA("BasePart") then
		return
	end
	local distance = (hrp.Position - rootPart.Position).Magnitude
	if distance >= HINT_DISTANCE then
		hasPromptedInCurrentRange = false
		return
	end
	if hasPromptedInCurrentRange then
		return
	end
	hasPromptedInCurrentRange = true

	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	local vehicleId = GetCurrentVehicleId()
	if localPlayerInfo == nil or vehicleId == nil then
		return
	end
	local isOwned = localPlayerInfo.vehicleInventory.ownedList[tostring(vehicleId)] == true
	if isOwned then
		ClientMsg.FireShowGameTip(GameTexts.VehicleAlreadyOwned.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.VehicleAlreadyOwned.key)
		return
	end
	local vehicleData = GameConfig.VehicleDataMap[vehicleId]
	if vehicleData == nil then
		return
	end
	if vehicleData.productId ~= nil and vehicleData.productId > 0 then
		marketplaceService:PromptProductPurchase(localPlayer, vehicleData.productId)
	end
end

local function AnimateVehicleModel()
	if vehicleModel == nil or originModelCFrame == nil then
		return
	end
	local rotationCF = CFrame.Angles(0, os.clock() * ROTATION_SPEED, 0)
	vehicleModel:PivotTo(originModelCFrame * rotationCF)
end

local function OnRenderStepped(_deltaTime: number)
	AnimateVehicleModel()
	PromptPurchaseIfNeeded()
end

function VehiclesPayClientManager.Init()
	vehiclesPayModel = workspaceService:FindFirstChild("VehiclesPayModel") :: Model?
	if vehiclesPayModel == nil then
		return
	end
	vehicleModel = vehiclesPayModel:FindFirstChild("VehicleModel") :: Model?
	rootPart = vehiclesPayModel:FindFirstChild("RootPart") :: BasePart?
	if vehicleModel == nil or rootPart == nil then
		warn("[VehiclesPayClientManager] VehicleModel or RootPart missing")
		return
	end
	originModelCFrame = vehicleModel:GetPivot()

	local guiAttachment = rootPart:FindFirstChild("GuiAttachment")
	if guiAttachment ~= nil then
		billboardGui = guiAttachment:FindFirstChild("Gui") :: BillboardGui?
	end
	if billboardGui == nil then
		warn("[VehiclesPayClientManager] BillboardGui not found at RootPart.GuiAttachment.Gui")
		return
	end
	local controllerFrame = billboardGui:FindFirstChild("ControllerFrame")
	if controllerFrame ~= nil and controllerFrame:IsA("Frame") then
		nameTextLabel = controllerFrame:FindFirstChild("NameLabel") :: TextLabel?
		costTextLabel = controllerFrame:FindFirstChild("CostText") :: TextLabel?
		local infoFrame = controllerFrame:FindFirstChild("InfoFrame")
		if infoFrame ~= nil and infoFrame:IsA("Frame") then
			fireCooldownValueLabel = infoFrame:FindFirstChild("FireCooldownValue") :: TextLabel?
			healthValueLabel = infoFrame:FindFirstChild("HealthValue") :: TextLabel?
			speedValueLabel = infoFrame:FindFirstChild("SpeedValue") :: TextLabel?
		end
	end

	BillboardManager.Track(billboardGui)
	RefreshDisplay()
	runService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, OnRenderStepped)
	vehiclesPayModel:GetAttributeChangedSignal("id"):Connect(function()
		hasPromptedInCurrentRange = false
		RefreshDisplay()
	end)
	ClientMsg.ConnectLocalPlayerInfoInit(function()
		hasPromptedInCurrentRange = false
	end)
	ClientMsg.ConnectLocalPlayerVehicleInventoryUpdate(function()
		hasPromptedInCurrentRange = false
	end)
end

return VehiclesPayClientManager
