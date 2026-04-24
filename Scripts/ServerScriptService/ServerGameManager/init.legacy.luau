--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverCore = serverStorage:WaitForChild("Core")
local serverCoreScripts = serverCore:WaitForChild("Scripts")
local DataStoreTool = require(serverCoreScripts:FindFirstChild("DataStoreTool"))
local MarketplaceTool = require(serverCoreScripts:FindFirstChild("MarketplaceTool"))
local serverScripts = serverStorage:WaitForChild("Scripts")
local PlayerSaveInfoVersionUpdateTool = require(serverScripts:FindFirstChild("PlayerSaveInfoVersionUpdateTool"))
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
local PlayerStateManager = require(serverScripts:FindFirstChild("PlayerStateManager"))
local MatchManager = require(serverScripts:FindFirstChild("MatchManager"))
local CombatManager = require(serverScripts:FindFirstChild("CombatManager"))
local VehicleManager = require(serverScripts:FindFirstChild("VehicleManager"))
local LeaderboardManager = require(serverScripts:FindFirstChild("LeaderboardManager"))
local ConfigCommandManager = require(script:FindFirstChild("ConfigCommandManager"))

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local RetryAsync = require(coreSharedScripts:FindFirstChild("RetryAsync"))
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local dataStoreService: DataStoreService = game:GetService("DataStoreService")
local playerInfoDataStore: DataStore = dataStoreService:GetDataStore("PlayerInfo")
local players: Players = game:GetService("Players")
local localizationService: LocalizationService = game:GetService("LocalizationService")
local runService: RunService = game:GetService("RunService")
local configService: ConfigService = game:GetService("ConfigService")

local LOG_PREFIX = "[ServerGameManager]"
local AutoSavePlayerInfoInterval: number = 30

local autoSaveThreads: { [number]: thread } = {}

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
end

local function SplitVersion(version: string): { number }
	local result: { number } = {}
	for v: string in string.gmatch(version, "%d+") do
		local v2: number? = tonumber(v)
		if v2 ~= nil then
			table.insert(result, v2)
		end
	end
	return result
end

