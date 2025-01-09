--!strict
local Roact = require(game.ReplicatedStorage.Shared.Roact)
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Get remote events
local remotes = ReplicatedStorage:WaitForChild("PongRemotes")
local gameStateChangedEvent = remotes:WaitForChild("GameStateChanged") :: RemoteEvent
local updateScoreEvent = remotes:WaitForChild("UpdateScore") :: RemoteEvent

-- Constants (adjusted to match original Pong)
local PADDLE_WIDTH = 10
local PADDLE_HEIGHT = 40
local PADDLE_MARGIN = 20
local BALL_SIZE = 10
local INITIAL_BALL_SPEED = 200  -- Initial speed
local MAX_BALL_SPEED = 400     -- Max speed after bounces
local SPEED_INCREASE = 20      -- Speed increase per hit
local PADDLE_SPEED = 300
local SCORE_TO_WIN = 11        -- Original Pong went to 11
local AI_SPEED = 250          -- Slightly slower than player speed
local FIXED_ANGLES = {
    math.rad(15),  -- Shallow angle
    math.rad(35)   -- Steep angle
}

-- Game component
local Pong = Roact.Component:extend("Pong")

function Pong:init()
    self:setState({
        gameState = "attract",
        p1Present = false,
        p2Present = false,
        ballPosition = Vector2.new(0.5, 0.5),
        ballVelocity = Vector2.new(INITIAL_BALL_SPEED, 0),
        currentBallSpeed = INITIAL_BALL_SPEED,
        leftPaddlePos = 0.5,
        rightPaddlePos = 0.5,
        leftPaddleVelocity = 0,
        rightPaddleVelocity = 0,
        leftScore = 0,
        rightScore = 0,
        winner = nil,
        time = 0
    })
    
    -- Listen for game state changes
    self.gameStateConnection = gameStateChangedEvent.OnClientEvent:Connect(function(newState)
        self:setState({
            gameState = newState.state,
            p1Present = newState.p1Present,
            p2Present = newState.p2Present,
            leftScore = newState.leftScore,
            rightScore = newState.rightScore
        })
    end)
    
    -- Listen for score updates
    self.scoreUpdateConnection = updateScoreEvent.OnClientEvent:Connect(function(leftScore, rightScore)
        self:setState({
            leftScore = leftScore,
            rightScore = rightScore
        })
    end)
end

function Pong:didMount()
    -- Input handling
    self.inputConnection = UserInputService.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Space then
            if self.state.gameState == "waiting" and self.state.p1Present and self.state.p2Present then
                -- Update local state
                self:setState({ gameState = "playing" })
                -- Notify server
                gameStateChangedEvent:FireServer("playing")
            elseif self.state.gameState == "gameOver" then
                -- Update local state
                self:setState({
                    gameState = self.state.p1Present and self.state.p2Present and "playing" or "attract",
                    leftScore = 0,
                    rightScore = 0,
                    winner = nil,
                })
                -- Notify server
                gameStateChangedEvent:FireServer(self.state.p1Present and self.state.p2Present and "playing" or "attract")
                updateScoreEvent:FireServer(0, 0)
                self:resetBall()
            end
        end
    end)

    -- Game loop
    self.gameConnection = RunService.RenderStepped:Connect(function(dt)
        if self.state.gameState == "playing" or self.state.gameState == "attract" then
            self:updateGame(dt)
        end
    end)
    
    -- Player presence monitoring
    if self.props.controller then
        self.p1Connection = self.props.controller.p1State.prompt.Triggered:Connect(function()
            self:setState({
                p1Present = true,
                gameState = "waiting"
            })
        end)
        
        self.p2Connection = self.props.controller.p2State.prompt.Triggered:Connect(function()
            self:setState({
                p2Present = true,
                gameState = "waiting"
            })
        end)
        
        -- Monitor when players leave
        self.leaveCheckConnection = RunService.Heartbeat:Connect(function()
            if self.props.controller.p1State.isAnchored == false and self.state.p1Present then
                self:setState({
                    p1Present = false,
                    gameState = "attract",
                    leftScore = 0,
                    rightScore = 0
                })
            end
            if self.props.controller.p2State.isAnchored == false and self.state.p2Present then
                self:setState({
                    p2Present = false,
                    gameState = "attract",
                    leftScore = 0,
                    rightScore = 0
                })
            end
        end)
    end
