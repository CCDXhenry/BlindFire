--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")
local BulletClientManager = require(clientScripts:FindFirstChild("BulletClientManager"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local gameFrame: Frame = script.Parent

local FIRE_BUTTON_SIZE = UDim2.new(0, 140, 0, 140)
-- Extra rotation on both ring bars (degrees). Studio template `ReplicatedStorage.UI.GameFrame` uses Bar.Rotation=180 at full ring; keep 0 unless you intentionally retime the fill.
local CooldownRingRotationOffsetDeg = 0

local fireButtonContainer: Frame? = nil
local fireButton: TextButton? = nil

local progressLeft: Frame? = nil
local progressRight: Frame? = nil
local flashOverlay: Frame? = nil

local isCoolingDown = false

local function PlayFlashEffect()
	if not flashOverlay or not fireButton then return end
	
	flashOverlay.BackgroundTransparency = 0.3
	local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	tweenService:Create(flashOverlay, tweenInfo, {BackgroundTransparency = 1}):Play()
	
	-- Button brightness bump
	local originalColor = Color3.fromRGB(220, 60, 60)
	fireButton.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
	tweenService:Create(fireButton, tweenInfo, {BackgroundColor3 = originalColor}):Play()
end

local function UpdateGameFrame()
	local matchState = BulletClientManager.GetMatchState()
	local isAlive = BulletClientManager.IsLocalInVehicle()
	
	-- Show fire button only if alive AND during GameStartCountdown or Fighting
	local shouldBeVisible = isAlive and (matchState == "GameStartCountdown" or matchState == "Fighting")
	if fireButtonContainer then
		fireButtonContainer.Visible = shouldBeVisible
	end
	
	if not shouldBeVisible or fireButton == nil then
		return
	end

	local cooldownLeft = BulletClientManager.GetLocalFireCooldownLeft()

	-- Update Progress Bar
	local totalCD = GameConfig.FireCooldown
	local progress = 1 - math.clamp(cooldownLeft / totalCD, 0, 1)
	
	if progressLeft and progressRight then
		-- progress 0 = empty (dark), 1 = full ring. Each half only rotates 0–180 so at p=1 we get (180,180), not (180,360); 360° == 0° and would drop the second semicircle.
		-- Fill from top toward left first: LeftHalf bar leads 0–50%, RightHalf follows 50–100% (CCW sense on screen when paired with masks below).
		local leftAngle = math.clamp(progress * 2, 0, 1) * 180
		local rightAngle = math.clamp(progress * 2 - 1, 0, 1) * 180
		
		progressLeft.Rotation = leftAngle + CooldownRingRotationOffsetDeg
		progressRight.Rotation = rightAngle + CooldownRingRotationOffsetDeg
	end

	-- State feedback
	if cooldownLeft > 0 then
		isCoolingDown = true
		fireButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		fireButton.TextTransparency = 0.5
	else
		if isCoolingDown then
			isCoolingDown = false
			PlayFlashEffect()
		end
		fireButton.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
		fireButton.TextTransparency = 0
	end
end

local function SemicircleTransparencyLeftHalf(): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.499, 0),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function SemicircleTransparencyRightHalf(): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.499, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
end

local function ApplySemicircleMaskToTarget(target: GuiObject, useRightHalfMask: boolean)
	local grad = target:FindFirstChildOfClass("UIGradient")
	if grad == nil then
		grad = Instance.new("UIGradient")
		grad.Parent = target
	end
	grad.Rotation = 0
	grad.Transparency = if useRightHalfMask then SemicircleTransparencyRightHalf() else SemicircleTransparencyLeftHalf()
end

local function InitCooldownRingMasks()
	if progressLeft == nil or progressRight == nil then
		return
	end
	ApplySemicircleMaskToTarget(progressRight, true)
	local strokeRight = progressRight:FindFirstChildOfClass("UIStroke")
	if strokeRight then
		ApplySemicircleMaskToTarget(strokeRight, true)
	end
	ApplySemicircleMaskToTarget(progressLeft, false)
	local strokeLeft = progressLeft:FindFirstChildOfClass("UIStroke")
	if strokeLeft then
		ApplySemicircleMaskToTarget(strokeLeft, false)
	end
end

local function OnFireButtonPressed()
	if fireButton == nil or isCoolingDown then return end
	fireButton.Size = UDim2.new(0, 130, 0, 130)
end

local function OnFireButtonReleased()
	if fireButton == nil then return end
	fireButton.Size = FIRE_BUTTON_SIZE
end

local function OnFireButtonClicked()
	if isCoolingDown then return end
	BulletClientManager.FireShot()
end

local function SetupFireButton()
	fireButtonContainer = gameFrame:WaitForChild("FireButtonContainer", 5) :: Frame
	if not fireButtonContainer then 
		warn("[GameFrame] FireButtonContainer not found in GameFrame")
		return 
	end

	-- Find the button (could be TextButton or ImageButton)
	fireButton = (fireButtonContainer:FindFirstChild("FireButton") or fireButtonContainer:FindFirstChildOfClass("TextButton") or fireButtonContainer:FindFirstChildOfClass("ImageButton")) :: any
	
	if fireButton then
		flashOverlay = fireButton:FindFirstChild("FlashOverlay") :: Frame
		
		fireButton.MouseButton1Down:Connect(OnFireButtonPressed)
		fireButton.MouseButton1Up:Connect(OnFireButtonReleased)
		fireButton.Activated:Connect(OnFireButtonClicked)
	end

	local rightHalf = fireButtonContainer:FindFirstChild("RightHalf")
	if rightHalf then
		progressRight = rightHalf:FindFirstChild("Bar") :: Frame
	end

	local leftHalf = fireButtonContainer:FindFirstChild("LeftHalf")
	if leftHalf then
		progressLeft = leftHalf:FindFirstChild("Bar") :: Frame
	end

	InitCooldownRingMasks()
end

local function InitUI()
	UIAdapter.AddAdaptiveFrame(gameFrame, UIAdapter.AdaptiveType.FullScreen)
	SetupFireButton()
end

InitUI()
runService.RenderStepped:Connect(UpdateGameFrame)
