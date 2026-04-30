--!strict
local BulletClientManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local workspaceService = game:GetService("Workspace")
local runService = game:GetService("RunService")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local SoundTool = require(coreSharedScripts:FindFirstChild("SoundTool"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))

type ClientUnitState = {
	playerId: number,
	vehicleId: number,
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
	isParticipant: boolean,
	recoilJoint: Weld | Motor6D?,
	recoilPropName: "C0" | "C1"?,
}

local VEHICLE_MODEL_NAME_PREFIX = "Vehicle_"
local SERVER_BULLETS_FOLDER_NAME = "ServerBullets"
local SERVER_PROJECTILE_NAME_PREFIX = "ServerProjectile_"
local SHOOTER_USER_ID_ATTRIBUTE = "ShooterUserId"
local TEMPLATE_NAME_ATTRIBUTE = "TemplateName"
local PROJECTILE_MODEL_TEMPLATE_NAME = "ProjectileModel"
local LOCAL_OWNED_PROJECTILE_COLOR = Color3.new(0, 1, 0)
local ENEMY_PROJECTILE_COLOR = Color3.new(1, 0.2, 0.2)
local LOCAL_OWNED_PROJECTILE_BRICK_COLOR = BrickColor.new("Lime green")
local ENEMY_PROJECTILE_BRICK_COLOR = BrickColor.new("Bright red")
local CLIENT_BULLET_PREWARM_FOLDER_NAME = "ClientBulletPrewarm"
-- 远离赛场的世界坐标，避免预热模型出现在擂台/相机附近
local PREWARM_WORLD_POSITION = Vector3.new(200, -600, -200)
local PREWARM_OFFSET_STEP = Vector3.new(300, -100, -8)

-- Recoil Animation Constants
local RECOIL_OFFSET_STUDS = 1.4 -- 枪管后退的距离 (Studs)
local RECOIL_IN_DURATION_SEC = 0.22 -- 枪管向后收缩的瞬间耗时 (秒)
local RECOIL_OUT_DURATION_SEC = 0.05 -- 枪管向前平滑回弹的耗时 (秒)
local RECOIL_MUZZLE_MAGNITUDE_THRESHOLD = 0.01 -- 枪口位置向量判定阈值，防止极小值导致的除零错误
-- local UNIT_SPEED: number = GameConfig.UnitSpeed
-- local UNIT_MAX_HORIZONTAL_SPEED: number = GameConfig.UnitMaxHorizontalSpeed
-- local FIRE_COOLDOWN: number = GameConfig.FireCooldown
-- local SPIN_DAMPING_DURATION: number = GameConfig.SpinDampingDuration
-- local DRIVE_HORIZONTAL_FORCE_GAIN: number = 14
-- local WALL_BOUNCE_COOLDOWN_SEC: number = 0.22
-- local WALL_BOUNCE_VEL_INTO_WALL: number = -0.35
-- local WALL_STUCK_SPEED_MAX: number = 10
-- local WALL_STUCK_DESIRED_DOT: number = -0.02

local matchState: GameConfig.MatchState = GameConfig.MatchState.InLobby

local localPlayerId: number = 0
local unitStateMap: { [number]: ClientUnitState } = {}
local pendingUnitInits: { [number]: GameConfig.UnitInitInfo } = {}
local unitInitRetryCountMap: { [number]: number } = {}
local lastFireTime: number = -math.huge
local isInitialized: boolean = false
local _hasWarnedMissingTurretActuator: boolean = false
local isLocalAfk: boolean = false
local prewarmedBulletResourceNameMap: { [string]: boolean } = {}

