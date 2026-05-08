--!strict
local CombatCameraManager = {}

local players = game:GetService("Players")
local runService = game:GetService("RunService")
local _userInputService = game:GetService("UserInputService")
local workspaceService = game:GetService("Workspace")
local contextActionService = game:GetService("ContextActionService")

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local BulletClientManager = require(clientScripts:WaitForChild("BulletClientManager"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))

local COMBAT_FIRE_ACTION_NAME = "BlindFire_CombatVehicleFire"

local isInitialized: boolean = false

local jumpSuppressionHumanoid: Humanoid? = nil
local jumpSuppressionJumpingWasEnabled: boolean? = nil
local arenaSeatPrepareJumpLock: boolean = false

local characterAddedConnection: RBXScriptConnection? = nil
local scriptDestroyingConnection: RBXScriptConnection? = nil
local renderSteppedConnection: RBXScriptConnection? = nil
local localPlayer = players.LocalPlayer

local INITIAL_CAMERA_ZOOM_APPLY_DELAY_SEC = 0.15
local hasAppliedInitialZoomOnce = false

local function ApplyInitialCameraZoomOnce()
	if hasAppliedInitialZoomOnce then
		return
	end
	hasAppliedInitialZoomOnce = true

	local player = localPlayer
	-- 初次进入服务器时，临时钳住缩放距离，避免默认过近；随后恢复范围以允许滚轮调整。
	local originalMin = player.CameraMinZoomDistance
	local originalMax = player.CameraMaxZoomDistance
	local minValue = math.min(originalMin, originalMax)
	local maxValue = math.max(originalMin, originalMax)
	local initialDistance = GameConfig.InitialCameraZoomDistance or 50
	local desired = math.clamp(initialDistance, minValue, maxValue)

	player.CameraMinZoomDistance = desired
	player.CameraMaxZoomDistance = desired

	task.delay(INITIAL_CAMERA_ZOOM_APPLY_DELAY_SEC, function()
		-- 若期间有其他逻辑接管缩放（或玩家设置被改），避免“恢复”覆盖外部写入。
		if player.CameraMinZoomDistance ~= desired or player.CameraMaxZoomDistance ~= desired then
			return
		end
		player.CameraMinZoomDistance = originalMin
		player.CameraMaxZoomDistance = originalMax
	end)
end

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
	return phase == GameConfig.MatchState.Fighting
end

local function ShouldSuppressJumpOnOwnVehicle(): boolean
	if GetOwnVehicleSeat() == nil then
		return false
	end
	local phase = BulletClientManager.GetMatchState()
	return phase == GameConfig.MatchState.Fighting or phase == GameConfig.MatchState.GameStartCountdown
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
	if phase == GameConfig.MatchState.InLobby then
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

local function UpdateLocalCameraSubject()
	local camera = workspaceService.CurrentCamera
	if camera == nil then
		return
	end
	local character = localPlayer.Character
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	if camera.CameraSubject ~= humanoid then
		camera.CameraSubject = humanoid
	end
end

local function OnRenderStepped()
	UpdateJumpSuppressionForCombatSeat()
	UpdateLocalCameraSubject()
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
	ClientGameInfo.TryCompleteGuide(GameConfig.GuideType.TutorialFireBySpace)
	return Enum.ContextActionResult.Sink
end

local function OnCharacterAdded(_character: Model)
	RestoreJumpSuppressionIfNeeded()
	ApplyInitialCameraZoomOnce()
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

	-- 覆盖“脚本初始化晚于角色生成”的情况：本次进服仍只会执行一次
	if localPlayer.Character ~= nil then
		ApplyInitialCameraZoomOnce()
	end
end

return CombatCameraManager
