-- ============================================
-- whip_autos — developer tools
-- ============================================
-- Every /whiplash* command lives here, so the shop's own files hold only the shop. None of it runs
-- until typed. Anything that changes the world is checked by the server (whip.devtools).
--
--   /whiplash            open the shop anywhere in the car you drive (whip.devtools), or close it
--   /whiplashtune ...    put tuning straight on the car you drive (server/dev.lua)
--   /whiplashengines     rebuild the engine list (engines.json) by measuring every vehicle model
--   Open Whiplash        an option in whip_core's object viewer (G on a saved car): the shop on that car

local function notify(text, kind, ms)
    Whip.core:Notify(text, kind or 'info', ms or 6000)
end

-- ============================================
-- The shop
-- ============================================

--- Opens the shop wherever the car is; the server's claimAnywhere checks whip.devtools. Also closes a
--- session whose page failed to load.
RegisterCommand('whiplash', function()
    if Session.isActive() then
        Session.close(false)
        return
    end
    local ok, reason = Session.open({ anywhere = true })
    if not ok then
        print(('[whip_autos] cannot open: %s'):format(tostring(reason)))
        notify(reason or 'Cannot open', 'error')
    end
end, false)

-- The object viewer's (whip_core's /w tool) Open Whiplash, on one of whip's saved cars: into its driver's seat,
-- then /whiplash's open. whip_core lists it; this resource owns it.
Whip.objectViewerOption('autos.whiplash', {
    label = 'Open Whiplash', group = 'Whiplash', tint = 'violet', kinds = { 'vehicle' }, whip = true,
    hint = 'Takes the driver\'s seat and opens the Whiplash shop on this car, wherever it is.',
    select = function(target)
        local veh, ped = target.entity, PlayerPedId()
        if not veh or not DoesEntityExist(veh) then return notify('It is not there any more', 'error') end
        if Session.isActive() then return notify('Whiplash is open already', 'error') end
        if GetPedInVehicleSeat(veh, -1) ~= ped then
            if GetPedInVehicleSeat(veh, -1) ~= 0 then return notify('Someone is in its driver\'s seat', 'error') end
            TaskWarpPedIntoVehicle(ped, veh, -1)
            local deadline = GetGameTimer() + 1500
            while GetPedInVehicleSeat(veh, -1) ~= ped and GetGameTimer() < deadline do Wait(50) end
            if GetPedInVehicleSeat(veh, -1) ~= ped then return notify('Could not get into its driver\'s seat', 'error') end
        end
        local ok, reason = Session.open({ anywhere = true })
        if not ok then notify(reason or 'Cannot open', 'error') end
    end,
})

-- ============================================
-- Tuning
-- ============================================

--- Sends the line to server/dev.lua, which checks whip.devtools and writes it.
RegisterCommand('whiplashtune', function(_, args)
    local what = args[1]
    if what ~= 'engine' and what ~= 'stance' and what ~= 'setup' and what ~= 'drive' and what ~= 'clear' then
        notify('Usage: /whiplashtune engine <model|stock> · stance <height> <trackF> <trackR> <camberF> <camberR> [width] [size]'
            .. ' · setup <springs> <dampers> <antiroll> <steering> <grip> <handbrake> · drive <stock|fwd|rwd|awd> [front %] · clear', 'info', 12000)
        return
    end
    local rest = {}
    for i = 2, #args do rest[#rest + 1] = args[i] end
    TriggerServerEvent('whip_autos:server:devTune', what, rest)
end, false)

-- ============================================
-- /whiplashengines — rebuild the engine list
-- ============================================
-- Spawns every vehicle model locally (invisible, frozen, no collision, under Config.EngineDumpAt),
-- reads its engine, deletes it, and sends the list to server/engines.lua in chunks, which writes
-- engines.json. Takes minutes; whip.devtools only. Run again after adding add-on cars.