local HttpService = game:GetService("HttpService")
local soundOriginsFolder = replicatedStorage:FindFirstChild("Sounds")
local fireSoundOrigin = if soundOriginsFolder then soundOriginsFolder:FindFirstChild("FireSound") else nil
local hitSoundOrigin = if soundOriginsFolder then soundOriginsFolder:FindFirstChild("HitSound") else nil
local struckSoundOrigin = if soundOriginsFolder then soundOriginsFolder:FindFirstChild("StruckSound") else nil
local impactSoundOrigin = if soundOriginsFolder then soundOriginsFolder:FindFirstChild("ImpactSound") else nil
local deathSoundOrigin = if soundOriginsFolder then soundOriginsFolder:FindFirstChild("DeathSound") else nil
local unitFireSoundCache: { [Model]: Instance } = {}
local unitMissingFireSoundCache: { [Model]: boolean } = {}

local function PlayLocalCombatSound(soundOrigin: Instance?, worldPosition: Vector3)
	if soundOrigin == nil or not soundOrigin:IsA("Sound") then
		return
	end
	SoundTool.PlayLocalSoundEffect(soundOrigin, worldPosition, false)
end

local function PlayGlobalCombatSound(soundOrigin: Instance?)
	if soundOrigin == nil or not soundOrigin:IsA("Sound") then
		return
	end
	SoundTool.PlayGlobalSoundEffect(soundOrigin, false)
end

local function ClearCachedFireSoundForModel(unitModel: Model?)
	if unitModel == nil then
		return
	end
	unitFireSoundCache[unitModel] = nil
	unitMissingFireSoundCache[unitModel] = nil
end

local function ResolveFireSound(unitModel: Model?): Instance?
	if unitModel == nil then
		return fireSoundOrigin
	end

	local cachedFireSound = unitFireSoundCache[unitModel]
	if cachedFireSound ~= nil then
		return cachedFireSound
	end
	if unitMissingFireSoundCache[unitModel] then
		return fireSoundOrigin
	end

	local modelFireSound = unitModel:FindFirstChild("FireSound", true)
	if modelFireSound ~= nil then
		if modelFireSound:IsA("Sound") then
			unitFireSoundCache[unitModel] = modelFireSound
			return modelFireSound
		end
	end

	unitMissingFireSoundCache[unitModel] = true
	return fireSoundOrigin
end

local function GetModelsFolder(): Folder
	return replicatedStorage:WaitForChild("Models") :: Folder
end

local function GetBulletModelsFolder(): Folder?
	local modelsFolder = GetModelsFolder()
	local bulletFolder = modelsFolder:FindFirstChild("Bullet")
	if bulletFolder ~= nil and bulletFolder:IsA("Folder") then
		return bulletFolder
	end
	return nil
end

local function EnsureClientBulletPrewarmFolder(): Folder
	local existing = workspaceService:FindFirstChild(CLIENT_BULLET_PREWARM_FOLDER_NAME)
	if existing ~= nil and not existing:IsA("Folder") then
		existing:Destroy()
		existing = nil
	end
	if existing ~= nil and existing:IsA("Folder") then
		return existing :: Folder
	end
	local created = Instance.new("Folder")
	created.Name = CLIENT_BULLET_PREWARM_FOLDER_NAME
	created:SetAttribute("PrewarmedByClient", true)
	created.Parent = workspaceService
	return created
end

local function ClearClientBulletPrewarmFolder()
	if not runService:IsClient() then
		return
	end
	local folder = workspaceService:FindFirstChild(CLIENT_BULLET_PREWARM_FOLDER_NAME)
	if folder ~= nil and folder:IsA("Folder") then
		folder:Destroy()
	end
end

local function SetPrewarmModelHighlightEnabled(model: Model, enabled: boolean)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Highlight") then
			descendant.Enabled = enabled
		end
	end
end

