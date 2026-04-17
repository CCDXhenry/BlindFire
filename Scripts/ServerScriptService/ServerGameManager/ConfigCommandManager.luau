--!strict
local ConfigCommandManager = {}

local textChatService: TextChatService = game:GetService("TextChatService")
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ConfigManager = require(serverScripts:WaitForChild("ConfigManager"))
local MatchManager = require(serverScripts:WaitForChild("MatchManager"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local serverCore = serverStorage:WaitForChild("Core")
local serverCoreScripts = serverCore:WaitForChild("Scripts")
local GMConfig = require(serverCoreScripts:FindFirstChild("GMConfig"))

local LOG_PREFIX = "[ConfigCommandManager]"

local function LogInfo(message: string)
	print(string.format("%s %s", LOG_PREFIX, message))
end

-- 创建指令物体
local function CreateCommands()
	local customCommandsFolder = textChatService:FindFirstChild("CustomTextChatCommands")
	if not customCommandsFolder then
		customCommandsFolder = Instance.new("Folder")
		customCommandsFolder.Name = "CustomTextChatCommands"
		customCommandsFolder.Parent = textChatService
	end

	-- /config 指令
	local configCommand = customCommandsFolder:FindFirstChild("ConfigCommand")
	if not configCommand then
		configCommand = Instance.new("TextChatCommand")
		configCommand.Name = "ConfigCommand"
		configCommand.PrimaryAlias = "/config"
		configCommand.SecondaryAlias = "/c"
		configCommand.Parent = customCommandsFolder
	end

	return configCommand :: TextChatCommand
end

local function OnConfigCommandTriggered(originTextSource: TextSource, unfilteredText: string)
	local userId = originTextSource.UserId
	if not GMConfig.IsGMPlayer(userId) then
		warn(string.format("%s Unauthorized user %d tried to use /config", LOG_PREFIX, userId))
		return
	end

	-- 解析指令格式: /config <subcommand> [key] [value]
	local args = string.split(unfilteredText, " ")
	local subcommand = args[2] -- args[1] 是 "/config" 或 "/c"

	if subcommand == "set" then
		local inputKey = args[3]
		local valueString = args[4]
		if inputKey and valueString then
			-- 根据输入解析真正的 Key (支持英文 Key 或 中文 Alias)
			local realKey = inputKey
			local visibleParams = GameConfig.VisibleParameters or {}
			for _, configInfo in ipairs(visibleParams) do
				if configInfo.alias == inputKey then
					realKey = configInfo.key
					break
				end
			end

			-- 根据 GameConfig 中原值的类型进行转换
			local originalValue = GameConfig[realKey]
			local finalValue: any = valueString

			if type(originalValue) == "number" then
				finalValue = tonumber(valueString)
			elseif type(originalValue) == "boolean" then
				finalValue = (valueString == "true" or valueString == "1")
			end

			if finalValue ~= nil and originalValue ~= nil then
				ConfigManager.SetOverride(realKey, finalValue)
				ConfigManager.SyncPendingOnly() -- 立即同步待定变更给客户端 UI
				LogInfo(string.format("Command set %s (%s) = %s (applied next round)", realKey, inputKey, tostring(finalValue)))
			else
				warn(string.format("%s Invalid key or value [%s / %s]", LOG_PREFIX, inputKey, valueString))
			end
		end
	elseif subcommand == "reset" then
		ConfigManager.ResetOverrides()
		ConfigManager.SyncPendingOnly() -- 立即同步待定变更给客户端 UI
		LogInfo("Command reset all overrides (applied next round)")
	elseif subcommand == "stop" then
		MatchManager.RequestStopMatch()
	elseif subcommand == "list" then
		local overrides = ConfigManager.GetOverrides()
		LogInfo("Current overrides: " .. game:GetService("HttpService"):JSONEncode(overrides))
	end
end

function ConfigCommandManager.Init()
	local configCommand = CreateCommands()
	configCommand.Triggered:Connect(OnConfigCommandTriggered)
	LogInfo("Init completed")
end

return ConfigCommandManager
