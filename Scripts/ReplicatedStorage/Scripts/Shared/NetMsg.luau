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
local notifyPlayerCurrencyUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerCurrencyUpdate") :: RemoteEvent
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
local notifyImpactEvent: RemoteEvent? = remoteEventsFolder:FindFirstChild("NotifyImpact") :: RemoteEvent?
local notifyMatchStateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyMatchState") :: RemoteEvent
local notifyTeleportEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyTeleport") :: RemoteEvent
local notifyArenaSeatPrepareEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyArenaSeatPrepare") :: RemoteEvent
local notifyGameConfigSyncEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyGameConfigSync") :: RemoteEvent
local notifyPendingConfigSyncEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPendingConfigSync") :: RemoteEvent
local requestSyncUnitEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSyncUnit") :: RemoteEvent
local requestSetAfkStateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetAfkState") :: RemoteEvent
local requestSyncAfkStateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSyncAfkState") :: RemoteEvent
local notifyAfkStateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyAfkState") :: RemoteEvent
local requestBuyVehicleEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestBuyVehicle") :: RemoteEvent
local requestUpdateVehicleUsingEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestUpdateVehicleUsing") :: RemoteEvent
local notifyPlayerVehicleInventoryUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerVehicleInventoryUpdate") :: RemoteEvent
local notifyLeaderboardUpdateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyLeaderboardUpdate") :: RemoteEvent
local notifyLeaderboardResetTimeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyLeaderboardResetTime") :: RemoteEvent
local requestClaimGroupRewardEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestClaimGroupReward") :: RemoteEvent
local notifyPlayerClaimedGroupRewardEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerClaimedGroupReward") :: RemoteEvent

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

--通知客户端玩家货币更新
function NetMsg.FireNotifyPlayerCurrencyUpdate(player: Player, currencyType: number, totalAmount: number, changeAmount: number, reason: number)
	notifyPlayerCurrencyUpdateEvent:FireClient(player, currencyType, totalAmount, changeAmount, reason)
end

function NetMsg.ConnectNotifyPlayerCurrencyUpdate(callback: (currencyType: number, totalAmount: number, changeAmount: number, reason: number) -> ())
	notifyPlayerCurrencyUpdateEvent.OnClientEvent:Connect(callback)
end

-- ============================================================
-- Demo 玩法通信封装
-- ============================================================

--客户端请求开火
function NetMsg.FireRequestFire(clientTimestamp: number, bulletId: string)
	requestFireEvent:FireServer(clientTimestamp, bulletId)
end

function NetMsg.ConnectRequestFire(callback: (player: Player, clientTimestamp: number, bulletId: string) -> ())
	requestFireEvent.OnServerEvent:Connect(callback)
end

--客户端请求同步单位状态
function NetMsg.FireRequestSyncUnit()
	requestSyncUnitEvent:FireServer()
end

function NetMsg.ConnectRequestSyncUnit(callback: (player: Player) -> ())
	requestSyncUnitEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求切换 AFK 状态
function NetMsg.FireRequestSetAfkState(isAfk: boolean)
	requestSetAfkStateEvent:FireServer(isAfk)
end

function NetMsg.ConnectRequestSetAfkState(callback: (player: Player, isAfk: boolean) -> ())
	requestSetAfkStateEvent.OnServerEvent:Connect(callback)
end

-- 客户端请求同步 AFK 状态
function NetMsg.FireRequestSyncAfkState()
	requestSyncAfkStateEvent:FireServer()
end

function NetMsg.ConnectRequestSyncAfkState(callback: (player: Player) -> ())
	requestSyncAfkStateEvent.OnServerEvent:Connect(callback)
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

function NetMsg.FireNotifyHpChangedToPlayer(player: Player, playerId: number, hitCount: number, maxHits: number)
	notifyHpChangedEvent:FireClient(player, playerId, hitCount, maxHits)
end

function NetMsg.ConnectNotifyHpChanged(callback: (playerId: number, hitCount: number, maxHits: number) -> ())
	notifyHpChangedEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyDead(playerId: number, killerId: number?)
	notifyDeadEvent:FireAllClients(playerId, killerId)
end

function NetMsg.ConnectNotifyDead(callback: (playerId: number, killerId: number?) -> ())
	notifyDeadEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyRoundOutcome(endReason: GameConfig.RoundEndReason, aliveUserIds: { number })
	notifyRoundOutcomeEvent:FireAllClients(endReason, aliveUserIds)
end

