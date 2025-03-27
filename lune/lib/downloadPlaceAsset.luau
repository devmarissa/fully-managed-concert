local net = require("@lune/net")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")

return function(placeId)
    -- Try to read cookie from file first
    local cookie = nil
    if fs.isFile(".cookie") then
        cookie = fs.readFile(".cookie")
        -- Remove any whitespace/newlines
        cookie = string.gsub(cookie, "%s+", "")
        -- Format the cookie properly
        cookie = ".ROBLOSECURITY=" .. cookie
    end

    -- Fallback to roblox.getAuthCookie() if no file
    if not cookie or cookie == "PASTE_YOUR_COOKIE_HERE" then
        cookie = roblox.getAuthCookie()
    end
    
    assert(cookie, "Failed to get auth cookie")
    print("Using cookie:", cookie)

    -- Try direct download first
    local download = net.request({
        url = "https://assetdelivery.roblox.com/v1/asset/?id=" .. tostring(placeId),
        headers = {
            Cookie = cookie,
        },
    })

    if download.ok then
        return download.body
    end

    print("Direct download failed, trying v2 API...")
    print("Error:", download.body)

    -- If direct download fails, try the v2 API
    local result = net.request({
        url = "https://assetdelivery.roblox.com/v2/assetId/" .. tostring(placeId),
        headers = {
            Cookie = cookie,
        },
    })

    assert(result.ok, result.body)
    local responseTable = net.jsonDecode(result.body)
    
    -- Handle error response
    if responseTable.errors then
        error("API Error: " .. responseTable.errors[1].message)
    end
    
    assert(responseTable.locations and responseTable.locations[1], "No download location found in response")
    local location = responseTable.locations[1].location

    -- Then download from the location
    download = net.request({
        url = location,
        headers = {
            Cookie = cookie,
        },
    })

    assert(download.ok, download.body)
    return download.body
end
