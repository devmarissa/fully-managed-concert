--!strict
--[[
    Types.luau
    Shared type definitions for the AudioScape music system.
    
    Example Usage:
    ```lua
    local Types = require(game:GetService("ReplicatedStorage").shared.Types)
    local function playSong(data: Types.SongData)
        -- Type-safe song handling
    end
    ```
]]

-- Beat timing information
export type BeatGrid = {
    beat_nums: {number}, -- Array of beat numbers (1-4 pattern)
    beat_times: {number} -- Array of beat timestamps in seconds
}

-- Section timing information (optional)
export type SongSection = {
    name: string,      -- Section name (e.g., "verse", "chorus")
    start_time: number, -- When section starts (seconds)
    end_time: number   -- When section ends (seconds)
}

-- Complete song data from API
export type SongData = {
    asset_id: string,  -- Roblox asset ID
    beat_grid: BeatGrid?,
    song_sections: {SongSection}?,
    num_bars: number?,
    asset_first_beat_offset: number?, -- Time to first beat
    asset_first_downbeat: number?,    -- Time to first downbeat
    asset_bpm: number?                -- Beats per minute
}

-- Beat data sent to clients
export type BeatData = {
    songId: string,
    beatGrid: BeatGrid,
    songSections: {SongSection}?,
    firstBeatOffset: number?,
    firstDownbeat: number?,
    bpm: number?,
    numBars: number?
}

-- Data sent to clients for beat/section updates
export type BeatUpdateData = {
    songId: string,
    beatGrid: BeatGrid,
    songSections: {SongSection}?,
    firstBeatOffset: number?,
    firstDownbeat: number?,
    bpm: number?,
    numBars: number?
}

return nil
