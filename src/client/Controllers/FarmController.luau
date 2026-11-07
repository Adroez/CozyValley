--!strict
-- Client-side farming input and presentation. Sends intent only; never
-- mutates farm state locally beyond rendering what the server replicated.
-- Debug keybindings until Milestone 3's hotbar exists:
--   1 = Hoe (till), 2 = Seed bag (plant), 3 = Watering can, 4 = Harvest,
--   E = use current tool on the hovered soil tile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local Farming = require(Shared.Modules.Farming)
local Crops = require(Shared.Config.Crops)

local Controller = { Name = "FarmController" }

local TILL, PLANT, WATER, HARVEST = "Till", "Plant", "Water", "Harvest"

-- Placeholder seed used by the debug plant tool until inventory exists (M3).
local PLACEHOLDER_SEED = "TurnipSeeds"

local TILE_COLORS = {
	bare = Color3.fromRGB(120, 108, 92),
	tilled = Color3.fromRGB(84, 58, 38),
	tilledWet = Color3.fromRGB(56, 38, 26),
}

local currentTool = TILL
local lastHoverKey: string? = nil
local ready = false -- input is ignored until the snapshot load completes

local function plotFolder(): Folder?
	local farm = Workspace:FindFirstChild("Farm")
	if farm then
		local plots = farm:FindFirstChild("Plots")
		if plots and plots:IsA("Folder") then
			return plots
		end
	end
	return nil
end

local function raycastToPlot(): BasePart?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local unit = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local folder = plotFolder()
	if not folder then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }

	local result = Workspace:Raycast(unit.Origin, unit.Direction * 500, params)
	if result and result.Instance:IsA("BasePart") then
		return result.Instance :: BasePart
	end
	return nil
end

local function request(action: string, plotKey: string, payload: any?)
	Remotes.event("FarmAction"):FireServer(action, plotKey, payload)
end

local function onInteractPressed()
	local hoverKey = lastHoverKey
	if not ready or not hoverKey then
		return
	end
	if currentTool == PLANT then
		request(PLANT, hoverKey, PLACEHOLDER_SEED)
	else
		request(currentTool, hoverKey)
	end
end

-- Rendering ---------------------------------------------------------------------

local function visualsFolder(): Folder
	local existing = Workspace:FindFirstChild("CropVisualsClient")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "CropVisualsClient"
	folder.Parent = Workspace
	return folder
end

-- Crop tiles are thin (0.5 stud); the visual must sit on their top face,
-- which is +0.25 above the tile center.
local TILE_TOP_Y = 0.25

local function renderCrop(key: string, part: BasePart, cropId: string?, stage: integer)
	local container = visualsFolder()
	local model = container:FindFirstChild(key)

	if not cropId or stage <= 0 then
		if model then
			model:Destroy()
		end
		return
	end

	local def = Crops.get(cropId)
	if not def then
		return
	end

	if not model or not model:IsA("Model") then
		model = Instance.new("Model")
		model.Name = key
		model.Parent = container
	end
	for _, child in model:GetChildren() do
		child:Destroy()
	end

	local mature = stage >= def.StageCount
	local t = stage / def.StageCount

	local stem = Instance.new("Part")
	stem.Anchored = true
	stem.CanCollide = false
	stem.CanQuery = false
	stem.Size = Vector3.new(0.35, 0.4 + 1.7 * t, 0.35)
	stem.Transparency = mature and 0.5 or 0
	stem.Color = Color3.fromRGB(60 + 40 * t, 140 + 60 * t, 60)
	stem.Material = Enum.Material.Grass
	stem.CFrame = part.CFrame * CFrame.new(0, TILE_TOP_Y + stem.Size.Y / 2, 0)
	stem.Parent = model

	if mature then
		local fruit = Instance.new("Part")
		fruit.Shape = Enum.PartType.Ball
		fruit.Anchored = true
		fruit.CanCollide = false
		fruit.CanQuery = false
		fruit.Size = Vector3.new(1, 1, 1)
		fruit.Color = Color3.fromRGB(235, 120, 70)
		fruit.Material = Enum.Material.SmoothPlastic
		local stemTop = TILE_TOP_Y + stem.Size.Y
	fruit.CFrame = part.CFrame * CFrame.new(0, stemTop + fruit.Size.Y / 2 - 0.15, 0)
		fruit.Parent = model
	end
end

local function applyPlotState(key: string, state: Farming.PlotState?)
	local folder = plotFolder()
	local part = folder and folder:FindFirstChild(key)
	if not part or not part:IsA("BasePart") then
		return
	end

	if state and state.tilled then
		part.Color = state.watered and TILE_COLORS.tilledWet or TILE_COLORS.tilled
		part.Material = Enum.Material.Mud
	else
		part.Color = TILE_COLORS.bare
		part.Material = Enum.Material.Grass
	end

	renderCrop(key, part, state and state.cropId or nil, state and state.stage or 0)
end

function Controller.Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local code = input.KeyCode
		if code == Enum.KeyCode.E then
			onInteractPressed()
		elseif code == Enum.KeyCode.One then
			currentTool = TILL
		elseif code == Enum.KeyCode.Two then
			currentTool = PLANT
		elseif code == Enum.KeyCode.Three then
			currentTool = WATER
		elseif code == Enum.KeyCode.Four then
			currentTool = HARVEST
		end
	end)

	task.spawn(function()
		while true do
			local hovered = raycastToPlot()
			lastHoverKey = hovered and hovered.Name or nil
			task.wait(0.1)
		end
	end)

	Remotes.event("FarmSync").OnClientEvent:Connect(function(key: string, state: Farming.PlotState?)
		applyPlotState(key, state)
	end)

	Remotes.event("FarmResult").OnClientEvent:Connect(function(ok: boolean, message: string)
		print(("[Farm] %s"):format(message))
		if not ok then
			warn(("[FarmController] rejected: %s"):format(message))
		end
	end)

	-- Pull the full snapshot so late joiners see existing farm state.
	task.spawn(function()
		-- Tiles are server-built; give replication a generous window before
		-- invoking, so the snapshot has somewhere to land.
		local folder = plotFolder()
		local deadline = os.clock() + 30
		while not folder and os.clock() < deadline do
			task.wait(0.5)
			folder = plotFolder()
		end
		if not folder then
			warn("FarmController: Workspace.Farm.Plots never replicated")
			return
		end

		local ok, snap = pcall(function()
			return Remotes.function("GetFarmSnapshot"):InvokeServer()
		end)
		if ok and typeof(snap) == "table" and snap.plots then
			local count = 0
			for key, state in snap.plots do
				applyPlotState(key, state)
				count += 1
			end
			ready = true
			print(("FarmController: loaded %d plots (tool: %s)")
				:format(count, currentTool))
		else
			warn("FarmController: could not load farm snapshot")
		end
	end)
end

return Controller
