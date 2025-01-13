print("Hello world, from server!")

local Roact = require(game:GetService("ReplicatedStorage").Shared.Roact)
local PongGame = require(script.PongGame)
local CabinetScreen = require(game:GetService("ReplicatedStorage").Shared.Components.CabinetScreen)
local CabinetEvents = require(game:GetService("ReplicatedStorage").Shared.CabinetEvents)

-- Store active game instances and their UI handles
local activeGames = {}
local mountedScreens = {}

-- Handle play requests from clients
CabinetEvents.PlayCabinet.OnServerEvent:Connect(function(player, promptPart)
    if not promptPart then return end
    
    -- Get the cabinet from the prompt part
    local cabinet = promptPart.Parent
    if not cabinet then return end
    
    -- Check if cabinet exists and has a game instance
    local game = activeGames[cabinet]
    if not game then return end
    
    -- Check if this player is already playing
    if game.gameState.player1 == player or game.gameState.player2 == player then
        -- Player is trying to exit
        game:playerLeft(player)
        return
    end
    
    -- Determine if this is P1 or P2
    local position = promptPart.Name == "P1" and 1 or 2
    
    -- Start or join the game
    game:startGame(player, position)
end)

-- Clean up when players leave
game:GetService("Players").PlayerRemoving:Connect(function(player)
    -- Check all games for the leaving player
    for _, game in pairs(activeGames) do
        game:playerLeft(player)
    end
end)

-- Initialize arcade cabinets
local function initializeArcadeCabinets()
    local workspace = game:GetService("Workspace")
    local cabinetsFolder = workspace:WaitForChild("Cabinets")
    
    print("Starting cabinet initialization...")
    
    -- Initialize each cabinet type
    for _, cabinetFolder in cabinetsFolder:GetChildren() do
        local cabinet = cabinetFolder:WaitForChild("Cabinet")
        if cabinet then
            if cabinetFolder.Name == "Pong" then
                print("Creating Pong game instance...")
                local pongGame = PongGame.new(cabinet)
                activeGames[cabinet] = pongGame
                
                -- Mount the screen UI
                local screen = cabinet:WaitForChild("Screen")
                if screen then
                    local surfaceGui = screen:WaitForChild("SurfaceGui")
                    if surfaceGui then
                        -- Configure the existing SurfaceGui
                        surfaceGui.Face = Enum.NormalId.Front
                        surfaceGui.LightInfluence = 0
                        surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
                        surfaceGui.PixelsPerStud = 429 -- 858 pixels / 2 studs = 429 pixels per stud
                        surfaceGui.ResetOnSpawn = false
                        surfaceGui.Enabled = true
                        surfaceGui.AlwaysOnTop = false
                        surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                        
                        -- Mount our UI to the existing SurfaceGui
                        local element = Roact.createElement(CabinetScreen, {
                            gameType = "Pong",
                            gameState = pongGame:getState(),
                        })
                        mountedScreens[cabinet] = Roact.mount(element, surfaceGui, "CabinetScreen")
                        print("Initialized Pong cabinet and mounted screen")
                    else
                        warn("No SurfaceGui found in Screen part!")
                    end
                else
                    warn("No Screen part found in Pong cabinet!")
                end
            else
                print("Found cabinet:", cabinetFolder.Name)
            end
        end
    end
    
    print("Number of active games:", #activeGames)
end

-- Update game states and UI
local RunService = game:GetService("RunService")
local lastUpdateTime = os.clock()
local HttpService = game:GetService("HttpService") -- Get HttpService once

local function updateGames()
    local currentTime = os.clock()
    local deltaTime = currentTime - lastUpdateTime
    lastUpdateTime = currentTime
    
    -- Update all active games
    for cabinet, gameInstance in pairs(activeGames) do
        -- Update game state
        gameInstance:update(deltaTime)
        
        -- Update UI
        if mountedScreens[cabinet] then
            local screen = cabinet:FindFirstChild("Screen")
            if screen then
                local surfaceGui = screen:FindFirstChild("SurfaceGui")
                if surfaceGui then
                    local element = Roact.createElement(CabinetScreen, {
                        gameType = "Pong",
                        gameState = gameInstance:getState(),
                    })
                    Roact.update(mountedScreens[cabinet], element)
                end
            end
        end
    end
end

-- Initialize cabinets
print("Starting initialization...")
initializeArcadeCabinets()

-- Start the game loop
print("Starting game loop...")
RunService.Heartbeat:Connect(updateGames)
print("Game loop started!")