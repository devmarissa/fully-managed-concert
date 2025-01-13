local ArcadeGame = require(script.Parent.ArcadeGame)

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Events
local CabinetEvents = require(ReplicatedStorage.Shared.CabinetEvents)

-- Game constants
local BALL_SPEED = 0.5 -- Units per second (relative coordinates)
local PADDLE_SPEED = 0.3 -- Units per second
local PADDLE_HEIGHT = 70 -- Pixels
local PADDLE_WIDTH = 16 -- Pixels
local BALL_SIZE = 16 -- Pixels
local SCREEN_PADDING = 20 -- Pixels
local FIXED_HEIGHT = 525 -- SurfaceGui height
local FIXED_WIDTH = 858 -- SurfaceGui width

-- Calculate relative sizes and positions
local PLAYABLE_HEIGHT = FIXED_HEIGHT - (SCREEN_PADDING * 2)
local RELATIVE_PADDLE_HEIGHT = PADDLE_HEIGHT / PLAYABLE_HEIGHT
local PADDLE_X_OFFSET = (SCREEN_PADDING + PADDLE_WIDTH/2) / FIXED_WIDTH -- Relative X position from edge
local RELATIVE_BALL_SIZE = BALL_SIZE / FIXED_WIDTH -- For X collision

-- Calculate the safe range for paddle movement to keep paddles fully visible
-- Add a small offset to prevent edge overflow
local EDGE_OFFSET = 0.035 -- 3.5% offset from edges
local MIN_PADDLE_Y = EDGE_OFFSET
local MAX_PADDLE_Y = 1 - EDGE_OFFSET

-- Game states
local GameState = {
    ATTRACT_MODE = "ATTRACT_MODE",
    WAITING_FOR_P2 = "WAITING_FOR_P2",
    PLAYING = "PLAYING"
}

local PongGame = {}
PongGame.__index = PongGame

function PongGame.new(cabinet)
    local self = setmetatable({}, PongGame)
    
    self.cabinet = cabinet
    self.p1Prompt = cabinet:WaitForChild("P1"):WaitForChild("ProximityPrompt")
    self.p2Prompt = cabinet:WaitForChild("P2"):WaitForChild("ProximityPrompt")
    
    -- Get control references
    local controls = cabinet:WaitForChild("Controls"):WaitForChild("Buttons")
    self.leftPaddle = controls:WaitForChild("leftPaddle")
    self.rightPaddle = controls:WaitForChild("rightPaddle")
    
    -- Initialize positions
    self.paddlePosition = 0.5
    self.aiPaddlePosition = 0.5
    self.ballPosition = Vector2.new(0.5, 0.5)
    self.ballVelocity = Vector2.new(BALL_SPEED, 0)
    
    -- Initialize game state
    self.gameState = {
        state = GameState.ATTRACT_MODE,
        isActive = false,
        p1Score = 0,
        p2Score = 0,
        player1 = nil,
        player2 = nil,
        message = "PRESS START"
    }
    
    -- Debug info
    self.lastStateChange = os.clock()
    self.lastDebugPrint = 0
    
    -- Update prompt visibility
    self:updatePrompts()
    
    -- Initialize ball for attract mode
    self:resetBall(true)
    
    return self
end

function PongGame:updatePrompts()
    if self.gameState.state == GameState.ATTRACT_MODE then
        -- In attract mode, only P1 prompt is visible
        self.p1Prompt.Enabled = true
        self.p1Prompt.ActionText = "Play"
        self.p2Prompt.Enabled = false
        
    elseif self.gameState.state == GameState.WAITING_FOR_P2 then
        -- P1 can exit, others can join as P2
        self.p1Prompt.Enabled = true
        self.p1Prompt.ActionText = "Exit"
        self.p2Prompt.Enabled = true
        self.p2Prompt.ActionText = "Play"
        
    else -- PLAYING
        -- Both players can exit
        self.p1Prompt.Enabled = self.gameState.player1 ~= nil
        self.p2Prompt.Enabled = self.gameState.player2 ~= nil
        self.p1Prompt.ActionText = "Exit"
        self.p2Prompt.ActionText = "Exit"
    end
    
    -- Send state update to all clients with both player info
    CabinetEvents.GameStateChanged:FireAllClients(
        self.cabinet,
        self.gameState.state,
        self.gameState.player1,
        self.gameState.player2
    )
end

