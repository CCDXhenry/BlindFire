--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local scriptsFolder = core:WaitForChild("Scripts")
local sharedScripts = scriptsFolder:WaitForChild("Shared")
local NumberExtension = require(sharedScripts:FindFirstChild("NumberExtension"))
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts_game = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts_game:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts_game:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local uiManagerScript = clientScripts:WaitForChild("UIManager")
local UIManager = require(uiManagerScript)
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local TranslationTool = require(core:WaitForChild("Scripts"):WaitForChild("Client"):FindFirstChild("TranslationTool"))
local GameTexts = require(sharedScripts_game:FindFirstChild("GameTexts"))
local userInputService = game:GetService("UserInputService")
local tweenService: TweenService = game:GetService("TweenService")

local lobbyFrame: Frame = script.Parent
local coinFrame: Frame = lobbyFrame:FindFirstChild("CoinFrame") :: Frame
local coinCountText: TextLabel = coinFrame:FindFirstChild("CoinCountText") :: TextLabel
local guideText: TextLabel = lobbyFrame:FindFirstChild("GuideText") :: TextLabel
guideText.Visible = false
local mainGuideText: LocalScript = uiManagerScript:FindFirstChild("MainGuideText") :: LocalScript
local guideTextScript: LocalScript = mainGuideText:Clone()
guideTextScript.Parent = guideText

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
end

local function RefreshView()
	RefreshCoinCountText()
end

local function OnLocalPlayerInfoInit()
	RefreshView()
end

UIAdapter.AddAdaptiveFrame(lobbyFrame, UIAdapter.AdaptiveType.FullScreen)

RefreshView()

ClientMsg.ConnectLocalPlayerCurrencyUpdate(OnLocalPlayerCurrencyUpdate)
ClientMsg.ConnectLocalPlayerInfoInit(OnLocalPlayerInfoInit)
