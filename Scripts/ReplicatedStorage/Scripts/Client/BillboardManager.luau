--!strict
local BillboardManager = {}
local infoGuis: { BillboardGui } = {}
local infoGuiIndexMap: { [BillboardGui]: number } = {}
local connectionMap: { [BillboardGui]: { RBXScriptConnection } } = {}
local SCALE_EPSILON = 0.001

local function RemoveInfoGuiByIndex(index: number)
	local lastIndex = #infoGuis
	local removedGui = infoGuis[index]
	local lastGui = infoGuis[lastIndex]
	if index ~= lastIndex then
		infoGuis[index] = lastGui
		infoGuiIndexMap[lastGui] = index
	end
	infoGuis[lastIndex] = nil
	infoGuiIndexMap[removedGui] = nil
end

local function RemoveInfoGui(gui: BillboardGui)
	local index = infoGuiIndexMap[gui]
	if index == nil then
		return
	end
	local connections = connectionMap[gui]
	if connections ~= nil then
		for _, connection in connections do
			connection:Disconnect()
		end
		connectionMap[gui] = nil
	end
	RemoveInfoGuiByIndex(index)
end

local function UpdateSingleInfoScale(infoUI: BillboardGui)
	local controllerFrame = infoUI:FindFirstChild("ControllerFrame")
	if controllerFrame == nil or not controllerFrame:IsA("Frame") then
		return
	end
	local uiScale = controllerFrame:FindFirstChild("UIScale")
	if uiScale == nil or not uiScale:IsA("UIScale") then
		return
	end
	local controllerWidth = controllerFrame.Size.X.Offset
	local controllerHeight = controllerFrame.Size.Y.Offset
	if controllerWidth <= 0 or controllerHeight <= 0 then
		return
	end
	local nextScale = math.min(
		infoUI.AbsoluteSize.X / controllerWidth,
		infoUI.AbsoluteSize.Y / controllerHeight
	)
	if math.abs(uiScale.Scale - nextScale) < SCALE_EPSILON then
		return
	end
	uiScale.Scale = nextScale
end

function BillboardManager.Track(gui: BillboardGui)
	if infoGuiIndexMap[gui] ~= nil then
		return
	end
	table.insert(infoGuis, gui)
	infoGuiIndexMap[gui] = #infoGuis
	UpdateSingleInfoScale(gui)
	connectionMap[gui] = {
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			UpdateSingleInfoScale(gui)
		end),
		gui:GetPropertyChangedSignal("Adornee"):Connect(function()
			local adornee = gui.Adornee
			gui.Enabled = adornee.Parent ~= nil
			UpdateSingleInfoScale(gui)
		end),
		gui.AncestryChanged:Connect(function()
			if gui.Parent == nil then
				RemoveInfoGui(gui)
			end
		end),
	}
end

function BillboardManager.Untrack(gui: BillboardGui)
	RemoveInfoGui(gui)
end

return BillboardManager
