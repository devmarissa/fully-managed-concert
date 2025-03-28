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
    currentBeat = 0,
    currentBar = 0,
    currentSection = nil,
}

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
end

-- Handle song changes
SongEvent.OnClientEvent:Connect(function(songId: string)
    print("Now playing:", songId)
end)

-- Handle beat updates
BeatEvent.OnClientEvent:Connect(function(data: Types.BeatUpdateData)
    if not data then return end
    
    print("Beat Data Received:")
    print("BPM:", data.bpm)
    print("First Beat Offset:", tostring(data.firstBeatOffset or "nil") .. "s")
    print("Number of Bars:", data.numBars)
    
    if danceController then
        if danceController.onBeat then
            danceController:onBeat(data)
        end
    end
    if beatEffects and beatEffects.onBeat then
        beatEffects:onBeat(data.currentTime, data.beatTime)
    end
    onBeat(data)
end)

-- Initialize chat commands when LocalPlayer is ready
if Players.LocalPlayer then
    setupChatCommands()
else
    Players:GetPropertyChangedSignal("LocalPlayer"):Connect(setupChatCommands)
end
