--!strict
local ArenaManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local LOG_PREFIX = "[ArenaManager]"
local ARENA_MODEL_NAME = "Arena"
local FLOOR_NAME = "ArenaFloor"
local SPAWN_FOLDER_NAME = "ArenaSpawnPoints"

local arenaModel: Model? = nil
local floorPart: BasePart? = nil
local initialSpawnPositions: { [BasePart]: Vector3 } = {}
local currentHalfSize: number = 60

local shrinkThread: thread? = nil

local initialHalfSizeConstant = 60

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
end

function ArenaManager.Init()
	arenaModel = workspace:FindFirstChild(ARENA_MODEL_NAME) :: Model
	if not arenaModel then
		LogInfo("Arena model not found in workspace")
		return
	end

	currentHalfSize = GameConfig.ArenaHalfSize
	
	-- Identify Floor
	floorPart = arenaModel:FindFirstChild(FLOOR_NAME) :: BasePart
	if not floorPart then
		for _, child in arenaModel:GetChildren() do
			if child:IsA("BasePart") and string.find(child.Name:lower(), "floor") then
				floorPart = child
				break
			end
		end
	end
	
	-- 标记墙壁方向，解决极小缩圈下的方向翻转问题
	if floorPart then
		local arenaCenter = floorPart.Position
		for _, child in arenaModel:GetDescendants() do
			if child:IsA("BasePart") and (child.Name == "ArenaWall" or string.find(child.Name:lower(), "wall")) then
				-- 计算局部坐标系下的内向法线
				-- 这样做不论 ScaleTo 如何缩放，局部法线始终代表相对于墙面“向里”的方向
				local toCenterWorld = (arenaCenter - child.Position).Unit
				local wallCF = child.CFrame
				
				-- 找到最匹配的主轴
				local toCenterLocal = wallCF:VectorToObjectSpace(toCenterWorld)
				local mainAxis = Vector3.new(0, 0, 0)
				if math.abs(toCenterLocal.X) > math.abs(toCenterLocal.Z) then
					mainAxis = Vector3.new(math.sign(toCenterLocal.X), 0, 0)
				else
					mainAxis = Vector3.new(0, 0, math.sign(toCenterLocal.Z))
				end
				
				child:SetAttribute("LocalInwardNormal", mainAxis)
				-- LogInfo(string.format("Tagged wall %s with normal %s", child.Name, tostring(mainAxis)))
			end
		end
	end

	LogInfo("Init success")
end

function ArenaManager.GetArenaFloorInfo(): (Vector3, Vector3)
	if floorPart then
		return floorPart.Position, floorPart.Size
	end
	return Vector3.zero, Vector3.new(GameConfig.ArenaHalfSize * 2, 0, GameConfig.ArenaHalfSize * 2)
end

function ArenaManager.SetArenaHalfSize(halfSize: number)
	if not arenaModel then return end

	currentHalfSize = halfSize
	-- Update GameConfig on server for other server scripts
	GameConfig.ArenaHalfSize = halfSize
	
	-- Calculate ratio relative to the design-time base size (60)
	local ratio = halfSize / initialHalfSizeConstant
	
	-- Use ScaleTo to scale the entire model (Floor, Walls, and SpawnPoints)
	arenaModel:ScaleTo(ratio)

	-- Replicate to attributes for client to read
	arenaModel:SetAttribute("CurrentHalfSize", halfSize)
end

function ArenaManager.PrepareArena(playerCount: number)
	local initialHalfSize = GameConfig.ArenaBaseHalfSize + (playerCount * GameConfig.ArenaExtraHalfSizePerPlayer)
	LogInfo(string.format("PrepareArena playerCount=%d initialHalfSize=%.1f", playerCount, initialHalfSize))
	ArenaManager.SetArenaHalfSize(initialHalfSize)
end

function ArenaManager.StartShrinking(maxDuration: number)
	ArenaManager.StopShrinking()
	
	shrinkThread = task.spawn(function()
		local startTime = os.clock()
		local durationSoFar = 0
		
		while durationSoFar < maxDuration do
			local dt = task.wait()
			durationSoFar = os.clock() - startTime
			
			if durationSoFar > GameConfig.ArenaShrinkStartDelay then
				local shrinkStep = GameConfig.ArenaShrinkSpeed * dt
				local newSize = math.max(GameConfig.ArenaMinHalfSize, currentHalfSize - shrinkStep)
				if newSize ~= currentHalfSize then
					ArenaManager.SetArenaHalfSize(newSize)
				end
				
				if newSize <= GameConfig.ArenaMinHalfSize then
					LogInfo("Min arena size reached")
					break
				end
			end
		end
		LogInfo("Shrinking thread ended")
	end)
end

function ArenaManager.StopShrinking()
	if shrinkThread then
		task.cancel(shrinkThread)
		shrinkThread = nil
	end
end

function ArenaManager.ResetArena()
	ArenaManager.StopShrinking()
	ArenaManager.SetArenaHalfSize(60) -- Default or Config.ArenaHalfSize
	LogInfo("ResetArena")
end

return ArenaManager
