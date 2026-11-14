-- ============================================
-- whip_autos — showroom camera
-- ============================================
-- An orbit camera around the car, adapted from nfsmw_camera's showcase mover and kept self-contained.
-- session.lua starts and stops it and says when the page shares the mouse; framings come from
-- Config.Camera.framings, fitted to each car through client/boxfit.lua.

Cam = {}

local abs, sqrt, deg, rad = math.abs, math.sqrt, math.deg, math.rad
local sin, cos, asin, exp = math.sin, math.cos, math.asin, math.exp
local atan2 = math.atan   -- Lua 5.3+ math.atan(y, x) is atan2

-- ---- maths ----------------------------------------------------------------

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- Whichever of b, b+360 or b-360 is closest to a, so yaw never turns the long way round.
local function nearestAngle(a, b)
    local d0, bUp, bDn = abs(a - b), b + 360.0, b - 360.0
    local d1, d2 = abs(a - bUp), abs(a - bDn)
    if d0 <= d1 and d0 <= d2 then return b end
    if d1 <= d2 then return bUp end
    return bDn
end

--- Frame-rate independent exponential approach.
local function damp(current, target, rate, dt)
    return target + (current - target) * exp(-rate * dt)
end

local function dampAngle(current, target, rate, dt)
    local t = nearestAngle(current, target)
    local v = t + (current - t) * exp(-rate * dt)
    return (v + 180.0) % 360.0 - 180.0
end

--- Folds an angle into (-180, 180]. Target yaw must stay in the same range as the damped yaw, or
--- nearestAngle cannot bridge them and the camera flips.
local function wrap180(a)
    return (a + 180.0) % 360.0 - 180.0
end

local function lerp(a, b, t) return a + (b - a) * t end

local function normalize(x, y, z)
    local l = sqrt(x * x + y * y + z * z)
    if l < 1e-6 then return 0.0, 0.0, 0.0 end
    return x / l, y / l, z / l
end

--- Camera pitch and yaw that look down a direction.
local function rotFromDir(dx, dy, dz)
    local nx, ny, nz = normalize(dx, dy, dz)
    return deg(asin(clamp(nz, -1.0, 1.0))), deg(atan2(-nx, ny))
end

--- Offsets a world position by a local (right, forward, up) triple.
local function localToWorld(px, py, pz, heading, right, fwd, up)
    local h = rad(heading)
    local fx, fy = -sin(h), cos(h)
    local rx, ry =  cos(h), sin(h)
    return px + rx * right + fx * fwd, py + ry * right + fy * fwd, pz + up
end

-- ---- state ----------------------------------------------------------------

local handle       = nil     -- the GTA cam
local active       = false
local target       = nil     -- the vehicle being framed
local inputEnabled = false   -- listening to the mouse this frame

--- Does the page share the mouse? Then the camera only listens while the orbit button is held.
local mouseShared = false

--- Told when the camera starts or stops listening (the page hides its cursor).
local onInputChange = nil

-- Current and target framing; every change eases from one to the other.
local yaw,  pitch,  dist,  fov  = 0.0, 0.0, 6.0, 40.0
local tYaw, tPitch, tDist, tFov = 0.0, 0.0, 6.0, 40.0

-- The point the camera orbits, in the car's own axes (metres from its origin), from the framing's aim.
local aimR,  aimF,  aimU  = 0.0, 0.0, 0.8
local tAimR, tAimF, tAimU = 0.0, 0.0, 0.8

-- A rotation nudge off that point, for composition.
local aimP,  aimY  = 0.0, 0.0
local tAimP, tAimY = 0.0, 0.0

-- How far the car sits right of screen centre, as a share of the width (the picker column; Cam.setScreenShift).
local shift, tShift = 0.0, 0.0

--- The distance that just fills the frame with this car: the unit of distRatio and the zoom limits.
--- Recomputed when the framing changes, not per frame.
local fitDist = 6.0

local idle      = 0.0     -- seconds since the player last moved it, for the turntable
local enterT    = 1.0     -- entry blend progress

-- Output pose, kept between frames so entering blends from where the camera already was.
local px, py, pz, pPitch, pYaw, pFov = 0.0, 0.0, 0.0, 0.0, 0.0, 40.0
local seeded = false

--- The loop runs from Cam.start to Cam.stop; each start bumps the turn so an old loop ends.
local loopTurn = 0
local runLoop   -- defined at the bottom

--- The framing a shot name stands for.
local function resolveFraming(name)
    return Config.Camera.framings[name]
