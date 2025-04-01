--!strict
--[[
    BeatEffects.luau
    Creates visual effects synchronized to music beats.
    
    Example Usage:
    ```lua
    local effects = BeatEffects.new()
    effects:doBeatEffect(1.5, 1, 0) -- Strong effect on downbeat
    effects:doBeatEffect(1.0, 2, 1) -- Normal effect on other beats
    ```
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Types = require(game:GetService("ReplicatedStorage").shared.Types)

type BeatGrid = Types.BeatGrid

local BeatEffects = {}
BeatEffects.__index = BeatEffects

-- Constants
local DEFAULT_FOV = 70
local TWEEN_DURATION = 0.1

function BeatEffects.new()
    local self = setmetatable({}, BeatEffects)
    
    -- Store original FOV
    local player = Players.LocalPlayer
    if player.Character then
        local camera = workspace.CurrentCamera
        if camera then
            self.defaultFov = camera.FieldOfView
        else
            self.defaultFov = DEFAULT_FOV
        end
    end
    
    return self
end

--[[
    Create a camera FOV pulse effect on the beat
    @param intensity: number - How strong the effect should be (1.0 = normal, 1.5 = strong)
    @param beatNum: number - Which beat in the bar (1-4)
    @param beatTime: number - Time of the beat in seconds
]]
function BeatEffects:doBeatEffect(intensity: number, beatNum: number, beatTime: number)
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    local function onBeat(beatData: Types.BeatData)
        if not beatData then return end
        
        print(string.format("[BeatEffects] Beat %d at %.3fs (BPM: %.1f)", 
            beatData.beatNum or 0,
            beatData.beatTime or 0,
            beatData.bpm or 0
        ))
        
        -- Calculate FOV change based on intensity
        local fovChange = 5 * intensity -- 5 degree change for normal beats, 7.5 for strong beats
        local startFov = self.defaultFov or DEFAULT_FOV
        
        -- Zoom out
        local outTween = TweenService:Create(camera, 
            TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { FieldOfView = startFov + fovChange }
        )
        outTween:Play()
        
        -- Return to normal
        task.delay(TWEEN_DURATION, function()
            local inTween = TweenService:Create(camera, 
                TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                { FieldOfView = startFov }
            )
            inTween:Play()
        end)
    end
    
    onBeat({ beatNum = beatNum, beatTime = beatTime, bpm = 120 }) -- Assuming 120 BPM for now
end

return BeatEffects
