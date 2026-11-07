--!strict
-- Bootstrap smoke test: answers the client's Ping with a hello message.
-- Remove or absorb into real services once gameplay milestones land.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local GameConstants = require(ReplicatedStorage.Shared.Config.GameConstants)

local PingService = { Name = "PingService" }

function PingService.Start()
	local ping = Remotes.event("Ping")

	ping.OnServerEvent:Connect(function(player: Player, message: string?)
		if typeof(message) == "string" and #message <= 200 then
			ping:FireClient(player, ("hello from server, %s"):format(player.Name))
		else
			warn(("PingService: invalid payload from %s"):format(player.Name))
		end
	end)

	-- Announce readiness to each spawn as a lightweight connectivity check.
	local function onCharacterAdded(player: Player, _character: Model)
		task.delay(1, function()
			if player.Parent then
				ping:FireClient(player, ("welcome to %s"):format(GameConstants.GameName))
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end)
end

return PingService
