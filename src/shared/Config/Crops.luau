--!strict
-- Crop definitions shared by client and server. Data only.
-- Growth is measured in game minutes; watering multiplies progress via
-- Crops.WaterBonus while the most recent watering is still fresh.

local Crops = {
	-- How long one watering stays effective, in game minutes.
	WaterDurationMinutes = 600,
	-- Extra growth rate applied while watered (1.5 = half again as fast).
	WaterBonus = 1.5,
	-- Growth rate when not watered.
	DryGrowthRate = 0.25,

	Definitions = {
		Turnip = {
			DisplayName = "Turnip",
			SeedItemId = "TurnipSeeds",
			HarvestItemId = "Turnip",
			-- Game minutes to fully mature (before rate modifiers).
			TotalGrowMinutes = 360,
			StageCount = 4,
			-- Seasons in which this crop grows at all.
			Seasons = { Spring = true, Fall = true },
			Regrows = false,
		},
		Potato = {
			DisplayName = "Potato",
			SeedItemId = "PotatoSeeds",
			HarvestItemId = "Potato",
			TotalGrowMinutes = 720,
			StageCount = 4,
			Seasons = { Spring = true, Summer = true, Fall = true },
			Regrows = false,
		},
		Cauliflower = {
			DisplayName = "Cauliflower",
			SeedItemId = "CauliflowerSeeds",
			HarvestItemId = "Cauliflower",
			TotalGrowMinutes = 1200,
			StageCount = 5,
			Seasons = { Spring = true },
			Regrows = false,
		},
	},
}

function Crops.get(cropId: string)
	return Crops.Definitions[cropId]
end

return Crops
