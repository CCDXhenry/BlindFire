--!strict
local BulletClientManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
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
local UNIT_SPEED: number = GameConfig.UnitSpeed
local UNIT_MAX_HORIZONTAL_SPEED: number = GameConfig.UnitMaxHorizontalSpeed
local FIRE_COOLDOWN: number = GameConfig.FireCooldown
local SPIN_DAMPING_DURATION: number = GameConfig.SpinDampingDuration
local DRIVE_HORIZONTAL_FORCE_GAIN: number = 14
local WALL_BOUNCE_COOLDOWN_SEC: number = 0.22
-- 放宽阈值：低速贴墙时仍能触发反弹并翻转 targetVel
local WALL_BOUNCE_VEL_INTO_WALL: number = -0.35
local WALL_STUCK_SPEED_MAX: number = 10
local WALL_STUCK_DESIRED_DOT: number = -0.02

local BASE_DISK_MESH_OFFSET = CFrame.Angles(0, 0, 0)

local matchState: GameConfig.MatchState = "InLobby"

local localPlayerId: number = 0
local unitStateMap: {[number]: ClientUnitState} = {}
local unitInitRetryCountMap: {[number]: number} = {}
local lastFireTime: number = -math.huge
local _heartbeatConnection: RBXScriptConnection? = nil
local isInitialized: boolean = false
local hasWarnedMissingTurretActuator: boolean = false

local function GetModelsFolder(): Folder
	return replicatedStorage:WaitForChild("Models") :: Folder
end

local function GetPlayerIdByVehicleModelName(modelName: string): number?
	if not modelName:match("^" .. VEHICLE_MODEL_NAME_PREFIX) then
		return nil
	end
	local userIdText = string.gsub(modelName, VEHICLE_MODEL_NAME_PREFIX, "")
	return tonumber(userIdText)
end

local function SpawnLocalVisualProjectile(spawnPos: Vector3, shotDir: Vector3, ownerId: number)
	local modelsFolder = GetModelsFolder()
	local projectileTemplate = modelsFolder:FindFirstChild("ProjectileModel")
	if projectileTemplate == nil or not projectileTemplate:IsA("Model") then
		return
	end
	
	local projectileModel = projectileTemplate:Clone()
	projectileModel.Name = "LocalProjectile"
	projectileModel.Parent = workspaceService
	
	local projectileRoot = projectileModel:FindFirstChild("Core")
	if projectileRoot == nil or not projectileRoot:IsA("BasePart") then
		projectileModel:Destroy()
		return
	end
	
	projectileModel.PrimaryPart = projectileRoot
	projectileRoot.CanCollide = false
	for _, d in projectileModel:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	
	local spawnCFrame = CFrame.lookAt(spawnPos, spawnPos + shotDir)
	projectileModel:PivotTo(spawnCFrame)
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList: {Instance} = {projectileModel}
	local character = players.LocalPlayer.Character
	if character ~= nil then
		table.insert(excludeList, character)
	end
	local localState = unitStateMap[localPlayerId]
	if localState ~= nil and localState.model ~= nil then
		table.insert(excludeList, localState.model)
	end
	rayParams.FilterDescendantsInstances = excludeList
	
	local spawnTime = os.clock()
	local hbConn: RBXScriptConnection?
	hbConn = runService.Heartbeat:Connect(function(dt)
		if projectileModel.Parent == nil then
			if hbConn ~= nil then hbConn:Disconnect() end
			return
		end
		dt = math.min(dt, 0.05)
		if os.clock() - spawnTime > GameConfig.ProjectileLifetime then
			projectileModel:Destroy()
			if hbConn ~= nil then hbConn:Disconnect() end
			return
		end
		
		local stepDist = GameConfig.ProjectileSpeed * dt
		local pivot = projectileModel:GetPivot()
		local origin = pivot.Position
		local remaining = stepDist + 0.45
		local hitResult: RaycastResult? = nil
		
		local radius = projectileRoot.Size.X / 2
		if radius < 0.5 then radius = 1.5 end
		
		for _ = 1, 10 do
			if remaining < 1e-4 then break end
			local res = workspaceService:Spherecast(origin, radius, shotDir * remaining, rayParams)
			if res == nil then break end
			local inst = res.Instance
			local shouldPass = false
			if inst:IsA("BasePart") then
				if inst.Name == "ArenaFloor" then
					shouldPass = true
				else
					local tm = inst:FindFirstAncestorOfClass("Model")
					if tm ~= nil then
						if tm.Name == "LocalProjectile" then
							shouldPass = true
						elseif GetPlayerIdByVehicleModelName(tm.Name) ~= nil then
							if inst.Name ~= "HitRange" then
								shouldPass = true
							end
						elseif players:GetPlayerFromCharacter(tm) ~= nil then
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
			if ownerId == localPlayerId then
				if inst:IsA("BasePart") then
					local tm = inst:FindFirstAncestorOfClass("Model")
					local targetId: number? = nil
					if tm ~= nil then
						targetId = GetPlayerIdByVehicleModelName(tm.Name)
					end
					if targetId ~= nil and targetId ~= localPlayerId then
						NetMsg.FireRequestHit(targetId, shotDir)
					end
				end
			end
			projectileModel:Destroy()
			if hbConn ~= nil then hbConn:Disconnect() end
			return
		end
		
		local newPos = pivot.Position + shotDir * stepDist
		projectileModel:PivotTo(CFrame.lookAt(newPos, newPos + shotDir))
	end)
