--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local players = game:GetService("Players")

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local sharedScripts = scripts:WaitForChild("Shared")
local BulletClientManager = require(clientScripts:FindFirstChild("BulletClientManager"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local GuideManager = require(clientScripts:FindFirstChild("GuideManager"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local gameFrame: Frame = script.Parent

local UI_UPDATE_INTERVAL_SEC = 1 / 20


local fireButtonContainer: Frame? = nil
local shootButton: ImageButton? = nil

local updateAccumSec = 0
local lastButtonVisible: boolean? = nil
local lastShootButtonActive: boolean? = nil
local shootButtonPulseTween: Tween? = nil
local fingerClone: ImageLabel? = nil

local FINGER_CLONE_NAME = "GuideFingerClone"
local FINGER_ZINDEX_BOOST = 50
local FINGER_PULSE_TWEEN_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local FINGER_PULSE_MIN_SCALE = 0.78

local function ResolveFingerTemplate(): ImageLabel?
	local playerGui = players.LocalPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
	if playerGui ~= nil then
		local gameScreenGui = playerGui:FindFirstChild("GameScreenGui") :: ScreenGui?
		if gameScreenGui ~= nil then
			local guideFrame = gameScreenGui:FindFirstChild("GuideFrame", true)
			if guideFrame ~= nil then
				local fingerImage = guideFrame:FindFirstChild("FingerImage", true)
				if fingerImage ~= nil and fingerImage:IsA("ImageLabel") then
					return fingerImage
				end
			end
		end
	end
	local uiFolder = replicatedStorage:FindFirstChild("UI")
	if uiFolder ~= nil then
		local guideFrame = uiFolder:FindFirstChild("GuideFrame", true)
		if guideFrame ~= nil then
			local fingerImage = guideFrame:FindFirstChild("FingerImage", true)
			if fingerImage ~= nil and fingerImage:IsA("ImageLabel") then
				return fingerImage
			end
		end
	end
	return nil
end

local function StopShootButtonGuidePulse()
	if shootButtonPulseTween ~= nil then
		shootButtonPulseTween:Cancel()
		shootButtonPulseTween = nil
	end
	if fingerClone ~= nil then
		fingerClone:Destroy()
		fingerClone = nil
	end
	if shootButton == nil then
		return
	end
	local uiScale = shootButton:FindFirstChildOfClass("UIScale")
	if uiScale ~= nil then
		uiScale.Scale = 1
	end
end

local function EnsureShootButtonGuidePulse()
	if shootButton == nil or shootButtonPulseTween ~= nil then
		return
	end

	local fingerTemplate = ResolveFingerTemplate()
	if fingerTemplate ~= nil then
		if fingerClone ~= nil and fingerClone.Parent == shootButton then
			return
		end
		if fingerClone ~= nil then
			fingerClone:Destroy()
			fingerClone = nil
		end
		local clone = fingerTemplate:Clone()
		clone.Name = FINGER_CLONE_NAME
		clone.Visible = true
		clone.ZIndex = shootButton.ZIndex + FINGER_ZINDEX_BOOST
		clone.Parent = shootButton
		fingerClone = clone
		local fingerScale = clone:FindFirstChildOfClass("UIScale") :: UIScale?
		if fingerScale == nil then
			local createdFingerScale = Instance.new("UIScale")
			createdFingerScale.Scale = 1
			createdFingerScale.Parent = clone
			fingerScale = createdFingerScale
		end
		local resolvedFingerScale = fingerScale :: UIScale
		resolvedFingerScale.Scale = 1
		local fingerTween = tweenService:Create(resolvedFingerScale, FINGER_PULSE_TWEEN_INFO, { Scale = FINGER_PULSE_MIN_SCALE })
		shootButtonPulseTween = fingerTween
		fingerTween:Play()
		return
	end

	-- FingerImage 未找到时不做任何兜底显示，避免出现非手指样式引导
end

local function ApplyFireButtonVisible(shouldBeVisible: boolean)
	if lastButtonVisible == shouldBeVisible then
		return
	end
	lastButtonVisible = shouldBeVisible
	if fireButtonContainer then
		fireButtonContainer.Visible = shouldBeVisible
	end
end

local function ApplyShootButtonActive(canShoot: boolean)
	if lastShootButtonActive == canShoot then
		return
	end
	lastShootButtonActive = canShoot
	if shootButton == nil then
		return
	end
	shootButton.Active = canShoot
	shootButton.AutoButtonColor = canShoot
end

local function UpdateGameFrame(deltaTime: number)
	updateAccumSec += deltaTime
	if updateAccumSec < UI_UPDATE_INTERVAL_SEC then
		return
	end
	updateAccumSec = 0

	local matchState = BulletClientManager.GetMatchState()
	local isAlive = BulletClientManager.IsLocalInVehicle()
	
	-- Show fire button only if alive AND during GameStartCountdown or Fighting
	local shouldBeVisible = isAlive
		and (matchState == GameConfig.MatchState.GameStartCountdown or matchState == GameConfig.MatchState.Fighting)
	ApplyFireButtonVisible(shouldBeVisible)
	
	if not shouldBeVisible or shootButton == nil then
		ApplyShootButtonActive(false)
		return
	end

	local cooldownLeft = BulletClientManager.GetLocalFireCooldownLeft()
	local canShoot = cooldownLeft <= 0
	ApplyShootButtonActive(canShoot)

	local shouldShowButtonGuidePulse = shouldBeVisible
		and canShoot
		and GuideManager.ShouldShowButtonGuide()
	if shouldShowButtonGuidePulse then
		EnsureShootButtonGuidePulse()
	else
		StopShootButtonGuidePulse()
	end
end

local function OnShootButtonClicked()
	BulletClientManager.FireShot()
	ClientGameInfo.TryCompleteGuide(GameConfig.GuideType.TutorialFireByButton)
	StopShootButtonGuidePulse()
end

local function SetupFireButton()
	fireButtonContainer = gameFrame:WaitForChild("FireButtonContainer", 5) :: Frame
	if not fireButtonContainer then 
		warn("[GameFrame] FireButtonContainer not found in GameFrame")
		return 
	end

	shootButton = fireButtonContainer:FindFirstChild("ShootButton") :: ImageButton?
	if shootButton == nil then
		warn("[GameFrame] ShootButton not found in FireButtonContainer")
		return
	end

	shootButton.Activated:Connect(OnShootButtonClicked)
end

local function InitUI()
	UIAdapter.AddAdaptiveFrame(gameFrame, UIAdapter.AdaptiveType.FullScreen)
	SetupFireButton()
end

InitUI()
runService.Heartbeat:Connect(UpdateGameFrame)
