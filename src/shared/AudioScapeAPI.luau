--!strict
--[[
    AudioScapeAPI.luau
    Interface to the AudioScape API for music timing data.
    
    Example Usage:
    ```lua
    local AudioScapeAPI = require(script.Parent.AudioScapeAPI)
    
    -- Get beat/section data for a song
    local songData, err = AudioScapeAPI.getSongData("1234567890")
    if err then
        warn("Failed to get song data:", err)
        return
    end
    
    -- Use the data
    print("Song BPM:", songData.asset_bpm)
    print("Total beats:", #songData.beat_grid.beat_nums)
    ```
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local Types = require(script.Parent.Types)

type SongData = Types.SongData

-- Constants
local API_URL = "https://api.audioscape.ai/boombox"
local GAME_NAME = MarketplaceService:GetProductInfo(game.PlaceId).Name

-- Get API key from secret in production, or use dev key in Studio
local API_KEY = if RunService:IsStudio() 
    then "4deRFtaaGO2o0VXeIvMrjaPKAvuI2PjhaoOOU4VO"
    else HttpService:GetSecret("audioscape_boombox_api_key")

local AudioScapeAPI = {}

--[[
    Send an HTTP request to the AudioScape API
    @param url: string - Full API endpoint URL
    @param method: string - HTTP method (GET/POST)
    @param data: table? - Optional data to send (for POST)
    @return success: boolean, response: table|string
]]
local function sendRequest(url: string, method: string, data: {[string]: any}?)
    local requestData = {
        Url = url,
        Method = method,
        Headers = {
            ["Content-Type"] = "application/json",
            ["X-API-Key"] = API_KEY
        }
    }
    
    if method == "POST" and data then
        requestData.Body = HttpService:JSONEncode(data)
    end
    
    local success, response = pcall(function()
        return HttpService:RequestAsync(requestData)
    end)
    
    if success then
        -- Debug output for development
        if RunService:IsStudio() then
            print("[AudioScapeAPI] Raw response from", url, ":", response.Body)
        end
        return true, HttpService:JSONDecode(response.Body)
    else
        warn("[AudioScapeAPI] Request failed for", url, ":", response)
        return false, response
    end
end

--[[
    Get beat and section timing data for a song
    @param songId: string - Roblox asset ID of the song
    @return songData: SongData, error: string?
]]
function AudioScapeAPI.getSongData(songId: string): (SongData, string?)
    local success, data = sendRequest(
        API_URL .. "/assets/data",
        "POST",
        {
            asset_id = songId,
            game_id = game.PlaceId,
            game_name = GAME_NAME
        }
    )
    
    if success and type(data) == "table" then
        if type(data) == "table" and #data > 0 then
            return data[1], nil
        end
        return data, nil
    end
    return {} :: SongData, "Failed to get song data for ID: " .. songId
end

return AudioScapeAPI
