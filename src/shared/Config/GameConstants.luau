--!strict
-- Central tuning values for Cozy Valley. Data only; no logic.

local GameConstants = {
	GameName = "Cozy Valley",

	-- Networking
	RemoteFolderName = "CozyRemotes",

	-- Player defaults (consumed by later milestones: economy, energy)
	Player = {
		StartGold = 500,
		MaxEnergy = 100,
	},

	-- Time system (Milestone 4 will drive this from the server clock service)
	Time = {
		RealSecondsPerGameMinute = 1,
		DaysPerSeason = 28,
		StartDay = 1,
		StartYear = 1,
	},
}

return GameConstants
