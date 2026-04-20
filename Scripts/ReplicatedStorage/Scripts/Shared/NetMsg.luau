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
-- Demo 玩法
local requestFireEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestFire") :: RemoteEvent
local requestHitEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestHit") :: RemoteEvent
local notifyUnitInitEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyUnitInit") :: RemoteEvent
local notifyDirectionFlipEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyDirectionFlip") :: RemoteEvent
local notifyUnitRemoveEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyUnitRemove") :: RemoteEvent
local notifyFireAcceptedEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyFireAccepted") :: RemoteEvent
local notifyHitEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyHit") :: RemoteEvent
local notifyHpChangedEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyHpChanged") :: RemoteEvent
local notifyDeadEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyDead") :: RemoteEvent
local notifyRoundOutcomeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyRoundOutcome") :: RemoteEvent
local notifyMatchStateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyMatchState") :: RemoteEvent
local notifyTeleportEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyTeleport") :: RemoteEvent
local notifyArenaSeatPrepareEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyArenaSeatPrepare") :: RemoteEvent
local notifyGameConfigSyncEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyGameConfigSync") :: RemoteEvent
local notifyPendingConfigSyncEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPendingConfigSync") :: RemoteEvent

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
function NetMsg.FireNotifyPlayerInfoInit(
	player: Player,
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
)
	notifyPlayerInfoInitEvent:FireClient(player, localPlayerSaveInfo, otherPlayerSaveInfoMap, playerConfigInfo)
end

function NetMsg.ConnectNotifyPlayerInfoInit(callback: (
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
) -> ())
	notifyPlayerInfoInitEvent.OnClientEvent:Connect(callback)
end

--通知客户端其他玩家信息初始化完成
function NetMsg.FireNotifyPlayersOtherPlayerInfoInit(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo)
	notifyPlayersOtherPlayerInfoInitEvent:FireAllClients(playerId, otherPlayerSaveInfo)
end

function NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(callback: (playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo) -> ())
	notifyPlayersOtherPlayerInfoInitEvent.OnClientEvent:Connect(callback)
end

--通知客户端玩家获得了通行证
function NetMsg.FireNotifyPlayerAcquiredGamePass(player: Player, gamePassId: number)
	notifyPlayerAcquiredGamePassEvent:FireClient(player, gamePassId)
end

function NetMsg.ConnectNotifyPlayerAcquiredGamePass(callback: (gamePassId: number) -> ())
	notifyPlayerAcquiredGamePassEvent.OnClientEvent:Connect(callback)
end

-- ============================================================
-- Demo 玩法通信封装
-- ============================================================

--客户端请求开火
function NetMsg.FireRequestFire(spawnPos: Vector3, shotDir: Vector3, clientTimestamp: number, bulletId: string)
	requestFireEvent:FireServer(spawnPos, shotDir, clientTimestamp, bulletId)
end

function NetMsg.ConnectRequestFire(callback: (player: Player, spawnPos: Vector3, shotDir: Vector3, clientTimestamp: number, bulletId: string) -> ())
	requestFireEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求命中某个玩家
function NetMsg.FireRequestHit(targetPlayerId: number, hitDir: Vector3, bulletId: string)
	requestHitEvent:FireServer(targetPlayerId, hitDir, bulletId)
end

function NetMsg.ConnectRequestHit(callback: (player: Player, targetPlayerId: number, hitDir: Vector3, bulletId: string) -> ())
	requestHitEvent.OnServerEvent:Connect(callback)
end

--通知所有客户端某玩家单位初始化信息
function NetMsg.FireNotifyUnitInit(player: Player, unitInitInfo: GameConfig.UnitInitInfo)
	notifyUnitInitEvent:FireClient(player, unitInitInfo)
end

function NetMsg.FireNotifyUnitInitToAll(unitInitInfo: GameConfig.UnitInitInfo)
	notifyUnitInitEvent:FireAllClients(unitInitInfo)
end

function NetMsg.ConnectNotifyUnitInit(callback: (unitInitInfo: GameConfig.UnitInitInfo) -> ())
	notifyUnitInitEvent.OnClientEvent:Connect(callback)
end

--通知所有客户端某玩家方向翻转function NetMsg.FireNotifyDirectionFlipToAll(playerId: number)
function NetMsg.FireNotifyDirectionFlipToAll(playerId: number)
	notifyDirectionFlipEvent:FireAllClients(playerId)
