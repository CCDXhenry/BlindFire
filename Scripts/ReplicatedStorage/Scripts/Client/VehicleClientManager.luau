--!strict
local VehicleClientManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local workspaceService = game:GetService("Workspace")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local VehicleLocomotionTool = require(sharedScripts:FindFirstChild("VehicleLocomotionTool"))

type ClientVehicleState = {
	playerId: number,
	vehicleId: number,
	model: Model?,
	rootPart: BasePart?,
	proxyRootPart: BasePart?,
	spinDir: number,
	forceDirection: Vector3,
	targetVelX: number,
	targetVelZ: number,
	spinAngleRad: number,
	lastWallBounceClock: number,
	lastVehicleBumpClock: number,
	driveVectorForce: VectorForce?,
	lastPos: Vector3?,
	stuckTime: number?,
	targetServerPosition: Vector3?,
	targetServerYaw: number?,
	targetServerVelocity: Vector3?,
	targetServerAngVelY: number?,
	lastServerTime: number,
	lastServerTick: number,
	isParticipant: boolean,
	isLocalControlled: boolean,
	nextInputSeq: number,
	lastAckInputSeq: number,
	lastInputSendAccumulator: number,
	pendingInputList: { GameConfig.VehicleInputCmd },
	snapshotBuffer: { GameConfig.VehicleStateSnapshot },
	-- 旋转写入跟踪：避免每帧覆盖 SpinAngularVelocity 与抑制反向抖动
	lastAppliedSpinDir: number,
	lastAppliedSpinMatchState: GameConfig.MatchState?,
	lastSpinDirFlipClock: number,
	-- 本地玩家被命中时：短时间抑制服务端纠偏，避免“先被击退后看到命中”
	suppressServerCorrectionUntilServerTime: number,
	hitSoftReconcileUntilServerTime: number,
}

local VEHICLE_MODEL_NAME_PREFIX = "Vehicle_"
local VEHICLE_PROXY_PART_NAME_PREFIX = "VehiclePhysicsProxy_"
local CLIENT_VEHICLE_VISUAL_COLLISION_GROUP = "ClientVehicleVisual"
local HIT_SOFT_RECONCILE_DURATION_SEC = 0.45
local HIT_SOFT_RECONCILE_HARD_SNAP_MULTIPLIER = 3
local HIT_SOFT_RECONCILE_VELOCITY_CONVERGE_RATE = 16
local HIT_SOFT_RECONCILE_MAX_CORRECTION_SPEED = 140

local vehicleStateMap: { [number]: ClientVehicleState } = {}
local matchState: GameConfig.MatchState = GameConfig.MatchState.InLobby
local isInitialized = false
local localPlayerId = 0

local function Clamp01(value: number): number
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

local function _NormalizeAngleRad(angleRad: number): number
	local twoPi = math.pi * 2
	local normalized = (angleRad + math.pi) % twoPi
	if normalized < 0 then
		normalized += twoPi
	end
	return normalized - math.pi
end

local function _LerpAngleRad(fromRad: number, toRad: number, alpha: number): number
	local delta = _NormalizeAngleRad(toRad - fromRad)
	return _NormalizeAngleRad(fromRad + delta * alpha)
end

local function _BuildYawCFrame(position: Vector3, yawRad: number): CFrame
	return CFrame.new(position) * VehicleLocomotionTool.UprightGoalCFrame(yawRad)
end

local function SnapshotYawToDriveYawRad(snapshotYawRad: number): number
	-- Snapshot yaw is derived from LookVector, while UprightGoalCFrame expects the drive yaw.
	local lookX = math.cos(snapshotYawRad)
	local lookZ = math.sin(snapshotYawRad)
	return math.atan2(-lookX, -lookZ)
end

local function BuildSnapshotYawCFrame(position: Vector3, snapshotYawRad: number): CFrame
	return _BuildYawCFrame(position, SnapshotYawToDriveYawRad(snapshotYawRad))
end

local function GetSnapshotYawFromCFrame(cframe: CFrame): number
	local look = cframe.LookVector
	return math.atan2(look.Z, look.X)
end

local function GetExpectedYawRateRad(state: ClientVehicleState): number
	return math.rad(GameConfig.UnitRotationSpeed) * state.spinDir
end

