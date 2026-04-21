--!strict
local BulletClientManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local workspaceService = game:GetService("Workspace")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

type ClientUnitState = {
	playerId: number,
	targetVelX: number,
	targetVelZ: number,
	spinDir: number,
	unitPart: BasePart,
	turretPart: BasePart?,
	model: Model?,
	isLocal: boolean,
	maxHits: number,
	hitCount: number,
	spinDampingUntil: number,
	driveVectorForce: VectorForce?,
	hasPassiveTurretConstraint: boolean,
	spinAngleRad: number,
	aimRelSmoothedRad: number,
	spinImpulseRadPerSec: number,
	spinOffsetRad: number,
	lastWallBounceClock: number,
	lastVehicleBumpClock: number?,
}

local VEHICLE_MODEL_NAME_PREFIX = "Vehicle_"
local SERVER_BULLETS_FOLDER_NAME = "ServerBullets"
local SERVER_PROJECTILE_NAME_PREFIX = "ServerProjectile_"
local SHOOTER_USER_ID_ATTRIBUTE = "ShooterUserId"
local LOCAL_OWNED_PROJECTILE_COLOR = Color3.new(0, 1, 0)
-- local UNIT_SPEED: number = GameConfig.UnitSpeed
-- local UNIT_MAX_HORIZONTAL_SPEED: number = GameConfig.UnitMaxHorizontalSpeed
-- local FIRE_COOLDOWN: number = GameConfig.FireCooldown
-- local SPIN_DAMPING_DURATION: number = GameConfig.SpinDampingDuration
-- local DRIVE_HORIZONTAL_FORCE_GAIN: number = 14
-- local WALL_BOUNCE_COOLDOWN_SEC: number = 0.22
-- local WALL_BOUNCE_VEL_INTO_WALL: number = -0.35
-- local WALL_STUCK_SPEED_MAX: number = 10
-- local WALL_STUCK_DESIRED_DOT: number = -0.02

local matchState: GameConfig.MatchState = "InLobby"

local localPlayerId: number = 0
local unitStateMap: { [number]: ClientUnitState } = {}
local unitInitRetryCountMap: { [number]: number } = {}
local lastFireTime: number = -math.huge
local isInitialized: boolean = false
local _hasWarnedMissingTurretActuator: boolean = false

local HttpService = game:GetService("HttpService")

local function GetModelsFolder(): Folder
	return replicatedStorage:WaitForChild("Models") :: Folder
end

local cachedProjectileRadius: number? = nil
local function GetProjectileRadius(): number
	if cachedProjectileRadius ~= nil then
		return cachedProjectileRadius
	end
	local defaultRadius = 1.5
	local modelsFolder = GetModelsFolder()
	local projectileTemplate = modelsFolder:FindFirstChild("ProjectileModel")
	if projectileTemplate ~= nil and projectileTemplate:IsA("Model") then
		local core = projectileTemplate:FindFirstChild("Core")
		if core ~= nil and core:IsA("BasePart") then
			local radius = core.Size.X / 2
			if radius >= 0.5 then
				defaultRadius = radius
			end
		end
	end
	cachedProjectileRadius = defaultRadius
	return defaultRadius
end

local function IsServerProjectileModelName(modelName: string): boolean
	return string.sub(modelName, 1, #SERVER_PROJECTILE_NAME_PREFIX) == SERVER_PROJECTILE_NAME_PREFIX
end

local function TintServerProjectileForLocalPlayerIfOwner(projectileModel: Model)
	if not IsServerProjectileModelName(projectileModel.Name) then
		return
	end
	local function tryTint()
		local shooterId = projectileModel:GetAttribute(SHOOTER_USER_ID_ATTRIBUTE)
		if typeof(shooterId) ~= "number" then
			return
		end
		if shooterId ~= localPlayerId then
			return
		end
		for _, d in projectileModel:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = LOCAL_OWNED_PROJECTILE_COLOR
			end
		end
	end
	tryTint()
	projectileModel:GetAttributeChangedSignal(SHOOTER_USER_ID_ATTRIBUTE):Connect(tryTint)
end

local function BindServerProjectileLocalTintFolder(folder: Folder)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			TintServerProjectileForLocalPlayerIfOwner(child)
		end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			TintServerProjectileForLocalPlayerIfOwner(child)
		end
	end)