end

function NetMsg.ConnectNotifyDirectionFlip(callback: (playerId: number) -> ())
	notifyDirectionFlipEvent.OnClientEvent:Connect(callback)
end

--通知所有客户端某玩家单位移除
function NetMsg.FireNotifyUnitRemoveToAll(playerId: number)
	notifyUnitRemoveEvent:FireAllClients(playerId)
end

function NetMsg.ConnectNotifyUnitRemove(callback: (playerId: number) -> ())
	notifyUnitRemoveEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyFireAccepted(playerId: number, fireTime: number, spawnPos: Vector3, shotDir: Vector3, serverTime: number, bulletId: string)
	notifyFireAcceptedEvent:FireAllClients(playerId, fireTime, spawnPos, shotDir, serverTime, bulletId)
end

function NetMsg.ConnectNotifyFireAccepted(callback: (playerId: number, fireTime: number, spawnPos: Vector3, shotDir: Vector3, serverTime: number, bulletId: string) -> ())
	notifyFireAcceptedEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyHit(targetPlayerId: number, fromPlayerId: number, hitDirection: Vector3, hitCount: number, bulletId: string, hitPosition: Vector3)
	notifyHitEvent:FireAllClients(targetPlayerId, fromPlayerId, hitDirection, hitCount, bulletId, hitPosition)
end

function NetMsg.ConnectNotifyHit(callback: (targetPlayerId: number, fromPlayerId: number, hitDirection: Vector3, hitCount: number, bulletId: string, hitPosition: Vector3) -> ())
	notifyHitEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyHpChanged(playerId: number, hitCount: number, maxHits: number)
	notifyHpChangedEvent:FireAllClients(playerId, hitCount, maxHits)
end

function NetMsg.ConnectNotifyHpChanged(callback: (playerId: number, hitCount: number, maxHits: number) -> ())
	notifyHpChangedEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyDead(playerId: number)
	notifyDeadEvent:FireAllClients(playerId)
end

function NetMsg.ConnectNotifyDead(callback: (playerId: number) -> ())
	notifyDeadEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyRoundOutcome(endReason: GameConfig.RoundEndReason, aliveUserIds: { number })
	notifyRoundOutcomeEvent:FireAllClients(endReason, aliveUserIds)
end

function NetMsg.ConnectNotifyRoundOutcome(callback: (endReason: GameConfig.RoundEndReason, aliveUserIds: { number }) -> ())
	notifyRoundOutcomeEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyMatchState(matchState: GameConfig.MatchState, countdown: number)
	notifyMatchStateEvent:FireAllClients(matchState, countdown)
end

function NetMsg.ConnectNotifyMatchState(callback: (matchState: GameConfig.MatchState, countdown: number) -> ())
	notifyMatchStateEvent.OnClientEvent:Connect(callback)
end

-- 本局竞技场入座前：仅通知本局参与者，客户端应先禁止跳跃再等待服务端入座
function NetMsg.FireNotifyArenaSeatPrepare(participantPlayers: { Player })
	for _, p in participantPlayers do
		notifyArenaSeatPrepareEvent:FireClient(p)
	end
end

function NetMsg.ConnectNotifyArenaSeatPrepare(callback: () -> ())
	notifyArenaSeatPrepareEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyTeleport(playerId: number, targetPosition: Vector3)
	notifyTeleportEvent:FireAllClients(playerId, targetPosition)
end

function NetMsg.ConnectNotifyTeleport(callback: (playerId: number, targetPosition: Vector3) -> ())
	notifyTeleportEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyGameConfigSync(overrides: { [string]: any })
	notifyGameConfigSyncEvent:FireAllClients(overrides)
end

function NetMsg.ConnectNotifyGameConfigSync(callback: (overrides: { [string]: any }) -> ())
	notifyGameConfigSyncEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyPendingConfigSync(overrides: { [string]: any })
	notifyPendingConfigSyncEvent:FireAllClients(overrides)
end

function NetMsg.ConnectNotifyPendingConfigSync(callback: (overrides: { [string]: any }) -> ())
	notifyPendingConfigSyncEvent.OnClientEvent:Connect(callback)
end

return NetMsg
