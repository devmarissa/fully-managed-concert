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
        score = 0,
        highScore = 0,
        lastUpdateTime = os.clock(),
        player1 = nil,
        player2 = nil,
        message = "PRESS START"
    }
    
    -- Debug info (for logging only)
    self.debugInfo = {
        resetCount = 0,
        lastResetTime = 0,
        ballPositionHistory = {}
    }
    
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
        self.p2Prompt.Enabled = false
        CabinetEvents.GameStateChanged:FireAllClients(self.cabinet, self.gameState.state, nil)
    elseif self.gameState.state == GameState.WAITING_FOR_P2 then
        -- Waiting for P2, P1 prompt disabled, P2 prompt enabled
        self.p1Prompt.Enabled = false
        self.p2Prompt.Enabled = true
        CabinetEvents.GameStateChanged:FireAllClients(self.cabinet, self.gameState.state, self.gameState.player1)
    else
        -- During gameplay, both prompts disabled
        self.p1Prompt.Enabled = false
        self.p2Prompt.Enabled = false
        CabinetEvents.GameStateChanged:FireAllClients(self.cabinet, self.gameState.state, self.gameState.player1)
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
    
    -- Disable all state changes except for Physics
    for _, state in pairs(Enum.HumanoidStateType:GetEnumItems()) do
        if state ~= Enum.HumanoidStateType.Physics then
            humanoid:SetStateEnabled(state, false)
        end
    end
    
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
            
            -- Re-enable all states
            for _, state in pairs(Enum.HumanoidStateType:GetEnumItems()) do
                humanoid:SetStateEnabled(state, true)
            end
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

function PongGame:startGame(player: Player, position: number)
    if position == 1 and self.gameState.state == GameState.ATTRACT_MODE then
        -- Player 1 joining
        print("[PongGame] Player 1 joined:", player.Name)
        self.gameState.player1 = player
        self.gameState.state = GameState.WAITING_FOR_P2
        self.gameState.message = "WAITING FOR PLAYER 2"
        self:positionPlayer(player, 1)
        self:updatePrompts()
    elseif position == 2 and self.gameState.state == GameState.WAITING_FOR_P2 then
        -- Player 2 joining, start the game
        print("[PongGame] Player 2 joined:", player.Name)
        self.gameState.player2 = player
        self.gameState.state = GameState.PLAYING
        self.gameState.isActive = true
        self.gameState.score = 0
        self.gameState.message = ""
        self:positionPlayer(player, 2)
        self:updatePrompts()
        self:resetBall()
    end
end

function PongGame:playerLeft(player: Player)
    if player == self.gameState.player1 or player == self.gameState.player2 then
        print("[PongGame] Player left:", player.Name)
        -- Remove IK control and unanchor player
        self:removePlayer(player)
        -- Reset to attract mode
        self.gameState.state = GameState.ATTRACT_MODE
        self.gameState.isActive = false
        self.gameState.player1 = nil
        self.gameState.player2 = nil
        self.gameState.score = 0
        self.gameState.message = "PRESS START"
        self:updatePrompts()
        self:resetBall(true)
    end
end

function PongGame:getState()
    return self.gameState
end

