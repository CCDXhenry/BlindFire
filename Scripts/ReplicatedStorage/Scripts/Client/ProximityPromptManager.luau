--!strict
local ProximityPromptManager = {}

local replicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local uiManager = require(clientScripts:WaitForChild("UIManager"))

local isInitialized = false

function ProximityPromptManager.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	-- 载具商店 ProximityPrompt 管理
	task.defer(function()
		local vehicleShop = workspace:WaitForChild("VehicleShop", 10)
		if vehicleShop then
			local rootPart = vehicleShop:WaitForChild("RootPart", 5)
			if rootPart then
				local attachment = rootPart:WaitForChild("ProximityPromptAttachment", 5)
				if attachment then
					local prompt = attachment:WaitForChild("ProximityPrompt", 5)
					if prompt and prompt:IsA("ProximityPrompt") then
						prompt.Triggered:Connect(function()
							uiManager.OpenWindow(uiManager.WindowId.VehiclesShop)
						end)
					end
				end
			end
		end
	end)
end

return ProximityPromptManager