function PongGame:startGame(player: Player, position: number)
    if position == 1 and self.gameState.state == GameState.ATTRACT_MODE then
        -- Player 1 joining
        print("[PongGame] Player 1 joined:", player.Name)
        self.gameState.player1 = player
        self.gameState.state = GameState.WAITING_FOR_P2
        self.gameState.message = "WAITING FOR PLAYER 2"
        self.lastStateChange = os.clock()
        self:positionPlayer(player, 1)
        self:updatePrompts()
        -- Don't reset ball, keep it moving
        
    elseif position == 2 and self.gameState.state == GameState.WAITING_FOR_P2 then
        -- Player 2 joining
        print("[PongGame] Player 2 joined:", player.Name)
        self.gameState.player2 = player
        self.gameState.state = GameState.PLAYING
        self.gameState.isActive = true
        self.gameState.p1Score = 0
        self.gameState.p2Score = 0
        self.gameState.message = ""
        self.lastStateChange = os.clock()
        self:positionPlayer(player, 2)
        self:updatePrompts()
        -- Start with a fresh serve
        self:resetBall()
    end
end

function PongGame:playerLeft(player: Player)
    if player == self.gameState.player1 then
        print("[PongGame] Player 1 left:", player.Name)
        self:removePlayer(player)
        
        -- If P2 exists, they need to leave too
        if self.gameState.player2 then
            self:removePlayer(self.gameState.player2)
            self.gameState.player2 = nil
        end
        
        -- Reset to attract mode
        self.gameState.player1 = nil
        self.gameState.state = GameState.ATTRACT_MODE
        self.gameState.isActive = false
        self.gameState.message = "PRESS START"
        self.lastStateChange = os.clock()
        self:updatePrompts()
        -- Keep ball moving, don't reset
        
    elseif player == self.gameState.player2 then
        print("[PongGame] Player 2 left:", player.Name)
        self:removePlayer(player)
        self.gameState.player2 = nil
        
        -- Return to waiting for P2
        self.gameState.state = GameState.WAITING_FOR_P2
        self.gameState.isActive = false
        self.gameState.message = "WAITING FOR PLAYER 2"
        self.lastStateChange = os.clock()
        self:updatePrompts()
        -- Keep ball moving, don't reset
    end
end

function PongGame:positionPlayer(player: Player, position: number)
    local character = player.Character
    if not character then return end
    
    -- Get the appropriate position part
    local positionPart = position == 1 and self.cabinet.P1 or self.cabinet.P2
    if not positionPart then return end
    
    -- Position and anchor the character
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:WaitForChild("Humanoid")
    
    -- Lock the character in place
    humanoidRootPart.CFrame = positionPart.CFrame
    humanoidRootPart.Anchored = true
    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    humanoid.AutoRotate = false
    
    -- Disable specific states
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
    
    -- Set up IK control
    local endEffector, chainRoot
    if character:FindFirstChild("RightUpperArm") then -- R15
        endEffector = character:WaitForChild("RightHand")
        chainRoot = character:WaitForChild("RightUpperArm")
    else -- R6
        endEffector = character:WaitForChild("Right Arm")
        chainRoot = character:WaitForChild("Torso")
    end
    
    if not endEffector or not chainRoot then return end
    
    -- Remove any existing IK controls
    for _, existingIK in pairs(humanoid:GetChildren()) do
        if existingIK:IsA("IKControl") then
            existingIK:Destroy()
        end
    end
    
    -- Create new IK control
    local ikControl = Instance.new("IKControl")
    ikControl.Name = position == 1 and "LeftPaddleIK" or "RightPaddleIK"
    ikControl.Type = Enum.IKControlType.Position
    ikControl.EndEffector = endEffector
    ikControl.ChainRoot = chainRoot
    ikControl.Target = position == 1 and self.leftPaddle or self.rightPaddle
    ikControl.SmoothTime = 0.1
    ikControl.Weight = 1
    ikControl.Enabled = true
    ikControl.Parent = humanoid
    
    -- Store for cleanup
    self.ikControls = self.ikControls or {}
    self.ikControls[player.UserId] = ikControl
end

function PongGame:removePlayer(player: Player)
    local character = player.Character
    if character then
        -- Restore humanoid state
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16  -- Default walk speed
            humanoid.JumpPower = 50  -- Default jump power
            humanoid.AutoRotate = true
            
            -- Re-enable specific states
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
        end
        
        -- Unanchor character
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if humanoidRootPart then
            humanoidRootPart.Anchored = false
        end
        
        -- Clean up IK control
        if self.ikControls and self.ikControls[player.UserId] then
            self.ikControls[player.UserId]:Destroy()
            self.ikControls[player.UserId] = nil
        end
    end