function PongGame:updateAttractMode(deltaTime: number)
    -- Store previous position for debugging
    table.insert(self.debugInfo.ballPositionHistory, {
        position = self.ballPosition,
        velocity = self.ballVelocity,
        time = os.clock()
    })
    if #self.debugInfo.ballPositionHistory > 10 then
        table.remove(self.debugInfo.ballPositionHistory, 1)
    end
    
    -- Update ball position
    local newPosition = Vector2.new(
        self.ballPosition.X + (self.ballVelocity.X * deltaTime),
        self.ballPosition.Y + (self.ballVelocity.Y * deltaTime)
    )
    
    -- Ball hits top or bottom
    if newPosition.Y <= 0 or newPosition.Y >= 1 then
        self.ballVelocity = Vector2.new(self.ballVelocity.X, -self.ballVelocity.Y)
        newPosition = Vector2.new(newPosition.X, math.clamp(newPosition.Y, 0, 1))
    end
    
    -- Ball hits paddles
    if newPosition.X <= PADDLE_X_OFFSET + RELATIVE_BALL_SIZE/2 then -- Left paddle
        if math.abs(newPosition.Y - self.paddlePosition) < RELATIVE_PADDLE_HEIGHT/2 then
            -- Reverse X direction and add some Y based on where it hit the paddle
            local hitOffset = (newPosition.Y - self.paddlePosition) / (RELATIVE_PADDLE_HEIGHT/2)
            self.ballVelocity = Vector2.new(
                BALL_SPEED,
                hitOffset * BALL_SPEED
            )
            newPosition = Vector2.new(PADDLE_X_OFFSET + RELATIVE_BALL_SIZE/2, newPosition.Y)
        else
            -- Miss! Reset ball
            print("[PongGame] Ball missed left paddle")
            self:resetBall(true)
            return
        end
    elseif newPosition.X >= (1 - PADDLE_X_OFFSET - RELATIVE_BALL_SIZE/2) then -- Right paddle
        if math.abs(newPosition.Y - self.aiPaddlePosition) < RELATIVE_PADDLE_HEIGHT/2 then
            -- Reverse X direction and add some Y based on where it hit the paddle
            local hitOffset = (newPosition.Y - self.aiPaddlePosition) / (RELATIVE_PADDLE_HEIGHT/2)
            self.ballVelocity = Vector2.new(
                -BALL_SPEED,
                hitOffset * BALL_SPEED
            )
            newPosition = Vector2.new(1 - PADDLE_X_OFFSET - RELATIVE_BALL_SIZE/2, newPosition.Y)
        else
            -- Miss! Reset ball
            print("[PongGame] Ball missed right paddle")
            self:resetBall(true)
            return
        end
    end
    
    -- Ensure ball stays within bounds
    newPosition = Vector2.new(
        math.clamp(newPosition.X, 0, 1),
        math.clamp(newPosition.Y, 0, 1)
    )

    -- Reset ball if it goes past paddles
    if newPosition.X <= 0 or newPosition.X >= 1 then
        print("[PongGame] Ball out of bounds, resetting")
        self:resetBall(true)
        return
    end

    -- Update ball position
    self.ballPosition = newPosition
    
    -- Move AI paddle towards ball
    local targetY = newPosition.Y
    local aiDelta = targetY - self.aiPaddlePosition
    
    if math.abs(aiDelta) > 0.01 then -- Add some deadzone
        self.aiPaddlePosition = math.clamp(
            self.aiPaddlePosition + math.sign(aiDelta) * PADDLE_SPEED * deltaTime,
            MIN_PADDLE_Y,
            MAX_PADDLE_Y
        )
    end
    
    -- Update paddles to follow ball
    local function updatePaddle(currentPos: number, targetY: number): number
        local diff = targetY - currentPos
        if math.abs(diff) > 0.01 then
            return math.clamp(
                currentPos + (math.sign(diff) * PADDLE_SPEED * deltaTime),
                MIN_PADDLE_Y,
                MAX_PADDLE_Y
            )
        end
        return currentPos
    end
    
    -- Left paddle
    self.paddlePosition = updatePaddle(self.paddlePosition, self.ballPosition.Y)
    
    -- Right paddle
    self.aiPaddlePosition = updatePaddle(self.aiPaddlePosition, self.ballPosition.Y)
    
    -- Print debug info every second
    if os.clock() - (self.lastDebugPrint or 0) > 1 then
        self.lastDebugPrint = os.clock()
        print(string.format("[PongGame] Ball: pos=(%.2f, %.2f) vel=(%.2f, %.2f)", 
            self.ballPosition.X, self.ballPosition.Y,
            self.ballVelocity.X, self.ballVelocity.Y
        ))
    end
end

