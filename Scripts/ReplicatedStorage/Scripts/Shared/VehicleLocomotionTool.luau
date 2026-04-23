--!strict
--[[
	服务端与客户端共用的载具水平驱动、贴墙与车-车交互逻辑。
	服务端权威模式下仅服务端应调用 Update / Resolve；客户端可只读或不再调用。
]]
local VehicleLocomotionTool = {}

local workspaceService = game:GetService("Workspace")

local scripts = game:GetService("ReplicatedStorage"):WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local BASE_DISK_MESH_OFFSET = CFrame.Angles(0, 0, 0)

local function isNaN(n: number): boolean
	return n ~= n
end

export type DriveState = {
	targetVelX: number,
	targetVelZ: number,
	spinAngleRad: number,
	lastWallBounceClock: number,
	lastVehicleBumpClock: number,
	lastPos: Vector3?,
	stuckTime: number?,
}

-- 缓存的竞技场碰撞墙列表，仅在首次调用时初始化（名称精确匹配 "ArenaWall"）
local cachedArenaWalls: { BasePart }? = nil

local function GetArenaWalls(): { BasePart }
	if cachedArenaWalls ~= nil then
		return cachedArenaWalls
	end
	local walls: { BasePart } = {}
	local arena = workspaceService:FindFirstChild("Arena")
	if arena then
		for _, child in arena:GetDescendants() do
			if child:IsA("BasePart") and child.Name == "ArenaWall" then
				table.insert(walls, child)
			end
		end
	end
	cachedArenaWalls = walls
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

local function GetWallInwardNormal(wall: BasePart, worldPos: Vector3): (Vector3, number, CFrame, Vector2)
	local wallCF = wall.CFrame
	local wallSize = wall.Size

	local mainAxisAttr = wall:GetAttribute("LocalInwardNormal")
	local mainAxis: Vector3

	if typeof(mainAxisAttr) == "vector" or typeof(mainAxisAttr) == "Vector3" then
		mainAxis = mainAxisAttr :: Vector3
	else
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

local function ComputeInwardNormalFromInnerWallProximity(worldPos: Vector3, unitRadius: number?): Vector3?
	local walls = GetArenaWalls()
	if #walls == 0 then
		return nil
	end

	local radius = unitRadius or 2.5
	local tol = GameConfig.ArenaWallProximityStuds
	local combinedNormal = Vector3.zero
	local found = false

	for _, wall in walls do
		local inwardNormalWorld, thickness, _innerFaceCF, _extent = GetWallInwardNormal(wall, worldPos)

		local distToCenter = (worldPos - wall.Position):Dot(inwardNormalWorld)
		local distToSurface = (thickness / 2) - distToCenter

		local edgeDepth = distToSurface + radius

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

function VehicleLocomotionTool.ComputeAggregatedWallInwardNormal(root: BasePart): Vector3?
	local sum = Vector3.zero
	local count = 0
	local pos = root.Position
	local radius = root.Size.X / 2

	for _, part in root:GetTouchingParts() do
		if part:IsA("BasePart") and part.Name == "ArenaWall" then
			local inwardNormalWorld, _, _, _ = GetWallInwardNormal(part, pos)
			sum += inwardNormalWorld
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

function VehicleLocomotionTool.UprightGoalCFrame(hullYawRad: number): CFrame
	return CFrame.Angles(0, hullYawRad, 0) * BASE_DISK_MESH_OFFSET
end

function VehicleLocomotionTool.AngleToVelocityXZ(angleDeg: number, customSpeed: number?): (number, number)
	local rad = math.rad(angleDeg)
	local speed = customSpeed or GameConfig.UnitSpeed
	return math.cos(rad) * speed, math.sin(rad) * speed
end

function VehicleLocomotionTool.BaseDiskDriveYawRadFromState(state: DriveState, root: BasePart): number
	local vel = root.AssemblyLinearVelocity
	local xz = Vector3.new(vel.X, 0, vel.Z)
	if xz.Magnitude >= GameConfig.HullYawVelocityEpsilonStudsPerSec then
		return math.atan2(-xz.X, -xz.Z)
	end
	return math.atan2(state.targetVelZ, state.targetVelX)
end

