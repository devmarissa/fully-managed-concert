--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CabinetController = {}
CabinetController.__index = CabinetController

-- Get remote events
local remotes = ReplicatedStorage:WaitForChild("PongRemotes")
local playerJoinedEvent = remotes:WaitForChild("PlayerJoined") :: RemoteEvent
local playerLeftEvent = remotes:WaitForChild("PlayerLeft") :: RemoteEvent

export type PlayerState = {
    prompt: ProximityPrompt?,
    position: BasePart?,
    controls: BasePart?,
    isAnchored: boolean,
    ikControl: IKControl?,
    player: Player?,
}

function CabinetController.new(cabinet: Model)
    print("[CabinetController] Initializing...")
    local self = setmetatable({}, CabinetController)
    
    self.cabinet = cabinet
    self.p1State = {} :: PlayerState
    self.p2State = {} :: PlayerState
    self.localPlayer = Players.LocalPlayer
    self.character = self.localPlayer.Character or self.localPlayer.CharacterAdded:Wait()
    
    print("[CabinetController] Setting up references...")
    -- Setup initial references
    self:setupReferences()
    self:setupProximityPrompts()
    
    -- Connect character added
    self.localPlayer.CharacterAdded:Connect(function(char)
        print("[CabinetController] Character added")
        self.character = char
        self:setupCharacterConnections()
    end)
    
    -- Handle remote events
    playerJoinedEvent.OnClientEvent:Connect(function(player, position)
        print("[CabinetController] Remote player joined:", player.Name, "position:", position)
        local state = position == 1 and self.p1State or self.p2State
        state.player = player
        
        -- If this is another player, set up their character
        if player ~= self.localPlayer then
            local char = player.Character or player.CharacterAdded:Wait()
            self:setupRemotePlayer(char, position)
            
            -- Connect to character changes
            player.CharacterAdded:Connect(function(char)
                self:setupRemotePlayer(char, position)
            end)
        end
    end)
    
    playerLeftEvent.OnClientEvent:Connect(function(player, position)
        print("[CabinetController] Remote player left:", player.Name, "position:", position)
        local state = position == 1 and self.p1State or self.p2State
        if state.player == player then
            state.player = nil
            -- Cleanup any remote player setup
            if player ~= self.localPlayer and player.Character then
                self:cleanupRemotePlayer(player.Character)
            end
        end
    end)
    
    self:setupCharacterConnections()
    print("[CabinetController] Initialization complete")
    
    return self
end

function CabinetController:setupRemotePlayer(char: Model, position: number)
    local state = position == 1 and self.p1State or self.p2State
    
    -- Position the character
    local humanoid = char:WaitForChild("Humanoid") :: Humanoid
    local rootPart = humanoid.RootPart
    
    rootPart.CFrame = state.position.CFrame * CFrame.new(0, 3, 0)
    rootPart.Anchored = true
    
    -- Setup IK
    local ikControl = Instance.new("IKControl")
    ikControl.Name = "CabinetIK"
    ikControl.Type = Enum.IKControlType.Position
    ikControl.EndEffector = char:WaitForChild("RightHand")
    ikControl.Target = state.controls
    ikControl.ChainRoot = char:WaitForChild("RightUpperArm")
    ikControl.Enabled = true
    ikControl.Parent = humanoid
    
    -- Store IK control for cleanup
    state.ikControl = ikControl
end

function CabinetController:cleanupRemotePlayer(char: Model)
    local humanoid = char:FindFirstChild("Humanoid") :: Humanoid?
    if humanoid then
        local ikControl = humanoid:FindFirstChild("CabinetIK") :: IKControl?
        if ikControl then
            ikControl:Destroy()
        end
        humanoid.RootPart.Anchored = false
    end
end

function CabinetController:setupReferences()
    -- Get positions and controls
    self.p1State.position = self.cabinet:WaitForChild("P1") :: BasePart
    self.p2State.position = self.cabinet:WaitForChild("P2") :: BasePart
    
    local buttons = self.cabinet.Controls.Buttons
    self.p1State.controls = buttons:WaitForChild("leftPaddle") :: BasePart
    self.p2State.controls = buttons:WaitForChild("rightPaddle") :: BasePart
    print("[CabinetController] References setup complete")