end

function PongGame:update(deltaTime: number)
    -- Print debug info every second
    if os.clock() - self.lastDebugPrint > 1 then
        self.lastDebugPrint = os.clock()
        local timeInState = math.floor(os.clock() - self.lastStateChange)
        local p1Name = self.gameState.player1 and self.gameState.player1.Name or "None"
        local p2Name = self.gameState.player2 and self.gameState.player2.Name or "None"
        print(string.format("[PongGame] State: %s (for %ds) | P1: %s (%d) | P2: %s (%d)", 
            self.gameState.state,
            timeInState,
            p1Name,
            self.gameState.p1Score,
            p2Name,
            self.gameState.p2Score
        ))
    end
    
    if self.gameState.state == GameState.ATTRACT_MODE then
        self:updateAttractMode(deltaTime)
    elseif self.gameState.state == GameState.WAITING_FOR_P2 then
        self:updateAttractMode(deltaTime)
    else -- PLAYING
        self:updatePlaying(deltaTime)
    end
end

function PongGame:updateAttractMode(deltaTime: number)
    -- Update ball position
    self.ballPosition = self.ballPosition + self.ballVelocity * deltaTime
    
    -- Check for top/bottom collisions
    if self.ballPosition.Y <= 0 or self.ballPosition.Y >= 1 then
        self.ballVelocity = Vector2.new(self.ballVelocity.X, -self.ballVelocity.Y)
        self.ballPosition = Vector2.new(
            self.ballPosition.X,
            math.clamp(self.ballPosition.Y, 0, 1)
        )
    end
    
    -- Update AI paddle positions
    self:updateAI(deltaTime)
    self:updateAI2(deltaTime)
    
    -- Check for paddle collisions
    self:checkPaddleCollisions()
    
    -- Check for scoring
    if self.ballPosition.X <= 0 then
        -- Right scores in playing mode only
        if self.gameState.state == GameState.PLAYING then
            self.gameState.p2Score += 1
        end
        -- Just bounce in attract/waiting mode
        self.ballVelocity = Vector2.new(math.abs(self.ballVelocity.X), self.ballVelocity.Y)
        self.ballPosition = Vector2.new(0, self.ballPosition.Y)
    elseif self.ballPosition.X >= 1 then
        -- Left scores in playing mode only
        if self.gameState.state == GameState.PLAYING then
            self.gameState.p1Score += 1
        end
        -- Just bounce in attract/waiting mode
        self.ballVelocity = Vector2.new(-math.abs(self.ballVelocity.X), self.ballVelocity.Y)
        self.ballPosition = Vector2.new(1, self.ballPosition.Y)
    end
end

function PongGame:updatePlaying(deltaTime: number)
    -- Similar to attract mode but with player control
    self.ballPosition = self.ballPosition + self.ballVelocity * deltaTime
    
    -- Check for top/bottom collisions
    if self.ballPosition.Y <= 0 or self.ballPosition.Y >= 1 then
        self.ballVelocity = Vector2.new(self.ballVelocity.X, -self.ballVelocity.Y)
        self.ballPosition = Vector2.new(
            self.ballPosition.X,
            math.clamp(self.ballPosition.Y, 0, 1)
        )
    end
    
    -- Update player paddle positions (will implement later)
    -- For now, use AI
    self:updateAI(deltaTime)
    self:updateAI2(deltaTime)
    
    -- Check for paddle collisions
    self:checkPaddleCollisions()
    
    -- Check for scoring
    if self.ballPosition.X <= 0 then
        -- Right scores
        if self.gameState.state == GameState.PLAYING then
            self.gameState.p2Score += 1
        end
        self:resetBall(false)
    elseif self.ballPosition.X >= 1 then
        -- Left scores
        if self.gameState.state == GameState.PLAYING then
            self.gameState.p1Score += 1
        end
        self:resetBall(false)
    end
end

function PongGame:updateAI(deltaTime: number)
    -- Simple AI: Follow the ball with some delay
    local targetY = self.ballPosition.Y
    local currentY = self.paddlePosition
    local diff = targetY - currentY
    
    -- Add some randomness and delay to make it beatable
    local maxSpeed = PADDLE_SPEED * 0.8
    local deadzone = 0.02
    
    if math.abs(diff) > deadzone then
        local direction = diff > 0 and 1 or -1
        self.paddlePosition = math.clamp(
            currentY + direction * maxSpeed * deltaTime,
            MIN_PADDLE_Y,
            MAX_PADDLE_Y
        )
    end
