--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Create RemoteEvents
local remotes = Instance.new("Folder")
remotes.Name = "PongRemotes"

local playerJoinedEvent = Instance.new("RemoteEvent")
playerJoinedEvent.Name = "PlayerJoined"

local playerLeftEvent = Instance.new("RemoteEvent")
playerLeftEvent.Name = "PlayerLeft"

local gameStateChangedEvent = Instance.new("RemoteEvent")
gameStateChangedEvent.Name = "GameStateChanged"

local updateScoreEvent = Instance.new("RemoteEvent")
updateScoreEvent.Name = "UpdateScore"

remotes.Parent = ReplicatedStorage

playerJoinedEvent.Parent = remotes
playerLeftEvent.Parent = remotes
gameStateChangedEvent.Parent = remotes
updateScoreEvent.Parent = remotes

-- Game state
type PlayerInfo = {
    player: Player,
    position: number, -- 1 for left, 2 for right
}

local activePlayers: {[Player]: PlayerInfo} = {}
local gameState = {
    state = "attract",
    p1Present = false,
    p2Present = false,
    leftScore = 0,
    rightScore = 0,
}

-- Handle player joining cabinet
playerJoinedEvent.OnServerEvent:Connect(function(player: Player, position: number)
    print("[PongServer] Player", player.Name, "joining position", position)
    
    -- Check if position is already taken by another player
    for _, info in activePlayers do
        if info.position == position then
            -- Position already taken
            return
        end
    end
    
    -- Add player to active players
    activePlayers[player] = {
        player = player,
        position = position,
    }
    
    -- Update game state
    if position == 1 then
        gameState.p1Present = true
    else
        gameState.p2Present = true
    end
    
    if gameState.p1Present and gameState.p2Present then
        gameState.state = "waiting"
    else
        gameState.state = "attract"
    end
    
    -- Notify all clients
    gameStateChangedEvent:FireAllClients(gameState)
    
    -- Notify all clients about the new player
    for _, client in Players:GetPlayers() do
        playerJoinedEvent:FireClient(client, player, position)
    end
end)

-- Handle player leaving cabinet
local function removePlayer(player: Player)
    local info = activePlayers[player]
    if not info then return end
    
    print("[PongServer] Player", player.Name, "leaving position", info.position)
    
    -- Update game state
    if info.position == 1 then
        gameState.p1Present = false
    else
        gameState.p2Present = false
    end
    
    if not (gameState.p1Present or gameState.p2Present) then
        gameState.state = "attract"
        gameState.leftScore = 0
        gameState.rightScore = 0
    end
    
    -- Remove from active players
    activePlayers[player] = nil
    
    -- Notify all clients
    gameStateChangedEvent:FireAllClients(gameState)
    
    -- Notify all clients about the player leaving
    for _, client in Players:GetPlayers() do
        playerLeftEvent:FireClient(client, player, info.position)
    end
end

playerLeftEvent.OnServerEvent:Connect(removePlayer)

-- Handle player disconnect
Players.PlayerRemoving:Connect(removePlayer)

-- Handle score updates
updateScoreEvent.OnServerEvent:Connect(function(player: Player, leftScore: number, rightScore: number)
    -- Only accept score updates from active players
    if not activePlayers[player] then return end
    
    gameState.leftScore = leftScore
    gameState.rightScore = rightScore
    
    -- Notify all clients except the sender
    for _, client in Players:GetPlayers() do
        if client ~= player then
            updateScoreEvent:FireClient(client, leftScore, rightScore)
        end
    end
end)

-- Handle game state changes
gameStateChangedEvent.OnServerEvent:Connect(function(player: Player, newState: string)
    -- Only accept state changes from active players
    if not activePlayers[player] then return end
    
    gameState.state = newState
    
    -- Notify all clients except the sender
    for _, client in Players:GetPlayers() do
        if client ~= player then
            gameStateChangedEvent:FireClient(client, gameState)
        end
    end
end)

print("[PongServer] Pong server initialized")
