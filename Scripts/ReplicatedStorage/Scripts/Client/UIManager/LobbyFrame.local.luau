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
local isLocalParticipant = false
local isLocalDead = false
local matchState: GameConfig.MatchState = "InLobby"

local function IsAfkButtonHiddenByBattleState(): boolean
	local isBattleState = (matchState == "GameStartCountdown" or matchState == "Fighting")
	return isBattleState and isLocalParticipant and not isLocalDead
end

--刷新载具红点
local function RefreshVehiclesRedPoint()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		vehiclesRedPoint.Visible = false
		return
	end

	local hasAffordableNew = false
	local coinAmount: number = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0

	for _, vehicleData in pairs(GameConfig.VehicleDataMap) do
		local vehicleIdStr = tostring(vehicleData.id)
		local isOwned = localPlayerInfo.vehicleInventory.ownedList[vehicleIdStr]
		
		if not isOwned then
			-- 如果是金币购买且钱够，则显示红点
			if vehicleData.costType == GameConfig.CurrencyType.Coin and coinAmount >= vehicleData.cost then
				hasAffordableNew = true
				break
			end
		end
	end

	vehiclesRedPoint.Visible = hasAffordableNew
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
	isLocalParticipant = unitInitInfo.isParticipant == true
	if isLocalParticipant then
		isLocalDead = false
	end
	RefreshAfkButton()
end

local function OnNotifyDead(playerId: number, _killerId: number?)
	if playerId ~= localPlayerId then
		return
	end
	isLocalDead = true
	RefreshAfkButton()
end

local function OnNotifyUnitRemove(playerId: number)
	if playerId ~= localPlayerId then
		return
	end
	isLocalParticipant = false
	isLocalDead = false
	RefreshAfkButton()
end

local function OnNotifyMatchState(newMatchState: GameConfig.MatchState, _countdown: number)
	matchState = newMatchState
	if newMatchState == "InLobby" or newMatchState == "MatchCountdown" then
		isLocalDead = false
	end
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
