--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local SoundTool = require(coreSharedScripts:FindFirstChild("SoundTool"))
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local GuideManager = require(clientScripts:WaitForChild("GuideManager"))
local NumberExtension = require(coreSharedScripts:WaitForChild("NumberExtension"))
local tweenService: TweenService = game:GetService("TweenService")
local runService: RunService = game:GetService("RunService")
local toolOriginsFolder = replicatedStorage:FindFirstChild("Tools")
local soundFolder = replicatedStorage:WaitForChild("Sounds")
local soundService: SoundService = game:FindFirstChild("SoundService")
local UserInputService = game:GetService("UserInputService")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local players = game:GetService("Players")
local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
if localPlayerInfo == nil then
	return
end

type GameTipTweens = {
	flyUpTween1: Tween,
	stayFlyUpTween1: Tween,
	flyUpTween2: Tween,
	twinkleTween: Tween,
	flyUpTwinkleTween: Tween,
	twinkleTween2: Tween,
}

local GameTipFlyUpTween1Info: TweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.5)
local GameTipStayFlyUpTween1Info: TweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 5)
local GameTipFlyUpTween2Info: TweenInfo = TweenInfo.new(0.5)
local GameTipTwinkleTweenInfo: TweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true)
local GameTipTwinkleTweenInfo2: TweenInfo = TweenInfo.new(
	0.25, -- 单程 0.25s
	Enum.EasingStyle.Linear,
	Enum.EasingDirection.InOut,
	5, -- 重复次数
	true,
	0
)

-- 受击红屏闪烁配置
local DamageFlashInTweenInfo: TweenInfo = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DamageFlashOutTweenInfo: TweenInfo = TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local ShowAddRewardsTipIntervalMin: number = 0.5

local waitingShowAddRewardInfoList: { GameConfig.RewardInfo } = {}
local lastShowedAddRewardsTipTime: number = -1
local isShowRewardFrame: boolean = false
local HideDownTipText: () -> ()

local gameTipFrame: Frame = script.Parent
local GameTipBaseZIndex = 1000

local function ElevateGameTipGuiObject(guiObject: GuiObject)
	if guiObject.ZIndex < GameTipBaseZIndex then
		guiObject.ZIndex = GameTipBaseZIndex + guiObject.ZIndex
	end
end

local function OnGameTipDescendantAdded(descendant: Instance)
	if descendant:IsA("GuiObject") then
		ElevateGameTipGuiObject(descendant)
	end
end

local function EnsureGameTipOnTop()
	ElevateGameTipGuiObject(gameTipFrame)
	for _, descendant in gameTipFrame:GetDescendants() do
		OnGameTipDescendantAdded(descendant)
	end
	gameTipFrame.DescendantAdded:Connect(OnGameTipDescendantAdded)
end

-- 常量定义
local GIFT_CONFIRM_TITLE_COLOR = Color3.fromRGB(0, 255, 0) -- 绿色
local GIFT_REQUEST_TITLE_COLOR = Color3.fromRGB(0, 0, 255) -- 蓝色
local TOP_TIP_DEFAULT_COLOR = Color3.fromRGB(255, 255, 255) -- 白色
local TOP_TIP_SUCCESS_COLOR = Color3.fromRGB(0, 255, 0) -- 绿色
local TOP_TIP_FAILURE_COLOR = Color3.fromRGB(255, 0, 0) -- 红色

local GIFT_POPUP_COUNTDOWN_TIME = 10
local GIFT_TOP_TIP_DURATION = 5
local TOP_TIP_FADE_DURATION = 0.5
local MATCH_PHASE_TOP_TIP_DURATION = 3
local ROUND_OUTCOME_GAME_TIP_TWEEN: number = GameConfig.GameTipTweenType.StayFlyUp
local DefaultPhaseTextScale = 1
local FightingPhaseTextScale = 0.5

--AddRewardTipFrame
local addRewardTipFrameOrigin: Frame = gameTipFrame:FindFirstChild("AddRewardTipFrame") :: Frame
addRewardTipFrameOrigin.Parent = nil
local addRewardsTipTweens: { [Frame]: { tween1: Tween, tween2: Tween } } = {}
local addRewardTipFramePool: { Frame } = {}
local getCoinSound: Sound = (soundFolder:FindFirstChild("GetCoinSound") :: Sound):Clone()
getCoinSound.Parent = soundService
local killSoundOrigin = soundFolder:FindFirstChild("KillSound")
local victorySoundOrigin = soundFolder:FindFirstChild("VictorySound")
if killSoundOrigin == nil then
	warn("[GameTipFrame] KillSound not found in ReplicatedStorage.Sounds.")
