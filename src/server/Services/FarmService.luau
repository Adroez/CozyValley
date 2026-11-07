--!strict
-- Authoritative farming state: soil plots, planting, watering, growth and
-- harvesting. The client only sends intent; every rule below is enforced
-- here. Growth runs on a single heartbeat that accumulates game minutes --
-- no per-crop tasks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local Farming = require(Shared.Modules.Farming)
local Crops = require(Shared.Config.Crops)
local Items = require(Shared.Config.Items)
local GameConstants = require(Shared.Config.GameConstants)
local Seasons = require(Shared.Config.Seasons)

local FarmService = { Name = "FarmService" }

local TILL_RANGE = 12 -- studs from the nearest character part to tile center
local HEARTBEAT_SECONDS = 5

type PlotRecord = {
	tilledBy: string?,
	tilledAt: number?, -- game minute stamp
	cropId: string?,
	plantedAt: number?, -- game minute stamp
	grownMinutes: number, -- accumulated effective growth
	wateredAt: number?, -- game minute stamp of last watering
}

-- Server truth ----------------------------------------------------------------

local plots: { [string]: PlotRecord } = {}
local plotParts: { [string]: BasePart } = {}

-- Tiny internal game clock. Milestone 4 replaces this with the day/night
-- TimeService; the interface used here (clock fields + currentSeason) stays.
-- totalMinutes is monotonic and stamps every age/water timestamp, so
-- comparisons never break when minuteOfDay wraps at midnight.
local clock = {
	minuteOfDay = 6 * 60, -- start each session at 06:00 day 1
	totalMinutes = 6 * 60, -- monotonic; used for age/water timestamps
	day = GameConstants.Time.StartDay,
	year = GameConstants.Time.StartYear,
}

local function currentSeason(): string
	local order = Seasons.Order
	local seasonNumber = (clock.year - 1) * #order + math.floor((clock.day - 1) / GameConstants.Time.DaysPerSeason)
	local index = seasonNumber % #order + 1
	return order[index]
end

local function seasonGrowthMultiplier(cropId: string): number
	local def = Crops.get(cropId)
	if not def then
		return 0
	end
	local season = currentSeason()
	if not def.Seasons[season] then
		return 0
	end
	local definition = Seasons.Definitions[season]
	return definition and definition.CropGrowthMultiplier or 1
end

local function isWatered(plot: PlotRecord): boolean
	if not plot.wateredAt then
		return false
	end
	return clock.totalMinutes - plot.wateredAt < Crops.WaterDurationMinutes
end

local function plotStateFor(key: string): Farming.PlotState?
	local plot = plots[key]
	if not plot then
		return nil
	end
	local state: Farming.PlotState = {
		tilled = plot.tilledAt ~= nil,
		watered = isWatered(plot),
		cropId = plot.cropId,
		stage = 0,
		growthProgress = 0,
	}
	if plot.cropId then
		state.stage = Farming.stageFor(plot.cropId, plot.grownMinutes)
		state.growthProgress = Farming.progressFor(plot.cropId, plot.grownMinutes)
	end
	return state
end

local function snapshot(): Farming.Snapshot
	local plotsOut: { [string]: Farming.PlotState } = {}
	for key in plots do
		local state = plotStateFor(key)
		if state then
			plotsOut[key] = state
		end
	end
	local g = Farming.Grid
	return {
		plots = plotsOut,
		gridSize = { x = g.SizeX, y = g.SizeY },
		tileSize = g.TileSize,
		spacing = g.Spacing,
		offset = g.Offset,
	}
end

-- Sync ------------------------------------------------------------------------

-- Assigned in Start(); the remote handlers and heartbeat only ever run after.
local farmAction: RemoteEvent = nil :: any
local farmResult: RemoteEvent = nil :: any
local farmSync: RemoteEvent = nil :: any

local function syncPlot(key: string)
	local state = plotStateFor(key)
	farmSync:FireAllClients(key, state)
end

local function deny(player: Player, message: string)
	farmResult:FireClient(player, false, message)
end

local function accept(player: Player, message: string)
	farmResult:FireClient(player, true, message)
end

-- World representation ----------------------------------------------------------
-- Simple placeholder tiles so farming is testable before Milestone 4 builds
-- the real farm environment. Positions derive from shared Farming.Grid data.

