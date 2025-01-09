local downloadPlaceAsset = require("./lib/downloadPlaceAsset")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")

local content = downloadPlaceAsset(129272607025831) -- replace with your own place id!
local game = roblox.deserializePlace(content)

if not fs.isDir("./map") then
    fs.writeDir("./map")
end

if not fs.isDir("./assets") then
    fs.writeDir("./assets")
end

-- Copy children to our containers
if game.Workspace then
    local container = roblox.Instance.new("Folder")
    container.Name = "Contents"
    for _, child in game.Workspace:GetChildren() do
        child:Clone().Parent = container
    end
    fs.writeFile("./map/Workspace.rbxm", roblox.serializeModel({container}))
end

if game.Lighting then
    local container = roblox.Instance.new("Folder")
    container.Name = "Contents"
    for _, child in game.Lighting:GetChildren() do
        child:Clone().Parent = container
    end
    fs.writeFile("./map/Lighting.rbxm", roblox.serializeModel({container}))
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