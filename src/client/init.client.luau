local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

-- Get the RemoteEvents
local CabinetEvents = require(ReplicatedStorage.Shared.CabinetEvents)

-- Track which cabinets have active P1 players
local activeP1Players = {}

-- Handle cabinet interaction
local function setupCabinetInteraction()
    local workspace = game:GetService("Workspace")
    local cabinetsFolder = workspace:WaitForChild("Cabinets")
    
    -- Setup interaction for each cabinet
    for _, cabinetFolder in cabinetsFolder:GetChildren() do
        local cabinet = cabinetFolder:WaitForChild("Cabinet")
        if cabinet then
            -- Get P1 and P2 prompts
            local p1Part = cabinet:WaitForChild("P1")
            local p2Part = cabinet:WaitForChild("P2")
            local p1Prompt = p1Part:WaitForChild("ProximityPrompt")
            local p2Prompt = p2Part:WaitForChild("ProximityPrompt")
            
            -- Initially hide P2 prompt
            p2Prompt.Enabled = false
            
            -- Handle P1 prompt
            p1Prompt.Triggered:Connect(function(player)
                if player == localPlayer then
                    CabinetEvents.PlayCabinet:FireServer(p1Part)
                end
            end)
            
            -- Handle P2 prompt
            p2Prompt.Triggered:Connect(function(player)
                if player == localPlayer then
                    CabinetEvents.PlayCabinet:FireServer(p2Part)
                end
            end)
        end
    end
end

-- Listen for game state changes
CabinetEvents.GameStateChanged.OnClientEvent:Connect(function(cabinet, state, p1Player)
    if not cabinet then return end
    
    local p2Prompt = cabinet.P2:FindFirstChild("ProximityPrompt")
    if not p2Prompt then return end
    
    if state == "WAITING_FOR_P2" then
        -- Only show P2 prompt to players who aren't P1
        p2Prompt.Enabled = p1Player ~= localPlayer
    else
        p2Prompt.Enabled = false
    end
end)

setupCabinetInteraction()