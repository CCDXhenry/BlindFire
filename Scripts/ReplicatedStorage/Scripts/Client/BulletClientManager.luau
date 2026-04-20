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
-- local UNIT_SPEED: number = GameConfig.UnitSpeed
-- local UNIT_MAX_HORIZONTAL_SPEED: number = GameConfig.UnitMaxHorizontalSpeed
-- local FIRE_COOLDOWN: number = GameConfig.FireCooldown
-- local SPIN_DAMPING_DURATION: number = GameConfig.SpinDampingDuration
-- local DRIVE_HORIZONTAL_FORCE_GAIN: number = 14
-- local WALL_BOUNCE_COOLDOWN_SEC: number = 0.22
-- local WALL_BOUNCE_VEL_INTO_WALL: number = -0.35
-- local WALL_STUCK_SPEED_MAX: number = 10
-- local WALL_STUCK_DESIRED_DOT: number = -0.02

local BASE_DISK_MESH_OFFSET = CFrame.Angles(0, 0, 0)

local matchState: GameConfig.MatchState = "InLobby"

local localPlayerId: number = 0
local unitStateMap: { [number]: ClientUnitState } = {}
local unitInitRetryCountMap: { [number]: number } = {}
local lastFireTime: number = -math.huge
local _heartbeatConnection: RBXScriptConnection? = nil
local isInitialized: boolean = false
local hasWarnedMissingTurretActuator: boolean = false

-- 调试可视化
local wallDebugPartMap: { [BasePart]: Part } = {}
local isDebugVisualsEnabled: boolean = false -- 关闭调试层

local HttpService = game:GetService("HttpService")
local activeVisualProjectiles: { [Model]: {ownerId: number, bulletId: string} } = {}
setmetatable(activeVisualProjectiles, {__mode = "k"})

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

local function GetPlayerIdByVehicleModelName(modelName: string): number?
	if not modelName:match("^" .. VEHICLE_MODEL_NAME_PREFIX) then
		return nil
	end
	local userIdText = string.gsub(modelName, VEHICLE_MODEL_NAME_PREFIX, "")
	return tonumber(userIdText)
end

