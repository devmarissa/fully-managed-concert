--[[
    Dance Controller
    Handles character dance animations synchronized to music beats
]]

--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.shared.Types)
local SyncHandler = require(script.Parent.SyncHandler)

-- Type definitions
export type DanceController = {
    state: {
        currentDanceId: string?,
        currentDanceConfig: DanceConfig?,
        currentTrack: AnimationTrack?,
        currentBPM: number,
        currentBeat: number,
        beatCount: number,
        preloadComplete: boolean,
        humanoid: Humanoid?,
        character: Model?,
        animator: Animator?,
        characterAddedConnection: RBXScriptConnection?,
        loopConnection: RBXScriptConnection?,
        movementConnection: RBXScriptConnection?,
        stateConnection: RBXScriptConnection?,
        beatEffects: { [string]: () -> () }
    },
    new: () -> DanceController,
    destroy: (self: DanceController) -> (),
    init: (self: DanceController) -> (),
    handleCharacterAdded: (self: DanceController, character: Model?) -> (),
    preloadAnimations: (self: DanceController) -> (),
    startDancing: (self: DanceController, danceId: string?) -> (),
    stopDancing: (self: DanceController) -> (),
    onBeat: (self: DanceController, beatData: Types.BeatData) -> ()
}

type DanceState = {
    currentTrack: AnimationTrack | nil,
    currentDanceConfig: DanceConfig | nil,
    currentDanceId: string | nil,
    currentBPM: number,
    currentBeat: number,
    beatCount: number,
    beatsPlayed: number,  
    humanoid: Humanoid | nil,
    animator: Animator | nil,
    loopConnection: RBXScriptConnection | nil,
    lastBeatTime: number,
    characterAddedConnection: RBXScriptConnection | nil,
    character: Model | nil,
    waitingForBeatOne: boolean,
    autoAdvance: boolean,
    preloadComplete: boolean,
    movementConnection: RBXScriptConnection | nil,
    stateConnection: RBXScriptConnection | nil
}

type DanceConfig = {
    id: string,
    beatsPerLoop: number,
    resetOnBeat: number,
    beatCount: number,
    offset: number,
    currentBeatCount: number?,
    lastResetBeat: number?
}

type AnimationMetadata = {
    danceId: string,
    originalLength: number,
    beatsPerLoop: number
}

-- Configuration
local DEFAULT_BPM = 110
local AnimationCache = {
    tracks = {} :: {[string]: AnimationTrack},
    lengths = {} :: {[string]: number}
}

local DANCE_ANIMATIONS: {[string]: DanceConfig} = {
    ["1"] = { 
        id = "135969890864340",
        beatsPerLoop = 8, 
        resetOnBeat = 1,
        beatCount = 8,
        offset = 0,
        currentBeatCount = 0
    },
    ["2"] = {
        id = "97830505935008",
        beatsPerLoop = 8,
        resetOnBeat = 1,
        beatCount = 8,
        offset = 0,
        currentBeatCount = 0
    },
    ["3"] = { 
        id = "138886954326226",
        beatsPerLoop = 16, 
        resetOnBeat = 1,
        beatCount = 16,
        offset = 0,
        currentBeatCount = 0
    },
    ["4"] = { 
        id = "87862418875672",
        beatsPerLoop = 8, 
        resetOnBeat = 1,
        beatCount = 8,
        offset = 0,
        currentBeatCount = 0
    },
    ["5"] = {
        id = "138209040418667",
        beatsPerLoop = 4,
        resetOnBeat = 1,
        beatCount = 4,
        offset = 0,
        currentBeatCount = 0
    },
}

-- Private functions
local function validateAnimationId(id: string?): string?
    if not id then return nil end
    
    -- If it already has the prefix, return as is
    if string.match(id, "^rbxassetid://") then
        return id
    end
    
    -- Convert to number to validate
    local numericId = tonumber(id)
    if not numericId then
        warn("[DanceController] Invalid animation ID format:", id)
        return nil
    end
    
    return "rbxassetid://" .. numericId