function VehicleLocomotionTool.EnsureVehicleDriveConstraints(baseDisk: BasePart): VectorForce
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
	vectorForce.Enabled = true

	local upAtt = baseDisk:FindFirstChild("UprightAttachment")
	if upAtt == nil or not upAtt:IsA("Attachment") then
		if upAtt ~= nil then
			upAtt:Destroy()
		end
		local newUpAtt = Instance.new("Attachment")
		newUpAtt.Name = "UprightAttachment"
		newUpAtt.Parent = baseDisk
		newUpAtt.Axis = Vector3.new(0, 1, 0)
		upAtt = newUpAtt
	end

	local ao = baseDisk:FindFirstChild("UprightAlignOrientation")
	if ao == nil or not ao:IsA("AlignOrientation") then
		if ao ~= nil then
			ao:Destroy()
		end
		local newAo = Instance.new("AlignOrientation")
		newAo.Name = "UprightAlignOrientation"
		newAo.Parent = baseDisk
		ao = newAo
	end
	local alignOrientation = ao :: AlignOrientation
	alignOrientation.Attachment0 = upAtt
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.AlignType = Enum.AlignType.PrimaryAxisParallel
	alignOrientation.PrimaryAxis = Vector3.new(0, 1, 0)
	alignOrientation.RigidityEnabled = false
	alignOrientation.MaxTorque = 10000000
	alignOrientation.Responsiveness = 200

	local av = baseDisk:FindFirstChild("SpinAngularVelocity")
	if av == nil or not av:IsA("AngularVelocity") then
		if av ~= nil then
			av:Destroy()
		end
		local newAv = Instance.new("AngularVelocity")
		newAv.Name = "SpinAngularVelocity"
		newAv.Parent = baseDisk
		av = newAv
	end
	local angularVel = av :: AngularVelocity
	angularVel.Attachment0 = driveAtt
	angularVel.RelativeTo = Enum.ActuatorRelativeTo.World
	angularVel.AngularVelocity = Vector3.zero
	angularVel.MaxTorque = 1000000

	local existingProps = baseDisk.CustomPhysicalProperties
	if existingProps ~= nil then
		local bounceElasticity = math.clamp(GameConfig.WallBounceElasticity, 0, 1)
		baseDisk.CustomPhysicalProperties = PhysicalProperties.new(
			existingProps.Density,
			0, -- 强制设为 0，防止自转物体互相挤压时产生破坏性的巨大摩擦力（导致斜向飞天）
			bounceElasticity,
			100, -- 最大摩擦力权重，覆盖其他物体的摩擦力
			existingProps.ElasticityWeight
		)
	end

	return vectorForce
end