end

function Pong:willUnmount()
    if self.gameConnection then
        self.gameConnection:Disconnect()
    end
    if self.inputConnection then
        self.inputConnection:Disconnect()
    end
    if self.gameStateConnection then
        self.gameStateConnection:Disconnect()
    end
    if self.scoreUpdateConnection then
        self.scoreUpdateConnection:Disconnect()
    end
    if self.p1Connection then
        self.p1Connection:Disconnect()
    end
    if self.p2Connection then
        self.p2Connection:Disconnect()
    end
    if self.leaveCheckConnection then
        self.leaveCheckConnection:Disconnect()
    end
end

function Pong:resetBall()
    local direction = math.random() > 0.5 and 1 or -1
    -- Use fixed 15 degree angle for serve
    local angle = FIXED_ANGLES[1] * (math.random() > 0.5 and 1 or -1)
    
    self:setState({
        ballPosition = Vector2.new(0.5, 0.5),
        ballVelocity = Vector2.new(
            math.cos(angle) * INITIAL_BALL_SPEED * direction,
            math.sin(angle) * INITIAL_BALL_SPEED
        ),
        currentBallSpeed = INITIAL_BALL_SPEED
    })
end

function Pong:updateAI(dt, ballPos, state)
    local aiSpeed = AI_SPEED
    local leftVelocity = 0
    local rightVelocity = 0
    
    if state.gameState == "attract" then
        -- Predict ball position
        local function predictBallY(paddleX)
            local timeToReach
            if state.ballVelocity.X > 0 then
                timeToReach = (paddleX - ballPos.X) / (state.ballVelocity.X / self.props.resolution.X)
            else
                timeToReach = (ballPos.X - paddleX) / (-state.ballVelocity.X / self.props.resolution.X)
            end
            
            if timeToReach <= 0 then return ballPos.Y end
            
            -- Calculate predicted Y including bounces
            local predictedY = ballPos.Y + (state.ballVelocity.Y / self.props.resolution.Y) * timeToReach
            local bounces = 0
            while (predictedY < 0 or predictedY > 1) and bounces < 4 do
                if predictedY < 0 then
                    predictedY = -predictedY
                elseif predictedY > 1 then
                    predictedY = 2 - predictedY
                end
                bounces = bounces + 1
            end
            return predictedY
        end
        
        -- Calculate target positions with slight offset
        local leftPaddleX = PADDLE_MARGIN / self.props.resolution.X
        local rightPaddleX = 1 - PADDLE_MARGIN / self.props.resolution.X - PADDLE_WIDTH / self.props.resolution.X
        
        -- Add small random offset to make it look more natural
        local function getAIVelocity(currentPos, targetY)
            local offset = math.sin(state.time * 2) * 0.03
            local adjustedTarget = targetY + offset
            local diff = adjustedTarget - currentPos
            
            -- Move more precisely when ball is close
            local threshold = math.abs(state.ballVelocity.X) > 300 and 0.02 or 0.05
            if math.abs(diff) > threshold then
                return math.sign(diff) * aiSpeed
            end
            return 0
        end
        
        -- Update paddle velocities based on prediction
        if state.ballVelocity.X < 0 then
            local leftTarget = predictBallY(leftPaddleX)
            leftVelocity = getAIVelocity(state.leftPaddlePos, leftTarget)
        else
            -- Keep left paddle in center when ball moving away
            leftVelocity = getAIVelocity(state.leftPaddlePos, 0.5)
        end
        
        if state.ballVelocity.X > 0 then
            local rightTarget = predictBallY(rightPaddleX)
            rightVelocity = getAIVelocity(state.rightPaddlePos, rightTarget)
        else
            -- Keep right paddle in center when ball moving away
            rightVelocity = getAIVelocity(state.rightPaddlePos, 0.5)
        end
    end
    
    return leftVelocity, rightVelocity
