--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local SoundTool = require(coreSharedScripts:FindFirstChild("SoundTool"))
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local UIManager = require(clientScripts:FindFirstChild("UIManager"))
local BulletClientManager = require(clientScripts:FindFirstChild("BulletClientManager"))
local CombatCameraManager = require(clientScripts:FindFirstChild("CombatCameraManager"))
local MatchActionManager = require(clientScripts:FindFirstChild("MatchActionManager"))
local players = game:GetService("Players")
local starterGui: StarterGui = game:GetService("StarterGui")

local DesignScreenSize: Vector2 = Vector2.new(1920, 1080)

local soundsFolder: Folder = workspace:FindFirstChild("Sounds")
local bgmSound: Sound = soundsFolder:FindFirstChild("BGM") :: Sound

local function InitUI()
	local playerGui: PlayerGui = players.LocalPlayer:WaitForChild("PlayerGui")
	local gameScreenGui: ScreenGui = playerGui:WaitForChild("GameScreenGui") :: ScreenGui
	--禁用默认工具栏
	starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	--设置窗口容器
	UIManager.Init(gameScreenGui)
	--创建游戏主界面
	--UIManager.CreateFrame("GameFrame", "GameFrame", gameScreenGui, 0)
	UIManager.CreateFrame("GameTipFrame", "GameTipFrame", gameScreenGui, 0)
	--UI适配器初始化
	UIAdapter.Init(DesignScreenSize, gameScreenGui.AbsoluteSize)
	gameScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() 
		UIAdapter.OnScreenSizeChange(gameScreenGui.AbsoluteSize)
	end)
end

--通知客户端玩家信息初始化
local function OnNotifyPlayerInfoInit(localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo, 
	otherPlayerSaveInfoMap: {[string]: GameConfig.ClientOtherPlayerSyncInfo}, playerConfigInfo: GameConfig.PlayerConfigInfo)
	ClientGameInfo.InitPlayerInfo(localPlayerSaveInfo, otherPlayerSaveInfoMap, playerConfigInfo)
	local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo ~= nil then
		SoundTool.SetBGMVolumn(localPlayerInfo.settingInfo.bgmVolume)
		SoundTool.SetSoundEffectVolume(localPlayerInfo.settingInfo.soundEffectVolume)
	end
	SoundTool.PlayBGM(bgmSound)
	-- 初始化核心玩法客户端管理器
	BulletClientManager.Init()
	CombatCameraManager.Init()
	MatchActionManager.Init()
	--初始化UI
	task.spawn(function()
		InitUI()
	end)
end

local function OnNotifyPlayersOtherPlayerInfoInit(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo)
	if playerId ~= players.LocalPlayer.UserId then
		ClientGameInfo.InitOtherPlayerInfo(playerId, otherPlayerSaveInfo)
	end
end

local function OnNotifyPlayerAcquiredGamePass(gamePassId: number)
	ClientGameInfo.SetLocalPlayerGamePassAcquired(gamePassId)
end

local function OnNotifyPlayerCurrencyUpdate(currencyType: number, totalAmount: number, lastChange: number, reason: number)
	ClientGameInfo.UpdateCurrency(currencyType, totalAmount, lastChange, reason)
end

NetMsg.ConnectNotifyPlayerInfoInit(OnNotifyPlayerInfoInit)
NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(OnNotifyPlayersOtherPlayerInfoInit)
NetMsg.ConnectNotifyPlayerAcquiredGamePass(OnNotifyPlayerAcquiredGamePass)
NetMsg.ConnectNotifyPlayerCurrencyUpdate(OnNotifyPlayerCurrencyUpdate)

BulletClientManager.Init()
CombatCameraManager.Init()