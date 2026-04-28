--!strict
local CombatManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local runService = game:GetService("RunService")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local PlayerStateManager = require(serverScripts:FindFirstChild("PlayerStateManager"))
local ArenaManager = require(serverScripts:FindFirstChild("ArenaManager"))
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local LeaderboardManager = require(serverScripts:FindFirstChild("LeaderboardManager"))
local VehicleLocomotionTool = require(sharedScripts:FindFirstChild("VehicleLocomotionTool"))

type OnPlayerDeadCallback = (player: Player, isDisconnect: boolean?, hitDirection: Vector3?) -> ()

type ServerUnitInfo = {
	playerId: number,
	unitModel: Model,
	rootPart: BasePart,
	spinDir: number,
	moveAngle: number,
	invincibleUntil: number,
	targetVelX: number,
	targetVelZ: number,
	spinAngleRad: number,
	lastWallBounceClock: number,
	lastVehicleBumpClock: number,
	driveVectorForce: VectorForce?,
	vehicleConfig: any,
	stuckTime: number?,
	lastPos: Vector3?,
}

type ServerBullet = {
	shooterId: number,
	templateName: string,
	spawnPos: Vector3,
	shotDir: Vector3,
	activeTime: number,
	speed: number,
	lifetime: number,
	maxDistance: number,
	maxBounces: number,
	distanceTraveled: number,
	hitRadius: number,
	bouncesLeft: number,
	currentPos: Vector3,
	estimatedRtt: number,
	visualModel: Model?,
	physicsRoot: BasePart?,
	visualWeld: Motor6D?,
	linearVelocity: LinearVelocity?,
	-- 激活前是否已执行过首次 PivotTo（避免每帧重复定位）
	visualSpawned: boolean,
	physicsStarted: boolean,
}

local heartbeatConnection: RBXScriptConnection? = nil
local activeServerBullets: { [string]: ServerBullet } = {}
-- 每个 shooterId 当前存活子弹数，O(1) 查询替代遍历
local shooterBulletCountMap: { [number]: number } = {}

local LOG_PREFIX = "[CombatManager]"
local DEBUG_LOG = false -- 生产环境设为 false 关闭高频日志
local VEHICLE_MODEL_NAME_PREFIX = "Vehicle_"
local UNDERGROUND_Y = -100
local SERVER_PROJECTILE_NAME_PREFIX = "ServerProjectile_"
local SERVER_BULLETS_FOLDER_NAME = "ServerBullets"
local SERVER_BULLET_SHOOTER_USER_ID_ATTR = "ShooterUserId"
local PROJECTILE_PREPARED_ATTR = "ServerPreparedProjectileTemplate"
local PROJECTILE_PHYSICS_ROOT_NAME = "PhysicsRoot"
local PROJECTILE_VISUAL_WELD_NAME = "VisualWeld"
local PROJECTILE_DRIVE_ATTACHMENT_NAME = "ProjectileDriveAttachment"
local PROJECTILE_ALIGN_ORIENTATION_NAME = "ProjectileAlignOrientation"
local PROJECTILE_LINEAR_VELOCITY_NAME = "ProjectileLinearVelocity"
local PROJECTILE_POOL_LIMIT_PER_TEMPLATE = 24
local PROJECTILE_BOUNCE_SEPARATION_BIAS = 0.05

local serverBulletsFolder: Folder? = nil
-- 缓存 Models Folder
local modelsFolder: Folder = replicatedStorage:WaitForChild("Models") :: Folder
local vehiclesFolder: Folder = modelsFolder:WaitForChild("Vehicles") :: Folder
local bulletModelsFolder: Folder = modelsFolder:WaitForChild("Bullet") :: Folder

local unitInfoMap: { [number]: ServerUnitInfo } = {}
local playerDeadCallback: OnPlayerDeadCallback? = nil

local serverMatchState: GameConfig.MatchState = GameConfig.MatchState.InLobby

local function LogInfo(message: string)
	if not DEBUG_LOG then
		return
	end
	print(string.format("%s %s", LOG_PREFIX, message))
end

local function _LogWarn(message: string)
	warn(string.format("%s %s", LOG_PREFIX, message))
end

local function FormatVector3(vector: Vector3): string
	return string.format("(%.2f, %.2f, %.2f)", vector.X, vector.Y, vector.Z)
end

local function isNaN(n: number): boolean
	return n ~= n
end

local function ToHorizontalDirection(vector: Vector3): Vector3
	if isNaN(vector.X) or isNaN(vector.Y) or isNaN(vector.Z) then
		return Vector3.new(0, 0, -1)
	end
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return horizontal.Unit
end

local function GetVehicleTemplate(modelName: string): Model?
	local vehicleTemplate = vehiclesFolder:FindFirstChild(modelName)
	if vehicleTemplate == nil or not vehicleTemplate:IsA("Model") then
		return nil
	end
	return vehicleTemplate
end

local function getVehicleIdFromUnitInfo(unitInfo: ServerUnitInfo): number
	local cfg = unitInfo.vehicleConfig
	if typeof(cfg) == "table" and cfg ~= nil then
		local id = (cfg :: any).id
		if typeof(id) == "number" then
			return id
		end
	end
	return 1
end

local function GetRandomMoveAngle(): number
	return math.random(0, 359)
end

local function GetRandomSpinDir(): number
	return (math.random(0, 1) == 0) and 1 or -1
end

local function GetSpawnPosition(): Vector3
	local arenaCenter, arenaSize = ArenaManager.GetArenaFloorInfo()
	local halfSize = (arenaSize.X / 2) - GameConfig.ArenaSpawnMargin
	local maxAttempts = 20
	local bestPos = arenaCenter

	for i = 1, maxAttempts do
		local randomX = (math.random() * 2 - 1) * halfSize
		local randomZ = (math.random() * 2 - 1) * halfSize
		local pos = arenaCenter + Vector3.new(randomX, GameConfig.UnitY - arenaCenter.Y, randomZ)

		local tooClose = false
		for _, unitInfo in unitInfoMap do
			local dist = (unitInfo.rootPart.Position * Vector3.new(1, 0, 1) - pos * Vector3.new(1, 0, 1)).Magnitude
			if dist < GameConfig.MinSpawnSeparation then
				tooClose = true
				break
			end
		end

		if not tooClose then
			return pos
		end
		bestPos = pos
		if i == maxAttempts then
			LogInfo(string.format("GetSpawnPosition warning: could not find separated position after %d attempts", maxAttempts))
		end
	end

	return bestPos
end

local function _GetMuzzleAttachment(unitModel: Model): Attachment?
	local barrelGroup = unitModel:FindFirstChild("TurretBarrel")
	if barrelGroup == nil then
		return nil
	end
	local muzzleAttachment = barrelGroup:FindFirstChild("MuzzleAttachment", true)
	if muzzleAttachment == nil or not muzzleAttachment:IsA("Attachment") then
		return nil
	end
	return muzzleAttachment
end

local function GetPlayerIdByVehicleModelName(modelName: string): number?
	if not modelName:match("^" .. VEHICLE_MODEL_NAME_PREFIX) then
		return nil
	end
	local userIdText = string.gsub(modelName, VEHICLE_MODEL_NAME_PREFIX, "")
	return tonumber(userIdText)
end

local function MoveModelKeepRotation(model: Model, targetPosition: Vector3)
	local pivot = model:GetPivot()
	local rotationOnly = pivot - pivot.Position
	model:PivotTo(CFrame.new(targetPosition) * rotationOnly)
end

-- 载具关节、Seat 与炮塔连接等以 ReplicatedStorage.Models.VehicleModel 在 Studio 中的配置为准；服务端仅克隆，不在运行时改装配。

local function ZeroHorizontalVelocity(part: BasePart)
	local v = part.AssemblyLinearVelocity
	part.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
