--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
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
    self.currentBeat = nil
    self.lastBeatTime = nil
    self.beatGrid = nil
    self.bpm = nil
    self.currentSongData = nil
    self.currentSongId = nil
    
    -- Set up player join handler
    Players.PlayerAdded:Connect(function(player)
        if self.currentSongId and self.currentSongData then
            print("[MusicController] Sending current song data to new player:", player.Name)
            self.events.song:FireClient(player, {
                assetId = self.currentSongId,
                beatGrid = self.currentSongData.beat_grid,
                sections = self.currentSongData.song_sections,
                bpm = self.currentSongData.asset_bpm,
                firstBeatOffset = self.currentSongData.asset_first_beat_offset,
                firstDownbeat = self.currentSongData.asset_first_downbeat,
                numBars = self.currentSongData.num_bars
            })
        end
    end)
    
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

function MusicController:updateBeat()
    if not self.currentSound or not self.currentSound.IsPlaying then return end
    
    local currentTime = self.currentSound.TimePosition
    if not self.beatGrid then return end
    
    -- Find current beat
    local beatNum = nil
    local beatTime = nil
    local nextBeatTime = nil
    
    for i, time in ipairs(self.beatGrid.beat_times) do
        if currentTime < time then
            -- Found next beat
            nextBeatTime = time
            if i > 1 then
                beatNum = self.beatGrid.beat_nums[i-1]
                beatTime = self.beatGrid.beat_times[i-1]
            end
            break
        end
    end
    
    -- Update current beat if changed
    if beatNum and beatTime and (beatNum ~= self.currentBeat or not self.lastBeatTime or math.abs(beatTime - self.lastBeatTime) > 0.001) then
        self.currentBeat = beatNum
        self.lastBeatTime = beatTime
        
        -- Send beat update to clients
        self.events.beat:FireAllClients({
            beatNum = beatNum,
            beatTime = beatTime,
            nextBeatTime = nextBeatTime,
            currentTime = currentTime
        })
        
        print(string.format("[MusicController] Beat %d at %.3fs (Next: %.3fs)", beatNum, beatTime, nextBeatTime))
    end
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
    self.currentSongData = songData
    self.currentSongId = songId
    
    sound:Play()
    
    -- Tell clients about the new song with all data
    self.events.song:FireAllClients({
        assetId = songId,
        beatGrid = songData and songData.beat_grid,
        sections = songData and songData.song_sections,
        bpm = songData and songData.asset_bpm,
        firstBeatOffset = songData and songData.asset_first_beat_offset,
        firstDownbeat = songData and songData.asset_first_downbeat,
        numBars = songData and songData.num_bars
    })
    
    -- If we have beat data, send it to clients
    if songData and songData.beat_grid then
        -- Calculate BPM from beat grid if not provided
        local bpm = songData.asset_bpm
        if not bpm or bpm == 0 then
            -- Calculate BPM from first few beats
            local beatGrid = songData.beat_grid
            local numBeats = math.min(5, #beatGrid.beat_times)
            if numBeats >= 2 then
                local timeSpan = beatGrid.beat_times[numBeats] - beatGrid.beat_times[1]
                bpm = ((numBeats - 1) / timeSpan) * 60
            end
        end
        
        self.beatGrid = songData.beat_grid
        self.bpm = bpm
        
        self.events.beat:FireAllClients({
            songId = songId,
            beatGrid = songData.beat_grid,
            songSections = songData.song_sections,
            firstBeatOffset = songData.asset_first_beat_offset,
            firstDownbeat = songData.asset_first_downbeat,
            bpm = bpm,
            numBars = songData.num_bars
        })
        
        -- Start beat updates
        while self.currentSound and self.currentSound.IsPlaying do
            self:updateBeat()
            task.wait(0.01)
        end
    end
    
    -- Set up sound finished callback
    sound.Ended:Connect(function()
        task.wait(3)  -- Wait a bit between songs
        self:playSong("9046443555")  -- Play test song again
    end)
end

return MusicController