end

local function getAnimationLength(animId: string?): number
    if not animId then return 0 end
    
    -- Check cache first
    if AnimationCache.lengths[animId] then
        return AnimationCache.lengths[animId]
    end
    
    -- Get numeric ID
    local assetId = string.match(animId, "^rbxassetid://(%d+)") or animId
    
    -- Get length using KeyframeSequenceProvider
    local success, sequence = pcall(function()
        return KeyframeSequenceProvider:GetKeyframeSequenceAsync("rbxassetid://" .. assetId)
    end)
    
    if not success or not sequence then
        warn("[DanceController] Failed to get keyframe sequence:", sequence)
        return 0
    end
    
    -- Find the last keyframe time
    local keyframes = sequence:GetKeyframes()
    local length = 0
    
    for _, keyframe in ipairs(keyframes) do
        if keyframe.Time > length then
            length = keyframe.Time
        end
    end
    
    sequence:Destroy()
    
    -- Cache the length with the full rbxassetid:// format
    local cacheId = validateAnimationId(assetId)
    if cacheId and length > 0 then
        AnimationCache.lengths[cacheId] = length
        print(string.format("[DanceController] Cached animation length: %.2f for %s", length, cacheId))
    end
    
    return length
end

local function updateAnimationSpeed(track: AnimationTrack, metadata: AnimationMetadata, bpm: number)
    if not track or not metadata then return end
    
    -- Calculate timing with higher precision
    local beatsPerSecond = bpm / 60
    local desiredLoopTime = metadata.beatsPerLoop / beatsPerSecond
    
    -- Calculate speed multiplier with higher precision
    -- We want the animation to loop exactly on the beat
    local speedMultiplier = metadata.originalLength / desiredLoopTime
    
    -- Round to 6 decimal places for more precise timing
    speedMultiplier = math.floor(speedMultiplier * 1000000 + 0.5) / 1000000
    
    -- Add a tiny adjustment to account for frame timing
    speedMultiplier = speedMultiplier * 0.9995
    
    print(string.format("[DanceController] Animation speed calculation:"))
    print(string.format("  - BPM: %.2f", bpm))
    print(string.format("  - Beats per second: %.6f", beatsPerSecond))
    print(string.format("  - Beats per loop: %.2f", metadata.beatsPerLoop))
    print(string.format("  - Original length: %.6f seconds", metadata.originalLength))
    print(string.format("  - Desired loop time: %.6f seconds", desiredLoopTime))
    print(string.format("  - Speed multiplier: %.6f", speedMultiplier))
    print(string.format("  - Actual loop time: %.6f seconds", metadata.originalLength / speedMultiplier))
    
    track:AdjustSpeed(speedMultiplier)
end

local function restartAnimation(self)
    if not self.state.currentTrack then return end
    
    -- Stop and remove the current track in a single frame
    local oldTrack = self.state.currentTrack
    self.state.currentTrack = nil
    oldTrack:Stop(0) -- Stop immediately
    oldTrack:Destroy()
    
    -- Start new track immediately in the same frame
    local track = self.state.animator:LoadAnimation(self.state.currentAnimation)
    self.state.currentTrack = track
    updateAnimationSpeed(track, self.state.currentMetadata, self.state.currentBPM)
    track:Play(0) -- Start immediately with no fade
end

local DanceController = {}
DanceController.__index = DanceController

function DanceController.new(): DanceController
    local self = setmetatable({
        state = {
            currentDanceId = nil :: string?,
            currentDanceConfig = nil :: DanceConfig?,
            currentTrack = nil :: AnimationTrack?,
            currentBPM = DEFAULT_BPM,
            currentBeat = 0,
            beatCount = 0,
            preloadComplete = false,
            humanoid = nil :: Humanoid?,
            character = nil :: Model?,
            animator = nil :: Animator?,
            characterAddedConnection = nil :: RBXScriptConnection?,
            loopConnection = nil :: RBXScriptConnection?,
            movementConnection = nil :: RBXScriptConnection?,
            stateConnection = nil :: RBXScriptConnection?,
            beatEffects = {} :: { [string]: () -> () },
            currentAnimation = nil :: Animation?,
            currentMetadata = nil :: AnimationMetadata?
        }
    }, DanceController)
    
    return self