-- 接收到的 spinDir 变化加 debounce：避免快照/事件来回切换造成 SpinAngularVelocity 净旋转 0
local function TryUpdateSpinDirFromSnapshot(state: ClientVehicleState, newSpinDir: number)
	if newSpinDir ~= -1 and newSpinDir ~= 1 then
		return
	end
	if newSpinDir == state.spinDir then
		return
	end
	local nowClock = os.clock()
	local debounceSec = math.max(0, GameConfig.VehicleSpinDirDebounceMs) / 1000
	if (nowClock - state.lastSpinDirFlipClock) < debounceSec then
		return
	end
	state.spinDir = newSpinDir
	state.lastSpinDirFlipClock = nowClock
end

-- 仅在 spinDir / matchState 变化时写 SpinAngularVelocity，避免每帧覆盖与物理子步对冲
local function UpdateLocalSpinAngularVelocityIfChanged(state: ClientVehicleState, spinAV: AngularVelocity)
	local desiredSpinDir = if matchState == GameConfig.MatchState.Fighting then state.spinDir else 0
	if desiredSpinDir == state.lastAppliedSpinDir and matchState == state.lastAppliedSpinMatchState then
		return
	end
	if matchState == GameConfig.MatchState.Fighting then
		spinAV.AngularVelocity = Vector3.new(0, math.rad(GameConfig.UnitRotationSpeed) * state.spinDir, 0)
	else
		spinAV.AngularVelocity = Vector3.zero
	end
	state.lastAppliedSpinDir = desiredSpinDir
	state.lastAppliedSpinMatchState = matchState
end

local function IsParticipantFromPayload(value: unknown): boolean
	if value == true or value == 1 then
		return true
	end
	if typeof(value) == "string" then
		local lower = string.lower(value :: string)
		return lower == "true" or lower == "1"
	end
	return false
end

local function GetVehicleSpeed(vehicleId: number): number
	local vehicleData = GameConfig.VehicleDataMap[vehicleId]
	if vehicleData ~= nil and vehicleData.moveSpeed ~= nil then
		return vehicleData.moveSpeed
	end
	return GameConfig.UnitSpeed
end

local function IsVehicleVisualActiveState(state: GameConfig.MatchState): boolean
	-- MatchCountdown：StartRound 与本局入场 teleport 均仍处备战阶段，必须与 GameStartCountdown 一样更新代理/视觉，否则远端（含机器人）会卡在地下看不见
	return state == GameConfig.MatchState.Fighting
		or state == GameConfig.MatchState.GameStartCountdown
		or state == GameConfig.MatchState.MatchCountdown
end

local function NormalizeHorizontalDirection(direction: Vector3): Vector3
	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	if horizontal.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return horizontal.Unit
end

local function SnapshotToDirection(snapshot: GameConfig.VehicleStateSnapshot): Vector3
	local horizontal = Vector3.new(snapshot.velocity.X, 0, snapshot.velocity.Z)
	if horizontal.Magnitude > 0.01 then
		return horizontal.Unit
	end
	return Vector3.new(math.cos(snapshot.yaw), 0, math.sin(snapshot.yaw))
end

local function FindVehicleModel(playerId: number): (Model?, BasePart?)
	local model = workspaceService:FindFirstChild(VEHICLE_MODEL_NAME_PREFIX .. tostring(playerId))
	if model == nil or not model:IsA("Model") then
		return nil, nil
	end
	local baseDisk = model:FindFirstChild("BaseDisk")
	if baseDisk == nil or not baseDisk:IsA("BasePart") then
		return model, nil
	end
	return model, baseDisk
end

local function FindVehiclePhysicsProxyPart(playerId: number): BasePart?
	local inst = workspaceService:FindFirstChild(VEHICLE_PROXY_PART_NAME_PREFIX .. tostring(playerId))
	if inst ~= nil and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function CreateDefaultState(playerId: number): ClientVehicleState
	return {
		playerId = playerId,
		vehicleId = 1,
		model = nil,
		rootPart = nil,
		proxyRootPart = nil,
		spinDir = 1,
		forceDirection = Vector3.new(0, 0, -1),
		targetVelX = 0,
		targetVelZ = -GameConfig.UnitSpeed,
		spinAngleRad = 0,
		lastWallBounceClock = 0,
		lastVehicleBumpClock = 0,
		driveVectorForce = nil,
		lastPos = nil,
		stuckTime = 0,
		targetServerPosition = nil,
		targetServerYaw = nil,
		targetServerVelocity = nil,
		targetServerAngVelY = nil,
		lastServerTime = 0,
		lastServerTick = 0,
		isParticipant = true,
		isLocalControlled = playerId == localPlayerId,
		nextInputSeq = 1,
		lastAckInputSeq = 0,
		lastInputSendAccumulator = 0,
		pendingInputList = {},
		snapshotBuffer = {},
		lastAppliedSpinDir = 0,
		lastAppliedSpinMatchState = nil,
		lastSpinDirFlipClock = 0,
		suppressServerCorrectionUntilServerTime = 0,
		hitSoftReconcileUntilServerTime = 0,
	}
