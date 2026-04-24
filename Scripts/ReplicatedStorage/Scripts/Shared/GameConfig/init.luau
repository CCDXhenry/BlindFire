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

--六次方群组id
GameConfig.SixcubeGroupId = 33977495
--群组奖励载具id
GameConfig.GroupRewardVehicleId = 2

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
	Rb = 2, --Robux
}

--消耗类型
GameConfig.CostType = {
	Coin = 1, --金币
	Rb = 2, --RB
	CoinOrRb = 3, --金币或RB
}

--物品数量改变原因
GameConfig.ItemCountChangeReason = {
	--获得
	GainFromGMCommand = 1001, --GM命令获得
	GainFromPurchase = 1002, --内购获得
	GainFromBattle = 1003, --战斗获得
	GainFromHit = 1004, --击中获得
	GainFromKill = 1005, --击杀获得
	--消耗
	SpendOnUpgrade = 2001, --升级消耗
}

-- 指引类型
GameConfig.GuideType = {
	None = 0,
	TutorialBasic = 1,
}

GameConfig.GuideTextKeyMap = {
	[GameConfig.GuideType.TutorialBasic] = "GuideTutorialBasic",
}

GameConfig.CoinIconImage = "rbxassetid://138756794615498"
GameConfig.RbIconImage = "rbxassetid://116949418469040"
GameConfig.AFKOnImage = "rbxassetid://114216336762183"
GameConfig.AFKOffImage = "rbxassetid://113696020530948"

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
export type BulletData = {
	id: number,
	iconImage: string,
	resourceName: string,
	labelName_t: string,
	sortId: number,
	maxDistance: number,
	productId: number,
	lifetime: number,
	cost: number,
	costRb: number?,
	maxBounces: number,
	costType: number,
	moveSpeed: number,
}

export type VehicleData = {
	id: number,
	iconImage: string,
	resourceName: string,
	labelName_t: string,
	bulletId: number,
	sortId: number,
	productId: number,
	costCoin: number,
	costRb: number?,
	costType: number,
	maxHits: number,
	fireCooldown: number,
	moveSpeed: number,
	bulletData: BulletData?,
}

export type VehicleInventory = {
	--当前使用的载具ID
	currentId: string,
	--已拥有的载具列表
	ownedList: { [string]: boolean },
}

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
	--货币信息
	currencies: { [string]: number },
	--载具信息
	vehicleInventory: VehicleInventory,
	--周统计信息
	weeklyStats: {
		kills: number,
		wins: number,
		earnings: number,
		lastResetWeek: string,
	},
	-- 是否已领取过群组奖励
	hasClaimedGroupReward: boolean,
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
	--当前指引类型
	currentGuideType: number,
	--是否在群组中
	isInGroup: boolean,
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
		hasClaimedGroupReward = false,
		currencies = {
			[tostring(GameConfig.CurrencyType.Coin)] = 0,
		},
		vehicleInventory = {
			currentId = "1",
			ownedList = {
				["1"] = true,
			},
		},
		weeklyStats = {
			kills = 0,
			wins = 0,
			earnings = 0,
			lastResetWeek = os.date("!%Y_%W"),
		},
	}
end

--客户端自己的玩家信息
export type ClientLocalPlayerSaveInfo = {
	--设置信息
	settingInfo: SettingInfo,
	--已拥有的通行证列表
	ownedGamePassList: { number },
	--货币信息
	currencies: { [string]: number },
	--载具信息
	vehicleInventory: VehicleInventory,
	--是否在群组中
	isInGroup: boolean,
	-- 是否已领取过群组奖励
	hasClaimedGroupReward: boolean,
}
export type ClientLocalPlayerInfo = ClientLocalPlayerSaveInfo & {
	--已拥有的通行证映射
	ownedGamePassMap: { [number]: boolean },
	--玩家配置信息
	playerConfigInfo: PlayerConfigInfo,
	--当前指引类型
	currentGuideType: number,
}

--客户端其他玩家信息
export type ClientOtherPlayerSaveInfo = {}
export type ClientOtherPlayerSyncInfo = ClientOtherPlayerSaveInfo & {}
export type ClientOtherPlayerInfo = ClientOtherPlayerSyncInfo & {}

-- ============================================================
-- Demo 核心玩法常量
-- ============================================================

