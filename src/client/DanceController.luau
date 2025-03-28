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
        -- Add new fields for tracking other players
        playerAnimators: { [Player]: Animator },
        playerTracks: { [Player]: AnimationTrack? },
        beatEffects: { [string]: () -> () }
    },
    new: () -> DanceController,
    destroy: (self: DanceController) -> (),
    init: (self: DanceController) -> (),
    handleCharacterAdded: (self: DanceController, character: Model?) -> (),
    preloadAnimations: (self: DanceController) -> (),
    startDancing: (self: DanceController, danceId: string?) -> (),
    stopDancing: (self: DanceController) -> (),
    onBeat: (self: DanceController, beatData: Types.BeatData) -> (),
    -- Add new methods for player sync
    handleOtherCharacterAdded: (self: DanceController, player: Player, character: Model) -> (),
    handleOtherCharacterRemoved: (self: DanceController, player: Player) -> (),
    startDanceForPlayer: (self: DanceController, player: Player, danceId: string?) -> (),
    stopDanceForPlayer: (self: DanceController, player: Player) -> ()
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

local function calculateTimePosition(currentBeat: number, beatCount: number, _bpm: number, animLength: number): number
    -- Calculate what fraction through the animation we should be based on the current beat
    local beatProgress = (currentBeat - 1) / beatCount
    
    -- Calculate the target time position
    local timePosition = beatProgress * animLength
    
    return timePosition
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

-- Constructor
function DanceController.new(): DanceController
    local self = setmetatable({
        state = {
            currentDanceId = nil :: string?,
            character = nil :: Model?,
            humanoid = nil :: Humanoid?,
            animator = nil :: Animator?,
            preloadComplete = false,
            stateConnection = nil :: RBXScriptConnection?,
            beatEffects = {} :: {[string]: () -> ()},
            currentBPM = 0,
            currentDanceConfig = nil,
            currentTrack = nil,
            playerAnimators = {},
            playerTracks = {}
        }
    }, DanceController)

    -- Wait for player and character
    task.spawn(function()
        local player = Players.LocalPlayer
        if not player then
            player = Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        end
        
        -- Wait for character
        local character = player.Character
        if not character then
            character = player.CharacterAdded:Wait()
        end
        
        -- Set up character handling
        self:handleCharacterAdded(character)
        player.CharacterAdded:Connect(function(newCharacter)
            self:handleCharacterAdded(newCharacter)
        end)
    end)
    
    return self
end

