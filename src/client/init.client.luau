--!strict
local Roact = require(game.ReplicatedStorage.Shared.Roact)
local PongGame = require(script.games.Pong)
local CabinetController = require(script.CabinetController)

-- Initialize the game on each cabinet
local function init()
    print("[Client] Starting Pong...")
    
    local cabinets = workspace:WaitForChild("Cabinets")
    print("[Client] Found Cabinets folder")
    
    local pongFolder = cabinets:WaitForChild("Pong")
    print("[Client] Found Pong folder")
    
    local pongCabinet = pongFolder:WaitForChild("PongCabinet")
    print("[Client] Found PongCabinet")
    
    local screen = pongCabinet:WaitForChild("Screen")
    print("[Client] Found Screen")
    
    local gui = screen:WaitForChild("SurfaceGui")
    print("[Client] Found SurfaceGui")
    
    -- Create cabinet controller
    print("[Client] Creating cabinet controller...")
    local controller = CabinetController.new(pongCabinet)
    
    -- Create game instance
    print("[Client] Creating game instance...")
    local config = {
        resolution = Vector2.new(800, 600),
        parent = gui,
        controller = controller -- Pass controller to game
    }
    local game = PongGame.new(config)
    print("[Client] Game created successfully!")
    
    -- Handle cleanup
    script.AncestryChanged:Connect(function(_, parent)
        if not parent then
            print("[Client] Cleaning up...")
            if game and game.destroy then
                game:destroy()
            end
            if controller and controller.destroy then
                controller:destroy()
            end
            print("[Client] Cleanup complete")
        end
    end)
end

init()