end

function PongGame:updateAI2(deltaTime: number)
    -- Second AI paddle (right side)
    local targetY = self.ballPosition.Y
    local currentY = self.aiPaddlePosition
    local diff = targetY - currentY
    
    -- Add some randomness and delay to make it beatable
    local maxSpeed = PADDLE_SPEED * 0.8
    local deadzone = 0.02
    
    if math.abs(diff) > deadzone then
        local direction = diff > 0 and 1 or -1
        self.aiPaddlePosition = math.clamp(
            currentY + direction * maxSpeed * deltaTime,
            MIN_PADDLE_Y,
            MAX_PADDLE_Y
        )
    end
end

function PongGame:handleInput(inputType: string, inputState: boolean)
    if not self.gameState.isActive then return end
    
    local deltaTime = os.clock() - self.gameState.lastUpdateTime
    
    -- Move paddle based on input
    if inputType == "Up" then
        if inputState then
            self.paddlePosition = math.clamp(
                self.paddlePosition - (PADDLE_SPEED * deltaTime),
                MIN_PADDLE_Y,
                MAX_PADDLE_Y
            )
        end
    elseif inputType == "Down" then
        if inputState then
            self.paddlePosition = math.clamp(
                self.paddlePosition + (PADDLE_SPEED * deltaTime),
                MIN_PADDLE_Y,
                MAX_PADDLE_Y
            )
        end
    end
end

function PongGame:getState(): PongState
    return {
        paddlePosition = self.paddlePosition,
        aiPaddlePosition = self.aiPaddlePosition,
        ballPosition = {
            X = self.ballPosition.X,
            Y = self.ballPosition.Y
        },
        ballVelocity = {
            X = self.ballVelocity.X,
            Y = self.ballVelocity.Y
        },
        gameState = self.gameState
    }
end

function PongGame:resetBall(isAttractMode: boolean?)
    -- Reset ball to center with random Y velocity
    self.ballPosition = Vector2.new(0.5, 0.5)
    local speed = BALL_SPEED
    local randomY = (math.random() - 0.5) * speed -- Random Y between -speed/2 and speed/2
    
    -- In attract mode, ball moves slower and more predictably
    if isAttractMode then
        self.ballVelocity = Vector2.new(speed * 0.8, randomY * 0.5)
    else
        -- During gameplay, add some randomness to the X direction too
        local angle = math.rad(math.random(-30, 30))
        self.ballVelocity = Vector2.new(
            math.cos(angle) * speed,
            math.sin(angle) * speed
        )
    end
end

function PongGame:checkPaddleCollisions()
    -- Check for left paddle collision
    if self.ballPosition.X <= PADDLE_X_OFFSET + RELATIVE_BALL_SIZE/2 then
        if math.abs(self.ballPosition.Y - self.paddlePosition) < RELATIVE_PADDLE_HEIGHT/2 then
            -- Reverse X direction and add some Y based on where it hit the paddle
            local hitOffset = (self.ballPosition.Y - self.paddlePosition) / (RELATIVE_PADDLE_HEIGHT/2)
            self.ballVelocity = Vector2.new(
                BALL_SPEED,
                hitOffset * BALL_SPEED
            )
            self.ballPosition = Vector2.new(PADDLE_X_OFFSET + RELATIVE_BALL_SIZE/2, self.ballPosition.Y)
        else
            -- Miss! Reset ball
            print("[PongGame] Ball missed left paddle")
            self:resetBall()
            return
        end
    end
    
    -- Check for right paddle collision
    if self.ballPosition.X >= (1 - PADDLE_X_OFFSET - RELATIVE_BALL_SIZE/2) then
        if math.abs(self.ballPosition.Y - self.aiPaddlePosition) < RELATIVE_PADDLE_HEIGHT/2 then
            -- Reverse X direction and add some Y based on where it hit the paddle
            local hitOffset = (self.ballPosition.Y - self.aiPaddlePosition) / (RELATIVE_PADDLE_HEIGHT/2)
            self.ballVelocity = Vector2.new(
                -BALL_SPEED,
                hitOffset * BALL_SPEED
            )
            self.ballPosition = Vector2.new(1 - PADDLE_X_OFFSET - RELATIVE_BALL_SIZE/2, self.ballPosition.Y)
        else
            -- Miss! Reset ball
            print("[PongGame] Ball missed right paddle")
            self:resetBall()
            return
        end
    end
end

return PongGame
