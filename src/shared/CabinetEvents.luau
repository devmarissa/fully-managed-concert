local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create a folder for our events if it doesn't exist
local eventsFolder = ReplicatedStorage:FindFirstChild("CabinetEvents")
if not eventsFolder then
    eventsFolder = Instance.new("Folder")
    eventsFolder.Name = "CabinetEvents"
    eventsFolder.Parent = ReplicatedStorage
end

-- Create RemoteEvents if they don't exist
local function createRemoteEvent(name: string): RemoteEvent
    local event = eventsFolder:FindFirstChild(name)
    if not event then
        event = Instance.new("RemoteEvent")
        event.Name = name
        event.Parent = eventsFolder
    end
    return event
end

-- Initialize our events
local CabinetEvents = {
    PlayCabinet = createRemoteEvent("PlayCabinet"),
    GameStateChanged = createRemoteEvent("GameStateChanged"),
    PlayerInput = createRemoteEvent("PlayerInput"),
}

return CabinetEvents
