--[[
    Client Music Controller
    Makes cool effects happen with the music!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
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

-- Chat command handling
local prefix = ":"  -- Using : as prefix for our commands

-- Process a chat message and handle any commands
local function handleChatCommand(message: string)
    -- Convert to lowercase and split into arguments
    local loweredString = string.lower(message)
    local args = string.split(loweredString, " ")
    
    -- Handle dance command
    if args[1] == prefix.."dance" then
        -- If no dance number specified, default to 1
        local danceIndex = args[2] or "1"
        
        -- Validate that danceIndex is a number
        local danceNum = tonumber(danceIndex)
        if danceNum then
            print("[Client] Setting dance to:", danceNum)
            -- Disable auto-advance when manually selecting a dance
            danceController.state.autoAdvance = false
            danceController:setDance(danceNum)
            CurrentSong.danceStarted = true
        else
            print("[Client] Invalid dance number:", danceIndex)
        end
    elseif args[1] == prefix.."autoadvance" then
        -- Add command to toggle auto-advance
        danceController.state.autoAdvance = not danceController.state.autoAdvance
        print("[Client] Auto-advance:", danceController.state.autoAdvance and "ON" or "OFF")
    end
end

-- Set up chat command handling using TextChatService
local function setupChatCommands()
    -- Try TextChatService first (modern chat)
    local success, _ = pcall(function()
        TextChatService.MessageReceived:Connect(function(textChatMessage)
            if textChatMessage.TextSource and textChatMessage.TextSource.UserId == Players.LocalPlayer.UserId then
                handleChatCommand(textChatMessage.Text)
            end
        end)
    end)
    
    if not success then
        -- Fallback to legacy chat
        local player = Players.LocalPlayer
        if player then
            player.Chatted:Connect(handleChatCommand)
        end
        
        -- Also try to use StarterGui chat (another legacy method)
        local StarterGui = game:GetService("StarterGui")
        StarterGui:SetCore("ChatMakeSystemMessage", {
            Text = "Chat commands initialized. Use :dance [number] to dance!",
            Color = Color3.fromRGB(0, 255, 0)
        })
    end
end

-- Initialize chat commands when LocalPlayer is ready
if Players.LocalPlayer then
    setupChatCommands()
else
    Players:GetPropertyChangedSignal("LocalPlayer"):Connect(setupChatCommands)
end

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
