--!strict
local CombatCameraManager = {}

local players = game:GetService("Players")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local workspaceService = game:GetService("Workspace")
local contextActionService = game:GetService("ContextActionService")

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local BulletClientManager = require(clientScripts:WaitForChild("BulletClientManager"))

local COMBAT_FIRE_ACTION_NAME = "BlindFire_CombatVehicleFire"

local isInitialized: boolean = false

local jumpSuppressionHumanoid: Humanoid? = nil
local jumpSuppressionJumpingWasEnabled: boolean? = nil
local arenaSeatPrepareJumpLock: boolean = false

local characterAddedConnection: RBXScriptConnection? = nil
local scriptDestroyingConnection: RBXScriptConnection? = nil
local renderSteppedConnection: RBXScriptConnection? = nil

local function GetOwnVehicleSeat(): Seat?
	local character = players.LocalPlayer.Character
	if character == nil then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then return nil end
	local seatPart = humanoid.SeatPart
	if seatPart == nil or not seatPart:IsA("Seat") then return nil end
	local model = seatPart:FindFirstAncestorOfClass("Model")
	if model == nil then return nil end
	local expectedName = "Vehicle_" .. tostring(players.LocalPlayer.UserId)
	if model.Name ~= expectedName then return nil end
	return seatPart :: Seat
end

local function ShouldCombatVehicleSpaceFire(): boolean
	if GetOwnVehicleSeat() == nil then return false end
	local phase = BulletClientManager.GetMatchState()
	return phase == "Fighting"
end

local function ShouldSuppressJumpOnOwnVehicle(): boolean
	if GetOwnVehicleSeat() == nil then
		return false
	end
	local phase = BulletClientManager.GetMatchState()
	return phase == "Fighting" or phase == "GameStartCountdown"
end

local function RestoreJumpSuppressionIfNeeded()
	if jumpSuppressionHumanoid ~= nil and jumpSuppressionJumpingWasEnabled ~= nil then
		if jumpSuppressionHumanoid.Parent ~= nil then
			jumpSuppressionHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, jumpSuppressionJumpingWasEnabled)
		end
	end
	jumpSuppressionHumanoid = nil
	jumpSuppressionJumpingWasEnabled = nil
end

local function UpdateJumpSuppressionForCombatSeat()
	local phase = BulletClientManager.GetMatchState()
	if phase == "InLobby" then
		arenaSeatPrepareJumpLock = false
	end
	if GetOwnVehicleSeat() ~= nil then
		arenaSeatPrepareJumpLock = false
	end

	local wantSuppression = ShouldSuppressJumpOnOwnVehicle() or arenaSeatPrepareJumpLock
	if not wantSuppression then
		RestoreJumpSuppressionIfNeeded()
		return
	end

	local character = players.LocalPlayer.Character
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	if jumpSuppressionHumanoid ~= humanoid then
		RestoreJumpSuppressionIfNeeded()
		jumpSuppressionHumanoid = humanoid
		jumpSuppressionJumpingWasEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

local function UpdateVehicleOcclusionProtection()
	local character = players.LocalPlayer.Character
	if character == nil then return end

	local seat = GetOwnVehicleSeat()
	if seat ~= nil then
		local model = seat:FindFirstAncestorOfClass("Model")
		if model ~= nil and model.Parent ~= character then
			-- 将载具模型本地父级设为角色，防止 Invisicam 将其视为遮挡物而变透明
			model.Parent = character
		end
	end
end

local function OnRenderStepped()
	UpdateJumpSuppressionForCombatSeat()
	UpdateVehicleOcclusionProtection()
end

local function OnCombatFireAction(actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
	if actionName ~= COMBAT_FIRE_ACTION_NAME then
		return Enum.ContextActionResult.Pass
	end
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not ShouldCombatVehicleSpaceFire() then
		return Enum.ContextActionResult.Pass
	end
	BulletClientManager.FireShot()
	return Enum.ContextActionResult.Sink
end

local function OnCharacterAdded(_character: Model)
	RestoreJumpSuppressionIfNeeded()
end

local function OnScriptDestroying()
	contextActionService:UnbindAction(COMBAT_FIRE_ACTION_NAME)
	arenaSeatPrepareJumpLock = false
	RestoreJumpSuppressionIfNeeded()
	if characterAddedConnection ~= nil then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end
	if scriptDestroyingConnection ~= nil then
		scriptDestroyingConnection:Disconnect()
		scriptDestroyingConnection = nil
	end
	if renderSteppedConnection ~= nil then
		renderSteppedConnection:Disconnect()
		renderSteppedConnection = nil
	end
end

function CombatCameraManager.AddRecoil()
	-- 空实现，取消原生固定视角后不做额外后坐力旋转
end

function CombatCameraManager.Init()
	if isInitialized then return end
	isInitialized = true

	contextActionService:BindActionAtPriority(
		COMBAT_FIRE_ACTION_NAME,
		OnCombatFireAction,
		false,
		Enum.ContextActionPriority.High.Value + 2500,
		Enum.KeyCode.Space,
		Enum.PlayerActions.CharacterJump
	)
	renderSteppedConnection = runService.RenderStepped:Connect(OnRenderStepped)
	characterAddedConnection = players.LocalPlayer.CharacterAdded:Connect(OnCharacterAdded)
	scriptDestroyingConnection = script.Destroying:Connect(OnScriptDestroying)
	NetMsg.ConnectNotifyArenaSeatPrepare(function()
		arenaSeatPrepareJumpLock = true
	end)
end

return CombatCameraManager
