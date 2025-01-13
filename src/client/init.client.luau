local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

-- Get the RemoteEvents
local CabinetEvents = require(ReplicatedStorage.Shared.CabinetEvents)
local PlayerController = require(script.PlayerController)

-- Initialize player controller
local controller = PlayerController.new()

-- Track active cabinets and player states
local activeCabinet = nil
local isPlaying = false
local isPlayer1 = false

-- Setup cabinet interaction
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
                    controller:enterCabinet(cabinet, true)
                end
            end)
            
            -- Handle P2 prompt
            p2Prompt.Triggered:Connect(function(player)
                if player == localPlayer then
                    CabinetEvents.PlayCabinet:FireServer(p2Part)
                    controller:enterCabinet(cabinet, false)
                end
            end)
        end
    end
end

-- Listen for game state changes
CabinetEvents.GameStateChanged.OnClientEvent:Connect(function(cabinet, state, p1Player, p2Player)
    if not cabinet then return end
    
    local p1Prompt = cabinet.P1:FindFirstChild("ProximityPrompt")
    local p2Prompt = cabinet.P2:FindFirstChild("ProximityPrompt")
    if not p1Prompt or not p2Prompt then return end
    
    if state == "ATTRACT_MODE" then
        -- Reset play state
        if cabinet == controller.activeCabinet then
            controller:exitCabinet()
        end
        -- Anyone can join as P1
        p1Prompt.Enabled = true
        p1Prompt.ActionText = "Play"
        p2Prompt.Enabled = false
        
    elseif state == "WAITING_FOR_P2" then
        -- P1 can exit, others can join as P2
        if localPlayer == p1Player then
            p1Prompt.Enabled = true
            p1Prompt.ActionText = "Exit"
            p2Prompt.Enabled = false
        else
            p1Prompt.Enabled = false
            p2Prompt.Enabled = true
            p2Prompt.ActionText = "Play"
        end
        
    else -- PLAYING
        -- Each player sees their own exit prompt
        p1Prompt.Enabled = localPlayer == p1Player
        p2Prompt.Enabled = localPlayer == p2Player
        p1Prompt.ActionText = "Exit"
        p2Prompt.ActionText = "Exit"
    end
end)

-- Connect input handlers
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    controller:handleInput(input, gameProcessed)
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    controller:handleInput(input, gameProcessed)
end)

UserInputService.TouchMoved:Connect(function(input, gameProcessed)
    controller:handleInput(input, gameProcessed)
end)

setupCabinetInteraction()