--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local serverCore = serverStorage:WaitForChild("Core")
local serverCoreScripts = serverCore:WaitForChild("Scripts")
local GMConfig = require(serverCoreScripts:FindFirstChild("GMConfig"))
local TeleportTool = require(serverCoreScripts:FindFirstChild("TeleportTool"))
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local runService: RunService = game:GetService("RunService")
local players: Players = game:GetService("Players")
local textChatService: TextChatService = game:GetService("TextChatService")
local customTextChatCommandsFolder: Folder = textChatService:FindFirstChild("CustomTextChatCommands") :: Folder
local clearDataStoreCommand: TextChatCommand = customTextChatCommandsFolder:FindFirstChild("ClearDataStoreCommand") :: TextChatCommand
local addCurrencyCommand: TextChatCommand = customTextChatCommandsFolder:FindFirstChild("AddCurrencyCommand") :: TextChatCommand

--清空数据
local function OnClearDataStoreCommandTrigged(originTextSource: TextSource, unfilteredText: string)
	if runService:IsStudio() or not GMConfig.IsGMPlayer(originTextSource.UserId) then
		return
	end
	local player: Player? = players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end
	--传送到清除玩家数据场景
	local teleportOptions = Instance.new("TeleportOptions")
	local teleportData: any = {
		gameStartPlaceId = GameConfig.GamePlaceId,
		defaultPlayerSaveInfo = GameConfig.CreateDefaultPlayerSaveInfo()
	}
	teleportOptions:SetTeleportData(teleportData)
	TeleportTool.SafeTeleport(GameConfig.ClearDataStorePlaceId, {player}, teleportOptions)
end

--增加货币
local function OnAddCurrencyCommandTrigged(originTextSource: TextSource, unfilteredText: string)
	if not runService:IsStudio() and not GMConfig.IsGMPlayer(originTextSource.UserId) then
		return
	end
	local player: Player? = players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end
	
	-- 使用正则匹配单词，处理多余空格
	local textWords: {string} = {}
	for word in string.gmatch(unfilteredText, "%S+") do
		table.insert(textWords, word)
	end

	if #textWords < 3 then
		return
	end

	local currencyTypeInput = string.lower(textWords[2])
	local addCurrencyType: number? = tonumber(currencyTypeInput)
	
	if addCurrencyType == nil then
		-- 支持常用的货币名称输入
		if currencyTypeInput == "coin" or currencyTypeInput == "金币" then
			addCurrencyType = GameConfig.CurrencyType.Coin
		elseif currencyTypeInput == "rb" or currencyTypeInput == "robux" or currencyTypeInput == "r币" then
			addCurrencyType = GameConfig.CurrencyType.Rb
		end
	end

	if addCurrencyType == nil then
		return
	end

	local addCurrencyCount: number? = tonumber(textWords[3])
	if addCurrencyCount == nil then
		return
	end
	
	ServerGameInfo.UpdatePlayerCurrency(player, addCurrencyType, addCurrencyCount, GameConfig.ItemCountChangeReason.GainFromGMCommand)
end

addCurrencyCommand.Triggered:Connect(OnAddCurrencyCommandTrigged)
clearDataStoreCommand.Triggered:Connect(OnClearDataStoreCommandTrigged)