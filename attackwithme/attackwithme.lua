_addon.version = '0.0.7'
_addon.name = 'attackwithme'
_addon.author = 'yyoshisaur'
_addon.commands = {'attackwithme','atkwm'}

require('logger')
require('chat')

local packets = require('packets')

local help_text = [[
attack with me Commands
//atkwm master
//atkwm slave <on/off>
//atkwm approach <on/off>
//atkwm refollow <on/off>]]

local master_id = nil
local is_master = false
local is_slave = false
local is_slave_approach = false
local is_slave_refollow = false

local player_status = {
    ['Idle'] = 0,
    ['Engaged'] = 1,
}
local dead_status = S{2,3}
local max_retry = 5

local approach_distance = {
    ['melee'] = 2,
    ['range'] = 21
}

local function attack_on(id)
    local target = windower.ffxi.get_mob_by_id(id)

    if not target then
        -- error
        return
    end

    local p = packets.new('outgoing', 0x01A, {
        ["Target"] = target.id,
        ["Target Index"] = target.index,
        ["Category"] = 0x02 -- Engage Monster
    })

    packets.inject(p)

    log('Slave: Attack ---> '..target.name)
end

local function attack_off()
    local player = windower.ffxi.get_player()

    if not player then
        -- error
        return
    end

    local p = packets.new('outgoing', 0x01A, {
        ["Target"] = player.id,
        ["Target Index"] = player.index,
        ["Category"] = 0x04 -- Disengage
    })

    packets.inject(p)

    log('Slave: Attack Off')
end

local function change_target(id)
    local target = windower.ffxi.get_mob_by_id(id)
    local player = windower.ffxi.get_player()

    if not target or not player then
        -- error
        return
    end

    local p = packets.new('incoming', 0x058, {
        ['Player'] = player.id,
        ['Target'] = target.id,
        ['Player Index'] = player.index,
    })

    packets.inject(p)

    log('Slave: Change Target ---> '..target.name)
end

local function switch_target(id)
    local target = windower.ffxi.get_mob_by_id(id)

    if not target then
        -- error
        return
    end

    local p = packets.new('outgoing', 0x01A, {
        ["Target"] = target.id,
        ["Target Index"] = target.index,
        ["Category"] = 0x0F -- Switch target
    })

    packets.inject(p)

    log('Slave: Attack ---> '..target.name)
end

local function target_lock_on()
    local player = windower.ffxi.get_player()
    if player and not player.target_locked then
        windower.send_command('input /lockon')
    end
end

local function unfollow()
    windower.send_command('setkey numpad7 down;wait .5;setkey numpad7 up;')
end

local function face_to(target_index)
    local player = windower.ffxi.get_mob_by_id(windower.ffxi.get_player().id)
    local target = windower.ffxi.get_mob_by_index(target_index)
    local angle = (math.atan2((target.y - player.y), (target.x - player.x))*180/math.pi)*-1
    windower.ffxi.turn((angle):radian())
end

local function approach(target_index, distance)
    local function target_distance(target_index)
        local target = windower.ffxi.get_mob_by_index(target_index)
        if target == nil then
            return 0
        end
        
        return target.distance:sqrt()
    end

    local function run_to(target_index, distance, retry_count)
        if retry_count > 25 then
            windower.ffxi.run(false)
            return
        end

        if target_distance(target_index) < distance then
            windower.ffxi.run(false)
            face_to(target_index)
            return
        end

        local player = windower.ffxi.get_mob_by_id(windower.ffxi.get_player().id)
        local target = windower.ffxi.get_mob_by_index(target_index)

        if dead_status:contains(target.status) then
            windower.ffxi.run(false)
            return
        end

        local angle = (math.atan2((target.y - player.y), (target.x - player.x))*180/math.pi)*-1
        windower.ffxi.run((angle):radian())

        coroutine.schedule(function()
            run_to(target_index, distance, retry_count + 1)
        end, 0.5)
    end
    run_to(target_index, distance, 0)
end

local function is_engaged(status)
    if status == player_status['Engaged'] then
        return true
    end
    return false
end

local function is_idle(status)
    if status == player_status['Idle'] then
        return true
    end
    return false
end

local function set_bool_color(bool)
    local bool_str = tostring(bool)
    if bool then
        bool_str = bool_str:color(5)
    else
        bool_str = bool_str:color(39)
    end
    return bool_str
end

windower.register_event('ipc message', function(message)
    local msg = message:split(' ')

    if not is_slave then
        return
    end

    if msg[1] == 'attack' then
        if msg[2] == 'on' then
            local id = tonumber(msg[3])
            local player = windower.ffxi.get_player()
            local target = windower.ffxi.get_mob_by_id(id)

            if not target then
                log('Slave: Target not found!')
                return
            end

            if math.sqrt(target.distance) > 29 then
                log('Slave: ['..target.name..']'..' found, buf too far!')
                return
            end

            unfollow()

            if not is_engaged(player.status) then
                attack_on(id)
            end

            target_lock_on:schedule(1)
            if is_slave_approach then
                approach:schedule(1, target.index, approach_distance.melee)
            end

        elseif msg[2] == 'off' then
            attack_off()
        end
    elseif msg[1] == 'change' then
        local id = tonumber(msg[2])
        local target = windower.ffxi.get_mob_by_id(id)
        local player = windower.ffxi.get_player()

        if not target then
            log('Slave: Target not found!')
            return
        end

        local retry_count = 0
        repeat
            switch_target(id)
            coroutine.sleep(2)
            player = windower.ffxi.get_player()
            retry_count = retry_count + 1
        until is_engaged(player.status) or retry_count > max_retry

        target_lock_on:schedule(1)

        if is_slave_approach then
            approach:schedule(0, target.index, approach_distance.melee)
        end

    elseif msg[1] == 'follow' then
        local id = tonumber(msg[2])
        local mob = windower.ffxi.get_mob_by_id(id)
        if mob then
            local index = mob.index
            windower.ffxi.follow(index)
        end
    elseif msg[1] == 'refollow' then
        if not is_slave_refollow then
            return
        end
        local id = tonumber(msg[2])
        local mob = windower.ffxi.get_mob_by_id(id)
        if mob then
            local index = mob.index
            windower.ffxi.follow(index)
        end
    elseif msg[1] == 'master_id' then
        master_id = tonumber(msg[2])
    end
end)

function send_ipc_message_delay(msg)
    windower.send_ipc_message(msg)
end

windower.register_event('outgoing chunk', function(id, original, modified, injected, blocked)
    if not is_master then
        return
    end

    if id == 0x01A then
        local p = packets.parse('outgoing', original)
        if p['Category'] == 0x02 then
            send_ipc_message_delay:schedule(1, 'attack on %d':format(p['Target']))
            log('Master: Attack On')
        elseif p['Category'] == 0x0F then
            send_ipc_message_delay:schedule(1, 'attack on %d':format(p['Target']))
            log('Master: Switch Target')
        elseif p['Category'] == 0x04 then
            windower.send_ipc_message('attack off')
            log('Master: Attack Off')
        end
    end
end)

windower.register_event('incoming chunk', function(id, original, modified, injected, blocked)
    if is_master then
        if id == 0x058 then
            local player = windower.ffxi.get_player()
            if is_engaged(player.status) then
                local p = packets.parse('incoming', original)
                if p['Target'] > 0 then
                    send_ipc_message_delay:schedule(1, 'change %d':format(p['Target']))
                    log('Master: Change Target')
                end
            end
        end
    elseif is_slave then
        if id == 0x00E then
            local player = windower.ffxi.get_player()
            if is_engaged(player.status) then
                local target = windower.ffxi.get_mob_by_target('t')
                local p = packets.parse('incoming', original)
                if is_slave_approach and target and target.id == p['NPC'] then
                    approach:schedule(0, target.index, approach_distance.melee)
                end
            end
        end
    end
end)

windower.register_event('status change', function(new, old)
    if is_idle(new) and is_engaged(old) then
        if is_master then
            local player = windower.ffxi.get_player()
            send_ipc_message_delay:schedule(1, 'refollow %d':format(player.id))
        elseif is_slave then
            if is_slave_refollow and master_id then
                local master = windower.ffxi.get_mob_by_id(master_id)
                send_ipc_message_delay:schedule(1, 'refollow %d':format(master.id))
            end
        end
    elseif is_engaged(new) and is_idle(old) then
        if is_master then
            local player = windower.ffxi.get_player()
            windower.send_ipc_message('master_id %d':format(player.id))
        end
    end
end)

windower.register_event('addon command', function(...)
    local function settings_disp()
        log('Master: %s':format(set_bool_color(is_master)))
        log('Slave: %s [Approach: %s Refollow: %s]':format(set_bool_color(is_slave), set_bool_color(is_slave_approach), set_bool_color(is_slave_refollow)))
    end

    local args = {...}

    if not args[1] then
        log(help_text)
        return
    end

    local mode = args[1]

    if mode == 'master' then
        is_master = true
        is_slave = false
        settings_disp()
    elseif mode == 'slave' then
        if not args[2] then
            return
        end

        local slave_mode = args[2]
        if slave_mode == 'on' then
            is_slave = true
            is_master = false
        elseif slave_mode == 'off' then
            is_slave = false
            is_master = false
        else
            -- error
            log(help_text)
            return
        end
        settings_disp()
    elseif mode == 'approach' or mode == 'apr' then
        if is_slave then
            local mode = args[2]
            if mode == 'on' then
                is_slave_approach = true
            elseif mode == 'off' then
                is_slave_approach = false
            end
        end
        settings_disp()
    elseif mode == 'refollow' or mode == 'rf' then
        if is_slave then
            local mode = args[2]
            if mode == 'on' then
                is_slave_refollow = true
            elseif mode == 'off' then
                is_slave_refollow = false
            end 
        end
        settings_disp()
    elseif mode == 'follow' or mode == 'f' then
        if is_master then
            local id = windower.ffxi.get_player().id
            windower.send_ipc_message('follow %d':format(id))
        end
    else
        -- error
        log(help_text)
    end
end)