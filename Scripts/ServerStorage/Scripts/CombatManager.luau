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

type OnPlayerDeadCallback = (player: Player) -> ()

type ServerUnitInfo = {
	playerId: number,
	unitModel: Model,
	rootPart: BasePart,
	spinDir: number,
	moveAngle: number,
}
local heartbeatConnection: RBXScriptConnection? = nil


local LOG_PREFIX = "[CombatManager]"
local VEHICLE_MODEL_NAME_PREFIX = "Vehicle_"
local UNDERGROUND_Y = -100

local unitInfoMap: { [number]: ServerUnitInfo } = {}
local playerDeadCallback: OnPlayerDeadCallback? = nil
local vehicleBumpNextAllowedClock: { [string]: number } = {}

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
end

local function FormatVector3(vector: Vector3): string
	return string.format("(%.2f, %.2f, %.2f)", vector.X, vector.Y, vector.Z)
end

local function ToHorizontalDirection(vector: Vector3): Vector3
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return horizontal.Unit
end

local function HorizontalImpulseFromVector(impulse: Vector3): Vector3
	return Vector3.new(impulse.X, 0, impulse.Z)
end

local function GetModelsFolder(): Folder
	return replicatedStorage:WaitForChild("Models") :: Folder
end

local function GetVehicleTemplate(): Model?
	local modelsFolder = GetModelsFolder()
	local vehicleTemplate = modelsFolder:FindFirstChild("VehicleModel")
	if vehicleTemplate == nil or not vehicleTemplate:IsA("Model") then
		return nil
	end
	return vehicleTemplate
end

local function GetRandomMoveAngle(): number
	return math.random(0, 359)
end

local function GetRandomSpinDir(): number
	return (math.random(0, 1) == 0) and 1 or -1
end

local function GetSpawnPosition(): Vector3
	local halfSize = GameConfig.ArenaHalfSize - GameConfig.ArenaSpawnMargin
	local maxAttempts = 20
	local bestPos = Vector3.zero

	for i = 1, maxAttempts do
		local randomX = math.random() * (halfSize * 2) - halfSize
		local randomZ = math.random() * (halfSize * 2) - halfSize
		local pos = Vector3.new(randomX, GameConfig.UnitY, randomZ)

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

local function GetMuzzleAttachment(unitModel: Model): Attachment?
	local barrel = unitModel:FindFirstChild("TurretBarrel", true)
	if barrel == nil or not barrel:IsA("BasePart") then
		return nil
	end
	local muzzleAttachment = barrel:FindFirstChild("MuzzleAttachment")
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

-- OnVehicleBaseDiskTouched removed as vehicle bumps are now handled client-side

