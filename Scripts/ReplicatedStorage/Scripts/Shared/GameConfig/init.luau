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
GameConfig.GameId = 10091007684
if game.GameId == GameConfig.GameId then
	--游戏场景
	GameConfig.GamePlaceId = 93872575939801
	--清除玩家数据场景
	GameConfig.ClearDataStorePlaceId = 99987902017784
else
	--游戏场景
	GameConfig.GamePlaceId = 140465012877509
	--清除玩家数据场景
	GameConfig.ClearDataStorePlaceId = 86129124165513
end

--六次方群组id
GameConfig.SixcubeGroupId = 33977495

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
	GroupReward = 4, --群组奖励
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
	TutorialFireBySpace = 2,
	TutorialFireByButton = 3,
}

GameConfig.GuideTextKeyMap = {
	[GameConfig.GuideType.TutorialBasic] = "GuideTutorialBasic",
	[GameConfig.GuideType.TutorialFireBySpace] = "GuideTutorialFireBySpace",
	[GameConfig.GuideType.TutorialFireByButton] = "GuideTutorialFireByButton",
}

export type GuideProgressInfo = {
	FireBySpace: boolean,
	FireByButton: boolean,
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
	lifetime: number,
	maxBounces: number,
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
	-- 来自载具模板 Attribute PlayerInfoUIOffset；客户端为在 PlayerInfoUI 模板 StudsOffset 上的附加偏移
	playerInfoUIOffset: Vector3,
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
	-- 新手引导进度
	guideProgress: GuideProgressInfo,
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
		guideProgress = {
			FireBySpace = false,
			FireByButton = false,
		},
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
	-- 新手引导进度
	guideProgress: GuideProgressInfo,
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

GameConfig.MinPlayerToStart = 4
GameConfig.MaxPlayerToStart = 8
GameConfig.EnableAIBotFill = true
GameConfig.AIBotMinFireInterval = 2
GameConfig.AIBotMaxFireInterval = 5
GameConfig.AIBotNamePrefix = "BOT"
-- 竞技场控制
GameConfig.ArenaBaseHalfSize = 40
GameConfig.ArenaExtraHalfSizePerPlayer = 7.5
-- 场地边长一半（初始值，由 ArenaManager 动态修改）
GameConfig.ArenaHalfSize = 60
GameConfig.ArenaMinHalfSize = 30
GameConfig.ArenaDesignHalfSize = 60
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
GameConfig.RoundStartCountdown = 3
-- 战斗阶段持续时长（秒）
GameConfig.RoundFightDuration = 120
-- 大厅到传送倒计时
GameConfig.MatchCountdown = 30
-- 准备入座延迟
GameConfig.ArenaSeatPrepareDelay = 0.22
-- 返回大厅解座等待
GameConfig.ReturnToLobbyWait = 0.1
-- 大厅补位机器人 NPC 漫游（LobbySpawnArea 内）
GameConfig.BotLobbyRoamLobbyAreaName = "LobbySpawnArea"
GameConfig.BotLobbyRoamWalkSpeed = 10
GameConfig.BotLobbyRoamIdleMinSec = 1
GameConfig.BotLobbyRoamIdleMaxSec = 4
GameConfig.BotLobbyRoamMaxStrideStuds = 18
GameConfig.BotLobbyRoamReachThresholdStuds = 1.5
GameConfig.BotLobbyRoamMoveTimeoutSec = 8
GameConfig.BotLobbyRoamTickIntervalSec = 0.25
GameConfig.BotLobbyRoamSamplePadding = 2
GameConfig.BotLobbyRoamMinSampleSeparationStuds = 4
GameConfig.BotLobbyRoamWalkAnimationId = "rbxassetid://507777826"
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

GameConfig.MatchState = {
	InLobby = "InLobby",
	MatchCountdown = "MatchCountdown",
	GameStartCountdown = "GameStartCountdown",
	Fighting = "Fighting",
	Settlement = "Settlement",
}

export type MatchState = typeof(GameConfig.MatchState.InLobby)
	| typeof(GameConfig.MatchState.MatchCountdown)
	| typeof(GameConfig.MatchState.GameStartCountdown)
	| typeof(GameConfig.MatchState.Fighting)
	| typeof(GameConfig.MatchState.Settlement)

GameConfig.RoundEndReason = {
	LastStanding = "LastStanding",
	TimeExpired = "TimeExpired",
}

export type RoundEndReason = typeof(GameConfig.RoundEndReason.LastStanding) | typeof(GameConfig.RoundEndReason.TimeExpired)

GameConfig.DirectionChangeReason = {
	Fire = "Fire",
	WallCollision = "WallCollision",
	VehicleCollision = "VehicleCollision",
	BulletHit = "BulletHit",
}

export type DirectionChangeReason = typeof(GameConfig.DirectionChangeReason.Fire)
	| typeof(GameConfig.DirectionChangeReason.WallCollision)
	| typeof(GameConfig.DirectionChangeReason.VehicleCollision)
	| typeof(GameConfig.DirectionChangeReason.BulletHit)

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
	-- 当前单位所用载具配置 id（用于客户端查 VehicleDataMap 等）
	vehicleId: number,
}

