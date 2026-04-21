--!strict
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local clientScripts = scripts:WaitForChild("Client")

local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local GameConfig = require(sharedScripts:WaitForChild("GameConfig"))
local BillboardManager = require(clientScripts:WaitForChild("BillboardManager"))

local playerInfoUITemplate = replicatedStorage:WaitForChild("UI"):WaitForChild("PlayerInfoUI") :: BillboardGui

local PlayerInfoUIManager = {}

local playerUIMap: { [number]: { ui: BillboardGui, isParticipant: boolean } } = {}
local connectionMap: { [number]: RBXScriptConnection } = {}
local isFighting = false

local RemoveUIForPlayer: (number) -> ()

local function GetPlayerHead(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChild("Head") :: BasePart?
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
		
		playerUIMap[playerId] = { ui = ui, isParticipant = isParticipant }
	end
	
	-- Set initial state for BOTH new and reused UI
	UpdateHpUI(playerId, 0, GameConfig.MaxHits)
	
	-- Refresh visibility
	if ui then
		UpdateUIVisibility(ui, isParticipant)
	end
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
		isFighting = (matchState == "Fighting" or matchState == "GameStartCountdown")
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

	print("[PlayerInfoUIManager] Initialized")
end

return PlayerInfoUIManager
