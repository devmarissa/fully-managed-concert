--[[
    Dance Controller
    Handles character dance animations synchronized to music beats
]]

--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.shared.Types)

-- Type definitions
export type DanceController = {
    state: DanceState,
    new: () -> DanceController,
    setupCharacterHandling: (self: DanceController) -> (),
    handleCharacterAdded: (self: DanceController, character: Model?) -> (),
    setDance: (self: DanceController, danceId: string | number) -> (),
    onBeat: (self: DanceController, beatData: Types.BeatData) -> (),
    stopDancing: (self: DanceController) -> (),
    destroy: (self: DanceController) -> (),
    preloadAnimations: (self: DanceController) -> ()
}

type DanceState = {
    currentTrack: AnimationTrack?,
    currentDanceConfig: DanceConfig?,
    currentDanceId: string?,
    currentBPM: number,
    currentBeat: number,
    beatCount: number,
    beatsPlayed: number,  
    humanoid: Humanoid?,
    animator: Animator?,
    loopConnection: RBXScriptConnection?,
    lastBeatTime: number,
    characterAddedConnection: RBXScriptConnection?,
    character: Model?,
    waitingForBeatOne: boolean,
    autoAdvance: boolean,
    preloadComplete: boolean
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
        id = "87862418875672",
        beatsPerLoop = 8, 
        resetOnBeat = 1,
        beatCount = 8,
        offset = 0,
        currentBeatCount = 0
    },
    ["2"] = {
        id = "138209040418667",
        beatsPerLoop = 4,
        resetOnBeat = 1,
        beatCount = 4,
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
    }
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

local function updateAnimationSpeed(track: AnimationTrack, metadata: AnimationMetadata, currentBpm: number?)
    if not track or not metadata then 
        warn("[DanceController] Missing track or metadata for speed update")
        return 
    end
    
    if not metadata.originalLength or metadata.originalLength <= 0 then
        warn("[DanceController] Invalid animation length:", metadata.originalLength)
        return
    end
    
    if not metadata.beatsPerLoop or metadata.beatsPerLoop <= 0 then
        warn("[DanceController] Invalid beatsPerLoop:", metadata.beatsPerLoop)
        return
    end
    
    -- Calculate target speed based on BPM
    -- One beat takes (60/BPM) seconds
    -- beatsPerLoop beats take (60/BPM * beatsPerLoop) seconds
    -- Speed = originalLength / targetDuration
    local bpm = currentBpm or DEFAULT_BPM
    local targetDuration = (60 / bpm) * metadata.beatsPerLoop
    local targetSpeed = metadata.originalLength / targetDuration
    
    print(string.format("[DanceController] Speed calculation for dance %s:", metadata.danceId))
    print(string.format("- BPM: %.2f", bpm))
    print(string.format("- Original Length: %.2f", metadata.originalLength))
    print(string.format("- Target Duration: %.2f", targetDuration))
    print(string.format("- Beats Per Loop: %d", metadata.beatsPerLoop))
    print(string.format("- Target Speed: %.2f", targetSpeed))
    
    track:AdjustSpeed(targetSpeed)
end

local function getNextDanceId(currentId: string?): string
    if not currentId then return "1" end
    
    local danceIds = {}
    for id in pairs(DANCE_ANIMATIONS) do
        table.insert(danceIds, id)
    end
    table.sort(danceIds)
    
    local currentIndex = table.find(danceIds, currentId)
    if not currentIndex then return danceIds[1] end
    
    local nextIndex = currentIndex % #danceIds + 1
    return danceIds[nextIndex]
end

local DanceController = {}
DanceController.__index = DanceController

function DanceController.new()
    local self = setmetatable({
        state = {
            currentTrack = nil,
            currentDanceConfig = nil,
            currentDanceId = nil,
            currentBPM = DEFAULT_BPM,
            currentBeat = 0,
            beatCount = 0,
            beatsPlayed = 0,
            humanoid = nil,
            animator = nil,
            loopConnection = nil,
            lastBeatTime = 0,
            characterAddedConnection = nil,
            character = nil,
            waitingForBeatOne = false,
            autoAdvance = true,
            preloadComplete = false
        }
    }, DanceController)
    
    self:setupCharacterHandling()
    return self
end

