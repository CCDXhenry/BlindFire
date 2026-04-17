--!strict
local ConfigManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local LOG_PREFIX = "[ConfigManager]"

-- 存储所有修改的参数覆盖值
local configOverrides: { [string]: any } = {}

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
end

-- 设置一个参数对应的覆盖值
function ConfigManager.SetOverride(key: string, value: any)
	configOverrides[key] = value
	LogInfo(string.format("SetOverride key=%s value=%s", key, tostring(value)))
end

-- 清除所有覆盖值
function ConfigManager.ResetOverrides()
	configOverrides = {}
	LogInfo("ResetOverrides")
end

-- 获取当前的覆盖值列表
function ConfigManager.GetOverrides(): { [string]: any }
	return configOverrides
end

-- 仅同步待定配置（不应用到服务器 GameConfig 表）
function ConfigManager.SyncPendingOnly()
	NetMsg.FireNotifyPendingConfigSync(configOverrides)
	LogInfo("SyncPendingOnly broadcasted")
end

-- 应用修改并同步给所有客户端
-- 通常在每局游戏开始时调用
function ConfigManager.ApplyAndSync()
	LogInfo("ApplyAndSync starting")
	
	-- 这里的逻辑是：将 server 上的 GameConfig 模块表格中的值更新为 override 值
	-- 这样 server 上其他引用该模块的代码都能拿到最新的配置
	for key, value in pairs(configOverrides) do
		if GameConfig[key] ~= nil then
			GameConfig[key] = value
		else
			warn(string.format("%s Key %s not found in GameConfig", LOG_PREFIX, key))
		end
	end
	
	-- 同步给所有客户端
	NetMsg.FireNotifyGameConfigSync(configOverrides)
	LogInfo("ApplyAndSync completed")
end

return ConfigManager
