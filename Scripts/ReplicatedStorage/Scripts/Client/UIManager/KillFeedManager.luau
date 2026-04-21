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

local uiOriginsFolder = replicatedStorage:WaitForChild("UI") :: Folder

local container: Frame? = nil
local entryTemplate: Frame? = nil

local FEED_DURATION = 3
local FADE_TIME = 0.5
local MAX_ITEMS = 5

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
	
	-- Store and hide template
	entryTemplate = template:Clone()
	template:Destroy()
	
	container = feedFrame
	
	NetMsg.ConnectNotifyDead(function(victimId: number, killerId: number?)
		if killerId ~= nil then
			KillFeedManager.AddEntry(killerId, victimId)
		end
	end)
end

function KillFeedManager.AddEntry(killerId: number, victimId: number)
	if not container or not entryTemplate then return end
	
	local killer = players:GetPlayerByUserId(killerId)
	local victim = players:GetPlayerByUserId(victimId)
	
	local killerName = killer and killer.DisplayName or "Player " .. tostring(killerId)
	local victimName = victim and victim.DisplayName or "Player " .. tostring(victimId)
	
	local entry = entryTemplate:Clone()
	entry.Name = "KillEntry"
	
	-- Find the text label. "结构一样" suggests it's a child.
	local label = entry:FindFirstChildOfClass("TextLabel")
	if not label then
		-- Try to find by name if class search fails
		label = entry:FindFirstChild("TextLabel") :: TextLabel?
	end
	
	if not label then
		warn("[KillFeedManager] No TextLabel found in KillEntry template.")
		entry:Destroy()
		return
	end
	
	-- Highlight local player
	local myId = players.LocalPlayer.UserId
	if killerId == myId then
		label.TextColor3 = Color3.fromRGB(80, 255, 80) -- Green
	elseif victimId == myId then
		label.TextColor3 = Color3.fromRGB(255, 80, 80) -- Red
	end
	
	-- Set automated translation
	TranslationTool.CustomAutoLocalizeTextLabel(label, GameTexts.KillFeedDefeated.source, GameTexts.KillFeedDefeated.key, {killerName, victimName})
	
	-- Manage stacking
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
	
	-- Animations (assuming template elements have Transparency = 0)
	-- To genericize, we fade out the group or individual parts
	local tweenInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	
	-- Initial state for fade-in
	entry.BackgroundTransparency = 1
	label.TextTransparency = 1
	local stroke = entry:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Transparency = 1 end
	
	tweenService:Create(entry, tweenInfo, {BackgroundTransparency = 0.6}):Play()
	tweenService:Create(label, tweenInfo, {TextTransparency = 0}):Play()
	if stroke then
		tweenService:Create(stroke, tweenInfo, {Transparency = 0.8}):Play()
	end
	
	-- Auto-hide
	task.delay(FEED_DURATION, function()
		if not entry or entry.Parent == nil then return end
		local fadeTween = tweenService:Create(entry, tweenInfo, {BackgroundTransparency = 1})
		tweenService:Create(label, tweenInfo, {TextTransparency = 1}):Play()
		if stroke then
			tweenService:Create(stroke, tweenInfo, {Transparency = 1}):Play()
		end
		
		fadeTween.Completed:Once(function()
			entry:Destroy()
		end)
		fadeTween:Play()
	end)
end

return KillFeedManager
