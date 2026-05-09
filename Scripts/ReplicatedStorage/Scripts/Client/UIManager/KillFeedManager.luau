--!strict
local KillFeedManager = {}

local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))

local uiOriginsFolder = replicatedStorage:WaitForChild("UI") :: Folder

local container: Frame? = nil
local entryTemplate: Frame? = nil
local botMetaMap: { [string]: { name: string, isBot: boolean } } = {}
local playerMaxHitsMap: { [number]: number } = {}
local playerHitCountMap: { [number]: number } = {}

local FEED_DURATION = 3
local FADE_TIME = 0.5
local MAX_ITEMS = 5

type FeedType = "Hit" | "Kill"

local function GetDisplayNameByPlayerId(playerId: number): string
	local player = players:GetPlayerByUserId(playerId)
	if player ~= nil then
		return player.DisplayName or player.Name
	end
	local botMeta = botMetaMap[tostring(playerId)]
	if botMeta ~= nil and botMeta.isBot then
		return botMeta.name
	end
	return "Player " .. tostring(playerId)
end

local function GetEntryNodes(entry: Frame): (ImageLabel?, ImageLabel?, TextLabel?, TextLabel?, TextLabel?)
	local hitImage = entry:FindFirstChild("HitImage")
	local killImage = entry:FindFirstChild("KillImage")
	local playerName1 = entry:FindFirstChild("PlayerName1")
	local playerName2 = entry:FindFirstChild("PlayerName2")
	local actionText = entry:FindFirstChild("ActionText")

	if hitImage ~= nil and not hitImage:IsA("ImageLabel") then
		hitImage = nil
	end
	if killImage ~= nil and not killImage:IsA("ImageLabel") then
		killImage = nil
	end
	if playerName1 ~= nil and not playerName1:IsA("TextLabel") then
		playerName1 = nil
	end
	if playerName2 ~= nil and not playerName2:IsA("TextLabel") then
		playerName2 = nil
	end
	if actionText ~= nil and not actionText:IsA("TextLabel") then
		actionText = nil
	end

	return hitImage :: ImageLabel?, killImage :: ImageLabel?, playerName1 :: TextLabel?, playerName2 :: TextLabel?, actionText :: TextLabel?
end

local function IsLethalHit(targetPlayerId: number, hitCount: number): boolean
	local maxHits = playerMaxHitsMap[targetPlayerId] or GameConfig.MaxHits
	return hitCount >= maxHits
end

function KillFeedManager.AddTypedEntry(feedType: FeedType, attackerId: number, targetId: number)
	if not container or not entryTemplate then return end
	
	local attacker = players:GetPlayerByUserId(attackerId)
	local target = players:GetPlayerByUserId(targetId)
	local attackerName = if attacker then (attacker.DisplayName or attacker.Name) else GetDisplayNameByPlayerId(attackerId)
	local targetName = if target then (target.DisplayName or target.Name) else GetDisplayNameByPlayerId(targetId)
	
	local entry = entryTemplate:Clone()
	entry.Name = "KillEntry"

	local hitImage, killImage, playerName1, playerName2, actionText = GetEntryNodes(entry)
	if hitImage == nil or killImage == nil or playerName1 == nil or playerName2 == nil then
		warn("[KillFeedManager] KillEntry missing required nodes (HitImage/KillImage/PlayerName1/PlayerName2).")
		entry:Destroy()
		return
	end

	playerName1.Text = attackerName
	playerName2.Text = targetName
	hitImage.Visible = feedType == "Hit"
	killImage.Visible = feedType == "Kill"

	-- 本地化：保留事件动作文案 key，供可选 ActionText 使用
	local textInfo = if feedType == "Hit" then GameTexts.KillFeedHit else GameTexts.KillFeedDefeated
	local localizedText = TranslationTool.FormatByKey(textInfo.source, textInfo.key, { attackerName, targetName })
	entry:SetAttribute("LocalizedFeedText", localizedText)
	if actionText ~= nil then
		TranslationTool.CustomAutoLocalizeTextLabel(actionText, textInfo.source, textInfo.key, { attackerName, targetName })
	end

	local myId = players.LocalPlayer.UserId
	playerName1.TextColor3 = Color3.new(1, 1, 1)
	playerName2.TextColor3 = Color3.new(1, 1, 1)
	if attackerId == myId then
		playerName1.TextColor3 = Color3.fromRGB(80, 255, 80)
	end
	if targetId == myId then
		playerName2.TextColor3 = Color3.fromRGB(80, 255, 80)
	end

	local currentEntries = {}
	for _, child in container:GetChildren() do
		if child.Name == "KillEntry" then
			table.insert(currentEntries, child)
		end
	end
	
	if #currentEntries >= MAX_ITEMS then
		local oldest = currentEntries[1]
		if oldest then
			oldest:Destroy()
		end
	end
	
	entry.LayoutOrder = tick() * 1000
	entry.Parent = container

	local tweenInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	entry.BackgroundTransparency = 1
	local stroke = entry:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Transparency = 1 end

	playerName1.TextTransparency = 1
	playerName2.TextTransparency = 1
	hitImage.ImageTransparency = 1
	killImage.ImageTransparency = 1
	if actionText ~= nil then
		actionText.TextTransparency = 1
	end

	tweenService:Create(entry, tweenInfo, {BackgroundTransparency = 0.6}):Play()
	tweenService:Create(playerName1, tweenInfo, {TextTransparency = 0}):Play()
	tweenService:Create(playerName2, tweenInfo, {TextTransparency = 0}):Play()
	if hitImage.Visible then
		tweenService:Create(hitImage, tweenInfo, {ImageTransparency = 0}):Play()
	end
	if killImage.Visible then
		tweenService:Create(killImage, tweenInfo, {ImageTransparency = 0}):Play()
	end
	if actionText ~= nil then
		tweenService:Create(actionText, tweenInfo, {TextTransparency = 0}):Play()
	end
	if stroke then
		tweenService:Create(stroke, tweenInfo, {Transparency = 0.8}):Play()
	end

	task.delay(FEED_DURATION, function()
		if not entry or entry.Parent == nil then return end
		local fadeTween = tweenService:Create(entry, tweenInfo, {BackgroundTransparency = 1})
		tweenService:Create(playerName1, tweenInfo, {TextTransparency = 1}):Play()
		tweenService:Create(playerName2, tweenInfo, {TextTransparency = 1}):Play()
		tweenService:Create(hitImage, tweenInfo, {ImageTransparency = 1}):Play()
		tweenService:Create(killImage, tweenInfo, {ImageTransparency = 1}):Play()
		if actionText ~= nil then
			tweenService:Create(actionText, tweenInfo, {TextTransparency = 1}):Play()
		end
		if stroke then
			tweenService:Create(stroke, tweenInfo, {Transparency = 1}):Play()
		end
		
		fadeTween.Completed:Once(function()
			entry:Destroy()
		end)
		fadeTween:Play()
	end)