local function CreateUnitModelForPlayer(player: Player): ServerUnitInfo?
	local vehicleTemplate = GetVehicleTemplate()
	if vehicleTemplate == nil then
		warn("[CombatManager] VehicleModel template not found.")
		return nil
	end
	local unitModel: Model = vehicleTemplate:Clone()
	unitModel.Name = "Vehicle_" .. tostring(player.UserId)
	unitModel.Parent = workspace

	local rootPart = unitModel:FindFirstChild("BaseDisk")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		unitModel:Destroy()
		warn("[CombatManager] VehicleModel.BaseDisk not found.")
		return nil
	end
	unitModel.PrimaryPart = rootPart
	rootPart.CanCollide = true
	-- SetNetworkOwner 必须在未锚固时调用；大厅 / MatchCountdown 期间再锚固，入场由 MatchManager 解锚
	rootPart.Anchored = false
	for _, inst in unitModel:GetDescendants() do
		if inst:IsA("BasePart") then
			local oldAnchored = inst.Anchored
			inst.Anchored = false
			pcall(function()
				inst:SetNetworkOwner(player)
			end)
			inst.Anchored = oldAnchored
		end
	end
	rootPart.Anchored = true
 
	local spawnPosition = GetSpawnPosition()
	local undergroundPosition = Vector3.new(spawnPosition.X, UNDERGROUND_Y, spawnPosition.Z)
	MoveModelKeepRotation(unitModel, undergroundPosition)

	local moveAngle = GetRandomMoveAngle()
	local spinDir = GetRandomSpinDir()
	local unitInfo: ServerUnitInfo = {
		playerId = player.UserId,
		unitModel = unitModel,
		rootPart = rootPart,
		spinDir = spinDir,
		moveAngle = moveAngle,
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
		LogInfo(string.format("DestroyUnit skip userId=%d reason=unit_not_found", playerId))
		return
	end
	if unitInfo.unitModel.Parent ~= nil then
		unitInfo.unitModel:Destroy()
	end
	unitInfoMap[playerId] = nil
	LogInfo(string.format("DestroyUnit userId=%d", playerId))
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

function CombatManager.ResetUnitToUnderground(playerId: number)
	ResetUnitToUnderground(playerId)
end

function CombatManager.ResetAllUnitsToUnderground()
	for playerId in unitInfoMap do
		ResetUnitToUnderground(playerId)
	end
end

local function BroadcastUnitInit(unitInfo: ServerUnitInfo)
	local unitInitInfo: GameConfig.UnitInitInfo = {
		playerId = unitInfo.playerId,
		moveAngle = unitInfo.moveAngle,
		spinDir = unitInfo.spinDir,
		spawnPosition = unitInfo.rootPart.Position,
		maxHits = GameConfig.MaxHits,
	}
	NetMsg.FireNotifyUnitInitToAll(unitInitInfo)
	NetMsg.FireNotifyHpChanged(unitInfo.playerId, 0, GameConfig.MaxHits)
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


local function ResolveProjectileHit(shooterId: number, targetPlayerId: number, hitDirection: Vector3)
	hitDirection = ToHorizontalDirection(hitDirection)

	if targetPlayerId == shooterId and not GameConfig.CanHitSelf then
		LogInfo(string.format("ProjectileHit ignored shooterId=%d targetId=%d", shooterId, targetPlayerId))
		return
	end

	local targetUnitInfo = unitInfoMap[targetPlayerId]
	if targetUnitInfo ~= nil then
		targetUnitInfo.spinDir = GetRandomSpinDir()
		NetMsg.FireNotifyDirectionFlipToAll(targetPlayerId)
	end

	local hitCount, isDead = PlayerStateManager.AddPlayerHit(targetPlayerId)
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
	NetMsg.FireNotifyHit(targetPlayerId, shooterId, hitDirection, hitCount)
	NetMsg.FireNotifyHpChanged(targetPlayerId, hitCount, GameConfig.MaxHits)
	if isDead then
		NetMsg.FireNotifyDead(targetPlayerId)
		local targetPlayer = players:GetPlayerByUserId(targetPlayerId)
		if targetPlayer ~= nil and playerDeadCallback ~= nil then
			LogInfo(string.format("NotifyPlayerDead userId=%d", targetPlayerId))
			playerDeadCallback(targetPlayer)
		end
	end
end



function CombatManager.Init(onPlayerDead: OnPlayerDeadCallback)
	playerDeadCallback = onPlayerDead
	NetMsg.ConnectRequestFire(CombatManager.OnRequestFire)
	NetMsg.ConnectRequestHit(CombatManager.OnRequestHit)
	LogInfo("Init success")
end

function CombatManager.OnRequestHit(player: Player, targetPlayerId: number, hitDirection: Vector3)
	local shooterId = player.UserId
	
	-- 检测发射者是否已被登记、是否存活（简单的安全校验）
	local shooterUnit = unitInfoMap[shooterId]
	if shooterUnit == nil then
		LogInfo(string.format("HitRejected shooterId=%d targetId=%d reason=shooter_not_found", shooterId, targetPlayerId))
		return
	end
	
	ResolveProjectileHit(shooterId, targetPlayerId, hitDirection)
end

function CombatManager.OnPlayerAdded(player: Player)
	PlayerStateManager.EnsurePlayerRoundInfo(player)
	LogInfo(string.format("OnPlayerAdded userId=%d", player.UserId))
	local unitInfo = CreateUnitModelForPlayer(player)
	if unitInfo == nil then
		LogInfo(string.format("OnPlayerAdded failed userId=%d reason=create_unit_failed", player.UserId))
		return
	end
	BroadcastUnitInit(unitInfo)
end

function CombatManager.OnPlayerRemoving(player: Player)
	LogInfo(string.format("OnPlayerRemoving userId=%d", player.UserId))
	
	local roundInfoMap = PlayerStateManager.GetAllPlayerRoundInfoMap()
	local roundInfo = roundInfoMap[player.UserId]
	if roundInfo ~= nil and roundInfo.isParticipant and roundInfo.isAlive then
		roundInfo.isAlive = false
		NetMsg.FireNotifyDead(player.UserId)
		if playerDeadCallback ~= nil then
			playerDeadCallback(player)
		end
	end

	unseatPlayerFromOwnedVehicle(player)
	DestroyUnitForPlayer(player.UserId)
	PlayerStateManager.RemovePlayerRoundInfo(player.UserId)
	NetMsg.FireNotifyUnitRemoveToAll(player.UserId)
end

function CombatManager.OnRequestFire(player: Player, spawnPos: Vector3, shotDirection: Vector3)
	-- Normalize and ensure height is roughly correct to prevent weird angle exploits, or trust the client for now
	shotDirection = ToHorizontalDirection(shotDirection)
	local nowTime = os.clock()
	local canFire = PlayerStateManager.CanFire(player.UserId, nowTime)
	if not canFire then
		LogInfo(string.format("FireRejected userId=%d reason=cooldown_or_dead now=%.2f", player.UserId, nowTime))
		return
	end
	PlayerStateManager.SetLastFireTime(player.UserId, nowTime)

	local unitInfo = unitInfoMap[player.UserId]
	if unitInfo ~= nil then
		unitInfo.spinDir = -unitInfo.spinDir
	end
	LogInfo(string.format("FireAccepted userId=%d fireTime=%.2f", player.UserId, nowTime))
	NetMsg.FireNotifyDirectionFlipToAll(player.UserId)
	local serverTime = workspace:GetServerTimeNow()
	NetMsg.FireNotifyFireAccepted(player.UserId, nowTime, spawnPos, shotDirection, serverTime)
end

function CombatManager.StartRound(participantIds: { number })
	LogInfo("StartRound begin")
	PlayerStateManager.ResetAllPlayerRoundInfo(participantIds)
	for _, playerId in participantIds do
		local unitInfo = unitInfoMap[playerId]
		if unitInfo == nil then
			continue
		end
		unitInfo.moveAngle = GetRandomMoveAngle()
		unitInfo.spinDir = GetRandomSpinDir()
		NetMsg.FireNotifyUnitInitToAll({
			playerId = playerId,
			moveAngle = unitInfo.moveAngle,
			spinDir = unitInfo.spinDir,
			spawnPosition = unitInfo.rootPart.Position,
			maxHits = GameConfig.MaxHits,
		})
		NetMsg.FireNotifyHpChanged(playerId, 0, GameConfig.MaxHits)
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
