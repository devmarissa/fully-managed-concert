--[[
    Server Music Controller
    Fetches music data from AudioScape and keeps all players in sync!
]]

local MusicController = require(script.MusicController)

print("Starting music server...")
print("Playing test song with ID: 9046443555")

local controller = MusicController.new()
controller:playSong("9046443555")