end

function Pong:updateGame(dt)
    self:setState(function(state)
        local newState = table.clone(state)
        
        -- Update time
        newState.time = state.time + dt
        
        -- Update paddle velocities
        if state.gameState == "attract" then
            -- AI controls both paddles
            newState.leftPaddleVelocity, newState.rightPaddleVelocity = self:updateAI(dt, state.ballPosition, state)
        else
            -- Player controls - only update if we're the player
            if state.p1Present and self.props.controller.p1State.player == Players.LocalPlayer then
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                    newState.leftPaddleVelocity = -PADDLE_SPEED
                elseif UserInputService:IsKeyDown(Enum.KeyCode.S) then
                    newState.leftPaddleVelocity = PADDLE_SPEED
                else
                    newState.leftPaddleVelocity = 0
                end
            end
            if state.p2Present and self.props.controller.p2State.player == Players.LocalPlayer then
                if UserInputService:IsKeyDown(Enum.KeyCode.Up) then
                    newState.rightPaddleVelocity = -PADDLE_SPEED
                elseif UserInputService:IsKeyDown(Enum.KeyCode.Down) then
                    newState.rightPaddleVelocity = PADDLE_SPEED
                else
                    newState.rightPaddleVelocity = 0
                end
            end
        end
        
        -- Convert all sizes to screen space once
        local screenPaddleHeight = PADDLE_HEIGHT / self.props.resolution.Y
        local screenPaddleWidth = PADDLE_WIDTH / self.props.resolution.X
        local screenBallSize = BALL_SIZE / math.min(self.props.resolution.X, self.props.resolution.Y)
        
        -- Calculate absolute boundaries for paddles
        local minPaddleY = screenBallSize + screenPaddleHeight/2  -- Keep paddle fully in bounds
        local maxPaddleY = 1 - screenBallSize - screenPaddleHeight/2
        
        -- Update and clamp paddle positions
        newState.leftPaddlePos = math.clamp(
            state.leftPaddlePos + (state.leftPaddleVelocity * dt) / self.props.resolution.Y,
            minPaddleY,
            maxPaddleY
        )
        newState.rightPaddlePos = math.clamp(
            state.rightPaddlePos + (state.rightPaddleVelocity * dt) / self.props.resolution.Y,
            minPaddleY,
            maxPaddleY
        )
        
        -- Calculate new ball position
        local newBallPos = Vector2.new(
            state.ballPosition.X + (state.ballVelocity.X * dt) / self.props.resolution.X,
            state.ballPosition.Y + (state.ballVelocity.Y * dt) / self.props.resolution.Y
        )
        
        -- Ball collision with top/bottom walls
        if newBallPos.Y <= screenBallSize or newBallPos.Y >= 1 - screenBallSize then
            newState.ballVelocity = Vector2.new(
                state.ballVelocity.X,
                -state.ballVelocity.Y
            )
            -- Clamp ball position
            newBallPos = Vector2.new(
                newBallPos.X,
                math.clamp(newBallPos.Y, screenBallSize, 1 - screenBallSize)
            )
        end
        
        -- Paddle positions in screen space
        local leftPaddleX = PADDLE_MARGIN / self.props.resolution.X
        local rightPaddleX = 1 - PADDLE_MARGIN / self.props.resolution.X - screenPaddleWidth
        
        -- Simple AABB collision check function
        local function checkCollision(ballX, ballY, paddleX, paddleY)
            -- Calculate box boundaries
            local ballLeft = ballX - screenBallSize
            local ballRight = ballX + screenBallSize
            local ballTop = ballY - screenBallSize
            local ballBottom = ballY + screenBallSize
            
            local paddleLeft = paddleX
            local paddleRight = paddleX + screenPaddleWidth
            local paddleTop = paddleY - screenPaddleHeight/2
            local paddleBottom = paddleY + screenPaddleHeight/2
            
            -- Simple box overlap test
            return ballRight >= paddleLeft and
                   ballLeft <= paddleRight and
                   ballBottom >= paddleTop and
                   ballTop <= paddleBottom
        end
        
        -- Left paddle collision
        if state.ballVelocity.X < 0 and
           checkCollision(newBallPos.X, newBallPos.Y, leftPaddleX, state.leftPaddlePos) then
            
            -- Calculate hit position (-1 to 1)
            local hitPos = (newBallPos.Y - state.leftPaddlePos) / (screenPaddleHeight/2)
            local angle = FIXED_ANGLES[math.abs(hitPos) > 0.5 and 2 or 1]
            if hitPos < 0 then angle = -angle end
            
            -- Update speed and velocity
            newState.currentBallSpeed = math.min(state.currentBallSpeed + SPEED_INCREASE, MAX_BALL_SPEED)
            newState.ballVelocity = Vector2.new(
                math.cos(angle) * newState.currentBallSpeed,
                math.sin(angle) * newState.currentBallSpeed
            )
            
            -- Place ball at paddle edge
            newBallPos = Vector2.new(leftPaddleX + screenPaddleWidth + screenBallSize, newBallPos.Y)
        end
        
        -- Right paddle collision
        if state.ballVelocity.X > 0 and
           checkCollision(newBallPos.X, newBallPos.Y, rightPaddleX, state.rightPaddlePos) then
            
            local hitPos = (newBallPos.Y - state.rightPaddlePos) / (screenPaddleHeight/2)
            local angle = FIXED_ANGLES[math.abs(hitPos) > 0.5 and 2 or 1]
            if hitPos < 0 then angle = -angle end
            
            newState.currentBallSpeed = math.min(state.currentBallSpeed + SPEED_INCREASE, MAX_BALL_SPEED)
            newState.ballVelocity = Vector2.new(
                -math.cos(angle) * newState.currentBallSpeed,
                math.sin(angle) * newState.currentBallSpeed
            )
            
            -- Place ball at paddle edge
            newBallPos = Vector2.new(rightPaddleX - screenBallSize, newBallPos.Y)
        end
        
        -- Check for scoring
        if newBallPos.X <= screenBallSize or newBallPos.X >= 1 - screenBallSize then
            if state.gameState == "playing" then
                if newBallPos.X < 0.5 then
                    newState.rightScore = state.rightScore + 1
                    updateScoreEvent:FireServer(newState.leftScore, newState.rightScore)
                    if newState.rightScore >= SCORE_TO_WIN then
                        newState.gameState = "gameOver"
                        newState.winner = "Right"
                        gameStateChangedEvent:FireServer("gameOver")
                    end
                else
                    newState.leftScore = state.leftScore + 1
                    updateScoreEvent:FireServer(newState.leftScore, newState.rightScore)
                    if newState.leftScore >= SCORE_TO_WIN then
                        newState.gameState = "gameOver"
                        newState.winner = "Left"
                        gameStateChangedEvent:FireServer("gameOver")
                    end
                end
            end
            
            -- Reset ball
            local direction = newBallPos.X < 0.5 and 1 or -1
            local angle = FIXED_ANGLES[1] * (math.random() > 0.5 and 1 or -1)
            
            newState.ballPosition = Vector2.new(0.5, 0.5)
            newState.ballVelocity = Vector2.new(
                math.cos(angle) * INITIAL_BALL_SPEED * direction,
                math.sin(angle) * INITIAL_BALL_SPEED
            )
            newState.currentBallSpeed = INITIAL_BALL_SPEED
            return newState
        end
        
        newState.ballPosition = newBallPos
        return newState
    end)
