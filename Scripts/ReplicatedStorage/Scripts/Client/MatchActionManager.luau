--!strict
local MatchActionManager = {}

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local JUMP_ACTION_NAME = "DisableJumpAction"
local isInitialized = false
local isJumpDisabled = false
local renderSteppedConnection: RBXScriptConnection? = nil

local function SinkJump()
	return Enum.ContextActionResult.Sink
end

local function UpdateHumanoidJumpSuppression()
	local localPlayer = game:GetService("Players").LocalPlayer
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		-- 每帧强制重置，拦截所有底层回弹逻辑
		humanoid.Jump = false
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
end

local function SetJumpEnabled(enabled: boolean)
	if enabled then
		if not isJumpDisabled then
			return
		end
		isJumpDisabled = false
		ContextActionService:UnbindAction(JUMP_ACTION_NAME)

		-- 断开每帧强制抑制
		if renderSteppedConnection then
			renderSteppedConnection:Disconnect()
			renderSteppedConnection = nil
		end

		-- 恢复一次 Humanoid 状态
		local character = game:GetService("Players").LocalPlayer.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			humanoid.JumpPower = 50
			humanoid.JumpHeight = 7.2
		end
	else
		if isJumpDisabled then
			return
		end
		isJumpDisabled = true
		
		-- 使用极高优先级拦截输入
		ContextActionService:BindActionAtPriority(
			JUMP_ACTION_NAME,
			SinkJump,
			false,
			3000, -- 进一步提高优先级
			Enum.KeyCode.Space,
			Enum.KeyCode.ButtonA
		)

		-- 开启每帧强制抑制循环
		if not renderSteppedConnection then
			renderSteppedConnection = RunService.RenderStepped:Connect(UpdateHumanoidJumpSuppression)
		end
		-- 立即执行一次
		UpdateHumanoidJumpSuppression()
	end
end

local function OnMatchStateChanged(matchState: GameConfig.MatchState, countdown: number)
	-- 根据纠正后的需求：
	-- 1. InLobby 和 MatchCountdown 的早期（> 2s）允许跳跃。
	-- 2. 在 MatchCountdown 的最后 2 秒开始屏蔽跳跃（此时即将进行转场）。
	-- 3. GameStartCountdown (竞技场倒计时) 和 Fighting 阶段继续屏蔽跳跃。

	local shouldDisable = false

	if matchState == "MatchCountdown" then
		-- 匹配倒计时的最后 2 秒起禁止跳跃
		if countdown <= 2 then
			shouldDisable = true
		end
	elseif matchState == "GameStartCountdown" or matchState == "Fighting" then
		-- 进入竞技场阶段全程禁止跳跃
		shouldDisable = true
	end

	if shouldDisable then
		SetJumpEnabled(false)
	else
		-- 其他情况（大厅待机、匹配阶段早期）允许跳跃
		SetJumpEnabled(true)
	end
end

function MatchActionManager.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	NetMsg.ConnectNotifyMatchState(OnMatchStateChanged)
end

return MatchActionManager
