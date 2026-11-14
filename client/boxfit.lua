-- ============================================
-- whip_autos — box geometry
-- ============================================
-- Pure maths that lets one framing fit every car: where to stand is a bearing from the car's nose and
-- a multiple of the distance that fills the frame with it, where to look is a fraction of its bounding
-- box. client/camera.lua resolves every framing through this.

BoxFit = {}

local sin, cos, tan, rad, abs = math.sin, math.cos, math.tan, math.rad, math.abs

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

local function cross(a, b)
    return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local function norm(v)
    local l = #(v)
    if l < 0.0001 then return vector3(0.0, 0.0, 0.0) end
    return v / l
end

-- ============================================
-- The box
-- ============================================

--- The eight corners of a vehicle's model box in world space (from the game's own transform, so
--- heading and tilt are in them), plus its centre and raw dimensions.
---@param veh number
---@return table pts, vector3 centre, vector3 minD, vector3 maxD
function BoxFit.corners(veh)
    local minD, maxD = GetModelDimensions(GetEntityModel(veh))

    local pts, sum = {}, vector3(0.0, 0.0, 0.0)
    for _, x in ipairs({ minD.x, maxD.x }) do
        for _, y in ipairs({ minD.y, maxD.y }) do
            for _, z in ipairs({ minD.z, maxD.z }) do
                local p = GetOffsetFromEntityInWorldCoords(veh, x, y, z)
                pts[#pts + 1] = p
                sum = sum + p
            end
        end
    end

    return pts, sum / 8.0, minD, maxD
end

--- Half-angle tangents of the view, vertical and horizontal, at the live screen's aspect.
---@param fov number
---@return number tanV, number tanH
function BoxFit.tangents(fov)
    local sw, sh = GetActiveScreenResolution()
    local aspect = (sh and sh > 0) and (sw / sh) or (16.0 / 9.0)
    local tanV = tan(rad(fov * 0.5))
    return tanV, tanV * aspect
end

-- ============================================
-- Where the camera stands
-- ============================================

--- The camera's axes for a framing, from the car's heading and the framing's yaw and pitch (not from
--- the live camera, so the same framing always gives the same distance).
---@param vehHeading number
---@param yaw number    bearing from the vehicle's nose
---@param pitch number  degrees above the vehicle's plane
---@return vector3 right, vector3 up, vector3 fwd
function BoxFit.basis(vehHeading, yaw, pitch)
    local h, a = rad(vehHeading + yaw), rad(pitch)
    local ch = cos(a)

    -- Out from the aim point to the camera; heading 0 faces +Y.
    local out = vector3(sin(h) * ch, -cos(h) * ch, sin(a))

    local fwd   = -out
    local right = norm(cross(fwd, vector3(0.0, 0.0, 1.0)))
    return right, cross(right, fwd), fwd
end

--- The distance at which the whole box just fills the frame: the unit every `distRatio` is measured
--- in. Measured from the box centre, so every framing of one car divides by the same number.
---@param pts table      world-space corners from BoxFit.corners
---@param centre vector3 world-space box centre
---@param fov number
---@return number
function BoxFit.fitDistance(pts, centre, fov, right, up, fwd)
    local tanV, tanH = BoxFit.tangents(fov)

    local d = 0.0
    for _, p in ipairs(pts) do
        local rel = p - centre
        local u, v, f = dot(rel, right), dot(rel, up), dot(rel, fwd)

        local needV = abs(v) / tanV - f
        local needH = abs(u) / tanH - f
        if needV > d then d = needV end
        if needH > d then d = needH end
    end

    return math.max(d, 1.0)
end

-- ============================================
-- Where the camera looks
-- ============================================
-- The aim point is box-normalised: -1..1 per axis, 0,0,0 the box centre, +y the nose, +z the roof.

--- Box-normalised aim to a local offset in metres from the vehicle's origin.
---@param aim table      { x, y, z }, each roughly -1..1
---@param minD vector3
---@param maxD vector3
---@return number right, number fwd, number up
function BoxFit.aimToLocal(aim, minD, maxD)
    aim = aim or {}

    local cx, cy, cz = (minD.x + maxD.x) * 0.5, (minD.y + maxD.y) * 0.5, (minD.z + maxD.z) * 0.5
    local hx, hy, hz = (maxD.x - minD.x) * 0.5, (maxD.y - minD.y) * 0.5, (maxD.z - minD.z) * 0.5

    return cx + (aim.x or 0.0) * hx,
           cy + (aim.y or 0.0) * hy,
           cz + (aim.z or 0.0) * hz
end

--- The inverse. A zero-size box (a model that failed to stream) reads as 0.
---@return table aim
function BoxFit.localToAim(right, fwd, up, minD, maxD)
    local cx, cy, cz = (minD.x + maxD.x) * 0.5, (minD.y + maxD.y) * 0.5, (minD.z + maxD.z) * 0.5
    local hx, hy, hz = (maxD.x - minD.x) * 0.5, (maxD.y - minD.y) * 0.5, (maxD.z - minD.z) * 0.5

    local function over(v, half)
        if half < 0.001 then return 0.0 end
        return v / half
    end

    return {
        x = over(right - cx, hx),
        y = over(fwd   - cy, hy),
        z = over(up    - cz, hz),
    }
end
