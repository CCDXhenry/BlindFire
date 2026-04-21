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

export type DriveState = {
	targetVelX: number,
	targetVelZ: number,
	spinAngleRad: number,
	lastWallBounceClock: number,
	lastVehicleBumpClock: number,
}

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
	local walls: { BasePart } = {}
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

	local radius = unitRadius or (2.5)
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
		if part:IsA("BasePart") and IsLikelyArenaWallPart(part) then
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

function VehicleLocomotionTool.AngleToVelocityXZ(angleDeg: number): (number, number)
	local rad = math.rad(angleDeg)
	return math.cos(rad) * GameConfig.UnitSpeed, math.sin(rad) * GameConfig.UnitSpeed
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

function VehicleLocomotionTool.UpdateBaseDiskLocomotion(
	state: DriveState,
	root: BasePart,
	drive: VectorForce,
	_dt: number,
	applyHorizontalDrive: boolean
)
	root.CFrame = CFrame.new(root.Position) * VehicleLocomotionTool.UprightGoalCFrame(state.spinAngleRad)

	if not applyHorizontalDrive then
		drive.Force = Vector3.zero
		return
	end

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
				local newSpeed = GameConfig.UnitSpeed * GameConfig.WallBounceSpeedMultiplier
				root.AssemblyLinearVelocity = inward * newSpeed
				if targetDir2.Magnitude >= 1e-4 then
					local du = targetDir2.Unit
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
	local radius = GameConfig.VehicleCollisionRadius

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

local function reflectTargetVelForVehicleBump(state: DriveState, normalAwayFromOther: Vector3)
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
		local r = rFlat.Unit * GameConfig.UnitSpeed
		state.targetVelX = r.X
		state.targetVelZ = r.Z
	end
end

--[[
	成对处理车-车碰撞：对两车施加相反水平冲量（与旧版双方客户端各收 Touched 的效果一致）。
	shouldInclude 为 nil 时处理 map 内全部单位。
]]
function VehicleLocomotionTool.ResolveAllVehicleBumps(
	unitInfoMap: { [number]: VehicleBumpUnitInfo },
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
			-- 物理接触优先（与旧版 Touched 一致）；否则用两盘水平半径之和 + 余量，避免「刚好 5 stud」被 dist>=5 判掉
			local sumRadii = horizontalHalfExtentXZ(rootA) + horizontalHalfExtentXZ(rootB)
			local maxCenterDist = math.max(sumRadii + 0.6, GameConfig.VehicleCollisionRadius)
			local touching = vehiclesPhysicallyTouching(rootA, uB.unitModel) or vehiclesPhysicallyTouching(rootB, uA.unitModel)
			if not touching and dist > maxCenterDist then
				continue
			end
			-- 初始 lastVehicleBumpClock 须为 -inf，否则 now-0 会在开局被误判为冷却中
			if math.min(now - uA.lastVehicleBumpClock, now - uB.lastVehicleBumpClock) < cd then
				continue
			end

			local bumpDir = flat.Unit
			local newSpeed = GameConfig.UnitSpeed * GameConfig.VehicleBumpSpeedMultiplier
			rootA.AssemblyLinearVelocity = bumpDir * newSpeed
			rootB.AssemblyLinearVelocity = (-bumpDir) * newSpeed

			uA.lastVehicleBumpClock = now
			uB.lastVehicleBumpClock = now

			reflectTargetVelForVehicleBump(uA, bumpDir)
			reflectTargetVelForVehicleBump(uB, -bumpDir)
		end
	end
end

return VehicleLocomotionTool