function DanceController:setupCharacterHandling()
    -- Set up character handling
    print("[DanceController] Setting up character handling")
    
    local player = Players.LocalPlayer
    if not player then return end
    
    -- Check for existing character
    if player.Character then
        print("[DanceController] Found existing character")
        self:handleCharacterAdded(player.Character)
    end
    
    -- Connect to character added event
    self.state.characterAddedConnection = player.CharacterAdded:Connect(function(character: Model)
        print("[DanceController] Character added")
        self:handleCharacterAdded(character)
    end)
end

function DanceController:handleCharacterAdded(character: Model?)
    if not character then return end
    
    print("[DanceController] Character added")
    
    -- Clean up previous connections
    if self.state.currentTrack then
        self.state.currentTrack:Stop()
    end
    
    -- Wait for humanoid
    print("[DanceController] Waiting for Humanoid...")
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    if not humanoid then
        warn("[DanceController] No Humanoid found")
        return
    end
    
    -- Wait for animator
    print("[DanceController] Waiting for Animator...")
    local animator = humanoid:WaitForChild("Animator") :: Animator
    if not animator then
        warn("[DanceController] No Animator found")
        return
    end
    
    print("[DanceController] Found humanoid and animator")
    
    -- Store references
    self.state.humanoid = humanoid :: any
    self.state.animator = animator :: any
    self.state.character = character :: any
    
    -- Preload animations
    self:preloadAnimations()
end

function DanceController:setDance(danceId: string | number)
    -- Convert number to string if needed
    local danceIdStr = if type(danceId) == "number" then tostring(danceId) else danceId

    print("[DanceController] Setting dance:", danceIdStr)
    local config = DANCE_ANIMATIONS[danceIdStr]
    if not config then
        warn("[DanceController] Invalid dance ID:", danceIdStr)
        return
    end

    -- Check if animations are preloaded
    if not self.state.preloadComplete then
        warn("[DanceController] Waiting for animations to preload...")
        -- Wait for preload to complete
        task.spawn(function()
            while not self.state.preloadComplete do
                task.wait(0.1)
            end
            self:setDance(danceIdStr)
        end)
        return
    end

    -- Get cached track
    local track = AnimationCache.tracks[danceIdStr]
    if not track then
        warn("[DanceController] No track found for dance:", danceIdStr)
        return
    end

    -- Get animation length
    local validId = validateAnimationId(config.id)
    if not validId then return end
    
    local length = getAnimationLength(validId)
    if length <= 0 then
        warn("[DanceController] Invalid animation length, cannot play dance:", danceIdStr)
        return
    end

    -- Stop previous animation if any
    if self.state.currentTrack then
        self.state.currentTrack:Stop()
    end

    -- Reset beats played counter
    self.state.beatsPlayed = 0
    
    -- Store current track and config
    self.state.currentTrack = track
    self.state.currentDanceId = danceIdStr
    self.state.currentDanceConfig = config
    
    -- Set up animation handling
    if not self.state.loopConnection then
        self.state.loopConnection = RunService.Heartbeat:Connect(function()
            -- Get current dance config and track
            local currentDanceId = self.state.currentDanceId
            if not currentDanceId then return end
            
            local currentConfig = DANCE_ANIMATIONS[currentDanceId]
            if not currentConfig then return end
            
            local currentTrack = AnimationCache.tracks[currentDanceId]
            if not currentTrack then return end
            
            local currentLength = getAnimationLength(validateAnimationId(currentConfig.id) or "")
            if currentLength <= 0 then return end
            
            -- If waiting for beat one, only start on beat one
            if self.state.waitingForBeatOne then
                if self.state.currentBeat == 1 then
                    print("[DanceController] Starting dance on beat 1:", currentDanceId)
                    self.state.waitingForBeatOne = false
                    currentTrack:Play()
                    -- Update speed after playing
                    updateAnimationSpeed(currentTrack, {
                        danceId = currentDanceId,
                        originalLength = currentLength,
                        beatsPerLoop = currentConfig.beatsPerLoop
                    } :: AnimationMetadata, self.state.currentBPM)
                end
                return
            end
            
            -- If track should be playing but isn't, restart it
            if not currentTrack.IsPlaying and not self.state.waitingForBeatOne then
                currentTrack:Play()
                -- Update speed after playing
                updateAnimationSpeed(currentTrack, {
                    danceId = currentDanceId,
                    originalLength = currentLength,
                    beatsPerLoop = currentConfig.beatsPerLoop
                } :: AnimationMetadata, self.state.currentBPM)
            end
        end)
    end
    
    -- Start playing if we're not waiting for beat one
    if not self.state.waitingForBeatOne then
        print("[DanceController] Playing dance immediately:", danceIdStr)
        track:Play()
        -- Update speed after playing
        updateAnimationSpeed(track, {
            danceId = danceIdStr,
            originalLength = length,
            beatsPerLoop = config.beatsPerLoop
        } :: AnimationMetadata, self.state.currentBPM)
    end
