--[[
    SyncHandler Module
    Handles animation synchronization between players
]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Types
type AnimationInfo = {["Animator"]: Animator, ["AnimationTracks"]: {AnimationTrack}}
type BeatData = {
    beatNum: number,
    beatTime: number,
    bpm: number?
}

-- Module
local SyncHandler = {}
SyncHandler.__index = SyncHandler

-- Private variables
local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local ClientAnimators: {[Player]: AnimationInfo} = {}
local Connections: {[string]: RBXScriptConnection} = {}
local ActiveAnimationTracks: {[Animator]: AnimationTrack} = {}
local currentLocalAnimation: AnimationTrack = nil

local BeatSignal = Instance.new("BindableEvent")

local function RegisterPlayer(Player: Player)
    if Connections[tostring(Player.UserId)] then
        local Connection = Connections[tostring(Player.UserId)]
        Connections[tostring(Player.UserId)] = nil
        Connection:Disconnect()
    end

    local currentCharacter = Player.Character or Player.CharacterAdded:Wait()
    if not currentCharacter then return end

    local Animator: Animator = Player.Character:FindFirstChild("Animator", true)
    if not Animator then return end

    ClientAnimators[Player] = {}
    local CurrentClientAnimator = ClientAnimators[Player]
    CurrentClientAnimator.Animator = Animator

    Connections[tostring(Player.UserId)] = Animator.AnimationPlayed:Connect(function(animationTrack: AnimationTrack)
        CurrentClientAnimator.AnimationTracks = Animator:GetPlayingAnimationTracks()

        if Player == LocalPlayer then
            currentLocalAnimation = animationTrack

            -- Fire beat event when local animation changes
            BeatSignal:Fire({
                beatNum = 1, -- Reset to beat 1 when animation changes
                beatTime = 0,
                bpm = nil -- Let DanceController handle BPM
            })

            for OtherPlayer, AnimationInfo: AnimationInfo in pairs(ClientAnimators) do
                if OtherPlayer == LocalPlayer then continue end

                local otherAnimator = AnimationInfo.Animator

                for _, otherAnimationTrack in pairs(otherAnimator:GetPlayingAnimationTracks()) do
                    local localAnimationId = currentLocalAnimation.Animation.AnimationId
                    local otherAnimationId = otherAnimationTrack.Animation.AnimationId
                    
                    if currentLocalAnimation and localAnimationId == otherAnimationId and otherAnimationTrack.IsPlaying then
                        currentLocalAnimation.TimePosition = otherAnimationTrack.TimePosition
                        break
                    end
                end
            end
        else    
            local localAnimationId = currentLocalAnimation and currentLocalAnimation.Animation.AnimationId
            local otherAnimationId = animationTrack.Animation.AnimationId

            ActiveAnimationTracks[Animator] = animationTrack

            if currentLocalAnimation and localAnimationId == otherAnimationId then
                animationTrack.TimePosition = currentLocalAnimation.TimePosition
            end
        end
    end)
end

function SyncHandler:init()
    print("[SyncHandler] Initializing...")
    
    -- Register all current players
    for _, Player in pairs(Players:GetPlayers()) do
        RegisterPlayer(Player)
    end
    
    -- Set up player added handling
    Players.PlayerAdded:Connect(function(player: Player)
        player.CharacterAdded:Connect(function()
            RegisterPlayer(player)
        end)
    end)
    
    -- Set up player removal handling
    Players.PlayerRemoving:Connect(function(player: Player)
        if Connections[tostring(player.UserId)] then
            Connections[tostring(player.UserId)]:Disconnect()
            Connections[tostring(player.UserId)] = nil
        end
        ClientAnimators[player] = nil
    end)
    
    print("[SyncHandler] Initialized")
end

function SyncHandler:destroy()
    -- Clean up all connections
    for _, connection in pairs(Connections) do
        connection:Disconnect()
    end
    Connections = {}
    ClientAnimators = {}
    ActiveAnimationTracks = {}
    currentLocalAnimation = nil
end

function SyncHandler:onBeatUpdate(beatData)
    if not beatData then return end
    
    print(string.format("[SyncHandler] Beat update: Beat %d at %.3fs (BPM: %.1f)", 
        beatData.beatNum or 0,
        beatData.beatTime or 0,
        beatData.bpm or 0
    ))
    
    -- Forward beat update to all handlers
    for _, handler in ipairs(self.beatHandlers) do
        task.spawn(function()
            handler(beatData)
        end)
    end
end

function SyncHandler:onTimeUpdate(timeData)
    if not timeData then return end
    
    print(string.format("[SyncHandler] Time update: %.3fs", timeData.currentTime or 0))
    
    -- Forward time update to all handlers
    for _, handler in ipairs(self.timeHandlers) do
        task.spawn(function()
            handler(timeData)
        end)
    end
end

function SyncHandler:onBeat()
    return BeatSignal.Event
end

return SyncHandler
