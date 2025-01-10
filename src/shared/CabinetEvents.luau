local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create events folder if it doesn't exist
local CabinetEvents = ReplicatedStorage:FindFirstChild("CabinetEvents")
if not CabinetEvents then
    CabinetEvents = Instance.new("Folder")
    CabinetEvents.Name = "CabinetEvents"
    CabinetEvents.Parent = ReplicatedStorage
    
    -- Create RemoteEvents
    local PlayCabinetEvent = Instance.new("RemoteEvent")
    PlayCabinetEvent.Name = "PlayCabinet"
    PlayCabinetEvent.Parent = CabinetEvents
    
    local GameStateChanged = Instance.new("RemoteEvent")
    GameStateChanged.Name = "GameStateChanged"
    GameStateChanged.Parent = CabinetEvents
end

return {
    PlayCabinet = CabinetEvents:WaitForChild("PlayCabinet"),
    GameStateChanged = CabinetEvents:WaitForChild("GameStateChanged")
}