end

--- Points the rig at a framing table, resolving everything that depends on the car's size.
local function applyFramingTable(f)
    if not f then return end

    local C = Config.Camera
    tYaw   = wrap180(f.yaw or 0.0)
    tPitch = clamp(f.pitch or 0.0, C.pitchMin, C.pitchMax)
    tFov   = f.fov or 40.0
    tAimP  = f.aimPitch or 0.0
    tAimY  = f.aimYaw or 0.0

    if target and DoesEntityExist(target) then
        local pts, centre, minD, maxD = BoxFit.corners(target)
        tAimR, tAimF, tAimU = BoxFit.aimToLocal(f.aim, minD, maxD)

        local right, up, fwd = BoxFit.basis(GetEntityHeading(target), tYaw, tPitch)
        fitDist = BoxFit.fitDistance(pts, centre, tFov, right, up, fwd)
        tDist   = math.max(fitDist * (f.distRatio or 1.0), 0.6)
    end

    idle = 0.0
end

--- The named framing the rig is on, or nil when stopped.
local framingName = nil

--- The standard camera (Cam.setStandard): the default shot only, moved by nobody but the player.
local standard = false

local function shiftOpen() return tShift > 0.0005 or tShift < -0.0005 end

--- On the default shot, opening the picker column turns the camera to Config.Camera.shiftedYaw.
--- Closing the column leaves the camera where it is. Not with the standard camera.
local function applyShiftYaw()
    local C = Config.Camera
    if standard then return end
    if not C.shiftedYaw or framingName ~= C.default or not shiftOpen() then return end
    tYaw = wrap180(C.shiftedYaw)
end

local function applyFraming(name)
    framingName = name
    applyFramingTable(resolveFraming(name))
    -- Arriving on the default shot with the column already open.
    if shiftOpen() then applyShiftYaw() end
end

-- On a pad the right stick turns the camera all the time (ui.lua shares no mouse then), at a rate scaled
-- by the frame (a stick is held, not moved like a mouse). The triggers zoom (LT out, RT in), smoothly.
local PAD_YAW, PAD_PITCH = 150.0, 75.0   -- degrees a second at a full push
local PAD_DEAD   = 0.12                  -- a stick resting short of this is not pushed
local PAD_ZOOM   = 1.4                   -- fit distances a second at a full pull
local PAD_LT, PAD_RT = { 207, 25, 72 }, { 208, 24, 71 }   -- each trigger's controls (frontend, foot, car)

--- One trigger, 0-1: the most any of its controls reads.
local function trigger(controls)
    local v = 0.0
    for i = 1, #controls do
        local n = GetDisabledControlNormal(0, controls[i])
        if n > v then v = n end
    end
    return v
end

--- This frame's look input, or nothing while the camera is not listening. Read with the disabled
--- reader because the shop blocks look (BlockControls) so the gameplay camera underneath stays still.
---@param pad boolean  a controller is the device (the stick is a rate, scaled by dt)
---@param dt number
local function lookInput(pad, dt)
    if not inputEnabled then return 0.0, 0.0, false end

    local C  = Config.Camera
    local lr = GetDisabledControlNormal(0, 1)
    local ud = GetDisabledControlNormal(0, 2)
    if abs(lr) + abs(ud) <= (pad and PAD_DEAD or C.deadzone) then return 0.0, 0.0, false end

    local sens = C.sensitivity or 1.0
    local sx   = C.invertX and -1.0 or 1.0
    local sy   = C.invertY and -1.0 or 1.0

    -- Yaw is negated: GTA headings grow counter-clockwise.
    if pad then
        return -lr * PAD_YAW * dt * sens * sx,
                ud * PAD_PITCH * dt * sens * sy,
                true
    end
    -- Mouse look is already per frame, so not scaled by dt.
    return -lr * C.yawSpeed   * sens * sx,
            ud * C.pitchSpeed * sens * sy,
            true
end

-- ---- public ---------------------------------------------------------------

function Cam.isActive() return active end
function Cam.target()   return target end

--- Shared with the page, the camera only listens while the orbit button is held; otherwise always.
---@param on boolean
function Cam.setMouseShared(on)
    mouseShared = on and true or false
end

--- `fn(listening)` is called whenever the camera starts or stops listening to the mouse.
---@param fn function
function Cam.onInputChange(fn)
    onInputChange = fn
end

