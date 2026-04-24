--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local userInputService = game:GetService("UserInputService")

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local NumberExtension = require(coreSharedScripts:FindFirstChild("NumberExtension"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local uiManagerScript = clientScripts:WaitForChild("UIManager")
local UIManager = require(uiManagerScript)
local BulletClientManager = require(clientScripts:FindFirstChild("BulletClientManager"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local localPlayer = players.LocalPlayer
local localPlayerId = localPlayer.UserId
local lobbyFrame: Frame = script.Parent
local coinFrame: Frame = lobbyFrame:FindFirstChild("CoinFrame") :: Frame
local coinCountText: TextLabel = coinFrame:FindFirstChild("CoinCountText") :: TextLabel
local guideText: TextLabel = lobbyFrame:FindFirstChild("GuideText") :: TextLabel
guideText.Visible = false
local mainGuideText: LocalScript = uiManagerScript:FindFirstChild("MainGuideText") :: LocalScript
local guideTextScript: LocalScript = mainGuideText:Clone()
guideTextScript.Parent = guideText

local vehiclesButton: ImageButton = lobbyFrame:FindFirstChild("VehiclesButton") :: ImageButton
local vehiclesRedPoint: ImageLabel = vehiclesButton:FindFirstChild("VehiclesRedPoint") :: ImageLabel
local afkButton: ImageButton = lobbyFrame:WaitForChild("AFKButton") :: ImageButton
local afkButtonTextLabel: TextLabel = afkButton:WaitForChild("TextLabel") :: TextLabel

local AFK_OFF_COLOR = Color3.fromRGB(220, 60, 60)
local AFK_ON_COLOR = Color3.fromRGB(60, 180, 75)

local isAfk = false
local matchState: GameConfig.MatchState = "InLobby"

local function IsVehicleAffordable(localPlayerInfo: GameConfig.ClientLocalPlayerInfo, vehicleData: GameConfig.VehicleData): boolean
	local coinAmount: number = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
	local rbAmount: number = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Rb)] or 0
	local rbCost = vehicleData.costRb or vehicleData.costCoin

	if vehicleData.costType == GameConfig.CostType.Coin then
		return coinAmount >= vehicleData.costCoin
	elseif vehicleData.costType == GameConfig.CostType.Rb then
		return rbAmount >= vehicleData.costCoin
	elseif vehicleData.costType == GameConfig.CostType.CoinOrRb then
		return coinAmount >= vehicleData.costCoin or rbAmount >= rbCost
	end

	return false
end

local function IsAfkButtonHiddenByBattleState(): boolean
	local isBattleState = (matchState == "GameStartCountdown" or matchState == "Fighting")
	if not isBattleState then
		return false
	end
	return BulletClientManager.IsLocalInVehicle()
end

--刷新载具红点
local function RefreshVehiclesRedPoint()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		vehiclesRedPoint.Visible = false
		return
	end

	local maxOwnedId = 0
	for idStr, owned in pairs(localPlayerInfo.vehicleInventory.ownedList) do
		if owned then
			local id = tonumber(idStr)
			if id and id > maxOwnedId then
				maxOwnedId = id
			end
		end
	end

	local hasAffordableBetter = false
	for _, vehicleData in pairs(GameConfig.VehicleDataMap) do
		-- 只考虑比当前最强车更强的载具
		if vehicleData.id > maxOwnedId then
			local isOwned = localPlayerInfo.vehicleInventory.ownedList[tostring(vehicleData.id)]
			
			if not isOwned then
				-- 红点只算能够金币购买且金币数量足够的
				if vehicleData.costType == GameConfig.CostType.Coin or vehicleData.costType == GameConfig.CostType.CoinOrRb then
					local coinAmount: number = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
					if coinAmount >= vehicleData.costCoin then
						hasAffordableBetter = true
						break
					end
				end
			end
		end
	end

	vehiclesRedPoint.Visible = hasAffordableBetter
end

local function RefreshAfkButton()
	afkButton.Visible = not IsAfkButtonHiddenByBattleState()
	local afkTextInfo = if isAfk then GameTexts.AfkOn else GameTexts.AfkOff
	TranslationTool.CustomAutoLocalizeTextLabel(afkButtonTextLabel, afkTextInfo.source, afkTextInfo.key, nil)
	afkButton.Image = if isAfk then GameConfig.AFKOnImage else GameConfig.AFKOffImage
end

--刷新金币数量
local function RefreshCoinCountText()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		return
	end
	local coinAmount: number = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0
	coinCountText.Text = NumberExtension.FormatBigNumberAA(coinAmount)
end

local function OnLocalPlayerCurrencyUpdate()
	RefreshCoinCountText()
	RefreshVehiclesRedPoint()
end

local function OnLocalPlayerVehicleInventoryUpdate()
	RefreshVehiclesRedPoint()
end

local function RefreshView()
	RefreshCoinCountText()
	RefreshVehiclesRedPoint()
	RefreshAfkButton()
end

local function OnLocalPlayerInfoInit()
	RefreshView()
end

local function TryToggleAfk()
	if not afkButton.Visible then
		return
	end
	NetMsg.FireRequestSetAfkState(not isAfk)
end

local function OnVehiclesButtonActivated()
	UIManager.OpenWindow(UIManager.WindowId.VehiclesShop)
end

local function OnAfkButtonActivated()
	TryToggleAfk()
end

local function OnInputBegan(inputObject: InputObject, processed: boolean)
	if processed then
		return
	end
	if inputObject.KeyCode ~= Enum.KeyCode.T then
		return
	end
	TryToggleAfk()
end

local function OnNotifyAfkState(playerId: number, newIsAfk: boolean)
	if playerId ~= localPlayerId then
		return
	end
	isAfk = newIsAfk
	RefreshAfkButton()
end

local function OnNotifyUnitInit(unitInitInfo: GameConfig.UnitInitInfo)
	if unitInitInfo.playerId ~= localPlayerId then
		return
	end
	RefreshAfkButton()
end

local function OnNotifyDead(playerId: number, _killerId: number?)
	if playerId ~= localPlayerId then
		return
	end
	RefreshAfkButton()
end

local function OnNotifyUnitRemove(playerId: number)
	if playerId ~= localPlayerId then
		return
	end
	RefreshAfkButton()
end

local function OnNotifyMatchState(newMatchState: GameConfig.MatchState, _countdown: number)
	matchState = newMatchState
	RefreshAfkButton()
end

local function InitUI()
	UIAdapter.AddAdaptiveFrame(lobbyFrame, UIAdapter.AdaptiveType.FullScreen)
end

local function InitEvents()
	vehiclesButton.Activated:Connect(OnVehiclesButtonActivated)
	afkButton.Activated:Connect(OnAfkButtonActivated)
	userInputService.InputBegan:Connect(OnInputBegan)
	ClientMsg.ConnectLocalPlayerCurrencyUpdate(OnLocalPlayerCurrencyUpdate)
	ClientMsg.ConnectLocalPlayerInfoInit(OnLocalPlayerInfoInit)
	ClientMsg.ConnectLocalPlayerVehicleInventoryUpdate(OnLocalPlayerVehicleInventoryUpdate)
	NetMsg.ConnectNotifyAfkState(OnNotifyAfkState)
	NetMsg.ConnectNotifyUnitInit(OnNotifyUnitInit)
	NetMsg.ConnectNotifyDead(OnNotifyDead)
	NetMsg.ConnectNotifyUnitRemove(OnNotifyUnitRemove)
	NetMsg.ConnectNotifyMatchState(OnNotifyMatchState)
end

InitUI()
InitEvents()
RefreshView()
NetMsg.FireRequestSyncAfkState()
