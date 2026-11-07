--!strict
-- Shared farming types and pure helpers. No instance ownership, no state:
-- both FarmService (server) and FarmController (client) rely on these so
-- plot keys and stage math always agree.

local Crops = require(script.Parent.Parent.Config.Crops)

local Farming = {}

export type PlotKey = { x: integer, y: integer }

-- Plot records as replicated between server and client.
export type PlotState = {
	tilled: boolean,
	watered: boolean, -- derived: wateredAt within WaterDuration of now
	cropId: string?,
	stage: integer, -- 0..StageCount; StageCount means harvestable
	growthProgress: number, -- 0..1, for smooth client visuals
}

export type Snapshot = {
	plots: { [string]: PlotState }, -- keyed by encodePlotKey
	gridSize: { x: integer, y: integer },
	tileSize: number,
	spacing: number,
	offset: Vector3,
}

local SEPARATOR = ","

function Farming.encodePlotKey(x: integer, y: integer): string
	return x .. SEPARATOR .. y
end

function Farming.decodePlotKey(key: string): (integer, integer)?
	local parts = string.split(key, SEPARATOR)
	if #parts ~= 2 then
		return nil
	end
	-- Reject malformed input ("1,2,3" would make tonumber return extras).
	local xi, yi = tonumber((parts[1])), tonumber((parts[2]))
	if not xi or not yi or math.floor(xi) ~= xi or math.floor(yi) ~= yi then
		return nil
	end
	return math.tointeger(xi), math.tointeger(yi)
end

-- Grid geometry is fixed data shared by the builder and the client so tile
-- positions are reproducible on both sides.
Farming.Grid = {
	SizeX = 10,
	SizeY = 8,
	TileSize = 4,
	Spacing = 0.5,
	Offset = Vector3.new(0, 0.25, -30), -- center of the (0,0) tile top area
}

function Farming.tileCFrame(x: integer, y: integer): CFrame
	local g = Farming.Grid
	local step = g.TileSize + g.Spacing
	local worldX = g.Offset.X + (x - (g.SizeX - 1) / 2) * step
	local worldZ = g.Offset.Z + (y - (g.SizeY - 1) / 2) * step
	return CFrame.new(worldX, g.Offset.Y, worldZ)
end

function Farming.isInsideGrid(x: integer, y: integer): boolean
	local g = Farming.Grid
	return x >= 0 and x < g.SizeX and y >= 0 and y < g.SizeY
end

-- Current growth stage for a crop given accumulated game-minute progress.
function Farming.stageFor(cropId: string, grownMinutes: number): integer
	local def = Crops.get(cropId)
	if not def then
		return 0
	end
	if grownMinutes >= def.TotalGrowMinutes then
		return def.StageCount
	end
	local stage = math.floor(grownMinutes / def.TotalGrowMinutes * def.StageCount)
	if stage < 0 then
		stage = 0
	end
	return stage
end

function Farming.progressFor(cropId: string, grownMinutes: number): number
	local def = Crops.get(cropId)
	if not def then
		return 0
	end
	return math.clamp(grownMinutes / def.TotalGrowMinutes, 0, 1)
end

return Farming
