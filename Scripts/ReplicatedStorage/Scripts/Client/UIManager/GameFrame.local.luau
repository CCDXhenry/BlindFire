--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

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

local UI_UPDATE_INTERVAL_SEC = 1 / 20


local fireButtonContainer: Frame? = nil
local shootButton: ImageButton? = nil

local updateAccumSec = 0
local lastButtonVisible: boolean? = nil
local lastShootButtonActive: boolean? = nil

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
end

local function OnShootButtonClicked()
	BulletClientManager.FireShot()
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