local function IsVersionAfter(version1: string, version2: string): boolean
	local v1: { number } = SplitVersion(version1)
	local v2: { number } = SplitVersion(version2)
	local length: number = math.max(#v1, #v2)
	for i: number = 1, length do
		local v1i: number = v1[i] or 0
		local v2i: number = v2[i] or 0
		if v1i ~= v2i then
			return v1i > v2i
		end
	end
	return true
end

local function CheckPlayerLoginDays(player: Player, todayDate: DateTimeExtension.DateTimeTable)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if
		playerInfo ~= nil
		and (
			todayDate.Year > playerInfo.lastOnlineDate.Year
			or (
				todayDate.Year == playerInfo.lastOnlineDate.Year
				and todayDate.Month > playerInfo.lastOnlineDate.Month
			)
			or (
				todayDate.Year == playerInfo.lastOnlineDate.Year
				and todayDate.Month == playerInfo.lastOnlineDate.Month
				and todayDate.Day > playerInfo.lastOnlineDate.Day
			)
		)
	then
		ServerGameInfo.ChangePlayerLoginDays(player, playerInfo.loginDays + 1, todayDate)
	end
end

local function CheckOwnedGamePasses(player: Player)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo ~= nil then
		task.spawn(function()
			for _gamePassIdKey: string, gamePassIdValue: number in pairs(GameConfig.GamePassId) do
				if playerInfo.ownedGamePassMap[gamePassIdValue] == nil then
					local success: boolean, result: any = MarketplaceTool.SafeUserOwnsGamePass(player, gamePassIdValue)
					if success and result then
						ServerGameInfo.SetPlayerGamePassAcquired(player, gamePassIdValue)
						AnalyticsTool.AddPassPurchaseEvent(
							player,
							gamePassIdValue,
							GameConfig.GamePassPrice[gamePassIdValue]
						)
					end
				end
			end
		end)
	end
end

local function SavePlayerInfo(player: Player)
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo ~= nil and playerInfo.playerInfoChanged then
		local playerSaveInfo: GameConfig.PlayerSaveInfo = ServerGameInfo.CreatePlayerSaveInfoByPlayerInfo(playerInfo)
		DataStoreTool.SafeSet(playerInfoDataStore, tostring(player.UserId), playerSaveInfo)
		LeaderboardManager.SavePlayerStats(player)
		playerInfo.playerInfoChanged = false
	end
end

local function OnPlayerAdded(player: Player)
	task.spawn(function()
		LogInfo(string.format("OnPlayerAdded userId=%d", player.UserId))

		local success: boolean, result: any = DataStoreTool.SafeGet(playerInfoDataStore, tostring(player.UserId))
		if not success then
			player:Kick(result)
			return
		end

		local playerSaveInfo: GameConfig.PlayerSaveInfo
		if result ~= nil then
			PlayerSaveInfoVersionUpdateTool.Update(result)
			playerSaveInfo = result
		else
			playerSaveInfo = GameConfig.CreateDefaultPlayerSaveInfo()
		end

		success, result = RetryAsync(function()
			return localizationService:GetCountryRegionForPlayerAsync(player)
		end, 5, 1)
		local countryRegion: string = if success then result else "unknown"

		local _configSnapshot: any
		if IsVersionAfter(playerSaveInfo.firstEnterVersion, GameConfig.ABTestVersion) then
			_configSnapshot = configService:GetConfigForPlayerAsync(player)
		else
			_configSnapshot = configService:GetConfigAsync()
		end

		local playerConfigInfo: GameConfig.PlayerConfigInfo = {}
		
		local isInGroup = false
		local successGroup, resultGroup = pcall(function()
			return player:IsInGroupAsync(GameConfig.SixcubeGroupId)
		end)
		if successGroup then
			isInGroup = resultGroup
		end

		ServerGameInfo.InitPlayerInfo(player, playerSaveInfo, countryRegion, playerConfigInfo, isInGroup)

		local nowDate: DateTimeExtension.DateTimeTable = DateTimeExtension.GetNowDate()
		CheckPlayerLoginDays(player, nowDate)
		CheckOwnedGamePasses(player)

		local autoSaveThread: thread = coroutine.create(function()
			while true do
				task.wait(AutoSavePlayerInfoInterval)
				SavePlayerInfo(player)
			end
		end)
		coroutine.resume(autoSaveThread)
		autoSaveThreads[player.UserId] = autoSaveThread

		AnalyticsTool.AddPlayer(player)

		CombatManager.OnPlayerAdded(player)
		MatchManager.OnPlayerAdded(player)
		LeaderboardManager.OnPlayerAdded(player)
	end)
end

local function OnPlayerRemoving(player: Player)
	task.spawn(function()
		LogInfo(string.format("OnPlayerRemoving userId=%d", player.UserId))

		SavePlayerInfo(player)
		AnalyticsTool.RemovePlayer(player)
		ServerGameInfo.RemovePlayerInfo(player)

		local autoSaveThread = autoSaveThreads[player.UserId]
		if autoSaveThread ~= nil then
			coroutine.close(autoSaveThread)
			autoSaveThreads[player.UserId] = nil
		end

		CombatManager.OnPlayerRemoving(player)
		MatchManager.OnPlayerRemoving(player)
	end)
end

local function OnHeartbeat(deltaTime: number)
	local nowDate: DateTimeExtension.DateTimeTable = DateTimeExtension.GetNowDate()
	for _, player: Player in players:GetPlayers() do
		ServerGameInfo.AddPlayerGameTime(player, deltaTime)
		CheckPlayerLoginDays(player, nowDate)
	end
end

local function InitGameSystems()
	LogInfo("Init begin")
	PlayerStateManager.Init()
	CombatManager.Init(MatchManager.OnPlayerDead)
	MatchManager.Init(CombatManager.StartRound)
	LeaderboardManager.Init()
	VehicleManager.Init()
	ConfigCommandManager.Init()
	LogInfo("Init end")
end

local function BootstrapOnlinePlayers()
	LogInfo("BootstrapOnlinePlayers begin")
	for _, player in players:GetPlayers() do
		OnPlayerAdded(player)
	end
	LogInfo("BootstrapOnlinePlayers end")
end

print("GameVersion", GameConfig.GameVersion)
AnalyticsTool.Init()
InitGameSystems()
BootstrapOnlinePlayers()

players.PlayerAdded:Connect(OnPlayerAdded)
players.PlayerRemoving:Connect(OnPlayerRemoving)
runService.Heartbeat:Connect(OnHeartbeat)
