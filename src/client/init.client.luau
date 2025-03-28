--[[
    Client Music Controller
    Makes cool effects happen with the music!
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Types = require(ReplicatedStorage.shared.Types)
local BeatEffects = require(script.BeatEffects)
local LightingEffects = require(script.LightingEffects)

-- Events from server
local BeatEvent = ReplicatedStorage:WaitForChild("BeatUpdate")
local SongEvent = ReplicatedStorage:WaitForChild("SongChange")
local StationEvent = ReplicatedStorage:WaitForChild("StationEvent")

-- Initialize effects
local beatEffects = BeatEffects.new()
local lightingEffects = LightingEffects.new()

-- Keep track of current song data
local CurrentSong = {
    id = nil,
    beatGrid = nil,
    songSections = nil,
    bpm = nil,
    firstBeatOffset = nil,
    firstDownbeat = nil,
    startTime = 0,
    currentBeatIndex = 1,
    currentSectionIndex = 1
}

-- Handle station changes
StationEvent.OnClientEvent:Connect(function(data)
    if data and data.station then
        print("Now playing station:", data.station)
    end
end)

-- Handle song changes
SongEvent.OnClientEvent:Connect(function(songId)
    print("Now playing:", songId)
    CurrentSong.id = songId
    CurrentSong.startTime = os.clock()
    CurrentSong.currentBeatIndex = 1
    CurrentSong.currentSectionIndex = 1
end)

-- Handle beat updates
BeatEvent.OnClientEvent:Connect(function(data: Types.BeatUpdateData)
    if data then
        CurrentSong.beatGrid = data.beatGrid
        CurrentSong.songSections = data.songSections
        CurrentSong.bpm = data.bpm
        CurrentSong.firstBeatOffset = data.firstBeatOffset
        CurrentSong.firstDownbeat = data.firstDownbeat
        CurrentSong.startTime = os.clock()
        CurrentSong.currentBeatIndex = 1
        CurrentSong.currentSectionIndex = 1
        
        if data.beatGrid then
            print("Beat Data Received:")
            print(string.format("BPM: %.1f", data.bpm or 0.0))
            print(string.format("First Beat Offset: %.2fs", data.firstBeatOffset or 0.0))
            print(string.format("Number of Bars: %d", data.numBars or 0))
            
            -- Start effect detection loop
            RunService.Heartbeat:Connect(function()
                local currentTime = os.clock() - CurrentSong.startTime
                
                -- Check for section changes
                if CurrentSong.songSections then
                    local nextSection = CurrentSong.songSections[CurrentSong.currentSectionIndex]
                    if nextSection and currentTime >= nextSection.start_time then
                        lightingEffects:transitionToSection(nextSection)
                        CurrentSong.currentSectionIndex += 1
                    end
                end
                
                -- Check for beats
                local nextBeatTime = CurrentSong.beatGrid.beat_times[CurrentSong.currentBeatIndex]
                if nextBeatTime and currentTime >= nextBeatTime then
                    -- Get current beat number (1-4 pattern)
                    local beatNum = CurrentSong.beatGrid.beat_nums[CurrentSong.currentBeatIndex]
                    
                    -- Do beat effects
                    if beatNum == 1 then
                        -- Stronger effect on downbeat
                        beatEffects:doBeatEffect(1.5, beatNum, nextBeatTime)
                    else
                        beatEffects:doBeatEffect(1, beatNum, nextBeatTime)
                    end
                    
                    -- Move to next beat
                    CurrentSong.currentBeatIndex += 1
                end
            end)
        end
    end
end)
