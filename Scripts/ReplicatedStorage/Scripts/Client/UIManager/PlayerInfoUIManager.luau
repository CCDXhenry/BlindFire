--!strict
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")

local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local BillboardManager = require(clientScripts:WaitForChild("BillboardManager"))
local BulletClientManager = require(clientScripts:WaitForChild("BulletClientManager"))

local playerInfoUITemplate = replicatedStorage:WaitForChild("UI"):WaitForChild("PlayerInfoUI") :: BillboardGui
local PlayerInfoUiTemplateStudsOffset: Vector3 = playerInfoUITemplate.StudsOffset

type PlayerInfoUIRecord = {
	ui: BillboardGui,
	isParticipant: boolean,
	vehicleId: number,
	fireRingCooldownText: TextLabel?,
	fireRingSegments: { Frame }?,
	fireRingWasCoolingDown: boolean,
	fireRingHighlightRemaining: number,
	lastFireRingActiveCount: number?,
	lastFireRingText: string?,
	lastFireRingReadyHighlighted: boolean?,
}

local PlayerInfoUIManager = {}

local playerUIMap: { [number]: PlayerInfoUIRecord } = {}
local connectionMap: { [number]: RBXScriptConnection } = {}
local lastDeadServerTimeMap: { [number]: number } = {}
local botMetaMap: { [string]: { name: string, isBot: boolean } } = {}
local isFighting = false

local SegmentNamePrefix = "SegmentFrame_"
local RingColorOn: Color3 = Color3.fromRGB(255, 170, 0)
local RingColorOff: Color3 = Color3.fromRGB(70, 70, 70)
local RingTransparencyOn: number = 0.05
local RingTransparencyOff: number = 0.35
local RingReadyColor: Color3 = Color3.fromRGB(60, 255, 120)
local RingHighlightColor: Color3 = Color3.fromRGB(170, 255, 190)
local RingHighlightDurationSeconds: number = 0.25
local FireRingUpdateIntervalSec: number = 1 / 20
local fireRingUpdateAccumSec: number = 0
local RealPlayerAdorneeRetryIntervalSec: number = 0.25
local RealPlayerAdorneeRetryLogIntervalSec: number = 2
local realPlayerAdorneeRetryAccumSec: number = 0

local RemoveUIForPlayer: (number) -> ()
local realPlayerAdorneeLastWarnClockMap: { [number]: number } = {}
local realPlayerAdorneePendingMap: { [number]: boolean } = {}

