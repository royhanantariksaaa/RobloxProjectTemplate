--[[
    Tween.luau
    Centralized Tween Scheduler using Structure of Arrays (SoA) for performance.
    Can be used by both UI and non-UI code.
    
    Features:
    - Custom lerping for various types (number, UDim2, Vector2, Vector3, Color3, UDim)
    - Keyframe animations
    - Marker callbacks at specific times
    - Automatic cancellation of conflicting tweens
    - Batch tweening
    - Looping/repeating support (RepeatCount, Reverses from TweenInfo)
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Tween = {}

-- Centralized Tween Scheduler (SoA / DoD)
local TweenIds = {}
local TweenInstances = {}
local TweenStartTimes = {}
local TweenDurations = {}
local TweenEasingStyles = {}
local TweenEasingDirections = {}
local TweenGoals = {}
local TweenStartValues = {}
local TweenCallbacks = {}
local TweenMarkers = {} -- { [time]: callback }
local TweenMarkersFired = {} -- { [time]: boolean }
-- Looping support
local TweenRepeatCounts = {} -- -1 = infinite, 0 = no repeat, N = N more times
local TweenReverses = {} -- boolean: reverse on each repeat
local TweenCurrentRepeats = {} -- How many repeats done so far
local TweenIsReversing = {} -- Currently in reverse phase
local NextTweenId = 1

local TweenConnection = nil

-- Lerp helper for various types
local function Lerp(a: any, b: any, t: number)
    if typeof(a) == "number" then
        return a + (b - a) * t
    elseif typeof(a) == "UDim2" then
        return a:Lerp(b, t)
    elseif typeof(a) == "Vector2" then
        return a:Lerp(b, t)
    elseif typeof(a) == "Vector3" then
        return a:Lerp(b, t)
    elseif typeof(a) == "Color3" then
        return a:Lerp(b, t)
    elseif typeof(a) == "CFrame" then
        return a:Lerp(b, t)
    elseif typeof(a) == "UDim" then
        return UDim.new(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t)
    end
    return a
end

-- Helper to remove at index (O(n) but maintains order)
local function RemoveTweenAtIndex(i: number)
    table.remove(TweenIds, i)
    table.remove(TweenInstances, i)
    table.remove(TweenStartTimes, i)
    table.remove(TweenDurations, i)
    table.remove(TweenEasingStyles, i)
    table.remove(TweenEasingDirections, i)
    table.remove(TweenGoals, i)
    table.remove(TweenStartValues, i)
    table.remove(TweenCallbacks, i)
    table.remove(TweenMarkers, i)
    table.remove(TweenMarkersFired, i)
    table.remove(TweenRepeatCounts, i)
    table.remove(TweenReverses, i)
    table.remove(TweenCurrentRepeats, i)
    table.remove(TweenIsReversing, i)
end

-- Helper to sample keyframes
local function SampleKeyframes(keyframes: {Frames: {{Time: number, Value: any}}}, t: number, startValue: any)
    local frames = keyframes.Frames
    
    -- Handle edge cases
    if t <= 0 then
        if frames[1].Time == 0 then return frames[1].Value end
        return startValue
    end
    if t >= 1 then
        return frames[#frames].Value
    end
    
    -- Find segment
    local p1 = {Time = 0, Value = startValue}
    local p2 = frames[1]
    
    for i = 1, #frames do
        if frames[i].Time > t then
            p2 = frames[i]
            break
        end
        p1 = frames[i]
    end
    
    -- Interpolate
    local segmentT = (t - p1.Time) / (p2.Time - p1.Time)
    return Lerp(p1.Value, p2.Value, segmentT)
end

--[=[
    Creates a keyframe animation sequence.
    @param frames {{Time: number, Value: any}} -- Array of keyframes with Time (0-1) and Value
    @return table -- Keyframes object for use in Tween goals
    
    Example:
    ```lua
    local tween = Tween.Tween(instance, TweenInfo.new(1), {
        Position = Tween.Keyframes({
            { Time = 0, Value = UDim2.fromScale(0, 0) },
            { Time = 0.5, Value = UDim2.fromScale(0.5, 0.5) },
            { Time = 1, Value = UDim2.fromScale(1, 1) },
        })
    })
    ```
]=]
function Tween.Keyframes(frames: {{Time: number, Value: any}})
    -- Sort by time to be safe
    table.sort(frames, function(a, b) return a.Time < b.Time end)
    return { _IsKeyframes = true, Frames = frames }
end

local function UpdateTweens()
    local now = os.clock()
    -- Iterate backwards to safely remove
    for i = #TweenIds, 1, -1 do
        local instance = TweenInstances[i]
        
        -- Safety check
        if not instance or not instance.Parent then
            RemoveTweenAtIndex(i)
            continue
        end

        local startTime = TweenStartTimes[i]
        local duration = TweenDurations[i]
        local elapsed = now - startTime
        local alpha = math.clamp(elapsed / duration, 0, 1) -- 0 to 1
        
        -- Handle reverse direction
        local isReversing = TweenIsReversing[i]
        local effectiveAlpha = isReversing and (1 - alpha) or alpha
        
        local curvedAlpha = TweenService:GetValue(effectiveAlpha, TweenEasingStyles[i], TweenEasingDirections[i])
        
        -- Apply properties
        local goals = TweenGoals[i]
        local startVals = TweenStartValues[i]
        
        for k, goal in pairs(goals) do
             if type(goal) == "table" and goal._IsKeyframes then
                 (instance :: any)[k] = SampleKeyframes(goal, curvedAlpha, startVals[k])
             else
                 (instance :: any)[k] = Lerp(startVals[k], goal, curvedAlpha)
             end
        end
        
        -- Check Markers (only in forward direction, first cycle)
        local markers = TweenMarkers[i]
        if markers and not isReversing and TweenCurrentRepeats[i] == 0 then
            local fired = TweenMarkersFired[i]
            for time, callback in pairs(markers) do
                if type(time) == "number" and not fired[time] and elapsed >= time then
                    fired[time] = true
                    task.spawn(callback)
                end
            end
        end
        
        if alpha >= 1 then
            local repeatCount = TweenRepeatCounts[i]
            local reverses = TweenReverses[i]
            local currentRepeats = TweenCurrentRepeats[i]
            
            -- Check if we should continue looping
            local shouldContinue = false
            
            if repeatCount == -1 then
                -- Infinite loop
                shouldContinue = true
            elseif currentRepeats < repeatCount then
                -- More repeats to do
                shouldContinue = true
            end
            
            if shouldContinue then
                -- Reset for next cycle
                TweenStartTimes[i] = now
                TweenCurrentRepeats[i] = currentRepeats + 1
                
                -- Toggle reverse state if reverses is enabled
                if reverses then
                    TweenIsReversing[i] = not isReversing
                end
                
                -- Reset markers for next cycle (if not reversing)
                if TweenMarkersFired[i] and not reverses then
                    TweenMarkersFired[i] = {}
                end
            else
                -- Tween complete - fire pending markers and callback
                if markers and not isReversing then
                    local fired = TweenMarkersFired[i]
                    for time, callback in pairs(markers) do
                        if type(time) == "number" and not fired[time] and time <= (duration + 0.01) then
                            fired[time] = true
                            task.spawn(callback)
                        end
                    end
                end

                local callback = TweenCallbacks[i]
                RemoveTweenAtIndex(i)
                
                if callback then 
                    local success, err = pcall(callback)
                    if not success then warn("Tween callback error:", err) end
                end
            end
        end
    end
    
    if #TweenIds == 0 and TweenConnection then
        (TweenConnection :: RBXScriptConnection):Disconnect()
        TweenConnection = nil
    end
end

--[=[
    Creates a custom tween with the centralized scheduler.
    @param instance Instance -- The instance to tween
    @param tweenInfo TweenInfo -- The tween timing information
    @param goals {[string]: any} -- Property goals to tween to
    @param callback (() -> ())? -- Optional callback when tween completes
    @return TweenController -- Controller with Cancel() and OnMarker() methods
    
    Example:
    ```lua
    local controller = Tween.Tween(frame, TweenInfo.new(0.5), {
        Position = UDim2.fromScale(1, 0),
        BackgroundTransparency = 1,
    }, function()
        print("Tween complete!")
    end)
    
    -- Cancel if needed
    controller.Cancel()
    
    -- Or add markers
    controller.OnMarker(0.25, function()
        print("25% through the tween!")
    end)
    ```
]=]
function Tween.Tween(instance: Instance, moveInfo: TweenInfo, goals: {[string]: any}, callback: (() -> ())?)
    local startValues = {}
    for k, _ in pairs(goals) do
        startValues[k] = (instance :: any)[k]
    end
    
    -- Cancel any existing tweens for this instance ONLY IF they share properties
    for i = #TweenIds, 1, -1 do
        if (TweenInstances[i] :: Instance) == instance then
            local existingGoals = TweenGoals[i]
            local overlaps = false
            for k, _ in pairs(goals) do
                if existingGoals[k] ~= nil then
                    overlaps = true
                    break
                end
            end
            
            if overlaps then
                RemoveTweenAtIndex(i)
            end
        end
    end

    local id = NextTweenId
    NextTweenId += 1
    
    table.insert(TweenIds, id)
    table.insert(TweenInstances, instance)
    table.insert(TweenStartTimes, os.clock())
    table.insert(TweenDurations, moveInfo.Time)
    table.insert(TweenEasingStyles, moveInfo.EasingStyle)
    table.insert(TweenEasingDirections, moveInfo.EasingDirection)
    table.insert(TweenGoals, goals)
    table.insert(TweenStartValues, startValues)
    table.insert(TweenCallbacks, callback or false :: any)
    table.insert(TweenMarkers, false :: any)
    table.insert(TweenMarkersFired, false :: any)
    -- Looping support from TweenInfo
    table.insert(TweenRepeatCounts, moveInfo.RepeatCount)
    table.insert(TweenReverses, moveInfo.Reverses)
    table.insert(TweenCurrentRepeats, 0)
    table.insert(TweenIsReversing, false)
    
    if not TweenConnection then
        TweenConnection = RunService.Heartbeat:Connect(UpdateTweens)
    end
    
    local controller = {}
    
    function controller.Cancel()
        local index = table.find(TweenIds, id)
        if index then
            RemoveTweenAtIndex(index)
        end
        if #TweenIds == 0 and TweenConnection then
            TweenConnection:Disconnect()
            TweenConnection = nil
        end
    end
    
    function controller.OnMarker(time: number, markerCallback: () -> ())
        local index = table.find(TweenIds, id)
        if index then
            local markers = TweenMarkers[index]
            if not markers then
                markers = {}
                TweenMarkers[index] = markers
                TweenMarkersFired[index] = {}
            end
            markers[time] = markerCallback
        end
        return controller -- Chainable
    end
    
    return controller
end

--[=[
    Creates multiple tweens at once.
    @param tweenDefs { { instance: Instance, info: TweenInfo, goals: {[string]: any} } }
    @return BatchController -- Controller with Cancel() method for all tweens
]=]
function Tween.BatchTween(tweenDefs: { { instance: Instance, info: TweenInfo, goals: {[string]: any} } })
    local cancellables = {}
    for _, def in ipairs(tweenDefs) do
         table.insert(cancellables, Tween.Tween(def.instance, def.info, def.goals))
    end
    return {
        Cancel = function()
            for _, t in ipairs(cancellables) do t.Cancel() end
        end
    }
end

-- Export the Lerp function for external use
Tween.Lerp = Lerp

return Tween
