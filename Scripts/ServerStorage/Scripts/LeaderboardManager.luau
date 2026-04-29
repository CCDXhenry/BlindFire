--!strict
local LeaderboardManager = {}

local dataStoreService = game:GetService("DataStoreService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local serverStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")

local LOG_PREFIX = "[LeaderboardManager]"
local SlowOperationWarnThresholdSeconds: number = 1

local httpService = game:GetService("HttpService")

-- 缓存每个分类的前20名
local topLists: { [string]: { { userId: number, value: number, name: string } } } = {}
local usernameCache: { [number]: string } = {}
local lastLeaderboardHashes: { [string]: string } = {}
-- 下次排行榜刷新时间戳（UTC 秒）
local nextRefreshTimestamp: number = 0

local function WarnIfSlow(operationName: string, startClock: number)
	local elapsed = os.clock() - startClock
	if elapsed >= SlowOperationWarnThresholdSeconds then
		warn(string.format("%s SlowOperation name=%s elapsed=%.2fs", LOG_PREFIX, operationName, elapsed))
	end
end

-- 获取本周 Key
local function GetWeeklyKey(category: string): string
	return category .. "_" .. os.date("!%Y_%W")
end

-- 获取 OrderedDataStore
local function GetOrderedDataStore(category: string): OrderedDataStore
	return dataStoreService:GetOrderedDataStore(GetWeeklyKey(category))
end

-- 获取到下周一 00:00:00 UTC 的时间戳
local function GetNextWeekResetTimestamp(): number
	local now = math.floor(workspace:GetServerTimeNow())
	local dateTable = os.date("!*t", now)
	
	-- wday: 1=Sunday, 2=Monday, ..., 7=Saturday
	-- 我们需要找到下一个周一 (wday = 2)
	local daysToMonday = (2 - dateTable.wday + 7) % 7
	if daysToMonday == 0 then
		-- 如果今天就是周一，我们需要锁定到下个周一
		daysToMonday = 7
	end
	
	-- 计算今天 00:00:00 UTC 的时间戳
	local secondsToday = dateTable.hour * 3600 + dateTable.min * 60 + dateTable.sec
	local dayStart = now - secondsToday
	
	-- 返回下周一的时间戳
	return dayStart + (daysToMonday * 24 * 60 * 60)
end

-- 获取下次排行榜刷新时间戳
local function GetAlignedNextRefreshTimestamp(nowTimestamp: number): number
	local dateTable = os.date("!*t", nowTimestamp)
	local secondsToday = dateTable.hour * 3600 + dateTable.min * 60 + dateTable.sec
	local dayStartTimestamp = nowTimestamp - secondsToday
	local refreshInterval = GameConfig.LeaderboardUpdateInterval
	local elapsedSinceDayStart = nowTimestamp - dayStartTimestamp
	local passedIntervals = math.floor(elapsedSinceDayStart / refreshInterval)
	return dayStartTimestamp + (passedIntervals + 1) * refreshInterval
end

local function GetNextRefreshTimestamp(): number
	local now = math.floor(workspace:GetServerTimeNow())
	if nextRefreshTimestamp > now then
		return nextRefreshTimestamp
	end
	return GetAlignedNextRefreshTimestamp(now)
end


-- 检查玩家是否需要重置周统计
function LeaderboardManager.CheckWeeklyReset(player: Player)
	local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then return end

	local currentWeek = os.date("!%Y_%W")
	if playerInfo.weeklyStats == nil then
		playerInfo.weeklyStats = {
			kills = 0,
			wins = 0,
			earnings = 0,
			lastResetWeek = currentWeek,
		}
		playerInfo.playerInfoChanged = true
	end

	if playerInfo.weeklyStats.lastResetWeek ~= currentWeek then
		print(string.format("%s Resetting weekly stats for player %d (Last: %s, Current: %s)", 
			LOG_PREFIX, player.UserId, playerInfo.weeklyStats.lastResetWeek, currentWeek))
		
		playerInfo.weeklyStats.kills = 0
		playerInfo.weeklyStats.wins = 0
		playerInfo.weeklyStats.earnings = 0
		playerInfo.weeklyStats.lastResetWeek = currentWeek
		playerInfo.playerInfoChanged = true
	end
end

-- 增加统计数值
function LeaderboardManager.AddStat(player: Player, category: string, amount: number)
	LeaderboardManager.CheckWeeklyReset(player)
	
	local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then return end

	if category == GameConfig.LeaderboardCategory.WeeklyKills then
		playerInfo.weeklyStats.kills += amount
	elseif category == GameConfig.LeaderboardCategory.WeeklyWins then
		playerInfo.weeklyStats.wins += amount
	elseif category == GameConfig.LeaderboardCategory.WeeklyEarnings then
		playerInfo.weeklyStats.earnings += amount
	end
	
	playerInfo.leaderboardChanges = playerInfo.leaderboardChanges or {}
	playerInfo.leaderboardChanges[category] = true
	playerInfo.playerInfoChanged = true
end

