--!strict
-- Minimal placeholder HUD proving the client bootstrap works end to end.
-- Replaced by real UI in later milestones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Modules.Remotes)
local GameConstants = require(Shared.Config.GameConstants)

local Controller = { Name = "HUDController" }

function Controller.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CozyValleyHUD"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10

	local label = Instance.new("TextLabel")
	label.Name = "StatusLabel"
	label.Size = UDim2.fromOffset(300, 40)
	label.Position = UDim2.fromScale(0.5, 0) + UDim2.fromOffset(-150, 8)
	label.BackgroundColor3 = Color3.fromRGB(20, 24, 20)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.fromRGB(235, 235, 210)
	label.Font = Enum.Font.GothemMedium
	label.TextSize = 18
	label.Text = GameConstants.GameName .. " — connected"

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	label.Parent = screenGui
	screenGui.Parent = playerGui

	-- Reflect server pings in the label (bootstrap smoke-test feedback).
	Remotes.event("Ping").OnClientEvent:Connect(function(message: string)
		label.Text = GameConstants.GameName .. " — " .. message
	end)

	-- Fire one test ping so the round trip is observable immediately.
	task.delay(2, function()
		Remotes.event("Ping"):FireServer("client handshake")
	end)
end

return Controller
