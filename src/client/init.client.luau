--[[
    Client Music Controller
    Makes cool effects happen with the music!
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Types = require(ReplicatedStorage.shared.Types)
local LightingEffects = require(script.LightingEffects)
local DanceController = require(script.DanceController)

-- Events from server
local BeatEvent = ReplicatedStorage:WaitForChild("BeatUpdate")
local SongEvent = ReplicatedStorage:WaitForChild("SongChange")
local StationEvent = ReplicatedStorage:WaitForChild("StationEvent")

-- Initialize effects and controllers
local beatEffects = {
    doBeatEffect = function(_self: any, intensity: number, beatNum: number, _beatTime: number)
        -- TODO: Implement beat effects
        print("[BeatEffects] Beat effect:", beatNum, "Intensity:", intensity)
    end,
    
    onBeat = function(_self, _currentTime: number, beatTime: number)
        _self:doBeatEffect(1, 0, beatTime)
    end,
    
    onDownbeat = function(_self, _currentTime: number, beatTime: number) 
        _self:doBeatEffect(1.5, 1, beatTime)
    end,
    
    destroy = function(_self)
        -- Nothing to clean up
    end
}

local lightingEffects = LightingEffects.new()
local danceController = DanceController.new()

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
    currentSectionIndex = 1,
    danceStarted = false,
    effectLoop = nil
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
    CurrentSong.danceStarted = false
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
        
        print("Beat Data Received:")
        print(string.format("BPM: %.1f", data.bpm or 0.0))
        print(string.format("First Beat Offset: %.2fs", data.firstBeatOffset or 0.0))
        print(string.format("Number of Bars: %d", data.numBars or 0))
        
        -- Update dance controller with beat data
        danceController:onBeat(data)
        
        -- Start dancing if not already started
        if not CurrentSong.danceStarted then
            print("[Client] Starting automatic dance")
            task.wait(0.1) -- Give a small delay for preload
            danceController:setDance("1")
            CurrentSong.danceStarted = true
        end
        
        -- Start effect detection loop
        if not CurrentSong.effectLoop then
            CurrentSong.effectLoop = RunService.Heartbeat:Connect(function()
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
                if CurrentSong.beatGrid and CurrentSong.beatGrid.beat_times then
                    local nextBeatTime = CurrentSong.beatGrid.beat_times[CurrentSong.currentBeatIndex]
                    if nextBeatTime and currentTime >= nextBeatTime then
                        -- Get current beat number (1-4 pattern)
                        local beatNum = CurrentSong.beatGrid.beat_nums[CurrentSong.currentBeatIndex]
                        
                        -- Update dance controller
                        danceController:onBeat({
                            beatNum = beatNum,
                            beatCount = CurrentSong.currentBeatIndex,
                            bpm = CurrentSong.bpm
                        })
                        
                        -- Do beat effects
                        if beatNum == 1 then
                            beatEffects:onDownbeat(currentTime, nextBeatTime)
                        else
                            beatEffects:onBeat(currentTime, nextBeatTime)
                        end
                        
                        -- Move to next beat
                        CurrentSong.currentBeatIndex += 1
                    end
                end
            end)
        end
    end
end)

-- Clean up when script is destroyed
task.spawn(function()
    script.Destroying:Wait()
    if beatEffects.destroy then
        beatEffects:destroy()
    end
    if lightingEffects.destroy then
        lightingEffects:destroy()
    end
    if danceController.destroy then
        danceController:destroy()
    end
    
    -- Clean up any running connections
    if CurrentSong.effectLoop then
        CurrentSong.effectLoop:Disconnect()
        CurrentSong.effectLoop = nil
    end
end)