--- Frames this vehicle, blending in from the gameplay camera.
function Cam.start(veh, framing)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end

    target, active = veh, true
    applyFraming(framing or Config.Camera.default)

    -- The framing snaps; only the camera pose blends.
    yaw, pitch, dist, fov = tYaw, tPitch, tDist, tFov
    aimR, aimF, aimU = tAimR, tAimF, tAimU
    aimP, aimY = tAimP, tAimY

    local p, r, f = GetGameplayCamCoord(), GetGameplayCamRot(2), GetGameplayCamFov()
    px, py, pz, pPitch, pYaw, pFov = p.x, p.y, p.z, r.x, r.z, f
    seeded, enterT = true, 0.0

    -- Created at the gameplay camera's pose (a plain CreateCam starts at 0,0,0 and would fly in from
    -- the map's middle), so the 0 ms handover is invisible and the loop does the swing.
    if not handle then
        handle = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
            p.x, p.y, p.z, r.x, r.y, r.z, f, true, 2)
    else
        SetCamCoord(handle, p.x, p.y, p.z)
        SetCamRot(handle, r.x, r.y, r.z, 2)
        SetCamFov(handle, f)
    end

    SetCamActive(handle, true)
    RenderScriptCams(true, false, 0, true, true)

    loopTurn = loopTurn + 1
    local turn = loopTurn
    CreateThread(function() runLoop(turn) end)
    return true
end

--- Hands the view back to the game.
function Cam.stop()
    active, target, inputEnabled = false, nil, false
    shift, tShift = 0.0, 0.0
    framingName = nil

    if handle then
        RenderScriptCams(false, true, 500, true, true)
        SetCamActive(handle, false)
        DestroyCam(handle, false)
        handle = nil
    end
end

--- Switches to a named framing. The shot already in use does nothing, so a hand-turned camera is kept.
--- With the standard camera every framing is the default one.
function Cam.setFraming(name)
    if not active then return end
    if standard then name = Config.Camera.default end
    if name == framingName then return end
    applyFraming(name)
end

