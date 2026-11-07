--!strict
-- Minimal item catalog. Data only. Milestone 3 (inventory) will extend this
-- with icons, categories, hotbar order, and sell prices where missing.

local Items = {
	Definitions = {
		TurnipSeeds = { DisplayName = "Turnip Seeds", Kind = "Seed", SellPrice = 5 },
		PotatoSeeds = { DisplayName = "Potato Seeds", Kind = "Seed", SellPrice = 8 },
		CauliflowerSeeds = { DisplayName = "Cauliflower Seeds", Kind = "Seed", SellPrice = 12 },

		Turnip = { DisplayName = "Turnip", Kind = "Produce", SellPrice = 35 },
		Potato = { DisplayName = "Potato", Kind = "Produce", SellPrice = 55 },
		Cauliflower = { DisplayName = "Cauliflower", Kind = "Produce", SellPrice = 90 },
	},
}

function Items.get(itemId: string): { [string]: any }?
	return Items.Definitions[itemId]
end

return Items