end

function CabinetController:setupProximityPrompts()
    -- Get existing prompts
    self.p1State.prompt = self.p1State.position:WaitForChild("ProximityPrompt") :: ProximityPrompt
    self.p2State.prompt = self.p2State.position:WaitForChild("ProximityPrompt") :: ProximityPrompt
    
    -- Setup prompt callbacks
    self.p1State.prompt.Triggered:Connect(function()
        print("[CabinetController] P1 prompt triggered")
        self:onPlayerJoin(1)
    end)
    
    self.p2State.prompt.Triggered:Connect(function()
        print("[CabinetController] P2 prompt triggered")
        self:onPlayerJoin(2)
    end)
    print("[CabinetController] Proximity prompts setup complete")
end

function CabinetController:setupCharacterConnections()
    if not self.character then 
        print("[CabinetController] No character found")
        return 
    end
    
    print("[CabinetController] Setting up character connections")
    -- Setup IK control
    local humanoid = self.character:WaitForChild("Humanoid") :: Humanoid
    humanoid.RootPart.Anchored = false
    
    -- Make character visible in first person
    humanoid.CameraOffset = Vector3.new(0, 0, -1)
    
    -- Setup camera
    local camera = workspace.CurrentCamera
    if camera then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = humanoid
    end
    print("[CabinetController] Character connections setup complete")
end

function CabinetController:onPlayerJoin(playerNum: number)
    print("[CabinetController] Player", playerNum, "joining")
    local state = playerNum == 1 and self.p1State or self.p2State
    if not self.character then return end
    
    -- Fire remote event first
    playerJoinedEvent:FireServer(playerNum)
    
    -- Position and anchor the character
    local humanoid = self.character:WaitForChild("Humanoid") :: Humanoid
    local rootPart = humanoid.RootPart
    
    rootPart.CFrame = state.position.CFrame * CFrame.new(0, 3, 0) -- Offset upward for proper positioning
    rootPart.Anchored = true
    state.isAnchored = true
    
    -- Setup camera
    local camera = workspace.CurrentCamera
    if camera then
        camera.CameraType = Enum.CameraType.Custom
        camera.CFrame = rootPart.CFrame * CFrame.new(0, 1.5, 0)
    end
    
    -- Create IK Control
    if state.ikControl then
        state.ikControl:Destroy()
    end
    
    state.ikControl = Instance.new("IKControl")
    state.ikControl.Name = "CabinetIK"
    state.ikControl.Type = Enum.IKControlType.Position
    state.ikControl.EndEffector = self.character:WaitForChild("RightHand")
    state.ikControl.Target = state.controls
    state.ikControl.ChainRoot = self.character:WaitForChild("RightUpperArm")
    state.ikControl.Enabled = true
    state.ikControl.Parent = humanoid
    
    print("[CabinetController] Player", playerNum, "joined successfully")
end

function CabinetController:onPlayerLeave(playerNum: number)
    print("[CabinetController] Player", playerNum, "leaving")
    local state = playerNum == 1 and self.p1State or self.p2State
    if not self.character then return end
    
    -- Fire remote event first
    playerLeftEvent:FireServer()
    
    -- Cleanup IK
    if state.ikControl then
        state.ikControl:Destroy()
        state.ikControl = nil
    end
    
    -- Unanchor character
    local humanoid = self.character:WaitForChild("Humanoid") :: Humanoid
    humanoid.RootPart.Anchored = false
    state.isAnchored = false
    
    -- Reset camera
    local camera = workspace.CurrentCamera
    if camera then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = humanoid
    end
    
    print("[CabinetController] Player", playerNum, "left successfully")
end

function CabinetController:destroy()
    print("[CabinetController] Cleaning up...")
    -- Cleanup any connections
    if self.p1State.isAnchored then
        self:onPlayerLeave(1)
    end
    if self.p2State.isAnchored then
        self:onPlayerLeave(2)
    end
    print("[CabinetController] Cleanup complete")
end

return CabinetController
