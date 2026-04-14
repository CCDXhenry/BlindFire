--!strict
local NetMsg = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local remoteEventsFolder: Folder = replicatedStorage:FindFirstChild("RemoteEvents") :: Folder
local requestSetBGMVolumeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetBGMVolume") :: RemoteEvent
local requestSetSoundEffectVolumeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetSoundEffectVolume") :: RemoteEvent
local requestSetVibrationsOnOffStateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetVibrationsOnOffState") :: RemoteEvent
local notifyPlayerInfoInitEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerInfoInit") :: RemoteEvent
local notifyPlayersOtherPlayerInfoInitEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayersOtherPlayerInfoInit") :: RemoteEvent
local notifyPlayerAcquiredGamePassEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerAcquiredGamePass") :: RemoteEvent

--客户端请求设置背景音乐音量
function NetMsg.FireRequestSetBGMVolume(volume: number)
	requestSetBGMVolumeEvent:FireServer(volume)
end

function NetMsg.ConnectRequestSetBGMVolume(callback: (player: Player, volume: number) -> ())
	requestSetBGMVolumeEvent.OnServerEvent:Connect(callback)
end

--客户端请求设置音效音量
function NetMsg.FireRequestSetSoundEffectVolume(volume: number)
	requestSetSoundEffectVolumeEvent:FireServer(volume)
end

function NetMsg.ConnectRequestSetSoundEffectVolume(callback: (player: Player, volume: number) -> ())
	requestSetSoundEffectVolumeEvent.OnServerEvent:Connect(callback)
end

--客户端请求设置振动开关状态
function NetMsg.FireRequestSetVibrationsOnOffState(vibrationsOn: boolean)
	requestSetVibrationsOnOffStateEvent:FireServer(vibrationsOn)
end

function NetMsg.ConnectRequestSetVibrationsOnOffState(callback: (player: Player, vibrationsOn: boolean) -> ())
	requestSetVibrationsOnOffStateEvent.OnServerEvent:Connect(callback)
end

--通知客户端玩家信息初始化完成
function NetMsg.FireNotifyPlayerInfoInit(player: Player, localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo, 
	otherPlayerSaveInfoMap: {[string]: GameConfig.ClientOtherPlayerSyncInfo}, playerConfigInfo: GameConfig.PlayerConfigInfo)
	notifyPlayerInfoInitEvent:FireClient(player, localPlayerSaveInfo, otherPlayerSaveInfoMap, playerConfigInfo)
end

function NetMsg.ConnectNotifyPlayerInfoInit(callback: (localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: {[string]: GameConfig.ClientOtherPlayerSyncInfo}, playerConfigInfo: GameConfig.PlayerConfigInfo) -> ())
	notifyPlayerInfoInitEvent.OnClientEvent:Connect(callback)
end

--通知客户端其他玩家信息初始化完成
function NetMsg.FireNotifyPlayersOtherPlayerInfoInit(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo)
	notifyPlayersOtherPlayerInfoInitEvent:FireAllClients(playerId, otherPlayerSaveInfo)
end

function NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(callback: (playerId: number, 
	otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo) -> ())
	notifyPlayersOtherPlayerInfoInitEvent.OnClientEvent:Connect(callback)
end

--通知客户端玩家获得了通行证
function NetMsg.FireNotifyPlayerAcquiredGamePass(player: Player, gamePassId: number)
	notifyPlayerAcquiredGamePassEvent:FireClient(player, gamePassId)
end

function NetMsg.ConnectNotifyPlayerAcquiredGamePass(callback: (gamePassId: number) -> ())
	notifyPlayerAcquiredGamePassEvent.OnClientEvent:Connect(callback)
end

return NetMsg
