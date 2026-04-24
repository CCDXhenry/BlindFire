--!strict
local GroupRewardClientManager = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players: Players = game:GetService("Players")
local runService: RunService = game:GetService("RunService")

local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local TranslationTool = require(coreClientScripts:FindFirstChild("TranslationTool"))
local SoundTool = require(coreSharedScripts:FindFirstChild("SoundTool"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local GameTexts = require(sharedScripts:FindFirstChild("GameTexts"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))
local BillboardManager = require(clientScripts:FindFirstChild("BillboardManager"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

-- 常量定义
local ROTATION_SPEED = math.rad(30) -- 每秒旋转角度
local HOVER_AMPLITUDE = 0.4 -- 漂浮振幅
local HOVER_SPEED = 2 -- 漂浮速度
local HINT_DISTANCE = 10 -- 靠近提示距离
local SUCCESS_COLOR = Color3.fromRGB(0, 255, 0) -- 成功提示颜色（绿色）

-- 变量声明
local groupRewardModel: Model?
local vehicleModel: Model?
local rootPart: Part?
local billboardGui: BillboardGui?
local originModelCFrame: CFrame?
local hasShownHint: boolean = false
local hasShownSuccessTip: boolean = false

-- 刷新提示文字
local function RefreshTipText()
	if not billboardGui then
		return
	end

	local controllerFrame = billboardGui:FindFirstChild("ControllerFrame")
	if not controllerFrame then
		return
	end

	local tipText1 = controllerFrame:FindFirstChild("TipText1") :: TextLabel?
	local tipText2 = controllerFrame:FindFirstChild("TipText2") :: TextLabel?
	local tipText3 = controllerFrame:FindFirstChild("TipText3") :: TextLabel?

	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	local hasClaimed = if localPlayerInfo then localPlayerInfo.hasClaimedGroupReward else false

	if tipText1 and tipText2 and tipText3 then
		if hasClaimed then
			tipText1.Visible = false
			tipText3.Visible = false
			TranslationTool.CustomAutoLocalizeTextLabel(tipText2, GameTexts.GroupRewardTipClaimed.source, GameTexts.GroupRewardTipClaimed.key)
		else
			tipText1.Visible = true
			tipText3.Visible = true
			TranslationTool.CustomAutoLocalizeTextLabel(tipText1, GameTexts.GroupRewardTip1.source, GameTexts.GroupRewardTip1.key)
			TranslationTool.CustomAutoLocalizeTextLabel(tipText2, GameTexts.GroupRewardTip2.source, GameTexts.GroupRewardTip2.key)
			TranslationTool.CustomAutoLocalizeTextLabel(tipText3, GameTexts.GroupRewardTip3.source, GameTexts.GroupRewardTip3.key)
		end
	end
end

-- 播放获得提示
local function PlayClaimSuccessHint()
	if hasShownSuccessTip then
		return
	end
	hasShownSuccessTip = true

	-- 显示绿色停留提示
	ClientMsg.FireShowGameTip(
		GameTexts.GroupRewardClaimSuccess.source,
		GameConfig.GameTipTweenType.StayFlyUp,
		GameTexts.GroupRewardClaimSuccess.key,
		nil,
		SUCCESS_COLOR
	)

	-- 播放获得音效
	local soundFolder = replicatedStorage:FindFirstChild("Sounds")
	local getCoinSound = if soundFolder then soundFolder:FindFirstChild("GetCoinSound") :: Sound? else nil
	if getCoinSound then
		SoundTool.PlayGlobalSoundEffect(getCoinSound, false)
	end
end

-- 检查并弹出成功提示（仅用于刚刚上线的玩家，如果已经领取过则静默刷新 UI）
local function CheckAndShowSuccessTip()
	local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo and localPlayerInfo.hasClaimedGroupReward then
		RefreshTipText()
	end
end

-- 靠近提示与自动领取逻辑
local function UpdateHint(deltaTime: number)
	if not rootPart or not players.LocalPlayer.Character then
		return
	end
	local char = players.LocalPlayer.Character
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local dist = (hrp.Position - rootPart.Position).Magnitude
	if dist < HINT_DISTANCE then
		if not hasShownHint then
			local localPlayerInfo = ClientGameInfo.GetLocalPlayerInfo()
			if localPlayerInfo and not localPlayerInfo.hasClaimedGroupReward then
				-- 尝试检测群组状态
				task.spawn(function()
					local success, isInGroup = pcall(function()
						return players.LocalPlayer:IsInGroupAsync(GameConfig.SixcubeGroupId)
					end)

					if success and isInGroup then
						-- 在群组中且未领取，发送请求领取
						NetMsg.FireRequestClaimGroupReward(true)
						-- 这里先不等服务器同步，直接给一个正面反馈
						PlayClaimSuccessHint()
					else
						-- 确实不在群组，显示加入提示
						ClientMsg.FireShowGameTip(GameTexts.GroupRewardJoinHint.source, GameConfig.GameTipTweenType.FlyUp, GameTexts.GroupRewardJoinHint.key)
					end
				end)
			end
			hasShownHint = true
		end
	else
		hasShownHint = false
	end
end

-- 模型漂浮旋转动画
local function AnimateVehicleModel(deltaTime: number)
	if not (vehicleModel and originModelCFrame) then
		return
	end

	local t = os.clock()
	local steadyRotateCF = CFrame.Angles(0, t * ROTATION_SPEED, 0)
	local hoverHeight = math.sin(t * HOVER_SPEED) * HOVER_AMPLITUDE

	vehicleModel:PivotTo(originModelCFrame * CFrame.new(0, hoverHeight, 0) * steadyRotateCF)
end

local function OnRenderStepped(deltaTime: number)
	AnimateVehicleModel(deltaTime)
	UpdateHint(deltaTime)
end

-- 初始化展示模型
local function InitDisplayModel()
	if not groupRewardModel then
		return
	end

	local rewardVehicleId = GameConfig.GroupRewardVehicleId
	local vehicleData = GameConfig.VehicleDataMap[rewardVehicleId]
	if not vehicleData then
		return
	end

	local vehiclesFolder = replicatedStorage:WaitForChild("Models"):WaitForChild("Vehicles")
	local sourceModel = vehiclesFolder:FindFirstChild(vehicleData.resourceName) :: Model?
	if not sourceModel then
		warn("[GroupRewardClientManager] Source model not found for display:", vehicleData.resourceName)
		return
	end

	if vehicleModel then
		local oldPivot = vehicleModel:GetPivot()
		local newModel = sourceModel:Clone()
		newModel.Name = "VehicleModel"
		newModel.Parent = groupRewardModel
		newModel:PivotTo(oldPivot)

		vehicleModel:Destroy()
		vehicleModel = newModel
		originModelCFrame = oldPivot

		-- 锚固 Seat 并禁用
		for _, desc in ipairs(vehicleModel:GetDescendants()) do
			if desc:IsA("Seat") or desc:IsA("VehicleSeat") then
				desc.Disabled = true
				desc.Anchored = true
			end
		end
	end
end

-- 初始化函数
function GroupRewardClientManager.Init()
	groupRewardModel = workspace:FindFirstChild("GroupRewardModel") :: Model?
	if not groupRewardModel then
		return
	end

	vehicleModel = groupRewardModel:FindFirstChild("VehicleModel") :: Model?
	rootPart = groupRewardModel:FindFirstChild("RootPart") :: Part?

	-- 寻找指定的 Gui 路径
	if rootPart then
		local guiAttachment = rootPart:FindFirstChild("GuiAttachment")
		if guiAttachment then
			billboardGui = guiAttachment:FindFirstChild("Gui") :: BillboardGui?
		end
	end

	-- 初始化展示模型（从资源库替换）
	InitDisplayModel()

	if billboardGui then
		BillboardManager.Track(billboardGui)
	end

	RefreshTipText()

	runService:BindToRenderStep("GroupRewardClientManager.RenderStepped", Enum.RenderPriority.Camera.Value + 1, OnRenderStepped)

	ClientMsg.ConnectLocalPlayerInfoInit(function()
		RefreshTipText()
		CheckAndShowSuccessTip()
	end)

	ClientMsg.ConnectLocalPlayerClaimedGroupReward(function()
		print("[GroupRewardClientManager] OnLocalPlayerClaimedGroupReward")
		RefreshTipText()
	end)
end

return GroupRewardClientManager
