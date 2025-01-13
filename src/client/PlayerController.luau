local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CabinetEvents = require(ReplicatedStorage.Shared.CabinetEvents)

local PlayerController = {}
PlayerController.__index = PlayerController

function PlayerController.new()
    local self = setmetatable({}, PlayerController)
    self.localPlayer = Players.LocalPlayer
    self.character = self.localPlayer.Character or self.localPlayer.CharacterAdded:Wait()
    self.activeCabinet = nil
    self.isPlaying = false
    self.isPlayer1 = false
    self.transparencyConnections = {}  -- Store connections for cleanup
    
    -- Connect character added event
    self.localPlayer.CharacterAdded:Connect(function(char)
        self.character = char
        -- If we're already in a cabinet, set visibility
        if self.activeCabinet then
            self:setCharacterVisibility(true)
        end
    end)
    
    return self
end

function PlayerController:makePartsVisible(part)
    if not part or not part:IsA("BasePart") then return end
    
    -- Check if R15 parts
    local isR15Arm = part.Name == "RightUpperArm" or 
                     part.Name == "RightLowerArm" or 
                     part.Name == "RightHand"
    
    -- Check if R6 parts
    local isR6Arm = part.Name == "Right Arm"
    
    -- Only modify arm parts
    if isR15Arm or isR6Arm then
        part.LocalTransparencyModifier = part.Transparency
        -- Store connection for cleanup
        local connection = part.Changed:Connect(function(property)
            part.LocalTransparencyModifier = part.Transparency
        end)
        self.transparencyConnections[part] = connection
    end
end

function PlayerController:setCharacterVisibility(visible: boolean)
    if not self.character then return end
    
    -- Disconnect any existing connections
    for _, connection in pairs(self.transparencyConnections) do
        connection:Disconnect()
    end
    self.transparencyConnections = {}
    
    if self.childAddedConnection then
        self.childAddedConnection:Disconnect()
        self.childAddedConnection = nil
    end
    
    if visible then
        -- Make arm parts visible with original transparency
        for _, part in pairs(self.character:GetChildren()) do
            self:makePartsVisible(part)
        end
        
        -- Connect to child added in case parts are added later
        self.childAddedConnection = self.character.ChildAdded:Connect(function(child)
            self:makePartsVisible(child)
        end)
    else
        -- Reset all transparency modifiers
        for _, part in pairs(self.character:GetChildren()) do
            if part:IsA("BasePart") then
                part.LocalTransparencyModifier = 0
            end
        end
    end
end

function PlayerController:enterCabinet(cabinet, isPlayer1: boolean)
    self.activeCabinet = cabinet
    self.isPlayer1 = isPlayer1
    self.isPlaying = true
    
    -- Make character visible in first person
    self:setCharacterVisibility(true)
    
    -- Notify server of input start
    CabinetEvents.PlayerInput:FireServer(cabinet, "start", true)
end

function PlayerController:exitCabinet()
    if self.activeCabinet then
        -- Reset character visibility
        self:setCharacterVisibility(false)
        
        -- Notify server of input end
        CabinetEvents.PlayerInput:FireServer(self.activeCabinet, "end", true)
        
        -- Reset state
        self.activeCabinet = nil
        self.isPlaying = false
        self.isPlayer1 = false
    end
end

function PlayerController:handleInput(input, gameProcessed)
    if not self.isPlaying or not self.activeCabinet then return end
    
    -- Handle keyboard input
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if self.isPlayer1 then
            -- Player 1 controls (W/S)
            if input.KeyCode == Enum.KeyCode.W then
                CabinetEvents.PlayerInput:FireServer(self.activeCabinet, "up", input.UserInputState == Enum.UserInputState.Begin)
            elseif input.KeyCode == Enum.KeyCode.S then
                CabinetEvents.PlayerInput:FireServer(self.activeCabinet, "down", input.UserInputState == Enum.UserInputState.Begin)
            end
        else
            -- Player 2 controls (Up/Down arrows)
            if input.KeyCode == Enum.KeyCode.Up then
                CabinetEvents.PlayerInput:FireServer(self.activeCabinet, "up", input.UserInputState == Enum.UserInputState.Begin)
            elseif input.KeyCode == Enum.KeyCode.Down then
                CabinetEvents.PlayerInput:FireServer(self.activeCabinet, "down", input.UserInputState == Enum.UserInputState.Begin)
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
                CabinetEvents.PlayerInput:FireServer(self.activeCabinet, deltaY > 0 and "up" or "down", true)
            end
        end
    end
end

return PlayerController
