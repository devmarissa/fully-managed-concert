--!strict
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Types = require(game:GetService("ReplicatedStorage").shared.Types)

type SongSection = Types.SongSection

local LightingEffects = {}
LightingEffects.__index = LightingEffects

-- Map of section names to colors
local SECTION_COLORS = {
    ["intro"] = Color3.fromRGB(64, 156, 255),    -- Light blue
    ["verse"] = Color3.fromRGB(101, 255, 162),   -- Light green
    ["chorus"] = Color3.fromRGB(255, 73, 73),    -- Red
    ["bridge"] = Color3.fromRGB(194, 77, 255),   -- Purple
    ["outro"] = Color3.fromRGB(255, 198, 89),    -- Orange
    ["drop"] = Color3.fromRGB(255, 73, 201),     -- Pink
    ["build"] = Color3.fromRGB(255, 247, 73),    -- Yellow
    ["breakdown"] = Color3.fromRGB(73, 255, 255), -- Cyan
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
    return self
end

function LightingEffects:getColorForSection(sectionName: string): Color3
    -- Convert section name to lowercase and remove spaces
    local cleanName = string.lower(string.gsub(sectionName, "%s+", ""))
    
    -- Try to find a predefined color for this section
    if SECTION_COLORS[cleanName] then
        return SECTION_COLORS[cleanName]
    end
    
    -- Use next color from default cycle
    local color = DEFAULT_COLORS[self.currentColorIndex]
    self.currentColorIndex = (self.currentColorIndex % #DEFAULT_COLORS) + 1
    return color
end

function LightingEffects:transitionToSection(section: SongSection)
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
    print(string.format("Section changed to: %s (%.2fs - %.2fs)", 
        section.name, section.start_time, section.end_time))
end

return LightingEffects