--- The standard camera on or off (the player's Camera button, or Config.Camera.followParts). On: the camera
--- goes back to the default shot and stays there, moved only by the player's own turning and zooming; parts
--- no longer frame it and the picker column no longer swings it. Off: the next framing asked for is used
--- (session.lua frames what is open again).
---@param on boolean
function Cam.setStandard(on)
    standard = on and true or false
    if standard and active then Cam.setFraming(Config.Camera.default) end
end

function Cam.isStandard() return standard end

-- A shot edited in /whip while it is on screen is framed again.
Whip.onConfigChanged('Camera.framings', function()
    if active and framingName then applyFraming(framingName) end
end)

--- Moves the car sideways on screen by a share of its width (0.12 = 12% right of centre, 0 = back).
--- The picker column asks for it so the car sits beside the column. A turn of the view, not the camera.
---@param s number
function Cam.setScreenShift(s)
    local wasOpen = shiftOpen()
    tShift = clamp(tonumber(s) or 0.0, -0.4, 0.4)
    -- Only the column opening turns the default shot (applyShiftYaw); a resize or closing does not.
    if shiftOpen() and not wasOpen then applyShiftYaw() end
end

-- ---- the loop -------------------------------------------------------------

--- Every frame while the camera is up. Waits out a car that has briefly gone; the session ends the
--- visit if it does not come back.
---@param turn number
runLoop = function(turn)
    while active and turn == loopTurn do
        if not target or not DoesEntityExist(target) then
            Wait(250)
            goto continue
        end

        do
            local C  = Config.Camera
            local dt = GetFrameTime()
            if dt <= 0.0 then dt = 1.0 / 60.0 end

            -- Who has the mouse: control 25 (right mouse / left trigger), read disabled because the
            -- shop blocks it.
            local listening = (not mouseShared) or IsDisabledControlPressed(0, 25)
            if listening ~= inputEnabled then
                inputEnabled = listening
                if listening then idle = 0.0 end
                if onInputChange then onInputChange(listening) end
            end

            local pad = not IsUsingKeyboard(0)
            local dYaw, dPitch, moved = lookInput(pad, dt)
            if moved then
                tYaw   = tYaw + dYaw
                tPitch = clamp(tPitch + dPitch, C.pitchMin, C.pitchMax)
            end

            -- A pad's triggers zoom (LT out, RT in) — not while Engine Swap lets the throttle (RT) rev
            -- the held car (Session.revving).
            if pad and inputEnabled and not (Session and Session.revving and Session.revving()) then
                local pull = trigger(PAD_LT) - trigger(PAD_RT)
                if abs(pull) > 0.08 then
                    tDist = clamp(tDist + pull * fitDist * PAD_ZOOM * dt, fitDist * C.zoomMin, fitDist * C.zoomMax)
                    moved = true
                end
            end

            -- The wheel zooms, in multiples of fitDist, only while the camera has the mouse. 16/17 are
            -- the wheel without pad bindings (14/15 are also the pad triggers); 241/242 are the cursor
            -- wheel. Read disabled: the shop and whip_core both block the weapon-wheel pair.
            if inputEnabled then
                local step = fitDist * C.zoomStep
                local lo, hi = fitDist * C.zoomMin, fitDist * C.zoomMax
                if IsDisabledControlJustPressed(0, 17) or IsDisabledControlJustPressed(0, 241) then
                    tDist = clamp(tDist - step, lo, hi); moved = true
                elseif IsDisabledControlJustPressed(0, 16) or IsDisabledControlJustPressed(0, 242) then
                    tDist = clamp(tDist + step, lo, hi); moved = true
                end
            end

            if moved then idle = 0.0 else idle = idle + dt end

            -- Turntable: drifts around the car once nobody is steering it.
            if C.turntable.enabled ~= false and idle >= C.turntable.delay then
                tYaw = tYaw + C.turntable.speed * dt
            end

            -- After every way tYaw can move (see wrap180).
            tYaw = wrap180(tYaw)

            local r = C.blendRate
            yaw    = dampAngle(yaw, tYaw, r, dt)
            pitch  = damp(pitch, tPitch, r, dt)
            dist   = damp(dist,  tDist,  r, dt)
            fov    = damp(fov,   tFov,   r, dt)

            aimR = damp(aimR, tAimR, r, dt)
            aimF = damp(aimF, tAimF, r, dt)
            aimU = damp(aimU, tAimU, r, dt)
            aimP = damp(aimP, tAimP, r, dt)
            aimY = dampAngle(aimY, tAimY, r, dt)
            shift = damp(shift, tShift, r, dt)

            local p  = GetEntityCoords(target)
            local vh = GetEntityHeading(target)

            -- The orbit point in the world.
            local lx, ly, lz = localToWorld(p.x, p.y, p.z, vh, aimR, aimF, aimU)

            local h     = vh + yaw
            local ang   = rad(pitch)
            local horiz = dist * cos(ang)
            local vert  = dist * sin(ang)

            local cx, cy, cz = localToWorld(lx, ly, lz, h, 0.0, -horiz, vert)

            -- No collision avoidance: the camera goes exactly where the framing says. If a framing
            -- clips the building, change the framing.
            local cpitch, cyaw = rotFromDir(lx - cx, ly - cy, lz - cz)

            -- The composition nudge turns the view, not the position.
            cpitch = clamp(cpitch + aimP, -89.0, 89.0)
            cyaw   = cyaw + aimY

            -- Screen shift: turn the view left by the angle spanning `shift` of the screen, at the live
            -- fov and aspect, so the car sits that far right of centre.
            if shift > 0.0005 or shift < -0.0005 then
                local _, tanH = BoxFit.tangents(fov)
                cyaw = cyaw + deg(atan2(2.0 * shift * tanH, 1.0))
            end

            if not seeded then
                px, py, pz, pPitch, pYaw, pFov = cx, cy, cz, cpitch, cyaw, fov
                seeded, enterT = true, 1.0
            end

            -- The blend rate eases up on entry, so the camera swings in rather than cutting.
            local br = C.enterRateMax
            if enterT < 1.0 then
                enterT = math.min(enterT + dt / C.enterTime, 1.0)
                local b = enterT * enterT * (3.0 - 2.0 * enterT)
                br = lerp(C.enterRateMin, C.enterRateMax, b)
            end

            px     = damp(px, cx, br, dt)
            py     = damp(py, cy, br, dt)
            pz     = damp(pz, cz, br, dt)
            pPitch = damp(pPitch, cpitch, br, dt)
            pYaw   = dampAngle(pYaw, cyaw, br, dt)
            pFov   = damp(pFov, fov, br, dt)

            ---@cast handle -nil -- the cam is there while active (Cam.start makes it, Cam.stop takes both away)
            SetCamCoord(handle, px, py, pz)
            SetCamRot(handle, pPitch, 0.0, pYaw, 2)
            SetCamFov(handle, pFov)
        end

        Wait(0)
        ::continue::
    end
end

-- Nothing else will put this camera away.
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Cam.stop() end
end)