end

local function EnsureState(playerId: number): ClientVehicleState
	local existing = vehicleStateMap[playerId]
	if existing ~= nil then
		return existing
	end
	local created = CreateDefaultState(playerId)
	local model, rootPart = FindVehicleModel(playerId)
	created.model = model
	created.rootPart = rootPart
	created.proxyRootPart = FindVehiclePhysicsProxyPart(playerId)
	vehicleStateMap[playerId] = created
	return created
end

local function EnsureLocalDriveConstraintsForVisual(state: ClientVehicleState, rootPart: BasePart)
	-- 仅本地玩家自己的视觉车需要在客户端创建约束
	if not state.isLocalControlled then
		return
	end
	local existing = rootPart:FindFirstChild("SpinAngularVelocity")
	local needRebuild = state.driveVectorForce == nil
		or (state.driveVectorForce :: VectorForce).Parent == nil
		or existing == nil
		or not existing:IsA("AngularVelocity")
	if not needRebuild then
		return
	end
	if existing ~= nil and not existing:IsA("AngularVelocity") then
		warn(string.format("[VehicleClientManager] Local visual SpinAngularVelocity unexpectedly missing for player %d, rebuilding.", state.playerId))
	end
	state.driveVectorForce = VehicleLocomotionTool.EnsureVehicleDriveConstraints(rootPart)
	-- 重建后强制下一帧重写 SpinAngularVelocity
	state.lastAppliedSpinDir = 0
	state.lastAppliedSpinMatchState = nil
end

local function RefreshVehicleReference(state: ClientVehicleState): boolean
	if state.model ~= nil and state.model.Parent ~= nil and state.rootPart ~= nil and state.rootPart.Parent ~= nil then
		EnsureLocalDriveConstraintsForVisual(state, state.rootPart :: BasePart)
		return true
	end
	local model, rootPart = FindVehicleModel(state.playerId)
	state.model = model
	state.rootPart = rootPart
	state.proxyRootPart = FindVehiclePhysicsProxyPart(state.playerId)
	if model ~= nil then
		for _, inst in model:GetDescendants() do
			if inst:IsA("BasePart") then
				inst.CollisionGroup = CLIENT_VEHICLE_VISUAL_COLLISION_GROUP
			end
		end
	end
	if rootPart ~= nil then
		-- 模型重建路径下 driveVectorForce 引用旧实例，先置空再确保
		state.driveVectorForce = nil
		EnsureLocalDriveConstraintsForVisual(state, rootPart :: BasePart)
	end
	return model ~= nil and rootPart ~= nil
end

local function StopVehicleVisualMotion(state: ClientVehicleState)
	if not RefreshVehicleReference(state) then
		return
	end

	local drive = state.driveVectorForce
	if drive ~= nil and drive.Parent ~= nil then
		drive.Force = Vector3.zero
	end

	local rootPart = state.rootPart
	if rootPart ~= nil and rootPart.Parent ~= nil then
		local spinAV = rootPart:FindFirstChild("SpinAngularVelocity")
		if spinAV ~= nil and spinAV:IsA("AngularVelocity") then
			spinAV.AngularVelocity = Vector3.zero
		end
	end

	local model = state.model
	if model ~= nil and model.Parent ~= nil then
		for _, inst in model:GetDescendants() do
			if inst:IsA("BasePart") then
				inst.AssemblyLinearVelocity = Vector3.zero
				inst.AssemblyAngularVelocity = Vector3.zero
			end
		end
	elseif rootPart ~= nil and rootPart.Parent ~= nil then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end

	state.targetServerPosition = nil
	state.targetServerYaw = nil
	state.targetServerVelocity = nil
	state.targetServerAngVelY = nil
	state.lastInputSendAccumulator = 0
	state.hitSoftReconcileUntilServerTime = 0
	table.clear(state.snapshotBuffer)
end

local function StopAllVehicleVisualMotion()
	for _, state in vehicleStateMap do
		StopVehicleVisualMotion(state)
	end
end