end

function DanceController:init()
    print("[DanceController] Initializing...")
    
    -- Set up character handling
    local player = Players.LocalPlayer
    if not player then
        warn("[DanceController] No LocalPlayer found")
        return
    end
    
    -- Handle initial character
    self:handleCharacterAdded(player.Character)
    
    -- Set up character added connection
    self.state.characterAddedConnection = player.CharacterAdded:Connect(function(character)
        self:handleCharacterAdded(character)
    end)
    
    -- Preload animations
    task.spawn(function()
        self:preloadAnimations()
    end)
    
    -- Connect to SyncHandler
    SyncHandler.onBeat:Connect(function(beatData)
        self:onBeat(beatData)
    end)
end

function DanceController:handleCharacterAdded(character: Model?)
    if not character then return end
    
    print("[DanceController] Character added")
    self.state.character = character
    
    -- Wait for humanoid
    local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid
    if not humanoid then
        warn("[DanceController] No Humanoid found in character")
        return
    end
    
    self.state.humanoid = humanoid
    
    -- Wait for animator
    local animator = humanoid:WaitForChild("Animator", 5) :: Animator
    if not animator then
        warn("[DanceController] No Animator found in Humanoid")
        return
    end
    
    self.state.animator = animator
    
    -- Set up movement detection
    if self.state.movementConnection then
        self.state.movementConnection:Disconnect()
    end
    
    self.state.movementConnection = humanoid.Running:Connect(function(speed)
        if speed > 0.1 then -- If character starts moving
            print("[DanceController] Movement detected, stopping dance")
            self:stopDancing()
        end
    end)
    
    -- If we were dancing before, restart the dance
    if self.state.currentDanceId then
        local danceId = self.state.currentDanceId
        self:stopDancing()
        self:startDancing(danceId)
    end
end

function DanceController:preloadAnimations()
    print("[DanceController] Preloading animations...")
    
    if not self.state.animator then
        warn("[DanceController] No animator available for preloading")
        return
    end
    
    -- Preload all dance animations
    for danceId, config in pairs(DANCE_ANIMATIONS) do
        local animId = validateAnimationId(config.id)
        if not animId then continue end
        
        -- Create animation object
        local animation = Instance.new("Animation")
        animation.AnimationId = animId
        
        -- Load it
        local success, track = pcall(function()
            return self.state.animator:LoadAnimation(animation)
        end)
        
        if success and track then
            -- Cache the track
            AnimationCache.tracks[danceId] = track
            
            -- Get and cache the length
            local length = getAnimationLength(animId)
            if length > 0 then
                AnimationCache.lengths[animId] = length
            end
            
            print(string.format("[DanceController] Preloaded animation %s (Length: %.2f)", danceId, length))
        else
            warn(string.format("[DanceController] Failed to preload animation %s: %s", danceId, tostring(track)))
        end
    end
    
    self.state.preloadComplete = true
    print("[DanceController] Animation preload complete")
end