end

function DanceController:onBeat(beatData: Types.BeatData)
    if not beatData then return end
    
    -- Update BPM if changed
    if beatData.bpm and beatData.bpm ~= self.state.currentBPM then
        self.state.currentBPM = beatData.bpm
        print("[DanceController] Updated BPM to:", beatData.bpm)
        
        if self.state.currentTrack and self.state.currentDanceConfig then
            local validId = validateAnimationId(self.state.currentDanceConfig.id)
            if validId then
                updateAnimationSpeed(self.state.currentTrack, {
                    danceId = self.state.currentDanceId or "",
                    originalLength = getAnimationLength(validId),
                    beatsPerLoop = self.state.currentDanceConfig.beatsPerLoop
                } :: AnimationMetadata, beatData.bpm)
            end
        end
    end
    
    -- Update beat tracking
    if beatData.beatGrid and #beatData.beatGrid.beat_nums > 0 then
        self.state.currentBeat = beatData.beatGrid.beat_nums[1]
        self.state.beatCount = #beatData.beatGrid.beat_nums
    end
    
    -- Track beats played for current dance
    if not self.state.waitingForBeatOne and self.state.currentTrack and self.state.currentTrack.IsPlaying then
        self.state.beatsPlayed = (self.state.beatsPlayed or 0) + 1
        
        -- Check if we should advance to next dance
        if self.state.autoAdvance and self.state.currentDanceConfig then
            if self.state.beatsPlayed >= self.state.currentDanceConfig.beatsPerLoop then
                local nextDanceId = getNextDanceId(self.state.currentDanceId or "1")
                print("[DanceController] Dance complete, advancing to:", nextDanceId)
                -- Stop current track before waiting for beat one
                if self.state.currentTrack then
                    (self.state.currentTrack :: AnimationTrack):Stop(0.3)
                end
                self.state.waitingForBeatOne = true
                self:setDance(nextDanceId)
            end
        end
    end
end

function DanceController:stopDancing()
    local track = self.state.currentTrack :: AnimationTrack
    if track then
        track:Stop(0.3)
    end
    self.state.currentTrack = nil
    self.state.currentDanceId = nil
    self.state.currentDanceConfig = nil
end

function DanceController:destroy()
    self:stopDancing()
    if self.state.characterAddedConnection then
        self.state.characterAddedConnection:Disconnect()
    end
    if self.state.loopConnection then
        self.state.loopConnection:Disconnect()
    end
    self.state = nil :: any
end

function DanceController:preloadAnimations()
    if not self.state.humanoid then
        warn("[DanceController] Cannot preload animations - no humanoid")
        return
    end
    
    print("[DanceController] Preloading animations...")
    
    -- Reset preload state
    self.state.preloadComplete = false
    AnimationCache.tracks = {}
    
    local animations = {}
    for danceId, config in pairs(DANCE_ANIMATIONS) do
        local validId = validateAnimationId(config.id)
        if validId then
            local anim = Instance.new("Animation")
            anim.AnimationId = validId
            
            -- Create animation track
            local track = self.state.humanoid:LoadAnimation(anim)
            if track then
                AnimationCache.tracks[danceId] = track
                print("[DanceController] Created track for animation", danceId)
            else
                warn("[DanceController] Failed to create track for animation", danceId)
            end
            
            table.insert(animations, anim)
        end
    end
    
    -- Preload all animations
    local success = pcall(function()
        ContentProvider:PreloadAsync(animations)
    end)
    
    if not success then
        warn("[DanceController] Failed to preload animations")
        return
    end
    
    -- Load and cache animation lengths
    for danceId, config in pairs(DANCE_ANIMATIONS) do
        local validId = validateAnimationId(config.id)
        if validId then
            print("[DanceController] Preloaded animation", danceId)
            local length = getAnimationLength(validId)
            print("[DanceController] Animation", danceId, "length:", length)
        end
    end
    
    print("[DanceController] Preload complete")
    self.state.preloadComplete = true
end

return DanceController