export type VehicleDirectionSyncInfo = {
	playerId: number,
	reason: DirectionChangeReason,
	serverPosition: Vector3,
	forceDirection: Vector3,
	serverTime: number,
}

export type VehicleInputCmd = {
	seq: number,
	clientTime: number,
	moveDir: Vector3,
	spinDir: number,
	firePressed: boolean?,
}

export type VehicleStateSnapshot = {
	playerId: number,
	serverTick: number,
	serverTime: number,
	ackInputSeq: number,
	position: Vector3,
	velocity: Vector3,
	yaw: number,
	angVelY: number,
	spinDir: number,
	vehicleId: number,
}

GameConfig.VehicleSyncLerpAlpha = 0.2
GameConfig.VehicleHardSnapDistance = 10
GameConfig.VehicleSnapshotHz = 20
GameConfig.VehicleInputSendHz = 30
-- 本地硬 reconcile 的固定位置误差门槛
GameConfig.VehicleReconcilePosThreshold = 6
-- 本地硬 reconcile 的速度相关门槛：允许 N 秒位移作为缓冲（N * 当前速度），与上者取较大值
-- 用于高速载具在网络抖动下不会被频繁硬纠拉扯
GameConfig.VehicleReconcilePosThresholdSecPerStud = 0.18
GameConfig.VehicleReconcileYawThreshold = math.rad(18)
GameConfig.VehicleInterpolationBackTimeMs = 100
GameConfig.VehicleExtrapolationMaxMs = 120
GameConfig.EnableRemoteVisualSmoothing = true
-- 命中特效时间对齐：允许的最大延后触发窗口（毫秒）
GameConfig.HitVfxAlignMaxDelayMs = 180
-- 命中特效时间对齐：允许使用的最大提前窗口（毫秒）
GameConfig.HitVfxAlignMaxLeadMs = 20
-- 命中特效时间对齐强度（0~1），按插值回退时间缩放额外延迟
GameConfig.HitVfxAlignLerpAlpha = 1
-- 自适应命中反馈延时最小值（毫秒）
GameConfig.HitVfxAdaptiveMinDelayMs = 40
-- 自适应命中反馈延时最大值（毫秒）
GameConfig.HitVfxAdaptiveMaxDelayMs = 180
-- RTT 对反馈延时贡献系数（ms per ms）
GameConfig.HitVfxAdaptiveRttScale = 0.6
-- 抖动对反馈延时贡献系数（ms per ms）
GameConfig.HitVfxAdaptiveJitterScale = 0.8
-- 反馈延时变化速率限制（毫秒/秒）
GameConfig.HitVfxAdaptiveSlewRateMsPerSec = 220
-- RTT 平滑 EMA 系数（0~1，越大越灵敏）
GameConfig.HitAdaptiveRttEmaAlpha = 0.25
-- RTT 抖动 EMA 系数（0~1，越大越灵敏）
GameConfig.HitAdaptiveJitterEmaAlpha = 0.2
-- RTT 统计最小采样间隔（秒）
GameConfig.HitAdaptiveRttSampleIntervalSec = 0.03
-- RTT 样本下限（秒）
GameConfig.HitAdaptiveRttMinSec = 0.01
-- RTT 样本上限（秒）
GameConfig.HitAdaptiveRttMaxSec = 0.8
-- 命中回溯：历史缓存时长（毫秒）
GameConfig.HitRewindHistoryMs = 1000
-- 命中回溯：允许回溯窗口（毫秒）
GameConfig.HitRewindWindowMs = 220
-- 命中回溯：最大补偿时长（毫秒）
GameConfig.HitRewindMaxCompensationMs = 180
-- 命中回溯：最小历史样本数
GameConfig.HitRewindMinSamples = 3
-- 命中回溯：代理碰撞半径补偿（Studs）
GameConfig.HitRewindTargetRadiusStuds = 4.2
-- 本地软校正：线速度向服务端目标插值的「收敛速率（秒^-1）」，越大收敛越快
GameConfig.VehicleVelocityConvergeRate = 10
-- 本地软校正：位置误差转换为额外速度项的弹簧增益（单位：秒^-1）
GameConfig.VehiclePosCorrectionGain = 6
-- 本地软校正：弹簧速度的最大幅度，避免误差大时一次反弹过冲
GameConfig.VehiclePosCorrectionMaxSpeed = 35
-- 客户端 spinDir 反向抖动抑制窗口（毫秒），避免快照/事件来回切换造成净旋转 0
GameConfig.VehicleSpinDirDebounceMs = 80

