--!strict
local ClientMsg = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local bindableEventsFolder: Folder = replicatedStorage:FindFirstChild("BindableEvents") :: Folder
local closeWindowEvent: BindableEvent = bindableEventsFolder:FindFirstChild("CloseWindow") :: BindableEvent
local localPlayerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerInfoInit") :: BindableEvent
local otherPlayerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("OtherPlayerInfoInit") :: BindableEvent
local localPlayerAcquiredGamePassEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerAcquiredGamePass") :: BindableEvent

local showTopTipTextEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowTopTipText") :: BindableEvent
local showGameTipEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowGameTip") :: BindableEvent
local showAddRewardsTipEvent: BindableEvent = bindableEventsFolder:FindFirstChild("ShowAddRewardsTip") :: BindableEvent
--关闭窗口事件
function ClientMsg.FireCloseWindow(windowName: string)
	closeWindowEvent:Fire(windowName)
end

function ClientMsg.ConnectCloseWindow(callback: (windowName: string) -> ())
	closeWindowEvent.Event:Connect(callback)
end

--自己的玩家信息初始化事件
function ClientMsg.FireLocalPlayerInfoInit()
	localPlayerInfoInitEvent:Fire()
end

function ClientMsg.ConnectLocalPlayerInfoInit(callback: () -> ())
	localPlayerInfoInitEvent.Event:Connect(callback)
end

--其他玩家的信息初始化事件
function ClientMsg.FireOtherPlayerInfoInit(playerId: number)
	otherPlayerInfoInitEvent:Fire(playerId)
end

function ClientMsg.ConnectOtherPlayerInfoInit(callback: (playerId: number) -> ())
	otherPlayerInfoInitEvent.Event:Connect(callback)
end

--自己获得了通行证
function ClientMsg.FireLocalPlayerAcquiredGamePass(gamePassId: number)
	localPlayerAcquiredGamePassEvent:Fire(gamePassId)
end

function ClientMsg.ConnectLocalPlayerAcquiredGamePass(callback: (gamePassId: number) -> ())
	localPlayerAcquiredGamePassEvent.Event:Connect(callback)
end

--显示游戏提示
function ClientMsg.FireShowGameTip(tipContentSource: string, tweenType: number, tipContentKey: string?, tipContentArgs: {string}?, textColor: Color3?)
	showGameTipEvent:Fire(tipContentSource, tweenType, tipContentKey, tipContentArgs, textColor)
end

function ClientMsg.ConnectShowGameTip(callback: (tipContentSource: string, tweenType: number,
	tipContentKey: string?, tipContentArgs: {string}?, textColor: Color3?) -> ())
	showGameTipEvent.Event:Connect(callback)
end

--显示获得奖励提示
function ClientMsg.FireShowAddRewardsTip(rewardInfoList: {GameConfig.RewardInfo})
	showAddRewardsTipEvent:Fire(rewardInfoList)
end

function ClientMsg.ConnectShowAddRewardsTip(callback: (rewardInfoList: {GameConfig.RewardInfo}) -> ())
	showAddRewardsTipEvent.Event:Connect(callback)
end

--显示头顶UI提示
function ClientMsg.FireShowTopTipText(textSource: string, color: Color3, duration: number, args: {string}?, key: string?)
	showTopTipTextEvent:Fire(textSource, color, duration, args, key)
end

function ClientMsg.ConnectShowTopTipText(callback: (textSource: string, color: Color3, duration: number, args: {string}?, key: string?) -> ())
	showTopTipTextEvent.Event:Connect(callback)
end
return ClientMsg