end

local function IsFightingDriveActive(): boolean
	return matchState == "Fighting"
end

local function Deg2Rad(deg: number): number
	return deg * math.pi / 180
end

local function AngleToVelocityXZ(angleDeg: number): (number, number)
	local rad = Deg2Rad(angleDeg)
	return math.cos(rad) * GameConfig.UnitSpeed, math.sin(rad) * GameConfig.UnitSpeed
end

local function FindUnitPart(playerId: number): BasePart?
	local modelName = VEHICLE_MODEL_NAME_PREFIX .. tostring(playerId)

	local vehicleModel = workspaceService:WaitForChild(modelName, 3)
	if vehicleModel ~= nil and vehicleModel:IsA("Model") then
		local baseDisk = vehicleModel:WaitForChild("BaseDisk", 2)
		if baseDisk ~= nil and baseDisk:IsA("BasePart") then
			return baseDisk :: BasePart
		end
	end

	return nil
end

local function UpdateInvincibilityEffect(model: Model, isInvincible: boolean)
	local existing = model:FindFirstChild("InvincibilityHighlight")
	local highlight: Highlight? = if existing ~= nil and existing:IsA("Highlight") then existing else nil
	if isInvincible then
		if highlight == nil then
			local newHighlight = Instance.new("Highlight")
			newHighlight.Name = "InvincibilityHighlight"
			newHighlight.FillColor = Color3.fromRGB(255, 255, 0)
			newHighlight.OutlineColor = Color3.fromRGB(255, 255, 0)
			newHighlight.FillTransparency = 0.5
			newHighlight.Parent = model
			highlight = newHighlight
		end
		local activeHighlight = highlight :: Highlight
		activeHighlight.Enabled = true
	else
		if highlight ~= nil then
			highlight.Enabled = false
		end
	end
end

function BulletClientManager.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	localPlayerId = players.LocalPlayer.UserId

	task.defer(function()
		local folder = workspaceService:WaitForChild(SERVER_BULLETS_FOLDER_NAME, 60)
		if folder ~= nil and folder:IsA("Folder") then
			BindServerProjectileLocalTintFolder(folder)
		end
	end)

	NetMsg.ConnectNotifyUnitInit(BulletClientManager.OnUnitInit)
	NetMsg.ConnectNotifyDirectionFlip(BulletClientManager.OnDirectionFlip)
	NetMsg.ConnectNotifyUnitRemove(BulletClientManager.OnUnitRemove)
	NetMsg.ConnectNotifyFireAccepted(BulletClientManager.OnFireAccepted)
	NetMsg.ConnectNotifyHit(BulletClientManager.OnHit)
	NetMsg.ConnectNotifyHpChanged(BulletClientManager.OnHpChanged)
	NetMsg.ConnectNotifyDead(BulletClientManager.OnDead)
	NetMsg.ConnectNotifyTeleport(BulletClientManager.OnTeleport)
	NetMsg.ConnectNotifyMatchState(BulletClientManager.OnMatchStateChanged)
end

