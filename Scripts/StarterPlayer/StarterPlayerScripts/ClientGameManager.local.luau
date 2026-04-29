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
local GuideManager = require(clientScripts:FindFirstChild("GuideManager"))
local LeaderboardClient = require(clientScripts:WaitForChild("LeaderboardClient"))
local MatchActionManager = require(clientScripts:FindFirstChild("MatchActionManager"))
local ProximityPromptManager = require(clientScripts:FindFirstChild("ProximityPromptManager"))
local GroupRewardClientManager = require(clientScripts:FindFirstChild("GroupRewardClientManager"))
local ArenaClientManager = require(clientScripts:FindFirstChild("ArenaClientManager"))
local players = game:GetService("Players")
local starterGui: StarterGui = game:GetService("StarterGui")
local contentProvider: ContentProvider = game:GetService("ContentProvider")

local modelOriginsFolder: Folder? = replicatedStorage:FindFirstChild("Models") :: Folder?
local uiOriginsFolder: Folder? = replicatedStorage:FindFirstChild("UI") :: Folder?
local soundOriginsFolder: Folder? = replicatedStorage:FindFirstChild("Sounds") :: Folder?

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
	UIManager.CreateFrame("GameFrame", "GameFrame", gameScreenGui, 0)
	UIManager.CreateFrame("GameTipFrame", "GameTipFrame", gameScreenGui, 0)
	UIManager.CreateFrame("LobbyFrame", "LobbyFrame", gameScreenGui, 0)
	--UI适配器初始化
	UIAdapter.Init(DesignScreenSize, gameScreenGui.AbsoluteSize)
	gameScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		UIAdapter.OnScreenSizeChange(gameScreenGui.AbsoluteSize)
	end)
end

--通知客户端玩家信息初始化
local function OnNotifyPlayerInfoInit(
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
)
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
	GuideManager.Init()
	LeaderboardClient.Init()
	MatchActionManager.Init()
	ProximityPromptManager.Init()
	ArenaClientManager.Init()
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

local function OnNotifyPlayerVehicleInventoryUpdate(vehicleInventory: GameConfig.VehicleInventory)
	ClientGameInfo.UpdateVehicleInventory(vehicleInventory)
end

NetMsg.ConnectNotifyPlayerInfoInit(OnNotifyPlayerInfoInit)
NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(OnNotifyPlayersOtherPlayerInfoInit)
NetMsg.ConnectNotifyPlayerAcquiredGamePass(OnNotifyPlayerAcquiredGamePass)
NetMsg.ConnectNotifyPlayerCurrencyUpdate(OnNotifyPlayerCurrencyUpdate)
NetMsg.ConnectNotifyPlayerVehicleInventoryUpdate(OnNotifyPlayerVehicleInventoryUpdate)

local function PreloadAssets()
	local preloadStartTime = os.clock()
	local assetList: { Instance } = {}
	local meshMap: { [string]: boolean } = {}
	local decalMap: { [string]: boolean } = {}
	local imageMap: { [string]: boolean } = {}
	local soundMap: { [string]: boolean } = {}
	local animationMap: { [string]: boolean } = {}
	local failedAssetList: { string } = {}
	local folderList: { Instance } = {}

	if modelOriginsFolder ~= nil then
		table.insert(folderList, modelOriginsFolder)
	end
	if soundOriginsFolder ~= nil then
		table.insert(folderList, soundOriginsFolder)
	end
	if uiOriginsFolder ~= nil then
		table.insert(folderList, uiOriginsFolder)
	end

	local function AddMesh(meshId: string)
		if meshId == "" or meshMap[meshId] ~= nil then
			return
		end
		local specialMesh = Instance.new("SpecialMesh")
		specialMesh.MeshId = meshId
		table.insert(assetList, specialMesh)
		meshMap[meshId] = true
	end

	local function AddDecal(textureId: string)
		if textureId == "" or decalMap[textureId] ~= nil then
			return
		end
		local decal = Instance.new("Decal")
		decal.Texture = textureId
		table.insert(assetList, decal)
		decalMap[textureId] = true
	end

	local function AddImage(imageId: string)
		if imageId == "" or imageMap[imageId] ~= nil then
			return
		end
		local image = Instance.new("ImageLabel")
		image.Image = imageId
		table.insert(assetList, image)
		imageMap[imageId] = true
	end

	local function AddSound(soundId: string)
		if soundId == "" or soundMap[soundId] ~= nil then
			return
		end
		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		table.insert(assetList, sound)
		soundMap[soundId] = true
	end

	local function AddAnimation(animationId: string)
		if animationId == "" or animationMap[animationId] ~= nil then
			return
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		table.insert(assetList, animation)
		animationMap[animationId] = true
	end

	for _, folder: Instance in folderList do
		for _, descendant: Instance in folder:GetDescendants() do
			if descendant:IsA("MeshPart") then
				AddMesh(descendant.MeshId)
				AddDecal(descendant.TextureID)
			elseif descendant:IsA("SpecialMesh") then
				AddMesh(descendant.MeshId)
				AddDecal(descendant.TextureId)
			elseif descendant:IsA("Decal") then
				AddDecal(descendant.Texture)
			elseif descendant:IsA("Texture") then
				AddDecal(descendant.Texture)
			elseif descendant:IsA("Sound") then
				AddSound(descendant.SoundId)
			elseif descendant:IsA("Animation") then
				AddAnimation(descendant.AnimationId)
			elseif descendant:IsA("ParticleEmitter") then
				AddDecal(descendant.Texture)
			elseif descendant:IsA("Beam") then
				AddDecal(descendant.Texture)
			elseif descendant:IsA("ImageLabel") then
				AddImage(descendant.Image)
			elseif descendant:IsA("ImageButton") then
				AddImage(descendant.Image)
			end
		end
	end

	-- 预加载 GameConfig 图片资源
	local otherImageList: { string } = {}
	table.insert(otherImageList, GameConfig.CoinIconImage)
	table.insert(otherImageList, GameConfig.RbIconImage)
	table.insert(otherImageList, GameConfig.AFKOnImage)
	table.insert(otherImageList, GameConfig.AFKOffImage)

	for _, otherImage: string in otherImageList do
		AddImage(otherImage)
	end

	local preloadSuccess, preloadErr = pcall(function()
		contentProvider:PreloadAsync(assetList, function(assetId: string, assetFetchStatus: Enum.AssetFetchStatus)
			if assetFetchStatus ~= Enum.AssetFetchStatus.Success then
				table.insert(failedAssetList, assetId)
				warn("[ClientGameManager] LoadAssetResult", assetId, assetFetchStatus)
			end
		end)
	end)

	if not preloadSuccess then
		warn("[ClientGameManager] PreloadAssets failed:", preloadErr)
	end

	for _, instance: Instance in assetList do
		instance:Destroy()
	end
	table.clear(assetList)

	local elapsedTime = os.clock() - preloadStartTime
	print(string.format("[ClientGameManager] PreloadAssets complete. failed=%d elapsed=%.2fs", #failedAssetList, elapsedTime))
	table.clear(failedAssetList)
end

-- 客户端启动时异步预加载资源
task.spawn(function()
	PreloadAssets()
end)

BulletClientManager.Init()
CombatCameraManager.Init()
GuideManager.Init()
ClientGameInfo.Init()
GroupRewardClientManager.Init()
