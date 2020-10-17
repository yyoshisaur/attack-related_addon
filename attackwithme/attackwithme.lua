_addon.version = '0.0.6'
_addon.name = 'attackwithme'
_addon.author = 'yyoshisaur'
_addon.commands = {'attackwithme','atkwm'}

require('logger')
require('chat')

local packets = require('packets')

local help_text = [[
attack with me Commands
//atkwm master
//atkwm slave on
//atkwm slave off]]

local is_master = false
local is_slave = false

local player_status = {
    ['Idle'] = 0,
    ['Engaged'] = 1,
}

local max_retry = 5

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
            local target = windower.ffxi.get_mob_by_id(id)

            if not target then
                log('Slave: Target not found!')
                return
            end

            if math.sqrt(target.distance) > 29 then
                log('Slave: ['..target.name..']'..' found, buf too far!')
                return
            end

            attack_on(id)
            target_lock_on:schedule(1)
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
        until player.status == player_status['Engaged'] or retry_count > max_retry

        target_lock_on:schedule(1)
    elseif msg[1] == 'follow' then
        local id = msg[2]
        local mob = windower.ffxi.get_mob_by_id(id)
        if mob then
            local index = mob.index
            windower.ffxi.follow(index)
        end
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
            send_ipc_message_delay:schedule(1, 'attack on '..tostring(p['Target']))
            log('Master: Attack On')
        elseif p['Category'] == 0x04 then
            windower.send_ipc_message('attack off')
            log('Master: Attack Off')
        end
    end
end)

windower.register_event('incoming chunk', function(id, original, modified, injected, blocked)
    if not is_master then
        return
    end

    if id == 0x058 then
        local player = windower.ffxi.get_player()
        if player.status == player_status['Engaged'] then
            local p = packets.parse('incoming', original)
            send_ipc_message_delay:schedule(1, 'change '..tostring(p['Target']))
            log('Master: Change Target')
        end
    end
end)

windower.register_event('addon command', function(...)
    local args = {...}

    if not args[1] then
        log(help_text)
        return
    end

    local mode = args[1]

    if mode == 'master' then
        is_master = true
        is_slave = false
        log('Master: '..set_bool_color(is_master), 'Slave: '..set_bool_color(is_slave))
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
        log('Master: '..set_bool_color(is_master), 'Slave: '..set_bool_color(is_slave))
    elseif mode == 'follow' or mode == 'f' then
        if is_master then
            local id = windower.ffxi.get_player().id
            windower.send_ipc_message('follow '..id)
        end
    else
        -- error
        log(help_text)
    end
end)