GameConfig.MinPlayerToStart = 2
-- 竞技场控制
GameConfig.ArenaBaseHalfSize = 40
GameConfig.ArenaExtraHalfSizePerPlayer = 10
-- 场地边长一半（初始值，由 ArenaManager 动态修改）
GameConfig.ArenaHalfSize = 60
GameConfig.ArenaMinHalfSize = 30
GameConfig.ArenaShrinkSpeed = 1
GameConfig.ArenaShrinkPeoplePower = 1
GameConfig.ArenaShrinkSizePower = 0.5
GameConfig.ArenaShrinkStartDelay = 10
GameConfig.ArenaWallProximityStuds = 2
-- 单位在场地中的运动高度（Y轴）
GameConfig.UnitY = 1
-- 单位移动速度（studs/s）
GameConfig.UnitSpeed = 30
-- 水平速度上限（防止连续碰撞后速度失控）
GameConfig.UnitMaxHorizontalSpeed = 60
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
-- 准备入座延迟
GameConfig.ArenaSeatPrepareDelay = 0.22
-- 返回大厅解座等待
GameConfig.ReturnToLobbyWait = 0.1
-- 结算阶段时长
GameConfig.SettlementDuration = 2
-- 入座重试参数
GameConfig.MaxSeatRetry = 30
GameConfig.SeatRetryInterval = 0.2
GameConfig.MaxForceSitRetry = 20
-- 命中次数上限（达到后死亡）
GameConfig.MaxHits = 3
-- 炮弹飞行速度
GameConfig.ProjectileSpeed = 60
-- 炮弹存在时间（秒）
GameConfig.ProjectileLifetime = 3
-- 炮弹步进余量 (studs)
GameConfig.ProjectileStepMargin = 0.45
-- 炮弹最大飞行距离 (studs)
GameConfig.MaxProjectileDistance = 500
-- 子弹最大反弹次数
GameConfig.ProjectileMaxBounces = 1
-- 开火后坐力速度倍数
GameConfig.FireRecoilSpeedMultiplier = 5
-- 开火前摇时长（秒）
GameConfig.FireCastTime = 0.2

-- 排行榜分类
GameConfig.LeaderboardCategory = {
	WeeklyKills = "WeeklyKills",
	WeeklyWins = "WeeklyWins",
	WeeklyEarnings = "WeeklyEarnings",
}

-- 排行榜更新频率（秒，1小时）
GameConfig.LeaderboardUpdateInterval = 60
-- 排行榜显示数量
GameConfig.LeaderboardDisplayCount = 20

-- 静态卡死检测阈值
GameConfig.StuckVelocityThreshold = 0.5
GameConfig.StuckStallDuration = 1.0 -- 秒

-- 服务端权威模式参数（OnRequestFire 中用于估算子弹发射时刻的延迟窗口）
GameConfig.HitValidationClientTimestampMinDelta = -0.2
GameConfig.HitValidationClientTimestampMaxDelta = 0.6

-- 自己的子弹是否可以命中自己
GameConfig.CanHitSelf = true
-- 命中击退速度倍数
GameConfig.BulletHitSpeedMultiplier = 6
-- 撞墙时 BaseDisk 弹性（与模板 CustomPhysicalProperties 合并时覆盖弹性项）
GameConfig.WallBounceElasticity = 0.42
-- 撞墙反弹冷却
GameConfig.WallBounceCooldown = 0.22
-- 玩家碰撞反弹冷却
GameConfig.VehicleBumpCooldown = 0.5
-- 玩家碰撞反弹速度倍数
GameConfig.VehicleBumpSpeedMultiplier = 1.2
-- 玩家碰撞判定半径 (从 VehicleModel.BaseDisk 动态计算并缓存)
local cachedVehicleCollisionRadius: number? = nil
function GameConfig.GetVehicleCollisionRadius(): number
	if cachedVehicleCollisionRadius then
		return cachedVehicleCollisionRadius
	end

	local models = replicatedStorage:FindFirstChild("Models")
	local vehicleModel = if models then models:FindFirstChild("VehicleModel") else nil
	local baseDisk = if vehicleModel then vehicleModel:FindFirstChild("BaseDisk") else nil

	if baseDisk and baseDisk:IsA("BasePart") then
		local size = baseDisk.Size
		cachedVehicleCollisionRadius = math.sqrt(size.X ^ 2 + size.Z ^ 2)
		return if cachedVehicleCollisionRadius then cachedVehicleCollisionRadius :: number else 5.0
	end

	return 5.0 -- Fallback
