_addon.version = '0.0.1'
_addon.name = 'attackwithme'
_addon.author = 'yyoshisaur'
_addon.commands = {'attackwithme','atkwm'}

require('logger')
require('chat')

packets = require('packets')

local help_text = [[
attack with me Commands
//atkwm master
//atkwm slave on
//atkwm slave off]]

local is_master = false
local is_slave = false

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
            attack_on(id)
        elseif msg[2] == 'off' then
            attack_off()
        end
    end
end)

windower.register_event('outgoing chunk', function(id, original, modified, injected, blocked)
    if not is_master then
        return
    end

    if id == 0x01A then
        local p = packets.parse('outgoing', original)
        if p['Category'] == 0x02 then
            windower.send_ipc_message('attack on '..tostring(p['Target']))
            log('Master: Attack On')
        elseif p['Category'] == 0x04 then
            windower.send_ipc_message('attack off')
            log('Master: Attack Off')
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
        end
        log('Master: '..set_bool_color(is_master), 'Slave: '..set_bool_color(is_slave))
    else
        --error
        log(help_text)
    end
end)