function BulletClientManager.OnUnitInit(unitInitInfo: GameConfig.UnitInitInfo)
	local playerId: number = unitInitInfo.playerId
	local isLocal: boolean = (playerId == localPlayerId)

	local unitPart: BasePart? = FindUnitPart(playerId)
	if unitPart == nil then
		local retryCount = (unitInitRetryCountMap[playerId] or 0) + 1
		unitInitRetryCountMap[playerId] = retryCount
		if retryCount <= 5 then
			task.delay(0.2, function()
				BulletClientManager.OnUnitInit(unitInitInfo)
			end)
			return
		end
		warn("[BulletClientManager] Failed to find unit part for playerId: " .. tostring(playerId))
		return
	end
	unitInitRetryCountMap[playerId] = nil

	local model = unitPart.Parent
	local unitModel: Model? = nil
	if model ~= nil and model:IsA("Model") then
		unitModel = model
	end
	local turretPart: BasePart? = nil
	if unitModel ~= nil then
		local turret = unitModel:FindFirstChild("TurretBarrel")
		if turret ~= nil and turret:IsA("BasePart") then
			turretPart = turret
		end
	end

	local targetVelX: number, targetVelZ: number = AngleToVelocityXZ(unitInitInfo.moveAngle)
	local initHullYaw = math.atan2(targetVelZ, targetVelX)

	local state: ClientUnitState = {
		playerId = playerId,
		targetVelX = targetVelX,
		targetVelZ = targetVelZ,
		spinDir = unitInitInfo.spinDir,
		unitPart = unitPart,
		turretPart = turretPart,
		model = unitModel,
		isLocal = isLocal,
		maxHits = unitInitInfo.maxHits,
		hitCount = 0,
		spinDampingUntil = 0,
		driveVectorForce = nil,
		hasPassiveTurretConstraint = false,
		spinAngleRad = initHullYaw,
		aimRelSmoothedRad = 0,
		spinImpulseRadPerSec = 0,
		spinOffsetRad = 0,
		lastWallBounceClock = 0,
		lastVehicleBumpClock = 0,
	}
	unitStateMap[playerId] = state

	if unitModel ~= nil then
		UpdateInvincibilityEffect(unitModel, unitModel:GetAttribute("IsInvincible") == true)
		unitModel:GetAttributeChangedSignal("IsInvincible"):Connect(function()
			UpdateInvincibilityEffect(unitModel, unitModel:GetAttribute("IsInvincible") == true)
		end)
	end
end

function BulletClientManager.OnDirectionFlip(playerId: number)
	local state: ClientUnitState? = unitStateMap[playerId]
	if state == nil then
		return
	end
	state.spinDir = -state.spinDir
end

function BulletClientManager.OnUnitRemove(playerId: number)
	unitStateMap[playerId] = nil
end
function BulletClientManager.OnFireAccepted(playerId: number, _fireTime: number, _spawnPos: Vector3, _shotDir: Vector3, _serverTime: number, _bulletId: string)
	if playerId == localPlayerId then
		return
	end

	local state = unitStateMap[playerId]
	if state ~= nil then
		state.spinDir = -state.spinDir
		state.spinDampingUntil = os.clock() + GameConfig.SpinDampingDuration
		state.spinImpulseRadPerSec += GameConfig.TurretSpinImpulseOnFireRadPerSec * state.spinDir
	end
end

function BulletClientManager.OnHit(targetPlayerId: number, _fromPlayerId: number, _hitDirection: Vector3, _hitCount: number, _bulletId: string, hitPosition: Vector3)
	local targetState = unitStateMap[targetPlayerId]
	if targetState == nil then
		return
	end
	targetState.spinDir = (math.random(0, 1) == 0) and 1 or -1
	local sign = (math.random(0, 1) == 0) and 1 or -1
	targetState.spinImpulseRadPerSec += GameConfig.TurretSpinImpulseOnHitRadPerSec * sign

	local finalExplosionPos = hitPosition
	if targetPlayerId == localPlayerId then
		finalExplosionPos = targetState.unitPart.Position
	end

	local explosion = Instance.new("Explosion")
	explosion.Position = finalExplosionPos
	explosion.BlastRadius = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Visible = true
	explosion.Parent = workspaceService
end

function BulletClientManager.OnHpChanged(playerId: number, hitCount: number, maxHits: number)
	local state = unitStateMap[playerId]
	if state == nil then
		return
	end
	state.hitCount = hitCount
	state.maxHits = maxHits
