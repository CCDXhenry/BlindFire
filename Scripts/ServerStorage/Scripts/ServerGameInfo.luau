--!strict
local ServerGameInfo = {}

local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerMsg = require(serverScripts:FindFirstChild("ServerMsg"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local players = game:GetService("Players")

local playerInfoMap: {[number]: GameConfig.PlayerInfo} = {}

--初始化玩家信息
function ServerGameInfo.InitPlayerInfo(player: Player, playerSaveInfo: GameConfig.PlayerSaveInfo, countryRegion: string,
	playerConfigInfo: GameConfig.PlayerConfigInfo)
	local playerInfo: GameConfig.PlayerInfo = {
		dataVersion = playerSaveInfo.dataVersion,
		firstEnterTime = playerSaveInfo.firstEnterTime,
		firstEnterVersion = playerSaveInfo.firstEnterVersion,
		gameTime = playerSaveInfo.gameTime,
		loginDays = playerSaveInfo.loginDays,
		lastOnlineDateUTC = playerSaveInfo.lastOnlineDateUTC,
		settingInfo = playerSaveInfo.settingInfo,
		ownedGamePassList = playerSaveInfo.ownedGamePassList,
		playerInfoChanged = false,
		timeOfThisLogin = DateTime.now().UnixTimestamp,
		countryRegion = countryRegion,
		lastOnlineDate = DateTimeExtension.GetDate(DateTime.fromUnixTimestamp(playerSaveInfo.lastOnlineDateUTC)),
		ownedGamePassMap = {},
		playerConfigInfo = playerConfigInfo,
	}
	for ownedGamePassIndex: number, ownedGamePassId: number in playerInfo.ownedGamePassList do
		playerInfo.ownedGamePassMap[ownedGamePassId] = true
	end
	playerInfoMap[player.UserId] = playerInfo
	ServerMsg.FirePlayerInfoInit(player)
	local clientLocalPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo = {
		settingInfo = playerInfo.settingInfo,
		ownedGamePassList = playerInfo.ownedGamePassList,
	}
	local clientOtherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo = {
		
	}
	local clientOtherPlayerSyncInfoMap: {[string]: GameConfig.ClientOtherPlayerSyncInfo} = {}
	for player2Index: number, player2: Player in players:GetPlayers() do
		if player2.UserId == player.UserId then
			continue
		end
		local player2Info: GameConfig.PlayerInfo = playerInfoMap[player2.UserId]
		if player2Info == nil then
			continue
		end
		local clientOtherPlayer2SyncInfo: GameConfig.ClientOtherPlayerSyncInfo = {
			
		}
		clientOtherPlayerSyncInfoMap[tostring(player2.UserId)] = clientOtherPlayer2SyncInfo
	end
	NetMsg.FireNotifyPlayerInfoInit(player, clientLocalPlayerSaveInfo, clientOtherPlayerSyncInfoMap, playerConfigInfo)
	NetMsg.FireNotifyPlayersOtherPlayerInfoInit(player.UserId, clientOtherPlayerSaveInfo)
end

--移除玩家信息
function ServerGameInfo.RemovePlayerInfo(player: Player)
	playerInfoMap[player.UserId] = nil
end

--获取玩家信息
function ServerGameInfo.GetPlayerInfo(player: Player)
	return playerInfoMap[player.UserId]
end

--创建玩家存档信息
function ServerGameInfo.CreatePlayerSaveInfoByPlayerInfo(playerInfo: GameConfig.PlayerInfo): GameConfig.PlayerSaveInfo
	return {
		dataVersion = playerInfo.dataVersion,
		firstEnterTime = playerInfo.firstEnterTime,
		firstEnterVersion = playerInfo.firstEnterVersion,
		gameTime = playerInfo.gameTime,
		loginDays = playerInfo.loginDays,
		lastOnlineDateUTC = playerInfo.lastOnlineDateUTC,
		lastOnlineDate = playerInfo.lastOnlineDate,
		ownedGamePassList = playerInfo.ownedGamePassList,
		settingInfo = playerInfo.settingInfo,
	}
end

--增加玩家游戏时间
function ServerGameInfo.AddPlayerGameTime(player: Player, addGameTime: number)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		return
	end
	playerInfo.gameTime += addGameTime
	playerInfo.playerInfoChanged = true
end

--改变玩家登录天数
function ServerGameInfo.ChangePlayerLoginDays(player: Player, loginDays: number, lastOnlineDate: DateTimeExtension.DateTimeTable)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		return
	end
	playerInfo.loginDays = loginDays
	playerInfo.lastOnlineDate = lastOnlineDate
	playerInfo.lastOnlineDateUTC = DateTime.fromUniversalTime(lastOnlineDate.Year, lastOnlineDate.Month, lastOnlineDate.Day).UnixTimestamp
	playerInfo.playerInfoChanged = true
end

--设置玩家通行证为已获得
function ServerGameInfo.SetPlayerGamePassAcquired(player: Player, gamePassId: number)
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil or playerInfo.ownedGamePassMap[gamePassId] then
		return
	end
	table.insert(playerInfo.ownedGamePassList, gamePassId)
	playerInfo.ownedGamePassMap[gamePassId] = true
	playerInfo.playerInfoChanged = true
	NetMsg.FireNotifyPlayerAcquiredGamePass(player, gamePassId)
end

return ServerGameInfo