local function buildPlotTiles()
	local folder = Instance.new("Folder")
	folder.Name = "Farm"

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = folder

	local g = Farming.Grid
	for x = 0, g.SizeX - 1 do
		for y = 0, g.SizeY - 1 do
			local part = Instance.new("Part")
			part.Name = Farming.encodePlotKey(x, y)
			part.Anchored = true
			part.CanCollide = false
			part.Size = Vector3.new(g.TileSize, 0.5, g.TileSize)
			part.CFrame = Farming.tileCFrame(x, y)
			part.Color = Color3.fromRGB(120, 108, 92) -- untilled ground
			part.Material = Enum.Material.Grass
			part.Parent = plotsFolder
			plotParts[part.Name] = part
		end
	end

	folder.Parent = Workspace
end

local TILE_COLORS = {
	bare = Color3.fromRGB(120, 108, 92),
	tilled = Color3.fromRGB(84, 58, 38),
	tilledWet = Color3.fromRGB(56, 38, 26),
}

local function repaintTile(key: string)
	local part = plotParts[key]
	local plot = plots[key]
	if not part then
		return
	end
	if plot and plot.tilledAt then
		part.Color = isWatered(plot) and TILE_COLORS.tilledWet or TILE_COLORS.tilled
		part.Material = Enum.Material.Mud
	else
		part.Color = TILE_COLORS.bare
		part.Material = Enum.Material.Grass
	end
end

-- Moisture flag mirror for every tilled plot, including bare soil. The crop
-- growth loop below only visits planted plots, so without this a watered
-- empty plot would stay dark forever after its watering expires.
local moistureMirror: { [string]: boolean } = {}

local function refreshMoisture(key: string): boolean
	local plot = plots[key]
	local wet = plot ~= nil and plot.tilledAt ~= nil and isWatered(plot)
	local previous = moistureMirror[key]
	moistureMirror[key] = wet
	return wet ~= previous
end

-- Actions -----------------------------------------------------------------------

local function withinReach(player: Player, key: string): boolean
	local character = player.Character
	local part = plotParts[key]
	if not character or not part then
		return false
	end
	-- Measure from the nearest body part so tall/small avatars behave the
	-- same; HumanoidRootPart alone misjudges vertical distance.
	local best = math.huge
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			local distance = (descendant.Position - part.Position).Magnitude
			if distance < best then
				best = distance
			end
		end
	end
	return best <= TILL_RANGE
end

local function handleTill(player: Player, key: string)
	local plot = plots[key]
	if plot and plot.tilledAt then
		deny(player, "Soil is already tilled.")
		return
	end
	if not plot then
		plots[key] = {
			tilledBy = player.Name,
			tilledAt = clock.totalMinutes,
			grownMinutes = 0,
		}
	else
		plot.tilledBy = player.Name
		plot.tilledAt = clock.totalMinutes
	end
	repaintTile(key)
	syncPlot(key)
	accept(player, "Tilled the soil.")
end

local function handlePlant(player: Player, key: string, seedItemId: string?)
	if typeof(seedItemId) ~= "string" then
		deny(player, "No seed selected.")
		return
	end
	local seed = Items.get(seedItemId)
	if not seed or seed.Kind ~= "Seed" then
		deny(player, "That item is not a seed.")
		return
	end

	-- Find which crop uses this seed.
	local cropId: string? = nil
	for id, def in Crops.Definitions do
		if def.SeedItemId == seedItemId then
			cropId = id
			break
		end
	end
	if not cropId then
		deny(player, "These seeds match no known crop.")
		return
	end

	local plot = plots[key]
	if not plot or not plot.tilledAt then
		deny(player, "Till the soil before planting.")
		return
	end
	if plot.cropId then
		deny(player, "This soil already has a crop growing.")
		return
	end

	local def = Crops.get(cropId)
	if not def then
		deny(player, "Unknown crop configuration.")
		return
	end
	if seasonGrowthMultiplier(cropId) == 0 then
		deny(player, ("%s cannot be planted in %s."):format(def.DisplayName, currentSeason()))
		return
	end

	-- Inventory checks arrive in Milestone 3; seeds are free for now.
	plot.cropId = cropId
	plot.plantedAt = clock.totalMinutes
	plot.grownMinutes = 0
	syncPlot(key)
	accept(player, ("Planted %s."):format(def.DisplayName))
end

local function handleWater(player: Player, key: string)
	local plot = plots[key]
	if not plot or not plot.tilledAt then
		deny(player, "Water tilled soil only.")
		return
	end
	if isWatered(plot) then
		deny(player, "The soil is still wet.")
		return
	end
	plot.wateredAt = clock.totalMinutes
	repaintTile(key)
	syncPlot(key)
	accept(player, "Watered the soil.")