end

function KillFeedManager.AddEntry(killerId: number, victimId: number)
	KillFeedManager.AddTypedEntry("Kill", killerId, victimId)
end

local function OnNotifyBotMetaSync(latestBotMetaMap: { [string]: { name: string, isBot: boolean } })
	botMetaMap = latestBotMetaMap
end

local function OnNotifyHpChanged(playerId: number, hitCount: number, maxHits: number, _hpServerTime: number, _adaptiveDelaySec: number)
	playerHitCountMap[playerId] = hitCount
	playerMaxHitsMap[playerId] = maxHits
end

local function OnNotifyHit(
	targetPlayerId: number,
	fromPlayerId: number,
	_hitDirection: Vector3,
	hitCount: number,
	_bulletId: string,
	_hitPosition: Vector3,
	_hitServerTime: number,
	_adaptiveDelaySec: number,
	_targetRttSec: number,
	_targetJitterSec: number,
	isProtected: boolean
)
	if isProtected then
		return
	end
	local previousHitCount = playerHitCountMap[targetPlayerId]
	if previousHitCount ~= nil and hitCount <= previousHitCount then
		return
	end
	if IsLethalHit(targetPlayerId, hitCount) then
		return
	end
	KillFeedManager.AddTypedEntry("Hit", targetPlayerId, fromPlayerId)
end

local function OnNotifyDead(victimId: number, killerId: number?, _deadServerTime: number, _adaptiveDelaySec: number)
	if killerId == nil then
		return
	end
	KillFeedManager.AddTypedEntry("Kill", victimId, killerId)
end

function KillFeedManager.Init(gameScreenGui: ScreenGui)
	if container then return end
	
	local feedOrigin = uiOriginsFolder:FindFirstChild("KillFeedFrame")
	if not feedOrigin or not feedOrigin:IsA("Frame") then
		warn("[KillFeedManager] KillFeedFrame template not found in UI folder.")
		return
	end
	
	local feedFrame = feedOrigin:Clone()
	feedFrame.Name = "KillFeedFrame_Runtime"
	feedFrame.Parent = gameScreenGui
	
	local template = feedFrame:FindFirstChild("KillEntry")
	if not template or not template:IsA("Frame") then
		warn("[KillFeedManager] KillEntry template not found in KillFeedFrame.")
		feedFrame:Destroy()
		return
	end
	
	entryTemplate = template:Clone()
	template:Destroy()
	container = feedFrame

	UIAdapter.AddAdaptiveFrame(feedFrame, UIAdapter.AdaptiveType.Center)

	NetMsg.ConnectNotifyBotMetaSync(OnNotifyBotMetaSync)
	NetMsg.ConnectNotifyHpChanged(OnNotifyHpChanged)
	NetMsg.ConnectNotifyHit(OnNotifyHit)
	NetMsg.ConnectNotifyDead(OnNotifyDead)
end

return KillFeedManager
