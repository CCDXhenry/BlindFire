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


local fireButtonContainer: Frame? = nil
local fireButton: TextButton? = nil
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
		(rightHalf :: any).Visible = false
	end

	local leftHalf = fireButtonContainer:FindFirstChild("LeftHalf")
	if leftHalf then
		(leftHalf :: any).Visible = false
	end
end

local function InitUI()
	UIAdapter.AddAdaptiveFrame(gameFrame, UIAdapter.AdaptiveType.FullScreen)
	SetupFireButton()
end

InitUI()
runService.RenderStepped:Connect(UpdateGameFrame)
