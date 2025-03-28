--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local AudioScapeAPI = require(ReplicatedStorage.shared.AudioScapeAPI)
local Types = require(ReplicatedStorage.shared.Types)

type SongData = Types.SongData

local MusicController = {}
MusicController.__index = MusicController

function MusicController.new()
    local self = setmetatable({}, MusicController)
    
    -- Initialize sound group
    self.musicGroup = Instance.new("SoundGroup")
    self.musicGroup.Name = "MusicGroup"
    self.musicGroup.Parent = SoundService
    
    -- Create events
    self.events = {
        station = Instance.new("RemoteEvent"),
        beat = Instance.new("RemoteEvent"),
        song = Instance.new("RemoteEvent")
    } :: {[string]: RemoteEvent}
    
    self.events.station.Name = "StationEvent"
    self.events.beat.Name = "BeatUpdate"
    self.events.song.Name = "SongChange"
    
    for _, event in self.events do
        event.Parent = ReplicatedStorage
    end
    
    -- State
    self.currentSound = nil :: Sound?
    
    return self
end

function MusicController:printSongData(songData: SongData)
    if songData.beat_grid then
        local numBeats = #songData.beat_grid.beat_nums
        local songLength = songData.beat_grid.beat_times[numBeats]
        print("\n=== Song Info ===")
        print(string.format("Duration: %.2f seconds", songLength))
        print(string.format("Total Beats: %d", numBeats))
        print(string.format("Bars: %d", songData.num_bars or 0))
        
        -- Print first few beats as example
        print("\nFirst 4 beats:")
        for i = 1, 4 do
            print(string.format("Beat %d at %.2fs", 
                songData.beat_grid.beat_nums[i],
                songData.beat_grid.beat_times[i]))
        end
        
        -- Print sections if available
        if songData.song_sections then
            print("\nSong Sections:")
            for _, section in songData.song_sections do
                print(string.format("%s (%.2fs - %.2fs)",
                    section.name,
                    section.start_time,
                    section.end_time))
            end
        end
    else
        print("\n=== Song Info ===")
        print("No beat grid available")
    end
    print("===============\n")
end

function MusicController:playSong(songId: string)
    print("Playing song:", songId)
    
    -- Try to get beat timing data first
    local songData, err = AudioScapeAPI.getSongData(songId)
    if err then
        warn("Beat timing data not available:", err)
    else
        self:printSongData(songData)
    end
    
    -- Clean up previous sound if it exists
    if self.currentSound then
        local prevSound = self.currentSound 
        task.spawn(function()
            local sound: Sound = prevSound
            sound:Stop()
            sound:Destroy()
        end)
    end
    
    -- Create and play the sound
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. songId
    sound.SoundGroup = self.musicGroup
    sound.RollOffMode = Enum.RollOffMode.Inverse
    sound.Volume = 0.5  -- Set a reasonable volume
    sound.Parent = SoundService
    
    self.currentSound = sound
    sound:Play()
    
    -- Tell clients about the new song
    self.events.song:FireAllClients(songId)
    
    -- If we have beat data, send it to clients
    if songData and songData.beat_grid then
        self.events.beat:FireAllClients({
            songId = songId,
            beatGrid = songData.beat_grid,
            songSections = songData.song_sections,
            firstBeatOffset = songData.asset_first_beat_offset,
            firstDownbeat = songData.asset_first_downbeat,
            bpm = songData.asset_bpm,
            numBars = songData.num_bars
        })
    end
    
    -- Set up sound finished callback
    sound.Ended:Connect(function()
        task.wait(3)  -- Wait a bit between songs
        self:playSong("9046443555")  -- Play test song again
    end)
end

return MusicController
