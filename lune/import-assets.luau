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

-- Create empty containers
local workspaceModel = roblox.Instance.new("Model")
local lightingModel = roblox.Instance.new("Model")
local assetsModel = roblox.Instance.new("Model")

-- Copy children to our containers
if game.Workspace then
    for _, child in game.Workspace:GetChildren() do
        child:Clone().Parent = workspaceModel
    end
    fs.writeFile("./map/Workspace.rbxm", roblox.serializeModel({workspaceModel}))
end

if game.Lighting then
    for _, child in game.Lighting:GetChildren() do
        child:Clone().Parent = lightingModel
    end
    fs.writeFile("./map/Lighting.rbxm", roblox.serializeModel({lightingModel}))
end

if game.ReplicatedStorage and game.ReplicatedStorage:FindFirstChild("Assets") then
    for _, child in game.ReplicatedStorage.Assets:GetChildren() do
        child:Clone().Parent = assetsModel
    end
    fs.writeFile("./assets/Models.rbxm", roblox.serializeModel({assetsModel}))
else
    print("Warning: ReplicatedStorage.Assets not found in place file")
end