end
if victorySoundOrigin == nil then
	warn("[GameTipFrame] VictorySound not found in ReplicatedStorage.Sounds.")
end
--GameTipText
local gameTipTextOrigin: TextLabel = gameTipFrame:FindFirstChild("GameTipText") :: TextLabel
gameTipTextOrigin.Parent = nil
local gameTipTextsTweens: { [TextLabel]: GameTipTweens } = {}
local gameTipTextsPool: { TextLabel } = {}

--PopUpTipFrame
local popUpTipFrame: Frame? = gameTipFrame:FindFirstChild("PopUpTipFrame") :: Frame
local popUpYesButton: TextButton?
local popUpNoButton: TextButton?
local popUpTitleLabel: TextLabel?
local popUpTipInfoLabel: TextLabel?
local popUpTimeLabel: TextLabel?

local activePopUpConnectionYes: RBXScriptConnection?
local activePopUpConnectionNo: RBXScriptConnection?
local popUpCountdownCoroutine: thread?

if popUpTipFrame then
	popUpYesButton = popUpTipFrame:FindFirstChild("YesButton") :: TextButton
	popUpNoButton = popUpTipFrame:FindFirstChild("NoButton") :: TextButton
	popUpTitleLabel = popUpTipFrame:FindFirstChild("TitleLabel") :: TextLabel
	popUpTipInfoLabel = popUpTipFrame:FindFirstChild("TipInfoLabel") :: TextLabel
	if popUpYesButton then
		popUpTimeLabel = popUpYesButton:FindFirstChild("TimeLabel") :: TextLabel
	end
end

local maskImage: ImageLabel? = gameTipFrame:FindFirstChild("MaskImage") :: ImageLabel
if maskImage then
	maskImage.Visible = false
end

--TopTipText
local topTipText: TextLabel? = gameTipFrame:FindFirstChild("TopTipText") :: TextLabel
local topTipFadeCoroutine: thread?
local topTipFadeTween: Tween?
local topTipStrokeFadeTween: Tween?
local downTipText: TextLabel? = gameTipFrame:FindFirstChild("DownTipText", true) :: TextLabel?
local downTipTween: Tween? = nil
local downTipFadeTween: Tween? = nil
local downTipStrokeFadeTween: Tween? = nil
local DOWN_TIP_PULSE_TWEEN_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local DOWN_TIP_PULSE_MIN_SCALE = 0.9
local DOWN_TIP_TEXT_COLOR = Color3.fromRGB(0, 255, 0)
local ShowDownTipTextWithScaleFade: (textSource: string, key: string?, args: { string }?) -> ()

local EARTHQUAKE_WARNING_COLOR = Color3.fromRGB(255, 210, 0)
local EARTHQUAKE_DANGER_COLOR = Color3.fromRGB(255, 60, 60)