end

local function UprightGoalCFrame(hullYawRad: number): CFrame
	return CFrame.Angles(0, hullYawRad, 0) * BASE_DISK_MESH_OFFSET
end

local function IsFightingDriveActive(): boolean
	return matchState == "Fighting"
end

local function IsGameStartObservePhase(): boolean
	return matchState == "GameStartCountdown"
end

local function Deg2Rad(deg: number): number
	return deg * math.pi / 180
end

local function AngleWrapRad(r: number): number
	local x = r
	while x > math.pi do
		x -= math.pi * 2
	end
	while x < -math.pi do
		x += math.pi * 2
	end
	return x
end

local function AngleToVelocityXZ(angleDeg: number): (number, number)
	local rad = Deg2Rad(angleDeg)
	return math.cos(rad) * UNIT_SPEED, math.sin(rad) * UNIT_SPEED
end

local function FindUnitPart(playerId: number): BasePart?
	local modelName = VEHICLE_MODEL_NAME_PREFIX .. tostring(playerId)

	local timeout = 5
	local start = os.clock()
	while os.clock() - start < timeout do
		local vehicleModel = workspaceService:FindFirstChild(modelName)
		if vehicleModel ~= nil and vehicleModel:IsA("Model") then
			local baseDisk = vehicleModel:FindFirstChild("BaseDisk", true)
			if baseDisk ~= nil and baseDisk:IsA("BasePart") then
				return baseDisk :: BasePart
			end
		end
		task.wait(0.1)
	end

	return nil
end

local function EnsureVehicleDriveConstraints(baseDisk: BasePart): VectorForce
	local att = baseDisk:FindFirstChild("DriveAttachment")
	if att == nil or not att:IsA("Attachment") then
		if att ~= nil then
			(att :: Instance):Destroy()
		end
		local newAtt = Instance.new("Attachment")
		newAtt.Name = "DriveAttachment"
		newAtt.Parent = baseDisk
		newAtt.CFrame = CFrame.new()
		att = newAtt
	end

	local vf = baseDisk:FindFirstChild("DriveVectorForce")
	if vf == nil or not vf:IsA("VectorForce") then
		if vf ~= nil then
			(vf :: Instance):Destroy()
		end
		local newVf = Instance.new("VectorForce")
		newVf.Name = "DriveVectorForce"
		newVf.Parent = baseDisk
		vf = newVf
	end
	local vectorForce = vf :: VectorForce
	local driveAtt = att :: Attachment
	vectorForce.Attachment0 = driveAtt
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.Force = Vector3.zero

	local ao = baseDisk:FindFirstChild("UprightAlignOrientation")
	if ao ~= nil then
		ao:Destroy()
	end

	local existingProps = baseDisk.CustomPhysicalProperties
	if existingProps ~= nil then
		local bounceElasticity = math.clamp(GameConfig.WallBounceElasticity, 0, 1)
		baseDisk.CustomPhysicalProperties = PhysicalProperties.new(
			existingProps.Density,
			existingProps.Friction,
			bounceElasticity,
			existingProps.FrictionWeight,
			existingProps.ElasticityWeight
		)
	end

	return vectorForce
