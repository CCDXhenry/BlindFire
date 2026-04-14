--!strict
local GameConfig = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))

--游戏版本
GameConfig.GameVersion = "1.0.0"
--本次AB测试版本
GameConfig.ABTestVersion = "1.0.0"
--玩家存档数据版本
GameConfig.PlayerSaveInfoDataVersion = 0
--正式版游戏id
GameConfig.GameId = 6376748064
if game.GameId == GameConfig.GameId then
	--游戏场景
	GameConfig.GamePlaceId = 17432470623
	--清除玩家数据场景
	GameConfig.ClearDataStorePlaceId = 18733054561
else
	--游戏场景
	GameConfig.GamePlaceId = 17432470623
	--清除玩家数据场景
	GameConfig.ClearDataStorePlaceId = 18733054561
end

--通行证id
GameConfig.GamePassId = {
	
}

--通行证价格
GameConfig.GamePassPrice = {
	
}

--玩家设置信息
export type SettingInfo = {
	--背景音乐音量
	bgmVolume: number,
	--音效音量
	soundEffectVolume: number,
	--是否开启振动
	vibrationOn: boolean,
}
--玩家配置信息
export type PlayerConfigInfo = {
	
}
export type PlayerSaveInfo = {
	--数据版本
	dataVersion: number,
	--首次进入游戏的时间
	firstEnterTime: number,
	--首次进入游戏的版本
	firstEnterVersion: string,
	--玩家累计游戏时间
	gameTime: number,
	--玩家累计登录天数
	loginDays: number,
	--玩家最后在线日期时间戳
	lastOnlineDateUTC: number,
	--设置信息
	settingInfo: SettingInfo,
	--已拥有的通行证列表
	ownedGamePassList: {number},
}
export type PlayerInfo = PlayerSaveInfo & {
	--玩家信息是否发生变化
	playerInfoChanged: boolean,
	--本次上线时间
	timeOfThisLogin: number,
	--玩家的国家/地区
	countryRegion: string,
	--玩家最后在线日期
	lastOnlineDate: DateTimeExtension.DateTimeTable,
	--已拥有的通行证映射
	ownedGamePassMap: {[number]: boolean},
	--玩家配置信息
	playerConfigInfo: PlayerConfigInfo,
}

--内购订单信息
export type ReceiptInfo = {
	PurchaseId: string,
	PlayerId: number,
	ProductId: number,
	PlaceIdWherePurchased: number,
	CurrencySpent: number,
	CurrencyType: Enum.CurrencyType,
}


--默认玩家存档
function GameConfig.CreateDefaultPlayerSaveInfo(): PlayerSaveInfo
	local nowDate: DateTimeExtension.DateTimeTable = DateTimeExtension.GetNowDate()
	return {
		dataVersion = GameConfig.PlayerSaveInfoDataVersion,
		firstEnterTime = DateTime.now().UnixTimestamp,
		firstEnterVersion = GameConfig.GameVersion,
		gameTime = 0,
		loginDays = 1,
		lastOnlineDateUTC = DateTime.fromUniversalTime(nowDate.Year, nowDate.Month, nowDate.Day).UnixTimestamp,
		settingInfo = {
			bgmVolume = 1,
			soundEffectVolume = 1,
			vibrationOn = true,
		},
		ownedGamePassList = {},
	}
end

--客户端自己的玩家信息
export type ClientLocalPlayerSaveInfo = {
	--设置信息
	settingInfo: SettingInfo,
	--已拥有的通行证列表
	ownedGamePassList: {number},
}
export type ClientLocalPlayerInfo = ClientLocalPlayerSaveInfo & {
	--已拥有的通行证映射
	ownedGamePassMap: {[number]: boolean},
	--玩家配置信息
	playerConfigInfo: PlayerConfigInfo,
}

--客户端其他玩家信息
export type ClientOtherPlayerSaveInfo = {
	
}
export type ClientOtherPlayerSyncInfo = ClientOtherPlayerSaveInfo & {
	
}
export type ClientOtherPlayerInfo = ClientOtherPlayerSyncInfo & {

}

return GameConfig