end

function Pong:render()
    local message = ""
    if self.state.gameState == "attract" then
        message = "Press Prompt to Join!"
    elseif self.state.gameState == "waiting" then
        if self.state.p1Present and not self.state.p2Present then
            message = "Waiting for Player 2..."
        elseif self.state.p2Present and not self.state.p1Present then
            message = "Waiting for Player 1..."
        else
            message = "Press SPACE to Start!"
        end
    elseif self.state.gameState == "gameOver" then
        message = self.state.winner .. " Player Wins! Press SPACE to Restart"
    end
    
    return Roact.createElement("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BorderSizePixel = 0,
    }, {
        AspectRatio = Roact.createElement("UIAspectRatioConstraint", {
            AspectRatio = self.props.resolution.X / self.props.resolution.Y,
            DominantAxis = Enum.DominantAxis.Height,
        }),
        
        -- Center line
        CenterLine = Roact.createElement("Frame", {
            Size = UDim2.new(0, 2, 1, 0),
            Position = UDim2.fromScale(0.5, 0),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
        }),
        
        -- Left paddle
        LeftPaddle = Roact.createElement("Frame", {
            Size = UDim2.fromOffset(PADDLE_WIDTH, PADDLE_HEIGHT),
            Position = UDim2.new(
                PADDLE_MARGIN / self.props.resolution.X,
                0,
                self.state.leftPaddlePos,
                -PADDLE_HEIGHT/2
            ),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
        }),
        
        -- Right paddle
        RightPaddle = Roact.createElement("Frame", {
            Size = UDim2.fromOffset(PADDLE_WIDTH, PADDLE_HEIGHT),
            Position = UDim2.new(
                1 - PADDLE_MARGIN / self.props.resolution.X - PADDLE_WIDTH / self.props.resolution.X,
                0,
                self.state.rightPaddlePos,
                -PADDLE_HEIGHT/2
            ),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
        }),
        
        -- Ball
        Ball = Roact.createElement("Frame", {
            Size = UDim2.fromOffset(BALL_SIZE, BALL_SIZE),
            Position = UDim2.new(
                self.state.ballPosition.X,
                -BALL_SIZE/2,
                self.state.ballPosition.Y,
                -BALL_SIZE/2
            ),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
        }),
        
        -- Scores
        LeftScore = Roact.createElement("TextLabel", {
            Size = UDim2.fromScale(0.1, 0.1),
            Position = UDim2.fromScale(0.25, 0.1),
            Text = tostring(self.state.leftScore),
            TextColor3 = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 1,
            TextScaled = true,
            Font = Enum.Font.GothamBold,
        }),
        
        RightScore = Roact.createElement("TextLabel", {
            Size = UDim2.fromScale(0.1, 0.1),
            Position = UDim2.fromScale(0.75, 0.1),
            Text = tostring(self.state.rightScore),
            TextColor3 = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 1,
            TextScaled = true,
            Font = Enum.Font.GothamBold,
        }),
        
        -- Game message
        Message = Roact.createElement("TextLabel", {
            Size = UDim2.fromScale(0.5, 0.1),
            Position = UDim2.fromScale(0.25, 0.4),
            Text = message,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 1,
            TextScaled = true,
            Font = Enum.Font.GothamBold,
            Visible = message ~= "",
        }),
        
        -- Controls hint (only show when relevant)
        Controls = Roact.createElement("TextLabel", {
            Size = UDim2.fromScale(0.8, 0.1),
            Position = UDim2.fromScale(0.1, 0.8),
            Text = self.state.gameState == "playing" and "Left: W/S  Right: ↑/↓" or "",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 1,
            TextScaled = true,
            Font = Enum.Font.Gotham,
            TextTransparency = 0.5,
        }),
    })
end

-- Game module interface
local PongGame = {}

function PongGame.new(config)
    local tree = Roact.createElement(Pong, {
        resolution = config.resolution,
        controller = config.controller
    })
    
    local handle = Roact.mount(tree, config.parent, "PongGame")
    
    return {
        destroy = function()
            Roact.unmount(handle)
        end
    }
end

return PongGame
