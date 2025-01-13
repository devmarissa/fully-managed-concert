local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

-- Get the RemoteEvents
local CabinetEvents = require(ReplicatedStorage.Shared.CabinetEvents)

-- Track active cabinets and player states
local activeCabinet = nil
local isPlaying = false
local isPlayer1 = false

-- Input handling
local function handleInput(input, gameProcessed)
    if not isPlaying or not activeCabinet then return end
    
    -- Handle keyboard input
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if isPlayer1 then
            -- Player 1 controls (W/S)
            if input.KeyCode == Enum.KeyCode.W then
                CabinetEvents.PlayerInput:FireServer(activeCabinet, "up", input.UserInputState == Enum.UserInputState.Begin)
            elseif input.KeyCode == Enum.KeyCode.S then
                CabinetEvents.PlayerInput:FireServer(activeCabinet, "down", input.UserInputState == Enum.UserInputState.Begin)
            end
        else
            -- Player 2 controls (Up/Down arrows)
            if input.KeyCode == Enum.KeyCode.Up then
                CabinetEvents.PlayerInput:FireServer(activeCabinet, "up", input.UserInputState == Enum.UserInputState.Begin)
            elseif input.KeyCode == Enum.KeyCode.Down then
                CabinetEvents.PlayerInput:FireServer(activeCabinet, "down", input.UserInputState == Enum.UserInputState.Begin)
            end
        end
    end
    
    -- Handle touch/gamepad input
    if input.UserInputType == Enum.UserInputType.Touch or 
       input.UserInputType == Enum.UserInputType.Gamepad1 then
        local position = input.Position
        if position then
            local deltaY = position.Y - (input.Delta and input.Delta.Y or 0)
            if math.abs(deltaY) > 0 then
                CabinetEvents.PlayerInput:FireServer(activeCabinet, deltaY > 0 and "up" or "down", true)
            end
        end
    end
end

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
                    activeCabinet = cabinet
                    isPlayer1 = true
                end
            end)
            
            -- Handle P2 prompt
            p2Prompt.Triggered:Connect(function(player)
                if player == localPlayer then
                    CabinetEvents.PlayCabinet:FireServer(p2Part)
                    activeCabinet = cabinet
                    isPlayer1 = false
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
        if cabinet == activeCabinet then
            isPlaying = false
            activeCabinet = nil
        end
        -- Anyone can join as P1
        p1Prompt.Enabled = true
        p1Prompt.ActionText = "Play"
        p2Prompt.Enabled = false
        
    elseif state == "WAITING_FOR_P2" then
        -- P1 can exit, others can join as P2
        if localPlayer == p1Player then
            isPlaying = true
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
        if localPlayer == p1Player or localPlayer == p2Player then
            isPlaying = true
        end
        p1Prompt.Enabled = localPlayer == p1Player
        p2Prompt.Enabled = localPlayer == p2Player
        p1Prompt.ActionText = "Exit"
        p2Prompt.ActionText = "Exit"
    end
end)

-- Connect input handlers
UserInputService.InputBegan:Connect(handleInput)
UserInputService.InputEnded:Connect(handleInput)
UserInputService.TouchMoved:Connect(handleInput)

setupCabinetInteraction()