local function ConfigurePrewarmClonedModelPhysics(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.Anchored = true
		end
	end
end

local function GetPrewarmWorldPositionForIndex(index: number): Vector3
	return PREWARM_WORLD_POSITION + PREWARM_OFFSET_STEP * index
end

-- StartRound 在「备战倒计时结束」与「开局倒计时广播」之间发 UnitInit，此时客户端仍为 MatchCountdown，必须仍允许预热
local function ShouldRunClientBulletPrewarm(): boolean
	if matchState == GameConfig.MatchState.InLobby or matchState == GameConfig.MatchState.Settlement then
		return false
	end
	return true
end

local function IsParticipantFromPayload(value: unknown): boolean
	if value == true or value == 1 then
		return true
	end
	if typeof(value) == "string" then
		local s = string.lower(value :: string)
		return s == "true" or s == "1"
	end
	return false
end

local function GetBulletResourceNameFromVehicleId(vehicleId: number): string
	local vehicleData = GameConfig.VehicleDataMap[vehicleId]
	local bulletData = if vehicleData then vehicleData.bulletData else nil
	local resourceName = if bulletData then bulletData.resourceName else nil
	if typeof(resourceName) == "string" and resourceName ~= "" then
		return resourceName
	end
	return PROJECTILE_MODEL_TEMPLATE_NAME
end

-- RemoteEvent 反序列化可能把 vehicleId 变成 string；缺字段时按 unknown 规范化
local function CoerceVehicleIdFromPayload(raw: unknown): number?
	if raw == nil then
		return nil
	end
	if typeof(raw) == "number" then
		if raw ~= raw then
			return nil
		end
		return raw
	end
	if typeof(raw) == "string" then
		return tonumber(raw)
	end
	return nil
end

local function GetMatchVehicleIdForPlayer(playerId: number): number?
	local pendingInfo = pendingUnitInits[playerId]
	if pendingInfo ~= nil then
		local id = CoerceVehicleIdFromPayload(pendingInfo.vehicleId)
		if id ~= nil then
			return id
		end
	end

	local state = unitStateMap[playerId]
	if state ~= nil then
		local id = CoerceVehicleIdFromPayload(state.vehicleId)
		if id ~= nil then
			return id
		end
	end

	return nil
end

local function GetMatchBulletResourceNameForParticipantPlayer(playerId: number): string
	local vehicleId = GetMatchVehicleIdForPlayer(playerId)
	if vehicleId == nil then
		return PROJECTILE_MODEL_TEMPLATE_NAME
	end
	return GetBulletResourceNameFromVehicleId(vehicleId)
end

local function CollectParticipantIdList(): { number }
	local participantIdMap: { [number]: boolean } = {}

	for playerId, unitInitInfo in pendingUnitInits do
		if IsParticipantFromPayload(unitInitInfo.isParticipant) then
			participantIdMap[playerId] = true
		end
	end

	for playerId, state in unitStateMap do
		if state.isParticipant then
			participantIdMap[playerId] = true
		end
	end

	local participantIdList: { number } = {}
	for playerId in participantIdMap do
		table.insert(participantIdList, playerId)
	end
	return participantIdList
end

local function CollectPrewarmBulletResourceNameList(): { string }
	local resourceNameMap: { [string]: boolean } = {}
	local participantIdList = CollectParticipantIdList()

	for _, playerId in participantIdList do
		local resourceName = GetMatchBulletResourceNameForParticipantPlayer(playerId)
		if resourceName ~= "" and prewarmedBulletResourceNameMap[resourceName] ~= true then
			resourceNameMap[resourceName] = true
		end
	end

	local resourceNameList: { string } = {}
	for resourceName in resourceNameMap do
		table.insert(resourceNameList, resourceName)
	end
	return resourceNameList
end

local function PrewarmBulletVisualsForCurrentParticipants()
	if not runService:IsClient() then
		return
	end
	local resourceNameList = CollectPrewarmBulletResourceNameList()
	if #resourceNameList <= 0 then
		return
	end
	local bulletFolder = GetBulletModelsFolder()
	if bulletFolder == nil then
		return
	end

	local prewarmFolder = EnsureClientBulletPrewarmFolder()

	for i, resourceName in ipairs(resourceNameList) do
		local template = bulletFolder:FindFirstChild(resourceName)
		if template == nil or not template:IsA("Model") then
			continue
		end
		local cloned = template:Clone()
		cloned.Name = "Prewarm_" .. resourceName
		SetPrewarmModelHighlightEnabled(cloned, false)
		ConfigurePrewarmClonedModelPhysics(cloned)
		cloned.Parent = prewarmFolder
		local targetCf = CFrame.new(GetPrewarmWorldPositionForIndex(i - 1))
		pcall(function()
			cloned:PivotTo(targetCf)
		end)
		task.defer(function()
			if cloned.Parent ~= nil then
				pcall(function()
					cloned:PivotTo(targetCf)
				end)
			end
		end)
		prewarmedBulletResourceNameMap[resourceName] = true
	end
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

local function TintServerProjectile(projectileModel: Model)
	if not IsServerProjectileModelName(projectileModel.Name) then
		return
	end
	local function tryTint()
		local shooterId = projectileModel:GetAttribute(SHOOTER_USER_ID_ATTRIBUTE)
		if typeof(shooterId) ~= "number" then
			return
		end

		local isLocal = (shooterId == localPlayerId)
		local tintColor = if isLocal then LOCAL_OWNED_PROJECTILE_COLOR else ENEMY_PROJECTILE_COLOR
		local brickColor = if isLocal then LOCAL_OWNED_PROJECTILE_BRICK_COLOR else ENEMY_PROJECTILE_BRICK_COLOR
		-- 规范：子弹模型的 Highlight 必须挂在模型根节点
		local rootHighlight = projectileModel:FindFirstChildWhichIsA("Highlight")
		if rootHighlight ~= nil then
			rootHighlight.OutlineColor = tintColor
		end
		local templateName = projectileModel:GetAttribute(TEMPLATE_NAME_ATTRIBUTE)
		if templateName ~= PROJECTILE_MODEL_TEMPLATE_NAME then
			return
		end
		local projectileCore = projectileModel:FindFirstChild("Core")
		if projectileCore ~= nil and projectileCore:IsA("BasePart") then
			projectileCore.BrickColor = brickColor
		end
	end
	tryTint()
	projectileModel:GetAttributeChangedSignal(SHOOTER_USER_ID_ATTRIBUTE):Connect(tryTint)
end

local function BindServerProjectileLocalTintFolder(folder: Folder)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			TintServerProjectile(child)
		end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			TintServerProjectile(child)
		end
	end)
