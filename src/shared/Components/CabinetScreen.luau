local Roact = require(script.Parent.Parent.Roact)
local PongDisplay = require(script.Parent.PongDisplay)

-- Original Pong resolution
local PONG_RESOLUTION = Vector2.new(858, 525)

local CabinetScreen = Roact.Component:extend("CabinetScreen")

function CabinetScreen:init()
    -- Subscribe to game state updates if needed
end

function CabinetScreen:render()
    local gameType = self.props.gameType
    local gameState = self.props.gameState
    
    -- Instead of creating a SurfaceGui, we'll create the contents directly
    return Roact.createElement("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
    }, {
        -- For now we only have Pong, we'll add other games later
        Game = gameType == "Pong" and
            Roact.createElement(PongDisplay, {
                gameState = gameState,
                size = PONG_RESOLUTION,
            }) or
            Roact.createElement("TextLabel", {
                Size = UDim2.fromScale(1, 1),
                Text = "Game Type Not Supported",
                TextColor3 = Color3.fromRGB(255, 255, 255),
                BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                BackgroundTransparency = 1,
            })
    })
end

return CabinetScreen