end

local function ZeroHorizontalVelocity(part: BasePart)
	local v = part.AssemblyLinearVelocity
	part.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
end

local function OnLocalVehicleTouched(hitPart: BasePart)
	if not hitPart:IsA("BasePart") then return end
	local otherModel = hitPart:FindFirstAncestorOfClass("Model")
	if otherModel == nil then return end
	local otherPlayerId = GetPlayerIdByVehicleModelName(otherModel.Name)
	if otherPlayerId == nil or otherPlayerId == localPlayerId then return end
	
	local selfState = unitStateMap[localPlayerId]
	local otherState = unitStateMap[otherPlayerId]
	if selfState == nil or otherState == nil then return end
	
	local now = os.clock()
	if now - (selfState.lastVehicleBumpClock or 0) < 0.2 then return end
	
	local delta = selfState.unitPart.Position - otherState.unitPart.Position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 0.05 then return end
	
	selfState.lastVehicleBumpClock = now
	local bumpDir = flat.Unit
	local newSpeed = UNIT_SPEED * 1.2
	selfState.unitPart.AssemblyLinearVelocity = bumpDir * newSpeed
	
	local currentTarget = Vector3.new(selfState.targetVelX, 0, selfState.targetVelZ)
	if currentTarget.Magnitude > 0.01 then
		local du = currentTarget.Unit
		local reflected = du - 2 * bumpDir:Dot(du) * bumpDir
		local rFlat = Vector3.new(reflected.X, 0, reflected.Z)
		if rFlat.Magnitude > 0.01 then
			local r = rFlat.Unit * UNIT_SPEED
			selfState.targetVelX = r.X
			selfState.targetVelZ = r.Z
		end
	end
end

-- BaseDisk 水平移动朝向（速度 / 目标速度），不混入瞄准角
local function BaseDiskDriveYawRadFromState(state: ClientUnitState): number
	local root = state.unitPart
	local vel = root.AssemblyLinearVelocity
	local xz = Vector3.new(vel.X, 0, vel.Z)
	if xz.Magnitude >= GameConfig.HullYawVelocityEpsilonStudsPerSec then
		return math.atan2(-xz.X, -xz.Z)
	end
	return math.atan2(state.targetVelZ, state.targetVelX)
end

-- 移除了原有的 UpdateSeatTurretAimAssembly 因为目前Seat采用WeldConstraint跟底盘固定，一起随底盘自转

local function IsAlignPositionPassiveTurretConstraint(baseDisk: BasePart, turretPart: BasePart?): boolean
	if turretPart == nil then
		return false
	end
	local alignPos = baseDisk:FindFirstChild("AlignPosition")
	if alignPos == nil or not alignPos:IsA("AlignPosition") then
		return false
	end
	local a0 = alignPos.Attachment0
	local a1 = alignPos.Attachment1
	if a0 == nil or a1 == nil then
		return false
	end
	local a0Parent = a0.Parent
	local a1Parent = a1.Parent
	if a0Parent == turretPart and a1Parent == baseDisk then
		return true
	end
	if a1Parent == turretPart and a0Parent == baseDisk then
		return true
	end
	return false
end

local function IsLikelyArenaWallPart(part: BasePart): boolean
	if part.Name == "ArenaWall" then
		return true
	end
	local arenaFolder = workspaceService:FindFirstChild("Arena")
	if arenaFolder ~= nil and part:IsDescendantOf(arenaFolder) then
		local lower = string.lower(part.Name)
		if string.find(lower, "wall", 1, true) ~= nil then
			return true
		end
	end
	return false
end