end

function BulletClientManager.OnDead(playerId: number)
	local state = unitStateMap[playerId]
	if state == nil then
		return
	end
	state.targetVelX = 0
	state.targetVelZ = 0
end

function BulletClientManager.OnTeleport(_playerId: number, _targetPosition: Vector3)
end

function BulletClientManager.OnMatchStateChanged(newState: GameConfig.MatchState, _countdown: number)
	matchState = newState
end

function BulletClientManager.FireShot()
	if not IsFightingDriveActive() then
		return
	end
	local now: number = tick()
	if now - lastFireTime < GameConfig.FireCooldown then
		return
	end
	lastFireTime = now

	local spawnPos = Vector3.zero
	local shotDir = Vector3.new(0, 0, -1)

	local localState: ClientUnitState? = unitStateMap[localPlayerId]
	if localState ~= nil then
		-- spinDir 由服务端 NotifyDirectionFlip 统一翻转，避免与 FireShot 本地预测双翻
		localState.spinDampingUntil = os.clock() + GameConfig.SpinDampingDuration

		local unitPart = localState.unitPart
		local muzzleAttachment: Attachment? = nil
		if localState.model ~= nil then
			local barrel = localState.model:FindFirstChild("TurretBarrel", true)
			if barrel ~= nil and barrel:IsA("BasePart") then
				muzzleAttachment = barrel:FindFirstChild("MuzzleAttachment") :: Attachment
			end
		end

		if muzzleAttachment ~= nil then
			spawnPos = muzzleAttachment.WorldCFrame.Position
			local flat = Vector3.new(muzzleAttachment.WorldCFrame.LookVector.X, 0, muzzleAttachment.WorldCFrame.LookVector.Z)
			if flat.Magnitude > 0.001 then
				shotDir = flat.Unit
			end
		else
			local fallbackCFrame = unitPart.CFrame * CFrame.new(0, 1.2, -3.4)
			spawnPos = fallbackCFrame.Position
			local flat = Vector3.new(unitPart.CFrame.LookVector.X, 0, unitPart.CFrame.LookVector.Z)
			if flat.Magnitude > 0.001 then
				shotDir = flat.Unit
			end
		end

		local rayOrigin = unitPart.Position + Vector3.new(0, 1.2, 0)
		local toSpawn = spawnPos - rayOrigin
		if toSpawn.Magnitude > 0.01 then
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			local excludeList: { Instance } = {}
			if localState.model ~= nil then
				table.insert(excludeList, localState.model)
			end
			local character = players.LocalPlayer.Character
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
				local res = workspaceService:Raycast(curOrigin, dir * remaining, rayParams)
				if res == nil then
					break
				end

				if res.Instance.Name == "ArenaFloor" then
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
				local projRadius = GetProjectileRadius()
				local safeDist = math.max(0, (hitPoint - rayOrigin).Magnitude - (projRadius * 2 + 0.1))
				spawnPos = rayOrigin + (dir * safeDist)
			end
		end
	end
	if localState ~= nil then
		localState.spinImpulseRadPerSec += GameConfig.TurretSpinImpulseOnFireRadPerSec * localState.spinDir
	end

	local bulletId = HttpService:GenerateGUID(false)
	NetMsg.FireRequestFire(spawnPos, shotDir, workspaceService:GetServerTimeNow(), bulletId)
end

function BulletClientManager.GetLocalHpInfo(): (number, number)
	local localState = unitStateMap[localPlayerId]
	if localState == nil then
		return 0, GameConfig.MaxHits
	end
	return localState.hitCount, localState.maxHits
end

function BulletClientManager.GetLocalFireCooldownLeft(): number
	local cooldownLeft = GameConfig.FireCooldown - (tick() - lastFireTime)
	if cooldownLeft < 0 then
		return 0
	end
	return cooldownLeft
end

function BulletClientManager.GetMatchState(): GameConfig.MatchState
	return matchState
end

return BulletClientManager
