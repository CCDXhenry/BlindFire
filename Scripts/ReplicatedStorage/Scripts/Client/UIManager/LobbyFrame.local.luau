--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
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
local AFK_LOCK_COUNTDOWN_THRESHOLD_SEC = 3

local isAfk = false
local matchState: GameConfig.MatchState = GameConfig.MatchState.InLobby
local matchCountdownRemainSec = 0
local matchPhaseEndClock = 0

local function IsVehicleAffordable(localPlayerInfo: GameConfig.ClientLocalPlayerInfo, vehicleData: GameConfig.VehicleData): boolean
	local coinAmount: number = localPlayerInfo.currencies[tostring(GameConfig.CurrencyType.Coin)] or 0

	if vehicleData.costType == GameConfig.CostType.Coin then
		return coinAmount >= vehicleData.costCoin
	elseif vehicleData.costType == GameConfig.CostType.CoinOrRb then
		return coinAmount >= vehicleData.costCoin
	end

	return false
end

local function GetCheapestAffordableUnownedVehicleId(localPlayerInfo: GameConfig.ClientLocalPlayerInfo): number?
	local cheapestVehicleData: GameConfig.VehicleData? = nil
	local cheapestVehicleId: number? = nil

	for vehicleId, vehicleData in pairs(GameConfig.VehicleDataMap) do
		local isOwned = localPlayerInfo.vehicleInventory.ownedList[tostring(vehicleId)] == true
		if not isOwned and IsVehicleAffordable(localPlayerInfo, vehicleData) then
			if cheapestVehicleData == nil then
				cheapestVehicleData = vehicleData
				cheapestVehicleId = vehicleId
			else
				local isCheaper = vehicleData.costCoin < cheapestVehicleData.costCoin
				local isSameCostBetterSort = vehicleData.costCoin == cheapestVehicleData.costCoin
					and vehicleData.sortId < cheapestVehicleData.sortId
				local isSameCostSameSortBetterId = vehicleData.costCoin == cheapestVehicleData.costCoin
					and vehicleData.sortId == cheapestVehicleData.sortId
					and vehicleId < (cheapestVehicleId :: number)
				if isCheaper or isSameCostBetterSort or isSameCostSameSortBetterId then
					cheapestVehicleData = vehicleData
					cheapestVehicleId = vehicleId
				end
			end
		end
	end

	return cheapestVehicleId
end

local function IsAfkButtonHiddenByBattleState(): boolean
	local isBattleState = (matchState == GameConfig.MatchState.GameStartCountdown or matchState == GameConfig.MatchState.Fighting)
	if not isBattleState then
		return false
	end
	return BulletClientManager.IsLocalInVehicle()
end

local function IsAfkToggleLockedByMatchCountdown(): boolean
	return matchState == GameConfig.MatchState.MatchCountdown
		and matchCountdownRemainSec <= AFK_LOCK_COUNTDOWN_THRESHOLD_SEC
end

--刷新载具红点
local function RefreshVehiclesRedPoint()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if not localPlayerInfo then
		vehiclesRedPoint.Visible = false
		return
	end

	vehiclesRedPoint.Visible = GetCheapestAffordableUnownedVehicleId(localPlayerInfo) ~= nil
end

local function RefreshAfkButton()
	local isAfkToggleLocked = IsAfkToggleLockedByMatchCountdown()
	local isAfkButtonVisible = (not IsAfkButtonHiddenByBattleState()) and (not isAfkToggleLocked)
	afkButton.Visible = isAfkButtonVisible
	afkButton.Active = isAfkButtonVisible
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

local function OnHeartbeat()
	if matchState ~= GameConfig.MatchState.MatchCountdown then
		return
	end
	local nextRemainSec = math.max(math.floor(matchPhaseEndClock - os.clock() + 1e-4), 0)
	if nextRemainSec == matchCountdownRemainSec then
		return
	end
	matchCountdownRemainSec = nextRemainSec
	RefreshAfkButton()
end

local function OnLocalPlayerInfoInit()
	RefreshView()
end

local function TryToggleAfk()
	if not afkButton.Visible then
		return
	end
	if IsAfkToggleLockedByMatchCountdown() then
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

local function OnNotifyDead(playerId: number, _killerId: number?, _deadServerTime: number, _adaptiveDelaySec: number)
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

local function OnNotifyMatchState(newMatchState: GameConfig.MatchState, countdown: number)
	matchState = newMatchState
	matchPhaseEndClock = os.clock() + countdown
	if newMatchState == GameConfig.MatchState.MatchCountdown then
		matchCountdownRemainSec = math.max(countdown, 0)
	else
		matchCountdownRemainSec = 0
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
	runService.Heartbeat:Connect(OnHeartbeat)
end

InitUI()
InitEvents()
RefreshView()
NetMsg.FireRequestSyncAfkState()