-- 与 BulletManager 轴对齐墙一致：内侧面约在 x=±ArenaHalfSize、z=±ArenaHalfSize；仅当 BaseDisk 中心距该面很近时返回法线（避免远处误触发）
local function ComputeInwardNormalFromInnerWallProximity(pos: Vector3): Vector3?
	local half = GameConfig.ArenaHalfSize
	local tol = GameConfig.ArenaWallProximityStuds
	local n = Vector3.zero
	local dEast = half - pos.X
	if dEast > 0 and dEast < tol then
		n += Vector3.new(-1, 0, 0)
	end
	local dWest = pos.X + half
	if dWest > 0 and dWest < tol then
		n += Vector3.new(1, 0, 0)
	end
	local dNorth = half - pos.Z
	if dNorth > 0 and dNorth < tol then
		n += Vector3.new(0, 0, -1)
	end
	local dSouth = pos.Z + half
	if dSouth > 0 and dSouth < tol then
		n += Vector3.new(0, 0, 1)
	end
	if n.Magnitude < 0.01 then
		return nil
	end
	return n.Unit
end

-- 从 BaseDisk 指向场地内侧的水平单位法线：优先物理接触；否则用距内墙近距离（不依赖墙 Part 命名）
local function ComputeAggregatedWallInwardNormal(root: BasePart): Vector3?
	local sum = Vector3.zero
	local count = 0
	for _, part in root:GetTouchingParts() do
		if part:IsA("BasePart") and IsLikelyArenaWallPart(part) then
			local flat = Vector3.new(root.Position.X - part.Position.X, 0, root.Position.Z - part.Position.Z)
			if flat.Magnitude > 0.05 then
				sum += flat.Unit
				count += 1
			end
		end
	end
	if count > 0 then
		local agg = Vector3.new(sum.X, 0, sum.Z)
		if agg.Magnitude > 0.05 then
			return agg.Unit
		end
	end
	return ComputeInwardNormalFromInnerWallProximity(root.Position)
end

-- BaseDisk：水平驱动力 + 仅速度 yaw 的直立对齐（与瞄准解耦）
local function UpdateBaseDiskLocomotion(state: ClientUnitState, _dt: number, applyHorizontalDrive: boolean)
	local drive = state.driveVectorForce
	if drive == nil then
		return
	end

	local root = state.unitPart
	root.CFrame = CFrame.new(root.Position) * UprightGoalCFrame(state.spinAngleRad)

	if not applyHorizontalDrive then
		drive.Force = Vector3.zero
		return
	end

	local root = state.unitPart
	local mass = root.AssemblyMass
	local vel = root.AssemblyLinearVelocity
	local curXZ = Vector3.new(vel.X, 0, vel.Z)

	local targetDir = Vector3.new(state.targetVelX, 0, state.targetVelZ)
	if targetDir.Magnitude < 1e-4 then
		drive.Force = Vector3.zero
	else
		local desired = targetDir.Unit * UNIT_SPEED
		local err = desired - curXZ
		drive.Force = Vector3.new(err.X, 0, err.Z) * (DRIVE_HORIZONTAL_FORCE_GAIN * mass)
	end

	local speed = curXZ.Magnitude
	if speed > UNIT_MAX_HORIZONTAL_SPEED then
		local damp = (speed - UNIT_MAX_HORIZONTAL_SPEED) * mass * 2
		drive.Force -= curXZ.Unit * damp
	end

	local inward = ComputeAggregatedWallInwardNormal(root)
	if inward ~= nil then
		local f = drive.Force
		local fH = Vector3.new(f.X, 0, f.Z)
		local intoWallForce = fH:Dot(inward)
		if intoWallForce < 0 then
			local fAdj = fH - inward * intoWallForce
			drive.Force = Vector3.new(fAdj.X, 0, fAdj.Z)
		end

		local now = os.clock()
		if now - state.lastWallBounceClock >= WALL_BOUNCE_COOLDOWN_SEC then
			local velInto = curXZ:Dot(inward)
			local desiredDot = 0
			if targetDir.Magnitude >= 1e-4 then
				desiredDot = targetDir.Unit:Dot(inward)
			end
			local shouldBounce = (velInto < WALL_BOUNCE_VEL_INTO_WALL)
				or (curXZ.Magnitude < WALL_STUCK_SPEED_MAX and desiredDot < WALL_STUCK_DESIRED_DOT)
			if shouldBounce then
				state.lastWallBounceClock = now
				local newSpeed = UNIT_SPEED * 1.2
				root.AssemblyLinearVelocity = inward * newSpeed
				if targetDir.Magnitude >= 1e-4 then
					local du = targetDir.Unit
					local reflected = du - 2 * inward:Dot(du) * inward
					local rFlat = Vector3.new(reflected.X, 0, reflected.Z)
					if rFlat.Magnitude > 1e-4 then
						local r = rFlat.Unit * UNIT_SPEED
						state.targetVelX = r.X
						state.targetVelZ = r.Z
					end
				end
			end
		end
	end