function VehicleLocomotionTool.UpdateBaseDiskLocomotion(
	state: DriveState,
	root: BasePart,
	drive: VectorForce,
	_dt: number,
	applyHorizontalDrive: boolean,
	customSpeed: number?
)
	local _, yaw, _ = root.CFrame:ToEulerAnglesYXZ()
	state.spinAngleRad = yaw

	if not applyHorizontalDrive then
		drive.Force = Vector3.zero
		return
	end

	local mass = root.AssemblyMass
	local vel = root.AssemblyLinearVelocity
	local curXZ = Vector3.new(vel.X, 0, vel.Z)

	local targetDir = Vector3.new(state.targetVelX, 0, state.targetVelZ)
	local isTargetVelInvalid = (targetDir.Magnitude < 1e-4) or isNaN(state.targetVelX) or isNaN(state.targetVelZ)

	if isTargetVelInvalid then
		-- 自愈逻辑：如果 applyHorizontalDrive 为 true 但速度矢量为 0 或 NaN，则根据当前旋转角恢复基础速度
		local recoveredX, recoveredZ = VehicleLocomotionTool.AngleToVelocityXZ(math.deg(state.spinAngleRad), customSpeed)
		state.targetVelX = recoveredX
		state.targetVelZ = recoveredZ
		targetDir = Vector3.new(recoveredX, 0, recoveredZ)
		root.AssemblyLinearVelocity = targetDir
	end

	-- 静态卡死检测：如果驱动开启，但长时间位移极小
	local currentPos = root.Position
	if state.lastPos ~= nil then
		if _dt > 0.2 then
			-- 服务器发生卡顿（例如新玩家加载载具），忽略这一帧的位移，防止误判卡死
			state.stuckTime = 0
		else
			local distMoved = (currentPos - state.lastPos).Magnitude
			if distMoved < GameConfig.StuckVelocityThreshold * _dt then
				state.stuckTime = (state.stuckTime or 0) + _dt
				if state.stuckTime >= GameConfig.StuckStallDuration then
					-- 触发强制重启位移
					local recoveredX, recoveredZ = VehicleLocomotionTool.AngleToVelocityXZ(math.deg(state.spinAngleRad), customSpeed)
					state.targetVelX = recoveredX
					state.targetVelZ = recoveredZ
					targetDir = Vector3.new(recoveredX, 0, recoveredZ)
					root.AssemblyLinearVelocity = Vector3.new(targetDir.X, root.AssemblyLinearVelocity.Y, targetDir.Z)
					state.stuckTime = 0
					warn(string.format("[VehicleLocomotionTool] Stuck detected for unit, resetting targetVel"))
				end
			else
				state.stuckTime = 0
			end
		end
	end
	state.lastPos = currentPos

	local targetDirUnit = if targetDir.Magnitude > 0.001 then targetDir.Unit else Vector3.new(0, 0, -1)
	local speed = customSpeed or GameConfig.UnitSpeed
	local desired = targetDirUnit * speed
	local err = desired - curXZ
	drive.Force = Vector3.new(err.X, 0, err.Z) * (GameConfig.DriveHorizontalForceGain * mass)

	local speed = curXZ.Magnitude
	if speed > GameConfig.UnitMaxHorizontalSpeed then
		local damp = (speed - GameConfig.UnitMaxHorizontalSpeed) * mass * 2
		drive.Force -= curXZ.Unit * damp
	end

	local inward = VehicleLocomotionTool.ComputeAggregatedWallInwardNormal(root)
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
			local targetDir2 = Vector3.new(state.targetVelX, 0, state.targetVelZ)
			local targetDirUnit = if targetDir2.Magnitude > 0.001 then targetDir2.Unit else Vector3.zero
			local desiredDot = targetDirUnit:Dot(inward)

			local shouldBounce = (velInto < GameConfig.WallBounceVelThreshold)
				or (curXZ.Magnitude < GameConfig.WallStuckSpeedThreshold and desiredDot < GameConfig.WallStuckAngleThreshold)
			if shouldBounce then
				state.lastWallBounceClock = now
				local speed = customSpeed or GameConfig.UnitSpeed
				local newSpeed = speed * GameConfig.WallBounceSpeedMultiplier
				root.AssemblyLinearVelocity = Vector3.new(inward.X * newSpeed, root.AssemblyLinearVelocity.Y, inward.Z * newSpeed)
				if targetDir2.Magnitude >= 1e-4 then
					local du = targetDir2.Unit
					local reflected = du - 2 * inward:Dot(du) * inward
					local rFlat = Vector3.new(reflected.X, 0, reflected.Z)
					if rFlat.Magnitude > 1e-4 then
						local speed = customSpeed or GameConfig.UnitSpeed
						local r = rFlat.Unit * speed
						state.targetVelX = r.X
						state.targetVelZ = r.Z
					end
				end
			end
		end
	end
end

export type UnitInfoLike = {
	rootPart: BasePart,
	targetVelX: number,
	targetVelZ: number,
}

export type VehicleBumpUnitInfo = DriveState & {
	rootPart: BasePart,
	unitModel: Model,
}

function VehicleLocomotionTool.ResolveVehicleOverlaps(selfInfo: UnitInfoLike, unitInfoMap: { [number]: UnitInfoLike }, selfId: number, dt: number)
	local root = selfInfo.rootPart
	local pos = root.Position
	local radius = GameConfig.GetVehicleCollisionRadius()

	for otherId, otherInfo in unitInfoMap do
		if otherId == selfId then
			continue
		end
		local otherRoot = otherInfo.rootPart
		if otherRoot.Parent == nil then
			continue
		end
		local otherPos = otherRoot.Position
		local delta = pos - otherPos
		local flatDelta = Vector3.new(delta.X, 0, delta.Z)
		if flatDelta.Magnitude < radius and flatDelta.Magnitude > 0.1 then
			local pushDir = flatDelta.Unit
			local overlapDepth = radius - flatDelta.Magnitude
			local pushVel = pushDir * (overlapDepth * GameConfig.VehicleOverlapResolutionSpeed)
			root.AssemblyLinearVelocity += pushVel * dt * 60
		end
	end
end

local function horizontalHalfExtentXZ(root: BasePart): number
	return 0.5 * math.max(root.Size.X, root.Size.Z)
end

local function vehiclesPhysicallyTouching(root: BasePart, otherVehicle: Model): boolean
	for _, p in root:GetTouchingParts() do
		if p:IsA("BasePart") and p:IsDescendantOf(otherVehicle) then
			return true
		end
	end
	return false
