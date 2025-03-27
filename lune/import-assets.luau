local downloadPlaceAsset = require("./lib/downloadPlaceAsset")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")

local content = downloadPlaceAsset(104742960499551) -- replace with your own place id!
local game = roblox.deserializePlace(content)

if not fs.isDir("./map") then
    fs.writeDir("./map")
end

if not fs.isDir("./assets") then
    fs.writeDir("./assets")
end

-- Copy Workspace contents
if game.Workspace then
    fs.writeFile("./map/Workspace.rbxm", roblox.serializeModel({game.Workspace}))
end

-- Copy Lighting with all its properties
if game.Lighting then
    fs.writeFile("./map/Lighting.rbxm", roblox.serializeModel({game.Lighting}))
end

if game.ReplicatedStorage and game.ReplicatedStorage:FindFirstChild("Assets") then
    -- Create models directory if it doesn't exist
    if not fs.isDir("./assets/models") then
        fs.writeDir("./assets/models")
    end

    -- Save each model individually
    for _, child in game.ReplicatedStorage.Assets:GetChildren() do
        local clone = child:Clone()
        -- Save the model
        local fileName = string.format("./assets/models/%s.rbxm", clone.Name)
        fs.writeFile(fileName, roblox.serializeModel({clone}))
    end
else
    print("Warning: ReplicatedStorage.Assets not found in place file")
end