local function ApplyRemoteProxyFollow(state: ClientVehicleState, rootPart: BasePart, dt: number)
	local proxyRoot = state.proxyRootPart
	if proxyRoot == nil or proxyRoot.Parent == nil then
		proxyRoot = FindVehiclePhysicsProxyPart(state.playerId)
		state.proxyRootPart = proxyRoot
	end
	if proxyRoot == nil then
		return
	end
	-- 位置可平滑；旋转必须用代理 Part 的完整 CFrame 旋转，不能用 LookVector 反推 yaw。
	-- atan2(LookVector) 与 CFrame.Angles(0, yaw, 0) 的 hull 角定义不一致，会导致反向与突变。
	local posAlpha = 1 - math.exp(-math.max(0, dt) * 14)
	posAlpha = Clamp01(posAlpha)
	local smoothedPos = rootPart.Position:Lerp(proxyRoot.Position, posAlpha)
	local rotationOnly = proxyRoot.CFrame - proxyRoot.Position
	rootPart.CFrame = CFrame.new(smoothedPos) * rotationOnly
end

local function ApplyDirectionToState(state: ClientVehicleState, newDirection: Vector3)
	state.forceDirection = NormalizeHorizontalDirection(newDirection)
	local speed = GetVehicleSpeed(state.vehicleId)
	state.targetVelX = state.forceDirection.X * speed
	state.targetVelZ = state.forceDirection.Z * speed
	state.spinAngleRad = math.atan2(state.targetVelZ, state.targetVelX)
end

local function PushInputCmd(state: ClientVehicleState, cmd: GameConfig.VehicleInputCmd)
	table.insert(state.pendingInputList, cmd)
	NetMsg.FireRequestVehicleInput(cmd)
end

local function TrimAckedInput(state: ClientVehicleState, ackInputSeq: number)
	state.lastAckInputSeq = math.max(state.lastAckInputSeq, ackInputSeq)
	local nextPending: { GameConfig.VehicleInputCmd } = {}
	for _, cmd in state.pendingInputList do
		if cmd.seq > ackInputSeq then
			table.insert(nextPending, cmd)
		end
	end
	state.pendingInputList = nextPending
end

local function ReplayPendingInput(state: ClientVehicleState)
	if not RefreshVehicleReference(state) then
		return
	end
	local rootPart = state.rootPart :: BasePart
	local drive = state.driveVectorForce
	if drive == nil then
		drive = VehicleLocomotionTool.EnsureVehicleDriveConstraints(rootPart)
		state.driveVectorForce = drive
	end
	local stepDt = 1 / math.max(1, GameConfig.VehicleSnapshotHz)
	local speed = GetVehicleSpeed(state.vehicleId)
	for _, cmd in state.pendingInputList do
		ApplyDirectionToState(state, cmd.moveDir)
		-- 重放本地未确认输入时直接采用客户端缓存的 spinDir（不走 debounce），保证回滚一致
		if cmd.spinDir == -1 or cmd.spinDir == 1 then
			state.spinDir = cmd.spinDir
		end
		VehicleLocomotionTool.UpdateBaseDiskLocomotion(state, rootPart, drive :: VectorForce, stepDt, true, speed)
	end
end

