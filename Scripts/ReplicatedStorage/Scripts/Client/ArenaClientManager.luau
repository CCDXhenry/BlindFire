--!strict
local ArenaClientManager = {}

local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local LOG_PREFIX = "[ArenaClientManager]"
local ARENA_MODEL_NAME = "Arena"

local arenaModel: Model? = nil
local visualHalfSize: number = 60
local isInitialized: boolean = false

local function LogInfo(message: string)
	-- print(string.format("%s %s", LOG_PREFIX, message))
end

function ArenaClientManager.Init()
	if isInitialized then return end
	
	arenaModel = workspace:FindFirstChild(ARENA_MODEL_NAME) :: Model
	if not arenaModel then
		LogInfo("Arena model not found in workspace")
		return
	end

	-- 初始值从属性获取，如果没有则默认 60
	visualHalfSize = arenaModel:GetAttribute("CurrentHalfSize") or GameConfig.ArenaHalfSize
	
	runService.RenderStepped:Connect(function(dt: number)
		if not arenaModel then return end
		
		local targetHalfSize = arenaModel:GetAttribute("CurrentHalfSize") :: number?
		if not targetHalfSize then return end
		
		-- 使用简单的插值平滑视觉表现
		-- 这里的 15 是平滑系数，可以根据手感调整
		local lerpFactor = math.clamp(dt * 15, 0, 1)
		visualHalfSize = visualHalfSize + (targetHalfSize - visualHalfSize) * lerpFactor
		
		-- 计算比例并应用本地缩放
		local ratio = visualHalfSize / GameConfig.ArenaDesignHalfSize
		arenaModel:ScaleTo(ratio)
	end)

	isInitialized = true
	LogInfo("Init success")
end

return ArenaClientManager
