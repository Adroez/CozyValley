--!strict
-- Client bootstrap logic, executed by the root LocalScript (init.client.luau).
-- Initialization order:
--   1. Wait for shared modules to replicate.
--   2. Initialize the Remotes wrapper (waits for CozyRemotes from the server).
--   3. Subscribe to the Ping smoke-test remote.
--   4. Start controllers in declared order with error isolation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
assert(Shared, "Cozy Valley client: ReplicatedStorage.Shared did not replicate in time")

local Remotes = require(Shared.Modules.Remotes)
local GameConstants = require(Shared.Config.GameConstants)
local Controllers = require(script.Parent.Controllers)

return function()
	print("Cozy Valley client: booting...")

	Remotes.init(nil)

	Remotes.event("Ping").OnClientEvent:Connect(function(message: string)
		print(("Cozy Valley client: server says %q"):format(message))
	end)

	for index, controller in Controllers do
		local ok, err = pcall(controller.Start)
		if not ok then
			warn(("Cozy Valley client: controller #%d (%s) failed to start: %s")
				:format(index, controller.Name or "unnamed", tostring(err)))
		else
			print(("Cozy Valley client: started %s"):format(controller.Name or ("controller #" .. index)))
		end
	end

	print(("Cozy Valley client: ready for %s"):format(GameConstants.GameName))
end