local function ReconcileLocalStateFromSnapshot(state: ClientVehicleState, snapshot: GameConfig.VehicleStateSnapshot)
	if snapshot.serverTick < state.lastServerTick then
		return
	end
	state.lastServerTick = snapshot.serverTick
	TrimAckedInput(state, snapshot.ackInputSeq)
	-- spinDir 已在调用方走 TryUpdateSpinDirFromSnapshot 处理过 debounce
	state.vehicleId = snapshot.vehicleId
	ApplyDirectionToState(state, SnapshotToDirection(snapshot))
	if not RefreshVehicleReference(state) then
		return
	end
	local rootPart = state.rootPart :: BasePart
	local currentPos = rootPart.Position
	local posErr = (snapshot.position - currentPos).Magnitude
	local nowServer = workspaceService:GetServerTimeNow()
	local suppressUntil = state.suppressServerCorrectionUntilServerTime or 0
	local shouldSuppress = nowServer < suppressUntil
	local isHitSoftReconcile = nowServer < (state.hitSoftReconcileUntilServerTime or 0)
	-- 硬 reconcile 门槛随当前速度放宽：高速载具允许 N 秒位移作为缓冲，避免快照延迟导致频繁拉扯
	local serverSpeed = Vector3.new(snapshot.velocity.X, 0, snapshot.velocity.Z).Magnitude
	local clientSpeed = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
	local effectiveSpeed = math.max(serverSpeed, clientSpeed)
	local speedAwareThreshold = effectiveSpeed * math.max(0, GameConfig.VehicleReconcilePosThresholdSecPerStud)
	local hardThreshold = math.max(GameConfig.VehicleReconcilePosThreshold, speedAwareThreshold)
	local shouldHardReconcile = posErr >= hardThreshold
	if shouldHardReconcile then
		local shouldUseHitSoftReconcile = shouldSuppress
			or (isHitSoftReconcile and posErr < hardThreshold * HIT_SOFT_RECONCILE_HARD_SNAP_MULTIPLIER)
		if shouldUseHitSoftReconcile then
			-- 被命中补偿窗口和随后的软纠偏窗口内不硬拉，避免高击退速度导致表现瞬移。
			state.targetServerPosition = snapshot.position
			state.targetServerYaw = snapshot.yaw
			state.targetServerVelocity = snapshot.velocity
			state.targetServerAngVelY = snapshot.angVelY
			return
		end
		rootPart.CFrame = BuildSnapshotYawCFrame(snapshot.position, snapshot.yaw)
		rootPart.AssemblyLinearVelocity = snapshot.velocity
		rootPart.AssemblyAngularVelocity = Vector3.new(0, snapshot.angVelY, 0)
		ReplayPendingInput(state)
		state.targetServerPosition = nil
		state.targetServerYaw = nil
		state.targetServerVelocity = nil
		state.targetServerAngVelY = nil
		return
	end
	state.targetServerPosition = snapshot.position
	state.targetServerYaw = snapshot.yaw
	state.targetServerVelocity = snapshot.velocity
	state.targetServerAngVelY = snapshot.angVelY
end

local function ApplyLocalSoftCorrection(state: ClientVehicleState, rootPart: BasePart, dt: number)
	local nowServer = workspaceService:GetServerTimeNow()
	local suppressUntil = state.suppressServerCorrectionUntilServerTime or 0
	if nowServer < suppressUntil then
		return
	end
	local serverPos = state.targetServerPosition
	if serverPos == nil then
		return
	end
	local currentVel = rootPart.AssemblyLinearVelocity
	local isHitSoftReconcile = nowServer < (state.hitSoftReconcileUntilServerTime or 0)
	local velocityConvergeRate = if isHitSoftReconcile
		then HIT_SOFT_RECONCILE_VELOCITY_CONVERGE_RATE
		else math.max(0, GameConfig.VehicleVelocityConvergeRate)
	-- 帧率无关的速度收敛：水平方向向服务端速度做指数插值，不动 Y 速度
	local blendedX, blendedZ = currentVel.X, currentVel.Z
	local targetVel = state.targetServerVelocity
	if targetVel ~= nil then
		local velAlpha = Clamp01(1 - math.exp(-math.max(0, dt) * velocityConvergeRate))
		blendedX = currentVel.X + (targetVel.X - currentVel.X) * velAlpha
		blendedZ = currentVel.Z + (targetVel.Z - currentVel.Z) * velAlpha
	end
	-- 位置误差以「虚拟弹簧」形式叠加到水平速度上，让物理积分自然把车带到服务端目标位置
	-- 不再每帧写 CFrame，避免与本地物理子步竞争造成「拉扯感 / 服务器端瞬移感」
	local posDelta = serverPos - rootPart.Position
	local correctionGain = math.max(0, GameConfig.VehiclePosCorrectionGain)
	local maxCorrectionSpeed = if isHitSoftReconcile
		then HIT_SOFT_RECONCILE_MAX_CORRECTION_SPEED
		else math.max(0, GameConfig.VehiclePosCorrectionMaxSpeed)
	local correctionX = math.clamp(posDelta.X * correctionGain, -maxCorrectionSpeed, maxCorrectionSpeed)
	local correctionZ = math.clamp(posDelta.Z * correctionGain, -maxCorrectionSpeed, maxCorrectionSpeed)
	rootPart.AssemblyLinearVelocity = Vector3.new(blendedX + correctionX, currentVel.Y, blendedZ + correctionZ)

	local targetYaw = state.targetServerYaw
	local yawErr = 0
	if targetYaw ~= nil then
		local yawAlpha = Clamp01(1 - math.exp(-math.max(0, dt) * velocityConvergeRate))
		local currentYaw = GetSnapshotYawFromCFrame(rootPart.CFrame)
		yawErr = math.abs(_NormalizeAngleRad(targetYaw - currentYaw))
		local smoothYaw = _LerpAngleRad(currentYaw, targetYaw, yawAlpha)
		rootPart.CFrame = BuildSnapshotYawCFrame(rootPart.Position, smoothYaw)
	end
	-- 收敛后清理（下一份快照来时会重新设置）
	if Vector3.new(posDelta.X, 0, posDelta.Z).Magnitude <= 0.15 and yawErr <= GameConfig.VehicleReconcileYawThreshold then
		state.targetServerPosition = nil
		state.targetServerYaw = nil
		state.targetServerVelocity = nil
		state.targetServerAngVelY = nil
	end
