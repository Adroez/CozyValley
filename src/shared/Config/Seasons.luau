--!strict
-- Season definitions shared by client and server. Data only.

local Seasons = {
	Order = { "Spring", "Summer", "Fall", "Winter" },

	Definitions = {
		Spring = { DisplayName = "Spring", CropGrowthMultiplier = 1.0 },
		Summer = { DisplayName = "Summer", CropGrowthMultiplier = 1.2 },
		Fall = { DisplayName = "Fall", CropGrowthMultiplier = 1.0 },
		Winter = { DisplayName = "Winter", CropGrowthMultiplier = 0.0 },
	},
}

return Seasons