-- 保存玩家的排行榜统计数据（批量同步，避免节流）
function LeaderboardManager.SavePlayerStats(player: Player)
	local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.leaderboardChanges == nil then return end

	for category, _ in pairs(playerInfo.leaderboardChanges) do
		local value = 0
		if category == GameConfig.LeaderboardCategory.WeeklyKills then
			value = playerInfo.weeklyStats.kills
		elseif category == GameConfig.LeaderboardCategory.WeeklyWins then
			value = playerInfo.weeklyStats.wins
		elseif category == GameConfig.LeaderboardCategory.WeeklyEarnings then
			value = playerInfo.weeklyStats.earnings
		end
		LeaderboardManager.UpdateToOrderedDataStore(player, category, value)
	end
	playerInfo.leaderboardChanges = nil
end

-- 更新到 OrderedDataStore
function LeaderboardManager.UpdateToOrderedDataStore(player: Player, category: string, value: number)
	local ods = GetOrderedDataStore(category)
	task.spawn(function()
		local updateStartClock = os.clock()
		local success, err = pcall(function()
			ods:SetAsync(tostring(player.UserId), math.floor(value))
		end)
		if not success then
			warn(string.format("%s Failed to update OrderedDataStore for %d in %s: %s", 
				LOG_PREFIX, player.UserId, category, err))
		end
		WarnIfSlow("UpdateToOrderedDataStore", updateStartClock)
	end)
end

-- 刷新排行榜缓存并同步给客户端
function LeaderboardManager.RefreshLeaderboard(category: string)
	local ods = GetOrderedDataStore(category)
	task.spawn(function()
		local refreshStartClock = os.clock()
		local success, pages = pcall(function()
			return ods:GetSortedAsync(false, GameConfig.LeaderboardDisplayCount)
		end)

		if success then
			local entries = pages:GetCurrentPage()
			local newList = {}
			for _, entry in ipairs(entries) do
				local userId = tonumber(entry.key)
				if userId then
					local name = usernameCache[userId]
					if not name then
						local successName, resultName = pcall(function()
							return players:GetNameFromUserIdAsync(userId)
						end)
						if successName then
							name = resultName
							usernameCache[userId] = name
						else
							name = "Unknown"
						end
					end
					table.insert(newList, {
						userId = userId,
						value = entry.value,
						name = name,
					})
				end
			end
			
			local jsonString = httpService:JSONEncode(newList)
			if lastLeaderboardHashes[category] == jsonString then
				WarnIfSlow("RefreshLeaderboard", refreshStartClock)
				return -- 数据没有变化，跳过网络广播
			end
			lastLeaderboardHashes[category] = jsonString
			
			topLists[category] = newList
			-- 同步给所有客户端
			NetMsg.FireNotifyLeaderboardUpdate(nil, category, newList, GetNextRefreshTimestamp())
		else
			warn(string.format("%s Failed to refresh leaderboard for %s: %s", LOG_PREFIX, category, tostring(pages)))
		end
		WarnIfSlow("RefreshLeaderboard", refreshStartClock)
	end)
end

-- 初始化
function LeaderboardManager.Init()
	-- 每隔一段时间刷新一次排行榜
	task.spawn(function()
		-- 初始化时，先立刻拉取一次排行榜数据，避免服务器刚启动时玩家进来看到的是空榜
		local nowInit = math.floor(workspace:GetServerTimeNow())
		nextRefreshTimestamp = GetAlignedNextRefreshTimestamp(nowInit)
		NetMsg.FireNotifyLeaderboardResetTime(nil, nextRefreshTimestamp)
		
		for _, category in pairs(GameConfig.LeaderboardCategory) do
			LeaderboardManager.RefreshLeaderboard(category)
			task.wait(0.5)
		end

		while true do
			-- 先等待到下一个对齐的刷新时间点
			local now = math.floor(workspace:GetServerTimeNow())
			nextRefreshTimestamp = GetAlignedNextRefreshTimestamp(now)
			local waitSeconds = math.max(1, nextRefreshTimestamp - now)
			task.wait(waitSeconds)

			-- 到达时间点，开始刷新
			print(string.format("%s Starting periodic refresh. Next: %s", LOG_PREFIX, os.date("!%X", nextRefreshTimestamp)))
			
			-- 刷新前更新一下目标时间，确保 RefreshLeaderboard 发送的是下一个时间点
			-- 实际上在这里，下一次刷新应该是 nextRefreshTimestamp + Interval
			local currentRefreshTarget = nextRefreshTimestamp
			nextRefreshTimestamp = GetAlignedNextRefreshTimestamp(math.floor(workspace:GetServerTimeNow()) + 1)
			
			-- 广播下一次的重置时间给所有客户端（防止后续 DataStore 节流导致客户端收不到倒计时更新）
			NetMsg.FireNotifyLeaderboardResetTime(nil, nextRefreshTimestamp)

			for _, category in pairs(GameConfig.LeaderboardCategory) do
				LeaderboardManager.RefreshLeaderboard(category)
				task.wait(2) -- 适当缩短间隔
			end
		end
	end)

	print(string.format("%s Initialized", LOG_PREFIX))
end

-- 玩家加入时同步当前排行榜
function LeaderboardManager.OnPlayerAdded(player: Player)
	LeaderboardManager.CheckWeeklyReset(player)
	
	local resetTime = GetNextRefreshTimestamp()
	NetMsg.FireNotifyLeaderboardResetTime(player, resetTime)
	
	for category, topList in pairs(topLists) do
		NetMsg.FireNotifyLeaderboardUpdate(player, category, topList, resetTime)
	end
end

return LeaderboardManager