end

local function handleHarvest(player: Player, key: string)
	local plot = plots[key]
	if not plot or not plot.cropId then
		deny(player, "Nothing to harvest here.")
		return
	end
	local def = Crops.get(plot.cropId)
	if not def then
		deny(player, "Unknown crop.")
		return
	end
	local stage = Farming.stageFor(plot.cropId, plot.grownMinutes)
	if stage < def.StageCount then
		deny(player, ("The %s is not ready yet."):format(def.DisplayName))
		return
	end

	-- Harvest succeeds: give produce once inventory exists (Milestone 3);
	-- for now we just clear the plot.
	plot.cropId = nil
	plot.plantedAt = nil
	plot.grownMinutes = 0
	plot.wateredAt = nil
	if not def.Regrows then
		plot.tilledAt = nil
		plot.tilledBy = nil
	end
	repaintTile(key)
	syncPlot(key)
	accept(player, ("Harvested %s."):format(def.DisplayName))
end

local ACTION_HANDLERS = {
	Till = handleTill,
	Plant = handlePlant,
	Water = handleWater,
	Harvest = handleHarvest,
}

local function onFarmAction(player: Player, actionName: any, plotKey: any, payload: any)
	if typeof(actionName) ~= "string" or typeof(plotKey) ~= "string" then
		return
	end
	local handler = ACTION_HANDLERS[actionName]
	if not handler then
		return
	end
	local coords = Farming.decodePlotKey(plotKey)
	if not coords then
		deny(player, "Invalid plot.")
		return
	end
	local x, y = coords
	if not Farming.isInsideGrid(x, y) then
		deny(player, "That is outside the farm.")
		return
	end
	if not withinReach(player, plotKey) then
		deny(player, "Move closer to the soil.")
		return
	end
	handler(player, plotKey, payload)
end

-- Growth heartbeat ---------------------------------------------------------------

local function advanceClock(deltaSeconds: number)
	local minutes = deltaSeconds / GameConstants.Time.RealSecondsPerGameMinute
	clock.totalMinutes += minutes
	clock.minuteOfDay += minutes
	if clock.minuteOfDay >= 24 * 60 then
		clock.minuteOfDay -= 24 * 60
		clock.day += 1
		if clock.day > GameConstants.Time.DaysPerSeason * #Seasons.Order then
			clock.day = 1
			clock.year += 1
		end
	end
end

local function tick()
	advanceClock(HEARTBEAT_SECONDS)

	local elapsed = HEARTBEAT_SECONDS / GameConstants.Time.RealSecondsPerGameMinute

	-- Bare tilled soil: repaint + resync when watering expires.
	for key, plot in plots do
		if plot.tilledAt and not plot.cropId and refreshMoisture(key) then
			repaintTile(key)
			syncPlot(key)
		end
	end

	for key, plot in plots do
		if plot.cropId then
			local def = Crops.get(plot.cropId)
			if not def then
				-- Unknown crop id in state; clear it rather than stall the loop.
				plot.cropId = nil
			else
				local before = Farming.stageFor(plot.cropId, plot.grownMinutes)
				local rate = seasonGrowthMultiplier(plot.cropId)
				if rate > 0 then
					if isWatered(plot) then
						rate *= Crops.WaterBonus
					else
						rate *= Crops.DryGrowthRate
					end
					plot.grownMinutes += elapsed * rate
				end
				local after = Farming.stageFor(plot.cropId, plot.grownMinutes)
				local waterChanged = refreshMoisture(key)
				if after ~= before or waterChanged then
					repaintTile(key)
					syncPlot(key)
				end
			end
		end
	end
end

function FarmService.Start()
	farmAction = Remotes.event("FarmAction")
	farmResult = Remotes.event("FarmResult")
	farmSync = Remotes.event("FarmSync")

	buildPlotTiles()

	Remotes.function("GetFarmSnapshot").OnServerInvoke = function(_player: Player)
		return snapshot()
	end

	farmAction.OnServerEvent:Connect(onFarmAction)

	task.spawn(function()
		while true do
			tick()
			task.wait(HEARTBEAT_SECONDS)
		end
	end)

	print(("FarmService: %dx%d plots online, season %s")
		:format(Farming.Grid.SizeX, Farming.Grid.SizeY, currentSeason()))
end

return FarmService