function PongGame:update(deltaTime: number)
    if not self.gameState.isActive then
        -- Run attract mode when no one is playing
        self:updateAttractMode(deltaTime)
        return
    end
    
    -- Store previous position for debugging
    table.insert(self.debugInfo.ballPositionHistory, {
        position = self.ballPosition,
        velocity = self.ballVelocity,
        time = os.clock()
    })
    if #self.debugInfo.ballPositionHistory > 10 then
        table.remove(self.debugInfo.ballPositionHistory, 1)
    end
    
    -- Update ball position
    local newPosition = Vector2.new(
        self.ballPosition.X + (self.ballVelocity.X * deltaTime),
        self.ballPosition.Y + (self.ballVelocity.Y * deltaTime)
    )
    
    -- Ball hits top or bottom
    if newPosition.Y <= 0 or newPosition.Y >= 1 then
        self.ballVelocity = Vector2.new(self.ballVelocity.X, -self.ballVelocity.Y)
        newPosition = Vector2.new(newPosition.X, math.clamp(newPosition.Y, 0, 1))
    end
    
    -- Ball hits paddles
    if newPosition.X <= PADDLE_X_OFFSET + RELATIVE_BALL_SIZE/2 then -- Left paddle
        if math.abs(newPosition.Y - self.paddlePosition) < RELATIVE_PADDLE_HEIGHT/2 then
            print(string.format("[PongGame] Ball hit left paddle at Y=%.2f", self.paddlePosition))
            -- Reverse X direction and add some Y based on where it hit the paddle
            local hitOffset = (newPosition.Y - self.paddlePosition) / (RELATIVE_PADDLE_HEIGHT/2)
            self.ballVelocity = Vector2.new(
                BALL_SPEED,
                hitOffset * BALL_SPEED
            )
            newPosition = Vector2.new(PADDLE_X_OFFSET + RELATIVE_BALL_SIZE/2, newPosition.Y)
        else
            -- Miss! Reset ball
            print("[PongGame] Ball missed left paddle")
            self:resetBall()
            return
        end
    elseif newPosition.X >= (1 - PADDLE_X_OFFSET - RELATIVE_BALL_SIZE/2) then -- Right paddle
        if math.abs(newPosition.Y - self.aiPaddlePosition) < RELATIVE_PADDLE_HEIGHT/2 then
            print(string.format("[PongGame] Ball hit right paddle at Y=%.2f", self.aiPaddlePosition))
            -- Reverse X direction and add some Y based on where it hit the paddle
            local hitOffset = (newPosition.Y - self.aiPaddlePosition) / (RELATIVE_PADDLE_HEIGHT/2)
            self.ballVelocity = Vector2.new(
                -BALL_SPEED,
                hitOffset * BALL_SPEED
            )
            newPosition = Vector2.new(1 - PADDLE_X_OFFSET - RELATIVE_BALL_SIZE/2, newPosition.Y)
        else
            -- Miss! Reset ball
            print("[PongGame] Ball missed right paddle")
            self:resetBall()
            return
        end
    end
    
    -- Ensure ball stays within bounds
    newPosition = Vector2.new(
        math.clamp(newPosition.X, 0, 1),
        math.clamp(newPosition.Y, 0, 1)
    )

    -- Reset ball if it goes past paddles
    if newPosition.X <= 0 or newPosition.X >= 1 then
        print("[PongGame] Ball out of bounds, resetting")
        self:resetBall()
        return
    end

    -- Update ball position
    self.ballPosition = newPosition
    
    -- Update AI paddle (simple follow behavior)
    local targetY = self.ballPosition.Y
    local aiDelta = targetY - self.aiPaddlePosition
    
    if math.abs(aiDelta) > 0.01 then -- Add some deadzone
        self.aiPaddlePosition = math.clamp(
            self.aiPaddlePosition + math.sign(aiDelta) * PADDLE_SPEED * deltaTime,
            MIN_PADDLE_Y,
            MAX_PADDLE_Y
        )
    end
    
    -- Print debug info every second
    if os.clock() - (self.lastDebugPrint or 0) > 1 then
        self.lastDebugPrint = os.clock()
        print(string.format("[PongGame] Ball: pos=(%.2f, %.2f) vel=(%.2f, %.2f)", 
            self.ballPosition.X, self.ballPosition.Y,
            self.ballVelocity.X, self.ballVelocity.Y
        ))
    end
end

function PongGame:updateAI(deltaTime: number)
    -- Simple AI: Follow the ball with some delay
    local targetY = self.ballPosition.Y
    local diff = targetY - self.aiPaddlePosition
    
    -- Add some intentional "sloppiness" to make it beatable
    if math.abs(diff) > 0.1 then
        self.aiPaddlePosition = self.aiPaddlePosition + (math.sign(diff) * PADDLE_SPEED * deltaTime)
    end
    
    -- Clamp paddle position
    self.aiPaddlePosition = math.clamp(self.aiPaddlePosition, MIN_PADDLE_Y, MAX_PADDLE_Y)
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
    if self.debugInfo then
        self.debugInfo.resetCount += 1
        self.debugInfo.lastResetTime = os.clock()
        print(string.format("[PongGame] Ball reset #%d at time %.2f", self.debugInfo.resetCount, self.debugInfo.lastResetTime))
    end
    
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
    
    if self.debugInfo then
        print(string.format("[PongGame] New ball velocity: (%.2f, %.2f)", self.ballVelocity.X, self.ballVelocity.Y))
    end
end

return PongGame
