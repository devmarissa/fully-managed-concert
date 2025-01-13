local ArcadeGame = require(script.Parent.ArcadeGame)

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Events
local CabinetEvents = require(ReplicatedStorage.Shared.CabinetEvents)

-- Game constants
local BALL_SPEED = 0.3 -- Units per second (relative coordinates)
local PADDLE_SPEED = 0.8 -- Units per second
local PADDLE_HEIGHT = 0.2 -- Relative height
local PADDLE_WIDTH = 0.02 -- Relative width
local PADDLE_LEFT_X = 0.05  -- Move paddles closer to edges (5% from edge)
local PADDLE_RIGHT_X = 0.95
local INITIAL_BALL_SPEED = 0.3  -- Slower initial speed
local MAX_BALL_SPEED = 0.8
local BALL_SPEED_INCREMENT = 0.05
local BALL_SIZE = 0.02 -- Relative size
local SCREEN_PADDING = 0.05 -- Relative padding
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

-- Initialize active games table at the top level
local activeGames = {}

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
    
    -- Store original CFrames for the buttons
    self.leftPaddleOriginalCFrame = self.leftPaddle.CFrame
    self.rightPaddleOriginalCFrame = self.rightPaddle.CFrame
    
    -- Initialize game state
    self.gameState = {
        state = GameState.ATTRACT_MODE,
        isActive = false,
        player1 = nil,
        player2 = nil,
        message = "PRESS START",
        p1Score = 0,
        p2Score = 0,
        lastUpdateTime = os.clock()
    }
    
    -- Initialize paddle positions
    self.paddlePosition = 0.5  -- P1 paddle
    self.aiPaddlePosition = 0.5  -- P2 paddle
    
    -- Initialize ball
    self.ballPosition = Vector2.new(0.5, 0.5)
    self.ballVelocity = Vector2.new(0, 0)  -- Start with no velocity
    self.isCountingDown = false
    
    -- Initialize player movement variables
    self.p1Movement = nil
    self.p2Movement = nil
    
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
        
    elseif position == 2 and self.gameState.state == GameState.WAITING_FOR_P2 then
        -- Player 2 joining
        print("[PongGame] Player 2 joined:", player.Name)
        self.gameState.player2 = player
        self.gameState.state = GameState.PLAYING
        self.gameState.isActive = true
        self.gameState.p1Score = 0
        self.gameState.p2Score = 0
        
        -- Reset positions
        self.ballPosition = Vector2.new(0.5, 0.5)
        self.ballVelocity = Vector2.new(0, 0)
        self.paddlePosition = 0.5
        self.aiPaddlePosition = 0.5
        
        self.lastStateChange = os.clock()
        self:positionPlayer(player, 2)
        self:updatePrompts()
        
        -- Start initial serve sequence
        self:startServeSequence("")  -- Empty string for initial serve
    end
    
    -- Store the game instance
    activeGames[self] = true
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
    
    -- Set camera mode to first person
    local player = Players:GetPlayerFromCharacter(character)
    if player then
        local camera = workspace.CurrentCamera
        if camera then
            camera.CameraType = Enum.CameraType.Custom
            camera.CameraSubject = humanoid
            camera.FieldOfView = 70
        end
    end
    
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
            
            -- Reset camera
            local camera = workspace.CurrentCamera
            if camera then
                camera.CameraType = Enum.CameraType.Custom
                camera.CameraSubject = humanoid
                camera.FieldOfView = 70
            end
            
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
    
    -- Check for top/bottom collisions with extended bottom boundary
    if self.ballPosition.Y <= 0 then
        -- Top collision
        self.ballVelocity = Vector2.new(self.ballVelocity.X, math.abs(self.ballVelocity.Y))
        self.ballPosition = Vector2.new(self.ballPosition.X, 0)
    elseif self.ballPosition.Y >= 1.05 then  -- Extended bottom boundary
        -- Bottom collision
        self.ballVelocity = Vector2.new(self.ballVelocity.X, -math.abs(self.ballVelocity.Y))
        self.ballPosition = Vector2.new(self.ballPosition.X, 1.05)
    end
    
    -- Update AI paddles for attract mode
    self:updateAI(deltaTime)
    self:updateAI2(deltaTime)
    
    -- Check for paddle collisions
    self:checkPaddleCollisions()
    
    -- Check for left/right collisions in attract mode (only if we haven't hit a paddle)
    if self.ballPosition.X <= 0 or self.ballPosition.X >= 1 then
        -- Reset ball to center with random angle
        self.ballPosition = Vector2.new(0.5, 0.5)
        local angle = math.rad(math.random(-30, 30))
        local direction = math.random() < 0.5 and -1 or 1
        self.ballVelocity = Vector2.new(
            direction * INITIAL_BALL_SPEED * 0.7 * math.cos(angle),
            INITIAL_BALL_SPEED * 0.7 * math.sin(angle)
        )
    end
    
    -- Update display state
    self:updateState()
end

function PongGame:updatePlaying(deltaTime: number)
    -- Don't update ball position during countdown
    if not self.isCountingDown then
        -- Handle player inputs
        self:handlePlayerInput(deltaTime)
        
        -- Update ball position
        self.ballPosition = self.ballPosition + self.ballVelocity * deltaTime
        
        -- Check for top/bottom collisions with extended bottom boundary
        if self.ballPosition.Y <= 0 then
            -- Top collision
            self.ballVelocity = Vector2.new(self.ballVelocity.X, math.abs(self.ballVelocity.Y))
            self.ballPosition = Vector2.new(self.ballPosition.X, 0)
        elseif self.ballPosition.Y >= 1.05 then  -- Extended bottom boundary
            -- Bottom collision
            self.ballVelocity = Vector2.new(self.ballVelocity.X, -math.abs(self.ballVelocity.Y))
            self.ballPosition = Vector2.new(self.ballPosition.X, 1.05)
        end
        
        -- Check for scoring
        if self.ballPosition.X <= 0 then
            -- Right scores
            self.gameState.p2Score += 1
            self:checkWinCondition("Player 2")
        elseif self.ballPosition.X >= 1 then
            -- Left scores
            self.gameState.p1Score += 1
            self:checkWinCondition("Player 1")
        else
            -- Check for paddle collisions if no scoring
            self:checkPaddleCollisions()
        end
    else
        -- During countdown, still handle paddle movement
        self:handlePlayerInput(deltaTime)
    end
    
    -- Update state for display
    self:updateState()
end

function PongGame:handlePlayerInput(deltaTime: number)
    -- Handle P1 movement
    if self.p1Movement then
        if self.p1Movement == "up" then
            self.paddlePosition = math.max(MIN_PADDLE_Y, self.paddlePosition - PADDLE_SPEED * deltaTime)
            -- Rotate left paddle button and update IK offset
            if self.leftPaddle then
                self.leftPaddle.CFrame = self.leftPaddleOriginalCFrame * CFrame.Angles(math.rad(-10), 0, 0)
                if self.ikControls and self.ikControls[self.gameState.player1.UserId] then
                    self.ikControls[self.gameState.player1.UserId].Offset = CFrame.new(0, 0.2, 0)
                end
            end
        elseif self.p1Movement == "down" then
            self.paddlePosition = math.min(MAX_PADDLE_Y, self.paddlePosition + PADDLE_SPEED * deltaTime)
            -- Rotate left paddle button and update IK offset
            if self.leftPaddle then
                self.leftPaddle.CFrame = self.leftPaddleOriginalCFrame * CFrame.Angles(math.rad(10), 0, 0)
                if self.ikControls and self.ikControls[self.gameState.player1.UserId] then
                    self.ikControls[self.gameState.player1.UserId].Offset = CFrame.new(0, -0.2, 0)
                end
            end
        end
    else
        -- Reset left paddle button rotation and IK offset
        if self.leftPaddle then
            self.leftPaddle.CFrame = self.leftPaddleOriginalCFrame
            if self.ikControls and self.ikControls[self.gameState.player1.UserId] then
                self.ikControls[self.gameState.player1.UserId].Offset = CFrame.new(0, 0, 0)
            end
        end
    end
    
    -- Handle P2 movement
    if self.gameState.player2 then
        if self.p2Movement then
            if self.p2Movement == "up" then
                self.aiPaddlePosition = math.max(MIN_PADDLE_Y, self.aiPaddlePosition - PADDLE_SPEED * deltaTime)
                -- Rotate right paddle button and update IK offset
                if self.rightPaddle then
                    self.rightPaddle.CFrame = self.rightPaddleOriginalCFrame * CFrame.Angles(math.rad(-10), 0, 0)
                    if self.ikControls and self.ikControls[self.gameState.player2.UserId] then
                        self.ikControls[self.gameState.player2.UserId].Offset = CFrame.new(0, 0.2, 0)
                    end
                end
            elseif self.p2Movement == "down" then
                self.aiPaddlePosition = math.min(MAX_PADDLE_Y, self.aiPaddlePosition + PADDLE_SPEED * deltaTime)
                -- Rotate right paddle button and update IK offset
                if self.rightPaddle then
                    self.rightPaddle.CFrame = self.rightPaddleOriginalCFrame * CFrame.Angles(math.rad(10), 0, 0)
                    if self.ikControls and self.ikControls[self.gameState.player2.UserId] then
                        self.ikControls[self.gameState.player2.UserId].Offset = CFrame.new(0, -0.2, 0)
                    end
                end
            end
        else
            -- Reset right paddle button rotation and IK offset
            if self.rightPaddle then
                self.rightPaddle.CFrame = self.rightPaddleOriginalCFrame
                if self.ikControls and self.ikControls[self.gameState.player2.UserId] then
                    self.ikControls[self.gameState.player2.UserId].Offset = CFrame.new(0, 0, 0)
                end
            end
        end
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
    -- Reset ball to center
    self.ballPosition = Vector2.new(0.5, 0.5)
    
    -- Set initial velocity
    local angle = math.rad(math.random(-45, 45))
    local direction = math.random() < 0.5 and -1 or 1
    self.ballVelocity = Vector2.new(
        direction * INITIAL_BALL_SPEED * math.cos(angle),
        INITIAL_BALL_SPEED * math.sin(angle)
    )
end

function PongGame:checkPaddleCollisions()
    -- Left paddle collision check
    if self.ballPosition.X > PADDLE_LEFT_X - PADDLE_WIDTH/2 and 
       self.ballPosition.X < PADDLE_LEFT_X + PADDLE_WIDTH/2 and
       self.ballVelocity.X < 0 then  -- Only check if ball is moving left
        
        local paddleY = self.paddlePosition
        if self.ballPosition.Y >= paddleY - PADDLE_HEIGHT/2 and
           self.ballPosition.Y <= paddleY + PADDLE_HEIGHT/2 then
            -- Calculate relative intersection with paddle (-1 to 1)
            local relativeIntersectY = (self.ballPosition.Y - paddleY) / (PADDLE_HEIGHT/2)
            -- Convert to bounce angle (maximum 60 degrees)
            local bounceAngle = relativeIntersectY * math.rad(60)
            
            -- Increase speed slightly with each hit
            local currentSpeed = math.sqrt(self.ballVelocity.X^2 + self.ballVelocity.Y^2)
            local newSpeed = math.min(currentSpeed + BALL_SPEED_INCREMENT, MAX_BALL_SPEED)
            
            -- Set new velocity
            self.ballVelocity = Vector2.new(
                newSpeed * math.cos(bounceAngle),
                newSpeed * math.sin(bounceAngle)
            )
            
            -- Place ball at paddle edge
            self.ballPosition = Vector2.new(PADDLE_LEFT_X + PADDLE_WIDTH/2, self.ballPosition.Y)
        end
    end
    
    -- Right paddle collision check
    if self.ballPosition.X < PADDLE_RIGHT_X + PADDLE_WIDTH/2 and 
       self.ballPosition.X > PADDLE_RIGHT_X - PADDLE_WIDTH/2 and
       self.ballVelocity.X > 0 then  -- Only check if ball is moving right
        
        local paddleY = self.aiPaddlePosition
        if self.ballPosition.Y >= paddleY - PADDLE_HEIGHT/2 and
           self.ballPosition.Y <= paddleY + PADDLE_HEIGHT/2 then
            -- Calculate relative intersection with paddle (-1 to 1)
            local relativeIntersectY = (self.ballPosition.Y - paddleY) / (PADDLE_HEIGHT/2)
            -- Convert to bounce angle (maximum 60 degrees)
            local bounceAngle = relativeIntersectY * math.rad(60)
            
            -- Increase speed slightly with each hit
            local currentSpeed = math.sqrt(self.ballVelocity.X^2 + self.ballVelocity.Y^2)
            local newSpeed = math.min(currentSpeed + BALL_SPEED_INCREMENT, MAX_BALL_SPEED)
            
            -- Set new velocity
            self.ballVelocity = Vector2.new(
                -newSpeed * math.cos(bounceAngle),
                newSpeed * math.sin(bounceAngle)
            )
            
            -- Place ball at paddle edge
            self.ballPosition = Vector2.new(PADDLE_RIGHT_X - PADDLE_WIDTH/2, self.ballPosition.Y)
        end
    end
end

function PongGame:checkWinCondition(lastScorer: string)
    if self.gameState.p1Score >= 11 or self.gameState.p2Score >= 11 then
        -- Check for win by 2
        if math.abs(self.gameState.p1Score - self.gameState.p2Score) >= 2 then
            -- Game over!
            self.isCountingDown = true
            self.ballVelocity = Vector2.new(0, 0)
            
            -- Exit players from the game
            self:exitPlayers()
            
            local winner = self.gameState.p1Score > self.gameState.p2Score and "Player 1" or "Player 2"
            self.gameState.message = string.format("%s Wins! Final Score: %d-%d", 
                winner, self.gameState.p1Score, self.gameState.p2Score)
            
            -- Update state immediately
            self:updateState()
            
            -- Reset game after delay
            task.spawn(function()
                wait(5)
                
                -- Reset game state
                self.gameState.state = GameState.ATTRACT_MODE
                self.gameState.message = "PRESS START"
                self.gameState.p1Score = 0
                self.gameState.p2Score = 0
                self.gameState.isActive = false
                self.gameState.player1 = nil
                self.gameState.player2 = nil
                
                -- Reset positions
                self.paddlePosition = 0.5
                self.aiPaddlePosition = 0.5
                self.ballPosition = Vector2.new(0.5, 0.5)
                self.ballVelocity = Vector2.new(0, 0)
                
                -- Update display and prompts
                self:updateState()
                self:updatePrompts()
                
                -- Start attract mode
                self:resetBall(true)
            end)
            return true
        end
    end
    
    -- No win condition met, continue with regular scoring
    self:startServeSequence(lastScorer)
    return false
end

function PongGame:updateState()
    -- Update the display state
    self.displayState = {
        paddlePosition = self.paddlePosition,
        aiPaddlePosition = self.aiPaddlePosition,
        ballPosition = self.ballPosition,
        -- Hide ball during countdown or when any message is displayed
        ballVisible = not self.isCountingDown and self.gameState.message == "",
        gameState = {
            state = self.gameState.state,
            message = self.gameState.message,
            p1Score = self.gameState.p1Score,
            p2Score = self.gameState.p2Score,
            isActive = self.gameState.isActive,
            player1 = self.gameState.player1,
            player2 = self.gameState.player2
        }
    }
    
    -- Notify all clients of the state change
    for _, player in game.Players:GetPlayers() do
        if player == self.gameState.player1 or player == self.gameState.player2 then
            CabinetEvents.GameStateChanged:FireClient(player, self.cabinet, self.gameState.state, 
                self.gameState.player1, self.gameState.player2, self.displayState)
        end
    end
end

function PongGame:startServeSequence(scoringPlayer: string)
    self.isCountingDown = true
    self.lastScorer = scoringPlayer
    
    -- Move ball off screen during countdown
    self.ballPosition = Vector2.new(-1, -1)
    self.ballVelocity = Vector2.new(0, 0)
    
    -- Reset paddle positions
    self.paddlePosition = 0.5
    self.aiPaddlePosition = 0.5
    
    -- Show score message
    if scoringPlayer ~= "" then  -- Don't show for initial serve
        self.gameState.message = string.format("%s Scores! %d-%d", scoringPlayer, self.gameState.p1Score, self.gameState.p2Score)
    else
        self.gameState.message = "3"  -- Start countdown immediately for initial serve
    end
    
    -- Update state immediately to hide ball
    self:updateState()
    
    -- Start countdown sequence
    task.spawn(function()
        if scoringPlayer ~= "" then  -- Skip initial delay for first serve
            wait(2) -- Show score message
        end
        if self.gameState.state ~= GameState.PLAYING then return end
        self.gameState.message = "3"
        self:updateState()
        wait(1)
        if self.gameState.state ~= GameState.PLAYING then return end
        self.gameState.message = "2"
        self:updateState()
        wait(1)
        if self.gameState.state ~= GameState.PLAYING then return end
        self.gameState.message = "1"
        self:updateState()
        wait(1)
        if self.gameState.state ~= GameState.PLAYING then return end
        
        -- Reset ball to center only after countdown completes
        self.ballPosition = Vector2.new(0.5, 0.5)
        self.gameState.message = ""
        self.isCountingDown = false
        self:resetBall()
        self:updateState()
    end)
end

function PongGame:exitPlayers()
    -- Store original states and restore them
    if self.gameState.player1 then
        local character = self.gameState.player1.Character
        if character then
            local humanoid = character:FindFirstChild("Humanoid")
            if humanoid then
                -- Restore movement
                humanoid.WalkSpeed = 16  -- Default walk speed
                humanoid.AutoRotate = true
                humanoid.JumpPower = 50  -- Default jump power
                
                -- Unanchor all parts
                for _, part in character:GetDescendants() do
                    if part:IsA("BasePart") then
                        part.Anchored = false
                    end
                end
            end
        end
        self:disableIKControl(self.gameState.player1)
    end
    
    if self.gameState.player2 then
        local character = self.gameState.player2.Character
        if character then
            local humanoid = character:FindFirstChild("Humanoid")
            if humanoid then
                -- Restore movement
                humanoid.WalkSpeed = 16  -- Default walk speed
                humanoid.AutoRotate = true
                humanoid.JumpPower = 50  -- Default jump power
                
                -- Unanchor all parts
                for _, part in character:GetDescendants() do
                    if part:IsA("BasePart") then
                        part.Anchored = false
                    end
                end
            end
        end
        self:disableIKControl(self.gameState.player2)
    end
end

function PongGame:disableIKControl(player: Player)
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            for _, ikControl in pairs(humanoid:GetChildren()) do
                if ikControl:IsA("IKControl") then
                    ikControl:Destroy()
                end
            end
        end
    end
end

-- Listen for player input
CabinetEvents.PlayerInput.OnServerEvent:Connect(function(player, cabinet, direction, isActive)
    -- Find the game instance for this cabinet
    for game in pairs(activeGames) do
        if game.cabinet == cabinet then
            -- Handle player 1 input
            if game.gameState.player1 == player then
                if direction == "start" or direction == "end" then
                    game.p1Movement = nil
                else
                    game.p1Movement = isActive and direction or nil
                end
                return
            end
            
            -- Handle player 2 input
            if game.gameState.player2 == player then
                if direction == "start" or direction == "end" then
                    game.p2Movement = nil
                else
                    game.p2Movement = isActive and direction or nil
                end
                return
            end
        end
    end
end)

return PongGame