end

local function IsFightingDriveActive(): boolean
	return matchState == GameConfig.MatchState.Fighting
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
	NetMsg.ConnectNotifyImpact(BulletClientManager.OnImpact)
	NetMsg.ConnectNotifyTeleport(BulletClientManager.OnTeleport)
	NetMsg.ConnectNotifyMatchState(BulletClientManager.OnMatchStateChanged)
	NetMsg.ConnectNotifyAfkState(BulletClientManager.OnNotifyAfkState)
end

function BulletClientManager.OnUnitInit(unitInitInfo: GameConfig.UnitInitInfo)
	local playerId: number = unitInitInfo.playerId
	local isLocal: boolean = (playerId == localPlayerId)

	pendingUnitInits[playerId] = unitInitInfo

	if ShouldRunClientBulletPrewarm() then
		PrewarmBulletVisualsForCurrentParticipants()
	end

	-- Update existing state immediately to avoid UI delays if this is a state update (e.g. StartRound)
	local existingState = unitStateMap[playerId]
	if existingState ~= nil then
		existingState.isParticipant = IsParticipantFromPayload(unitInitInfo.isParticipant)
		if existingState.model ~= nil then
			ClearCachedFireSoundForModel(existingState.model)
		end
	end

	local unitPart: BasePart? = FindUnitPart(playerId)

	local currentInfo = pendingUnitInits[playerId]
	if currentInfo == nil then
		-- Unit might have been removed while we were yielding in FindUnitPart, abort
		return
	end

	if unitPart == nil then
		-- Vehicle might not be streamed in yet (e.g. at UNDERGROUND_Y while player is in Lobby)
		-- We retry indefinitely until it's found or the unit is removed.
		task.delay(0.5, function()
			if pendingUnitInits[playerId] ~= nil then
				BulletClientManager.OnUnitInit(currentInfo)
			end
		end)
		return
	end

	pendingUnitInits[playerId] = nil
	unitInitRetryCountMap[playerId] = nil

	local model = unitPart.Parent
	local unitModel: Model? = nil
	if model ~= nil and model:IsA("Model") then
		unitModel = model
	end
	local turretPart: BasePart? = nil
	if unitModel ~= nil then
		local turretGroup = unitModel:FindFirstChild("TurretBarrel")
		if turretGroup ~= nil then
			if turretGroup:IsA("BasePart") then
				turretPart = turretGroup
			else
				local muzzle = turretGroup:FindFirstChild("MuzzleAttachment", true)
				if muzzle and muzzle.Parent and muzzle.Parent:IsA("BasePart") then
					turretPart = muzzle.Parent
				else
					for _, child in turretGroup:GetChildren() do
						if child:IsA("BasePart") then
							turretPart = child
							break
						end
					end
				end
			end
		end
	end

	local targetVelX: number, targetVelZ: number = AngleToVelocityXZ(currentInfo.moveAngle)
	local initHullYaw = math.atan2(targetVelZ, targetVelX)

	local state: ClientUnitState = {
		playerId = playerId,
		vehicleId = currentInfo.vehicleId,
		targetVelX = targetVelX,
		targetVelZ = targetVelZ,
		spinDir = currentInfo.spinDir,
		unitPart = unitPart,
		turretPart = turretPart,
		model = unitModel,
		isLocal = isLocal,
		maxHits = currentInfo.maxHits,
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
		recoilJoint = nil,
		recoilPropName = nil,
		isParticipant = IsParticipantFromPayload(currentInfo.isParticipant),
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
	if state ~= nil then
		ClearCachedFireSoundForModel(state.model)
	end
	pendingUnitInits[playerId] = nil
	unitStateMap[playerId] = nil
end
local TweenService = game:GetService("TweenService")

local function ResolveRecoilJoint(state: ClientUnitState): ((Weld | Motor6D)?, ("C0" | "C1")?)
	if state.turretPart == nil or state.model == nil then
		return nil, nil
	end

	local turretPart = state.turretPart
	local model = state.model
	local namedWeld = model:FindFirstChild("Weld_SeatToTurret", true)
	local weld: (Weld | Motor6D)? = nil

	if namedWeld ~= nil and namedWeld:IsA("Weld") then
		weld = namedWeld
	elseif namedWeld ~= nil and namedWeld:IsA("Motor6D") then
		weld = namedWeld
	end
	if weld ~= nil then
		if weld.Part0 and weld.Part0.Name ~= "Seat" then
			state.turretPart = weld.Part0
		elseif weld.Part1 and weld.Part1.Name ~= "Seat" then
			state.turretPart = weld.Part1
		end
		turretPart = state.turretPart or turretPart
	else
		local directWeld = turretPart:FindFirstChildWhichIsA("Weld")
		if directWeld ~= nil then
			weld = directWeld
		else
			local directMotor = turretPart:FindFirstChildWhichIsA("Motor6D")
			if directMotor ~= nil then
				weld = directMotor
			end
		end
		if weld == nil then
			for _, d in model:GetDescendants() do
				if (d:IsA("Weld") or d:IsA("Motor6D")) and (d.Part0 == turretPart or d.Part1 == turretPart) then
					weld = d
					break
				end
			end
		end
	end

	-- Support WeldConstraint by dynamically converting it to a standard Weld
	if not weld then
		local weldConstraint = turretPart:FindFirstChildWhichIsA("WeldConstraint")
		if not weldConstraint then
			for _, d in model:GetDescendants() do
				if d:IsA("WeldConstraint") and (d.Part0 == turretPart or d.Part1 == turretPart) then
					weldConstraint = d
					break
				end
			end
		end

		if weldConstraint and weldConstraint.Part0 and weldConstraint.Part1 then
			local newWeld = Instance.new("Weld")
			newWeld.Name = "ConvertedRecoilWeld"
			newWeld.Part0 = weldConstraint.Part0
			newWeld.Part1 = weldConstraint.Part1
			newWeld.C0 = CFrame.new()
			newWeld.C1 = weldConstraint.Part1.CFrame:ToObjectSpace(weldConstraint.Part0.CFrame)
			newWeld.Parent = weldConstraint.Parent

			weldConstraint.Enabled = false
			weldConstraint:Destroy()

			weld = newWeld
		end
	end

	if not weld then
		return nil, nil
	end
	local resolvedWeld: Weld | Motor6D = weld

	local propName: "C0" | "C1"
	if resolvedWeld.Part0 == state.turretPart then
		propName = "C0"
	else
		propName = "C1"
	end
	return resolvedWeld, propName
end

function BulletClientManager.PlayRecoilAnimation(state: ClientUnitState)
	if not state.turretPart or not state.model then
		return
	end

	if state.recoilJoint == nil or state.recoilJoint.Parent == nil or state.recoilPropName == nil then
		local resolvedWeld, resolvedPropName = ResolveRecoilJoint(state)
		state.recoilJoint = resolvedWeld
		state.recoilPropName = resolvedPropName :: ("C0" | "C1")?
	end
	local weld = state.recoilJoint
	local propName = state.recoilPropName

	if weld == nil or propName == nil then
		return
	end

	local attrName = "Original" .. propName
	if not weld:GetAttribute(attrName) then
		local currentJointCFrame = if propName == "C0" then weld.C0 else weld.C1
		weld:SetAttribute(attrName, currentJointCFrame)
	end

	local originalCFrame = weld:GetAttribute(attrName) :: CFrame
	
	local recoilOffset = CFrame.new(0, 0, RECOIL_OFFSET_STUDS)
	local muzzle = nil
	if state.model then
		local turretGroup = state.model:FindFirstChild("TurretBarrel")
		if turretGroup then
			muzzle = turretGroup:FindFirstChild("MuzzleAttachment", true)
		end
	end
	if not muzzle then
		muzzle = state.turretPart:FindFirstChild("MuzzleAttachment", true)
	end
	
	if muzzle and muzzle:IsA("Attachment") then
		local worldBackward = -muzzle.WorldCFrame.LookVector
		local localBackward = state.turretPart.CFrame:VectorToObjectSpace(worldBackward)
		if localBackward.Magnitude > RECOIL_MUZZLE_MAGNITUDE_THRESHOLD then
			recoilOffset = CFrame.new(localBackward.Unit * RECOIL_OFFSET_STUDS)
		end
	end

	local targetCFrame = recoilOffset:Inverse() * originalCFrame

	local recoilId = ((weld:GetAttribute("RecoilId") :: number?) or 0) + 1
	weld:SetAttribute("RecoilId", recoilId)

	local tweenInfoIn = TweenInfo.new(RECOIL_IN_DURATION_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenIn = TweenService:Create(weld, tweenInfoIn, { [propName] = targetCFrame })
	tweenIn:Play()

	tweenIn.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed and weld:GetAttribute("RecoilId") == recoilId then
			local tweenInfoOut = TweenInfo.new(RECOIL_OUT_DURATION_SEC, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			local tweenOut = TweenService:Create(weld, tweenInfoOut, { [propName] = originalCFrame })
			tweenOut:Play()
		end
	end)
end

function BulletClientManager.OnFireAccepted(playerId: number, _fireTime: number, _spawnPos: Vector3, _shotDir: Vector3, _serverTime: number, _bulletId: string)
	local state = unitStateMap[playerId]
	if state ~= nil then
		local resolvedFireSound = ResolveFireSound(state.model)
		PlayLocalCombatSound(resolvedFireSound, state.unitPart.Position)
	end

	if playerId == localPlayerId then
		return
	end

	if state ~= nil then
		state.spinDir = -state.spinDir
		state.spinDampingUntil = os.clock() + GameConfig.SpinDampingDuration
		state.spinImpulseRadPerSec += GameConfig.TurretSpinImpulseOnFireRadPerSec * state.spinDir
		BulletClientManager.PlayRecoilAnimation(state)
	end
end

function BulletClientManager.OnHit(
	targetPlayerId: number,
	_fromPlayerId: number,
	_hitDirection: Vector3,
	_hitCount: number,
	_bulletId: string,
	hitPosition: Vector3
)
	local targetState = unitStateMap[targetPlayerId]
	if targetState == nil then
		return
	end
	PlayGlobalCombatSound(hitSoundOrigin)
	if targetPlayerId == localPlayerId then
		PlayGlobalCombatSound(struckSoundOrigin)
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
	if playerId == localPlayerId then
		PlayGlobalCombatSound(deathSoundOrigin)
	end
end

function BulletClientManager.OnImpact(hitPosition: Vector3)
	PlayLocalCombatSound(impactSoundOrigin, hitPosition)
end

function BulletClientManager.OnTeleport(_playerId: number, _targetPosition: Vector3) end

function BulletClientManager.OnMatchStateChanged(newState: GameConfig.MatchState, _countdown: number)
	matchState = newState
	if
		newState == GameConfig.MatchState.MatchCountdown
		or newState == GameConfig.MatchState.GameStartCountdown
		or newState == GameConfig.MatchState.Fighting
	then
		PrewarmBulletVisualsForCurrentParticipants()
	end
	if newState == GameConfig.MatchState.InLobby then
		ClearClientBulletPrewarmFolder()
		table.clear(unitStateMap)
		table.clear(pendingUnitInits)
		table.clear(unitFireSoundCache)
		table.clear(unitMissingFireSoundCache)
	end
end

function BulletClientManager.OnNotifyAfkState(playerId: number, isAfk: boolean)
	if playerId == localPlayerId then
		isLocalAfk = isAfk
	end
end

local function GetLocalConfiguredFireCooldown(): number
	local cooldown = GameConfig.FireCooldown
	local localInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localInfo then
		local vehicleData = GameConfig.VehicleDataMap[tonumber(localInfo.vehicleInventory.currentId) or 1]
		if vehicleData then
			cooldown = vehicleData.fireCooldown
		end
	end
	return cooldown
end

function BulletClientManager.FireShot()
	if not IsFightingDriveActive() then
		return
	end

	local cooldown = GetLocalConfiguredFireCooldown()

	local now: number = tick()
	if now - lastFireTime < cooldown then
		return
	end
	lastFireTime = now

	local localState: ClientUnitState? = unitStateMap[localPlayerId]
	if localState ~= nil then
		-- spinDir 由服务端 NotifyDirectionFlip 统一翻转，避免与 FireShot 本地预测双翻
		localState.spinDampingUntil = os.clock() + GameConfig.SpinDampingDuration
		localState.spinImpulseRadPerSec += GameConfig.TurretSpinImpulseOnFireRadPerSec * localState.spinDir
		BulletClientManager.PlayRecoilAnimation(localState)
	end

	local bulletId = HttpService:GenerateGUID(false)
	NetMsg.FireRequestFire(workspaceService:GetServerTimeNow(), bulletId)
end

function BulletClientManager.GetLocalHpInfo(): (number, number)
	local localState = unitStateMap[localPlayerId]
	if localState == nil then
		return 0, GameConfig.MaxHits
	end
	return localState.hitCount, localState.maxHits
end

function BulletClientManager.GetLocalFireCooldownLeft(): number
	local cooldown = GetLocalConfiguredFireCooldown()

	local cooldownLeft = cooldown - (tick() - lastFireTime)
	if cooldownLeft < 0 then
		return 0
	end
	return cooldownLeft
end

function BulletClientManager.GetLocalFireCooldownSeconds(): number
	return GetLocalConfiguredFireCooldown()
end

function BulletClientManager.GetMatchState(): GameConfig.MatchState
	return matchState
end

function BulletClientManager.IsLocalInVehicle(): boolean
	local state = unitStateMap[localPlayerId]
	if state == nil then
		return false
	end
	return state.hitCount < state.maxHits and state.isParticipant and not isLocalAfk
end

function BulletClientManager.IsLocalAfk(): boolean
	return isLocalAfk
end

return BulletClientManager