local countdownText: TextLabel? = gameTipFrame:FindFirstChild("CountdownText") :: TextLabel
if countdownText == nil and topTipText ~= nil then
	local label = Instance.new("TextLabel")
	label.Name = "CountdownText"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.new(0, 140, 0, 80)
	label.Position = UDim2.new(0.5, 0, 0.4, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = EARTHQUAKE_WARNING_COLOR
	label.Text = ""
	label.Visible = false
	label.Parent = gameTipFrame
	countdownText = label
end

-- DamageOverlay
local damageOverlay: Frame? = gameTipFrame:FindFirstChild("DamageOverlay") :: Frame?
local damageFlashInTween: Tween?
local damageFlashOutTween: Tween?

if damageOverlay then
	damageOverlay.Visible = false
	damageOverlay.BackgroundTransparency = 1
	damageFlashInTween = tweenService:Create(damageOverlay, DamageFlashInTweenInfo, { BackgroundTransparency = 0.5 }) -- 设置闪烁时的最大透明度
	damageFlashOutTween = tweenService:Create(damageOverlay, DamageFlashOutTweenInfo, { BackgroundTransparency = 1 })
	local resolvedDamageFlashInTween = damageFlashInTween :: Tween
	local resolvedDamageFlashOutTween = damageFlashOutTween :: Tween

	resolvedDamageFlashInTween.Completed:Connect(function()
		resolvedDamageFlashOutTween:Play()
	end)

	resolvedDamageFlashOutTween.Completed:Connect(function()
		damageOverlay.Visible = false
	end)
end

local function PlayDamageFlash(hitDirection: Vector3?)
	if not damageOverlay or not damageFlashInTween then
		return
	end

	if hitDirection then
		local camera = workspace.CurrentCamera
		if camera then
			-- 攻击来源方向 (从受害者指向攻击者)
			local sourceDir = -hitDirection.Unit
			-- 转为相机本地坐标系
			local relativeDir = camera.CFrame:VectorToObjectSpace(sourceDir)
			-- 只关心水平面上的角度 (X, Z)
			-- atan2(X, -Z): 0 是前方, 90 是右方, -90 是左方
			local angleRad = math.atan2(relativeDir.X, -relativeDir.Z)
			local angleDeg = math.deg(angleRad)

			local gradient = damageOverlay:FindFirstChildOfClass("UIGradient")
			if gradient then
				-- UIGradient.Rotation = 0 时是左右渐变 (左红右透)
				-- 我们需要把 0度(前方) 映射到 90度(上方为红)
				gradient.Rotation = angleDeg + 90
			end
		end
	end

	damageOverlay.Visible = true
	damageFlashInTween:Play()
end
local function PlayPopTween(ui: ImageLabel, popTime: number, maxScale: number, hideOnMax: boolean)
	ui.ImageTransparency = 0
	ui.Visible = true
	local uiScale: UIScale = ui:FindFirstChild("UIScale") :: UIScale
	uiScale.Scale = 0

	local popTween = tweenService:Create(uiScale, TweenInfo.new(popTime * 0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = maxScale })

	local backTween = tweenService:Create(uiScale, TweenInfo.new(popTime * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = maxScale })

	popTween.Completed:Once(function()
		if hideOnMax then
			ui.Visible = false
			uiScale.Scale = 0
		end
		backTween:Play()
	end)

	popTween:Play()
end

local function ShowGameTip(tipContentSource: string, tweenType: number, tipContentKey: string?, tipContentArgs: { string }?, textColor: Color3?)
	local gameTipText: TextLabel = table.remove(gameTipTextsPool) or gameTipTextOrigin:Clone()
	if textColor then
		gameTipText.TextColor3 = textColor
	else
		gameTipText.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
	local gameTipTextTweens: GameTipTweens = gameTipTextsTweens[gameTipText]
	if gameTipTextTweens == nil then
		local gameTextStroke: UIStroke = gameTipText:FindFirstChild("UIStroke") :: UIStroke
		gameTipText:GetPropertyChangedSignal("TextTransparency"):Connect(function()
			gameTextStroke.Transparency = gameTipText.TextTransparency
		end)
		local flyUpTween1: Tween = tweenService:Create(gameTipText, GameTipFlyUpTween1Info, { Position = UDim2.new(0.5, 0, 0.5, -300) })
		local stayFlyUpTween1: Tween = tweenService:Create(gameTipText, GameTipStayFlyUpTween1Info, { Position = UDim2.new(0.5, 0, 0.5, -300) })
		local flyUpTwinkleTween: Tween = tweenService:Create(gameTipText, GameTipFlyUpTween1Info, { Position = UDim2.new(0.5, 0, 0.5, -300) })
		local flyUpTween2: Tween = tweenService:Create(gameTipText, GameTipFlyUpTween2Info, { TextTransparency = 1 })
		local twinkleTween2 = tweenService:Create(gameTipText, GameTipTwinkleTweenInfo2, { TextTransparency = 1 })
		flyUpTween1.Completed:Connect(function(playbackState: Enum.PlaybackState)
			flyUpTween2:Play()
		end)
		stayFlyUpTween1.Completed:Connect(function(playbackState: Enum.PlaybackState)
			flyUpTween2:Play()
		end)
		flyUpTween2.Completed:Connect(function(playbackState: Enum.PlaybackState)
			gameTipText.Parent = nil
			table.insert(gameTipTextsPool, gameTipText)
		end)
		local twinkleTween: Tween = tweenService:Create(gameTipText, GameTipTwinkleTweenInfo, { TextTransparency = 0 })
		twinkleTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
			gameTipText.Parent = nil
			table.insert(gameTipTextsPool, gameTipText)
		end)
		twinkleTween2.Completed:Connect(function(playbackState: Enum.PlaybackState)
			gameTipText.Parent = nil
			table.insert(gameTipTextsPool, gameTipText)
		end)
		flyUpTwinkleTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
			twinkleTween2:Play()
		end)

		gameTipTextTweens = {
			flyUpTween1 = flyUpTween1,
			stayFlyUpTween1 = stayFlyUpTween1,
			flyUpTween2 = flyUpTween2,
			twinkleTween = twinkleTween,
			flyUpTwinkleTween = flyUpTwinkleTween,
			twinkleTween2 = twinkleTween2,
		}
	end
	gameTipText.Parent = gameTipFrame
	local absolutePosition: Vector2 = gameTipText.AbsolutePosition
	if tweenType == GameConfig.GameTipTweenType.FlyUp then
		gameTipText.Position = UDim2.new(0.5, 0, 0.5, 0)
		gameTipText.TextTransparency = 0
		gameTipTextTweens.flyUpTween1:Play()
	elseif tweenType == GameConfig.GameTipTweenType.Twinkle then
		gameTipText.Position = UDim2.new(0.5, 0, 0.5, 0)
		gameTipText.TextTransparency = 1
		gameTipTextTweens.twinkleTween:Play()
	elseif tweenType == GameConfig.GameTipTweenType.StayFlyUp then
		gameTipText.Position = UDim2.new(0.5, 0, 0.5, 0)
		gameTipText.TextTransparency = 0
		gameTipTextTweens.stayFlyUpTween1:Play()
	elseif tweenType == GameConfig.GameTipTweenType.FlyUpTwinkle then
		gameTipText.Position = UDim2.new(0.5, 0, 0.5, 0)
		gameTipText.TextTransparency = 0
		gameTipTextTweens.flyUpTwinkleTween:Play()
	elseif tweenType == GameConfig.GameTipTweenType.Twinkle2 then
		gameTipText.Position = UDim2.new(0.5, 0, 0.5, 110)
		gameTipText.TextTransparency = 0
		gameTipTextTweens.twinkleTween2:Play()
	end
	TranslationTool.CustomAutoLocalizeTextLabel(gameTipText, tipContentSource, tipContentKey, tipContentArgs)