end

local function CreateUnitModelForPlayer(player: Player): ServerUnitInfo?
	local playerInfo = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return nil
	end
	local vehicleId = tonumber(playerInfo.vehicleInventory.currentId) or 1
	print(string.format("[CombatManager] CreateUnitModelForPlayer userId=%d currentId=%s (num=%d)", player.UserId, playerInfo.vehicleInventory.currentId, vehicleId))
	local vehicleConfig = GameConfig.VehicleDataMap[vehicleId]
	if vehicleConfig == nil then
		warn("[CombatManager] Vehicle config not found for id:", vehicleId)
		return nil
	end

	local vehicleTemplate = GetVehicleTemplate(vehicleConfig.resourceName)

	if vehicleTemplate == nil then
		warn("[CombatManager] Vehicle model template not found for vehicleId:", vehicleId)
		return nil
	end
	local unitModel: Model = vehicleTemplate:Clone()
	unitModel.Name = "Vehicle_" .. tostring(player.UserId)
	pcall(function()
		unitModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	unitModel.Parent = workspace

	local rootPart = unitModel:FindFirstChild("BaseDisk")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		unitModel:Destroy()
		warn("[CombatManager] VehicleModel.BaseDisk not found.")
		return nil
	end
	unitModel.PrimaryPart = rootPart
	rootPart.CanCollide = true
	-- SetNetworkOwner(nil) 必须在未锚固时调用；对战期由服务端模拟载具物理
	rootPart.Anchored = false
	for _, inst in unitModel:GetDescendants() do
		if inst:IsA("BasePart") then
			local oldAnchored = inst.Anchored
			inst.Anchored = false
			pcall(function()
				inst:SetNetworkOwner(nil)
			end)
			inst.Anchored = oldAnchored
		end
	end
	
	-- 监听座位变动，防止玩家入座后 Roblox 自动将网络所有权转移给客户端导致争夺和卡顿（高速抽搐/周期性停顿根源）
	local seatInstance = unitModel:FindFirstChild("Seat", true)
	if seatInstance and seatInstance:IsA("Seat") then
		seatInstance:GetPropertyChangedSignal("Occupant"):Connect(function()
			if seatInstance.Occupant ~= nil then
				local primary = unitModel.PrimaryPart
				if primary and not primary.Anchored then
					pcall(function()
						primary:SetNetworkOwner(nil)
					end)
				end
			end
		end)
	end
	
	rootPart.Anchored = true

	local spawnPosition = GetSpawnPosition()
	local undergroundPosition = Vector3.new(spawnPosition.X, UNDERGROUND_Y, spawnPosition.Z)

	local moveAngle = GetRandomMoveAngle()
	local spinDir = GetRandomSpinDir()
	local tvx, tvz = VehicleLocomotionTool.AngleToVelocityXZ(moveAngle)

	local initYawRad = math.atan2(tvz, tvx)
	unitModel:PivotTo(CFrame.new(undergroundPosition) * VehicleLocomotionTool.UprightGoalCFrame(initYawRad))
	local unitInfo: ServerUnitInfo = {
		playerId = player.UserId,
		unitModel = unitModel,
		rootPart = rootPart,
		spinDir = spinDir,
		moveAngle = moveAngle,
		invincibleUntil = 0,
		targetVelX = tvx,
		targetVelZ = tvz,
		spinAngleRad = math.atan2(tvz, tvx),
		lastWallBounceClock = 0,
		lastVehicleBumpClock = 0,
		driveVectorForce = nil,
		vehicleConfig = vehicleConfig,
	}

	unitInfoMap[player.UserId] = unitInfo
	LogInfo(string.format("CreateUnit userId=%d spawn=%s moveAngle=%d spinDir=%d", player.UserId, FormatVector3(spawnPosition), moveAngle, spinDir))
	return unitInfo
end

local function GetOwnedVehicleModelForPlayer(player: Player): Model?
	local unitInfo = unitInfoMap[player.UserId]
	if unitInfo ~= nil then
		return unitInfo.unitModel
	end
	local byName = workspace:FindFirstChild(VEHICLE_MODEL_NAME_PREFIX .. tostring(player.UserId))
	if byName ~= nil and byName:IsA("Model") then
		return byName
	end
	return nil
end

local function unseatPlayerFromOwnedVehicle(player: Player)
	local unitModel = GetOwnedVehicleModelForPlayer(player)
	if unitModel == nil then
		return
	end
	local character = player.Character
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	local seatPart = humanoid.SeatPart
	if seatPart ~= nil and seatPart:IsDescendantOf(unitModel) then
		humanoid.Sit = false
		LogInfo(string.format("UnseatPlayerFromOwnedVehicle userId=%d", player.UserId))
	end
end

function CombatManager.DestroyUnitForPlayer(playerId: number)
	local unitInfo = unitInfoMap[playerId]
	if unitInfo == nil then
		local orphanName = VEHICLE_MODEL_NAME_PREFIX .. tostring(playerId)
		local orphan = workspace:FindFirstChild(orphanName)
		if orphan ~= nil and orphan:IsA("Model") then
			orphan:Destroy()
			LogInfo(string.format("DestroyUnit orphan workspace model userId=%d", playerId))
		else
			LogInfo(string.format("DestroyUnit skip userId=%d reason=unit_not_found", playerId))
		end
		return
	end
	if unitInfo.unitModel.Parent ~= nil then
		unitInfo.unitModel:Destroy()
	end
	unitInfoMap[playerId] = nil
	LogInfo(string.format("DestroyUnit userId=%d", playerId))
end

function CombatManager.PlayVehicleDeathEffect(playerId: number, hitDirection: Vector3?)
	local unitInfo = unitInfoMap[playerId]
	if unitInfo == nil then
		return
	end

	local model = unitInfo.unitModel
	unitInfoMap[playerId] = nil -- 立即停止模拟更新

	if model == nil or model.Parent == nil then
		return
	end

	LogInfo(string.format("PlayVehicleDeathEffect userId=%d", playerId))

	-- 0. 清理物理组件和残留速度，防止死亡后继续滑行
	for _, item in model:GetDescendants() do
		if
			item:IsA("VectorForce")
			or item:IsA("AngularVelocity")
			or item:IsA("AlignOrientation")
			or item:IsA("LinearVelocity")
		then
			item:Destroy()
		end
	end

	-- 1. 显式断开关节，确保肢体能分离（解体）
	model:BreakJoints()

	-- 2. 死亡表现参数（参考人物死亡）
	local explosionPower = 60
	local upwardPower = 40
	local spreadPower = 50

	local partInitialTransparencies = {}

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			-- 记录初始透明度，用于后续渐变判断
			local initial = part.Transparency
			partInitialTransparencies[part] = initial

			-- 取消锚固并开启物理
			part.Anchored = false

			-- 如果初始透明度已经是 1（透明底盘），则关闭碰撞，避免产生隐形墙
			if initial >= 0.99 then
				part.CanCollide = false
			end

			-- 关闭 Touch 和 Query 以免干扰战斗
			part.CanTouch = false
			part.CanQuery = false

			-- 清除旧的速度，应用爆炸冲量
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero

			-- 应用爆炸冲量
			local randomSpread = Vector3.new(
				(math.random() - 0.5) * spreadPower,
				math.random() * upwardPower,
				(math.random() - 0.5) * spreadPower
			)
			local hitImpulse = if hitDirection and hitDirection.Magnitude > 0 then hitDirection.Unit * explosionPower else Vector3.zero
			part.AssemblyLinearVelocity = hitImpulse + randomSpread

			-- 确保服务器拥有物理所有权
			pcall(function()
				part:SetNetworkOwner(nil)
			end)
		end
	end

	-- 3. 逐渐淡出并销毁
	task.spawn(function()
		local fadeDuration = 2.0
		local steps = 20
		for i = 1, steps do
			task.wait(fadeDuration / steps)
			if model.Parent == nil then
				break
			end
			local alpha = i / steps
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					local initial = partInitialTransparencies[part] or 0
					if initial < 0.99 then
						-- 仅对原本可见的部件进行渐变
						part.Transparency = initial + (1 - initial) * alpha
					end
				elseif part:IsA("Decal") then
					part.Transparency = alpha
				end
			end
		end
		model:Destroy()
	end)
end

local function ResetUnitToUnderground(playerId: number)
	local unitInfo = unitInfoMap[playerId]
	if unitInfo == nil then
		return
	end
	local root = unitInfo.rootPart
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	local pos = root.Position
	MoveModelKeepRotation(unitInfo.unitModel, Vector3.new(pos.X, UNDERGROUND_Y, pos.Z))
	LogInfo(string.format("ResetUnitToUnderground userId=%d", playerId))
end

function CombatManager.SetMatchState(matchState: GameConfig.MatchState)
	serverMatchState = matchState
end

local function StepVehicleSimulation(dt: number)
	for playerId, unitInfo in unitInfoMap do
		local root = unitInfo.rootPart
		if root.Parent == nil then
			continue
		end
		if root.Anchored then
			continue
		end

		local drive = unitInfo.driveVectorForce
		if drive == nil then
			drive = VehicleLocomotionTool.EnsureVehicleDriveConstraints(root)
			unitInfo.driveVectorForce = drive
		end
		local driveNotNull: VectorForce = drive :: VectorForce

		local vehicleConfig = unitInfo.vehicleConfig
		local unitSpeed = if vehicleConfig then (vehicleConfig.moveSpeed or GameConfig.UnitSpeed) else GameConfig.UnitSpeed

		local spinAV = root:FindFirstChild("SpinAngularVelocity")
		local avValue = Vector3.zero

		if serverMatchState == GameConfig.MatchState.GameStartCountdown then
			ZeroHorizontalVelocity(root)
			root.AssemblyAngularVelocity = Vector3.zero
			-- unitInfo.spinAngleRad = VehicleLocomotionTool.BaseDiskDriveYawRadFromState(unitInfo, root)
			VehicleLocomotionTool.UpdateBaseDiskLocomotion(unitInfo, root, driveNotNull, dt, false, unitSpeed)
		elseif serverMatchState == GameConfig.MatchState.Fighting then
			local roundInfo = PlayerStateManager.GetAllPlayerRoundInfoMap()[playerId]
			if roundInfo ~= nil and roundInfo.isParticipant and roundInfo.isAlive then
				avValue = Vector3.new(0, math.rad(GameConfig.UnitRotationSpeed) * unitInfo.spinDir, 0)
				VehicleLocomotionTool.UpdateBaseDiskLocomotion(unitInfo, root, driveNotNull, dt, true, unitSpeed)
				VehicleLocomotionTool.ResolveVehicleOverlaps(unitInfo, unitInfoMap :: any, playerId, dt)
			else
				VehicleLocomotionTool.UpdateBaseDiskLocomotion(unitInfo, root, driveNotNull, dt, false, unitSpeed)
			end
		else
			VehicleLocomotionTool.UpdateBaseDiskLocomotion(unitInfo, root, driveNotNull, dt, false, unitSpeed)
		end

		if spinAV and spinAV:IsA("AngularVelocity") then
			spinAV.AngularVelocity = avValue
		end
	end

	if serverMatchState == GameConfig.MatchState.Fighting then
		VehicleLocomotionTool.ResolveAllVehicleBumps(unitInfoMap :: any, function(playerIdForBump: number): boolean
			local roundInfoForBump = PlayerStateManager.GetAllPlayerRoundInfoMap()[playerIdForBump]
			return roundInfoForBump ~= nil and roundInfoForBump.isParticipant and roundInfoForBump.isAlive
		end, function(_playerIdA: number, _playerIdB: number, impactPosition: Vector3)
			NetMsg.FireNotifyImpact(impactPosition)
		end)
	end
end

function CombatManager.ResetUnitToUnderground(playerId: number)
	ResetUnitToUnderground(playerId)
end

function CombatManager.DestroyAllUnits()
	local ids = {}
	for playerId in unitInfoMap do
		table.insert(ids, playerId)
	end
	for _, playerId in ids do
		CombatManager.DestroyUnitForPlayer(playerId)
	end
end

local function _BroadcastUnitInit(unitInfo: ServerUnitInfo)
	local playerRoundInfo = PlayerStateManager.GetAllPlayerRoundInfoMap()[unitInfo.playerId]
	local maxHits = if unitInfo.vehicleConfig then unitInfo.vehicleConfig.maxHits else GameConfig.MaxHits
	local unitInitInfo: GameConfig.UnitInitInfo = {
		playerId = unitInfo.playerId,
		moveAngle = unitInfo.moveAngle,
		spinDir = unitInfo.spinDir,
		spawnPosition = unitInfo.rootPart.Position,
		maxHits = maxHits,
		isParticipant = if playerRoundInfo then playerRoundInfo.isParticipant else false,
		vehicleId = getVehicleIdFromUnitInfo(unitInfo),
	}
	NetMsg.FireNotifyUnitInitToAll(unitInitInfo)
	NetMsg.FireNotifyHpChanged(unitInfo.playerId, 0, maxHits)
	LogInfo(
		string.format(
			"BroadcastUnitInit userId=%d pos=%s moveAngle=%d spinDir=%d",
			unitInfo.playerId,
			FormatVector3(unitInfo.rootPart.Position),
			unitInfo.moveAngle,
			unitInfo.spinDir
		)
	)
end

local DEFAULT_PROJECTILE_RADIUS = 1.5
local projectileRadiusByTemplateMap: { [string]: number } = {}
local function GetProjectileRadius(templateName: string): number
	local cachedRadius = projectileRadiusByTemplateMap[templateName]
	if cachedRadius ~= nil then
		return cachedRadius
	end

	local projectileTemplate = bulletModelsFolder:FindFirstChild(templateName)
	if projectileTemplate == nil or not projectileTemplate:IsA("Model") then
		warn(string.format("[CombatManager] Projectile template not found when reading radius: %s", templateName))
		projectileRadiusByTemplateMap[templateName] = DEFAULT_PROJECTILE_RADIUS
		return DEFAULT_PROJECTILE_RADIUS
	end

	local corePart = projectileTemplate:FindFirstChild("Core")
	if corePart == nil or not corePart:IsA("BasePart") then
		warn(string.format("[CombatManager] Projectile Core not found when reading radius: %s", templateName))
		projectileRadiusByTemplateMap[templateName] = DEFAULT_PROJECTILE_RADIUS
		return DEFAULT_PROJECTILE_RADIUS
	end

	local size = corePart.Size
	local maxAxis = math.max(size.X, size.Y, size.Z)
	local computedRadius = maxAxis * 0.5
	if computedRadius <= 0 then
		computedRadius = DEFAULT_PROJECTILE_RADIUS
	end
	projectileRadiusByTemplateMap[templateName] = computedRadius
	return computedRadius
end

local function EnsureServerBulletsFolder(): Folder
	if serverBulletsFolder ~= nil and serverBulletsFolder.Parent ~= nil then
		return serverBulletsFolder
	end
	local existing = workspace:FindFirstChild(SERVER_BULLETS_FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		serverBulletsFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = SERVER_BULLETS_FOLDER_NAME
	folder.Parent = workspace
	serverBulletsFolder = folder
	return folder
end

local function IsServerProjectileModel(model: Model): boolean
	return string.sub(model.Name, 1, #SERVER_PROJECTILE_NAME_PREFIX) == SERVER_PROJECTILE_NAME_PREFIX
end

local preparedProjectileTemplateMap: { [string]: Model? } = {}
local pooledProjectileVisualMap: { [string]: { [number]: { model: Model, physicsRoot: BasePart, visualWeld: Motor6D, linearVelocity: LinearVelocity } } } = {}
local raycastParamsPool: { RaycastParams } = {}
local excludeListPool: { { Instance } } = {}

local function AcquireRaycastParams(): RaycastParams
	local rp = table.remove(raycastParamsPool)
	if rp ~= nil then
		return rp
	end
	local created = RaycastParams.new()
	created.FilterType = Enum.RaycastFilterType.Exclude
	return created
end

local function ReleaseRaycastParams(rp: RaycastParams)
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {}
	table.insert(raycastParamsPool, rp)
end

local function AcquireExcludeList(): { Instance }
	local list = table.remove(excludeListPool)
	if list ~= nil then
		table.clear(list)
		return list
	end
	return {}
end

local function ReleaseExcludeList(list: { Instance })
	table.clear(list)
	table.insert(excludeListPool, list)
end

local function EnsurePreparedProjectileTemplate(templateName: string): Model?
	local cached = preparedProjectileTemplateMap[templateName]
	if cached ~= nil and cached.Parent ~= nil then
		return cached
	end

	local projectileTemplate = bulletModelsFolder:FindFirstChild(templateName)
	if projectileTemplate == nil or not projectileTemplate:IsA("Model") then
		warn("[CombatManager] ProjectileModel template not found:", templateName)
		return nil
	end

	local visualRoot = projectileTemplate:FindFirstChild("Core")
	if visualRoot == nil or not visualRoot:IsA("BasePart") then
		warn("[CombatManager] ProjectileModel.Core not found:", templateName)
		return nil
	end

	local physicsRoot = projectileTemplate:FindFirstChild(PROJECTILE_PHYSICS_ROOT_NAME)
	if physicsRoot == nil or not physicsRoot:IsA("BasePart") then
		local newPhysicsRoot = Instance.new("Part")
		newPhysicsRoot.Name = PROJECTILE_PHYSICS_ROOT_NAME
		newPhysicsRoot.Size = Vector3.new(1, 1, 1)
		newPhysicsRoot.Transparency = 1
		newPhysicsRoot.CanCollide = false
		newPhysicsRoot.Massless = true
		newPhysicsRoot.Anchored = false
		newPhysicsRoot.Parent = projectileTemplate
		physicsRoot = newPhysicsRoot
	end
	local physicsRootPart = physicsRoot :: BasePart
	projectileTemplate.PrimaryPart = physicsRootPart

	local visualWeld = physicsRootPart:FindFirstChild(PROJECTILE_VISUAL_WELD_NAME)
	if visualWeld == nil or not visualWeld:IsA("Motor6D") then
		local newVisualWeld = Instance.new("Motor6D")
		newVisualWeld.Name = PROJECTILE_VISUAL_WELD_NAME
		newVisualWeld.Part0 = physicsRootPart
		newVisualWeld.Part1 = visualRoot
		newVisualWeld.C0 = CFrame.new()
		newVisualWeld.Parent = physicsRootPart
	end

	local driveAttachment = physicsRootPart:FindFirstChild(PROJECTILE_DRIVE_ATTACHMENT_NAME)
	if driveAttachment == nil or not driveAttachment:IsA("Attachment") then
		local newAttachment = Instance.new("Attachment")
		newAttachment.Name = PROJECTILE_DRIVE_ATTACHMENT_NAME
		newAttachment.Parent = physicsRootPart
		driveAttachment = newAttachment
	end
	local driveAttachmentRef = driveAttachment :: Attachment

	local alignOrientation = physicsRootPart:FindFirstChild(PROJECTILE_ALIGN_ORIENTATION_NAME)
	if alignOrientation == nil or not alignOrientation:IsA("AlignOrientation") then
		local newAlignOrientation = Instance.new("AlignOrientation")
		newAlignOrientation.Name = PROJECTILE_ALIGN_ORIENTATION_NAME
		newAlignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		newAlignOrientation.Attachment0 = driveAttachmentRef
		newAlignOrientation.RigidityEnabled = true
		newAlignOrientation.CFrame = CFrame.new()
		newAlignOrientation.Parent = physicsRootPart
	end

	local linearVelocity = physicsRootPart:FindFirstChild(PROJECTILE_LINEAR_VELOCITY_NAME)
	if linearVelocity == nil or not linearVelocity:IsA("LinearVelocity") then
		local newLinearVelocity = Instance.new("LinearVelocity")
		newLinearVelocity.Name = PROJECTILE_LINEAR_VELOCITY_NAME
		newLinearVelocity.Attachment0 = driveAttachmentRef
		newLinearVelocity.MaxForce = math.huge
		newLinearVelocity.VectorVelocity = Vector3.zero
		newLinearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		newLinearVelocity.Parent = physicsRootPart
	end

	-- 模板预处理一次：视觉件全部焊到 Core，发射时不再重复创建约束
	if projectileTemplate:GetAttribute(PROJECTILE_PREPARED_ATTR) ~= true then
		for _, d in projectileTemplate:GetDescendants() do
			if d:IsA("BasePart") and d ~= physicsRootPart then
				d.Anchored = false
				d.Massless = true
				d.CanCollide = false
				if d ~= visualRoot then
					local existingWeld = d:FindFirstChild("WeldToCore")
					if existingWeld == nil then
						local weld = Instance.new("WeldConstraint")
						weld.Name = "WeldToCore"
						weld.Part0 = visualRoot
						weld.Part1 = d
						weld.Parent = d
					end
				end
			end
		end
		projectileTemplate:SetAttribute(PROJECTILE_PREPARED_ATTR, true)
	end

	preparedProjectileTemplateMap[templateName] = projectileTemplate
	return projectileTemplate
end

local function CreateServerProjectileVisual(shooterId: number, spawnPos: Vector3, shotDir: Vector3, bulletId: string, modelName: string?): (Model?, BasePart?, Motor6D?, LinearVelocity?)
	local templateName = modelName or "ProjectileModel"
	local projectileModel: Model? = nil
	local physicsRoot: BasePart? = nil
	local rootWeld: Motor6D? = nil
	local linearVelocity: LinearVelocity? = nil

	local poolList = pooledProjectileVisualMap[templateName]
	if poolList ~= nil and #poolList > 0 then
		local reused = table.remove(poolList)
		if reused ~= nil and reused.model.Parent == nil then
			projectileModel = reused.model
			physicsRoot = reused.physicsRoot
			rootWeld = reused.visualWeld
			linearVelocity = reused.linearVelocity
		end
	end

	if projectileModel == nil then
		local projectileTemplate = EnsurePreparedProjectileTemplate(templateName)
		if projectileTemplate == nil then
			return nil
		end
		local createdModel = projectileTemplate:Clone()
		projectileModel = createdModel
		local visualRoot = createdModel:FindFirstChild("Core")
		if visualRoot == nil or not visualRoot:IsA("BasePart") then
			createdModel:Destroy()
			warn("[CombatManager] ProjectileModel.Core not found.")
			return nil
		end

		local clonedPhysicsRoot = createdModel:FindFirstChild(PROJECTILE_PHYSICS_ROOT_NAME)
		if clonedPhysicsRoot == nil or not clonedPhysicsRoot:IsA("BasePart") then
			createdModel:Destroy()
			warn("[CombatManager] ProjectileModel.PhysicsRoot not found.")
			return nil
		end
		createdModel.PrimaryPart = clonedPhysicsRoot

		local clonedRootWeld = clonedPhysicsRoot:FindFirstChild(PROJECTILE_VISUAL_WELD_NAME)
		local clonedLinearVelocity = clonedPhysicsRoot:FindFirstChild(PROJECTILE_LINEAR_VELOCITY_NAME)
		if clonedRootWeld == nil or not clonedRootWeld:IsA("Motor6D") then
			createdModel:Destroy()
			warn("[CombatManager] ProjectileModel.VisualWeld not found.")
			return nil
		end
		if clonedLinearVelocity == nil or not clonedLinearVelocity:IsA("LinearVelocity") then
			createdModel:Destroy()
			warn("[CombatManager] ProjectileModel.ProjectileLinearVelocity not found.")
			return nil
		end
		physicsRoot = clonedPhysicsRoot
		rootWeld = clonedRootWeld
		linearVelocity = clonedLinearVelocity
	end

	local projectileModelRef = projectileModel :: Model
	local physicsRootRef = physicsRoot :: BasePart
	local rootWeldRef = rootWeld :: Motor6D
	local linearVelocityRef = linearVelocity :: LinearVelocity

	projectileModelRef.Parent = EnsureServerBulletsFolder()
	projectileModelRef.Name = SERVER_PROJECTILE_NAME_PREFIX .. bulletId
	projectileModelRef:SetAttribute(SERVER_BULLET_SHOOTER_USER_ID_ATTR, shooterId)
	projectileModelRef.PrimaryPart = physicsRootRef

	local visualRoot = projectileModelRef:FindFirstChild("Core")
	if visualRoot == nil or not visualRoot:IsA("BasePart") then
		projectileModelRef:Destroy()
		return nil
	end

	local flatShot = ToHorizontalDirection(shotDir)
	rootWeldRef.Part0 = physicsRootRef
	rootWeldRef.Part1 = visualRoot
	rootWeldRef.C0 = CFrame.lookAt(Vector3.zero, flatShot)
	linearVelocityRef.VectorVelocity = Vector3.zero
	physicsRootRef.AssemblyLinearVelocity = Vector3.zero
	physicsRootRef.AssemblyAngularVelocity = Vector3.zero

	-- SAFELY move the whole assembly to spawnPos
	projectileModelRef:PivotTo(CFrame.new(spawnPos))

	-- Server assumes physics ownership for reliable replication
	pcall(function()
		physicsRootRef:SetNetworkOwner(nil)
	end)

	return projectileModelRef, physicsRootRef, rootWeldRef, linearVelocityRef
end

local function RecycleServerProjectileVisual(templateName: string, model: Model?, physicsRoot: BasePart?, visualWeld: Motor6D?, linearVelocity: LinearVelocity?)
	if model == nil or physicsRoot == nil or visualWeld == nil or linearVelocity == nil then
		if model ~= nil then
			model:Destroy()
		end
		return
	end
	if model.Parent == nil then
		return
	end

	physicsRoot.AssemblyLinearVelocity = Vector3.zero
	physicsRoot.AssemblyAngularVelocity = Vector3.zero
	linearVelocity.VectorVelocity = Vector3.zero
	model:SetAttribute(SERVER_BULLET_SHOOTER_USER_ID_ATTR, nil)
	model.Name = "PooledProjectile"
	model.Parent = nil

	local poolList = pooledProjectileVisualMap[templateName]
	if poolList == nil then
		poolList = {}
		pooledProjectileVisualMap[templateName] = poolList
	end
	if #poolList >= PROJECTILE_POOL_LIMIT_PER_TEMPLATE then
		model:Destroy()
		return
	end
	table.insert(poolList, {
		model = model,
		physicsRoot = physicsRoot,
		visualWeld = visualWeld,
		linearVelocity = linearVelocity,
	})
end

local function PivotServerProjectileToBullet(bullet: ServerBullet, displayPos: Vector3, instantSnap: boolean?)
	local vm = bullet.visualModel
	if vm == nil or vm.Parent == nil then
		return
	end
	local look = ToHorizontalDirection(bullet.shotDir)
	
	local root = bullet.physicsRoot or vm.PrimaryPart
	if root then
		local visualWeld = bullet.visualWeld
		if visualWeld ~= nil and visualWeld.Parent ~= nil then
			-- Updating C0 bypasses physics interpolation, making the rotation snap instantly on clients
			visualWeld.C0 = CFrame.lookAt(Vector3.zero, look)
		end
		
		if bullet.physicsStarted then
			local lv = bullet.linearVelocity
			if lv ~= nil and lv.Parent ~= nil then
				lv.VectorVelocity = look * bullet.speed
			end
			if instantSnap then
				-- 反弹帧只强制速度/角速度与朝向，避免强改位置导致的单帧停顿感
				root.AssemblyLinearVelocity = look * bullet.speed
				root.AssemblyAngularVelocity = Vector3.zero
			end
		else
			root.CFrame = CFrame.new(displayPos)
		end
	end
end

local function DestroyServerBullet(bulletId: string)
	local bullet = activeServerBullets[bulletId]
	if bullet == nil then
		return
	end
	RecycleServerProjectileVisual(bullet.templateName, bullet.visualModel, bullet.physicsRoot, bullet.visualWeld, bullet.linearVelocity)
	-- 同步减少计数
	local sid = bullet.shooterId
	if shooterBulletCountMap[sid] ~= nil then
		shooterBulletCountMap[sid] = math.max(0, shooterBulletCountMap[sid] - 1)
	end
	activeServerBullets[bulletId] = nil
end

local function PrewarmProjectileTemplates()
	local preparedNameMap: { [string]: boolean } = {}
	preparedNameMap["ProjectileModel"] = true
	EnsurePreparedProjectileTemplate("ProjectileModel")

	for _, vehicleConfig in GameConfig.VehicleDataMap do
		local bulletData = if vehicleConfig then vehicleConfig.bulletData else nil
		local resourceName = if bulletData then bulletData.resourceName else nil
		if typeof(resourceName) == "string" and resourceName ~= "" and not preparedNameMap[resourceName] then
			preparedNameMap[resourceName] = true
			EnsurePreparedProjectileTemplate(resourceName)
		end
	end
end

local function ResolveProjectileHit(shooterId: number, targetPlayerId: number, hitDirection: Vector3, bulletId: string, hitPosition: Vector3)
	hitDirection = ToHorizontalDirection(hitDirection)

	if targetPlayerId == shooterId and not GameConfig.CanHitSelf then
		LogInfo(string.format("ProjectileHit ignored shooterId=%d targetId=%d", shooterId, targetPlayerId))
		return
	end

	local targetUnitInfo = unitInfoMap[targetPlayerId]
	local isProtected = false
	if targetUnitInfo ~= nil then
		local now = os.clock()
		if now < targetUnitInfo.invincibleUntil then
			isProtected = true
			LogInfo(string.format("ProjectileHit damage ignored targetId=%d reason=invincible", targetPlayerId))
		else
			targetUnitInfo.invincibleUntil = now + GameConfig.InvincibilityDuration
		end

		targetUnitInfo.spinDir = GetRandomSpinDir()
		NetMsg.FireNotifyDirectionFlipToAll(targetPlayerId)
	end

	local hitCount: number = 0
	local isDead: boolean = false
	local maxHits = if targetUnitInfo ~= nil then targetUnitInfo.vehicleConfig.maxHits else GameConfig.MaxHits
	if isProtected then
		hitCount = PlayerStateManager.GetPlayerHitCount(targetPlayerId)
		isDead = false
	else
		hitCount, isDead = PlayerStateManager.AddPlayerHit(targetPlayerId, maxHits)
	end

	-- 仅在受到伤害且未死亡的情况下开启无敌特效
	if not isProtected and not isDead and targetUnitInfo ~= nil then
		targetUnitInfo.unitModel:SetAttribute("IsInvincible", true)
		task.delay(GameConfig.InvincibilityDuration, function()
			if targetUnitInfo.unitModel.Parent ~= nil then
				targetUnitInfo.unitModel:SetAttribute("IsInvincible", false)
			end
		end)
	end

	if not isProtected and not isDead and targetUnitInfo ~= nil then
		local flatDir = Vector3.new(hitDirection.X, 0, hitDirection.Z)
		if flatDir.Magnitude > 0.001 then
			local knockbackDir = flatDir.Unit
			local unitSpeed = targetUnitInfo.vehicleConfig.moveSpeed or GameConfig.UnitSpeed
			targetUnitInfo.rootPart.AssemblyLinearVelocity = knockbackDir * (unitSpeed * GameConfig.BulletHitSpeedMultiplier)
			targetUnitInfo.targetVelX = knockbackDir.X * unitSpeed
			targetUnitInfo.targetVelZ = knockbackDir.Z * unitSpeed
		end
	end

	if isDead and targetUnitInfo ~= nil then
		targetUnitInfo.targetVelX = 0
		targetUnitInfo.targetVelZ = 0
		ZeroHorizontalVelocity(targetUnitInfo.rootPart)
	end

	LogInfo(
		string.format(
			"HitResolved shooterId=%d targetId=%d hitCount=%d isDead=%s direction=%s",
			shooterId,
			targetPlayerId,
			hitCount,
			tostring(isDead),
			FormatVector3(hitDirection)
		)
	)
	NetMsg.FireNotifyHit(targetPlayerId, shooterId, hitDirection, hitCount, bulletId, hitPosition)
	NetMsg.FireNotifyHpChanged(targetPlayerId, hitCount, maxHits)

	--增加金币奖励
	if shooterId ~= targetPlayerId then
		local shooterPlayer = players:GetPlayerByUserId(shooterId)
		if shooterPlayer ~= nil then
			if isDead then
				--击杀奖励
				ServerGameInfo.UpdatePlayerCurrency(shooterPlayer, GameConfig.CurrencyType.Coin, 2, GameConfig.ItemCountChangeReason.GainFromKill)
				LeaderboardManager.AddStat(shooterPlayer, GameConfig.LeaderboardCategory.WeeklyKills, 1)
				LeaderboardManager.AddStat(shooterPlayer, GameConfig.LeaderboardCategory.WeeklyEarnings, 2)
			else
				--命中奖励
				ServerGameInfo.UpdatePlayerCurrency(shooterPlayer, GameConfig.CurrencyType.Coin, 1, GameConfig.ItemCountChangeReason.GainFromHit)
				LeaderboardManager.AddStat(shooterPlayer, GameConfig.LeaderboardCategory.WeeklyEarnings, 1)
			end
		end
	end

	if isDead then
		NetMsg.FireNotifyDead(targetPlayerId, shooterId)
		local targetPlayer = players:GetPlayerByUserId(targetPlayerId)
		if targetPlayer ~= nil and playerDeadCallback ~= nil then
			LogInfo(string.format("NotifyPlayerDead userId=%d", targetPlayerId))
			task.defer(playerDeadCallback, targetPlayer, false, hitDirection)
		end
	end
end

function CombatManager.OnHeartbeat(dt: number)
	StepVehicleSimulation(dt)

	local currentServerTime = workspace:GetServerTimeNow()

	for bulletId, bullet in activeServerBullets do
		-- 激活前：仅在首帧定位 visualModel，然后 continue 跳过物理更新
		if currentServerTime < bullet.activeTime then
			if bullet.visualModel ~= nil and bullet.visualModel.Parent ~= nil and not bullet.visualSpawned then
				PivotServerProjectileToBullet(bullet, bullet.spawnPos)
				bullet.visualSpawned = true
			end
			continue
		end
		
		if not bullet.physicsStarted then
			bullet.physicsStarted = true
			PivotServerProjectileToBullet(bullet, bullet.currentPos)
		end

		if (currentServerTime - bullet.activeTime) > bullet.lifetime then
			DestroyServerBullet(bulletId)
			continue
		end
		if bullet.distanceTraveled >= bullet.maxDistance then
			DestroyServerBullet(bulletId)
			continue
		end

		local stepDist = bullet.speed * dt
		local origin = bullet.currentPos
		local frameStartPos = bullet.currentPos
		local shotDir = bullet.shotDir
		local remaining = stepDist + GameConfig.ProjectileStepMargin

		local rayParams = AcquireRaycastParams()
		local excludeList = AcquireExcludeList()
		local function ReleaseRaycastContext()
			ReleaseRaycastParams(rayParams)
			ReleaseExcludeList(excludeList)
		end

		local shooterUnitInfo = unitInfoMap[bullet.shooterId]
		if shooterUnitInfo and shooterUnitInfo.unitModel then
			table.insert(excludeList, shooterUnitInfo.unitModel)
		end
		local shooterPlayer = players:GetPlayerByUserId(bullet.shooterId)
		if shooterPlayer and shooterPlayer.Character then
			table.insert(excludeList, shooterPlayer.Character)
		end

		-- Allow hitting self if configured and bounces ran out (simulating that the bullet already bounced so self is exposed)
		-- Or if not configured, we keep self in exclude list.
		if GameConfig.CanHitSelf and bullet.bouncesLeft < bullet.maxBounces then
			-- It bounced at least once, can hit self, so don't exclude self.
			table.clear(excludeList)
		end

		rayParams.FilterDescendantsInstances = excludeList

		local hitResult: RaycastResult? = nil
		-- Use visual-matched radius to avoid early wall bounces before visible contact
		local radius = bullet.hitRadius

		for _ = 1, 10 do
			if remaining < 1e-4 then
				break
			end
			local res = workspace:Spherecast(origin, radius, shotDir * remaining, rayParams)
			if res == nil then
				break
			end

			local inst = res.Instance
			local shouldPass = false
			if inst:IsA("BasePart") then
				if inst.Name == "ArenaFloor" or inst.Name == "Ground" then
					shouldPass = true
				else
					local tm = inst:FindFirstAncestorOfClass("Model")
					if tm ~= nil then
						if tm.Name == "LocalProjectile" or IsServerProjectileModel(tm) then
							shouldPass = true
						end
					end
				end
			end

			if shouldPass then
				table.insert(excludeList, inst)
				rayParams.FilterDescendantsInstances = excludeList
				continue
			end
			hitResult = res
			break
		end

		if hitResult ~= nil then
			local inst = hitResult.Instance
			local targetId: number? = nil
			local currentAncestor = inst.Parent
			while currentAncestor and currentAncestor ~= workspace do
				if currentAncestor:IsA("Model") then
					targetId = GetPlayerIdByVehicleModelName(currentAncestor.Name)
					if targetId ~= nil then
						break
					end
					local charPlayer = players:GetPlayerFromCharacter(currentAncestor)
					if charPlayer then
						targetId = charPlayer.UserId
						break
					end
				end
				currentAncestor = currentAncestor.Parent
			end

			if targetId ~= nil then
				if targetId ~= bullet.shooterId or GameConfig.CanHitSelf then
					ResolveProjectileHit(bullet.shooterId, targetId, shotDir, bulletId, hitResult.Position)
				end
				ReleaseRaycastContext()
				DestroyServerBullet(bulletId)
				continue
			end

			if bullet.bouncesLeft > 0 then
				bullet.bouncesLeft -= 1

				local n = hitResult.Normal
				local nFlat = Vector3.new(n.X, 0, n.Z)
				if nFlat.Magnitude > 0.01 then
					nFlat = nFlat.Unit
				else
					nFlat = -shotDir
				end
				local impactCenter = origin + shotDir * hitResult.Distance

				local dot = shotDir:Dot(nFlat)
				if dot < 0 then
					shotDir = shotDir - 2 * dot * nFlat
				end

				local flatDir = Vector3.new(shotDir.X, 0, shotDir.Z)
				if flatDir.Magnitude > 0.01 then
					shotDir = flatDir.Unit
				end

				-- 确保反弹后有最小的离开角度，避免完美的平行滑动导致 Spherecast 穿模
				if shotDir:Dot(nFlat) < 0.05 then
					shotDir = (shotDir + nFlat * 0.05).Unit
				end

				bullet.shotDir = shotDir
				-- 反弹后继续对剩余路径做子步骤检测，防止高速子弹穿模
				local distanceRemaining = math.max(0, stepDist - hitResult.Distance)
				
				-- 反弹后按当前子弹半径推离墙体，避免大尺寸子弹下一帧仍处于接触区而被误判为再次撞墙
				local separationDistance = math.max(PROJECTILE_BOUNCE_SEPARATION_BIAS, radius + PROJECTILE_BOUNCE_SEPARATION_BIAS)
				origin = impactCenter + nFlat * separationDistance
				remaining = distanceRemaining
				bullet.currentPos = origin
				bullet.distanceTraveled += (bullet.currentPos - frameStartPos).Magnitude
				if bullet.distanceTraveled >= bullet.maxDistance then
					ReleaseRaycastContext()
					DestroyServerBullet(bulletId)
					continue
				end
				PivotServerProjectileToBullet(bullet, bullet.currentPos, true)
				ReleaseRaycastContext()
				continue
			end

			ReleaseRaycastContext()
			DestroyServerBullet(bulletId)
			continue
		end

		bullet.currentPos = origin + shotDir * stepDist
		bullet.distanceTraveled += (bullet.currentPos - frameStartPos).Magnitude
		ReleaseRaycastContext()
		if bullet.distanceTraveled >= bullet.maxDistance then
			DestroyServerBullet(bulletId)
			continue
		end
		-- visualModel 已经通过 LinearVelocity 自动平滑移动，无需每帧 PivotTo 造成客户端卡顿
		-- PivotServerProjectileToBullet(bullet, bullet.currentPos)
	end
end

function CombatManager.Init(onPlayerDead: OnPlayerDeadCallback)
	playerDeadCallback = onPlayerDead
	NetMsg.ConnectRequestFire(CombatManager.OnRequestFire)
	NetMsg.ConnectRequestSyncUnit(CombatManager.SyncToPlayer)
	-- 完全服务端权威模式：不再监听 RequestHit，所有命中由 OnHeartbeat 物理轨迹决定

	if heartbeatConnection == nil then
		heartbeatConnection = runService.Heartbeat:Connect(CombatManager.OnHeartbeat)
	end

	EnsureServerBulletsFolder()
	PrewarmProjectileTemplates()

	LogInfo("Init success [server-authoritative mode]")
end

-- OnRequestHit 已在服务端权威模式下移除；命中判定完全由 OnHeartbeat 物理轨迹负责

function CombatManager.SyncToPlayer(player: Player)
	LogInfo(string.format("SyncToPlayer userId=%d", player.UserId))
	-- Sync existing participation units to this new joiner
	local roundInfoMap = PlayerStateManager.GetAllPlayerRoundInfoMap()
	for otherId, otherUnitInfo in unitInfoMap do
		if otherId == player.UserId then
			continue
		end

		local otherRoundInfo = roundInfoMap[otherId]
		local maxHits = if otherUnitInfo.vehicleConfig then otherUnitInfo.vehicleConfig.maxHits else GameConfig.MaxHits
		NetMsg.FireNotifyUnitInit(player, {
			playerId = otherId,
			moveAngle = otherUnitInfo.moveAngle,
			spinDir = otherUnitInfo.spinDir,
			spawnPosition = otherUnitInfo.rootPart.Position,
			maxHits = maxHits,
			isParticipant = if otherRoundInfo then otherRoundInfo.isParticipant else false,
			vehicleId = getVehicleIdFromUnitInfo(otherUnitInfo),
		})

		-- Sync current HP
		local hitCount = PlayerStateManager.GetPlayerHitCount(otherId)
		NetMsg.FireNotifyHpChangedToPlayer(player, otherId, hitCount, maxHits)
	end
end

function CombatManager.OnPlayerAdded(player: Player)
	PlayerStateManager.EnsurePlayerRoundInfo(player)
	LogInfo(string.format("OnPlayerAdded userId=%d", player.UserId))
end

function CombatManager.OnPlayerRemoving(player: Player)
	LogInfo(string.format("OnPlayerRemoving userId=%d", player.UserId))

	local userId = player.UserId
	local roundInfoMap = PlayerStateManager.GetAllPlayerRoundInfoMap()
	local roundInfo = roundInfoMap[userId]
	local shouldNotifyDead = roundInfo ~= nil and roundInfo.isParticipant and roundInfo.isAlive

	unseatPlayerFromOwnedVehicle(player)
	CombatManager.DestroyUnitForPlayer(userId)
	PlayerStateManager.RemovePlayerRoundInfo(userId)
	NetMsg.FireNotifyUnitRemoveToAll(userId)

	if shouldNotifyDead then
		NetMsg.FireNotifyDead(userId, nil)
		if playerDeadCallback ~= nil then
			local ok, err = pcall(function()
				playerDeadCallback(player, true)
			end)
			if not ok then
				warn(string.format("%s OnPlayerRemoving playerDeadCallback failed userId=%d err=%s", LOG_PREFIX, userId, tostring(err)))
			end
		end
	end
end

function CombatManager.OnRequestFire(player: Player, clientTimestamp: number, bulletId: string)
	local unitInfo = unitInfoMap[player.UserId]
	local cooldown = if unitInfo then unitInfo.vehicleConfig.fireCooldown else GameConfig.FireCooldown

	local nowTime = os.clock()
	local canFire = PlayerStateManager.CanFire(player.UserId, nowTime, cooldown)
	if not canFire then
		LogInfo(string.format("FireRejected userId=%d reason=cooldown_or_dead now=%.2f", player.UserId, nowTime))
		return
	end

	local count = shooterBulletCountMap[player.UserId] or 0
	if count >= 3 then
		LogInfo(string.format("FireRejected userId=%d reason=bullet_spam_limit", player.UserId))
		return
	end

	PlayerStateManager.SetLastFireTime(player.UserId, nowTime)

	unitInfo = unitInfoMap[player.UserId]
	if unitInfo == nil then
		return
	end
	local bulletData = if unitInfo then unitInfo.vehicleConfig.bulletData else nil
	local bounces = if bulletData then bulletData.maxBounces else (GameConfig.ProjectileMaxBounces or 0)
	local bulletResource = if bulletData then bulletData.resourceName else "ProjectileModel"
	local bulletSpeed = if bulletData then bulletData.moveSpeed else GameConfig.ProjectileSpeed
	local bulletLifetime = if bulletData then bulletData.lifetime else GameConfig.ProjectileLifetime
	local bulletMaxDistance = if bulletData then bulletData.maxDistance else GameConfig.MaxProjectileDistance
	bulletSpeed = math.max(0.01, bulletSpeed)
	bulletLifetime = math.max(0.01, bulletLifetime)
	bulletMaxDistance = math.max(0.01, bulletMaxDistance)
	EnsurePreparedProjectileTemplate(bulletResource)
	local bulletRadius = GetProjectileRadius(bulletResource)

	local spawnPos = Vector3.zero
	local shotDirection = Vector3.new(0, 0, -1)

	local muzzleAttachment = _GetMuzzleAttachment(unitInfo.unitModel)
	if muzzleAttachment ~= nil then
		spawnPos = muzzleAttachment.WorldCFrame.Position
		local flat = Vector3.new(muzzleAttachment.WorldCFrame.LookVector.X, 0, muzzleAttachment.WorldCFrame.LookVector.Z)
		if flat.Magnitude > 0.001 then
			shotDirection = flat.Unit
		end
	else
		local fallbackCFrame = unitInfo.rootPart.CFrame * CFrame.new(0, 1.2, -3.4)
		spawnPos = fallbackCFrame.Position
		local flat = Vector3.new(unitInfo.rootPart.CFrame.LookVector.X, 0, unitInfo.rootPart.CFrame.LookVector.Z)
		if flat.Magnitude > 0.001 then
			shotDirection = flat.Unit
		end
	end

	local rayOrigin = unitInfo.rootPart.Position + Vector3.new(0, 1.2, 0)
	local toSpawn = spawnPos - rayOrigin
	if toSpawn.Magnitude > 0.01 then
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local excludeList: { Instance } = { unitInfo.unitModel }
		local character = player.Character
		if character ~= nil then
			table.insert(excludeList, character)
		end
		rayParams.FilterDescendantsInstances = excludeList

		local dist = toSpawn.Magnitude
		local dir = toSpawn.Unit

		local hitPoint = nil
		local curOrigin = rayOrigin
		local remaining = dist
		for _ = 1, 10 do
			if remaining < 1e-4 then
				break
			end
			local res = workspace:Raycast(curOrigin, dir * remaining, rayParams)
			if res == nil then
				break
			end

			if res.Instance.Name == "ArenaFloor" or res.Instance.Name == "Ground" then
				table.insert(excludeList, res.Instance)
				rayParams.FilterDescendantsInstances = excludeList
				curOrigin = res.Position + dir * 0.01
				remaining = remaining - res.Distance - 0.01
				continue
			end
			hitPoint = res.Position
			break
		end

		if hitPoint ~= nil then
			local projRadius = bulletRadius
			local safeDist = math.max(0, (hitPoint - rayOrigin).Magnitude - (projRadius * 2 + 0.1))
			spawnPos = rayOrigin + (dir * safeDist)
		end
	end

	unitInfo.spinDir = -unitInfo.spinDir

	local serverTime = workspace:GetServerTimeNow()
	local estimatedRtt = math.clamp(
		serverTime - clientTimestamp,
		GameConfig.HitValidationClientTimestampMinDelta or -0.2,
		GameConfig.HitValidationClientTimestampMaxDelta or 0.6
	)
	local bulletLaunchTime = clientTimestamp + GameConfig.FireCastTime

	local visualModel, physicsRoot, visualWeld, linearVelocity =
		CreateServerProjectileVisual(player.UserId, spawnPos, shotDirection, bulletId, bulletResource)
	activeServerBullets[bulletId] = {
		shooterId = player.UserId,
		templateName = bulletResource,
		spawnPos = spawnPos,
		shotDir = shotDirection,
		activeTime = bulletLaunchTime,
		speed = bulletSpeed,
		lifetime = bulletLifetime,
		maxDistance = bulletMaxDistance,
		maxBounces = bounces,
		distanceTraveled = 0,
		hitRadius = bulletRadius,
		bouncesLeft = bounces,
		currentPos = spawnPos,
		estimatedRtt = math.max(0, estimatedRtt),
		visualModel = visualModel,
		physicsRoot = physicsRoot,
		visualWeld = visualWeld,
		linearVelocity = linearVelocity,
		visualSpawned = false,
		physicsStarted = false,
	}
	-- 同步增加计数
	shooterBulletCountMap[player.UserId] = (shooterBulletCountMap[player.UserId] or 0) + 1

	local shooterUnit = unitInfoMap[player.UserId]
	if shooterUnit ~= nil then
		local recoilDir = -shotDirection
		local unitSpeed = shooterUnit.vehicleConfig.moveSpeed or GameConfig.UnitSpeed
		local recoilSpeed = unitSpeed * GameConfig.FireRecoilSpeedMultiplier
		shooterUnit.rootPart.AssemblyLinearVelocity = recoilDir * recoilSpeed
		shooterUnit.targetVelX = recoilDir.X * recoilSpeed
		shooterUnit.targetVelZ = recoilDir.Z * recoilSpeed
	end

	LogInfo(string.format("FireAccepted userId=%d bulletId=%s", player.UserId, bulletId))
	NetMsg.FireNotifyDirectionFlipToAll(player.UserId)
	NetMsg.FireNotifyFireAccepted(player.UserId, clientTimestamp, spawnPos, shotDirection, serverTime, bulletId)
end

function CombatManager.StartRound(participantIds: { number })
	LogInfo("StartRound begin")
	local staleBulletIds: { string } = {}
	for id in activeServerBullets do
		table.insert(staleBulletIds, id)
	end
	for _, id in staleBulletIds do
		DestroyServerBullet(id)
	end
	-- 确保计数表与子弹表同步归零
	shooterBulletCountMap = {}
	PlayerStateManager.ResetAllPlayerRoundInfo(participantIds)
	for _, playerId in participantIds do
		-- 无论之前有没有，都先尝试销毁旧载具并重新创建，以支持比赛间隙的载具切换
		CombatManager.DestroyUnitForPlayer(playerId)

		local player = players:GetPlayerByUserId(playerId)
		local unitInfo = if player then CreateUnitModelForPlayer(player) else nil
		
		if unitInfo == nil then
			continue
		end
		unitInfo.moveAngle = GetRandomMoveAngle()
		unitInfo.spinDir = GetRandomSpinDir()
		local unitSpeed = unitInfo.vehicleConfig.moveSpeed or GameConfig.UnitSpeed
		local tvx, tvz = VehicleLocomotionTool.AngleToVelocityXZ(unitInfo.moveAngle, unitSpeed)
		unitInfo.targetVelX = tvx
		unitInfo.targetVelZ = tvz
		unitInfo.spinAngleRad = math.atan2(tvz, tvx)
		unitInfo.unitModel:PivotTo(CFrame.new(unitInfo.rootPart.Position) * VehicleLocomotionTool.UprightGoalCFrame(unitInfo.spinAngleRad))
		local maxHits = if unitInfo.vehicleConfig then unitInfo.vehicleConfig.maxHits else GameConfig.MaxHits
		NetMsg.FireNotifyUnitInitToAll({
			playerId = playerId,
			moveAngle = unitInfo.moveAngle,
			spinDir = unitInfo.spinDir,
			spawnPosition = unitInfo.rootPart.Position,
			maxHits = maxHits,
			isParticipant = true, -- StartRound implies all passed IDs are participants
			vehicleId = getVehicleIdFromUnitInfo(unitInfo),
		})
		NetMsg.FireNotifyHpChanged(playerId, 0, maxHits)
		LogInfo(string.format("StartRoundReset userId=%d moveAngle=%d spinDir=%d", playerId, unitInfo.moveAngle, unitInfo.spinDir))
	end
	LogInfo("StartRound end")
end

function CombatManager.GetUnitInfoMap(): { [number]: ServerUnitInfo }
	return unitInfoMap
end

function CombatManager.SetVehicleAnchoredForPlayer(playerId: number, anchored: boolean)
	local unitInfo = unitInfoMap[playerId]
	if unitInfo == nil then
		return
	end
	local root = unitInfo.rootPart
	if root.Parent == nil then
		return
	end
	root.Anchored = anchored
	if anchored then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		unitInfo.driveVectorForce = nil
	end
end

function CombatManager.SetAllVehiclesAnchored(anchored: boolean)
	for playerId in unitInfoMap do
		CombatManager.SetVehicleAnchoredForPlayer(playerId, anchored)
	end
end

function CombatManager.UnseatPlayerFromOwnedVehicle(player: Player)
	unseatPlayerFromOwnedVehicle(player)
end


return CombatManager