end

local function reflectTargetVelForVehicleBump(state: DriveState, normalAwayFromOther: Vector3, customSpeed: number?)
	local currentTarget = Vector3.new(state.targetVelX, 0, state.targetVelZ)
	if currentTarget.Magnitude <= 0.01 then
		return
	end
	local du = currentTarget.Unit
	if normalAwayFromOther:Dot(du) >= GameConfig.VehicleBumpDotThreshold then
		return
	end
	local reflected = du - 2 * normalAwayFromOther:Dot(du) * normalAwayFromOther
	local rFlat = Vector3.new(reflected.X, 0, reflected.Z)
	if rFlat.Magnitude > 0.01 then
		local speed = customSpeed or GameConfig.UnitSpeed
		local r = rFlat.Unit * speed
		state.targetVelX = r.X
		state.targetVelZ = r.Z
	end
end

--[[
	成对处理车-车碰撞：对两车施加相反水平冲量（与旧版双方客户端各收 Touched 的效果一致）。
	shouldInclude 为 nil 时处理 map 内全部单位。
]]
function VehicleLocomotionTool.ResolveAllVehicleBumps(
	unitInfoMap: { [number]: VehicleBumpUnitInfo & { vehicleConfig: any? } },
	shouldInclude: ((number) -> boolean)?
)
	local now = os.clock()
	local cd = GameConfig.VehicleBumpCooldown
	local ids: { number } = {}
	for id in unitInfoMap do
		if shouldInclude == nil or shouldInclude(id) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)

	for i = 1, #ids do
		for j = i + 1, #ids do
			local idA = ids[i]
			local idB = ids[j]
			local uA = unitInfoMap[idA]
			local uB = unitInfoMap[idB]
			local rootA = uA.rootPart
			local rootB = uB.rootPart
			if rootA.Parent == nil or rootB.Parent == nil then
				continue
			end
			local delta = rootA.Position - rootB.Position
			local flat = Vector3.new(delta.X, 0, delta.Z)
			local dist = flat.Magnitude
			if dist < 1e-3 then
				continue
			end
			local sumRadii = horizontalHalfExtentXZ(rootA) + horizontalHalfExtentXZ(rootB)
			local maxCenterDist = math.max(sumRadii + 1.2, GameConfig.GetVehicleCollisionRadius())
			-- 快速距离剔除：距离明显过远时跳过 GetTouchingParts（物理查询），减少 O(n²) 开销
			-- 留 1 stud 安全余量，确保不会漏掉刚好掠过边界的物理接触
			if dist > maxCenterDist + 1 then
				continue
			end
			-- 在可能接触的范围内，再做精确物理查询
			local touching = vehiclesPhysicallyTouching(rootA, uB.unitModel) or vehiclesPhysicallyTouching(rootB, uA.unitModel)
			if not touching and dist > maxCenterDist then
				continue
			end
			-- 初始 lastVehicleBumpClock 须为 -inf，否则 now-0 会在开局被误判为冷却中
			if math.min(now - uA.lastVehicleBumpClock, now - uB.lastVehicleBumpClock) < cd then
				continue
			end

			local bumpDir = flat.Unit
			local speedA = if uA.vehicleConfig then uA.vehicleConfig.moveSpeed else GameConfig.UnitSpeed
			local speedB = if uB.vehicleConfig then uB.vehicleConfig.moveSpeed else GameConfig.UnitSpeed

			local bumpSpeedA = speedA * GameConfig.VehicleBumpSpeedMultiplier
			local bumpSpeedB = speedB * GameConfig.VehicleBumpSpeedMultiplier

			rootA.AssemblyLinearVelocity = Vector3.new(bumpDir.X * bumpSpeedA, rootA.AssemblyLinearVelocity.Y, bumpDir.Z * bumpSpeedA)
			rootB.AssemblyLinearVelocity = Vector3.new(-bumpDir.X * bumpSpeedB, rootB.AssemblyLinearVelocity.Y, -bumpDir.Z * bumpSpeedB)

			uA.lastVehicleBumpClock = now
			uB.lastVehicleBumpClock = now

			reflectTargetVelForVehicleBump(uA, bumpDir, speedA)
			reflectTargetVelForVehicleBump(uB, -bumpDir, speedB)
		end
	end
end

return VehicleLocomotionTool