end

local function ShowAddRewardsTip(rewardIcon: string, rewardCount: number)
	local addRewardTipFrame: Frame = table.remove(addRewardTipFramePool) or addRewardTipFrameOrigin:Clone()
	local transparencyValue: NumberValue = addRewardTipFrame:FindFirstChild("Transparency") :: NumberValue
	local rewardIconImage: ImageLabel = addRewardTipFrame:FindFirstChild("RewardIconImage") :: ImageLabel
	rewardIconImage.Image = rewardIcon
	local rewardCountText: TextLabel = addRewardTipFrame:FindFirstChild("RewardCountText") :: TextLabel
	rewardCountText.Text = "+" .. NumberExtension.FormatBigNumberAA(rewardCount)
	local addRewardsTipTweens: { tween1: Tween, tween2: Tween } = addRewardsTipTweens[addRewardTipFrame]
	if addRewardsTipTweens == nil then
		local rewardCountTextStroke: UIStroke = rewardCountText:FindFirstChild("UIStroke") :: UIStroke
		transparencyValue.Changed:Connect(function(value: number)
			rewardIconImage.ImageTransparency = value
			rewardCountText.TextTransparency = value
			rewardCountTextStroke.Transparency = value
		end)
		local tween1: Tween = tweenService:Create(addRewardTipFrame, GameTipFlyUpTween1Info, { Position = UDim2.new(0.5, 0, 0.5, 0) })
		local tween2: Tween = tweenService:Create(transparencyValue, GameTipFlyUpTween2Info, { Value = 1 })
		tween1.Completed:Connect(function(playbackState: Enum.PlaybackState)
			tween2:Play()
		end)
		tween2.Completed:Connect(function(playbackState: Enum.PlaybackState)
			addRewardTipFrame.Parent = nil
			table.insert(addRewardTipFramePool, addRewardTipFrame)
		end)
		addRewardsTipTweens = { tween1 = tween1, tween2 = tween2 }
	end
	addRewardTipFrame.Parent = gameTipFrame
	addRewardTipFrame.Position = UDim2.new(0.5, 0, 0.8, 0)
	transparencyValue.Value = 0
	addRewardsTipTweens.tween1:Play()
	SoundTool.PlayDesignatedSoundEffect(getCoinSound)