-- 客户端相机：玩家首次进入服务器（仅一次）时的初始缩放距离（studs）
GameConfig.InitialCameraZoomDistance = 50

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
local NPCNameData = require(script.NPCNameData)

GameConfig.BulletDataMap = BulletData :: { [number]: BulletData }
GameConfig.NPCNameDataMap = NPCNameData :: { [number]: { id: number, labelName: string } }
GameConfig.VehicleDataMap = {} :: { [number]: VehicleData }
local groupRewardVehicleIdListCache: { number }? = nil

local PlayerInfoUiOffsetAttributeName = "PlayerInfoUIOffset"
local modelsFolderForVehicleTemplates = replicatedStorage:FindFirstChild("Models") :: Folder?
local vehicleTemplatesFolder = if modelsFolderForVehicleTemplates
	then modelsFolderForVehicleTemplates:FindFirstChild("Vehicles") :: Folder?
	else nil

local function readPlayerInfoUiOffsetFromVehicleTemplate(resourceName: string): Vector3
	if vehicleTemplatesFolder == nil then
		return Vector3.zero
	end
	local template = vehicleTemplatesFolder:FindFirstChild(resourceName)
	if template == nil or not template:IsA("Model") then
		return Vector3.zero
	end
	local raw = template:GetAttribute(PlayerInfoUiOffsetAttributeName)
	if typeof(raw) == "Vector3" then
		return raw
	end
	return Vector3.zero
end

-- 必须用 data.id 作键：VehiclesData 的表序号（pairs 的 key）与 sortId、配置 id 三者可能不一致
for _, data in pairs(VehiclesData) do
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
		playerInfoUIOffset = readPlayerInfoUiOffsetFromVehicleTemplate(data.resourceName),
	}
	if vehicle.bulletId then
		vehicle.bulletData = BulletData[vehicle.bulletId]
	end
	GameConfig.VehicleDataMap[data.id] = vehicle
end

function GameConfig.GetGroupRewardVehicleIdList(): { number }
	if groupRewardVehicleIdListCache ~= nil then
		return table.clone(groupRewardVehicleIdListCache)
	end

	local groupRewardVehicleIdList = {} :: { number }
	for vehicleId, vehicleData in pairs(GameConfig.VehicleDataMap) do
		if vehicleData.costType == GameConfig.CostType.GroupReward then
			table.insert(groupRewardVehicleIdList, vehicleId)
		end
	end

	table.sort(groupRewardVehicleIdList, function(leftVehicleId, rightVehicleId)
		local leftVehicleData = GameConfig.VehicleDataMap[leftVehicleId]
		local rightVehicleData = GameConfig.VehicleDataMap[rightVehicleId]
		if leftVehicleData == nil or rightVehicleData == nil then
			return leftVehicleId < rightVehicleId
		end
		if leftVehicleData.sortId ~= rightVehicleData.sortId then
			return leftVehicleData.sortId < rightVehicleData.sortId
		end
		return leftVehicleId < rightVehicleId
	end)

	groupRewardVehicleIdListCache = groupRewardVehicleIdList
	local cachedList = groupRewardVehicleIdListCache
	if cachedList == nil then
		return {}
	end
	return table.clone(cachedList)
end

return GameConfig