end

local function UpdateLocalDrive(state: ClientUnitState, dt: number)
	state.spinAngleRad = state.spinAngleRad + math.rad(GameConfig.UnitRotationSpeed) * dt * state.spinDir
	local drive = state.driveVectorForce
	if drive == nil then
		return
	end

	UpdateBaseDiskLocomotion(state, dt, true)
end

function BulletClientManager.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	localPlayerId = players.LocalPlayer.UserId

	local function OnHeartbeat(dt: number)
		local localState: ClientUnitState? = unitStateMap[localPlayerId]
		if localState == nil or not localState.isLocal then
			return
		end
		if IsGameStartObservePhase() then
			if localState.driveVectorForce ~= nil then
				localState.driveVectorForce.Force = Vector3.zero
			end
			ZeroHorizontalVelocity(localState.unitPart)
			localState.unitPart.AssemblyAngularVelocity = Vector3.zero
			localState.spinAngleRad = BaseDiskDriveYawRadFromState(localState)
			UpdateBaseDiskLocomotion(localState, dt, false)
			return
		end
		if localState.driveVectorForce ~= nil and not IsFightingDriveActive() then
			localState.driveVectorForce.Force = Vector3.zero
			return
		end
		if IsFightingDriveActive() then
			UpdateLocalDrive(localState, dt)
		end
	end
	_heartbeatConnection = runService.Heartbeat:Connect(OnHeartbeat)

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
		if retryCount <= 20 then
			task.delay(0.5, function()
				BulletClientManager.OnUnitInit(unitInitInfo)
			end)
			return
		end
		warn("[BulletClientManager] 找不到玩家单位 Part: " .. tostring(playerId))
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

	local driveVectorForce: VectorForce? = nil
	if isLocal then
		local vf = EnsureVehicleDriveConstraints(unitPart)
		driveVectorForce = vf
		
		unitPart.Touched:Connect(function(hitPart)
			OnLocalVehicleTouched(hitPart)
		end)
	end

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
		driveVectorForce = driveVectorForce,
		hasPassiveTurretConstraint = IsAlignPositionPassiveTurretConstraint(unitPart, turretPart),
		spinAngleRad = initHullYaw,
		aimRelSmoothedRad = 0,
		spinImpulseRadPerSec = 0,
		spinOffsetRad = 0,
		lastWallBounceClock = 0,
	}
	unitStateMap[playerId] = state
end

function BulletClientManager.OnDirectionFlip(playerId: number)
	local state: ClientUnitState? = unitStateMap[playerId]
	if state == nil then
		return
	end
	state.spinDir = -state.spinDir
end

function BulletClientManager.OnUnitRemove(playerId: number)
	local state = unitStateMap[playerId]
	if state ~= nil and state.driveVectorForce ~= nil then
		state.driveVectorForce.Force = Vector3.zero
	end
	unitStateMap[playerId] = nil
end

function BulletClientManager.OnFireAccepted(playerId: number, _fireTime: number, spawnPos: Vector3, shotDir: Vector3, serverTime: number)
	local state = unitStateMap[playerId]
	if state == nil then
		return
	end
	state.spinDampingUntil = os.clock() + SPIN_DAMPING_DURATION
	-- 开火水平推力仅由服务端沿射击反向的 Recoil 冲量提供，此处不改 targetVel
	if playerId == localPlayerId then
		state.spinImpulseRadPerSec += GameConfig.TurretSpinImpulseOnFireRadPerSec * state.spinDir
	else
		local latency = workspaceService:GetServerTimeNow() - serverTime
		local adjustedSpawnPos = spawnPos + (shotDir * GameConfig.ProjectileSpeed * latency)
		SpawnLocalVisualProjectile(adjustedSpawnPos, shotDir, playerId)
	end