function DanceController:startDancing(danceId: string?)
    if not danceId then
        warn("[DanceController] No dance ID provided")
        return
    end
    
    print("[DanceController] Starting dance:", danceId)
    
    -- Stop current dance if any
    self:stopDancing()
    
    -- Get dance config
    local config = DANCE_ANIMATIONS[danceId]
    if not config then
        warn("[DanceController] Invalid dance ID:", danceId)
        return
    end
    
    -- Validate animation ID
    local animId = validateAnimationId(config.id)
    if not animId then
        warn("[DanceController] Invalid animation ID for dance:", danceId)
        return
    end
    
    -- Get animator
    if not self.state.animator then
        warn("[DanceController] No animator available")
        return
    end
    
    -- Try to get cached track first
    local track = AnimationCache.tracks[danceId]
    
    -- If not cached, create new track
    if not track then
        local animation = Instance.new("Animation")
        animation.AnimationId = animId
        
        local success, newTrack = pcall(function()
            return self.state.animator:LoadAnimation(animation)
        end)
        
        if not success or not newTrack then
            warn("[DanceController] Failed to load animation:", newTrack)
            return
        end
        
        track = newTrack
        AnimationCache.tracks[danceId] = track
    end
    
    -- Get animation length
    local length = getAnimationLength(animId)
    if length == 0 then
        warn("[DanceController] Failed to get animation length")
        return
    end
    
    -- Set up animation metadata
    local metadata: AnimationMetadata = {
        danceId = danceId,
        originalLength = length,
        beatsPerLoop = config.beatsPerLoop
    }
    
    -- Update animation speed based on current BPM
    updateAnimationSpeed(track, metadata, self.state.currentBPM)
    
    -- Play the animation (with looping)
    track.Looped = true -- Keep playing until stopped
    track:Play()
    
    -- Update state
    self.state.currentDanceId = danceId
    self.state.currentDanceConfig = config
    self.state.currentTrack = track
    self.state.currentAnimation = track.Animation
    self.state.currentMetadata = metadata
    
    print(string.format("[DanceController] Started dance %s (Length: %.2f, BPM: %.0f)", 
        danceId, length, self.state.currentBPM))
end

function DanceController:stopDancing()
    if self.state.currentTrack and self.state.currentTrack.IsPlaying then
        self.state.currentTrack:Stop()
    end
    
    self.state.currentDanceId = nil
    self.state.currentDanceConfig = nil
    self.state.currentTrack = nil
    self.state.currentAnimation = nil
    self.state.currentMetadata = nil
end

function DanceController:onBeat(beatData: Types.BeatData)
    if not beatData then return end
    
    -- Update BPM if changed
    if beatData.bpm and beatData.bpm ~= self.state.currentBPM then
        print(string.format("[DanceController] BPM changed: %.1f -> %.1f", 
            self.state.currentBPM or 0, beatData.bpm))
        self.state.currentBPM = beatData.bpm
        
        -- Update animation speed if playing
        if self.state.currentTrack and self.state.currentDanceId then
            local metadata: AnimationMetadata = {
                danceId = self.state.currentDanceId,
                originalLength = getAnimationLength(self.state.currentTrack.Animation.AnimationId),
                beatsPerLoop = self.state.currentDanceConfig.beatsPerLoop
            }
            updateAnimationSpeed(self.state.currentTrack, metadata, beatData.bpm)
        end
    end
    
    -- Update beat tracking with precise timing
    local prevBeat = self.state.currentBeat
    self.state.currentBeat = beatData.beatNum or 0
    self.state.beatCount = self.state.beatCount + 1
    
    print(string.format("[DanceController] Beat %d at %.3fs (BPM: %.1f)", 
        self.state.currentBeat,
        beatData.beatTime or 0,
        self.state.currentBPM or 0
    ))
    
    -- Only restart on beat 1
    if beatData.beatNum == 1 then
        print("[DanceController] Beat 1 detected, restarting animation")
        restartAnimation(self)
    end
end

function DanceController:destroy()
    self:stopDancing()
    
    -- Safely disconnect all connections
    local connections = {
        self.state.characterAddedConnection,
        self.state.loopConnection,
        self.state.movementConnection,
        self.state.stateConnection
    }
    
    for _, connection in ipairs(connections) do
        if connection then
            connection:Disconnect()
        end
    end
    
    -- Clear state
    self.state = nil
    
    print("[DanceController] Destroyed")
end

return DanceController
