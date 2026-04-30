--!strict
local GuideManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local userInputService = game:GetService("UserInputService")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")

local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local ClientGameInfo = require(clientScripts:WaitForChild("ClientGameInfo"))

local isInitialized = false
local currentMatchState: GameConfig.MatchState = GameConfig.MatchState.InLobby
local isSpaceGuideActivatedThisRound = false
local isButtonGuideActivatedThisRound = false

local function ResetRoundGuideActivation()
	isSpaceGuideActivatedThisRound = false
	isButtonGuideActivatedThisRound = false
end

local function OnNotifyMatchState(matchState: GameConfig.MatchState, _countdown: number)
	currentMatchState = matchState
	if matchState == GameConfig.MatchState.InLobby
		or matchState == GameConfig.MatchState.MatchCountdown
		or matchState == GameConfig.MatchState.Settlement
	then
		ResetRoundGuideActivation()
		return
	end

	-- 仅在开局倒计时阶段“激活”本局引导，进入 Fighting 后才允许显示
	if matchState ~= GameConfig.MatchState.GameStartCountdown then
		return
	end
	if not userInputService.TouchEnabled and not ClientGameInfo.IsGuideFinished(GameConfig.GuideType.TutorialFireBySpace) then
		isSpaceGuideActivatedThisRound = true
	end
	if not ClientGameInfo.IsGuideFinished(GameConfig.GuideType.TutorialFireByButton) then
		isButtonGuideActivatedThisRound = true
	end
end

function GuideManager.ShouldShowSpaceGuide(): boolean
	if currentMatchState ~= GameConfig.MatchState.Fighting then
		return false
	end
	if ClientGameInfo.IsGuideFinished(GameConfig.GuideType.TutorialFireBySpace) then
		return false
	end
	return isSpaceGuideActivatedThisRound
end

function GuideManager.ShouldShowButtonGuide(): boolean
	if currentMatchState ~= GameConfig.MatchState.Fighting then
		return false
	end
	if ClientGameInfo.IsGuideFinished(GameConfig.GuideType.TutorialFireByButton) then
		return false
	end
	return isButtonGuideActivatedThisRound
end

function GuideManager.Init()
	if isInitialized then
		return
	end
	isInitialized = true
	NetMsg.ConnectNotifyMatchState(OnNotifyMatchState)
end

return GuideManager
