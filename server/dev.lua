-- ============================================
-- whip_autos — developer tools, server side
-- ============================================
-- The server half of /whiplashtune (client/dev.lua). Nothing here is part of the shop.

--- /whiplashtune: puts tuning straight on the car the caller drives, free, through TuningServer.write.
--- whip.devtools only.
---   engine <model|stock> · stance <height> <trackF> <trackR> <camberF> <camberR> [width] [size]
---   setup <springs> <dampers> <antiroll> <steering> <grip> <handbrake> · drive <stock|fwd|rwd|awd> [front %] · clear
local function RegisterWithWhip()
    exports.whip_core:SecureEvent('whip_autos:server:devTune', {
        ace = 'whip.devtools',
        rateLimit = 500,
        params = {
            { 'what', 'enum', { 'engine', 'stance', 'setup', 'drive', 'clear' } },
            { 'args', 'any' },
        },
    }, function(source, _, what, args)
        local vehicleId, notDriving = exports.whip_core:GetPlayerVehicle(source, { driver = true })
        if not vehicleId then return false, notDriving or 'Drive the car you want to tune' end
        args = type(args) == 'table' and args or {}

        local changes
        if what == 'clear' then
            changes = { { key = TUNING_ENGINE_KEY }, { key = TUNING_STANCE_KEY }, { key = TUNING_SETUP_KEY },
                        { key = TUNING_DRIVE_KEY } }
        elseif what == 'drive' then
            local drive, why = TuningCleanDrive({ layout = tostring(args[1] or ''):lower(), front = tonumber(args[2]) })
            if not drive then return false, why end
            changes = { { key = TUNING_DRIVE_KEY, value = drive } }
        elseif what == 'setup' then
            local setup, why = TuningCleanSetup({
                springs = tonumber(args[1]), dampers = tonumber(args[2]), antiroll = tonumber(args[3]),
                steering = tonumber(args[4]), grip = tonumber(args[5]), handbrake = tonumber(args[6]),
            })
            if not setup then return false, why end
            changes = { { key = TUNING_SETUP_KEY, value = setup } }
        elseif what == 'engine' then
            local model = tostring(args[1] or ''):lower()
            if model == 'stock' then
                changes = { { key = TUNING_ENGINE_KEY } }
            else
                local data = Engines.data(model)
                if not data then return false, ('No engine "%s" in the engine list'):format(model) end
                changes = { { key = TUNING_ENGINE_KEY, value = data } }
            end
        else
            local stance, why = TuningCleanStance({
                height = tonumber(args[1]), trackF = tonumber(args[2]), trackR = tonumber(args[3]),
                camberF = tonumber(args[4]), camberR = tonumber(args[5]), width = tonumber(args[6]),
                size = tonumber(args[7]),
            })
            if not stance then return false, why end
            changes = { { key = TUNING_STANCE_KEY, value = stance } }
        end

        local ok, why = TuningServer.write(vehicleId, changes)
        if not ok then return false, why end
        exports.whip_core:NotifyPlayer(source, ('Tuning set on vehicle #%d'):format(vehicleId), 'success')
    end)
end

Whip.register(RegisterWithWhip)