local function SpawnLocalVisualProjectile(spawnPos: Vector3, shotDir: Vector3, ownerId: number, bulletId: string)
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
	
	activeVisualProjectiles[projectileModel] = {ownerId = ownerId, bulletId = bulletId}

	projectileModel.PrimaryPart = projectileRoot
	projectileRoot.CanCollide = false
	for _, d in projectileModel:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end

	if ownerId == localPlayerId then
		for _, d in projectileModel:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = Color3.new(0, 1, 0)
			end
		end
	end

	local spawnCFrame = CFrame.lookAt(spawnPos, spawnPos + shotDir)
	projectileModel:PivotTo(spawnCFrame)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList: { Instance } = { projectileModel }
	local character = players.LocalPlayer.Character
	if character ~= nil then
		table.insert(excludeList, character)
	end
	local ownerState = unitStateMap[ownerId]
	if ownerState ~= nil and ownerState.model ~= nil then
		table.insert(excludeList, ownerState.model)
	end
	rayParams.FilterDescendantsInstances = excludeList

	local spawnTime = os.clock()
	local bouncesLeft = GameConfig.ProjectileMaxBounces or 0
	local hbConn: RBXScriptConnection?
	hbConn = runService.Heartbeat:Connect(function(dt)
		if projectileModel.Parent == nil then
			activeVisualProjectiles[projectileModel] = nil
			if hbConn ~= nil then
				hbConn:Disconnect()
			end
			return
		end
		dt = math.min(dt, 0.05)
		if os.clock() - spawnTime > GameConfig.ProjectileLifetime then
			activeVisualProjectiles[projectileModel] = nil
			projectileModel:Destroy()
			if hbConn ~= nil then
				hbConn:Disconnect()
			end
			return
		end

		local stepDist = GameConfig.ProjectileSpeed * dt
		local pivot = projectileModel:GetPivot()
		local origin = pivot.Position
		local remaining = stepDist + GameConfig.ProjectileStepMargin
		local hitResult: RaycastResult? = nil

		local radius = GetProjectileRadius()

		for _ = 1, 10 do
			if remaining < 1e-4 then
				break
			end
			local res = workspaceService:Spherecast(origin, radius, shotDir * remaining, rayParams)
			if res == nil then
				break
			end
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
						else
							local testTargetId = GetPlayerIdByVehicleModelName(tm.Name)
							if testTargetId == nil then
								local charPlayer = players:GetPlayerFromCharacter(tm)
								if charPlayer then testTargetId = charPlayer.UserId end
							end
							-- Note: Only the shooter's own client gets to instantly collide with players.
							-- For all observers (and the victim themselves), fake bullets pass straight through players
							-- to prevent fake visual hits. The server's NotifyHit will intercept these bullets and explode them.
							if testTargetId ~= nil and ownerId ~= localPlayerId then
								shouldPass = true
							end
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
			if inst:IsA("BasePart") then
				local tm = inst:FindFirstAncestorOfClass("Model")
				if tm ~= nil then
					targetId = GetPlayerIdByVehicleModelName(tm.Name)
					if targetId == nil then
						local characterPlayer = players:GetPlayerFromCharacter(tm)
						if characterPlayer ~= nil then
							targetId = characterPlayer.UserId
						end
					end
				end
			end

			if targetId ~= nil then
				local explosion = Instance.new("Explosion")
				explosion.Position = hitResult.Position
				explosion.BlastRadius = 0
				explosion.DestroyJointRadiusPercent = 0
				explosion.Visible = true
				explosion.Parent = workspaceService
				
				-- 完全服务端权威：客户端仅播放预测爆炸，不发送 RequestHit
				-- 等待服务端 NotifyHit 做最终确认并强制对齐
				
				activeVisualProjectiles[projectileModel] = nil
				projectileModel:Destroy()
				if hbConn ~= nil then
					hbConn:Disconnect()
				end
				return
			end

			if bouncesLeft > 0 then
				bouncesLeft -= 1

				if GameConfig.CanHitSelf then
					local newList: { Instance } = { projectileModel }
					local character = players.LocalPlayer.Character
					if character ~= nil then
						table.insert(newList, character)
					end
					excludeList = newList
					rayParams.FilterDescendantsInstances = excludeList
				end

				local n = hitResult.Normal
				local nFlat = Vector3.new(n.X, 0, n.Z)
				if nFlat.Magnitude > 0.01 then
					nFlat = nFlat.Unit
				else
					nFlat = -shotDir
				end

				local impactCenter = origin + shotDir * hitResult.Distance

				shotDir = shotDir - 2 * shotDir:Dot(nFlat) * nFlat
				local flatDir = Vector3.new(shotDir.X, 0, shotDir.Z)
				if flatDir.Magnitude > 0.01 then
					shotDir = flatDir.Unit
				end

				local distanceRemaining = math.max(0, stepDist - hitResult.Distance)
				local newPos = impactCenter + shotDir * distanceRemaining

				projectileModel:PivotTo(CFrame.lookAt(newPos, newPos + shotDir))
				return
			end
			
			activeVisualProjectiles[projectileModel] = nil
			projectileModel:Destroy()
			if hbConn ~= nil then
				hbConn:Disconnect()
			end
			return
		end

		-- Magnetism / Visual Homing
		local closestDist = GameConfig.BulletMagnetismRadius
		local bestTargetDir = nil
		for otherId, otherState in unitStateMap do
			if otherId == ownerId then continue end
			if otherState.unitPart ~= nil and otherState.unitPart.Parent ~= nil then
				local toTarget = otherState.unitPart.Position - origin
				local dist = toTarget.Magnitude
				if dist < closestDist then
					local dirToTarget = toTarget.Unit
					local angle = math.acos(math.clamp(shotDir:Dot(dirToTarget), -1, 1))
					if angle < GameConfig.BulletMagnetismAngleRad then
						closestDist = dist
						bestTargetDir = dirToTarget
					end
				end
			end
		end
		
		if bestTargetDir ~= nil then
			-- Lerp shotDir towards best target
			local newDir = shotDir:Lerp(bestTargetDir, 0.2).Unit
			local flatNewDir = Vector3.new(newDir.X, 0, newDir.Z)
			if flatNewDir.Magnitude > 0.01 then
				shotDir = flatNewDir.Unit
			end
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
	if not hitPart:IsA("BasePart") then
		return
	end
	local otherModel = hitPart:FindFirstAncestorOfClass("Model")
	if otherModel == nil then
		return
	end
	local otherPlayerId = GetPlayerIdByVehicleModelName(otherModel.Name)
	if otherPlayerId == nil or otherPlayerId == localPlayerId then
		return
	end

	local selfState = unitStateMap[localPlayerId]
	local otherState = unitStateMap[otherPlayerId]
	if selfState == nil or otherState == nil then
		return
	end

	local now = os.clock()
	if now - (selfState.lastVehicleBumpClock or 0) < GameConfig.VehicleBumpCooldown then
		return
	end

	local delta = selfState.unitPart.Position - otherState.unitPart.Position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 0.05 then
		return
	end

	selfState.lastVehicleBumpClock = now
	local bumpDir = flat.Unit
	local newSpeed = GameConfig.UnitSpeed * GameConfig.VehicleBumpSpeedMultiplier
	selfState.unitPart.AssemblyLinearVelocity = bumpDir * newSpeed

	local currentTarget = Vector3.new(selfState.targetVelX, 0, selfState.targetVelZ)
	if currentTarget.Magnitude > 0.01 then
		local du = currentTarget.Unit
		-- 仅在向对方移动（点积为负）时才反射目标速度，防止同向挤压时的反向“吸附”
		if bumpDir:Dot(du) < GameConfig.VehicleBumpDotThreshold then
			local reflected = du - 2 * bumpDir:Dot(du) * bumpDir
			local rFlat = Vector3.new(reflected.X, 0, reflected.Z)
			if rFlat.Magnitude > 0.01 then
				local r = rFlat.Unit * GameConfig.UnitSpeed
				selfState.targetVelX = r.X
				selfState.targetVelZ = r.Z
			end
		end
	end
end

local function UpdateInvincibilityEffect(model: Model, isInvincible: boolean)
	local highlight = model:FindFirstChild("InvincibilityHighlight")
	if isInvincible then
		if not highlight then
			highlight = Instance.new("Highlight")
			highlight.Name = "InvincibilityHighlight"
			highlight.FillColor = Color3.fromRGB(255, 255, 0)
			highlight.OutlineColor = Color3.fromRGB(255, 255, 0)
			highlight.FillTransparency = 0.5
			highlight.Parent = model
		end
		highlight.Enabled = true
	else
		if highlight then
			highlight.Enabled = false
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
	local lower = string.lower(part.Name)
	if string.find(lower, "wall", 1, true) ~= nil then
		return true
	end
	return false
end

local function GetArenaWalls(): { BasePart }
	local walls = {}
	local arena = workspaceService:FindFirstChild("Arena")
	if arena then
		for _, child in arena:GetDescendants() do
			if child:IsA("BasePart") and IsLikelyArenaWallPart(child) then
				table.insert(walls, child)
			end
		end
	end
	return walls
end

local function GetArenaCenter(): Vector3
	local arena = workspaceService:FindFirstChild("Arena")
	local floor = if arena then arena:FindFirstChild("ArenaFloor", true) else nil
	if floor and floor:IsA("BasePart") then
		return floor.Position
	end
	return Vector3.zero
end

local function UpdateWallDebugVisuals(wall: BasePart, innerFaceCFrame: CFrame, innerSize: Vector2)
	local debugPart = wallDebugPartMap[wall]
	if not isDebugVisualsEnabled then
		if debugPart then
			debugPart:Destroy()
			wallDebugPartMap[wall] = nil
		end
		return
	end

	if not debugPart then
		debugPart = Instance.new("Part")
		debugPart.Name = "WallBoundaryDebug"
		debugPart.Anchored = true
		debugPart.CanCollide = false
		debugPart.CanTouch = false
		debugPart.CanQuery = false
		debugPart.Transparency = 0.5
		debugPart.Color = Color3.fromRGB(0, 255, 0) -- 绿色显示
		debugPart.Material = Enum.Material.ForceField
		debugPart.Parent = workspace
		wallDebugPartMap[wall] = debugPart
	end

	debugPart.Size = Vector3.new(innerSize.X, 20, 0.2)
	debugPart.CFrame = innerFaceCFrame
end

local function GetArenaFloorPart(): BasePart?
	local arena = workspaceService:FindFirstChild("Arena")
	if not arena then
		return nil
	end

	local floor = arena:FindFirstChild("ArenaFloor", true)
	if floor and floor:IsA("BasePart") then
		return floor
	end

	-- Fallback to searching for anything containing "floor"
	for _, child in arena:GetDescendants() do
		if child:IsA("BasePart") and string.find(child.Name:lower(), "floor", 1, true) then
			return child
		end
	end

	return nil
end

local function GetWallInwardNormal(wall: BasePart, worldPos: Vector3): (Vector3, number, CFrame, Vector2)
	local wallCF = wall.CFrame
	local wallSize = wall.Size

	-- 优先使用服务器预定义的局部法线，解决极小圈下的识别失效问题
	local mainAxisAttr = wall:GetAttribute("LocalInwardNormal")
	local mainAxis: Vector3

	if typeof(mainAxisAttr) == "vector" or typeof(mainAxisAttr) == "Vector3" then
		mainAxis = mainAxisAttr
	else
		-- 兜底逻辑：计算墙壁指向中心的方向
		local arenaCenter = GetArenaCenter()
		local toCenterLocal = wallCF:VectorToObjectSpace((arenaCenter - wall.Position).Unit)
		if math.abs(toCenterLocal.X) > math.abs(toCenterLocal.Z) then
			mainAxis = Vector3.new(math.sign(toCenterLocal.X), 0, 0)
		else
			mainAxis = Vector3.new(0, 0, math.sign(toCenterLocal.Z))
		end
	end

	local thickness = 0
	local extentX = wallSize.X

	if mainAxis.X ~= 0 then
		thickness = wallSize.X
		extentX = wallSize.Z
	else
		thickness = wallSize.Z
		extentX = wallSize.X
	end

	local inwardNormalWorld = wallCF:VectorToWorldSpace(mainAxis).Unit
	local innerFaceCF = wallCF * CFrame.new(mainAxis * (thickness / 2)) * CFrame.Angles(0, if mainAxis.X ~= 0 then math.pi / 2 else 0, 0)

	return inwardNormalWorld, thickness, innerFaceCF, Vector2.new(extentX, wallSize.Y)
end

-- 与 BulletManager 轴对齐墙一致：当 BaseDisk 中心距边界很近时返回向内的法线
-- 多加一些缓冲区应对高速缩圈
local function ComputeInwardNormalFromInnerWallProximity(worldPos: Vector3, unitRadius: number?): Vector3?
	local walls = GetArenaWalls()
	if #walls == 0 then
		return nil
	end

	local radius = unitRadius or (2.5) -- 假定半径，后续动态读取
	-- 判定距离 (tol)：在半径边缘之外的额外缓冲区
	local tol = GameConfig.ArenaWallProximityStuds
	local combinedNormal = Vector3.zero
	local found = false

	for _, wall in walls do
		local inwardNormalWorld, thickness, innerFaceCF, extent = GetWallInwardNormal(wall, worldPos)

		-- 计算载具中心距离内侧表面的相对深度
		-- distToSurface = 0 (在面上), > 0 (在墙内), < 0 (在安全区)
		local distToCenter = (worldPos - wall.Position):Dot(inwardNormalWorld)
		local distToSurface = (thickness / 2) - distToCenter

		-- 调试可视化
		UpdateWallDebugVisuals(wall, innerFaceCF, extent)

		-- 计算载具边缘的深度
		local edgeDepth = distToSurface + radius

		-- 正确的判定逻辑：
		-- 1. 边缘深度 > -tol (载具边缘已接近或越过内表面)
		-- 2. 边缘深度 < thickness + 10 (载具还在墙体厚度范围内，防止判定到竞技场另一侧)
		if edgeDepth > -tol and edgeDepth < thickness + 10 then
			combinedNormal += inwardNormalWorld
			found = true
		end
	end

	if not found then
		return nil
	end
	return combinedNormal.Unit
end

-- 从 BaseDisk 指向场地内侧的水平单位法线：优先物理接触；否则用距内墙近距离（不依赖墙 Part 命名）
local function ComputeAggregatedWallInwardNormal(root: BasePart): Vector3?
	local sum = Vector3.zero
	local count = 0
	local pos = root.Position
	local radius = root.Size.X / 2

	for _, part in root:GetTouchingParts() do
		if part:IsA("BasePart") and IsLikelyArenaWallPart(part) then
			-- 使用平面法线而不是简单的向量差，确保反弹方向正确
			local inwardNormal = GetWallInwardNormal(part, pos)
			sum += inwardNormal
			count += 1
		end
	end

	if count > 0 then
		local agg = Vector3.new(sum.X, 0, sum.Z)
		if agg.Magnitude > 0.05 then
			return agg.Unit
		end
	end
	return ComputeInwardNormalFromInnerWallProximity(pos, radius)
end

-- 解决载具重叠的被动解围逻辑 (针对 Touched 事件失效的情况)
local function ResolveVehicleOverlaps(state: ClientUnitState, dt: number)
	local root = state.unitPart
	local pos = root.Position
	local radius = GameConfig.VehicleCollisionRadius
	
	for playerId, otherState in unitStateMap do
		if playerId == localPlayerId then continue end
		if otherState.unitPart == nil or otherState.unitPart.Parent == nil then continue end
		
		local otherPos = otherState.unitPart.Position
		local delta = pos - otherPos
		local flatDelta = Vector3.new(delta.X, 0, delta.Z)
		if flatDelta.Magnitude < radius and flatDelta.Magnitude > 0.1 then
			local pushDir = flatDelta.Unit
			local overlapDepth = radius - flatDelta.Magnitude
			-- 施加一个与重叠深度成正比的排斥初速度
			local pushVel = pushDir * (overlapDepth * GameConfig.VehicleOverlapResolutionSpeed)
			root.AssemblyLinearVelocity += pushVel * dt * 60 -- 归一化强度
		end
	end
end

-- BaseDisk：水平驱动力 + 仅速度 yaw 的直立对齐（与瞄准解耦）
local function UpdateBaseDiskLocomotion(state: ClientUnitState, _dt: number, applyHorizontalDrive: boolean)
	local drive = state.driveVectorForce
	if drive == nil then
		return
	end

	local root = state.unitPart
	-- 恢复旋转逻辑：仅更新旋转部分以保持竖直且根据 spinAngleRad 自转
	-- 同时保持当前位置，不对 Position 做任何干预以消除“异常拉力”
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
		local desired = targetDir.Unit * GameConfig.UnitSpeed
		local err = desired - curXZ
		drive.Force = Vector3.new(err.X, 0, err.Z) * (GameConfig.DriveHorizontalForceGain * mass)
	end

	local speed = curXZ.Magnitude
	if speed > GameConfig.UnitMaxHorizontalSpeed then
		local damp = (speed - GameConfig.UnitMaxHorizontalSpeed) * mass * 2
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
		if now - state.lastWallBounceClock >= GameConfig.WallBounceCooldown then
			local velInto = curXZ:Dot(inward)
			local targetDir = Vector3.new(state.targetVelX, 0, state.targetVelZ)
			-- 安全获取目标方向，防止零向量导致 NaN
			local targetDirUnit = if targetDir.Magnitude > 0.001 then targetDir.Unit else Vector3.zero
			local desiredDot = targetDirUnit:Dot(inward)

			local shouldBounce = (velInto < GameConfig.WallBounceVelThreshold)
				or (curXZ.Magnitude < GameConfig.WallStuckSpeedThreshold and desiredDot < GameConfig.WallStuckAngleThreshold)
			if shouldBounce then
				state.lastWallBounceClock = now
				local newSpeed = GameConfig.UnitSpeed * GameConfig.WallBounceSpeedMultiplier
				root.AssemblyLinearVelocity = inward * newSpeed
				if targetDir.Magnitude >= 1e-4 then
					local du = targetDir.Unit
					local reflected = du - 2 * inward:Dot(du) * inward
					local rFlat = Vector3.new(reflected.X, 0, reflected.Z)
					if rFlat.Magnitude > 1e-4 then
						local r = rFlat.Unit * GameConfig.UnitSpeed
						state.targetVelX = r.X
						state.targetVelZ = r.Z
					end
				end
			end
		end
	end
end

local function UpdateLocalDrive(state: ClientUnitState, dt: number)
	-- 旋转角度已在全局循环中更新
	
	local drive = state.driveVectorForce
	if drive == nil then
		return
	end

	UpdateBaseDiskLocomotion(state, dt, true)
	ResolveVehicleOverlaps(state, dt)
end

function BulletClientManager.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	localPlayerId = players.LocalPlayer.UserId

	local function OnHeartbeat(dt: number)
		-- 全局更新所有单位的旋转和解围表现
		for _, state in unitStateMap do
			if state.unitPart == nil or state.unitPart.Parent == nil then
				continue
			end
			
			-- 只有 Fighting 阶段才持续更新自转角度
			if matchState == "Fighting" then
				state.spinAngleRad = (state.spinAngleRad + math.rad(GameConfig.UnitRotationSpeed) * dt * state.spinDir) % (math.pi * 2)
			end
			
			-- 更新基础表现 (CFrame 旋转)
			if state.isLocal then
				-- 本地单位只在非观察阶段更新驱动和解围
				if IsGameStartObservePhase() then
					ZeroHorizontalVelocity(state.unitPart)
					state.unitPart.AssemblyAngularVelocity = Vector3.zero
					state.spinAngleRad = BaseDiskDriveYawRadFromState(state)
					UpdateBaseDiskLocomotion(state, dt, false)
				elseif IsFightingDriveActive() then
					UpdateLocalDrive(state, dt)
				else
					-- 其它非战斗阶段也需要保持自转视觉效果
					UpdateBaseDiskLocomotion(state, dt, false)
				end
			else
				-- 远程单位仅更新旋转表现
				UpdateBaseDiskLocomotion(state, dt, false)
			end
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
	local state = unitStateMap[playerId]
	if state ~= nil and state.driveVectorForce ~= nil then
		state.driveVectorForce.Force = Vector3.zero
	end
	unitStateMap[playerId] = nil
end
function BulletClientManager.OnFireAccepted(playerId: number, fireTime: number, spawnPos: Vector3, shotDir: Vector3, serverTime: number, bulletId: string)
	if playerId == localPlayerId then
		return
	end

	local state = unitStateMap[playerId]
	if state ~= nil then
		state.spinDir = -state.spinDir
		state.spinDampingUntil = os.clock() + GameConfig.SpinDampingDuration
		state.spinImpulseRadPerSec += GameConfig.TurretSpinImpulseOnFireRadPerSec * state.spinDir
		local latency = workspaceService:GetServerTimeNow() - serverTime
		-- The expected launch time from server's perspective:
		local expectedLaunchTime = fireTime + GameConfig.FireCastTime
		local currentServerTime = workspaceService:GetServerTimeNow()
		
		if currentServerTime >= expectedLaunchTime then
			-- Already launched, extrapolate
			local flightTime = currentServerTime - expectedLaunchTime
			local adjustedSpawnPos = spawnPos + (shotDir * GameConfig.ProjectileSpeed * flightTime)
			SpawnLocalVisualProjectile(adjustedSpawnPos, shotDir, playerId, bulletId)
		else
			-- Not launched yet, wait the remaining time
			task.delay(expectedLaunchTime - currentServerTime, function()
				SpawnLocalVisualProjectile(spawnPos, shotDir, playerId, bulletId)
			end)
		end
	end
end

function BulletClientManager.OnHit(targetPlayerId: number, fromPlayerId: number, _hitDirection: Vector3, _hitCount: number, bulletId: string, hitPosition: Vector3)
	local targetState = unitStateMap[targetPlayerId]
	if targetState == nil then
		return
	end
	targetState.spinDir = (math.random(0, 1) == 0) and 1 or -1
	local sign = (math.random(0, 1) == 0) and 1 or -1
	targetState.spinImpulseRadPerSec += GameConfig.TurretSpinImpulseOnHitRadPerSec * sign

	if targetPlayerId == localPlayerId then
		local flatDir = Vector3.new(_hitDirection.X, 0, _hitDirection.Z)
		if flatDir.Magnitude > 0.001 then
			local knockbackDir = flatDir.Unit
			targetState.unitPart.AssemblyLinearVelocity = knockbackDir * (GameConfig.UnitSpeed * GameConfig.BulletHitSpeedMultiplier)
			targetState.targetVelX = knockbackDir.X * GameConfig.UnitSpeed
			targetState.targetVelZ = knockbackDir.Z * GameConfig.UnitSpeed
		end
	end
	
	-- Destroy the matching visual projectile
	local targetProj = nil
	for projModel, info in activeVisualProjectiles do
		if info.bulletId == bulletId then
			targetProj = projModel
			break
		end
	end
	
	-- Fallback to distance based only if bulletId is unknown (rare)
	if targetProj == nil and (bulletId == "" or bulletId == nil) then
		local bestDist = math.huge
		for projModel, info in activeVisualProjectiles do
			if info.ownerId == fromPlayerId then
				local dist = (projModel:GetPivot().Position - targetState.unitPart.Position).Magnitude
				if dist < bestDist then
					bestDist = dist
					targetProj = projModel
				end
			end
		end
	end
	
	local finalExplosionPos = hitPosition
	-- If I am the victim, the hit should always feel like it hit MY vehicle precisely
	if targetPlayerId == localPlayerId and targetState.unitPart ~= nil then
		finalExplosionPos = targetState.unitPart.Position
	end
	
	if targetProj ~= nil then
		local explosion = Instance.new("Explosion")
		explosion.Position = finalExplosionPos
		explosion.BlastRadius = 0
		explosion.DestroyJointRadiusPercent = 0
		explosion.Visible = true
		explosion.Parent = workspaceService
		
		activeVisualProjectiles[targetProj] = nil
		targetProj:Destroy()
	else
		-- If bullet already exploded or was never there, still show an explosion at the target's current position to signify a hit
		local explosion = Instance.new("Explosion")
		explosion.Position = finalExplosionPos
		explosion.BlastRadius = 0
		explosion.DestroyJointRadiusPercent = 0
		explosion.Visible = true
		explosion.Parent = workspaceService
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
			local excludeList: { Instance } = { localState.model }
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
		local recoilDir = -shotDir
		localState.unitPart.AssemblyLinearVelocity = recoilDir * (GameConfig.UnitSpeed * GameConfig.FireRecoilSpeedMultiplier)
		localState.targetVelX = recoilDir.X * GameConfig.UnitSpeed * GameConfig.FireRecoilSpeedMultiplier
		localState.targetVelZ = recoilDir.Z * GameConfig.UnitSpeed * GameConfig.FireRecoilSpeedMultiplier
		localState.spinImpulseRadPerSec += GameConfig.TurretSpinImpulseOnFireRadPerSec * localState.spinDir
	end

	local bulletId = HttpService:GenerateGUID(false)
	NetMsg.FireRequestFire(spawnPos, shotDir, workspaceService:GetServerTimeNow(), bulletId)
	
	task.delay(GameConfig.FireCastTime, function()
		SpawnLocalVisualProjectile(spawnPos, shotDir, localPlayerId, bulletId)
	end)
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