local function CollectFireRingSegmentFrames(fireCooldownFrame: Frame): { Frame }
	local segmentList: { Frame } = {}
	for _, child in fireCooldownFrame:GetChildren() do
		if child:IsA("Frame") and child.Name ~= "CenterMaskFrame" and string.sub(child.Name, 1, #SegmentNamePrefix) == SegmentNamePrefix then
			table.insert(segmentList, child)
		end
	end
	table.sort(segmentList, function(a, b)
		return a.Name < b.Name
	end)
	return segmentList
end

local function SetFireRingReadySegments(segmentList: { Frame }, useHighlight: boolean)
	local targetColor = if useHighlight then RingHighlightColor else RingReadyColor
	local targetTransparency = if useHighlight then 0 else RingTransparencyOn
	for _, segmentFrame in ipairs(segmentList) do
		segmentFrame.BackgroundColor3 = targetColor
		segmentFrame.BackgroundTransparency = targetTransparency
	end
end

local function UpdateLocalFireCooldownRingDisplay(deltaTime: number)
	local localPlayer = players.LocalPlayer
	local data = playerUIMap[localPlayer.UserId]
	if data == nil or data.fireRingSegments == nil or #data.fireRingSegments == 0 then
		return
	end

	local segmentList = data.fireRingSegments :: { Frame }
	local cooldownTextLabel = data.fireRingCooldownText
	local actualLeft = BulletClientManager.GetLocalFireCooldownLeft()
	local totalSeconds = math.max(BulletClientManager.GetLocalFireCooldownSeconds(), 0.001)
	local isCoolingDown = actualLeft > 0

	if cooldownTextLabel then
		local nextText = if isCoolingDown then string.format("%.1f", actualLeft) else ""
		if data.lastFireRingText ~= nextText then
			data.lastFireRingText = nextText
			cooldownTextLabel.Text = nextText
		end
	end

	local segmentCount = #segmentList
	if isCoolingDown then
		data.fireRingHighlightRemaining = 0
		local progress = 1 - (actualLeft / totalSeconds)
		progress = math.clamp(progress, 0, 1)
		local activeCount = math.floor(progress * segmentCount + 0.5)
		if data.lastFireRingActiveCount ~= activeCount or data.lastFireRingReadyHighlighted ~= nil then
			for index, segmentFrame in ipairs(segmentList) do
				local isLit = index <= activeCount
				segmentFrame.BackgroundColor3 = if isLit then RingColorOn else RingColorOff
				segmentFrame.BackgroundTransparency = if isLit then RingTransparencyOn else RingTransparencyOff
			end
			data.lastFireRingActiveCount = activeCount
			data.lastFireRingReadyHighlighted = nil
		end
		data.fireRingWasCoolingDown = true
	else
		if data.fireRingWasCoolingDown then
			data.fireRingHighlightRemaining = RingHighlightDurationSeconds
			data.fireRingWasCoolingDown = false
		end
		if data.fireRingHighlightRemaining > 0 then
			data.fireRingHighlightRemaining = math.max(data.fireRingHighlightRemaining - deltaTime, 0)
			if data.lastFireRingReadyHighlighted ~= true then
				SetFireRingReadySegments(segmentList, true)
				data.lastFireRingReadyHighlighted = true
				data.lastFireRingActiveCount = nil
			end
		else
			if data.lastFireRingReadyHighlighted ~= false then
				SetFireRingReadySegments(segmentList, false)
				data.lastFireRingReadyHighlighted = false
				data.lastFireRingActiveCount = nil
			end
		end
	end
end

local function ConfigureFireCooldownRing(playerId: number)
	local data = playerUIMap[playerId]
	if data == nil then
		return
	end

	local controllerFrame = data.ui:FindFirstChild("ControllerFrame")
	if controllerFrame == nil then
		return
	end
	local healthBar = controllerFrame:FindFirstChild("HealthBar")
	if healthBar == nil or not healthBar:IsA("GuiObject") then
		return
	end
	local fireCooldownFrame = healthBar:FindFirstChild("FireCooldownFrame") :: Frame?
	if fireCooldownFrame == nil then
		data.fireRingCooldownText = nil
		data.fireRingSegments = nil
		return
	end

	if playerId ~= players.LocalPlayer.UserId then
		fireCooldownFrame.Visible = false
		data.fireRingCooldownText = nil
		data.fireRingSegments = nil
		return
	end

	fireCooldownFrame.Visible = true

	local centerMaskFrame = fireCooldownFrame:FindFirstChild("CenterMaskFrame") :: Frame?
	local cooldownTextLabel: TextLabel? = nil
	if centerMaskFrame then
		local foundText = centerMaskFrame:FindFirstChild("CooldownText")
		if foundText and foundText:IsA("TextLabel") then
			cooldownTextLabel = foundText
		end
	end

	local segmentList = CollectFireRingSegmentFrames(fireCooldownFrame)
	data.fireRingCooldownText = cooldownTextLabel
	data.fireRingSegments = if #segmentList > 0 then segmentList else nil
	data.fireRingWasCoolingDown = false
	data.fireRingHighlightRemaining = 0
	data.lastFireRingActiveCount = nil
	data.lastFireRingText = nil
	data.lastFireRingReadyHighlighted = nil
end

local function UpdateHpUI(playerId: number, hitCount: number, maxHits: number)
	local data = playerUIMap[playerId]
	if data == nil then
		return
	end
	local ui = data.ui

	local controllerFrame = ui:FindFirstChild("ControllerFrame")
	if not controllerFrame then return end
	local healthBar = controllerFrame:FindFirstChild("HealthBar")
	if not healthBar then return end
	local scaleBar = healthBar:FindFirstChild("ScaleBar")
	if not scaleBar then return end
	local scaleFrame = scaleBar:FindFirstChild("Scale") :: Frame?
	local textLabel = healthBar:FindFirstChild("TextLabel") :: TextLabel?

	local currentHp = math.max(0, maxHits - hitCount)
	local ratio = currentHp / maxHits

	if scaleFrame then
		scaleFrame.Size = UDim2.new(ratio, 0, 1, 0)
		-- Optional: Change color based on HP
		if ratio > 0.67 then
			scaleFrame.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
		elseif ratio > 0.34 then
			scaleFrame.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
		else
			scaleFrame.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
		end
	end

	if textLabel then
		textLabel.Text = string.format("%d/%d", currentHp, maxHits)
	end
end

local function UpdateUIVisibility(ui: BillboardGui, isParticipant: boolean)
	ui.Enabled = true
	local controllerFrame = ui:FindFirstChild("ControllerFrame")
	if controllerFrame then
		local healthBar = controllerFrame:FindFirstChild("HealthBar") :: GuiObject?
		if healthBar then
			healthBar.Visible = isFighting and isParticipant
		end
	end
end

local function TryAttachUiToRealPlayer(playerId: number, ui: BillboardGui, isParticipant: boolean): (boolean, string?)
	local player = players:GetPlayerByUserId(playerId)
	if player == nil then
		return false, "player_missing"
	end
	local character = player.Character
	if character == nil then
		return false, "character_missing"
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid ~= nil and humanoid:IsA("Humanoid") then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end

	local head = character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return false, "head_missing"
	end
	ui.Adornee = head

	local playerGui = players.LocalPlayer:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return false, "player_gui_missing"
	end
	if ui.Parent ~= playerGui then
		ui.Parent = playerGui
		BillboardManager.Track(ui)
	end
	UpdateUIVisibility(ui, isParticipant)
	return true, nil
end

local function GetDisplayNameByPlayerId(playerId: number): string
	local player = players:GetPlayerByUserId(playerId)
	if player ~= nil then
		return player.DisplayName or player.Name
	end
	local botMeta = botMetaMap[tostring(playerId)]
	if botMeta ~= nil and botMeta.isBot then
		return botMeta.name
	end
	return "Player " .. tostring(playerId)
end

local function ResolveBotAdorneePart(playerId: number): BasePart?
	local lobbyNpc = workspace:FindFirstChild("BotLobbyNpc_" .. tostring(playerId))
	if lobbyNpc ~= nil and lobbyNpc:IsA("Model") then
		local head = lobbyNpc:FindFirstChild("Head")
		if head ~= nil and head:IsA("BasePart") then
			return head
		end
		local hrp = lobbyNpc:FindFirstChild("HumanoidRootPart")
		if hrp ~= nil and hrp:IsA("BasePart") then
			return hrp
		end
	end

	local vehicleModel = workspace:FindFirstChild("Vehicle_" .. tostring(playerId))
	if vehicleModel ~= nil and vehicleModel:IsA("Model") then
		local vehicleNpc = vehicleModel:FindFirstChild("BotNpcCharacter")
		if vehicleNpc ~= nil and vehicleNpc:IsA("Model") then
			local head = vehicleNpc:FindFirstChild("Head")
			if head ~= nil and head:IsA("BasePart") then
				return head
			end
			local hrp = vehicleNpc:FindFirstChild("HumanoidRootPart")
			if hrp ~= nil and hrp:IsA("BasePart") then
				return hrp
			end
		end
		local baseDisk = vehicleModel:FindFirstChild("BaseDisk")
		if baseDisk ~= nil and baseDisk:IsA("BasePart") then
			return baseDisk
		end
	end
	return nil
end

local function RefreshBotUiAdornee(playerId: number)
	local data = playerUIMap[playerId]
	if data == nil then
		return
	end
	if players:GetPlayerByUserId(playerId) ~= nil then
		return
	end
	local targetAdornee = ResolveBotAdorneePart(playerId)
	if targetAdornee ~= nil then
		data.ui.Adornee = targetAdornee
		local localPlayerGui = players.LocalPlayer:FindFirstChild("PlayerGui")
		if localPlayerGui ~= nil and data.ui.Parent ~= localPlayerGui then
			data.ui.Parent = localPlayerGui
			BillboardManager.Track(data.ui)
		end
	end
end

local function RefreshRealPlayerUiAdornee(playerId: number)
	local data = playerUIMap[playerId]
	if data == nil then
		return
	end
	if players:GetPlayerByUserId(playerId) == nil then
		return
	end

	local playerGui = players.LocalPlayer:FindFirstChild("PlayerGui")
	if data.ui.Adornee ~= nil and playerGui ~= nil and data.ui.Parent == playerGui then
		realPlayerAdorneePendingMap[playerId] = nil
		return
	end

	local attached, reason = TryAttachUiToRealPlayer(playerId, data.ui, data.isParticipant)
	if attached then
		if realPlayerAdorneePendingMap[playerId] then
			print(string.format("[PlayerInfoUIManager] RecoveredPlayerNameUI userId=%d", playerId))
		end
		realPlayerAdorneePendingMap[playerId] = nil
		realPlayerAdorneeLastWarnClockMap[playerId] = nil
		return
	end

	realPlayerAdorneePendingMap[playerId] = true
	local nowClock = os.clock()
	local lastWarnClock = realPlayerAdorneeLastWarnClockMap[playerId]
	if lastWarnClock == nil or nowClock - lastWarnClock >= RealPlayerAdorneeRetryLogIntervalSec then
		warn(string.format("[PlayerInfoUIManager] PendingPlayerNameUI userId=%d reason=%s", playerId, reason or "unknown"))
		realPlayerAdorneeLastWarnClockMap[playerId] = nowClock
	end
end

-- PlayerInfoUIOffset 为在模板 BillboardGui.StudsOffset 基础上的附加偏移；仅在 CreateUIForPlayer 时按载具设一次
local function updatePlayerInfoUiStudsOffsetFromVehicle(playerId: number)
	local data = playerUIMap[playerId]
	if data == nil then
		return
	end
	local vehicleData = GameConfig.VehicleDataMap[data.vehicleId]
	local extra = if vehicleData then vehicleData.playerInfoUIOffset else Vector3.zero
	data.ui.StudsOffset = PlayerInfoUiTemplateStudsOffset + extra
end

local function CreateUIForPlayer(playerId: number, isParticipant: boolean, vehicleId: number)
	local existingRecord = playerUIMap[playerId]
	local ui: BillboardGui?
	
	if existingRecord and existingRecord.ui.Parent ~= nil then
		existingRecord.isParticipant = isParticipant
		existingRecord.vehicleId = vehicleId
		ui = existingRecord.ui
	else
		-- If UI was destroyed but still in map, clean up before recreating
		if existingRecord then
			RemoveUIForPlayer(playerId)
		end

		local player = players:GetPlayerByUserId(playerId)
		
		ui = playerInfoUITemplate:Clone()
		ui.Parent = replicatedStorage -- Just a holder until we can adonree
		local controllerFrame = ui:FindFirstChild("ControllerFrame")
		if controllerFrame then
			local playerNameLabel = controllerFrame:FindFirstChild("PlayerName") :: TextLabel?
			if playerNameLabel then
				playerNameLabel.Text = GetDisplayNameByPlayerId(playerId)
			end
		end
		
		if player then
			local function SetupAdornee()
				if not ui or ui.Parent == nil then return end -- Validate UI is not destroyed
				local attached, reason = TryAttachUiToRealPlayer(playerId, ui, isParticipant)
				if not attached then
					realPlayerAdorneePendingMap[playerId] = true
					local nowClock = os.clock()
					local lastWarnClock = realPlayerAdorneeLastWarnClockMap[playerId]
					if lastWarnClock == nil or nowClock - lastWarnClock >= RealPlayerAdorneeRetryLogIntervalSec then
						warn(string.format("[PlayerInfoUIManager] InitialPlayerNameUIBindFailed userId=%d reason=%s", playerId, reason or "unknown"))
						realPlayerAdorneeLastWarnClockMap[playerId] = nowClock
					end
					return
				end
				realPlayerAdorneePendingMap[playerId] = nil
				realPlayerAdorneeLastWarnClockMap[playerId] = nil
			end
			
			SetupAdornee()
			local conn = player.CharacterAdded:Connect(SetupAdornee)
			connectionMap[playerId] = conn
		else
			local botAdornee = ResolveBotAdorneePart(playerId)
			if botAdornee ~= nil then
				ui.Adornee = botAdornee
				local playerGui = players.LocalPlayer:WaitForChild("PlayerGui", 5)
				if playerGui then
					ui.Parent = playerGui
					BillboardManager.Track(ui)
					UpdateUIVisibility(ui, isParticipant)
				end
			end
		end
		
		playerUIMap[playerId] = {
			ui = ui :: BillboardGui,
			isParticipant = isParticipant,
			vehicleId = vehicleId,
			fireRingCooldownText = nil,
			fireRingSegments = nil,
			fireRingWasCoolingDown = false,
			fireRingHighlightRemaining = 0,
			lastFireRingActiveCount = nil,
			lastFireRingText = nil,
			lastFireRingReadyHighlighted = nil,
		}
	end
	
	-- Set initial state for BOTH new and reused UI
	local initialMaxHits = GameConfig.MaxHits
	-- Try to get current max hits if possible, but usually OnHpChanged will follow shortly
	UpdateHpUI(playerId, 0, initialMaxHits)
	
	-- Refresh visibility
	if ui then
		UpdateUIVisibility(ui, isParticipant)
	end

	ConfigureFireCooldownRing(playerId)
	updatePlayerInfoUiStudsOffsetFromVehicle(playerId)
end

local function EnsureRealPlayerNameUI(player: Player)
	if player.UserId == players.LocalPlayer.UserId then
		return
	end
	local existingRecord = playerUIMap[player.UserId]
	if existingRecord ~= nil and existingRecord.ui.Parent ~= nil then
		return
	end
	CreateUIForPlayer(player.UserId, false, 1)
end

local function EnsureRealPlayerNameUIForAll()
	for _, player in players:GetPlayers() do
		EnsureRealPlayerNameUI(player)
	end
end

RemoveUIForPlayer = function(playerId: number)
	local data = playerUIMap[playerId]
	if data then
		local ui = data.ui
		BillboardManager.Untrack(ui)
		ui:Destroy()
		playerUIMap[playerId] = nil
		realPlayerAdorneePendingMap[playerId] = nil
		realPlayerAdorneeLastWarnClockMap[playerId] = nil
	end
	local conn = connectionMap[playerId]
	if conn then
		conn:Disconnect()
		connectionMap[playerId] = nil
	end
end

function PlayerInfoUIManager.Init()
	NetMsg.ConnectNotifyBotMetaSync(function(latestBotMetaMap)
		botMetaMap = latestBotMetaMap
		-- 某些大厅时序下，bot 可能没有新的 UnitInit，但需要显示名字 UI；此处兜底补建
		for idText, meta in botMetaMap do
			if meta.isBot then
				local botId = tonumber(idText)
				if botId ~= nil and playerUIMap[botId] == nil then
					CreateUIForPlayer(botId, false, 1)
				end
			end
		end
		for playerId, data in playerUIMap do
			local controllerFrame = data.ui:FindFirstChild("ControllerFrame")
			if controllerFrame then
				local playerNameLabel = controllerFrame:FindFirstChild("PlayerName") :: TextLabel?
				if playerNameLabel then
					playerNameLabel.Text = GetDisplayNameByPlayerId(playerId)
				end
			end
			RefreshBotUiAdornee(playerId)
		end
	end)

	NetMsg.ConnectNotifyUnitInit(function(unitInitInfo)
		CreateUIForPlayer(unitInitInfo.playerId, unitInitInfo.isParticipant, unitInitInfo.vehicleId)
		UpdateHpUI(unitInitInfo.playerId, 0, unitInitInfo.maxHits)
	end)

	NetMsg.ConnectNotifyUnitRemove(function(playerId)
		if players:GetPlayerByUserId(playerId) ~= nil then
			-- 真人玩家在大厅不依赖 Unit 生命周期，避免被误删导致名字丢失
			RefreshRealPlayerUiAdornee(playerId)
			return
		end
		RemoveUIForPlayer(playerId)
	end)

	NetMsg.ConnectNotifyHpChanged(function(playerId, hitCount, maxHits, _hpServerTime, adaptiveDelaySec)
		local hpDelaySec = math.max(0, adaptiveDelaySec or 0)
		if hpDelaySec > 0 then
			task.delay(hpDelaySec, function()
				UpdateHpUI(playerId, hitCount, maxHits)
			end)
			return
		end
		UpdateHpUI(playerId, hitCount, maxHits)
	end)

	NetMsg.ConnectNotifyDead(function(playerId, _killerId, deadServerTime, adaptiveDelaySec)
		local sampleDeadServerTime = if deadServerTime == deadServerTime then deadServerTime else 0
		local lastDeadServerTime = lastDeadServerTimeMap[playerId]
		if lastDeadServerTime ~= nil and sampleDeadServerTime <= lastDeadServerTime then
			return
		end
		lastDeadServerTimeMap[playerId] = sampleDeadServerTime
		local deadDelaySec = math.max(0, adaptiveDelaySec or 0)
		task.delay(deadDelaySec, function()
			if lastDeadServerTimeMap[playerId] ~= sampleDeadServerTime then
				return
			end
			RemoveUIForPlayer(playerId)
		end)
	end)

	NetMsg.ConnectNotifyMatchState(function(matchState, countdown)
		isFighting = (matchState == GameConfig.MatchState.Fighting or matchState == GameConfig.MatchState.GameStartCountdown)
		EnsureRealPlayerNameUIForAll()
		for playerId, data in playerUIMap do
			UpdateUIVisibility(data.ui, data.isParticipant)
			RefreshRealPlayerUiAdornee(playerId)
			RefreshBotUiAdornee(playerId)
		end
		if matchState == GameConfig.MatchState.InLobby then
			table.clear(lastDeadServerTimeMap)
		end
	end)
	
	NetMsg.FireRequestSyncUnit()
	EnsureRealPlayerNameUIForAll()

	players.PlayerAdded:Connect(function(player: Player)
		EnsureRealPlayerNameUI(player)
	end)

	players.PlayerRemoving:Connect(function(player: Player)
		RemoveUIForPlayer(player.UserId)
	end)

	-- Local player respawn handling
	players.LocalPlayer.CharacterAdded:Connect(function()
		-- When local player respawns, the PlayerGui may be reset.
		-- Clear all local UI state and request a fresh sync.
		local ids = {}
		for id, _ in playerUIMap do
			table.insert(ids, id)
		end
		for _, id in ids do
			RemoveUIForPlayer(id)
		end
		
		NetMsg.FireRequestSyncUnit()
	end)

	runService.Heartbeat:Connect(function(deltaTime: number)
		fireRingUpdateAccumSec += deltaTime
		if fireRingUpdateAccumSec >= FireRingUpdateIntervalSec then
			local updateDeltaTime = fireRingUpdateAccumSec
			fireRingUpdateAccumSec = 0
			UpdateLocalFireCooldownRingDisplay(updateDeltaTime)
		end

		realPlayerAdorneeRetryAccumSec += deltaTime
		local shouldRetryRealPlayerAdornee = realPlayerAdorneeRetryAccumSec >= RealPlayerAdorneeRetryIntervalSec
		if shouldRetryRealPlayerAdornee then
			realPlayerAdorneeRetryAccumSec = 0
		end

		for playerId, _ in playerUIMap do
			if shouldRetryRealPlayerAdornee then
				RefreshRealPlayerUiAdornee(playerId)
			end
			RefreshBotUiAdornee(playerId)
		end
	end)

	print("[PlayerInfoUIManager] Initialized")
end

return PlayerInfoUIManager