end

function BulletClientManager.OnHit(targetPlayerId: number, _fromPlayerId: number, _hitDirection: Vector3, _hitCount: number)
	local state = unitStateMap[targetPlayerId]
	if state == nil then
		return
	end
	state.spinDir = (math.random(0, 1) == 0) and 1 or -1
	local sign = (math.random(0, 1) == 0) and 1 or -1
	state.spinImpulseRadPerSec += GameConfig.TurretSpinImpulseOnHitRadPerSec * sign
	
	if targetPlayerId == localPlayerId then
		local flatDir = Vector3.new(_hitDirection.X, 0, _hitDirection.Z)
		if flatDir.Magnitude > 0.001 then
			local knockbackDir = flatDir.Unit
			state.unitPart.AssemblyLinearVelocity = knockbackDir * (UNIT_SPEED * GameConfig.BulletHitSpeedMultiplier)
			state.targetVelX = knockbackDir.X * UNIT_SPEED
			state.targetVelZ = knockbackDir.Z * UNIT_SPEED
		end
	end
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
	if state.driveVectorForce ~= nil then
		state.driveVectorForce.Force = Vector3.zero
	end
	ZeroHorizontalVelocity(state.unitPart)
end

function BulletClientManager.OnTeleport(playerId: number, _targetPosition: Vector3)
	local state = unitStateMap[playerId]
	if state == nil then
		return
	end
	if state.driveVectorForce ~= nil then
		state.driveVectorForce.Force = Vector3.zero
	end
	local root = state.unitPart
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

function BulletClientManager.OnMatchStateChanged(newState: GameConfig.MatchState, _countdown: number)
	matchState = newState
	local localState = unitStateMap[localPlayerId]
	if newState == "GameStartCountdown" then
		if localState ~= nil then
			if localState.driveVectorForce ~= nil then
				localState.driveVectorForce.Force = Vector3.zero
			end
			ZeroHorizontalVelocity(localState.unitPart)
			localState.unitPart.AssemblyAngularVelocity = Vector3.zero
			localState.spinAngleRad = BaseDiskDriveYawRadFromState(localState)
		end
	elseif newState ~= "Fighting" then
		if localState ~= nil and localState.driveVectorForce ~= nil then
			localState.driveVectorForce.Force = Vector3.zero
		end
	end
end

function BulletClientManager.FireShot()
	if not IsFightingDriveActive() then
		return
	end
	local now: number = tick()
	if now - lastFireTime < FIRE_COOLDOWN then
		return
	end
	lastFireTime = now

	local spawnPos = Vector3.zero
	local shotDir = Vector3.new(0, 0, -1)

	local localState: ClientUnitState? = unitStateMap[localPlayerId]
	if localState ~= nil then
		-- spinDir 由服务端 NotifyDirectionFlip 统一翻转，避免与 FireShot 本地预测双翻
		localState.spinDampingUntil = os.clock() + SPIN_DAMPING_DURATION
		
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
	end
	SpawnLocalVisualProjectile(spawnPos, shotDir, localPlayerId)
	
	if localState ~= nil then
		local recoilDir = -shotDir
		localState.unitPart.AssemblyLinearVelocity = recoilDir * (UNIT_SPEED * GameConfig.FireRecoilSpeedMultiplier)
		localState.targetVelX = recoilDir.X * UNIT_SPEED
		localState.targetVelZ = recoilDir.Z * UNIT_SPEED
	end

	NetMsg.FireRequestFire(spawnPos, shotDir)
end

function BulletClientManager.GetLocalHpInfo(): (number, number)
	local localState = unitStateMap[localPlayerId]
	if localState == nil then
		return 0, GameConfig.MaxHits
	end
	return localState.hitCount, localState.maxHits
end

function BulletClientManager.GetLocalFireCooldownLeft(): number
	local cooldownLeft = FIRE_COOLDOWN - (tick() - lastFireTime)
	if cooldownLeft < 0 then
		return 0
	end
	return cooldownLeft
end

function BulletClientManager.GetMatchState(): GameConfig.MatchState
	return matchState
end

return BulletClientManager
