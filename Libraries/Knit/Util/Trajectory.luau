--[[
    Trajectory.luau
    Utility for calculating parabolic trajectories (projectile motion).
    Used for fishing rod casts, thrown items, etc.
]]

local Workspace = game:GetService("Workspace")

local Trajectory = {}

-- Physics constants
Trajectory.DefaultGravity = Workspace.Gravity or 196.2
Trajectory.DefaultVelocity = 50 -- studs/sec initial velocity

--[=[
    Calculate points along a parabolic trajectory.
    @param origin Vector3 -- Starting position
    @param direction Vector3 -- Normalized direction to launch
    @param velocity number -- Initial velocity (studs/sec)
    @param gravity number -- Gravity acceleration
    @param maxTime number -- Maximum simulation time
    @param stepSize number -- Time step for each point
    @return { Vector3 } -- Array of positions along the trajectory
]=]
function Trajectory.CalculatePath(
    origin: Vector3,
    direction: Vector3,
    velocity: number?,
    gravity: number?,
    maxTime: number?,
    stepSize: number?
): { Vector3 }
    local v0 = velocity or Trajectory.DefaultVelocity
    local g = gravity or Trajectory.DefaultGravity
    local tMax = maxTime or 3
    local dt = stepSize or 0.05
    
    local points = {}
    local velocityVector = direction.Unit * v0
    
    local t = 0
    while t <= tMax do
        -- Position at time t: p = p0 + v0*t + 0.5*g*t^2
        local x = origin.X + velocityVector.X * t
        local y = origin.Y + velocityVector.Y * t - 0.5 * g * t * t
        local z = origin.Z + velocityVector.Z * t
        
        table.insert(points, Vector3.new(x, y, z))
        t += dt
    end
    
    return points
end

--[=[
    Raycast along a parabolic trajectory to find where it hits something.
    @param origin Vector3 -- Starting position
    @param direction Vector3 -- Normalized direction to launch
    @param velocity number -- Initial velocity
    @param gravity number -- Gravity acceleration
    @param raycastParams RaycastParams -- Raycast filter params
    @param maxTime number -- Maximum simulation time
    @return (RaycastResult?, Vector3, number) -- Hit result, landing position, flight time
]=]
function Trajectory.Raycast(
    origin: Vector3,
    direction: Vector3,
    velocity: number?,
    gravity: number?,
    raycastParams: RaycastParams?,
    maxTime: number?
): (RaycastResult?, Vector3, number)
    local v0 = velocity or Trajectory.DefaultVelocity
    local g = gravity or Trajectory.DefaultGravity
    local tMax = maxTime or 5
    local dt = 0.05 -- Time step
    
    local velocityVector = direction.Unit * v0
    local params = raycastParams or RaycastParams.new()
    
    local previousPoint = origin
    local t = dt -- Start from first step
    
    while t <= tMax do
        -- Calculate current position
        local x = origin.X + velocityVector.X * t
        local y = origin.Y + velocityVector.Y * t - 0.5 * g * t * t
        local z = origin.Z + velocityVector.Z * t
        local currentPoint = Vector3.new(x, y, z)
        
        -- Raycast between previous and current point
        local rayDirection = currentPoint - previousPoint
        local result = Workspace:Raycast(previousPoint, rayDirection, params)
        
        if result then
            return result, result.Position, t
        end
        
        -- Check if we've gone below the world
        if currentPoint.Y < -100 then
            return nil, currentPoint, t
        end
        
        previousPoint = currentPoint
        t += dt
    end
    
    -- No hit, return final position
    local finalX = origin.X + velocityVector.X * tMax
    local finalY = origin.Y + velocityVector.Y * tMax - 0.5 * g * tMax * tMax
    local finalZ = origin.Z + velocityVector.Z * tMax
    
    return nil, Vector3.new(finalX, finalY, finalZ), tMax
end

--[=[
    Calculate launch direction to hit a target position.
    Uses the physics formula for projectile motion.
    @param origin Vector3 -- Starting position
    @param target Vector3 -- Target position to hit
    @param velocity number -- Initial velocity
    @param gravity number -- Gravity acceleration
    @param preferHighArc boolean -- Prefer higher arc trajectory
    @return Vector3? -- Direction to launch, or nil if impossible
]=]
function Trajectory.CalculateLaunchDirection(
    origin: Vector3,
    target: Vector3,
    velocity: number?,
    gravity: number?,
    preferHighArc: boolean?
): Vector3?
    local v0 = velocity or Trajectory.DefaultVelocity
    local g = gravity or Trajectory.DefaultGravity
    
    local displacement = target - origin
    local horizontalDistance = Vector3.new(displacement.X, 0, displacement.Z).Magnitude
    local verticalDistance = displacement.Y
    
    -- Calculate launch angles (quadratic formula)
    local v2 = v0 * v0
    local v4 = v2 * v2
    local gx = g * horizontalDistance
    local gx2 = gx * horizontalDistance
    
    local discriminant = v4 - g * (gx2 + 2 * verticalDistance * v2)
    
    if discriminant < 0 then
        -- Target unreachable
        return nil
    end
    
    local sqrtDisc = math.sqrt(discriminant)
    
    -- Two possible angles
    local angle1 = math.atan2(v2 + sqrtDisc, gx)
    local angle2 = math.atan2(v2 - sqrtDisc, gx)
    
    local angle = preferHighArc and math.max(angle1, angle2) or math.min(angle1, angle2)
    
    -- Convert angle to 3D direction
    local horizontalDir = Vector3.new(displacement.X, 0, displacement.Z).Unit
    local direction = horizontalDir * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)
    
    return direction.Unit
end

--[=[
    Get launch direction based on camera look vector with a slight upward arc.
    @param lookVector Vector3 -- Camera look direction
    @param arcAngle number -- Upward arc angle in degrees (default 30)
    @return Vector3 -- Launch direction
]=]
function Trajectory.GetCastDirection(lookVector: Vector3, arcAngle: number?): Vector3
    local angle = math.rad(arcAngle or 30)
    
    -- Flatten the look vector to horizontal
    local horizontal = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
    
    -- Add upward component based on arc angle
    local direction = horizontal * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)
    
    return direction.Unit
end

return Trajectory
