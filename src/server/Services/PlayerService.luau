--!strict
-- Owns the player lifecycle: spawn placement and per-player runtime state.
-- Kept intentionally small; leaderstats/economy arrive in later milestones.

local Players = game:GetService("Players")

local GameConstants = require(script.Parent.Parent.Parent.Config.GameConstants)

local PlayerService = {}

local SPAWN_POSITION = Vector3.new(0, 12, 0)

local function onPlayerAdded(player: Player)
	-- Place the player at the farm spawn. StarterCharacterScripts and
	-- CharacterAppearance remain untouched.
	player.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root then
			root.CFrame = CFrame.new(SPAWN_POSITION)
		end
	end)

	if player.Character then
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.CFrame = CFrame.new(SPAWN_POSITION)
		end
	end

	player:SetAttribute("JoinedAt", os.time())
	print(("PlayerService: %s joined (%s)"):format(player.Name, GameConstants.GameName))
end

function PlayerService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerService
