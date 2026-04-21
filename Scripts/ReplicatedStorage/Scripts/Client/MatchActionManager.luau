--!strict
local MatchActionManager = {}

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local CAS_PRIORITY = 3000
local DEFAULT_JUMP_POWER = 50
local DEFAULT_JUMP_HEIGHT = 7.2

local isInitialized = false
local localPlayer: Player = Players.LocalPlayer
local disableJumpActionId: string = ""

local isLocalParticipant = false
local isLocalDead = false
local lastMatchState: GameConfig.MatchState = "InLobby"
local lastCountdown = 0
local isWaitingForRelease = false
local wasDisabledLastFrame = false
local jumpCasBound = false

local function OnDisableJumpAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		return Enum.ContextActionResult.Pass
	end
	return Enum.ContextActionResult.Sink
end

local function BindJumpSuppressCas()
	ContextActionService:BindActionAtPriority(
		disableJumpActionId,
		OnDisableJumpAction,
		false,
		CAS_PRIORITY,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA
	)
end

local function UnbindJumpSuppressCas()
	ContextActionService:UnbindAction(disableJumpActionId)
end

local function OnUpdate()
	local shouldSuppressByState = false
	if lastMatchState == "MatchCountdown" then
		if lastCountdown <= 2 then
			shouldSuppressByState = true
		end
	elseif lastMatchState == "GameStartCountdown" or lastMatchState == "Fighting" then
		if isLocalParticipant and not isLocalDead then
			shouldSuppressByState = true
		end
	end

	if shouldSuppressByState then
		isWaitingForRelease = true
	else
		local isHoldingJumpKey = UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.ButtonA)
		if isWaitingForRelease and not isHoldingJumpKey then
			isWaitingForRelease = false
		end
	end

	local finalDisable = shouldSuppressByState or isWaitingForRelease

	if finalDisable then
		if not jumpCasBound then
			BindJumpSuppressCas()
			jumpCasBound = true
		end
		wasDisabledLastFrame = true
	else
		if jumpCasBound then
			UnbindJumpSuppressCas()
			jumpCasBound = false
		end
	end

	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil

	if finalDisable then
		if humanoid then
			humanoid.Jump = false
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		end
		return
	end

	if wasDisabledLastFrame then
		if humanoid then
			humanoid.Jump = false
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			humanoid.JumpPower = DEFAULT_JUMP_POWER
			humanoid.JumpHeight = DEFAULT_JUMP_HEIGHT
		end
		wasDisabledLastFrame = false
	end
end

local function OnMatchStateChanged(matchState: GameConfig.MatchState, countdown: number)
	lastMatchState = matchState
	lastCountdown = countdown

	if matchState == "InLobby" or matchState == "MatchCountdown" then
		isLocalDead = false
	end
end

local function OnUnitInit(unitInitInfo: GameConfig.UnitInitInfo)
	if unitInitInfo.playerId == localPlayer.UserId then
		isLocalParticipant = unitInitInfo.isParticipant
		isLocalDead = false
	end
end

local function OnDead(playerId: number, _killerId: number?)
	if playerId == localPlayer.UserId then
		isLocalDead = true
	end
end

local function OnUnitRemove(playerId: number)
	if playerId == localPlayer.UserId then
		isLocalParticipant = false
		isLocalDead = false
	end
end

function MatchActionManager.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	disableJumpActionId = "DisableJump_" .. tostring(localPlayer.UserId)

	NetMsg.ConnectNotifyMatchState(OnMatchStateChanged)
	NetMsg.ConnectNotifyUnitInit(OnUnitInit)
	NetMsg.ConnectNotifyDead(OnDead)
	NetMsg.ConnectNotifyUnitRemove(OnUnitRemove)

	RunService.Heartbeat:Connect(OnUpdate)
end

return MatchActionManager
