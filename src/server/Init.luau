--!strict
-- Server bootstrap logic, executed by the root Script (init.server.luau).
-- Initialization order:
--   1. Create the replicated remote folder + registered remotes via
--      Remotes.init(ReplicatedStorage), so they exist before any client joins.
--   2. Start services in declared order with error isolation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local Services = require(script.Parent.Services)

return function()
	print("Cozy Valley server: booting...")

	Remotes.init(ReplicatedStorage)

	for index, service in Services do
		local ok, err = pcall(service.Start)
		if not ok then
			warn(("Cozy Valley server: service #%d (%s) failed to start: %s")
				:format(index, service.Name or "unnamed", tostring(err)))
		else
			print(("Cozy Valley server: started %s"):format(service.Name or ("service #" .. index)))
		end
	end

	print("Cozy Valley server: ready.")
end
