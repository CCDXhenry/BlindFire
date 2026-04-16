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

--奖励信息
export type RewardInfo = {
	rewardType: number,
	rewardId: number,
	rewardCount: number,
	rewardSource: number?,
	rewardLv: number?,
	productIndex: number?,
}

--游戏提示缓动方式
GameConfig.GameTipTweenType = {
	FlyUp = 1, --向上飞
	Twinkle = 2, --闪烁
	StayFlyUp = 3, --停留一段时间后向上飞
	FlyUpTwinkle = 4, --向上飞后闪烁
	Twinkle2 = 5,
}

--奖励类型
GameConfig.RewardType = {
	Currency = 1, --货币
}

--货币类型
GameConfig.CurrencyType = {
	Coin = 1, --金币
}

GameConfig.CoinIconImage = "rbxassetid://138756794615498"

--通行证id
GameConfig.GamePassId = {}

--通行证价格
GameConfig.GamePassPrice = {}

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
export type PlayerConfigInfo = {}
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
	ownedGamePassList: { number },
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
	ownedGamePassMap: { [number]: boolean },
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
	ownedGamePassList: { number },
}
export type ClientLocalPlayerInfo = ClientLocalPlayerSaveInfo & {
	--已拥有的通行证映射
	ownedGamePassMap: { [number]: boolean },
	--玩家配置信息
	playerConfigInfo: PlayerConfigInfo,
}

--客户端其他玩家信息
export type ClientOtherPlayerSaveInfo = {}
export type ClientOtherPlayerSyncInfo = ClientOtherPlayerSaveInfo & {}
export type ClientOtherPlayerInfo = ClientOtherPlayerSyncInfo & {}

-- ============================================================
-- Demo 核心玩法常量
-- ============================================================

GameConfig.MinPlayerToStart = 2
-- 场地边长一半（方形场地在 XZ 平面，从 -ArenaHalfSize 到 +ArenaHalfSize）
GameConfig.ArenaHalfSize = 60
GameConfig.ArenaWallProximityStuds = 1
-- 单位在场地中的运动高度（Y轴）
GameConfig.UnitY = 1
-- 单位移动速度（studs/s）
GameConfig.UnitSpeed = 40
-- 水平速度上限（防止连续碰撞后速度失控）
GameConfig.UnitMaxHorizontalSpeed = 42
-- 单位自转速度（degrees/s）
GameConfig.UnitRotationSpeed = 120
-- 开火冷却时间（秒），防连击
GameConfig.FireCooldown = 1
-- 每局开始倒计时
GameConfig.RoundStartCountdown = 5
-- 战斗阶段持续时长（秒）
GameConfig.RoundFightDuration = 120
-- 大厅到传送倒计时
GameConfig.MatchCountdown = 10
-- 命中次数上限（达到后死亡）
GameConfig.MaxHits = 5
-- 炮弹飞行速度
GameConfig.ProjectileSpeed = 100
-- 炮弹存在时间（秒）
GameConfig.ProjectileLifetime = 5
-- 炮弹最大飞行距离 (studs)
GameConfig.MaxProjectileDistance = 500
-- 开火后坐力速度倍数
GameConfig.FireRecoilSpeedMultiplier = 5
-- 命中击退速度倍数
GameConfig.BulletHitSpeedMultiplier = 10
-- 撞墙时 BaseDisk 弹性（与模板 CustomPhysicalProperties 合并时覆盖弹性项）
GameConfig.WallBounceElasticity = 0.42
-- 旋转输入衰减时间（开火旋转未结束期）
GameConfig.SpinDampingDuration = 0.8
-- Arena 中随机出生安全边距
GameConfig.ArenaSpawnMargin = 8
-- 开火导致的镜头旋转角度（每次射击改变顺逆时针）
GameConfig.CameraRecoilAngleRad = math.rad(720)
-- 镜头后坐力平滑系数（越大抵达顶峰越快）
GameConfig.CameraRecoilLerpSpeed = 2
-- 自定义战斗相机俯仰限制（弧度）
GameConfig.CombatCameraMaxPitchRad = math.rad(72)
-- 第三人称：焦点相对 BaseDisk 位置的垂直偏移（studs，向上为正）
GameConfig.CombatCameraFocusYOffsetStuds = 5
-- 炮塔受开火扰动：角速度增量（弧度/秒，乘 spinDir）
GameConfig.TurretSpinImpulseOnFireRadPerSec = math.rad(420)
-- 炮塔受击扰动：角速度增量（弧度/秒，随机向）
GameConfig.TurretSpinImpulseOnHitRadPerSec = math.rad(300)
-- 扰动角速度衰减（越大越快停）
GameConfig.TurretSpinVelocityDecayPerSec = 5.5
-- 扰动积分角向 0 衰减（瞄准可逐渐“拉回”炮塔）
GameConfig.TurretSpinOffsetDecayPerSec = 2.8
-- 底盘用速度对齐朝向时的水平速度阈值（studs/s）
GameConfig.HullYawVelocityEpsilonStudsPerSec = 1.5

export type MatchState = "InLobby" | "MatchCountdown" | "GameStartCountdown" | "Fighting"

export type RoundEndReason = "LastStanding" | "TimeExpired"

-- 单位初始化信息（服务端广播给所有客户端）
export type UnitInitInfo = {
	-- 玩家 UserId
	playerId: number,
	-- 初始运动朝向角度（度，XZ 平面，0 = +X 方向）
	moveAngle: number,
	-- 初始自转方向：+1 顺时针 / -1 逆时针
	spinDir: number,
	-- 初始位置
	spawnPosition: Vector3,
	-- 初始生命（命中上限）
	maxHits: number,
}

return GameConfig