end

local function PushSnapshotToBuffer(state: ClientVehicleState, snapshot: GameConfig.VehicleStateSnapshot)
	table.insert(state.snapshotBuffer, snapshot)
	table.sort(state.snapshotBuffer, function(a, b)
		if a.serverTime == b.serverTime then
			return a.serverTick < b.serverTick
		end
		return a.serverTime < b.serverTime
	end)
	while #state.snapshotBuffer > 24 do
		table.remove(state.snapshotBuffer, 1)
	end
end

local function _ApplyRemoteSnapshotToVisual(state: ClientVehicleState)
	if not RefreshVehicleReference(state) then
		return
	end
	local rootPart = state.rootPart :: BasePart
	if #state.snapshotBuffer == 0 then
		return
	end
	local nowServer = workspaceService:GetServerTimeNow()
	local renderTarget = nowServer - (GameConfig.VehicleInterpolationBackTimeMs / 1000)
	local fromSnapshot = state.snapshotBuffer[1]
	local toSnapshot = state.snapshotBuffer[#state.snapshotBuffer]
	for i = 1, #state.snapshotBuffer - 1 do
		local left = state.snapshotBuffer[i]
		local right = state.snapshotBuffer[i + 1]
		local leftTime = left.serverTime
		local rightTime = right.serverTime
		if renderTarget >= leftTime and renderTarget <= rightTime then
			fromSnapshot = left
			toSnapshot = right
			break
		end
	end
	local fromTime = fromSnapshot.serverTime
	local toTime = toSnapshot.serverTime
	local alpha = 1
	if toTime > fromTime then
		alpha = Clamp01((renderTarget - fromTime) / (toTime - fromTime))
	end
	local pos = fromSnapshot.position:Lerp(toSnapshot.position, alpha)
	local yaw = _LerpAngleRad(fromSnapshot.yaw, toSnapshot.yaw, alpha)
	local expectedYawRate = GetExpectedYawRateRad(state)
	local snapshotDeltaTime = math.max(0, toTime - fromTime)
	local snapshotYawDelta = _NormalizeAngleRad(toSnapshot.yaw - fromSnapshot.yaw)
	local expectedDelta = expectedYawRate * snapshotDeltaTime
	-- 快照间角增量异常偏小时，使用理论自转速度补偿，避免远端“抽小角度”
	if snapshotDeltaTime > 1e-4 and math.abs(snapshotYawDelta) < math.abs(expectedDelta) * 0.2 then
		yaw = _NormalizeAngleRad(fromSnapshot.yaw + expectedYawRate * (renderTarget - fromTime))
	end
	local latestTime = state.snapshotBuffer[#state.snapshotBuffer].serverTime
	if renderTarget > latestTime then
		local extraTime = math.min(renderTarget - latestTime, GameConfig.VehicleExtrapolationMaxMs / 1000)
		pos = toSnapshot.position + toSnapshot.velocity * extraTime
		local yawRate = toSnapshot.angVelY
		-- 服务器角速度约束在部分机型上可能无法稳定反映到 AssemblyAngularVelocity，
		-- 此时回退到 spinDir 驱动的理论角速度，避免远端仅在快照到达时才跳变旋转角。
		if math.abs(yawRate) < math.abs(expectedYawRate) * 0.2 then
			yawRate = expectedYawRate
		end
		yaw = _NormalizeAngleRad(toSnapshot.yaw + yawRate * extraTime)
	end
	local smoothAlpha = Clamp01(0.35)
	local smoothPos = rootPart.Position:Lerp(pos, smoothAlpha)
	local currentYaw = math.atan2(rootPart.CFrame.LookVector.Z, rootPart.CFrame.LookVector.X)
	local smoothYaw = _LerpAngleRad(currentYaw, yaw, smoothAlpha)
	local horizontalVelocity = Vector3.new(toSnapshot.velocity.X, 0, toSnapshot.velocity.Z)
	if not (smoothYaw == smoothYaw) then
		if horizontalVelocity.Magnitude > 0.01 then
			smoothYaw = math.atan2(horizontalVelocity.Z, horizontalVelocity.X)
		else
			smoothYaw = math.atan2(rootPart.CFrame.LookVector.Z, rootPart.CFrame.LookVector.X)
		end
	end
	rootPart.CFrame = _BuildYawCFrame(smoothPos, smoothYaw)
end

local function StepVehicleVisuals(dt: number)
	if not IsVehicleVisualActiveState(matchState) then
		return
	end

	for _, state in vehicleStateMap do
		if not state.isParticipant then
			continue
		end
		if not RefreshVehicleReference(state) then
			continue
		end

		local rootPart = state.rootPart :: BasePart
		if state.isLocalControlled then
			local speed = GetVehicleSpeed(state.vehicleId)
			local drive = state.driveVectorForce
			if drive == nil then
				drive = VehicleLocomotionTool.EnsureVehicleDriveConstraints(rootPart)
				state.driveVectorForce = drive
			end
			local applyDrive = matchState == GameConfig.MatchState.Fighting
			VehicleLocomotionTool.UpdateBaseDiskLocomotion(state, rootPart, drive :: VectorForce, dt, applyDrive, speed)
			local spinAV = rootPart:FindFirstChild("SpinAngularVelocity")
			if spinAV ~= nil and spinAV:IsA("AngularVelocity") then
				UpdateLocalSpinAngularVelocityIfChanged(state, spinAV :: AngularVelocity)
			end
			state.lastInputSendAccumulator += dt
			local sendInterval = 1 / math.max(1, GameConfig.VehicleInputSendHz)
			while state.lastInputSendAccumulator >= sendInterval do
				state.lastInputSendAccumulator -= sendInterval
				local moveDir = NormalizeHorizontalDirection(Vector3.new(state.targetVelX, 0, state.targetVelZ))
				local cmd: GameConfig.VehicleInputCmd = {
					seq = state.nextInputSeq,
					clientTime = workspaceService:GetServerTimeNow(),
					moveDir = moveDir,
					spinDir = state.spinDir,
				}
				state.nextInputSeq += 1
				PushInputCmd(state, cmd)
			end
			ApplyLocalSoftCorrection(state, rootPart, dt)
		else
			local spinAV = rootPart:FindFirstChild("SpinAngularVelocity")
			if spinAV ~= nil and spinAV:IsA("AngularVelocity") then
				-- 远端视觉由服务器物理代理跟随驱动，避免本地约束和外部同步双写
				spinAV.AngularVelocity = Vector3.zero
			end
			ApplyRemoteProxyFollow(state, rootPart, dt)
		end
	end
end

function VehicleClientManager.OnUnitInit(unitInitInfo: GameConfig.UnitInitInfo)
	local playerId = unitInitInfo.playerId
	local state = EnsureState(playerId)
	local targetVelX, targetVelZ = VehicleLocomotionTool.AngleToVelocityXZ(unitInitInfo.moveAngle, GetVehicleSpeed(unitInitInfo.vehicleId))
	local forceDirection = NormalizeHorizontalDirection(Vector3.new(targetVelX, 0, targetVelZ))
	local model, rootPart = FindVehicleModel(playerId)
	state.vehicleId = unitInitInfo.vehicleId
	state.model = model
	state.rootPart = rootPart
	state.spinDir = unitInitInfo.spinDir
	state.forceDirection = forceDirection
	state.targetVelX = targetVelX
	state.targetVelZ = targetVelZ
	state.spinAngleRad = math.atan2(targetVelZ, targetVelX)
	state.targetServerPosition = nil
	state.targetServerYaw = nil
	state.targetServerVelocity = nil
	state.targetServerAngVelY = nil
	state.hitSoftReconcileUntilServerTime = 0
	state.lastServerTime = 0
	state.lastServerTick = 0
	state.isParticipant = IsParticipantFromPayload(unitInitInfo.isParticipant)
	state.isLocalControlled = playerId == localPlayerId
	state.nextInputSeq = 1
	state.lastAckInputSeq = 0
	state.lastInputSendAccumulator = 0
	table.clear(state.pendingInputList)
	table.clear(state.snapshotBuffer)
	if rootPart ~= nil and rootPart.Parent ~= nil then
		local rootPos = rootPart.Position
		state.targetServerPosition = rootPos
	end
end

function VehicleClientManager.OnUnitRemove(playerId: number)
	vehicleStateMap[playerId] = nil
end

function VehicleClientManager.OnVehicleDirectionChanged(
	playerId: number,
	_reason: GameConfig.DirectionChangeReason,
	serverPosition: Vector3,
	forceDirection: Vector3,
	serverTime: number
)
	local state = EnsureState(playerId)
	-- 快照同步已接管后，方向事件仅作为早期兜底，避免 Fire/BulletHit 后重复改向导致左右抖摆
	if state.lastServerTick > 0 then
		return
	end
	if serverTime < state.lastServerTime then
		return
	end

	RefreshVehicleReference(state)
	ApplyDirectionToState(state, forceDirection)
	state.targetServerPosition = serverPosition
	state.targetServerYaw = nil
	state.targetServerVelocity = nil
	state.targetServerAngVelY = nil
	state.lastServerTime = serverTime
end

function VehicleClientManager.OnDirectionFlip(playerId: number)
	local state = EnsureState(playerId)
	if state.isLocalControlled then
		TryUpdateSpinDirFromSnapshot(state, -state.spinDir)
	else
		state.spinDir = -state.spinDir
	end
end

function VehicleClientManager.OnTeleport(playerId: number, targetPosition: Vector3)
	local state = EnsureState(playerId)
	state.targetServerPosition = targetPosition
	state.targetServerYaw = nil
	state.targetServerVelocity = nil
	state.targetServerAngVelY = nil
end

function VehicleClientManager.OnVehicleStateSnapshot(snapshot: GameConfig.VehicleStateSnapshot)
	local isActiveState = IsVehicleVisualActiveState(matchState)
	local state = vehicleStateMap[snapshot.playerId]
	if state == nil then
		if not isActiveState then
			return
		end
		state = EnsureState(snapshot.playerId)
	end
	state.lastServerTime = workspaceService:GetServerTimeNow()
	state.vehicleId = snapshot.vehicleId
	if not isActiveState then
		StopVehicleVisualMotion(state)
		return
	end
	if state.isLocalControlled then
		TryUpdateSpinDirFromSnapshot(state, snapshot.spinDir)
		ReconcileLocalStateFromSnapshot(state, snapshot)
	else
		state.spinDir = snapshot.spinDir
		if GameConfig.EnableRemoteVisualSmoothing then
			PushSnapshotToBuffer(state, snapshot)
		end
	end
end

function VehicleClientManager.OnMatchStateChanged(newState: GameConfig.MatchState, _countdown: number)
	matchState = newState
	if not IsVehicleVisualActiveState(newState) then
		StopAllVehicleVisualMotion()
	end
	if newState == GameConfig.MatchState.InLobby then
		table.clear(vehicleStateMap)
	end
end

function VehicleClientManager.Init()
	if isInitialized then
		return
	end
	isInitialized = true
	localPlayerId = players.LocalPlayer.UserId

	NetMsg.ConnectNotifyUnitInit(VehicleClientManager.OnUnitInit)
	NetMsg.ConnectNotifyUnitRemove(VehicleClientManager.OnUnitRemove)
	NetMsg.ConnectNotifyVehicleDirectionChanged(VehicleClientManager.OnVehicleDirectionChanged)
	NetMsg.ConnectNotifyVehicleStateSnapshot(VehicleClientManager.OnVehicleStateSnapshot)
	NetMsg.ConnectNotifyTeleport(VehicleClientManager.OnTeleport)
	NetMsg.ConnectNotifyMatchState(VehicleClientManager.OnMatchStateChanged)

	runService.RenderStepped:Connect(StepVehicleVisuals)
end

function VehicleClientManager.GetVehicleVisualPositionAtServerTime(playerId: number, _serverTime: number): Vector3?
	local state = vehicleStateMap[playerId]
	if state == nil then
		return nil
	end
	if not RefreshVehicleReference(state) then
		return nil
	end
	local rootPart = state.rootPart
	if rootPart ~= nil and rootPart.Parent ~= nil then
		return rootPart.Position
	end
	local proxyRoot = state.proxyRootPart
	if proxyRoot ~= nil and proxyRoot.Parent ~= nil then
		return proxyRoot.Position
	end
	return nil
end

function VehicleClientManager.SetLocalHitCorrectionSuppression(untilServerTime: number)
	local state = vehicleStateMap[localPlayerId]
	if state == nil then
		return
	end
	state.suppressServerCorrectionUntilServerTime = math.max(state.suppressServerCorrectionUntilServerTime or 0, untilServerTime)
	state.hitSoftReconcileUntilServerTime =
		math.max(state.hitSoftReconcileUntilServerTime or 0, untilServerTime + HIT_SOFT_RECONCILE_DURATION_SEC)
end

return VehicleClientManager
