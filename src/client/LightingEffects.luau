--!strict
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Types = require(game:GetService("ReplicatedStorage").shared.Types)

type SongSection = Types.SongSection

local LightingEffects = {}
LightingEffects.__index = LightingEffects

-- Map of section names to colors
local SECTION_COLORS = {
    ["Intro"] = Color3.fromRGB(64, 156, 255),      -- Light blue
    ["Intro 2"] = Color3.fromRGB(101, 255, 162),   -- Light green
    ["Drop 1"] = Color3.fromRGB(255, 73, 73),      -- Red
    ["Drop 2"] = Color3.fromRGB(255, 73, 201),     -- Pink
    ["Breakdown"] = Color3.fromRGB(73, 255, 255),   -- Cyan
    ["Buildup"] = Color3.fromRGB(255, 247, 73),    -- Yellow
    ["Vocals"] = Color3.fromRGB(194, 77, 255),     -- Purple
    ["Vocals 2"] = Color3.fromRGB(194, 77, 255),   -- Purple
    ["Outro"] = Color3.fromRGB(255, 198, 89),      -- Orange
}

-- Default colors for unknown sections (will cycle through these)
local DEFAULT_COLORS = {
    Color3.fromRGB(255, 73, 73),   -- Red
    Color3.fromRGB(73, 255, 73),   -- Green
    Color3.fromRGB(73, 73, 255),   -- Blue
    Color3.fromRGB(255, 255, 73),  -- Yellow
    Color3.fromRGB(255, 73, 255),  -- Magenta
    Color3.fromRGB(73, 255, 255),  -- Cyan
}

function LightingEffects.new()
    local self = setmetatable({}, LightingEffects)
    self.currentColorIndex = 1
    print("[LightingEffects] Initialized")
    return self
end

function LightingEffects:getColorForSection(sectionName: string): Color3
    -- Try to find a predefined color for this section
    if SECTION_COLORS[sectionName] then
        print("[LightingEffects] Found color for section:", sectionName)
        return SECTION_COLORS[sectionName]
    end
    
    -- Use next color from default cycle
    print("[LightingEffects] No color found for section:", sectionName)
    local color = DEFAULT_COLORS[self.currentColorIndex]
    self.currentColorIndex = (self.currentColorIndex % #DEFAULT_COLORS) + 1
    return color
end

function LightingEffects:transitionToSection(section: SongSection)
    print("[LightingEffects] Transitioning to section:", section.name)
    local color = self:getColorForSection(section.name)
    
    -- Create smooth transition
    local tweenInfo = TweenInfo.new(
        1,                              -- Time to transition
        Enum.EasingStyle.Sine,         -- Smooth easing
        Enum.EasingDirection.InOut     -- Smooth both ways
    )
    
    -- Tween ambient and outdoor ambient
    local lightingTween = TweenService:Create(Lighting, tweenInfo, {
        Ambient = color,
        OutdoorAmbient = color:Lerp(Color3.new(0, 0, 0), 0.5) -- Darker version
    })
    
    lightingTween:Play()
    print(string.format("[LightingEffects] Section changed to: %s (%.2fs - %.2fs)", 
        section.name, section.start_time, section.end_time))
end

return LightingEffects
