--[[
    Client Music Controller
    Makes cool effects happen with the music!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local SoundService = game:GetService("SoundService")
local Types = require(ReplicatedStorage.shared.Types)
local LightingEffects = require(script.LightingEffects)
local DanceController = require(script.DanceController)
local SyncHandler = require(script.SyncHandler)

-- Events from server
local BeatEvent = ReplicatedStorage:WaitForChild("BeatUpdate")
local SongEvent = ReplicatedStorage:WaitForChild("SongChange")
local StationEvent = ReplicatedStorage:WaitForChild("StationEvent")

-- Initialize effects and controllers
local beatEffects = {
    doBeatEffect = function(self: any, intensity: number, beatNum: number, _beatTime: number)
        -- TODO: Implement beat effects
        print("[BeatEffects] Beat effect:", beatNum, "Intensity:", intensity)
    end,
    
    onBeat = function(self: any, currentTime: number, beatTime: number)
        self:doBeatEffect(1, 0, beatTime)
    end,
    
    onDownbeat = function(self: any, currentTime: number, beatTime: number) 
        self:doBeatEffect(1.5, 1, beatTime)
    end,
    
    destroy = function(self: any)
        -- Nothing to clean up
    end
}

-- Initialize lighting effects once game is ready
local lightingEffects = nil
local function initLightingEffects()
    if not lightingEffects then
        lightingEffects = LightingEffects.new()
        print("[Client] Lighting effects initialized")
    end
end

if game:IsLoaded() then
    task.spawn(initLightingEffects)
else
    game.Loaded:Connect(initLightingEffects)
end

-- Keep track of current song data
local CurrentSong = {
    beatGrid = nil,
    songSections = nil,
    bpm = nil,
    currentSection = nil,
    sound = nil,
    heartbeatConnection = nil -- Track the connection
}

-- Function to find current section
local function findCurrentSection(sections: {Types.SongSection}, currentTime: number): (Types.SongSection?, number)
    -- Sort sections by start time to ensure proper ordering
    table.sort(sections, function(a, b)
        return a.start_time < b.start_time
    end)
    
    -- Find the current section based on time
    for i, section in ipairs(sections) do
        if currentTime >= section.start_time and currentTime < section.end_time then
            return section, i
        end
    end
    
    -- If we're past the last section's end time, return nil
    if #sections > 0 and currentTime >= sections[#sections].end_time then
        return nil, 0
    end
    
    -- Return the first section if we're before any section starts
    if #sections > 0 and currentTime < sections[1].start_time then
        return sections[1], 1
    end
    
    return nil, 0
end

-- Handle chat commands
local function handleChatCommand(message)
    -- Check if it's a TextChatMessage
    local messageText = if typeof(message) == "Instance" and message:IsA("TextChatMessage") 
        then message.Text 
        else message

    if messageText:sub(1, 1) ~= ":" then return end
    
    local command = messageText:sub(2):lower()
    if command:sub(1, 5) == "dance" then
        local danceId = command:sub(7)
        if danceId == "" then danceId = "1" end
        print("[Client] Setting dance to:", danceId)
        if danceController then
            danceController:startDancing(danceId)
        end
    end
end

local function setupChatCommands()
    local textChat = TextChatService.TextChannels.RBXGeneral
    textChat.MessageReceived:Connect(handleChatCommand)
    print("[Client] Chat commands initialized")
end

-- Initialize controllers when LocalPlayer is ready
local function initializeControllers()
    if not Players.LocalPlayer then return end
    
    -- Initialize SyncHandler first
    SyncHandler:init()
    
    -- Create DanceController instance if not already created
    if not danceController then
        danceController = DanceController.new()
    end
    
    task.spawn(function()
        pcall(function()
            danceController:init()
            print("[Client] DanceController initialized")
        end)
    end)
end

if Players.LocalPlayer then
    initializeControllers()
else
    Players:GetPropertyChangedSignal("LocalPlayer"):Connect(initializeControllers)
end

-- Set up beat handling
local function onBeat(data)
    if not danceController or not danceController.state then
        warn("[Client] Dance controller not ready for beat event")
        return
    end
    
    -- Forward beat data
    if typeof(danceController.onBeat) == "function" then
        task.spawn(function()
            danceController:onBeat({
                beatNum = data.beatNum,
                beatTime = data.beatTime,
                bpm = data.bpm or CurrentSong.bpm
            })
        end)
    end
    
    -- Handle section changes
    if data.currentSection and (not CurrentSong.currentSection or data.currentSection.name ~= CurrentSong.currentSection.name) then
        print("[Client] Section changed to:", data.currentSection.name)
        CurrentSong.currentSection = data.currentSection
        
        -- Update lighting for new section
        if lightingEffects then
            lightingEffects:transitionToSection(data.currentSection)
        end
    end
end

-- Handle song changes
SongEvent.OnClientEvent:Connect(function(songData)
    print("[Client] Received song data for:", songData.assetId)
    print("[Client] Number of sections:", songData.sections and #songData.sections or 0)
    
    -- Clean up previous connections
    if CurrentSong.heartbeatConnection then
        CurrentSong.heartbeatConnection:Disconnect()
        CurrentSong.heartbeatConnection = nil
    end
    
    -- Update song data
    CurrentSong.beatGrid = songData.beatGrid
    CurrentSong.songSections = songData.sections
    CurrentSong.bpm = songData.bpm
    CurrentSong.currentSection = nil -- Reset section tracking
    
    -- Find the sound in SoundService
    if CurrentSong.sound then
        CurrentSong.sound:Destroy()
    end
    
    -- Wait for sound to be replicated
    task.delay(0.1, function()
        for _, child in SoundService:GetChildren() do
            if child:IsA("Sound") and child.SoundId:match(songData.assetId) then
                CurrentSong.sound = child
                print("[Client] Found sound in SoundService:", child.SoundId)
                break
            end
        end
        
        if not CurrentSong.sound then
            warn("[Client] Could not find sound for:", songData.assetId)
            return
        end
        
        -- Set up section change detection
        local lastCheckTime = 0
        CurrentSong.heartbeatConnection = game:GetService("RunService").Heartbeat:Connect(function()
            if not CurrentSong.sound.IsPlaying then return end
            
            -- Only check every 0.1 seconds to avoid excessive checks
            local now = tick()
            if now - lastCheckTime < 0.1 then return end
            lastCheckTime = now
            
            local currentTime = CurrentSong.sound.TimePosition
            if not CurrentSong.songSections then return end
            
            -- Find current section based on time
            for _, section in CurrentSong.songSections do
                if currentTime >= section.start_time and currentTime < section.end_time then
                    if not CurrentSong.currentSection or CurrentSong.currentSection.name ~= section.name then
                        print(string.format("[Client] Section change: %s -> %s at %.3fs (range: %.3f - %.3f)",
                            CurrentSong.currentSection and CurrentSong.currentSection.name or "none",
                            section.name,
                            currentTime,
                            section.start_time,
                            section.end_time
                        ))
                        
                        CurrentSong.currentSection = section
                        -- Make sure lighting effects are initialized
                        if not lightingEffects then
                            initLightingEffects()
                        end
                        if lightingEffects then
                            lightingEffects:transitionToSection(section)
                        end
                    end
                    break
                end
            end
        end)
    end)
    
    -- Set initial section
    if CurrentSong.songSections and #CurrentSong.songSections > 0 then
        local firstSection = CurrentSong.songSections[1]
        print(string.format("[Client] Section change: %s -> %s at %.3fs (range: %.3f - %.3f)",
            "none",
            firstSection.name,
            0,
            firstSection.start_time,
            firstSection.end_time
        ))
        
        CurrentSong.currentSection = firstSection
        -- Make sure lighting effects are initialized
        if not lightingEffects then
            initLightingEffects()
        end
        if lightingEffects then
            lightingEffects:transitionToSection(firstSection)
        end
    end
end)

-- Handle beat updates (just for dance animations and effects)
BeatEvent.OnClientEvent:Connect(function(data: Types.BeatUpdateData)
    if not data then return end
    
    -- Update beat info
    if data.bpm then
        CurrentSong.bpm = data.bpm
    end
    
    if danceController then
        if danceController.onBeat then
            danceController:onBeat(data)
        end
    end
    if beatEffects and beatEffects.onBeat then
        beatEffects:onBeat(data.currentTime, data.beatTime)
    end
end)

-- Initialize chat commands when LocalPlayer is ready
if Players.LocalPlayer then
    setupChatCommands()
else
    Players:GetPropertyChangedSignal("LocalPlayer"):Connect(setupChatCommands)
end
