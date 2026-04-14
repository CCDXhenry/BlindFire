--!strict
local ClientMsg = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local bindableEventsFolder: Folder = replicatedStorage:FindFirstChild("BindableEvents") :: Folder
local closeWindowEvent: BindableEvent = bindableEventsFolder:FindFirstChild("CloseWindow") :: BindableEvent
local localPlayerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerInfoInit") :: BindableEvent
local otherPlayerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("OtherPlayerInfoInit") :: BindableEvent
local localPlayerAcquiredGamePassEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerAcquiredGamePass") :: BindableEvent

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

return ClientMsg