function NetMsg.ConnectNotifyRoundOutcome(callback: (endReason: GameConfig.RoundEndReason, aliveUserIds: { number }) -> ())
	notifyRoundOutcomeEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyImpact(hitPosition: Vector3)
	if notifyImpactEvent == nil then
		return
	end
	notifyImpactEvent:FireAllClients(hitPosition)
end

function NetMsg.ConnectNotifyImpact(callback: (hitPosition: Vector3) -> ())
	if notifyImpactEvent == nil then
		return
	end
	notifyImpactEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyMatchState(matchState: GameConfig.MatchState, countdown: number)
	notifyMatchStateEvent:FireAllClients(matchState, countdown)
end

function NetMsg.ConnectNotifyMatchState(callback: (matchState: GameConfig.MatchState, countdown: number) -> ())
	notifyMatchStateEvent.OnClientEvent:Connect(callback)
end

-- 通知 AFK 状态变化
function NetMsg.FireNotifyAfkState(playerId: number, isAfk: boolean)
	notifyAfkStateEvent:FireAllClients(playerId, isAfk)
end

function NetMsg.FireNotifyAfkStateToPlayer(player: Player, playerId: number, isAfk: boolean)
	notifyAfkStateEvent:FireClient(player, playerId, isAfk)
end

function NetMsg.ConnectNotifyAfkState(callback: (playerId: number, isAfk: boolean) -> ())
	notifyAfkStateEvent.OnClientEvent:Connect(callback)
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

--客户端请求购买载具
function NetMsg.FireRequestBuyVehicle(vehicleId: number)
	requestBuyVehicleEvent:FireServer(vehicleId)
end

function NetMsg.ConnectRequestBuyVehicle(callback: (player: Player, vehicleId: number) -> ())
	requestBuyVehicleEvent.OnServerEvent:Connect(callback)
end

--客户端请求更新当前使用的载具
function NetMsg.FireRequestUpdateVehicleUsing(vehicleId: number)
	requestUpdateVehicleUsingEvent:FireServer(vehicleId)
end

function NetMsg.ConnectRequestUpdateVehicleUsing(callback: (player: Player, vehicleId: number) -> ())
	requestUpdateVehicleUsingEvent.OnServerEvent:Connect(callback)
end

--通知客户端玩家载具仓库更新
function NetMsg.FireNotifyPlayerVehicleInventoryUpdate(player: Player, vehicleInventory: GameConfig.VehicleInventory)
	notifyPlayerVehicleInventoryUpdateEvent:FireClient(player, vehicleInventory)
end

function NetMsg.ConnectNotifyPlayerVehicleInventoryUpdate(callback: (vehicleInventory: GameConfig.VehicleInventory) -> ())
	notifyPlayerVehicleInventoryUpdateEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyLeaderboardUpdate(player: Player?, category: string, topList: { { userId: number, value: number, name: string } }, resetTimestamp: number)
	if player then
		notifyLeaderboardUpdateEvent:FireClient(player, category, topList, resetTimestamp)
	else
		notifyLeaderboardUpdateEvent:FireAllClients(category, topList, resetTimestamp)
	end
end

function NetMsg.ConnectNotifyLeaderboardUpdate(callback: (category: string, topList: { { userId: number, value: number, name: string } }, resetTimestamp: number) -> ())
	notifyLeaderboardUpdateEvent.OnClientEvent:Connect(callback)
end

function NetMsg.FireNotifyLeaderboardResetTime(player: Player?, resetTimestamp: number)
	if player then
		notifyLeaderboardResetTimeEvent:FireClient(player, resetTimestamp)
	else
		notifyLeaderboardResetTimeEvent:FireAllClients(resetTimestamp)
	end
end

function NetMsg.ConnectNotifyLeaderboardResetTime(callback: (resetTimestamp: number) -> ())
	notifyLeaderboardResetTimeEvent.OnClientEvent:Connect(callback)
end

--客户端请求领取群组奖励
function NetMsg.FireRequestClaimGroupReward(isInGroup: boolean)
	requestClaimGroupRewardEvent:FireServer(isInGroup)
end

function NetMsg.ConnectRequestClaimGroupReward(callback: (player: Player, isInGroup: boolean) -> ())
	requestClaimGroupRewardEvent.OnServerEvent:Connect(callback)
end

--通知客户端领取群组奖励成功
function NetMsg.FireNotifyPlayerClaimedGroupReward(player: Player)
	notifyPlayerClaimedGroupRewardEvent:FireClient(player)
end

function NetMsg.ConnectNotifyPlayerClaimedGroupReward(callback: () -> ())
	notifyPlayerClaimedGroupRewardEvent.OnClientEvent:Connect(callback)
end

return NetMsg
