--!strict
-- Ordered service list for the server bootstrap. Services are plain modules
-- exposing Name and Start(). Infrastructure first, gameplay after.

return {
	require(script.PingService),
	require(script.PlayerService),
	require(script.FarmService),
}
