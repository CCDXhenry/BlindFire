--!strict
local LeaderboardClient = {}

local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local coreClientScripts = coreScripts:WaitForChild("Client")
local NumberExtension = require(coreSharedScripts:FindFirstChild("NumberExtension"))
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))

local localPlayer = players.LocalPlayer

local categoryFrames: { [string]: ScrollingFrame } = {}
local itemTemplates: { [string]: Frame } = {}
local countdownLabel: TextLabel? = nil
local resetTargetTimestamp: number = 0

local CATEGORY_CONFIG = {
	[GameConfig.LeaderboardCategory.WeeklyKills] = {
		modelName = "Leaderboard_WeeklyKills",
		color = Color3.fromRGB(255, 0, 0), -- 红色
	},
	[GameConfig.LeaderboardCategory.WeeklyWins] = {
		modelName = "Leaderboard_WeeklyWins",
		color = Color3.fromRGB(0, 255, 0), -- 绿色
	},
	[GameConfig.LeaderboardCategory.WeeklyEarnings] = {
		modelName = "Leaderboard_WeeklyEarnings",
		color = Color3.fromRGB(255, 215, 0), -- 黄色
	},
}

-- 客户端兜底计算：按每天 00:00:00 UTC 对齐刷新时间
local function GetFallbackNextRefreshTimestamp(): number
	local nowTimestamp = math.floor(workspace:GetServerTimeNow())
	local dateTable = os.date("!*t", nowTimestamp)
	local secondsToday = dateTable.hour * 3600 + dateTable.min * 60 + dateTable.sec
	local dayStartTimestamp = nowTimestamp - secondsToday
	local refreshInterval = GameConfig.LeaderboardUpdateInterval
	local elapsedSinceDayStart = nowTimestamp - dayStartTimestamp
	local passedIntervals = math.floor(elapsedSinceDayStart / refreshInterval)
	
	local nextTimestamp = dayStartTimestamp + (passedIntervals + 1) * refreshInterval
	-- 如果算出来的时间太近（小于2秒），则锁定到下一个间隔，防止界面闪烁
	if nextTimestamp - nowTimestamp < 2 then
		nextTimestamp += refreshInterval
	end
	return nextTimestamp
end

-- 初始化立牌
local function InitLeaderboards()
	local leaderboardFolder = workspace:WaitForChild("Leaderboard", 5)
	if not leaderboardFolder then
		warn("[LeaderboardClient] workspace.Leaderboard folder not found!")
		return
	end

	for category, config in pairs(CATEGORY_CONFIG) do
		local model = leaderboardFolder:FindFirstChild(config.modelName)
		if not model then
			warn("[LeaderboardClient] Model not found:", config.modelName)
			continue
		end

		-- 遵循用户提供的路径: Model -> Union -> Part(Show) -> SurfaceGui(LeaderboardGui) -> Frame -> ScrollingFrame
		local union = model:FindFirstChild(config.modelName) -- UnionOperation 名字与 Model 名字一致
		local showPart = if union then union:FindFirstChild("Show") else nil
		local gui = if showPart then showPart:FindFirstChild("LeaderboardGui") else nil
		local mainFrame = if gui then gui:FindFirstChild("Frame") else nil
		local scroll = if mainFrame then mainFrame:FindFirstChild("ScrollingFrame") else nil

		if scroll and scroll:IsA("ScrollingFrame") then
			categoryFrames[category] = scroll
			
			-- 模板条目
			local template = scroll:FindFirstChild("Frame")
			if template and template:IsA("Frame") then
				template.Visible = false
				itemTemplates[category] = template
			else
				warn("[LeaderboardClient] Template Frame not found in", config.modelName)
			end
		else
			warn("[LeaderboardClient] ScrollingFrame not found in", config.modelName)
		end
	end

	-- 初始化倒计时显示
	local countdownModel = leaderboardFolder:FindFirstChild("Leaderboard_Countdown")
	local countdownGui = if countdownModel then countdownModel:FindFirstChild("LeaderboardGui") else nil
	local countdownFrame = if countdownGui then countdownGui:FindFirstChild("Frame") else nil
	countdownLabel = if countdownFrame then countdownFrame:FindFirstChild("TextLabel") :: TextLabel else nil

	if not countdownLabel then
		warn("[LeaderboardClient] Leaderboard_Countdown TextLabel not found!")
	end
