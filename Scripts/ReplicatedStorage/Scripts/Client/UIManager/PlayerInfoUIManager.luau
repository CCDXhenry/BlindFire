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

local playerUIMap: { [number]: BillboardGui } = {}
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
	local ui = playerUIMap[playerId]
	if ui == nil then
		return
	end

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

local function CreateUIForPlayer(playerId: number)
	local existingUI = playerUIMap[playerId]
	if existingUI and existingUI.Parent ~= nil then
		return
	end

	-- If UI was destroyed but still in map, clean up before recreating
	if existingUI then
		RemoveUIForPlayer(playerId)
	end

	local player = players:GetPlayerByUserId(playerId)
	local head = player and GetPlayerHead(player)
	
	-- In this specific game, players are often on vehicles. 
	-- But usually we mount to the head or the vehicle. 
	-- Given "挂载到每个玩家身上", head is the standard choice.
	
	local ui = playerInfoUITemplate:Clone()
	ui.Parent = replicatedStorage -- Just a holder until we can adonree
	
	if player then
		local localPlayer = players.LocalPlayer
		local function SetupAdornee()
			if not ui or ui.Parent == nil then return end -- Validate UI is not destroyed
			local character = player.Character
			if not character then return end
			
			-- Wait for the head if the character exists but head isn't ready
			local currentHead = character:WaitForChild("Head", 5) :: BasePart?
			if currentHead then
				ui.Adornee = currentHead
				local playerGui = localPlayer:WaitForChild("PlayerGui", 5)
				if playerGui then
					ui.Parent = playerGui
					BillboardManager.Track(ui)
					ui.Enabled = isFighting
				end
			end
		end
		
		SetupAdornee()
		local conn = player.CharacterAdded:Connect(SetupAdornee)
		connectionMap[playerId] = conn
	end
	
	playerUIMap[playerId] = ui
	
	-- Set initial state
	UpdateHpUI(playerId, 0, GameConfig.MaxHits)
	
	-- Hide if not fighting
	ui.Enabled = isFighting
end

RemoveUIForPlayer = function(playerId: number)
	local ui = playerUIMap[playerId]
	if ui then
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
		CreateUIForPlayer(unitInitInfo.playerId)
	end)

	NetMsg.ConnectNotifyUnitRemove(function(playerId)
		RemoveUIForPlayer(playerId)
	end)

	NetMsg.ConnectNotifyHpChanged(function(playerId, hitCount, maxHits)
		UpdateHpUI(playerId, hitCount, maxHits)
	end)

	NetMsg.ConnectNotifyMatchState(function(matchState, countdown)
		isFighting = (matchState == "Fighting" or matchState == "GameStartCountdown")
		for _, ui in playerUIMap do
			ui.Enabled = isFighting
		end
		
		-- If we just entered a match, make sure UIs are up for everyone
		if isFighting then
			-- In case some players were already there
			for _, player in players:GetPlayers() do
				if not playerUIMap[player.UserId] then
					-- We might not have UnitInit info yet if we joined late, 
					-- but CombatManager sends it.
				end
			end
		end
	end)
	
	print("[PlayerInfoUIManager] Initialized")
end

return PlayerInfoUIManager
