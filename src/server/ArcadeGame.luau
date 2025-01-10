local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

export type GameState = {
    isActive: boolean,
    currentPlayer: Player?,
    score: number,
    highScore: number,
    lastUpdateTime: number,
}

-- Base class for all arcade games
local ArcadeGame = {}
ArcadeGame.__index = ArcadeGame

function ArcadeGame.new(cabinetModel: Model)
    local self = setmetatable({}, ArcadeGame)
    
    -- Core properties
    self.cabinet = cabinetModel
    self.gameState = {
        isActive = false,
        currentPlayer = nil,
        score = 0,
        highScore = 0,
        lastUpdateTime = os.clock(),
    }
    
    -- Bind methods
    self.heartbeatConnection = nil
    
    return self
end

function ArcadeGame:start(player: Player)
    if self.gameState.isActive then
        return false, "Game is already in progress"
    end
    
    self.gameState.isActive = true
    self.gameState.currentPlayer = player
    self.gameState.score = 0
    self.gameState.lastUpdateTime = os.clock()
    
    -- Start game loop
    self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
        self:update(deltaTime)
    end)
    
    self:onGameStart()
    return true
end

function ArcadeGame:stop()
    if not self.gameState.isActive then
        return
    end
    
    -- Update high score if needed
    if self.gameState.score > self.gameState.highScore then
        self.gameState.highScore = self.gameState.score
    end
    
    -- Clean up
    if self.heartbeatConnection then
        self.heartbeatConnection:Disconnect()
        self.heartbeatConnection = nil
    end
    
    self.gameState.isActive = false
    self.gameState.currentPlayer = nil
    
    self:onGameStop()
end

-- Virtual methods to be implemented by specific games
function ArcadeGame:update(deltaTime: number)
    -- Override this in specific game implementations
end

function ArcadeGame:onGameStart()
    -- Override this in specific game implementations
end

function ArcadeGame:onGameStop()
    -- Override this in specific game implementations
end

function ArcadeGame:handleInput(inputType: string, inputState: boolean)
    -- Override this in specific game implementations
end

-- Utility methods
function ArcadeGame:updateScore(points: number)
    self.gameState.score += points
end

function ArcadeGame:getState(): GameState
    return self.gameState
end

return ArcadeGame