function DanceController:init()
    local danceEvent = ReplicatedStorage:WaitForChild("DanceSync", 5)
    if not danceEvent then
        warn("[DanceController] Failed to find DanceSync event after 5 seconds")
        return
    end
    
    -- Update state with initial values (don't overwrite the whole state)
    if not self.state then
        self.state = {}
    end
    
    -- Merge in default values while preserving existing state
    local defaults = {
        currentDanceId = self.state.currentDanceId,
        currentDanceConfig = self.state.currentDanceConfig,
        currentTrack = self.state.currentTrack,
        currentBPM = self.state.currentBPM or 0,
        currentBeat = self.state.currentBeat or 0,
        beatCount = self.state.beatCount or 0,
        preloadComplete = self.state.preloadComplete or false,
        humanoid = self.state.humanoid,
        character = self.state.character,
        animator = self.state.animator,
        characterAddedConnection = self.state.characterAddedConnection,
        loopConnection = self.state.loopConnection,
        movementConnection = self.state.movementConnection,
        stateConnection = self.state.stateConnection,
        playerAnimators = self.state.playerAnimators or {},
        playerTracks = self.state.playerTracks or {},
        beatEffects = self.state.beatEffects or {}
    }
    
    -- Update state while preserving any existing values
    for k, v in pairs(defaults) do
        self.state[k] = self.state[k] or v
    end
    
    -- Set up character handling for local player
    self:setupCharacterHandling()
    
    -- Set up handling for other players
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer and player.Character then
            self:handleOtherCharacterAdded(player, player.Character)
        end
    end
    
    Players.PlayerAdded:Connect(function(player)
        if player ~= Players.LocalPlayer then
            if player.Character then
                self:handleOtherCharacterAdded(player, player.Character)
            end
            player.CharacterAdded:Connect(function(character)
                self:handleOtherCharacterAdded(player, character)
            end)
        end
    end)
    
    print("[DanceController] Initialized successfully")
    return true
end

function DanceController:handleOtherCharacterAdded(player: Player, character: Model)
    -- Get humanoid and animator
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    if not humanoid then return end
    
    local animator = humanoid:WaitForChild("Animator") :: Animator
    if not animator then return end
    
    -- Store animator reference
    self.state.playerAnimators[player] = animator
    self.state.playerTracks[player] = nil
end

function DanceController:handleOtherCharacterRemoved(player: Player)
    -- Clean up player's state
    if self.state.playerTracks[player] then
        self.state.playerTracks[player]:Stop(0.3)
        self.state.playerTracks[player] = nil
    end
    self.state.playerAnimators[player] = nil
end

function DanceController:startDanceForPlayer(player: Player, danceId: string?)
    local animator = self.state.playerAnimators[player]
    if not animator then return end
    
    -- Stop current dance if any
    if self.state.playerTracks[player] then
        self.state.playerTracks[player]:Stop(0.3)
        self.state.playerTracks[player] = nil
    end
    
    -- If no dance specified, just stop
    if not danceId then return end
    
    -- Get dance config
    local config = DANCE_ANIMATIONS[danceId]
    if not config then return end
    
    -- Create and play animation
    local validId = validateAnimationId(config.id)
    if not validId then return end
    
    local anim = Instance.new("Animation")
    anim.AnimationId = validId
    
    local track = animator:LoadAnimation(anim)
    if not track then
        anim:Destroy()
        return
    end
    
    -- Store track reference
    self.state.playerTracks[player] = track
    
    -- Calculate initial time position
    local length = getAnimationLength(validId)
    if length <= 0 then
        anim:Destroy()
        return
    end
    
    local timePosition = calculateTimePosition(
        (self.state.currentBeat or 1) :: number,
        config.beatCount,
        (self.state.currentBPM or 120) :: number,
        length
    )
    
    -- Play the track
    track:Play()
    track.TimePosition = timePosition
    
    -- Update animation speed
    updateAnimationSpeed(track, {
        danceId = danceId,
        originalLength = length,
        beatsPerLoop = config.beatsPerLoop
    } :: AnimationMetadata, self.state.currentBPM)
    
    -- Clean up animation object
    anim:Destroy()
end

function DanceController:stopDanceForPlayer(player: Player)
    if self.state.playerTracks[player] then
        self.state.playerTracks[player]:Stop(0.3)
        self.state.playerTracks[player] = nil
    end
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
    local characterAddedConnection = player.CharacterAdded:Connect(function(character: Model)
        print("[DanceController] Character added")
        self:handleCharacterAdded(character)
    end)
    self.state.characterAddedConnection = characterAddedConnection :: RBXScriptConnection
end

function DanceController:handleCharacterAdded(character: Model?)
    print("[DanceController] Character added")
    
    -- Clean up old state
    if self.state.stateConnection then
        self.state.stateConnection:Disconnect()
    end
    self.state.character = nil
    self.state.humanoid = nil
    self.state.animator = nil
    self.state.stateConnection = nil
    
    -- Get humanoid
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid then
        warn("[DanceController] Cannot find humanoid in character")
        return
    end
    
    -- Get animator
    local animator = humanoid:WaitForChild("Animator", 5)
    if not animator then
        warn("[DanceController] Cannot find animator in humanoid")
        return
    end
    
    -- Store references
    self.state.character = character
    self.state.humanoid = humanoid
    self.state.animator = animator
    
    -- Preload animations now that we have an animator
    task.spawn(function()
        self:preloadAnimations()
    end)
    
    -- Re-apply current dance if needed
    if self.state.currentDanceId then
        self:startDancing(self.state.currentDanceId)
    end
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
        local loopConnection = RunService.Heartbeat:Connect(function()
            -- Get current dance config and track
            local currentDanceId = self.state.currentDanceId
            if not currentDanceId then return end
            
            local currentConfig = DANCE_ANIMATIONS[currentDanceId]
            if not currentConfig then return end
            
            local currentTrack = AnimationCache.tracks[currentDanceId]
            if not currentTrack then return end
            
            local currentLength = getAnimationLength(validateAnimationId(currentConfig.id) or "")
            if currentLength <= 0 then return end
            
            -- If track should be playing but isn't, restart it
            if not currentTrack.IsPlaying then
                currentTrack:Play()
                -- Update speed after playing
                updateAnimationSpeed(currentTrack, {
                    danceId = currentDanceId,
                    originalLength = currentLength,
                    beatsPerLoop = currentConfig.beatsPerLoop
                } :: AnimationMetadata, self.state.currentBPM)
            end
        end)
        self.state.loopConnection = loopConnection :: RBXScriptConnection
    end
    
    -- Calculate initial time position based on current beat
    local timePosition = calculateTimePosition(
        (self.state.currentBeat or 1) :: number,  
        config.beatCount,
        (self.state.currentBPM or 120) :: number,  
        length
    )
    
    print(string.format("[DanceController] Starting dance at time position: %.2f (beat %d/%d)", 
        timePosition, (self.state.currentBeat or 1), config.beatCount))
    
    -- Play the track from the calculated time position
    track:Play()
    track.TimePosition = timePosition
    
    -- Update speed after playing
    updateAnimationSpeed(track, {
        danceId = danceIdStr,
        originalLength = length,
        beatsPerLoop = config.beatsPerLoop
    } :: AnimationMetadata, self.state.currentBPM)
end

function DanceController:onBeat(data: any)
    -- Validate we're ready
    if not self.state.preloadComplete then
        return
    end
    
    -- Update BPM if provided
    if data.bpm then
        print("[DanceController] Updated BPM to:", data.bpm)
        self.state.currentBPM = data.bpm
    end
    
    -- Apply beat effects if any exist
    if self.state.beatEffects then
        for _, effect in pairs(self.state.beatEffects) do
            if typeof(effect) == "function" then
                task.spawn(effect, data)
            end
        end
    end
end

function DanceController:stopDancing()
    if self.state.currentTrack then
        self.state.currentTrack:Stop(0.3)
        self.state.currentTrack = nil
    end
    self.state.currentDanceId = nil
    self.state.currentDanceConfig = nil
end

function DanceController:destroy()
    self:stopDancing()
    
    -- Safely disconnect all connections
    local connections = {
        characterAddedConnection = self.state.characterAddedConnection,
        loopConnection = self.state.loopConnection,
        movementConnection = self.state.movementConnection,
        stateConnection = self.state.stateConnection
    }
    
    for _name, connection in pairs(connections) do
        if connection then
            connection:Disconnect()
        end
    end
    
    -- Clear all state
    self.state.characterAddedConnection = nil
    self.state.loopConnection = nil
    self.state.movementConnection = nil
    self.state.stateConnection = nil
    self.state = nil
end

function DanceController:preloadAnimations()
    print("[DanceController] Preloading animations...")
    
    -- Wait for animator if needed
    if not self.state.animator then
        local character = self.state.character or Players.LocalPlayer.Character
        if not character then
            warn("[DanceController] Cannot preload animations - no character")
            return
        end
        
        local humanoid = character:WaitForChild("Humanoid", 5)
        if not humanoid then
            warn("[DanceController] Cannot preload animations - no humanoid")
            return
        end
        
        local animator = humanoid:WaitForChild("Animator", 5)
        if not animator then
            warn("[DanceController] Cannot preload animations - no animator")
            return
        end
        
        self.state.animator = animator
    end
    
    -- Preload each animation
    for danceId, config in pairs(DANCE_ANIMATIONS) do
        -- Get animation ID
        local validId = validateAnimationId(config.id)
        if not validId then
            warn("[DanceController] Invalid animation ID for dance:", danceId)
            continue
        end
        
        -- Create animation object
        local animation = Instance.new("Animation")
        animation.AnimationId = validId
        
        -- Load and cache animation
        task.spawn(function()
            local success, result = pcall(function()
                local track = self.state.animator:LoadAnimation(animation)
                if track then
                    AnimationCache.tracks[danceId] = track
                    local length = track.Length
                    AnimationCache.lengths[validId] = length
                    print(string.format("[DanceController] Cached animation %s: length=%.2f", danceId, length))
                end
            end)
            if not success then
                warn("[DanceController] Failed to load animation", danceId, "-", result)
            end
        end)
    end
    
    self.state.preloadComplete = true
    print("[DanceController] Animation preload complete")
end

function DanceController:startDancing(danceId: string?)
    -- First handle local animation
    local oldDanceId = self.state.currentDanceId
    
    if self.state.currentTrack then
        self.state.currentTrack:Stop(0.3)
        self.state.currentTrack = nil
    end
    
    -- If no dance specified, just stop and broadcast stop
    if not danceId then
        self.state.currentDanceId = nil
        self.state.currentDanceConfig = nil
        ReplicatedStorage.DanceSync:FireServer(nil)
        return
    end
    
    -- Get dance config
    local config = DANCE_ANIMATIONS[danceId]
    if not config then
        warn("[DanceController] Invalid dance ID:", danceId)
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
            self:startDancing(danceId)
        end)
        return
    end
    
    -- Get cached track
    local track = AnimationCache.tracks[danceId]
    if not track then
        warn("[DanceController] No track found for dance:", danceId)
        return
    end
    
    -- Update state
    self.state.currentDanceId = danceId
    self.state.currentDanceConfig = config
    self.state.currentTrack = track
    
    -- Play animation
    track:Play(0.3)
    track:AdjustSpeed(1)
    
    -- Broadcast dance change to other clients
    ReplicatedStorage.DanceSync:FireServer(danceId)
end

return DanceController
