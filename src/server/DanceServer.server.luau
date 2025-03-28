--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create the dance sync event if it doesn't exist
local DanceEvent = Instance.new("RemoteEvent")
DanceEvent.Name = "DanceSync"
DanceEvent.Parent = ReplicatedStorage

-- Handle dance sync events
DanceEvent.OnServerEvent:Connect(function(player: Player, danceId: string?)
    -- Broadcast the dance to all other clients
    DanceEvent:FireAllClients(player, danceId)
end)

print("[DanceServer] Dance synchronization initialized")