end

-- 获取到重置目标的秒数
local function GetSecondsToNextWeekReset(): number
	if not resetTargetTimestamp or resetTargetTimestamp <= 0 then
		return 0
	end
	local now = math.floor(workspace:GetServerTimeNow())
	local diff = resetTargetTimestamp - now
	return diff
end

-- 更新倒计时文本
local function UpdateCountdownDisplay()
	if not countdownLabel then return end
	
	local secondsLeft = GetSecondsToNextWeekReset()
	if secondsLeft < 0 then secondsLeft = 0 end
	
	local days = math.floor(secondsLeft / 86400)
	local hours = math.floor((secondsLeft % 86400) / 3600)
	local mins = math.floor((secondsLeft % 3600) / 60)
	local secs = secondsLeft % 60
	
	TranslationTool.CustomAutoLocalizeTextLabel(
		countdownLabel, 
		GameTexts.LeaderboardRefreshCountdown.source, 
		GameTexts.LeaderboardRefreshCountdown.key, 
		{ string.format("%02d", days), string.format("%02d", hours), string.format("%02d", mins), string.format("%02d", secs) }
	)
end

-- 更新某个分类的列表
function LeaderboardClient.UpdateList(category: string, topList: { { userId: number, value: number, name: string } }, resetTimestamp: number?)
	if resetTimestamp and resetTimestamp > 0 then
		resetTargetTimestamp = resetTimestamp
	end
	local scroll = categoryFrames[category]
	local template = itemTemplates[category]
	local config = CATEGORY_CONFIG[category]
	if not scroll or not template or not config then return end

	-- 对象池：获取现有的行
	local existingRows = {}
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") and child ~= template then
			table.insert(existingRows, child)
		end
	end

	for i, data in ipairs(topList) do
		local row = existingRows[i]
		if not row then
			row = template:Clone()
			row.Parent = scroll
		end
		
		row.Name = "Player_" .. i
		row.Visible = true
		row.LayoutOrder = i

		-- 获取子物体
		local rankLabel = row:FindFirstChild("Rank") :: TextLabel
		local nameLabel = row:FindFirstChild("PlayerName") :: TextLabel
		local quantityLabel = row:FindFirstChild("Quantiy") :: TextLabel
		local playerImg = row:FindFirstChild("PlayerImg") :: ImageLabel

		if rankLabel then
			rankLabel.AutoLocalize = false -- 数字不需要翻译
			rankLabel.Text = tostring(i)
		end

		if nameLabel then
			nameLabel.Text = data.name
		end

		if quantityLabel then
			quantityLabel.AutoLocalize = false -- 数字不需要翻译
			quantityLabel.Text = NumberExtension.FormatBigNumberAA(data.value)
			quantityLabel.TextColor3 = config.color -- 设置特定颜色
		end

		if playerImg then
			playerImg.Image = "rbxthumb://type=AvatarHeadShot&id=" .. data.userId .. "&w=100&h=100"
		end
	end
	
	-- 隐藏多余的行
	for i = #topList + 1, #existingRows do
		existingRows[i].Visible = false
	end

	scroll.CanvasSize = UDim2.new(0, 0, 0, #topList * (template.Size.Y.Offset + 8))
end

function LeaderboardClient.Init()
	InitLeaderboards()
	if resetTargetTimestamp <= 0 then
		resetTargetTimestamp = GetFallbackNextRefreshTimestamp()
	end

	NetMsg.ConnectNotifyLeaderboardUpdate(function(category, topList, resetTimestamp)
		LeaderboardClient.UpdateList(category, topList, resetTimestamp)
	end)
	
	NetMsg.ConnectNotifyLeaderboardResetTime(function(resetTimestamp)
		if resetTimestamp > 0 then
			resetTargetTimestamp = resetTimestamp
		end
	end)
	
	-- 启动倒计时刷新
	task.spawn(function()
		while true do
			UpdateCountdownDisplay()
			task.wait(1)
		end
	end)
	
	print("[LeaderboardClient] Initialized with 3 independent boards and countdown")
end

return LeaderboardClient
