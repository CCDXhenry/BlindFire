--!strict
local BotLobbyRoamManager = {}

local runService: RunService = game:GetService("RunService")

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage: ServerStorage = game:GetService("ServerStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))

local serverScripts = serverStorage:WaitForChild("Scripts")
local CombatManager = require(serverScripts:WaitForChild("CombatManager"))

type RoamPhase = "Idle" | "Walking"

type RoamInfo = {
	phase: RoamPhase,
	phaseEndClock: number,
	walkStartClock: number,
	walkGoal: Vector3,
	walkAnimationTrack: AnimationTrack?,
}

local PhaseIdle: RoamPhase = "Idle"
local PhaseWalking: RoamPhase = "Walking"

local roamInfoMap: { [number]: RoamInfo } = {}
local isInitialized: boolean = false
local heartbeatConnection: RBXScriptConnection? = nil
local tickAccumulatorSec: number = 0

local function RandomIdleDuration(): number
	local minSec = math.max(0, GameConfig.BotLobbyRoamIdleMinSec or 0)
	local maxSec = math.max(minSec, GameConfig.BotLobbyRoamIdleMaxSec or minSec)
	return minSec + (maxSec - minSec) * math.random()
end

local function HorizontalDistanceXZ(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function SamplePointInLobbyArea(currentPos: Vector3): Vector3?
	local areaName = GameConfig.BotLobbyRoamLobbyAreaName or "LobbySpawnArea"
	local areaInst = workspace:FindFirstChild(areaName)
	if areaInst == nil or not areaInst:IsA("BasePart") then
		return nil
	end
	local area = areaInst :: BasePart
	local padding = math.max(0, GameConfig.BotLobbyRoamSamplePadding or 0)
	local halfX = area.Size.X * 0.5 - padding
	local halfZ = area.Size.Z * 0.5 - padding
	if halfX <= 0.05 or halfZ <= 0.05 then
		return nil
	end
	local minSep = math.max(0, GameConfig.BotLobbyRoamMinSampleSeparationStuds or 4)
	local maxStride = math.max(1, GameConfig.BotLobbyRoamMaxStrideStuds or 18)

	for _ = 1, 6 do
		local lx = (math.random() * 2 - 1) * halfX
		local lz = (math.random() * 2 - 1) * halfZ
		local flatWorld = area.CFrame:PointToWorldSpace(Vector3.new(lx, 0, lz))
		local candidate = Vector3.new(flatWorld.X, currentPos.Y, flatWorld.Z)
		if HorizontalDistanceXZ(candidate, currentPos) >= minSep then
			local flatCurrent = Vector3.new(currentPos.X, 0, currentPos.Z)
			local flatTarget = Vector3.new(candidate.X, 0, candidate.Z)
			local deltaFlat = flatTarget - flatCurrent
			local mag = deltaFlat.Magnitude
			if mag > maxStride then
				deltaFlat = deltaFlat.Unit * maxStride
			end
			return Vector3.new(currentPos.X + deltaFlat.X, currentPos.Y, currentPos.Z + deltaFlat.Z)
		end
	end
	return nil
end

local function GetOrCreateAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator ~= nil then
		return animator
	end
	local created = Instance.new("Animator")
	created.Parent = humanoid
	return created
end

local function CreateWalkAnimationTrack(humanoid: Humanoid): AnimationTrack?
	local animationId = GameConfig.BotLobbyRoamWalkAnimationId
	if typeof(animationId) ~= "string" or animationId == "" then
		return nil
	end
	local animator = GetOrCreateAnimator(humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or track == nil then
		return nil
	end
	local walkTrack = track :: AnimationTrack
	walkTrack.Looped = true
	walkTrack.Priority = Enum.AnimationPriority.Movement
	return walkTrack
end

local function PlayWalkAnimation(roamInfo: RoamInfo)
	local track = roamInfo.walkAnimationTrack
	if track == nil or track.IsPlaying then
		return
	end
	track:Play(0.15)
end

local function StopWalkAnimation(roamInfo: RoamInfo)
	local track = roamInfo.walkAnimationTrack
	if track == nil or not track.IsPlaying then
		return
	end
	track:Stop(0.15)
end

local function StopRoam(botId: number)
	local npcModel = CombatManager.GetLobbyNpcModel(botId)
	local roamInfo = roamInfoMap[botId]
	if roamInfo ~= nil then
		StopWalkAnimation(roamInfo)
	end
	roamInfoMap[botId] = nil
	if npcModel == nil then
		return
	end
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	local hrp = npcModel:FindFirstChild("HumanoidRootPart")
	if humanoid ~= nil and hrp ~= nil and hrp:IsA("BasePart") then
		humanoid:MoveTo((hrp :: BasePart).Position)
	end
end

local function UpdateRoamForBot(botId: number)
	local npcModel = CombatManager.GetLobbyNpcModel(botId)
	if npcModel == nil then
		roamInfoMap[botId] = nil
		return
	end

	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	local hrp = npcModel:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or hrp == nil or not hrp:IsA("BasePart") then
		roamInfoMap[botId] = nil
		return
	end

	local hrpPart = hrp :: BasePart
	local roamInfo = roamInfoMap[botId]
	if roamInfo == nil then
		humanoid.WalkSpeed = math.max(0, GameConfig.BotLobbyRoamWalkSpeed or 10)
		humanoid.AutoRotate = true
		roamInfoMap[botId] = {
			phase = PhaseIdle,
			phaseEndClock = os.clock() + RandomIdleDuration(),
			walkStartClock = 0,
			walkGoal = Vector3.zero,
			walkAnimationTrack = CreateWalkAnimationTrack(humanoid),
		}
		return
	end

	if roamInfo.phase == PhaseIdle then
		StopWalkAnimation(roamInfo)
		if os.clock() >= roamInfo.phaseEndClock then
			local sample = SamplePointInLobbyArea(hrpPart.Position)
			if sample == nil then
				roamInfo.phaseEndClock = os.clock() + RandomIdleDuration()
				return
			end
			humanoid:MoveTo(sample)
			PlayWalkAnimation(roamInfo)
			roamInfo.phase = PhaseWalking
			roamInfo.walkStartClock = os.clock()
			roamInfo.walkGoal = sample
		end
	elseif roamInfo.phase == PhaseWalking then
		local reachThreshold = math.max(0.1, GameConfig.BotLobbyRoamReachThresholdStuds or 1.5)
		local moveTimeout = math.max(0.5, GameConfig.BotLobbyRoamMoveTimeoutSec or 8)
		local dist = HorizontalDistanceXZ(hrpPart.Position, roamInfo.walkGoal)
		if dist <= reachThreshold or (os.clock() - roamInfo.walkStartClock) >= moveTimeout then
			roamInfo.phase = PhaseIdle
			roamInfo.phaseEndClock = os.clock() + RandomIdleDuration()
			StopWalkAnimation(roamInfo)
			humanoid:MoveTo(hrpPart.Position)
		end
	end
end

local function UpdateAllRoam()
	local matchState = CombatManager.GetServerMatchState()
	if matchState ~= GameConfig.MatchState.InLobby and matchState ~= GameConfig.MatchState.MatchCountdown then
		local staleIds: { number } = {}
		for botId in roamInfoMap do
			table.insert(staleIds, botId)
		end
		for _, botId in staleIds do
			StopRoam(botId)
		end
		table.clear(roamInfoMap)
		return
	end

	local botIds = CombatManager.GetBotIds()
	for _, botId in botIds do
		UpdateRoamForBot(botId)
	end

	local activeBotMap: { [number]: boolean } = {}
	for _, botId in botIds do
		activeBotMap[botId] = true
	end

	local orphanIds: { number } = {}
	for botId in roamInfoMap do
		if not activeBotMap[botId] then
			table.insert(orphanIds, botId)
		end
	end
	for _, botId in orphanIds do
		StopRoam(botId)
	end
end

local function OnHeartbeat(dt: number)
	tickAccumulatorSec += dt
	local interval = math.max(0.05, GameConfig.BotLobbyRoamTickIntervalSec or 0.25)
	while tickAccumulatorSec >= interval do
		tickAccumulatorSec -= interval
		UpdateAllRoam()
	end
end

function BotLobbyRoamManager.Init()
	if isInitialized then
		return
	end
	isInitialized = true
	if heartbeatConnection == nil then
		heartbeatConnection = runService.Heartbeat:Connect(OnHeartbeat)
	end
end

return BotLobbyRoamManager