end
-- 玩家重叠主动解围速度
GameConfig.VehicleOverlapResolutionSpeed = 15
-- 玩家碰撞方向判定阈值 (点积 < 此值则反射; 调为 0.0 以增加侧向碰撞灵敏度)
GameConfig.VehicleBumpDotThreshold = 0.0
-- 触发反弹的进入速度阈值 (负数)
GameConfig.WallBounceVelThreshold = -0.35
-- 判定卡墙的最大速度
GameConfig.WallStuckSpeedThreshold = 10
-- 判定卡墙的角度阈值
GameConfig.WallStuckAngleThreshold = -0.02
-- 旋转输入衰减时间（开火旋转未结束期）
GameConfig.SpinDampingDuration = 0.8
-- 驱动水平力增益 单位质量的驱动水平力（牛顿）
GameConfig.DriveHorizontalForceGain = 3
-- 撞墙反弹速度倍数
GameConfig.WallBounceSpeedMultiplier = 1
-- Arena 中随机出生安全边距
GameConfig.ArenaSpawnMargin = 8
-- 随机出生时单位间的最小间隔（Studs）
GameConfig.MinSpawnSeparation = 20

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
-- 受击后无敌时间（秒）
GameConfig.InvincibilityDuration = 2

export type MatchState = "InLobby" | "MatchCountdown" | "GameStartCountdown" | "Fighting" | "Settlement"

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
	-- 是否为当前回合参赛者
	isParticipant: boolean,
}

GameConfig.VisibleParameters = {
	{ key = "UnitSpeed", alias = "单位移动速度" },
	{ key = "UnitMaxHorizontalSpeed", alias = "水平速度上限" },
	{ key = "UnitRotationSpeed", alias = "单位旋转速度" },
	{ key = "MaxHits", alias = "生命值(命中上限)" },
	{ key = "ProjectileSpeed", alias = "子弹飞行速度" },
	{ key = "ProjectileLifetime", alias = "子弹生存时间" },
	{ key = "ProjectileMaxBounces", alias = "子弹最大反弹次数" },
	{ key = "CanHitSelf", alias = "能否击中自己" },
	{ key = "FireCooldown", alias = "射击冷却时间" },
	{ key = "WallBounceSpeedMultiplier", alias = "撞墙反弹速度倍数" },
	{ key = "BulletHitSpeedMultiplier", alias = "命中击退速度倍数" },
	{ key = "FireRecoilSpeedMultiplier", alias = "开火后坐力速度倍数" },
	{ key = "DriveHorizontalForceGain", alias = "驱动水平力增益" },
	{ key = "MatchCountdown", alias = "备战倒计时" },
	{ key = "RoundStartCountdown", alias = "开局倒计时" },
	{ key = "RoundFightDuration", alias = "战斗持续时间" },
	{ key = "FireCastTime", alias = "开火前摇" },
	{ key = "ArenaBaseHalfSize", alias = "竞技场基础半长" },
	{ key = "ArenaExtraHalfSizePerPlayer", alias = "每人额外增加半长" },
	{ key = "ArenaShrinkSpeed", alias = "基础缩圈速度" },
	{ key = "ArenaShrinkPeoplePower", alias = "人数速度权重" },
	{ key = "ArenaShrinkSizePower", alias = "半径速度权重" },
	{ key = "ArenaMinHalfSize", alias = "最小圈半径" },
	{ key = "InvincibilityDuration", alias = "受伤无敌时间" },
	{ key = "VehicleBumpCooldown", alias = "载具碰撞冷却" },
	{ key = "VehicleBumpSpeedMultiplier", alias = "载具碰撞反弹倍率" },
	{ key = "VehicleCollisionRadius", alias = "载具碰撞半径" },
	{ key = "VehicleOverlapResolutionSpeed", alias = "重叠解围速度" },
}

local BulletData = require(script.BulletData)
local VehiclesData = require(script.VehiclesData)

GameConfig.BulletDataMap = BulletData :: { [number]: BulletData }
GameConfig.VehicleDataMap = {} :: { [number]: VehicleData }

for id, data in pairs(VehiclesData) do
	local vehicle: VehicleData = {
		id = data.id,
		iconImage = data.iconImage,
		resourceName = data.resourceName,
		labelName_t = data.labelName_t,
		bulletId = data.bulletId,
		sortId = data.sortId,
		productId = data.productId,
		costCoin = data.costCoin or data.cost,
		costRb = data.costRb,
		costType = data.costType,
		maxHits = data.maxHits or GameConfig.MaxHits,
		fireCooldown = data.fireCooldown or GameConfig.FireCooldown,
		moveSpeed = data.moveSpeed,
	}
	if vehicle.bulletId then
		vehicle.bulletData = BulletData[vehicle.bulletId]
	end
	GameConfig.VehicleDataMap[id] = vehicle
end

return GameConfig