local SPAWN_DEPTH = 60.0    -- metres under Config.EngineDumpAt
local CHUNK_SIZE  = 40      -- engines per upload
local CHUNK_GAP   = 150     -- ms between uploads (under the server's rate limit)
local LOAD_WAIT   = 5000    -- ms to wait for a model before counting it failed

-- Vehicle classes with no engine to take: bicycles, and trains (CreateVehicle cannot make them).
local NO_ENGINE_CLASS = { [13] = true, [21] = true }

local dumping = false

--- One model's engine, or nil and 'skip' / 'failed'.
local function measure(name, x, y, z)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil, 'skip' end
    local class = GetVehicleClassFromName(hash)
    if NO_ENGINE_CLASS[class] then return nil, 'skip' end

    -- whip_core's loader (Whip.core: our own command's thread), not a per-frame loop.
    if type(Whip.core:LoadModel(hash, LOAD_WAIT)) ~= 'number' then return nil, 'failed' end

    local veh = CreateVehicle(hash, x, y, z, 0.0, false, false)
    if veh == 0 then
        SetModelAsNoLongerNeeded(hash)
        return nil, 'failed'
    end
    FreezeEntityPosition(veh, true)
    SetEntityVisible(veh, false, false)
    SetEntityCollision(veh, false, false)

    local drive = {}
    for _, field in ipairs(TUNING_ENGINE_FIELDS) do
        if field:sub(1, 1) == 'n' then
            drive[field] = GetVehicleHandlingInt(veh, 'CHandlingData', field)
        else
            drive[field] = GetVehicleHandlingFloat(veh, 'CHandlingData', field)
        end
    end
    local mass = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fMass')
    DeleteEntity(veh)
    SetModelAsNoLongerNeeded(hash)

    if not (drive.fInitialDriveForce and drive.fInitialDriveForce > 0) then return nil, 'skip' end   -- a trailer

    local label = GetLabelText(GetDisplayNameFromVehicleModel(hash))
    if not label or label == 'NULL' or label == '' then label = name end
    return {
        model = name:lower(), label = label, class = class, mass = mass, drive = drive,
        topSpeed = GetVehicleModelEstimatedMaxSpeed(hash) * 3.6,   -- m/s to km/h
        accel = GetVehicleModelAcceleration(hash),
    }
end

RegisterCommand('whiplashengines', function()
    if dumping then
        notify('The engine list is already being built.', 'error')
        return
    end
    CreateThread(function()
        if Whip.core:Callback('whip_autos:engineDumpAllowed') ~= true then
            notify('Building the engine list needs whip.devtools, with developer mode on in /w.', 'error')
            return
        end
        dumping = true

        local anchor = Config.EngineDumpAt
        local x, y, z = anchor.x, anchor.y, anchor.z - SPAWN_DEPTH
        local models = GetAllVehicleModels()
        local out, skipped, failed = {}, 0, 0

        for i, name in ipairs(models) do
            local entry, why = measure(name, x, y, z)
            if entry then
                out[#out + 1] = entry
            elseif why == 'failed' then
                failed = failed + 1
            else
                skipped = skipped + 1
            end
            if i % 10 == 0 then
                Whip.core:ShowText(('Measuring engines: %d / %d (%d found)'):format(i, #models, #out))
            end
            Wait(0)
        end

        local total = math.max(1, math.ceil(#out / CHUNK_SIZE))
        local run = ('%d-%d'):format(GetPlayerServerId(PlayerId()), GetGameTimer())
        for c = 1, total do
            local entries = {}
            for j = (c - 1) * CHUNK_SIZE + 1, math.min(#out, c * CHUNK_SIZE) do entries[#entries + 1] = out[j] end
            Whip.core:ShowText(('Sending the engine list: %d / %d'):format(c, total))
            TriggerServerEvent('whip_autos:server:engineDumpChunk', { run = run, index = c, total = total, entries = entries })
            Wait(CHUNK_GAP)
        end
        Whip.core:HideText()
        print(('[whip_autos] engine dump: %d engines measured, %d without an engine or not a vehicle, %d failed to load')
            :format(#out, skipped, failed))
        dumping = false
    end)
end, false)

RegisterNetEvent('whip_autos:client:engineDumpSaved', function(ok, count)
    if ok then
        notify(('Engine list saved: %d engines.'):format(tonumber(count) or 0), 'success')
    else
        notify('The server could not write engines.json — see its console.', 'error')
    end
end)
