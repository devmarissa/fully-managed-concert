local Roact = require(script.Parent.Parent.Roact)

-- Constants for visual styling based on original Pong
local SCREEN_PADDING = 20 -- Reduced padding for better use of space
local PADDLE_WIDTH = 16
local PADDLE_HEIGHT = 70
local BALL_SIZE = 16
local SCORE_TEXT_SIZE = 36

-- Fixed dimensions based on SurfaceGui
local FIXED_WIDTH = 858
local FIXED_HEIGHT = 525

local function getPlayableHeight()
    return FIXED_HEIGHT - (SCREEN_PADDING * 2)
end

local function getVerticalPosition(relativeY, elementHeight)
    -- Convert from relative (0-1) to actual pixels
    -- The relativeY now represents the center point of the element
    local playableHeight = getPlayableHeight()
    local pixelY = SCREEN_PADDING + (playableHeight * relativeY)
    -- Center the element at the calculated position with half offset and manual adjustment
    return pixelY - elementHeight/4 - PADDLE_HEIGHT/4
end

local PongDisplay = Roact.Component:extend("PongDisplay")

function PongDisplay:init()
    -- Initialize any component state if needed
end

function PongDisplay:render()
    local gameState = self.props.gameState
    local playableHeight = getPlayableHeight()
    
    return Roact.createElement("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BorderSizePixel = 0,
    }, {
        -- Left paddle
        LeftPaddle = Roact.createElement("Frame", {
            Size = UDim2.new(0, PADDLE_WIDTH, 0, PADDLE_HEIGHT),
            Position = UDim2.new(
                0, 
                SCREEN_PADDING, 
                0, 
                getVerticalPosition(gameState.paddlePosition, PADDLE_HEIGHT)
            ),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
        }),

        -- Right paddle (AI)
        RightPaddle = Roact.createElement("Frame", {
            Size = UDim2.new(0, PADDLE_WIDTH, 0, PADDLE_HEIGHT),
            Position = UDim2.new(
                1, 
                -SCREEN_PADDING - PADDLE_WIDTH, 
                0, 
                getVerticalPosition(gameState.aiPaddlePosition, PADDLE_HEIGHT)
            ),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
        }),

        -- Ball
        Ball = Roact.createElement("Frame", {
            Size = UDim2.new(0, BALL_SIZE, 0, BALL_SIZE),
            Position = UDim2.new(
                gameState.ballPosition.X, 
                -BALL_SIZE/2,
                0, 
                getVerticalPosition(gameState.ballPosition.Y, BALL_SIZE)
            ),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
        }),

        -- Score
        Score = Roact.createElement("TextLabel", {
            Size = UDim2.new(0, 200, 0, 50),
            Position = UDim2.new(0.5, -100, 0, SCREEN_PADDING),
            Text = string.format("%d  %d", gameState.gameState.p1Score or 0, gameState.gameState.p2Score or 0),
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = SCORE_TEXT_SIZE,
            Font = Enum.Font.Arcade,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextXAlignment = Enum.TextXAlignment.Center,
        }),

        -- Game State Message
        Message = (gameState.gameState.message ~= "") and Roact.createElement("TextLabel", {
            Size = UDim2.new(0, 400, 0, 50),
            Position = UDim2.new(0.5, -200, 0.5, -25),
            Text = gameState.gameState.message,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = SCORE_TEXT_SIZE,
            Font = Enum.Font.Arcade,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
        }) or nil,
    })
end

return PongDisplay