end

local function OnRenderStepped(deltaTime: number)
	local nowTime: number = time()
	--获得奖励提示
	if #waitingShowAddRewardInfoList > 0 and (lastShowedAddRewardsTipTime == -1 or nowTime - lastShowedAddRewardsTipTime >= ShowAddRewardsTipIntervalMin) then
		local rewardInfo: GameConfig.RewardInfo? = table.remove(waitingShowAddRewardInfoList, 1)
		if rewardInfo ~= nil then
			if rewardInfo.rewardType == GameConfig.RewardType.Currency then
				local currencyType: number? = tonumber(rewardInfo.rewardId)
				if currencyType == GameConfig.CurrencyType.Coin then
					ShowAddRewardsTip(GameConfig.CoinIconImage, rewardInfo.rewardCount)
				end
			end
		end
		lastShowedAddRewardsTipTime = nowTime
	end

	if GuideManager.ShouldShowSpaceGuide() then
		if downTipText == nil or not downTipText.Visible then
			ShowDownTipTextWithScaleFade(GameTexts.GuideTutorialFireBySpace.source, GameTexts.GuideTutorialFireBySpace.key, nil)
		end
	elseif downTipText ~= nil and downTipText.Visible then
		HideDownTipText()
	end
end

local function OnShowAddRewardsTip(rewardInfoList: { GameConfig.RewardInfo })
	table.move(rewardInfoList, 1, #rewardInfoList, #waitingShowAddRewardInfoList + 1, waitingShowAddRewardInfoList)
end

--显示游戏提示
local function OnShowGameTip(tipContentSource: string, tweenType: number, tipContentKey: string?, tipContentArgs: { string }?, textColor: Color3?)
	ShowGameTip(tipContentSource, tweenType, tipContentKey, tipContentArgs, textColor)
end

local function SetMaskVisible(isVisible: boolean)
	if maskImage then
		maskImage.Visible = isVisible
	end
end

local function HidePopUpTipFrame()
	if popUpTipFrame then
		popUpTipFrame.Visible = false
	end
	SetMaskVisible(false)
	if activePopUpConnectionYes then
		activePopUpConnectionYes:Disconnect()
		activePopUpConnectionYes = nil
	end
	if activePopUpConnectionNo then
		activePopUpConnectionNo:Disconnect()
		activePopUpConnectionNo = nil
	end
	if popUpCountdownCoroutine and coroutine.status(popUpCountdownCoroutine) ~= "dead" and popUpCountdownCoroutine ~= coroutine.running() then
		coroutine.close(popUpCountdownCoroutine)
		popUpCountdownCoroutine = nil
	end
end

local function ApplyCountdownFormatToLabel(targetLabel: TextLabel, seconds: number)
	local secondsText = tostring(seconds)
	TranslationTool.CustomAutoLocalizeTextLabel(
		targetLabel,
		string.gsub(GameTexts.CountdownFormat.source, "{1}", secondsText),
		GameTexts.CountdownFormat.key,
		{ secondsText }
	)
end

local function ApplyPhaseTextScale(targetLabel: TextLabel?, scaleValue: number)
	if targetLabel == nil then
		return
	end
	local scaleNode = targetLabel:FindFirstChildOfClass("UIScale")
	if scaleNode == nil then
		local createdScaleNode = Instance.new("UIScale")
		createdScaleNode.Parent = targetLabel
		scaleNode = createdScaleNode
	end
	local resolvedScaleNode = scaleNode :: UIScale
	resolvedScaleNode.Scale = scaleValue
end

local function ApplyMatchStateTextScale(matchState: GameConfig.MatchState)
	local targetScale = if matchState == GameConfig.MatchState.Fighting then FightingPhaseTextScale else DefaultPhaseTextScale
	ApplyPhaseTextScale(topTipText, targetScale)
	ApplyPhaseTextScale(countdownText, targetScale)
end

local function ApplyFightingTopTipCountdownText(countdown: number)
	if topTipText == nil then
		return
	end
	topTipText.Visible = true
	topTipText.TextColor3 = TOP_TIP_SUCCESS_COLOR
	topTipText.TextTransparency = 0
	local stroke = topTipText:FindFirstChild("UIStroke") :: UIStroke?
	if stroke ~= nil then
		stroke.Transparency = 0
	end
	local countdownSeconds = math.max(countdown, 0)
	local countdownSource = string.gsub(GameTexts.CountdownFormat.source, "{1}", tostring(countdownSeconds))
	topTipText.Text = string.format("%s %s", GameTexts.MatchPhaseFighting.source, countdownSource)
end

local function StartPopUpCountdown(targetTimeLabel: TextLabel?, totalSeconds: number, timeoutCallback: () -> ())
	if targetTimeLabel == nil then
		return
	end
	if popUpCountdownCoroutine and coroutine.status(popUpCountdownCoroutine) ~= "dead" and popUpCountdownCoroutine ~= coroutine.running() then
		coroutine.close(popUpCountdownCoroutine)
	end
	if totalSeconds < 0 then
		timeoutCallback()
		return
	end
	local newCoroutine = coroutine.create(function()
		if totalSeconds == 0 then
			ApplyCountdownFormatToLabel(targetTimeLabel, 0)
			timeoutCallback()
			return
		end
		for i = totalSeconds, 1, -1 do
			ApplyCountdownFormatToLabel(targetTimeLabel, i)
			task.wait(1)
		end
		ApplyCountdownFormatToLabel(targetTimeLabel, 0)
		timeoutCallback()
	end)
	popUpCountdownCoroutine = newCoroutine
	coroutine.resume(newCoroutine)
end

local function OnShowTopTipText(textSource: string, color: Color3, duration: number, args: { string }?, key: string?)
	if not topTipText then
		return
	end
	if topTipFadeTween then
		topTipFadeTween:Cancel()
		topTipFadeTween = nil
	end
	if topTipStrokeFadeTween then
		topTipStrokeFadeTween:Cancel()
		topTipStrokeFadeTween = nil
	end
	if topTipFadeCoroutine ~= nil and coroutine.status(topTipFadeCoroutine) ~= "dead" and topTipFadeCoroutine ~= coroutine.running() then
		pcall(coroutine.close, topTipFadeCoroutine)
	end
	topTipFadeCoroutine = nil

	topTipText.Visible = true
	topTipText.TextColor3 = color
	topTipText.TextTransparency = 0

	local stroke = topTipText:FindFirstChild("UIStroke") :: UIStroke
	if stroke then
		stroke.Transparency = 0
	end

	TranslationTool.CustomAutoLocalizeTextLabel(topTipText, textSource, key, args)

	local newCoroutine = coroutine.create(function()
		task.wait(duration)
		if not topTipText or topTipText.Parent == nil then
			return
		end
		local tween = tweenService:Create(topTipText, TweenInfo.new(TOP_TIP_FADE_DURATION), { TextTransparency = 1 })
		topTipFadeTween = tween
		tween:Play()
		if stroke then
			local strokeTween = tweenService:Create(stroke, TweenInfo.new(TOP_TIP_FADE_DURATION), { Transparency = 1 })
			topTipStrokeFadeTween = strokeTween
			strokeTween:Play()
		end
		tween.Completed:Wait()
		topTipFadeTween = nil
		topTipStrokeFadeTween = nil
		topTipText.Visible = false
	end)
	topTipFadeCoroutine = newCoroutine
	coroutine.resume(newCoroutine)
end

function ShowDownTipTextWithScaleFade(textSource: string, key: string?, args: { string }?)
	if downTipText == nil then
		return
	end
	local targetDownTipText = downTipText
	if downTipTween ~= nil then
		downTipTween:Cancel()
		downTipTween = nil
	end
	if downTipFadeTween ~= nil then
		downTipFadeTween:Cancel()
		downTipFadeTween = nil
	end
	if downTipStrokeFadeTween ~= nil then
		downTipStrokeFadeTween:Cancel()
		downTipStrokeFadeTween = nil
	end

	targetDownTipText.Visible = true
	targetDownTipText.TextColor3 = DOWN_TIP_TEXT_COLOR
	targetDownTipText.TextTransparency = 0
	local downTipStroke = targetDownTipText:FindFirstChild("UIStroke") :: UIStroke?
	if downTipStroke ~= nil then
		downTipStroke.Transparency = 0
	end

	local scaleNode = targetDownTipText:FindFirstChildOfClass("UIScale")
	if scaleNode == nil then
		local createdScaleNode = Instance.new("UIScale")
		createdScaleNode.Parent = targetDownTipText
		scaleNode = createdScaleNode
	end
	local resolvedScaleNode = scaleNode :: UIScale
	resolvedScaleNode.Scale = 1

	TranslationTool.CustomAutoLocalizeTextLabel(targetDownTipText, textSource, key, args)

	local pulseTween = tweenService:Create(
		resolvedScaleNode,
		DOWN_TIP_PULSE_TWEEN_INFO,
		{ Scale = DOWN_TIP_PULSE_MIN_SCALE }
	)
	downTipTween = pulseTween
	pulseTween:Play()
end

function HideDownTipText()
	if downTipText == nil then
		return
	end
	if downTipTween ~= nil then
		downTipTween:Cancel()
		downTipTween = nil
	end
	if downTipFadeTween ~= nil then
		downTipFadeTween:Cancel()
		downTipFadeTween = nil
	end
	if downTipStrokeFadeTween ~= nil then
		downTipStrokeFadeTween:Cancel()
		downTipStrokeFadeTween = nil
	end
	downTipText.Visible = false
end

local lastNotifiedMatchState: GameConfig.MatchState? = nil

local function GetMatchPhaseTipEntry(matchState: GameConfig.MatchState): ({ key: string, source: string }, Color3)
	if matchState == GameConfig.MatchState.InLobby then
		return GameTexts.MatchPhaseInLobby, TOP_TIP_DEFAULT_COLOR
	elseif matchState == GameConfig.MatchState.MatchCountdown then
		return GameTexts.MatchPhaseMatchCountdown, EARTHQUAKE_WARNING_COLOR
	elseif matchState == GameConfig.MatchState.GameStartCountdown then
		return GameTexts.MatchPhaseGameStartCountdown, EARTHQUAKE_WARNING_COLOR
	elseif matchState == GameConfig.MatchState.Fighting then
		return GameTexts.MatchPhaseFighting, TOP_TIP_SUCCESS_COLOR
	end
	return GameTexts.MatchPhaseInLobby, TOP_TIP_DEFAULT_COLOR
end

-- 阶段顶栏停留时长与对应阶段倒计时一致（含战斗 RoundFightDuration / 服务器 remain）
local function GetPhaseTopTipDuration(matchState: GameConfig.MatchState, countdown: number): number
	if matchState == GameConfig.MatchState.MatchCountdown then
		if countdown > 0 then
			return countdown
		end
		return GameConfig.MatchCountdown
	elseif matchState == GameConfig.MatchState.GameStartCountdown then
		if countdown > 0 then
			return countdown
		end
		return GameConfig.RoundStartCountdown
	elseif matchState == GameConfig.MatchState.Fighting then
		if countdown > 0 then
			return countdown
		end
		return GameConfig.RoundFightDuration
	elseif matchState == GameConfig.MatchState.InLobby then
		return 999999
	end
	return MATCH_PHASE_TOP_TIP_DURATION
end

local function UserIdInList(userIds: { number }, userId: number): boolean
	for _, id in userIds do
		if id == userId then
			return true
		end
	end
	return false
end

local function OnNotifyDeadForRoundTip(playerId: number)
	if playerId ~= players.LocalPlayer.UserId then
		return
	end
	ShowGameTip(GameTexts.RoundDefeat.source, ROUND_OUTCOME_GAME_TIP_TWEEN, GameTexts.RoundDefeat.key, nil, TOP_TIP_FAILURE_COLOR)
end

local function OnNotifyRoundOutcome(endReason: GameConfig.RoundEndReason, aliveUserIds: { number })
	local myId: number = players.LocalPlayer.UserId
	if endReason == GameConfig.RoundEndReason.LastStanding and #aliveUserIds == 0 then
		ShowGameTip(GameTexts.RoundNoSurvivors.source, ROUND_OUTCOME_GAME_TIP_TWEEN, GameTexts.RoundNoSurvivors.key, nil, TOP_TIP_DEFAULT_COLOR)
		return
	end
	if not UserIdInList(aliveUserIds, myId) then
		return
	end
	if endReason == GameConfig.RoundEndReason.LastStanding and #aliveUserIds == 1 then
		ShowGameTip(GameTexts.RoundVictory.source, ROUND_OUTCOME_GAME_TIP_TWEEN, GameTexts.RoundVictory.key, nil, TOP_TIP_SUCCESS_COLOR)
		if victorySoundOrigin ~= nil and victorySoundOrigin:IsA("Sound") then
			SoundTool.PlayGlobalSoundEffect(victorySoundOrigin, false)
		end
	elseif endReason == GameConfig.RoundEndReason.TimeExpired then
		if #aliveUserIds == 1 then
			ShowGameTip(GameTexts.RoundVictory.source, ROUND_OUTCOME_GAME_TIP_TWEEN, GameTexts.RoundVictory.key, nil, TOP_TIP_SUCCESS_COLOR)
			if victorySoundOrigin ~= nil and victorySoundOrigin:IsA("Sound") then
				SoundTool.PlayGlobalSoundEffect(victorySoundOrigin, false)
			end
		else
			ShowGameTip(GameTexts.RoundTimeDraw.source, ROUND_OUTCOME_GAME_TIP_TWEEN, GameTexts.RoundTimeDraw.key, nil, TOP_TIP_DEFAULT_COLOR)
		end
	end
end

local function OnNotifyDeadForKillSound(_playerId: number, killerId: number?)
	if killerId ~= players.LocalPlayer.UserId then
		return
	end
	if killSoundOrigin ~= nil and killSoundOrigin:IsA("Sound") then
		SoundTool.PlayGlobalSoundEffect(killSoundOrigin, false)
	end
end

local function OnNotifyMatchState(matchState: GameConfig.MatchState, countdown: number)
	ApplyMatchStateTextScale(matchState)

	if matchState ~= lastNotifiedMatchState then
		local entry, tipColor = GetMatchPhaseTipEntry(matchState)
		local tipDuration = GetPhaseTopTipDuration(matchState, countdown)
		OnShowTopTipText(entry.source, tipColor, tipDuration, nil, entry.key)
		lastNotifiedMatchState = matchState
	end

	if matchState == GameConfig.MatchState.Fighting then
		if countdownText ~= nil then
			countdownText.Visible = false
		end
		ApplyFightingTopTipCountdownText(countdown)
		return
	end

	if countdownText == nil then
		return
	end
	if matchState == GameConfig.MatchState.MatchCountdown or matchState == GameConfig.MatchState.GameStartCountdown then
		if countdown > 0 then
			countdownText.Visible = true
			countdownText.TextColor3 = EARTHQUAKE_WARNING_COLOR
			ApplyCountdownFormatToLabel(countdownText, countdown)
		else
			countdownText.Visible = false
		end
	else
		countdownText.Visible = false
	end
end

EnsureGameTipOnTop()
UIAdapter.AddAdaptiveFrame(gameTipFrame, UIAdapter.AdaptiveType.FullScreen)

runService:BindToRenderStep("GameTipFrame.RenderStepped", Enum.RenderPriority.Camera.Value + 2, OnRenderStepped)

ClientMsg.ConnectShowGameTip(OnShowGameTip)
ClientMsg.ConnectShowAddRewardsTip(OnShowAddRewardsTip)
ClientMsg.ConnectShowTopTipText(OnShowTopTipText)
NetMsg.ConnectNotifyMatchState(OnNotifyMatchState)
NetMsg.ConnectNotifyRoundOutcome(OnNotifyRoundOutcome)
NetMsg.ConnectNotifyDead(OnNotifyDeadForRoundTip)
NetMsg.ConnectNotifyDead(OnNotifyDeadForKillSound)

NetMsg.ConnectNotifyHit(function(targetPlayerId, fromPlayerId, hitDirection, hitCount)
	if targetPlayerId == players.LocalPlayer.UserId then
		PlayDamageFlash(hitDirection)
	end
end)
