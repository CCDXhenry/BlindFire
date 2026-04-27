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

type PlayerInfoUIRecord = {
	ui: BillboardGui,
	isParticipant: boolean,
	fireRingCooldownText: TextLabel?,
	fireRingSegments: { Frame }?,
	fireRingWasCoolingDown: boolean,
	fireRingHighlightRemaining: number,
}

local PlayerInfoUIManager = {}

local playerUIMap: { [number]: PlayerInfoUIRecord } = {}
local connectionMap: { [number]: RBXScriptConnection } = {}
local isFighting = false

local SegmentNamePrefix = "SegmentFrame_"
local RingColorOn: Color3 = Color3.fromRGB(255, 170, 0)
local RingColorOff: Color3 = Color3.fromRGB(70, 70, 70)
local RingTransparencyOn: number = 0.05
local RingTransparencyOff: number = 0.35
local RingReadyColor: Color3 = Color3.fromRGB(60, 255, 120)
local RingHighlightColor: Color3 = Color3.fromRGB(170, 255, 190)
local RingHighlightDurationSeconds: number = 0.25

local RemoveUIForPlayer: (number) -> ()

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
		if isCoolingDown then
			cooldownTextLabel.Text = string.format("%.1f", actualLeft)
		else
			cooldownTextLabel.Text = ""
		end
	end

	local segmentCount = #segmentList
	if isCoolingDown then
		data.fireRingHighlightRemaining = 0
		local progress = 1 - (actualLeft / totalSeconds)
		progress = math.clamp(progress, 0, 1)
		local activeCount = math.floor(progress * segmentCount + 0.5)
		for index, segmentFrame in ipairs(segmentList) do
			local isLit = index <= activeCount
			segmentFrame.BackgroundColor3 = if isLit then RingColorOn else RingColorOff
			segmentFrame.BackgroundTransparency = if isLit then RingTransparencyOn else RingTransparencyOff
		end
		data.fireRingWasCoolingDown = true
	else
		if data.fireRingWasCoolingDown then
			data.fireRingHighlightRemaining = RingHighlightDurationSeconds
			data.fireRingWasCoolingDown = false
		end
		if data.fireRingHighlightRemaining > 0 then
			data.fireRingHighlightRemaining = math.max(data.fireRingHighlightRemaining - deltaTime, 0)
			SetFireRingReadySegments(segmentList, true)
		else
			SetFireRingReadySegments(segmentList, false)
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

local function CreateUIForPlayer(playerId: number, isParticipant: boolean)
	local existingRecord = playerUIMap[playerId]
	local ui: BillboardGui?
	
	if existingRecord and existingRecord.ui.Parent ~= nil then
		existingRecord.isParticipant = isParticipant
		ui = existingRecord.ui
	else
		-- If UI was destroyed but still in map, clean up before recreating
		if existingRecord then
			RemoveUIForPlayer(playerId)
		end

		local player = players:GetPlayerByUserId(playerId)
		
		ui = playerInfoUITemplate:Clone()
		ui.Parent = replicatedStorage -- Just a holder until we can adonree
		
		if player then
			local localPlayer = players.LocalPlayer
			local function SetupAdornee()
				if not ui or ui.Parent == nil then return end -- Validate UI is not destroyed
				local character = player.Character
				if not character then return end
				
				-- Hide default Roblox name UI
				local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
				if humanoid then
					humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				end

				-- Setup Name Label
				local controllerFrame = ui:FindFirstChild("ControllerFrame")
				if controllerFrame then
					local playerNameLabel = controllerFrame:FindFirstChild("PlayerName") :: TextLabel?
					if playerNameLabel then
						playerNameLabel.Text = player.DisplayName or player.Name
					end
				end

				-- Wait for the head if the character exists but head isn't ready
				local currentHead = character:WaitForChild("Head", 5) :: BasePart?
				if currentHead then
					ui.Adornee = currentHead
					local playerGui = localPlayer:WaitForChild("PlayerGui", 5)
					if playerGui then
						ui.Parent = playerGui
						BillboardManager.Track(ui)
						UpdateUIVisibility(ui, isParticipant)
					end
				end
			end
			
			SetupAdornee()
			local conn = player.CharacterAdded:Connect(SetupAdornee)
			connectionMap[playerId] = conn
		end
		
		playerUIMap[playerId] = {
			ui = ui :: BillboardGui,
			isParticipant = isParticipant,
			fireRingCooldownText = nil,
			fireRingSegments = nil,
			fireRingWasCoolingDown = false,
			fireRingHighlightRemaining = 0,
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
end

RemoveUIForPlayer = function(playerId: number)
	local data = playerUIMap[playerId]
	if data then
		local ui = data.ui
		BillboardManager.Untrack(ui)
		ui:Destroy()
		playerUIMap[playerId] = nil
	end
	local conn = connectionMap[playerId]
	if conn then
		conn:Disconnect()
		connectionMap[playerId] = nil
	end
end

function PlayerInfoUIManager.Init()
	NetMsg.ConnectNotifyUnitInit(function(unitInitInfo)
		CreateUIForPlayer(unitInitInfo.playerId, unitInitInfo.isParticipant)
		UpdateHpUI(unitInitInfo.playerId, 0, unitInitInfo.maxHits)
	end)

	NetMsg.ConnectNotifyUnitRemove(function(playerId)
		RemoveUIForPlayer(playerId)
	end)

	NetMsg.ConnectNotifyHpChanged(function(playerId, hitCount, maxHits)
		UpdateHpUI(playerId, hitCount, maxHits)
	end)

	NetMsg.ConnectNotifyDead(function(playerId, killerId)
		RemoveUIForPlayer(playerId)
	end)

	NetMsg.ConnectNotifyMatchState(function(matchState, countdown)
		isFighting = (matchState == GameConfig.MatchState.Fighting or matchState == GameConfig.MatchState.GameStartCountdown)
		for playerId, data in playerUIMap do
			UpdateUIVisibility(data.ui, data.isParticipant)
		end
	end)
	
	NetMsg.FireRequestSyncUnit()

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

	runService.RenderStepped:Connect(function(deltaTime: number)
		UpdateLocalFireCooldownRingDisplay(deltaTime)
	end)

	print("[PlayerInfoUIManager] Initialized")
end

return PlayerInfoUIManager
