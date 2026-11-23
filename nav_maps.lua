--[[
    nav_maps.lua -- AutoAttack "aa nav" warp data (v5.06)

    The map tables below are taken unchanged from SuperWarp by Akaden
    (https://github.com/AkadenTK/superwarp, map/*.lua, fetched 2026-11-23).
    They hold every warp destination, its menu option index, its unlock
    bit and the packets each warp system needs. nav.lua runs them in its own
    environment -- SuperWarp itself does NOT need to be installed.
    Replace this file to pick up new SuperWarp data.

    SuperWarp licence (kept as its licence requires):

    Copyright © 2019, Akaden of Asura
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    
        * Redistributions of source code must retain the above copyright
          notice, this list of conditions and the following disclaimer.
        * Redistributions in binary form must reproduce the above copyright
          notice, this list of conditions and the following disclaimer in the
          documentation and/or other materials provided with the distribution.
        * Neither the name of superwarp nor the
          names of its contributors may be used to endorse or promote products
          derived from this software without specific prior written permission.
    
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
    ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

return {
-- ======================================================== homepoints
['homepoints'] = function()
local npc_names = T{
    warp = S{'Home Point'},
    set = S{'Home Point'},
}
-- Which homepoint we go to when we specify a zone, whether in shorthand or longform, and not a sub-zone location. QoL
-- Others are already the most ideal homepoint for a given zone or there is only one homepoint.
local default_by_keyword = {
    jeuno = "1", -- Jeuno zones
    nor = "2", -- Norg AH
    port = "1", -- Port zones
    aht = "2", -- Assault, Nyzul, Salvage, Survival Guide. i.e. just '//sw aht' will take you to the point of highest interest for that zone.
    urh = "2", -- Assault, Nyzul, Salvage, Survival Guide.
    mark = "1", --Sparks / Unity Bastok Markets
    rab = "2", --Ody + Nomad moogles
    wes = "2", -- Western Adoulin MH + Sparks + Unity + Vendors
    eas = "2", -- Eastern Adoulin AH + MH
    woo = "5", --Closest Ephemeral Moogle to a HP? Bone, Cloth guilds + vendors.
    win = "1", --Fishing guild Port wind
    up = "3", -- AH upper jeuno
    wat = "4", --Windurst Waters 4
    mine = "3", -- Bastok Mines alchemy
    sou = "1", --Southern San d'Oria 1 Sparks, Unity, Voidwatch, Exit, Deeds, Copper Voucher exchange.
}
return T{ -- option: 2
    short_name = {'hp','ho'},
    long_name = 'Homepoint',
    npc_plural = 'homepoints',
    npc_names = npc_names,
    zone_npc_list = function(type)
        local mlist = windower.ffxi.get_mob_list()
        mlist = table.filter(mlist, function(name)
            return name ~= "" and npc_names[type]:any(string.startswith+{name})
        end)
        mlist = table.map(mlist, function(name)
            local num = name:match('%d+$')
            return {name=name, key=(num and tostring(num))}
        end)
        return mlist
    end,
    validate = function(menu_id, zone, current_activity)
        if not(menu_id >= 8700 and menu_id <= 8704) then
            return "Incorrect menu detected! Menu ID: "..menu_id
        end
        return nil
    end,
    missing = function(warpdata, zone, p)
        local missing = T{}
        local unlock_bit_start = 32

        for z, zd in pairs(warpdata) do
            if not zd.shortcut then
                if not zd.index then
                    for d, dd in pairs(zd) do
                        if not dd.shortcut then
                            if not has_bit(p["Menu Parameters"], unlock_bit_start + dd.index) then
                                missing:append(z..'-'..d)
                            end                            
                        end
                    end
                else
                    if not has_bit(p["Menu Parameters"], unlock_bit_start + zd.index) then
                        missing:append(z)
                    end
                end
            end
        end
        return missing
    end,
    help_text = "| Homepoints |\n Command options [hp, ho]\n- hp zone name [homepoint_number] -- warp to a designated homepoint.\n- hp set -- set the closest homepoint as your return homepoint\n-----------------------------",
    sub_zone_targets = S{'entrance', 'mog house', 'auction house', '1', '2', '3', '4', '5', '6', '7', '8', '9', },
    auto_select_sub_zone = function(zone, specified)
        if not specified.legacy then
            local destiny = specified.zone:lower()
            if not specified.subzone then
                for keyword, value in pairs(default_by_keyword) do
                    if destiny:find(keyword, 1, true) then
                        return value
                    end
                end
            else
                return nil
            end
        else
            return nil
        end
    end,
    build_warp_packets = function(current_activity, zone, p, settings)
        local actions = T{}
        local packet = nil
        local menu = p["Menu ID"]
        local npc = current_activity.npc
        local destination = current_activity.activity_settings

        local gil = p["Menu Parameters"]:unpack('i', 21)
        local unlock_bit_start = 32

        debug('homepoint is unlocked: '..tostring(has_bit(p["Menu Parameters"], unlock_bit_start + destination.index)))

        if not has_bit(p["Menu Parameters"], unlock_bit_start + destination.index) then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Destination Homepoint is not unlocked yet!'})
            return actions
        end

        debug('gil: '..gil)

        if gil < 1000 then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Not enough Gil!'})
            return actions
        end

        local expac_flags = p['Menu Parameters']:sub(0x19)
        debug('destination expac: '..destination.expac..'. has access? '..tostring(has_bit(expac_flags, destination.expac)))
        if destination.expac and not has_bit(expac_flags, destination.expac) then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='You do not have access to that expansion!'})
            return actions
        end

        if settings.enable_same_zone_teleport and zone == destination.zone and destination.x and destination.y and destination.z then

            -- update request
            packet = packets.new('outgoing', 0x016)
            packet["Target Index"] = windower.ffxi.get_player().index
            actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='update request'})

            -- menu change
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = 8
            packet["_unknown1"] = 0
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, description='menu change'})

            -- request map
            packet = packets.new('outgoing', 0x114)
            actions:append(T{packet=packet, wait_packet=0x05C, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='request map'})

            -- menu change
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = 2
            packet["_unknown1"] = destination.index
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, delay=0.2, description='send options'})

            -- request in-zone warp
            packet = packets.new('outgoing', 0x05C)
            packet["Target ID"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["X"] = destination.x
            packet["Y"] = destination.y
            packet["Z"] = destination.z
            packet["_unknown1"] = destination.unknown1
            packet["Rotation"] = destination.h
            actions:append(T{packet=packet,  wait_packet=0x05C, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='same-zone move request'})

            -- complete menu
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = 3
            packet["_unknown1"] = 0
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, wait_packet=0x05C, expecting_zone=false, delay=1, description='complete menu'})

        else

            -- update request
            packet = packets.new('outgoing', 0x016)
            packet["Target Index"] = windower.ffxi.get_player().index
            actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='update request'})

            -- menu change
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = 8
            packet["_unknown1"] = 0
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, description='menu change'})
            
            -- request map
            packet = packets.new('outgoing', 0x114)
            actions:append(T{packet=packet, wait_packet=0x05C, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='request map'})

            -- menu change
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = 2
            packet["_unknown1"] = destination.index
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, delay=0.2, description='menu change'})
        
            -- request warp
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = 2
            packet["_unknown1"] = destination.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, wait_packet=0x05C, expecting_zone=true, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options and complete menu'})
        end

        return actions
    end,
    sub_commands = {
        set = function(current_activity, zone, p, settings)
            local actions = T{}
            local packet = nil
            local menu = p["Menu ID"]
            local npc = current_activity.npc
            
            -- menu change
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = 8
            packet["_unknown1"] = 0
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, description='menu change'})
            
            -- select "set HP"
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = 1
            packet["_unknown1"] = 0
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, wait_packet=0x052, expecting_zone=false, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='hp set request'})

            return actions
        end,
    },
    warpdata = T{
        ['Southern San d\'Oria'] = {
            ['Entrance'] = { shortcut = '1' },
            ['Auction House'] = { shortcut = '2' },
            ['Mog House'] = { shortcut = '3' },
            ['1'] = { index = 0,  expac = 0, zone = 230, npc = 135, x = -84.468002319336, z = 1, y = -65.454002380371, h = 95, unknown1 = 3},
            ['2'] = { index = 1,  expac = 0, zone = 230, npc = 136, x = 45.000003814697, z = 2, y = -34, h = 63, unknown1 = 65539},
            ['3'] = { index = 2,  expac = 0, zone = 230, npc = 137, x = 140, z = -2, y = 124.00000762939, h = 63, unknown1 = 131075},
            ['4'] = { index = 97, expac = 0, zone = 230, npc = 138, x = -164.00001525879, z = -1, y = 11.000000953674, h = 127, unknown1 = 6356995},},
        ['Northern San d\'Oria'] = {
            ['Entrance'] = { shortcut = '1', },
            ['Mog House'] = { shortcut = '3', },
            ['1'] = { index = 3,  expac = 0, zone = 231, npc = 112, x = -179.10101318359, z = 4, y = 71.279006958008, h = 0, unknown1 = 196611},
            ['2'] = { index = 4,  expac = 0, zone = 231, npc = 113, x = 10, z = -0.20000000298023, y = 94.000007629395, h = 191, unknown1 = 262147},
            ['3'] = { index = 5,  expac = 0, zone = 231, npc = 114, x = 69, z = -0.20000000298023, y = 9, h = 223, unknown1 = 327683},
            ['4'] = { index = 98, expac = 0, zone = 231, npc = 115, x = -134, z = 12.000000953674, y = 195.00001525879, h = 0, unknown1 = 6422531},},
        ['Port San d\'Oria'] = {
            ['Mog House'] = { shortcut = '2', },
            ['Auction House'] = { shortcut = '3', },
            ['1'] = { index = 6, expac = 0, zone = 232, npc = 86, x = -38, z = -4, y = -64, h = 191, unknown1 = 393219},
            ['2'] = { index = 7, expac = 0, zone = 232, npc = 87, x = 49.000003814697, z = -12.000000953674, y = -106.00000762939, h = 159, unknown1 = 458755},
            ['3'] = { index = 8, expac = 0, zone = 232, npc = 88, x = -6.0000004768372, z = -13.000000953674, y = -151, h = 191, unknown1 = 524291},},
        ['Bastok Mines'] = {
            ['Auction House'] = { shortcut = '1', },
            ['Mog House'] = { shortcut = '2', },
            ['1'] = { index = 9,  expac = 0, zone = 234, npc = 68, x = 38.189002990723, z = 0, y = -42.618003845215, h = 0, unknown1 = 589827},
            ['2'] = { index = 10, expac = 0, zone = 234, npc = 69, x = 117.00000762939, z = 1, y = -58.000003814697, h = 0, unknown1 = 655363},
            ['3'] = { index = 99, expac = 0, zone = 234, npc = 70, x = 86.000007629395, z = 7.0000004768372, y = 1, h = 0, unknown1 = 6488067},},
        ['Bastok Markets'] = {
            ['Entrance'] = { shortcut = '1', },
            ['Auction House'] = { shortcut = '2', },
            ['Mog House'] = { shortcut = '3', },
            ['1'] = { index = 11,  expac = 0, zone = 235, npc = 84, x = -343.00003051758, z = -10, y = -156, h = 159, unknown1 = 720899},
            ['2'] = { index = 12,  expac = 0, zone = 235, npc = 85, x = -329.00003051758, z = -12.000000953674, y = -33, h = 0, unknown1 = 786435},
            ['3'] = { index = 13,  expac = 0, zone = 235, npc = 86, x = -189.00001525879, z = -8, y = 27.000001907349, h = 63, unknown1 = 851971},
            ['4'] = { index = 100, expac = 0, zone = 235, npc = 87, x = -190.00001525879, z = -6.0000004768372, y = -68, h = 95, unknown1 = 6553603},},
        ['Port Bastok'] = {
            ['Entrance'] = { shortcut = '1', },
            ['Mog House'] = { shortcut = '2', },
            ['1'] = { index = 14,  expac = 0, zone = 236, npc = 72, x = 125.00000762939, z = 8.5, y = 7.0000004768372, h = 223, unknown1 = 917507},
            ['2'] = { index = 15,  expac = 0, zone = 236, npc = 73, x = 41.000003814697, z = 8.5, y = -238.00001525879, h = 127, unknown1 = 983043},
            ['3'] = { index = 101, expac = 0, zone = 236, npc = 74, x = -126.00000762939, z = -6.0000004768372, y = 11.000000953674, h = 95, unknown1 = 6619139},},
        ['Metalworks'] = {
            ['1'] = { index = 16,  expac = 0, zone = 237, npc = 214, x = 45.000003814697, z = -14.000000953674, y = -18, h = 63, unknown1 = 1048579},
            ['2'] = { index = 102, expac = 0, zone = 237, npc = 215, x = -77, z = 2, y = 3.0000002384186, h = 127, unknown1 = 6684675},},
        ['Windurst Waters'] = {
            ['Entrance'] = { shortcut = '1', },
            ['Mog House'] = { shortcut = '2', },
            ['1'] = { index = 17,  expac = 0, zone = 238, npc = 152, x = -33.022003173828, z = -5, y = 131.74101257324, h = 0, unknown1 = 1114115},
            ['2'] = { index = 18,  expac = 0, zone = 238, npc = 153, x = 137, z = 0, y = -14.000000953674, h = 0, unknown1 = 1179651},
            ['3'] = { index = 103, expac = 0, zone = 238, npc = 154, x = 4, z = -4, y = -175.00001525879, h = 0, unknown1 = 6750211},
            ['4'] = { index = 118, expac = 0, zone = 238, npc = 155, x = -92.000007629395, z = -2, y = 53.000003814697, h = 191, unknown1 = 7733251},},
        ['Windurst Walls'] = {
            ['Mog House'] = { shortcut = '2', },
            ['Auction House'] = { shortcut = '3', },
            ['1'] = { index = 19, expac = 0, zone = 239, npc = 103, x = -73.069999694824, z = -5.0130000114441, y = 124.78400421143, h = 0, unknown1 = 1245187},
            ['2'] = { index = 20, expac = 0, zone = 239, npc = 104, x = -212.00001525879, z = 0, y = -100.00000762939, h = 191, unknown1 = 1310723},
            ['3'] = { index = 21, expac = 0, zone = 239, npc = 105, x = 31.000001907349, z = -6.5000004768372, y = -39, h = 63, unknown1 = 1376259},},
        ['Port Windurst'] = {
            ['Entrance'] = { shortcut = '2', },
            ['Mog House'] = { shortcut = '3', },
            ['1'] = { index = 22, expac = 0, zone = 240, npc = 140, x = -188.00001525879, z = -4, y = 100.00000762939, h = 191, unknown1 = 1441795},
            ['2'] = { index = 23, expac = 0, zone = 240, npc = 141, x = -208.00001525879, z = -8.1600008010864, y = 209.00001525879, h = 223, unknown1 = 1507331},
            ['3'] = { index = 24, expac = 0, zone = 240, npc = 142, x = 179.00001525879, z = -12.000000953674, y = 226.00001525879, h = 0, unknown1 = 1572867},},
        ['Windurst Woods'] = {
            ['Entrance'] = { shortcut = '2', },
            ['Mog House'] = { shortcut = '3', },
            ['Auction House'] = { shortcut = '4', },
            ['1'] = { index = 25,  expac = 0, zone = 241, npc = 184, x = 10.088000297546, z = -2.5, y = 0.61700004339218, h = 95, unknown1 = 1638403},
            ['2'] = { index = 26,  expac = 0, zone = 241, npc = 185, x = 108.00000762939, z = -5, y = -56.000003814697, h = 127, unknown1 = 1703939},
            ['3'] = { index = 27,  expac = 0, zone = 241, npc = 186, x = -92.000007629395, z = -5, y = 63.000003814697, h = 63, unknown1 = 1769475},
            ['4'] = { index = 28,  expac = 0, zone = 241, npc = 187, x = 75, z = -7.5000004768372, y = -139, h = 127, unknown1 = 1835011},
            ['5'] = { index = 119, expac = 0, zone = 241, npc = 188, x = -44.500003814697, z = 0, y = -145, h = 0, unknown1 = 7798787},},
        ['Ru\'Lude Gardens'] = {
            ['Mog House'] = { shortcut = '2', },
            ['Auction House'] = { shortcut = '3', },
            ['1'] = { index = 29, expac = 0, zone = 243, npc = 301, x = -6.0000004768372, z = 3.0000002384186, y = -1, h = 191, unknown1 = 1900547},
            ['2'] = { index = 30, expac = 0, zone = 243, npc = 302, x = 53.000003814697, z = 9, y = -56.000003814697, h = 63, unknown1 = 1966083},
            ['3'] = { index = 31, expac = 0, zone = 243, npc = 303, x = -67, z = 6.0000004768372, y = -26.000001907349, h = 191, unknown1 = 2031619},},
        ['Upper Jeuno'] = {
            ['Entrance'] = { shortcut = '1', },
            ['Mog House'] = { shortcut = '2', },
            ['Auction House'] = { shortcut = '3', },
            ['1'] = { index = 32, expac = 0, zone = 244, npc = 87, x = -99.981002807617, z = 0, y = 167.56901550293, h = 0, unknown1 = 2097155},
            ['2'] = { index = 33, expac = 0, zone = 244, npc = 88, x = 31.000001907349, z = -1, y = -44.000003814697, h = 0, unknown1 = 2162691},
            ['3'] = { index = 34, expac = 0, zone = 244, npc = 89, x = -52.000003814697, z = 1, y = 15.000000953674, h = 191, unknown1 = 2228227},},
        ['Lower Jeuno'] = {
            ['Entrance'] = { shortcut = '1', },
            ['Mog House'] = { shortcut = '2', },
            ['1'] = { index = 35, expac = 0, zone = 245, npc = 137, x = -99.588005065918, z = 0, y = -183.416015625, h = 0, unknown1 = 2293763},
            ['2'] = { index = 36, expac = 0, zone = 245, npc = 138, x = 19, z = -1, y = 53.000003814697, h = 159, unknown1 = 2359299},},
        ['Port Jeuno'] = {
            ['Entrance'] = { shortcut = '1', },
            ['Mog House'] = { shortcut = '2', },
            ['1'] = { index = 37, expac = 0, zone = 246, npc = 57, x = 36.076000213623, z = 0, y = 8.831000328064, h = 0, unknown1 = 2424835},
            ['2'] = { index = 38, expac = 0, zone = 246, npc = 58, x = -155, z = -1, y = -3.0000002384186, h = 63, unknown1 = 2490371},},
        ['Kazham'] = { index = 39, expac = 1, zone = 250, npc = 89},
        ['Mhaura'] = { index = 40, expac = 0, zone = 249, npc = 41},
        ['Norg'] = {
            ['Entrance'] = { shortcut = '1', },
            ['Auction House'] = { shortcut = '2', },
            ['1'] = { index = 41,  expac = 1, zone = 252, npc = 52, x = -25.910001754761, z = 0.2960000038147, y = -46.164001464844, h = 95, unknown1 = 2686979},
            ['2'] = { index = 104, expac = 1, zone = 252, npc = 53, x = -65, z = -5.2000002861023, y = 54.000003814697, h = 127, unknown1 = 6815747},},
        ['Rabao'] = {
            ['Entrance'] = { shortcut = '1', },
            ['1'] = { index = 42,  expac = 1, zone = 247, npc = 27, x = -29.276000976563, z = 0, y = -77.585006713867, h = 191, unknown1 = 2752515},
            ['2'] = { index = 105, expac = 1, zone = 247, npc = 28, x = -21.000001907349, z = 8.1300001144409, y = 111.00000762939, h = 63, unknown1 = 6881283},},
        ['Selbina'] = { index = 43, expac = 0, zone = 248, npc = 45},
        ['Western Adoulin'] = {
            ['Auction House'] = { shortcut = '1', },
            ['Entrance'] = { shortcut = '1', },
            ['Mog House'] = { shortcut = '2', },
            ['1'] = { index = 44,  expac = 11, zone = 256, npc = 115, x = -85.435005187988, z = 3.9990000724792, y = -31.303001403809, h = 31, unknown1 = 2883587},
            ['2'] = { index = 109, expac = 11, zone = 256, npc = 116, x = 30.950000762939, z = 0, y = -163.00001525879, h = 31, unknown1 = 7143427},},
        ['Eastern Adoulin'] = {
            ['Auction House'] = { shortcut = '2', },
            ['Mog House'] = { shortcut = '2', },
            ['1'] = { index = 45,  expac = 11, zone = 257, npc = 88, x = -52.857002258301, z = -0.15000000596046, y = 58.877002716064, h = 223, unknown1 = 2949123},
            ['2'] = { index = 110, expac = 11, zone = 257, npc = 89, x = -50.500003814697, z = -0.15000000596046, y = -95.500007629395, h = 95, unknown1 = 7208963},},
        ['Ceizak Battlegrounds'] = { index = 46, expac = 11, zone = 261, npc = 587},
        ['Foret de Hennetiel'] = { index = 47, expac = 11, zone = 262, npc = 611},
        ['Morimar Basalt Fields'] = { index = 48, expac = 11, zone = 265, npc = 838},
        ['Yorcia Weald'] = { index = 49, expac = 11, zone = 263, npc = 637},
        ['Marjami Ravine'] = { index = 50, expac = 11, zone = 266, npc = 469},
        ['Kamihr Drifts'] = { index = 51, expac = 11, zone = 267, npc = 370},
        ['Yughott Grotto'] = { index = 52, expac = 0, zone = 142, npc = 246},
        ['Palborough Mines'] = { index = 53, expac = 0, zone = 143, npc = 433},
        ['Giddeus'] = { index = 54, expac = 0, zone = 145, npc = 480},
        ['Fei\'Yin'] = {
            ['1'] = { index = 55, expac = 0, zone = 204, npc = 476, x = 242.00001525879, z = -24.500001907349, y = 62.000003814697, h = 0, unknown1 = 3604483},
            ['2'] = { index = 94, expac = 0, zone = 204, npc = 477, x = 102.34400177002, z = -0.11300000548363, y = 269.36199951172, h = 191, unknown1 = 6160387},},
        ['Quicksand Caves'] = {
            ['1'] = { index = 56, expac = 1, zone = 208, npc = 593, x = -984.00006103516, z = 17, y = -290, h = 191, unknown1 = 3670019},
            ['2'] = { index = 96, expac = 1, zone = 208, npc = 594, x = 573, z = 8.9500007629395, y = -500.00003051758, h = 191, unknown1 = 6291459},},
        ['Den of Rancor'] = {
            ['1'] = { index = 57, expac = 1, zone = 160, npc = 520, x = -79, z = 46.000003814697, y = 62.000003814697, h = 127, unknown1 = 3735555},
            ['2'] = { index = 93, expac = 1, zone = 160, npc = 521, x = 182.00001525879, z = 34.470001220703, y = -62.000003814697, h = 223, unknown1 = 6094851},},
        ['Castle Zvahl Keep'] = { index = 58, expac = 0, zone = 162, npc = 334},
        ['Ru\'Aun Gardens'] = {
            ['1'] = { index = 59, expac = 0, zone = 130, npc = 421, x = 5, z = -42.000003814697, y = 525, h = 191, unknown1 = 3866627},
            ['2'] = { index = 60, expac = 0, zone = 130, npc = 422, x = -311, z = -42.000003814697, y = -421.00003051758, h = 95, unknown1 = 3932163},
            ['3'] = { index = 61, expac = 0, zone = 130, npc = 423, x = -498.00003051758, z = -42.000003814697, y = 167.00001525879, h = 127, unknown1 = 3997699},
            ['4'] = { index = 62, expac = 0, zone = 130, npc = 424, x = 499.00003051758, z = -42.000003814697, y = 158, h = 0, unknown1 = 4063235},
            ['5'] = { index = 63, expac = 0, zone = 130, npc = 425, x = 304, z = -42.000003814697, y = -426.00003051758, h = 31, unknown1 = 4128771},},
        ['Tavnazian Safehold'] = {
            ['1'] = { index = 64,  expac = 2, zone = 26, npc = 89, x = -2.25, z = -27.907001495361, y = 106.42500305176, h = 223, unknown1 = 4194307},
            ['2'] = { index = 120, expac = 2, zone = 26, npc = 90, x = 13.000000953674, z = -10, y = -5, h = 0, unknown1 = 7864323},
            ['3'] = { index = 121, expac = 2, zone = 26, npc = 91, x = 74.590003967285, z = -36.150001525879, y = 38.870002746582, h = 127, unknown1 = 7929859},},
        ['Aht Urhgan Whitegate'] = {
            ['Auction House'] = { shortcut = '3', },
            ['Mog House'] = { shortcut = '4', },
            ['1'] = { index = 65,  expac = 3, zone = 50, npc = 38, x = -20.130001068115, z = 0, y = -19.944000244141, h = 95, unknown1 = 4259843},
            ['2'] = { index = 106, expac = 3, zone = 50, npc = 39, x = 129, z = 0, y = -16, h = 0, unknown1 = 6946819},
            ['3'] = { index = 107, expac = 3, zone = 50, npc = 40, x = -107.00000762939, z = -6.0000004768372, y = 108.00000762939, h = 127, unknown1 = 7012355},
            ['4'] = { index = 108, expac = 3, zone = 50, npc = 41, x = -98.000007629395, z = 0, y = -68, h = 127, unknown1 = 7077891},},
        ['Nashmau'] = { index = 66, expac = 3, zone = 53, npc = 28},
        --['Al Zahbi'] = { index = 67, },
        ['Southern San d\'Oria [S]'] = { index = 68, expac = 4, zone = 80, npc = 479},
        ['Bastok Markets [S]'] = { index = 69, expac = 4, zone = 87, npc = 509},
        ['Windurst Waters [S]'] = { index = 70, expac = 4, zone = 94, npc = 468},
        ['Upper Delkfutt\'s Tower'] = { index = 71, expac = 4, zone = 158, npc = 187},
        ['The Shrine of Ru\'Avitau'] = { index = 72, expac = 1, zone = 178, npc = 529},
        ['Riverne - Site #B01'] = { index = 73, expac = 2, zone = 29, npc = 250},
        ['Bhaflau Thickets'] = { index = 74, expac = 3, zone = 52, npc = 410},
        ['Caedarva Mire'] = { index = 75, expac = 3, zone = 79, npc = 551},
        ['Uleguerand Range'] = {
            ['1'] = { index = 76, expac = 2, zone = 5, npc = 455, x = 64, z = -196.50001525879, y = 181.00001525879, h = 0, unknown1 = 4980739},
            ['2'] = { index = 77, expac = 2, zone = 5, npc = 456, x = 380.00003051758, z = 23.000001907349, y = -62.600002288818, h = 127, unknown1 = 5046275},
            ['3'] = { index = 78, expac = 2, zone = 5, npc = 457, x = 424.00003051758, z = -32.5, y = 221.00001525879, h = 63, unknown1 = 5111811},
            ['4'] = { index = 79, expac = 2, zone = 5, npc = 458, x = 64, z = -96.500007629395, y = 461.00003051758, h = 63, unknown1 = 5177347},
            ['5'] = { index = 80, expac = 2, zone = 5, npc = 459, x = -220.00001525879, z = -1, y = -62.000003814697, h = 0, unknown1 = 5242883},},
        ['Attohwa Chasm'] = { index = 81, expac = 2, zone = 7, npc = 495},
        ['Pso\'Xja'] = { index = 82, expac = 2, zone = 9, npc = 487},
        ['Newton Movalpolos'] = { index = 83, expac = 2, zone = 12, npc = 260},
        ['Riverne - Site #A01'] = { index = 84, expac = 2, zone = 30, npc = 303},
        ['Al\'Taieu'] = {
            ['1'] = { index = 85, expac = 2, zone = 33, npc = 612, x = 7.0000004768372, z = 0, y = 708.00006103516, h = 191, unknown1 = 5570563},
            ['2'] = { index = 86, expac = 2, zone = 33, npc = 613, x = -531, z = 0, y = 447.00003051758, h = 127, unknown1 = 5636099},
            ['3'] = { index = 87, expac = 2, zone = 33, npc = 614, x = 569, z = 0, y = 409.00003051758, h = 191, unknown1 = 5701635},},
        ['Grand Palace of Hu\'Xzoi'] = { index = 88, expac = 2, zone = 34, npc = 460},
        ['The Garden of Ru\'Hmet'] = { index = 89, expac = 2, zone = 35, npc = 562},
        ['Mount Zhayolm'] = { index = 90, expac = 3, zone = 61, npc = 553},
        ['Cape Teriggan'] = { index = 91, expac = 1, zone = 113, npc = 465},
        ['The Boyahda Tree'] = { index = 92, expac = 1, zone = 153, npc = 511},
        ['Ifrit\'s Cauldron'] = { index = 95, expac = 1, zone = 205, npc = 379},
        ['Xarcabard [S]'] = { index = 111, expac = 4, zone = 137, npc = 891},
        ['Leafallia'] = { index = 112, expac = 11, zone = 281, npc = 66},
        ['Castle Zvahl Keep [S]'] = { index = 113, expac = 4, zone = 155, npc = 707},
        ['Qufim Island'] = { index = 114, expac = 0, zone = 126, npc = 521},
        ['Toraimarai Canal'] = { index = 115, expac = 0, zone = 169, npc = 416},
        ['Ra\'Kaznar Inner Court'] = { index = 116, expac = 11, zone = 276, npc = 550},
        ['Misareaux Coast'] = { index = 117, expac = 2, zone = 25, npc = 394},
    },
}
end,
-- ======================================================== survivalguides
['survivalguides'] = function()
local npc_names = T{
    warp = S{'Survival Guide'},
}
return T{ -- option: 1
    short_name = {'sg','sur'},
    long_name = 'Survival guide',
    npc_plural = 'survival guides',
    npc_names = npc_names,
    zone_npc_list = function(type)
        local mlist = windower.ffxi.get_mob_list()
        mlist = table.filter(mlist, function(name)
            return name ~= "" and npc_names[type]:any(string.startswith+{name})
        end)
        mlist = table.map(mlist, function(name)
            return {name=name}
        end)
        return mlist
    end,
    validate = function(menu_id, zone, current_activity)
        if not(menu_id == 8500 or menu_id == 8501) then
            return "Incorrect menu detected! Menu ID: "..menu_id
        end
        local destination = current_activity.activity_settings
        if zone == destination.zone then
            return "You are already at that location."
        end
        return nil
    end,
    missing = function(warpdata, zone, p)
        local missing = T{}
        local unlock_bit_start = 12*8

        for z, zd in pairs(warpdata) do
            if not zd.shortcut then
                if zd.offset then
                    if not has_bit(p["Menu Parameters"], unlock_bit_start + zd.offset) then
                        missing:append(z)
                    end
                end
            end
        end
        return missing
    end,
    help_text = "| Survival Guides |\n Command options [sg, sur]\n- sg zone name -- warp to a designated survival guide.\n-----------------------------",
    sub_zone_targets = S{},
    build_warp_packets = function(current_activity, zone, p, settings)
        local actions = T{}
        local packet = nil
        local menu = p["Menu ID"]
        local npc = current_activity.npc
        local destination = current_activity.activity_settings

        local gil = p["Menu Parameters"]:unpack('I', 9)
        local valor = p["Menu Parameters"]:unpack('H', 7)    

        local thrifty_transit = menu == 8501

        local unlock_bit_start = 12*8
        
        debug('guide is unlocked: '..tostring(has_bit(p["Menu Parameters"], unlock_bit_start + destination.offset)))

        if not has_bit(p["Menu Parameters"], unlock_bit_start + destination.offset) then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Destination Survival Guide is not unlocked yet!'})
            return actions
        end

        debug('gil: '..gil.." valor: "..valor)

        local currency_stock = gil
        local currency_name = 'gil'
        local currency_minimum = 200
        -- during Thrifty Transit, the gil packet is used, but no gil is removed.
        local use_tabs_at_survival_guides = not thrifty_transit and settings.use_tabs_at_survival_guides
        if use_tabs_at_survival_guides then
            if valor < 10 then
                log("Valor point stock is too low to use. Using gil instead.")
                use_tabs_at_survival_guides = false
            else
                currency_stock = valor
                currency_name = 'valor points'
                currency_minimum = 10
            end
        end

        if currency_stock < currency_minimum then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Not enough '..currency_name..'!'})
            return actions
        end

        -- update request
        packet = packets.new('outgoing', 0x016)
        packet["Target Index"] = windower.ffxi.get_player().index
        actions:append(T{packet=packet, description='update request'})

        -- menu change
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        packet["Option Index"] = 7
        packet["_unknown1"] = 0
        packet["Automated Message"] = true
        packet["_unknown2"] = 0
        actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='menu change'})

        -- request map
        packet = packets.new('outgoing', 0x114)
        actions:append(T{packet=packet, wait_packet=0x05C, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='request map'})

        -- menu change
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        packet["Option Index"] = 1
        packet["_unknown1"] = 0
        packet["Automated Message"] = true
        packet["_unknown2"] = 0
        actions:append(T{packet=packet, delay=0.2, description='menu change'})
    
        -- request warp
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        if use_tabs_at_survival_guides then
            packet["Option Index"] = 257
        else
            packet["Option Index"] = 1
        end
        packet["_unknown1"] = destination.index
        packet["Automated Message"] = false
        packet["_unknown2"] = 0
        actions:append(T{packet=packet, wait_packet=0x05C, expecting_zone=true, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options and complete menu'})

        return actions
    end,
    warpdata = T{
        ["Northern San d'Oria"] = {index =  0, offset = 24, zone = 231, },
        ["Bastok Mines"] = {index =  1, offset = 25, zone = 234, },
        ["Port Windurst"] = {index =  2, offset = 26, zone = 240, },
        ["Ru'Lude Gardens"] = {index =  3, offset = 27, zone = 243, },
        ["Tavnazian Safehold"] = {index =  4, offset = 83, zone = 26, },
        ["Aht Urhgan Whitegate"] = {index =  5, offset = 84, zone = 50, },
        ["West Ronfaure"] = {index =  6, offset =  0, zone = 100, },
        ["Fort Ghelsba"] = {index =  7, offset = 34, zone = 141, },
        ["Bostaunieux Oubliette"] = {index =  8, offset = 19, zone = 167, },
        ["King Ranperre's Tomb"] = {index =  9, offset = 41, zone = 190, },
        ["La Theine Plateau"] = {index = 10, offset = 28, zone = 102, },
        ["Valkurm Dunes"] = {index = 11, offset =  1, zone = 103, },
        ["Konschtat Highlands"] = {index = 12, offset = 30, zone = 108, },
        ["Ordelle's Caves"] = {index = 13, offset = 44, zone = 193, },
        ["Gusgen Mines"] = {index = 14, offset = 45, zone = 196, },
        ["Carpenters' Landing"] = {index = 15, offset = 55, zone = 2, },
        ["Jugner Forest"] = {index = 16, offset =  2, zone = 104, },
        ["Batallia Downs"] = {index = 17, offset = 29, zone = 105, },
        ["Davoi"] = {index = 18, offset = 36, zone = 149, },
        ["The Eldieme Necropolis"] = {index = 19, offset = 21, zone = 195, },
        ["North Gustaberg"] = {index = 20, offset =  3, zone = 106, },
        ["Zeruhn Mines"] = {index = 21, offset = 96, zone = 172, },
        ["Korroloka Tunnel"] = {index = 22, offset = 50, zone = 173, },
        ["Dangruf Wadi"] = {index = 23, offset = 42, zone = 191, },
        ["Pashhow Marshlands"] = {index = 24, offset =  4, zone = 109, },
        ["Rolanberry Fields"] = {index = 25, offset = 31, zone = 110, },
        ["Beadeaux"] = {index = 26, offset = 35, zone = 147, },
        ["Crawlers' Nest"] = {index = 27, offset = 22, zone = 197, },
        ["West Sarutabaruta"] = {index = 28, offset =  5, zone = 115, },
        ["Toraimarai Canal"] = {index = 29, offset = 20, zone = 169, },
        ["Inner Horutoto Ruins"] = {index = 30, offset = 43, zone = 192, },
        ["Bibiki Bay"] = {index = 31, offset = 56, zone = 4, },
        ["Tahrongi Canyon"] = {index = 32, offset = 32, zone = 117, },
        ["Buburimu Peninsula"] = {index = 33, offset =  6, zone = 118, },
        ["Maze of Shakhrami"] = {index = 34, offset = 46, zone = 198, },
        ["Labyrinth of Onzozo"] = {index = 35, offset = 54, zone = 213, },
        ["Meriphataud Mountains"] = {index = 36, offset = 10, zone = 119, },
        ["Sauromugue Champaign"] = {index = 37, offset = 33, zone = 120, },
        ["Castle Oztroja"] = {index = 38, offset = 37, zone = 151, },
        ["Garlaige Citadel"] = {index = 39, offset = 23, zone = 200, },
        ["Beaucedine Glacier"] = {index = 40, offset =  7, zone = 111, },
        ["Ranguemont Pass"] = {index = 41, offset = 39, zone = 166, },
        ["Xarcabard"] = {index = 42, offset =  8, zone = 112, },
        ["Castle Zvahl Baileys"] = {index = 43, offset = 38, zone = 161, },
        ["Qufim Island"] = {index = 44, offset =  9, zone = 126, },
        ["Behemoth's Dominion"] = {index = 45, offset = 92, zone = 127, },
        ["Lower Delkfutt's Tower"] = {index = 46, offset = 40, zone = 184, },
        ["The Sanctuary of Zi'Tah"] = {index = 47, offset = 11, zone = 121, },
        ["Ro'Maeve"] = {index = 48, offset = 47, zone = 122, },
        ["Dragon's Aery"] = {index = 49, offset = 93, zone = 154, },
        ["Eastern Altepa Desert"] = {index = 50, offset = 12, zone = 114, },
        ["Western Altepa Desert"] = {index = 51, offset = 48, zone = 125, },
        ["Rabao"] = {index = 52, offset = 82, zone = 247, },
        ["Cape Teriggan"] = {index = 53, offset = 13, zone = 113, },
        ["Valley of Sorrows"] = {index = 54, offset = 94, zone = 128, },
        ["Kuftal Tunnel"] = {index = 55, offset = 51, zone = 174, },
        ["Gustav Tunnel"] = {index = 56, offset = 53, zone = 212, },
        ["Yuhtunga Jungle"] = {index = 57, offset = 14, zone = 123, },
        ["Sea Serpent Grotto"] = {index = 58, offset = 52, zone = 176, },
        ["Kazham"] = {index = 59, offset = 80, zone = 250, },
        ["Norg"] = {index = 60, offset = 81, zone = 252, },
        ["Yhoator Jungle"] = {index = 61, offset = 15, zone = 124, },
        ["Temple of Uggalepih"] = {index = 62, offset = 49, zone = 159, },
        ["Ifrit's Cauldron"] = {index = 63, offset = 95, zone = 205, },
        ["Ru'Aun Gardens"] = {index = 64, offset = 17, zone = 130, },
        ["Oldton Movalpolos"] = {index = 65, offset = 18, zone = 11, },
        ["Lufaise Meadows"] = {index = 66, offset = 16, zone = 24, },
        ["Misareaux Coast"] = {index = 67, offset = 57, zone = 25, },
        ["Phomiuna Aqueducts"] = {index = 68, offset = 58, zone = 27, },
        ["Sacrarium"] = {index = 69, offset = 59, zone = 28, },
        ["Wajaom Woodlands"] = {index = 70, offset = 60, zone = 51, },
        ["Mamook"] = {index = 71, offset = 61, zone = 65, },
        ["Aydeewa Subterrane"] = {index = 72, offset = 62, zone = 68, },
        ["Halvung"] = {index = 73, offset = 91, zone = 62, },
        ["Nashmau"] = {index = 74, offset = 85, zone = 53, },
        ["Arrapago Reef"] = {index = 75, offset = 90, zone = 54, },
        ["Caedarva Mire"] = {index = 76, offset = 89, zone = 79, },
        ["Southern San d'Oria [S]"] = {index = 77, offset = 86, zone = 80, },
        ["East Ronfaure [S]"] = {index = 78, offset = 63, zone = 81, },
        ["Jugner Forest [S]"] = {index = 79, offset = 64, zone = 82, },
        ["Batallia Downs [S]"] = {index = 80, offset = 66, zone = 84, },
        ["The Eldieme Necropolis [S]"] = {index = 81, offset = 79, zone = 175, },
        ["Bastok Markets [S]"] = {index = 82, offset = 87, zone = 87, },
        ["North Gustaberg [S]"] = {index = 83, offset = 67, zone = 88, },
        ["Grauberg [S]"] = {index = 84, offset = 68, zone = 89, },
        ["Vunkerl Inlet [S]"] = {index = 85, offset = 65, zone = 83, },
        ["Pashhow Marshlands [S]"] = {index = 86, offset = 69, zone = 90, },
        ["Rolanberry Fields [S]"] = {index = 87, offset = 70, zone = 91, },
        ["Crawlers' Nest [S]"] = {index = 88, offset = 78, zone = 171, },
        ["Windurst Waters [S]"] = {index = 89, offset = 88, zone = 94, },
        ["West Sarutabaruta [S]"] = {index = 90, offset = 71, zone = 95, },
        ["Fort Karugo-Narugo [S]"] = {index = 91, offset = 72, zone = 96, },
        ["Meriphataud Mountains [S]"] = {index = 92, offset = 73, zone = 97, },
        ["Sauromugue Champaign [S]"] = {index = 93, offset = 74, zone = 98, },
        ["Garlaige Citadel [S]"] = {index = 94, offset = 77, zone = 164, },
        ["Beaucedine Glacier [S]"] = {index = 95, offset = 75, zone = 136, },
        ["Castle Zvahl Baileys [S]"] = {index = 96, offset = 76, zone = 138, },
        ["Eastern Adoulin"] = {index = 97, offset = 97, zone = 257, },
    },
}
end,
-- ======================================================== waypoints
['waypoints'] = function()
local npc_names = T{
    warp = S{'Waypoint'},
}
local adoulin = S(require('resources').zones:en(string.endswith-{' Adoulin'}):map(table.get-{'id'}))
return T{
    short_name = {'wp','wa'},
    long_name = 'Waypoint',
    npc_plural = 'waypoints',
    npc_names = npc_names,
    zone_npc_list = function(type)
        local mlist = windower.ffxi.get_mob_list()
        local zone = windower.ffxi.get_info().zone
        mlist = table.filter(mlist, function(name)
            return name ~= "" and npc_names[type]:any(string.startswith+{name})
        end)
        if table.length(mlist) <= 1 then
            mlist = table.map(mlist, function(name)
                return {name=name}
            end)
        else
            local temp_list = L{}
            for index, name in pairs(mlist) do
                temp_list:append(index)
            end
            temp_list:sort()
            mlist = table.map(mlist, function(name)
                return {name=name}
            end)
            for index, number in temp_list:it() do
                if not adoulin:contains(zone) then
                    if number == 1 then
                        mlist[index].key = "Frontier Station"
                    else
                        mlist[index].key = tostring(number-1)
                    end
                else
                    mlist[index].key = tostring(number)
                end
            end
        end
        return mlist
    end,
    validate = function(menu_id, zone, current_activity)
        if not ((menu_id >= 5000 and menu_id <= 5008) or menu_id == 10121) then
            return "Incorrect menu detected! Menu ID: "..menu_id
        end
        return nil
    end,
    missing = function(warpdata, zone, p)
        local missing = T{}
        local unlock_bit_start = 32

        for z, zd in pairs(warpdata) do
            if not zd.shortcut then
                if not zd.index then
                    -- has sub-destinations
                    for d, dd in pairs(zd) do
                        if not dd.shortcut then
                            if dd.offset ~= nil and not has_bit(p["Menu Parameters"], unlock_bit_start + dd.offset) then
                                missing:append(z..'-'..d)
                            elseif dd.invoffset ~= nil and has_bit(p["Menu Parameters"], unlock_bit_start + dd.invoffset) then
                                missing:append(z..'-'..d)
                            end                            
                        end
                    end
                else
                    if zd.offset ~= nil and not has_bit(p["Menu Parameters"], unlock_bit_start + zd.offset) then

                        missing:append(z)
                    elseif zd.invoffset ~= nil and has_bit(p["Menu Parameters"], unlock_bit_start + zd.invoffset) then
                        missing:append(z)
                    end
                end
            end
        end
        return missing
    end,
    help_text = "| Waypoints |\n Command options [wp, wa]\n- wp zone name [waypoint_number] -- warp to a designated waypoint.\n-----------------------------",
    sub_zone_targets =  S{'frontier station','front','frontier','station', 'platea', 'triumphus', 'couriers', 'pioneers', 'mummers', 'inventors', 'auction house', 'mog house', 'bridge', 'airship', 'docks', 'waterfront', 'peacekeepers', 'scouts', 'statue', 'goddess', 'wharf', 'yahse', 'sverdhried', 'hillock', 'coronal', 'esplanade', 'castle', 'gates', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'enigmatic device'},
    auto_select_sub_zone = function(zone, specified)
        local destiny = specified.zone:lower()
        if not specified.subzone then
            if destiny:find("eas") then
                return "Auction House"
            elseif destiny:find("wes") then
                return "Mog House"
            elseif zone == 256 or zone == 257 then 
                return 'Frontier'
            else
                return 'Frontier'
            end
        else
            return nil
        end
    end,
    build_warp_packets = function(current_activity, zone, p, settings)
        local actions = T{}
        local packet = nil
        local menu = p["Menu ID"]
        local npc = current_activity.npc
        local destination = current_activity.activity_settings

        local kinetic_units_stock = p["Menu Parameters"]:unpack('H', 3)
        local current_waypoint_index = p["Menu Parameters"]:unpack('b8', 1)
        local unlock_bit_start = 32

        local destination_unlocked = false
        if destination.offset ~= nil then
            destination_unlocked = has_bit(p["Menu Parameters"], unlock_bit_start + destination.offset)
        elseif destination.invoffset then
            destination_unlocked = not has_bit(p["Menu Parameters"], unlock_bit_start + destination.invoffset)
        end

        debug('waypoint is unlocked: '..tostring(destination_unlocked))

        if not destination_unlocked then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Destination Waypoint is not unlocked yet!'})
            return actions
        end

        local courier_edi_level = p['Menu Parameters']:unpack('b4', 2, 4)

        debug('Kinetic Units stock: '..kinetic_units_stock..', current waypoint: '..current_waypoint_index..', couriers: '.. courier_edi_level)

        -- request map
        packet = packets.new('outgoing', 0x114)
        actions:append(T{packet=packet, description='request map'})

        local teleport_cost = 1
        if zone == 256 or zone == 257 then -- in Adoulin
            if destination.zone == 256 or destination.zone == 257 then -- to Adoulin
                teleport_cost = 1
            elseif destination.zone == 246 then -- to Jeuno
                teleport_cost = 15
            elseif destination.zone == 999 or destination.zone == 258 or destination.zone == 270 or destination.zone == 274 then -- to enigmatic
                teleport_cost = 150
            elseif destination.index >= 200 and destination.index <= 210 then -- rune
                teleport_cost = 100
            else
                teleport_cost = 50
            end
        elseif zone == 246 then -- in Jeuno
            if destination.zone == 256 or destination.zone == 257 then -- to Adoulin
                teleport_cost = 15
            else
                teleport_cost = 0 -- can't go there
            end
        else -- in Ulbuka
            if destination.zone == 256 or destination.zone == 257 then -- to Adoulin
                teleport_cost = 15
            elseif destination.zone == zone then -- to same zone
                teleport_cost = 2
            else -- to Ulbuka
                teleport_cost = 0 -- can't go there
            end
        end

        if teleport_cost <= 0 then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Can\'t teleport from here.'})

            return actions
        elseif teleport_cost > kinetic_units_stock then

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Not enough Kinetic Units'})

            return actions
        end

        debug('teleport cost, calculated: '..teleport_cost)

        if settings.enable_same_zone_teleport and destination.zone == zone and destination.x and destination.y and destination.z  then

            -- update request
            packet = packets.new('outgoing', 0x016)
            packet["Target Index"] = windower.ffxi.get_player().index
            actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='update request'})

            -- send options and KU cost
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = ('b7b4b3'):pack(current_waypoint_index, destination.op_z, destination.op_i):unpack('b14')
            packet["_unknown1"] = ('b5b8'):pack(0, teleport_cost):unpack('b13')
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options'})

            -- request in-zone warp
            packet = packets.new('outgoing', 0x05C)
            packet["Target ID"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["X"] = destination.x
            packet["Y"] = destination.y
            packet["Z"] = destination.z
            packet["_unknown1"] = destination.unknown1
            packet["Rotation"] = destination.h
            actions:append(T{packet=packet, wait_packet=0x05C, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='same-zone move request'})

            --print(packets.build(packet):hex())

            -- complete menu
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = destination.sz_oi
            packet["_unknown1"] = 0
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, wait_packet=0x05C, expecting_zone=false, delay=1, description='complete menu'})
        else

            -- update request
            packet = packets.new('outgoing', 0x016)
            packet["Target Index"] = windower.ffxi.get_player().index
            actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='update request'})

            -- menu change
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = ('b7b4b3'):pack(current_waypoint_index, destination.op_z, destination.op_i):unpack('b14')
            packet["_unknown1"] = ('b5b8'):pack(0, teleport_cost):unpack('b13')
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options'})


            -- request warp
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = destination.index
            packet["_unknown1"] = 0
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, wait_packet=0x05C, expecting_zone=true, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options and complete menu'})
        end

        return actions
    end,
    warpdata = T{
        ['Western Adoulin'] = {
            ['Platea'] = { shortcut = '1' },
            ['Triumphus'] = { shortcut = '1' },
            ['Couriers'] = { shortcut = '1' },
            ['Pioneers'] = { shortcut = '2' },
            ['Mummers'] = { shortcut = '3' },
            ['Inventors'] = { shortcut = '4' },
            ['Auction House'] = { shortcut = '5' },
            ['Mog House'] = { shortcut = '6' },
            ['Bridge'] = { shortcut = '7' },
            ['Airship'] = { shortcut = '8' },
            ['Docks'] = { shortcut = '8' },
            ['Waterfront'] = { shortcut = '9' },
            ['1'] = { index = 1, offset = 0, zone = 256, npc = 180, op_z = 1, op_i = 1, sz_oi = 0, x = 4.8960003852844, z = 0, y = -4.7890000343323, h = 33, unknown1 = 0},
            ['2'] = { index = 2, offset = 1, zone = 256, npc = 181, op_z = 1, op_i = 2, sz_oi = 0, x = -110.50000762939, z = 3.8500001430511, y = -13.482000350952, h = 191, unknown1 = 0},
            ['3'] = { index = 3, offset = 2, zone = 256, npc = 182, op_z = 1, op_i = 3, sz_oi = 0, x = -20.982000350952, z = -0.15000000596046, y = -79.891006469727, h = 127, unknown1 = 0},
            ['4'] = { index = 4, offset = 3, zone = 256, npc = 183, op_z = 1, op_i = 4, sz_oi = 0, x = 91.45100402832, z = -0.15000000596046, y = -49.013000488281, h = 0, unknown1 = 0},
            ['5'] = { index = 5, offset = 4, zone = 256, npc = 184, op_z = 1, op_i = 5, sz_oi = 0, x = -68.099006652832, z = 4, y = -73.672004699707, h = 28, unknown1 = 0},
            ['6'] = { index = 6, offset = 5, zone = 256, npc = 185, op_z = 1, op_i = 6, sz_oi = 0, x = 5.7310004234314, z = 0, y = -123.04300689697, h = 127, unknown1 = 0},
            ['7'] = { index = 7, offset = 6, zone = 256, npc = 186, op_z = 1, op_i = 7, sz_oi = 0, x = 174.78300476074, z = 3.8500001430511, y = -35.78800201416, h = 63, unknown1 = 0},
            ['8'] = { index = 8, offset = 7, zone = 256, npc = 187, op_z = 1, op_i = 8, sz_oi = 0, x = 14.586000442505, z = 0, y = 162.60800170898, h = 191, unknown1 = 0},
            ['9'] = { index = 9, offset = 8, zone = 256, npc = 188, op_z = 1, op_i = 9, sz_oi = 0, x = 51.09400177002, z = 32, y = 126.29900360107, h = 191, unknown1 = 0},
        },
        ['Eastern Adoulin'] = {
            ['Peacekeepers'] = { shortcut = '1' },
            ['Scouts'] = { shortcut = '2' },
            ['Statue'] = { shortcut = '3' },
            ['Goddess'] = { shortcut = '3' },
            ['Wharf'] = { shortcut = '4' },
            ['Yahse'] = { shortcut = '4' },
            ['Mog House'] = { shortcut = '5' },
            ['Auction House'] = { shortcut = '6' },
            ['Sverdhried'] = { shortcut = '7' },
            ['Hillock'] = { shortcut = '7' },
            ['Hill'] = { shortcut = '7' },
            ['Coronal'] = { shortcut = '8' },
            ['Esplanade'] = { shortcut = '8' },
            ['Castle'] = { shortcut = '9' },
            ['Gates'] = { shortcut = '9' },
            ['1'] = { index = 21, offset = 15, zone = 257, npc = 127, op_z = 2, op_i = 1, sz_oi = 0, x = -101.2740020752, z = -0.15000000596046, y = -10.726000785828, h = 191, unknown1 = 0},
            ['2'] = { index = 22, offset = 16, zone = 257, npc = 128, op_z = 2, op_i = 2, sz_oi = 0, x = -77.944000244141, z = -0.15000000596046, y = -63.926002502441, h = 0, unknown1 = 0},
            ['3'] = { index = 23, offset = 17, zone = 257, npc = 129, op_z = 2, op_i = 3, sz_oi = 0, x = -46.838001251221, z = -0.075000002980232, y = -12.767000198364, h = 63, unknown1 = 0},
            ['4'] = { index = 24, offset = 18, zone = 257, npc = 130, op_z = 2, op_i = 4, sz_oi = 0, x = -57.773002624512, z = -0.15000000596046, y = 85.237007141113, h = 127, unknown1 = 0},
            ['5'] = { index = 25, offset = 19, zone = 257, npc = 131, op_z = 2, op_i = 5, sz_oi = 0, x = -61.865001678467, z = -0.15000000596046, y = -120.81000518799, h = 127, unknown1 = 0},
            ['6'] = { index = 26, offset = 20, zone = 257, npc = 132, op_z = 2, op_i = 6, sz_oi = 0, x = -42.065002441406, z = -0.15000000596046, y = -89.97900390625, h = 191, unknown1 = 0},
            ['7'] = { index = 27, offset = 21, zone = 257, npc = 133, op_z = 2, op_i = 7, sz_oi = 0, x = 11.681000709534, z = -22.150001525879, y = 29.976001739502, h = 127, unknown1 = 0},
            ['8'] = { index = 28, offset = 22, zone = 257, npc = 134, op_z = 2, op_i = 8, sz_oi = 0, x = 27.124000549316, z = -40.150001525879, y = -60.84400177002, h = 127, unknown1 = 0},
            ['9'] = { index = 29, offset = 23, zone = 257, npc = 135, op_z = 2, op_i = 9, sz_oi = 0, x = 95.994003295898, z = -40.150001525879, y = -74.541000366211, h = 0, unknown1 = 0},
        },
        ['Yahse Hunting Grounds'] = {
            ['Frontier'] = { shortcut = 'Frontier Station' },
            ['Frontier Station'] = { index = 31, offset = 70, zone = 260, npc = 517, op_z = 4, op_i = 1, sz_oi = 1002, x = 321, z = 0, y = -199.80000305176, h = 127, unknown1 = 0},
            ['1'] =                { index = 32, offset = 71, zone = 260, npc = 518, op_z = 4, op_i = 2, sz_oi = 1002, x = 86.500007629395, z = 0, y = 1.5000001192093, h = 0, unknown1 = 0},
            ['2'] =                { index = 33, offset = 72, zone = 260, npc = 519, op_z = 4, op_i = 3, sz_oi = 1002, x = -286.5, z = 0, y = 43.500003814697, h = 127, unknown1 = 0},
            ['3'] =                { index = 34, offset = 73, zone = 260, npc = 520, op_z = 4, op_i = 4, sz_oi = 1002, x = -162.40000915527, z = 0, y = -272.80001831055, h = 191, unknown1 = 0},
        },
        ['Ceizak Battlegrounds'] = {
            ['Frontier'] = { shortcut = 'Frontier Station' },
            ['Frontier Station'] = { index = 41, offset = 64, zone = 261, npc = 524, op_z = 3,    op_i = 1, sz_oi = 1002, x = 365.00003051758, z = 0.60000002384186, y = 190.00001525879, h = 127, unknown1 = 0},
            ['1'] =                   { index = 42, offset = 65, zone = 261, npc = 525, op_z = 3, op_i = 2, sz_oi = 1002, x = -6.8790001869202, z = 0, y = -117.51100921631, h = 63, unknown1 = 0},
            ['2'] =                   { index = 43, offset = 66, zone = 261, npc = 526, op_z = 3, op_i = 3, sz_oi = 1002, x = -42.000003814697, z = 0, y = 155, h = 191, unknown1 = 0},
            ['3'] =                   { index = 44, offset = 67, zone = 261, npc = 527, op_z = 3, op_i = 4, sz_oi = 1002, x = -442.00003051758, z = 0, y = -247.00001525879, h = 191, unknown1 = 0},
        },
        ['Foret de Hennetiel'] = {
            ['Frontier'] = { shortcut = 'Frontier Station' },
            ['Frontier Station'] = { index = 51, offset = 96, zone = 262, npc = 533, op_z = 5,  op_i = 1, sz_oi = 1002, x = 398.11001586914, z = -2, y = 279.11001586914, h = 0, unknown1 = 0},
            ['1'] =                { index = 52, offset = 97, zone = 262, npc = 534, op_z = 5,  op_i = 2, sz_oi = 1002, x = 12.60000038147, z = -2.4000000953674, y = 342.00003051758, h = 0, unknown1 = 0},
            ['2'] =                { index = 53, offset = 98, zone = 262, npc = 535, op_z = 5,  op_i = 3, sz_oi = 1002, x = 505.00003051758, z = -2.25, y = -303.5, h = 127, unknown1 = 0},
            ['3'] =                { index = 54, offset = 99, zone = 262, npc = 536, op_z = 5,  op_i = 4, sz_oi = 1002, x = 103.00000762939, z = -2.2000000476837, y = -92.300003051758, h = 63, unknown1 = 0},
            ['4'] =                { index = 55, offset = 100, zone = 262, npc = 537, op_z = 5, op_i = 5, sz_oi = 1002, x = -251.80001831055, z = -2.3700001239777, y = -39.25, h = 63, unknown1 = 0},
        },
        ['Morimar Basalt Fields'] = {
            ['Frontier'] = { shortcut = 'Frontier Station' },
            ['Frontier Station'] = { index = 61, offset = 102, zone = 265, npc = 736, op_z = 6, op_i = 1, sz_oi = 1002, x = 443.72802734375, z = -16, y = -325.4280090332, h = 191, unknown1 = 0},
            ['1'] =                { index = 62, offset = 103, zone = 265, npc = 737, op_z = 6, op_i = 2, sz_oi = 1002, x = 368.00003051758, z = -16, y = 37.5, h = 127, unknown1 = 0},
            ['2'] =                { index = 63, offset = 104, zone = 265, npc = 738, op_z = 6, op_i = 3, sz_oi = 1002, x = 112.80000305176, z = -0.483000010252, y = 324.40002441406, h = 63, unknown1 = 0},
            ['3'] =                { index = 64, offset = 105, zone = 265, npc = 739, op_z = 6, op_i = 4, sz_oi = 1002, x = 175.50001525879, z = -15.581000328064, y = -318.20001220703, h = 127, unknown1 = 0},
            ['4'] =                { index = 65, offset = 106, zone = 265, npc = 740, op_z = 6, op_i = 5, sz_oi = 1002, x = -323.00003051758, z = -32, y = 2, h = 63, unknown1 = 0},
            ['5'] =                { index = 66, offset = 107, zone = 265, npc = 741, op_z = 6, op_i = 6, sz_oi = 1002, x = -78.200004577637, z = -47.284000396729, y = 303, h = 191, unknown1 = 0},
        },
        ['Yorcia Weald'] = {
            ['Frontier'] = { shortcut = 'Frontier Station' },
            ['Frontier Station'] = { index = 71, offset = 128, zone = 263, npc = 564, op_z = 7, op_i = 1, sz_oi = 1002, x = 353.30001831055, z = 0.20000000298023, y = 153.30000305176, h = 223, unknown1 = 0},
            ['1'] =                { index = 72, offset = 129, zone = 263, npc = 565, op_z = 7, op_i = 2, sz_oi = 1002, x = -40.499000549316, z = 0.36700001358986, y = 296.36700439453, h = 0, unknown1 = 0},
            ['2'] =                { index = 73, offset = 130, zone = 263, npc = 566, op_z = 7, op_i = 3, sz_oi = 1002, x = 122.13200378418, z = 0.14600001275539, y = -287.73101806641, h = 127, unknown1 = 0},
            ['3'] =                { index = 74, offset = 131, zone = 263, npc = 567, op_z = 7, op_i = 4, sz_oi = 1002, x = -274.77600097656, z = 0.3570000231266, y = 85.376007080078, h = 127, unknown1 = 0},
            ['Enigmatic Device'] = { index = 302, offset = 162, zone = 999, op_z = 11, op_i = 3 },
        },
        ['Marjami Ravine'] = {
            ['Frontier'] = { shortcut = 'Frontier Station' },
            ['Frontier Station'] = { index = 81, offset = 134, zone = 266, npc = 414, op_z = 8, op_i = 1, sz_oi = 1002, x = 358.00003051758, z = -60.000003814697, y = 165.00001525879, h = 63, unknown1 = 0},
            ['1'] =                { index = 82, offset = 135, zone = 266, npc = 415, op_z = 8, op_i = 2, sz_oi = 1002, x = 323.00003051758, z = -20, y = -79, h = 0, unknown1 = 0},
            ['2'] =                { index = 83, offset = 136, zone = 266, npc = 416, op_z = 8, op_i = 3, sz_oi = 1002, x = 6.808000087738, z = 0, y = 78.437004089355, h = 191, unknown1 = 0},
            ['3'] =                { index = 84, offset = 137, zone = 266, npc = 417, op_z = 8, op_i = 4, sz_oi = 1002, x = -318.7080078125, z = -20, y = -127.27500915527, h = 63, unknown1 = 0},
            ['4'] =                { index = 85, offset = 138, zone = 266, npc = 418, op_z = 8, op_i = 5, sz_oi = 1002, x = -326.02200317383, z = -40.023002624512, y = 201.09600830078, h = 191, unknown1 = 0},
        },
        ['Kamihr Drifts'] = {
            ['Frontier'] = { shortcut = 'Frontier Station' },
            ['Frontier Station'] = { index = 91, offset = 166, zone = 267, npc = 364, op_z = 9, op_i = 1, sz_oi = 1002, x = 439.40301513672, z = 63.000003814697, y = -272.55401611328, h = 63, unknown1 = 0},
            ['1'] =                { index = 92, offset = 167, zone = 267, npc = 365, op_z = 9, op_i = 2, sz_oi = 1002, x = -42.574001312256, z = 43.000003814697, y = -71.319000244141, h = 0, unknown1 = 0},
            ['2'] =                { index = 93, offset = 168, zone = 267, npc = 366, op_z = 9, op_i = 3, sz_oi = 1002, x = 8.2400007247925, z = 43.000003814697, y = -283.01699829102, h = 191, unknown1 = 0},
            ['3'] =                { index = 94, offset = 169, zone = 267, npc = 367, op_z = 9, op_i = 4, sz_oi = 1002, x = 9.2400007247925, z = 23.000001907349, y = 162.8030090332, h = 63, unknown1 = 0},
            ['4'] =                { index = 95, offset = 170, zone = 267, npc = 368, op_z = 9, op_i = 5, sz_oi = 1002, x = -228.94201660156, z = 3.5670001506805, y = 364.51202392578, h = 127, unknown1 = 0},
        },
        ['Jeuno'] = {
            ['Enigmatic Device'] = { index = 100, offset = 100, zone = 246, op_z = 10, op_i = 0, cost_out = 100 },
        },
        ['Rala Waterways'] = {
            ['Enigmatic Device'] = { index = 300, offset = 160, zone = 258, op_z = 11, op_i = 1, cost_out = 100 },
        },
        ['Cirdas Caverns'] = {
            ['Enigmatic Device'] = { index = 301, offset = 161, zone = 270, op_z = 11, op_i = 2 },
        },
        ['Outer Ra\'Kaznar'] = {
            ['Enigmatic Device'] = { index = 303, offset = 163, zone = 274, op_z = 11, op_i = 4 },
        },
        ['Northern San d\'Oria'] = { index = 200, invoffset = 33, op_z = 12, op_i = 1 }, 
        ['Bastok Markets'] = { index = 201, invoffset = 34, op_z = 12, op_i = 2 }, 
        ['Windurst Woods'] = { index = 202, invoffset = 35, op_z = 12, op_i = 3 }, 
        ['Selbina'] = { index = 203, invoffset = 36, op_z = 12, op_i = 4 }, 
        ['Mhaura'] = { index = 204, invoffset = 37, op_z = 12, op_i = 5 }, 
        ['Kazham'] = { index = 205, invoffset = 38, op_z = 12, op_i = 6 }, 
        ['Rabao'] = { index = 206, invoffset = 39, op_z = 12, op_i = 7 }, 
        ['Norg'] = { index = 207, invoffset = 40, op_z = 12, op_i = 8 }, 
        ['Tavnazian Safehold'] = { index = 208, invoffset = 41, op_z = 12, op_i = 9 }, 
        ['Aht Urhgan Whitegate'] = { index = 209, invoffset = 42, op_z = 12, op_i = 10 }, 
        ['Nashmau'] = { index = 210, invoffset = 43, op_z = 12, op_i = 11 }, 
    },
}
end,
-- ======================================================== protowaypoints
['protowaypoints'] = function()
local npc_names = T{
    warp = S{'Proto-Waypoint'},
}
return T{
    short_name = {'pwp','pw'},
    long_name = 'Proto-waypoint',
    npc_plural = 'proto-waypoints',
    npc_names = npc_names,
    zone_npc_list = function(type)
        local mlist = windower.ffxi.get_mob_list()
        mlist = table.filter(mlist, function(name)
            return name ~= "" and npc_names[type]:any(string.startswith+{name})
        end)
        mlist = table.map(mlist, function(name)
            return {name}
        end)
        return mlist
    end,
    validate = function(menu_id, zone, current_activity)
        local destination = current_activity.activity_settings
        if destination.zone == zone then 
            return "You are already at that location."
        end
        if not (menu_id == 10209 or -- Ru'Lude Gardens
               menu_id == 10012 or -- Selbina
               menu_id == 345 or -- Mhaura
               menu_id == 266 or -- Norg
               menu_id == 141) then -- Rabao
            return "Incorrect menu detected! Menu ID: "..menu_id
        end
        return nil
    end,
    missing = function(warpdata, zone, p)
        local missing = T{}
        local unlock_bit_start = 0

        for z, zd in pairs(warpdata) do
            if not zd.shortcut then
                if zd.offset then
                    if not has_bit(p["Menu Parameters"], unlock_bit_start + zd.offset) then
                        missing:append(z)
                    end
                end
            end
        end
        return missing
    end,
    help_text = "| Proto-Waypoints |\n Command options [pwp, pw]\n- pwp zone name -- warp to a designated geomagnetic fount.\n-----------------------------",
    build_warp_packets = function(current_activity, zone, p, settings)
        local actions = T{}
        local packet = nil
        local menu = p["Menu ID"]
        local npc = current_activity.npc
        local destination = current_activity.activity_settings

        local kinetic_units_stock = p["Menu Parameters"]:unpack('H', 13)
        local unlock_bit_start = 0

        local destination_unlocked = false
        if destination.offset ~= nil then
            destination_unlocked = has_bit(p["Menu Parameters"], unlock_bit_start + destination.offset)
        end

        debug('geomagnetic fount is unlocked: '..tostring(destination_unlocked))

        if not destination_unlocked then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Destination Geomagnetic Fount is not unlocked yet!'})
            return actions
        end

        debug('Kinetic Units stock: '..kinetic_units_stock)

        if destination.cost > kinetic_units_stock then

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Not enough Kinetic Units'})

            return actions
        end

        -- menu change
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        packet["Option Index"] = destination.index
        packet["_unknown1"] = 0
        packet["Automated Message"] = true
        packet["_unknown2"] = 0
        actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options'})


        -- request warp
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        packet["Option Index"] = destination.index
        packet["_unknown1"] = 0
        packet["Automated Message"] = false
        packet["_unknown2"] = 0
        actions:append(T{packet=packet, wait_packet=0x05C, expecting_zone=true, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options and complete menu'})


        return actions
    end,
    warpdata = T{
        ["Ru'lude Gardens"] = { index = 4, offset = 0, zone = 243, cost = 30, },
        ["Selbina"] = { index = 5, offset = 1, zone = 248, cost = 30, },
        ["Mhaura"] = { index = 6, offset = 2, zone = 249, cost = 30, },
        ["Rabao"] = { index = 7, offset = 3, zone = 247, cost = 30, },
        ["Norg"] = { index = 8, offset = 4, zone = 252, cost = 30, },
        ["West Ronfaure"] = { index = 9, offset = 5, zone = 100, cost = 100, },
        ["North Gustaberg"] = { index = 10, offset = 6, zone = 106, cost = 100, },
        ["West Sarutabaruta"] = { index = 11, offset = 7, zone = 115, cost = 100, },
        ["La Theine Plateau"] = { index = 12, offset = 8, zone = 102, cost = 100, },
        ["Konschtat Highlands"] = { index = 13, offset = 9, zone = 108, cost = 100, },
        ["Tahrongi Canyon"] = { index = 14, offset = 10, zone = 117, cost = 100, },
        ["Jugner Forest"] = { index = 15, offset = 11, zone = 104, cost = 100, },
        ["Pashhow Marshlands"] = { index = 16, offset = 12, zone = 109, cost = 100, },
        ["Meriphataud Mountains"] = { index = 17, offset = 13, zone = 119, cost = 100, },
        ["Attohwa Chasm"] = { index = 18, offset = 14, zone = 7, cost = 100, },
        ["Uleguerand Range"] = { index = 19, offset = 15, zone = 5, cost = 100, },
        ["Davoi"] = { index = 20, offset = 16, zone = 149, cost = 300, },
        ["Beadeaux"] = { index = 21, offset = 17, zone = 147, cost = 300, },
        ["Castle Oztroja"] = { index = 22, offset = 18, zone = 151, cost = 300, },
        ["Quicksand Caves"] = { index = 23, offset = 19, zone = 208, cost = 300, },
        ["Sea Serpent Grotto"] = { index = 24, offset = 20, zone = 176, cost = 300, },
        ["Temple of Uggalepih"] = { index = 25, offset = 21, zone = 159, cost = 300, },
        ["The Boyahda Tree"] = { index = 26, offset = 22, zone = 153, cost = 300, },
        ["Oldton Movalpolos"] = { index = 27, offset = 23, zone = 11, cost = 300, },
        ["Riverne - Site #B01"] = { index = 28, offset = 24, zone = 29, cost = 300, },
        ["Castle Zvahl Keep"] = { index = 29, offset = 25, zone = 162, cost = 300, },
    },
}
end,
-- ======================================================== unity
['unity'] = function()
local npc_names = T{
    warp = S{"Igsli", "Urbiolaine", "Teldro-Kesdrodo", "Yonolala", "Nunaarl Bthtrogg"},
}
return T{ -- option: 1
    short_name = {'un','uy'},
    long_name = 'Unity',
    npc_plural = 'unity npcs',
    npc_names = T{
        warp = T{"Igsli", "Urbiolaine", "Teldro-Kesdrodo", "Yonolala", "Nunaarl Bthtrogg"},
    },
    zone_npc_list = function(type)
        local mlist = windower.ffxi.get_mob_list()
        mlist = table.filter(mlist, function(name)
            return name ~= "" and npc_names[type]:any(string.startswith+{name})
        end)
        mlist = table.map(mlist, function(name)
            return {name=name}
        end)
        return mlist
    end,
    validate = function(menu_id, zone, current_activity)
        if not(menu_id == 598 or -- Igsli
               menu_id == 3529 or -- Urbiolaine
               menu_id == 879 or -- Teldro-Kesdrodo
               menu_id == 879 or -- Yonolala
               menu_id == 5149) then -- Nunaarl Bthtrogg
            return "Incorrect menu detected! Menu ID: "..menu_id
        end
        return nil
    end,
    missing = function(warpdata, zone, p)
        local missing = T{}
        local unlock_bit_start = (0x20 - 0x08) * 8

        for z, zd in pairs(warpdata) do
            if not zd.shortcut then
                if zd.offset then
                    if not has_bit(p["Menu Parameters"], unlock_bit_start + zd.offset) then
                        missing:append(z)
                    end
                end
            end
        end
        return missing
    end,
    help_text = "| Unity |\n Command options [un, uy]\n- un zone name -- warp to a designated unity zone.\n-----------------------------",
    sub_zone_targets = S{},
    build_warp_packets = function(current_activity, zone, p, settings)
        local actions = T{}
        local packet = nil
        local menu = p["Menu ID"]
        local npc = current_activity.npc
        local destination = current_activity.activity_settings

        local accolades = p["Menu Parameters"]:unpack('i', 9)

        local unlock_bit_start = (0x20 - 0x08) * 8

        local destination_unlocked = true
        if destination.offset ~= nil then
            destination_unlocked = has_bit(p["Menu Parameters"], unlock_bit_start + destination.offset)
        --elseif destination.invoffset then
        --    destination_unlocked = not has_bit(p["Menu Parameters"], unlock_bit_start + destination.invoffset)
        end

        debug('unity warp is unlocked: '..tostring(destination_unlocked))

        if not destination_unlocked then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Destination is not unlocked yet!'})
            return actions
        end

        debug("accolades: "..accolades)
        if accolades < 100 then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Not enough accolades!'})
            return actions
        end

        local popMessage = nil
        if destination.z and destination.pops then
            popMessage = "Pops located at: "..destination.z.." "..destination.pops
        end

        -- update request
        packet = packets.new('outgoing', 0x016)
        packet["Target Index"] = windower.ffxi.get_player().index
        actions:append(T{packet=packet, description='update request'})

        -- menu change
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        packet["Option Index"] = 10
        packet["_unknown1"] = 0
        packet["Automated Message"] = true
        packet["_unknown2"] = 0
        actions:append(T{packet=packet, description='menu change'})

        -- menu change
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        packet["Option Index"] = 7
        packet["_unknown1"] = 0
        packet["Automated Message"] = true
        packet["_unknown2"] = 0
        actions:append(T{packet=packet, wait_packet=0x05C, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='menu change'})
    
        -- request warp
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        packet["Option Index"] = destination.index
        packet["_unknown1"] = 0
        packet["Automated Message"] = false
        packet["_unknown2"] = 0
        actions:append(T{packet=packet, wait_packet=0x05C, expecting_zone=true, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options and complete menu', message=popMessage})

        return actions
    end,
    warpdata = T{
        -- some of these are duplicates. They've been commented out.
        ['East Ronfaure'] = { index = 1, },
        ['South Gustaberg'] = { index = 33, },
        ['East Sarutabaruta'] = { index = 65, },
        ['La Theine Plateau'] = { index = 97, },
        ['Konschtat Highlands'] = { index = 129, },
        ['Tahrongi Canyon'] = { index = 161, },
        ['Valkurm Dunes'] = { index = 193, },
        ['Buburimu Peninsula'] = { index = 225, },
        ['Qufim Island'] = { index = 257, },
        ['Bibiki Bay'] = { index = 289, },
        ['Carpenters\' Landing'] = { index = 321, },
        ['Yuhtunga Jungle'] = { index = 353, },
        ['Lufaise Meadows'] = { index = 385, offset = 1, },
        ['Jugner Forest'] = { index = 417, },
        ['Pashhow Marshlands'] = { index = 449, },
        ['Meriphataud Mountains'] = { index = 481, },
        ['Eastern Altepa Desert'] = { index = 513, },
        ['Yhoator Jungle'] = { index = 545, },
        ['The Sanctuary of Zi\'Tah'] = { index = 577, },
        ['Misareaux Coast'] = { index = 609, offset = 2, },
        ['Labyrinth of Onzozo'] = { index = 641, },
        ['Bostaunieux Oubliette'] = { index = 673, offset = 4, },
        ['Batallia Downs'] = { index = 705, },
        ['Rolanberry Fields'] = { index = 737, },
        ['Sauromugue Champaign'] = { index = 769, },
        ['Beaucedine Glacier'] = { index = 801, },
        ['Xarcabard'] = { index = 833, },
        ['Ro\'Maeve'] = { index = 865, },
        ['Western Altepa Desert'] = { index = 897, },
        ['Attohwa Chasm'] = { index = 929, },
        ['Garlaige Citadel'] = { index = 961, },
        ['Ifrit\'s Cauldron'] = { index = 993, },
        ['The Boyahda Tree'] = { index = 1025, },
        ['Kuftal Tunnel'] = { index = 1057, },
        ['Sea Serpent Grotto'] = { index = 1089, },
        ['Temple of Uggalepih'] = { index = 1121, },
        ['Quicksand Caves'] = { index = 1153, },
        ['Wajaom Woodlands'] = { index = 1185, offset = 5, },
        --['Lufaise Meadows'] = { index = 1217, offset = 1, },
        ['Cape Teriggan'] = { index = 1249, },
        ['Uleguerand Range'] = { index = 1313, },
        ['Den of Rancor'] = { index = 1345, offset = 3, },
        ['Fei\'Yin'] = { index = 1377, },
        ['Alzadaal Undersea Ruins'] = { index = 1441, offset = 6, },
        --['Misareaux Coast'] = { index = 1473, offset = 2, },
        ['Mount Zhayolm'] = { index = 1505, offset = 5, },
        ['Gustav Tunnel'] = { index = 1537, },
        ['Behemoth\'s Dominion'] = { index = 1569, },
        --['The Boyahda Tree'] = { index = 1601, },
        ['Valley of Sorrows'] = { index = 1633, },
        --['Wajaom Woodlands'] = { index = 1665, offset = 5, },
        --['Mount Zhayolm'] = { index = 1697, offset = 5, },
        ['Caedarva Mire'] = { index = 1729, offset = 6, },
        ['Aydeewa Subterrane'] = { index = 1761, offset = 7, },

        -- organized by NM:
        ['Bounding Belinda'] = { index = 33, z = "South Gustaberg", pops = "(E-7), (G-7), (G-8)", },
        ['Hugemaw Harold'] = { index = 1, z = "East Ronfaure", pops = "(H-9), (J-8), (J-10)", },
        ['Prickly Pitriv'] = { index = 65, z = "East Sarutabaruta", pops = "(G-9), (I-7), (J-9)", },
        ['Ironhorn Baldurno'] = { index = 97, z = "La Theine Plateau", pops = "(G-8), (G-9), (I-9)", },
        ['Sleepy Mabel'] = { index = 129, z = "Konschtat Highlands", pops = "(F-5), (G-9), (H-8)", },
        ['Serpopard Ninlil'] = { index = 161, z = "Tahrongi Canyon", pops = "(E-9), (H-8), (I-9)", },
        ['Abyssdiver'] = { index = 225, z = "Buburimu Peninsula", pops = "(H-7), (K-6), (K-9)", },
        ['Immanibugard'] = { index = 385, offset = 1, z = "Lufaise Meadows", pops = "(G-7), (J-9), (K-9)", },
        ['Intuila'] = { index = 289, z = "Bibiki Bay", pops = "(G-8), (H-10), (I-6)", },
        ['Jester Malatrix'] = { index = 257, z = "Qufim Island", pops = "(G-7), (G-8), (I-8)", },
        ['Orcfeltrap'] = { index = 321, z = "Carpenters' Landing", pops = "(H-9), (I-9), (I-11)", },
        ['Sybaritic Samantha'] = { index = 353, z = "Yuhtunga Jungle", pops = "(F-11), (F-10), (I-6)", },
        ['Valkurm Imperator'] = { index = 193, z = "Valkurm Dunes", pops = "(D-6), (E-8), (K-9)", },
        ['Cactrot Veloz'] = { index = 513, z = "Eastern Altepa Desert", pops = "(G-10), (I-5), (J-9)", },
        ['Emperor Arthro'] = { index = 417, z = "Jugner Forest", pops = "(I-6), (I-9), (J-11)", },
        ['Garbage Gel'] = { index = 673, offset = 4, z = "Bostaunieux Oubliette", pops = "(J-7), (J-10), (F-8)", },
        ['Joyous Green'] = { index = 449, z = "Pashhow Marshlands", pops = "(H-9), (I-6), (J-9)", },
        ['Keeper of Heiligtum'] = { index = 577, z = "The Sanctuary of Zi'Tah", pops = "(J-11), (K-9), (J-10)", },
        ['Tiyanak'] = { index = 609, z = "Misareaux Coast", offset = 2, pops = "(G-8), (F-8), (I-11)", },
        ['Voso'] = { index = 641, z = "Labyrinth of Onzozo", pops = "(G-6), (H-7), (I-5)", },
        ['Warblade Beak'] = { index = 481, z = "Meriphataud Mountains", pops = "(G-9), (I-9), (K-11)", },
        ['Woodland Mender'] = { index = 545, z = "Yhoator Jungle", pops = "(G-10), (H-7), (I-10)", },
        ['Arke'] = { index = 769, z = "Sauromugue Champaign", pops = "(G-8), (J-9), (L-7)", },
        ['Ayapec'] = { index = 1025, z = "The Boyahda Tree", pops = "(D-6), (I-10), (H-6)", },
        ['Azure-toothed Clawberry'] = { index = 1121, z = "Temple of Uggalepih", pops = "Map 1 : (J-8), Map 2 :(H-9), (F-7)", },
        ['Bakunawa'] = { index = 1089, z = "Sea Serpent Grotto", pops = "(J-8), (I-10), (D-9)", },
        ['Beist'] = { index = 833, z = "Xarcabard", pops = "(I-7), (I-8), (I-9)", },
        ['Centurio XX-I'] = { index = 1153, z = "Quicksand Caves", pops = "Map 1 : (H-12), (I-5), (I-9)", },
        ['Coca'] = { index = 993, z = "Ifrit's Cauldron", pops = "(I-7), (F-10), (H-6)", },
        ['Douma Weapon'] = { index = 865, z = "Ro'Maeve", pops = "(I-10), (G-11), (C-9)", },
        ['King Uropygid'] = { index = 897, z = "Western Altepa Desert", pops = "(F-10), (F-8), (J-6)", },
        ['Kubool Ja\'s Mhuufya'] = { index = 1185, offset = 5, z = "Wajaom Woodlands", pops = "(K-9), (I-9), (I-8)", },
        ['Largantua'] = { index = 801, z = "Beaucedine Glacier", pops = "(J-7), (K-8), (K-9)", },
        ['Lumber Jill'] = { index = 705, z = "Batallia Downs", pops = "(E-5), (H-9), (J-7)", },
        ['Mephitas'] = { index = 961, z = "Garlaige Citadel", pops = "(I-6), (G-7), (H-8)", },
        ['Muut'] = { index = 929, z = "Attohwa Chasm", pops = "(F-7), (E-8), (G-9)", },
        ['Specter Worm'] = { index = 1057, z = "Kuftal Tunnel", pops = "(F-9), (H-5), (J-11)", },
        ['Strix'] = { index = 737, z = "Rolanberry Fields", pops = "(E-11), (F-8), (J-8)", },
        ['Vermillion Fishfly'] = { index = 1217, offset = 1, z = "Lufaise Meadows", pops = "(G-7), (J-9), (K-9)", },
        ['Azrael'] = { index = 1345, offset = 3, z = "Den of Rancor", pops = "(H-5), (G-10), (G-9)", },
        ['Borealis Shadow'] = { index = 1377, z = "Fei'Yin", pops = "(I-7), (J-8), (F-9)", },
        ['Camahueto'] = { index = 1313, z = "Uleguerand Range", pops = "(G-10), (D-9), (D-8)", },
        ['Carousing Celine'] = { index = 1377, z = "Fei'Yin", pops = "Map 1 : (I-7), (J-8), (F-9)", },
        ['Grand Grenade'] = { index = 1505, offset = 5, z = "Mount Zhayolm", pops = "(D-5), (C-6), (E-7)", },
        ['Vedrfolnir'] = { index = 1249, z = "Cape Teriggan", pops = "(I-7), (H-8), (I-8)", },
        ['Vidmapire'] = { index = 1441, offset = 6, z = "Alzadaal Undersea Ruins", pops = "Map 5: (F-7), (F-10), (I-10)", },
        ['Volatile Cluster'] = { index = 1473, z = "Misareaux Coast", offset = 2, pops = "(G-8), (F-8), (I-11)", },
        ['Glazemane'] = { index = 1249, z = "Cape Teriggan", pops = "(I-7), (H-8), (I-8)", },
        ['Wyvernhunter Bambrox'] = { index = 1537, z = "Gustav Tunnel", pops = "Map 2 : (H-6), (G-8), (F-7)", },
        ['Hidhaegg'] = { index = 1601, z = "The Boyahda Tree", pops = "Map 1 : (D-6), Map 2 : (I-10), Map 3 : (F-6)", },
        ['Sovereign Behemoth'] = { index = 1569, z = "Behemoth's Dominion", pops = "(E-8), (G-8), (J-9)", },
        ['Tolba'] = { index = 1633, z = "Valley of Sorrows", pops = "(G-8), (F-9), (G-9)", },
        ['Thu\'ban'] = { index = 1665, offset = 5, z = "Wajaom Woodlands", pops = "(K-9), (I-8), (I-9)", },
        ['Sarama'] = { index = 1697, offset = 5, z = "Mount Zhayolm", pops = "(D-5), (C-6), (E-7)", },
        ['Shedu'] = { index = 1729, offset = 6, z = "Caedarva Mire", pops = "Map 4 : (H-7), (G-8), (I-7)", },
        ['Tumult Curator'] = { index = 1761, offset = 7, z = "Aydeewa Subterrane", pops = "Map 2 : (J-9), (K-7), (L-8)", },
    },
}
end,
-- ======================================================== escha
['escha'] = function()
local entry_zones = S{126,25,102,108,117,291}
local escha_zones = S{288,289,291,293}
local npc_names = T{
    warp = S{'Eschan Portal', 'Ethereal Ingress'},
    enter = S{'Undulating Confluence', 'Dimensional Portal','Etched Rock'},
    domain = S{'Affi', 'Dremi', 'Shiftrix'},
    exit= S{'Undulating Confluence', 'Dimensional Portal','Etched Rock'},
}
return T{
    short_name = {'ew','ea'},
    long_name = 'Escha',
    npc_plural = 'eschan npcs',
    npc_names = npc_names,
    escha_zones = escha_zones,
    zone_npc_list = function(type)
        local mlist = windower.ffxi.get_mob_list()
        mlist = table.filter(mlist, function(name)
            return name ~= "" and npc_names[type]:any(string.startswith+{name})
        end)
        mlist = table.map(mlist, function(name)
            local num = name:match('%d+$')
            return {name=name, key=(num and tostring(num))}
        end)
        return mlist
    end,
    validate = function(menu_id, zone, current_activity)
        local destination = current_activity.activity_settings
        if not ( -- NPCs:
               menu_id == 9701 or 
               -- enter: Confluence/Portal:
               menu_id == 65 or -- Qufim
               menu_id == 14 or -- Misareaux
               menu_id == 926 or -- Tahrongi
               menu_id == 222 or -- La Theine
               menu_id == 926 or -- Konschtat
               -- exit: Confluence/Portal
               menu_id == 4 or -- Escha - Zi'tah
               menu_id == 1 or -- Escha - Ru'aun
               menu_id == 14 or -- Reisenjima
               menu_id == 16 or -- Etched Rock, Reisenjima Sanctorium
               menu_id == 11 or -- Etched Rock, Reisenjima
               -- portal/ingress: 
               menu_id == 9100 ) then
            return "Incorrect menu detected! Menu ID: "..menu_id
        end

        if current_activity.sub_cmd == nil and zone ~= destination.zone then
            return "Not in correct zone!"
        end

        if current_activity.sub_cmd == 'enter' and not entry_zones:contains(zone) then
            return 'Not in an entry zone!'
        end
        if current_activity.sub_cmd == 'enter' and menu_id == 14 and escha_zones:contains(zone) then
            return 'You are already inside.'
        end
        if current_activity.sub_cmd == 'exit' and not escha_zones:contains(zone) then
            return 'Not in an eschan zone!'
        end
        if current_activity.sub_cmd == 'domain' and not escha_zones:contains(zone) then
            return 'Not in an eschan zone!'
        end
        return nil
    end,
    missing = function(warpdata, zone, p)
        local missing = T{}
        local unlock_bit_start = 32

        local zd = nil
        if zone == 288 then zd = warpdata['Escha Zi\'tah'] end
        if zone == 289 then zd = warpdata['Escha Ru\'an'] end
        if zone == 291 then zd = warpdata['Reisenjima'] end
        if zd == nil then
            return nil, 'You cannot check missing destinations from here.'
        end

        for d, dd in pairs(zd) do
            if not dd.shortcut and dd.offset then
                if not has_bit(p["Menu Parameters"], unlock_bit_start + dd.offset) then
                    missing:append(z..'-'..d)
                end
            end
        end
        return missing
    end,
    help_text = "| Escha |\n Command options [ew, ea]\n- ew portal number -- warp to a designated portal in your current escha zone.\n- ew enter -- enter the eschan zone corresponding to the entrance zone.\n- ew domain -- get Elvorseal if needed and warp to the domain invasion arena.\n- ew domain return -- return Elvorseal.\n- ew exit -- leave escha.\n-----------------------------",
    sub_zone_targets =  S{'1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14','15' },
    auto_select_zone = function(zone)
        if zone == 288 then return 'Escha Zi\'tah' end
        if zone == 289 then return 'Escha Ru\'an' end
        if zone == 291 then return 'Reisenjima' end
    end,
    build_warp_packets = function(current_activity, zone, p, settings)
        local actions = T{}
        local packet = nil
        local menu = p["Menu ID"]
        local npc = current_activity.npc
        local destination = current_activity.activity_settings

        local silt_stock = p["Menu Parameters"]:unpack('i', 21)

        debug('silt '..silt_stock)
        if silt_stock < 1000 then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Not enough Silt!'})
            return actions
        end

        local unlock_bit_start = 32

        local destination_unlocked = true
        if destination.offset ~= nil then
            destination_unlocked = has_bit(p["Menu Parameters"], unlock_bit_start + destination.offset)
        --elseif destination.invoffset then
        --    destination_unlocked = not has_bit(p["Menu Parameters"], unlock_bit_start + destination.invoffset)
        end

        debug('portal is unlocked: '..tostring(destination_unlocked))

            if not destination_unlocked then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Destination Portal is not unlocked yet!'})
            return actions
        end

        -- update request
        packet = packets.new('outgoing', 0x016)
        packet["Target Index"] = windower.ffxi.get_player().index
        actions:append(T{packet=packet, description='update request'})

        -- request map
        packet = packets.new('outgoing', 0x114)
        actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='request map'})

        -- menu change
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        packet["Option Index"] = 1
        packet["_unknown1"] = destination.index
        packet["Automated Message"] = true
        packet["_unknown2"] = 0
        actions:append(T{packet=packet, delay=0.2, description='send options'})

        -- request in-zone warp
        packet = packets.new('outgoing', 0x05C)
        packet["Target ID"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        packet["X"] = destination.x
        packet["Y"] = destination.y
        packet["Z"] = destination.z
        packet["_unknown1"] = destination.unknown1
        packet["Rotation"] = destination.h
        actions:append(T{packet=packet, wait_packet=0x052, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='same-zone move request'})

        -- complete menu
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        packet["Option Index"] = 2
        packet["_unknown1"] = 0
        packet["Automated Message"] = false
        packet["_unknown2"] = 0
        actions:append(T{packet=packet, wait_packet=0x052, expecting_zone=false, delay=1, description='complete menu'})
            
        return actions
    end,
    sub_commands = {
        enter = function(current_activity, zone, p, settings)
            local actions = T{}
            local packet = nil
            local menu = p["Menu ID"]
            local npc = current_activity.npc

            local oi = 0

            -- qufim or misareaux
            if zone == 126 or zone == 25 or zone == 291 then 
                oi = 1
            -- La theine, konschtat or tahrongi
            elseif zone == 102 or zone == 108 or zone == 117 then 
                oi = 2 
            end

            if zone == 291 then
                log("Entering Reisenjima Sanctorium...")
            else
                log("Entering Escha...")
            end
            -- update request
            packet = packets.new('outgoing', 0x016)
            packet["Target Index"] = windower.ffxi.get_player().index
            actions:append(T{packet=packet, description='update request'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = oi
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, wait_packet=0x052, expecting_zone=true, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation) + 0.5, description='complete menu'})

            return actions
        end,
        exit = function(current_activity, zone, p, settings)
            local actions = T{}
            local packet = nil
            local menu = p["Menu ID"]
            local npc = current_activity.npc

            if zone == 293 then
                log("Leaving Reisenjima Sanctorium...")
            else
                log("Leaving Escha...")
            end
            -- update request
            packet = packets.new('outgoing', 0x016)
            packet["Target Index"] = windower.ffxi.get_player().index
            actions:append(T{packet=packet, description='update request'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 1
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, wait_packet=0x052, expecting_zone=true, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='complete menu'})

            return actions
        end,
        domain = function(current_activity, zone, p, settings)
            local actions = T{}
            local packet = nil
            local menu = p["Menu ID"]
            local npc = current_activity.npc
            local args = current_activity.args

            local dragon_state = p["Menu Parameters"]:unpack('b2', 1)
            local has_elvorseal = p["Menu Parameters"]:unpack('b8', 4) == 0x80

            if #args == 0 or args[1] == 'enter' then

                log('Checking Domain Invasion state.')

                if dragon_state == 0 or dragon_state == 3 then
                    -- dragon not ready.

                    packet = packets.new('outgoing', 0x05B)
                    packet["Target"] = npc.id
                    packet["Option Index"] = 0
                    packet["_unknown1"] = 16384
                    packet["Target Index"] = npc.index
                    packet["Automated Message"] = false
                    packet["_unknown2"] = 0
                    packet["Zone"] = zone
                    packet["Menu ID"] = menu
                    actions:append(T{packet=packet, description='cancel menu', message='Elvorseal is not ready yet.'})        
                    return actions        
                end

                packet = packets.new('outgoing', 0x05B)
                packet["Target"] = npc.id
                packet["Option Index"] = 14
                packet["_unknown1"] = 0
                packet["Target Index"] = npc.index
                packet["Automated Message"] = true
                packet["_unknown2"] = 0
                packet["Zone"] = zone
                packet["Menu ID"] = menu
                actions:append(T{packet=packet, description='init menu'})    

                packet = packets.new('outgoing', 0x05B)
                packet["Target"] = npc.id
                packet["Option Index"] = 8
                packet["_unknown1"] = 0
                packet["Target Index"] = npc.index
                packet["Automated Message"] = true
                packet["_unknown2"] = 0
                packet["Zone"] = zone
                packet["Menu ID"] = menu
                actions:append(T{packet=packet, wait_packet=0x05C, description='init menu'})    

                packet = packets.new('outgoing', 0x05B)
                packet["Target"] = npc.id
                packet["Option Index"] = 9
                packet["_unknown1"] = 0
                packet["Target Index"] = npc.index
                packet["Automated Message"] = true
                packet["_unknown2"] = 0
                packet["Zone"] = zone
                packet["Menu ID"] = menu
                actions:append(T{packet=packet, wait_packet=0x05C, description='init menu'})    

                if not has_elvorseal then
                    packet = packets.new('outgoing', 0x05B)
                    packet["Target"] = npc.id
                    packet["Option Index"] = 9
                    packet["_unknown1"] = 0
                    packet["Target Index"] = npc.index
                    packet["Automated Message"] = true
                    packet["_unknown2"] = 0
                    packet["Zone"] = zone
                    packet["Menu ID"] = menu
                    actions:append(T{packet=packet, wait_packet=0x05C, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='menu choice elvorseal', message='Getting Elvorseal...'})    

                    packet = packets.new('outgoing', 0x05B)
                    packet["Target"] = npc.id
                    packet["Option Index"] = 10
                    packet["_unknown1"] = 0
                    packet["Target Index"] = npc.index
                    packet["Automated Message"] = true
                    packet["_unknown2"] = 0    
                    packet["Zone"] = zone
                    packet["Menu ID"] = menu
                    actions:append(T{packet=packet, wait_packet=0x05C, description='menu choice elvorseal'})    
                end

                packet = packets.new('outgoing', 0x05B)
                packet["Target"] = npc.id
                packet["Option Index"] = 11
                packet["_unknown1"] = 0
                packet["Target Index"] = npc.index
                packet["Automated Message"] = true
                packet["_unknown2"] = 0
                packet["Zone"] = zone
                packet["Menu ID"] = menu
                actions:append(T{packet=packet, wait_packet=0x05C, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='menu choice teleport', message='Warping to battle!'})    

                -- 0x05C
                packet = packets.new('outgoing', 0x05C)
                packet["Target ID"] = npc.id
                packet["Target Index"] = npc.index
                packet["Zone"] = zone
                packet["Menu ID"] = menu

                if zone == 288 then -- zitah
                    packet["X"] = -2
                    packet["Z"] = 0
                    packet["Y"] = 59.500003814697
                    packet["_unknown1"] = 12
                    packet["Rotation"] = 63
                elseif zone == 289 then -- ruaun
                    packet["X"] = 0
                    packet["Z"] = -43.600002288818
                    packet["Y"] = -238.00001525879 
                    packet["_unknown1"] = 12
                    packet["Rotation"] = 191
                elseif zone == 291 then -- Reisenjima
                    packet["X"] = 640
                    packet["Z"] = -372.00003051758
                    packet["Y"] = -921.00006103516
                    packet["_unknown1"] = 12
                    packet["Rotation"] = 95
                end

                actions:append(T{packet=packet, wait_packet=0x05C, delay=1, description='same-zone move request'})

                packet = packets.new('outgoing', 0x05B)
                packet["Target"] = npc.id
                packet["Option Index"] = 12
                packet["_unknown1"] = 0
                packet["Target Index"] = npc.index
                packet["Automated Message"] = false
                packet["_unknown2"] = 0
                packet["Zone"] = zone
                packet["Menu ID"] = menu
                actions:append(T{packet=packet, wait_packet=0x05C, expecting_zone=false, delay = 1, description='complete menu'})    

                return actions  
            elseif args[1] == 'return' then
                if not has_elvorseal then

                    packet = packets.new('outgoing', 0x05B)
                    packet["Target"] = npc.id
                    packet["Option Index"] = 0
                    packet["_unknown1"] = 16384
                    packet["Target Index"] = npc.index
                    packet["Automated Message"] = false
                    packet["_unknown2"] = 0
                    packet["Zone"] = zone
                    packet["Menu ID"] = menu
                    actions:append(T{packet=packet, description='cancel menu', message='You don\'t have elvorseal.'})      

                    return actions
                else
                    packet = packets.new('outgoing', 0x05B)
                    packet["Target"] = npc.id
                    packet["Option Index"] = 14
                    packet["_unknown1"] = 0
                    packet["Target Index"] = npc.index
                    packet["Automated Message"] = true
                    packet["_unknown2"] = 0
                    packet["Zone"] = zone
                    packet["Menu ID"] = menu
                    actions:append(T{packet=packet, description='init menu'})    

                    packet = packets.new('outgoing', 0x05B)
                    packet["Target"] = npc.id
                    packet["Option Index"] = 8
                    packet["_unknown1"] = 0
                    packet["Target Index"] = npc.index
                    packet["Automated Message"] = true
                    packet["_unknown2"] = 0
                    packet["Zone"] = zone
                    packet["Menu ID"] = menu
                    actions:append(T{packet=packet, delay=.5, description='init menu'})    

                    packet = packets.new('outgoing', 0x05B)
                    packet["Target"] = npc.id
                    packet["Option Index"] = 9
                    packet["_unknown1"] = 0
                    packet["Target Index"] = npc.index
                    packet["Automated Message"] = true
                    packet["_unknown2"] = 0
                    packet["Zone"] = zone
                    packet["Menu ID"] = menu
                    actions:append(T{packet=packet, delay=.5, description='init menu'})    

                    packet = packets.new('outgoing', 0x05B)
                    packet["Target"] = npc.id
                    packet["Option Index"] = 9
                    packet["_unknown1"] = 0
                    packet["Target Index"] = npc.index
                    packet["Automated Message"] = true
                    packet["_unknown2"] = 0
                    packet["Zone"] = zone
                    packet["Menu ID"] = menu
                    actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='menu choice return', message="Returning Elvorseal."})    

                    packet = packets.new('outgoing', 0x05B)
                    packet["Target"] = npc.id
                    packet["Option Index"] = 10
                    packet["_unknown1"] = 0
                    packet["Target Index"] = npc.index
                    packet["Automated Message"] = true
                    packet["_unknown2"] = 0
                    packet["Zone"] = zone
                    packet["Menu ID"] = menu
                    actions:append(T{packet=packet, wait_packet=0x05C, description='menu choice return'})    

                    packet = packets.new('outgoing', 0x05B)
                    packet["Target"] = npc.id
                    packet["Option Index"] = 0
                    packet["_unknown1"] = 0
                    packet["Target Index"] = npc.index
                    packet["Automated Message"] = false
                    packet["_unknown2"] = 0
                    packet["Zone"] = zone
                    packet["Menu ID"] = menu
                    actions:append(T{packet=packet, wait_packet=0x05C, delay = 1, expecting_zone=false, description='complete menu'})    

                    return actions
                end
            end
        end,
    },
    warpdata = T{
        ['Escha Zi\'tah'] = T{
            ['1'] = { index = 0, zone = 288, npc = 586, offset = 0, x = -343.00003051758, z = -0.070000000298023, y = -172.00001525879, h = 0, unknown1 = 2},
            ['2'] = { index = 1, zone = 288, npc = 587, offset = 1, x = -303, z = -0.030000001192093, y = 308, h = 191, unknown1 = 65538},
            ['3'] = { index = 2, zone = 288, npc = 588, offset = 2, x = -261, z = 0.6700000166893, y = -16, h = 191, unknown1 = 131074},
            ['4'] = { index = 3, zone = 288, npc = 589, offset = 3, x = -110.00000762939, z = 0.12000000476837, y = -241.00001525879, h = 63, unknown1 = 196610},
            ['5'] = { index = 4, zone = 288, npc = 590, offset = 4, x = 245.00001525879, z = 0.27000001072884, y = -148, h = 0, unknown1 = 262146},
            ['6'] = { index = 5, zone = 288, npc = 591, offset = 5, x = 452.00003051758, z = 1.3900001049042, y = -344.00003051758, h = 191, unknown1 = 327682},
            ['7'] = { index = 6, zone = 288, npc = 592, offset = 6, x = 191.00001525879, z = 0.20000000298023, y = -318, h = 0, unknown1 = 393218},
            ['8'] = { index = 7, zone = 288, npc = 593, offset = 7, x = -134, z = 1.8000000715256, y = -454.00003051758, h = 159, unknown1 = 458754},
            --elvorseal x = -2, z = 0, y = 59.500003814697, h = 16129, unknown1 = 12
        },
        ['Escha Ru\'an'] = T{
            ['1'] = { index = 8,   zone = 289, npc = 752, offset = 8,  x = 10, z = -34, y = -464.00003051758, h = 191, unknown1 = 524290},
            ['2'] = { index = 9,   zone = 289, npc = 753, offset = 9,  x = -275.5, z = -40.500003814697, y = -378.50003051758, h = 223, unknown1 = 589826},
            ['3'] = { index = 10,  zone = 289, npc = 754, offset = 10, x = -454.00003051758, z = -3.5000002384186, y = -147.5, h = 127, unknown1 = 655362},
            ['4'] = { index = 11,  zone = 289, npc = 755, offset = 11, x = -452.50003051758, z = -71.42000579834, y = -307.5, h = 223, unknown1 = 720898},
            ['5'] = { index = 12,  zone = 289, npc = 756, offset = 12, x = -444.50003051758, z = -40.500003814697, y = 144, h = 0, unknown1 = 786434},
            ['6'] = { index = 13,  zone = 289, npc = 757, offset = 13, x = -280.5, z = -3.5000002384186, y = 386.50003051758, h = 159, unknown1 = 851970},
            ['7'] = { index = 14,  zone = 289, npc = 758, offset = 14, x = -431.50003051758, z = -71.850006103516, y = 335.50003051758, h = 31, unknown1 = 917506},
            ['8'] = { index = 15,  zone = 289, npc = 759, offset = 15, x = 0, z = -40.500003814697, y = 466.50003051758, h = 63, unknown1 = 983042},
            ['9'] = { index = 16,  zone = 289, npc = 760, offset = 16, x = 278.5, z = -3.6300001144409, y = 384.00003051758, h = 223, unknown1 = 1048578},
            ['10'] = { index = 17, zone = 289, npc = 761, offset = 17, x = 186.00001525879, z = -71.850006103516, y = 514.5, h = 95, unknown1 = 1114114},
            ['11'] = { index = 18, zone = 289, npc = 762, offset = 18, x = 444.50003051758, z = -40, y = 144, h = 127, unknown1 = 1179650},
            ['12'] = { index = 19, zone = 289, npc = 763, offset = 19, x = 454.50003051758, z = -3.6000001430511, y = -147.5, h = 0, unknown1 = 1245186},
            ['13'] = { index = 20, zone = 289, npc = 764, offset = 20, x = 546.5, z = -71.5, y = -17, h = 127, unknown1 = 1310722},
            ['14'] = { index = 21, zone = 289, npc = 765, offset = 21, x = 275, z = -40.500003814697, y = -377.50003051758, h = 159, unknown1 = 1376258},
            ['15'] = { index = 22, zone = 289, npc = 766, offset = 22, x = -1.2000000476837, z = -52.000003814697, y = -581.5, h = 191, unknown1 = 1441794},
            --elvorseal x = 0, z = -43.600002288818, y = -238.00001525879, h = 48897, unknown1 = 12
        },
        ['Reisenjima'] = T{
            ['1'] = {  index = 23, zone = 291, npc = 826, offset = 23, x = -495.44003295898, z = -19, y = -476.48001098633, h = 0, unknown1 = 1507330},
            ['2'] = {  index = 24, zone = 291, npc = 827, offset = 24, x = -404.00003051758, z = -55.000003814697, y = 86.000007629395, h = 63, unknown1 = 1572866},
            ['3'] = {  index = 25, zone = 291, npc = 828, offset = 25, x = -530.40002441406, z = -50.000003814697, y = 399.75003051758, h = 95, unknown1 = 1638402},
            ['4'] = {  index = 26, zone = 291, npc = 829, offset = 26, x = -554.40002441406, z = -48.750003814697, y = 602, h = 191, unknown1 = 1703938},
            ['5'] = {  index = 27, zone = 291, npc = 830, offset = 27, x = 107.00000762939, z = -75.400001525879, y = 599, h = 63, unknown1 = 1769474},
            ['6'] = {  index = 28, zone = 291, npc = 831, offset = 28, x = 243.50001525879, z = -87.400001525879, y = 106.00000762939, h = 127, unknown1 = 1835010},
            ['7'] = {  index = 29, zone = 291, npc = 832, offset = 29, x = 641.60003662109, z = -374.00003051758, y = -912.20007324219, h = 159, unknown1 = 1900546},
            ['8'] = {  index = 30, zone = 291, npc = 833, x = -368.72003173828, z = -113.30000305176, y = 212.45001220703, h = 63, unknown1 = 1966082},
            ['9'] = {  index = 31, zone = 291, npc = 834, offset = 31, x = -581, z = -417.40002441406, y = -1065, h = 0, unknown1 = 2031618},
            ['10'] = { index = 32, zone = 291, npc = 835, x = -390.22003173828, z = -439.71002197266, y = -835.13006591797, h = 0, unknown1 = 2097156},
            --elvorseal x = 640, z = -372.00003051758, y = -921.00006103516, h = 24321, unknown1 = 12
        },
    },
}
end,
-- ======================================================== abyssea
['abyssea'] = function()
local warp_zones = S{ 232, 236, 240, 246, 243, 242 } -- ports + ru'lude and heaven's tower
local entry_zones = S{ 102, 108, 117, 118, 103, 104, 107, 106, 112, 126} 
local teleport_npcs = S{ "Ernst", "Ivan", "Willis", "Horst", "Kierron", "Vincent"}
local abyssea_zones = S{ 15, 45, 132, 215, 216, 217, 218, 253, 254, 255}
local all_warp_zones = S{232, 236, 240, 246, 243, 242, 102, 108, 117, 118, 103, 104, 107, 106, 112, 15, 45, 132, 215, 216, 217, 218, 253, 254, 255, 126}
local aby_menu_ids = S{404,795,873,339,433,10185,107,100,218,61,55,47,914,204,908,200,2132,2133,2134,2135,2136,2137,2138,2139,123,200,46}
local target_ids = S{17199772,17203935,17212109}
local npc_names = T{
    warp = S{'Veridical Conflux', 'Ernst', 'Ivan', 'Willis', 'Horst', 'Kierron', 'Vincent'},
    enter = S{'Cavernous Maw','Transcendental Radiance'},
    exit = S{'Cavernous Maw'},
}
return T{
    short_name = {'ab','aa'},
    long_name = 'Abyssea',
    npc_plural = 'abyssean npcs',
    npc_names = npc_names,
    abyssea_zones = abyssea_zones,
    all_warp_zones = all_warp_zones,
    target_ids = target_ids,
    zone_npc_list = function(type)
        local mlist = windower.ffxi.get_mob_list()
        mlist = table.filter(mlist, function(name)
            return name ~= "" and npc_names[type]:any(string.startswith+{name})
        end)
        mlist = table.map(mlist, function(name)
            local num = name:match('%d+$')
            return {name=name, key=(num and tostring(num))}
        end)
        return mlist
    end,
    validate = function(menu_id, zone, current_activity, p)
        local destination = current_activity.activity_settings
        local npcindex = p['NPC Index']
        if current_activity.sub_cmd ~= 'exit' and current_activity.sub_cmd ~= 'enter' then
            if abyssea_zones:contains(zone) then
                if npcindex == destination.npcindex then
                    return "You are already at that location."
                end
            end
        end
                -- npc warps:
        if not aby_menu_ids:contains(menu_id) then
            return "Incorrect menu detected! Menu ID: "..menu_id
        end
        if current_activity.sub_cmd == 'enter' and not entry_zones:contains(zone) then
            return "Not in an entry zone!"
        end
        if current_activity.sub_cmd == 'exit' and not abyssea_zones:contains(zone) then
            return "Not in an Abyssea zone!"
        end
        return nil
    end,
    missing = function(warpdata, zone, p)
        local missing = T{}
        local unlock_bit_start = 128

        local zd = nil
        if zone == 15 then zd = warpdata[ 'Abyssea - Konschtat' ] end
        if zone == 45 then zd = warpdata[ 'Abyssea - Tahrongi' ] end
        if zone == 132 then zd = warpdata[ 'Abyssea - La Theine' ] end
        if zone == 215 then zd = warpdata[ 'Abyssea - Attohwa' ] end
        if zone == 216 then zd = warpdata[ 'Abyssea - Misareaux' ] end
        if zone == 217 then zd = warpdata[ 'Abyssea - Vunkerl' ] end
        if zone == 218 then zd = warpdata[ 'Abyssea - Altepa' ] end
        if zone == 253 then zd = warpdata[ 'Abyssea - Uleguerand' ] end
        if zone == 254 then zd = warpdata[ 'Abyssea - Grauberg' ] end
        if zd == nil then
            return nil, 'You cannot check missing destinations from here.'
        end

        for d, dd in pairs(zd) do
            if not dd.shortcut and dd.offset then
                if not has_bit(p["Menu Parameters"], unlock_bit_start + dd.offset) then
                    missing:append(z..'-'..d)
                end
            end
        end
        return missing
    end,
    help_text = "| Abyssea |\n Command options [ab, aa]\n- ab conflux number -- warp to a designated conflux in your current abyssea zone.\n- ab enter -- enter the abyssea zone corresponding to the entrance zone.\n- ab exit -- exit the abyssea zone.\n-----------------------------",
    sub_zone_targets =  S{'00', '0', '1', '2', '3', '4', '5', '6', '7', '8', 'Cavernous Maw'},
    auto_select_zone = function(zone)
        if zone == 15 then return 'Abyssea - Konschtat' end
        if zone == 45 then return 'Abyssea - Tahrongi' end
        if zone == 132 then return 'Abyssea - La Theine' end
        if zone == 215 then return 'Abyssea - Attohwa' end
        if zone == 216 then return 'Abyssea - Misareaux' end
        if zone == 217 then return 'Abyssea - Vunkerl' end
        if zone == 218 then return 'Abyssea - Altepa' end
        if zone == 253 then return 'Abyssea - Uleguerand' end
        if zone == 254 then return 'Abyssea - Grauberg' end
    end,
    auto_select_sub_zone = function(zone)
        if warp_zones:contains(zone) then return 'Cavernous Maw' end
    end,
    build_warp_packets = function(current_activity, zone, p, settings)
        local actions = T{}
        local packet = nil
        local menu = p["Menu ID"]
        local npc = current_activity.npc
        local destination = current_activity.activity_settings
        if zone == destination.zone then

            -- have xyz data and within zone. must be conflux.
            local cruor = p["Menu Parameters"]:unpack('I', 29)

            debug("cruor: "..cruor)

            if cruor < 200 then
                packet = packets.new('outgoing', 0x05B)
                packet["Target"] = npc.id
                packet["Option Index"] = 0
                packet["_unknown1"] = 16384
                packet["Target Index"] = npc.index
                packet["Automated Message"] = false
                packet["_unknown2"] = 0
                packet["Zone"] = zone
                packet["Menu ID"] = menu
                actions:append(T{packet=packet, description='cancel menu', message='Not enough cruor!'})
                return actions
            end

            local unlock_bit_start = 128

            local destination_unlocked = false
            if destination.offset ~= nil then
                destination_unlocked = has_bit(p["Menu Parameters"], unlock_bit_start + destination.offset)
            --elseif destination.invoffset then
            --    destination_unlocked = not has_bit(p["Menu Parameters"], unlock_bit_start + destination.invoffset)
            end

            debug('zone is unlocked: '..tostring(destination_unlocked))

            if not destination_unlocked then
                packet = packets.new('outgoing', 0x05B)
                packet["Target"] = npc.id
                packet["Option Index"] = 0
                packet["_unknown1"] = 16384
                packet["Target Index"] = npc.index
                packet["Automated Message"] = false
                packet["_unknown2"] = 0
                packet["Zone"] = zone
                packet["Menu ID"] = menu
                actions:append(T{packet=packet, description='cancel menu', message='Destination Conflux is not unlocked yet!'})
                return actions
            end

            -- request map
            --packet = packets.new('outgoing', 0x114)
            --packet.debug_desc = 'request map'
            --actions:append(packet)

            -- menu change
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = 1
            packet["_unknown1"] = destination.index
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, description='send options'})

            -- request in-zone warp
            packet = packets.new('outgoing', 0x05C)
            packet["Target ID"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["X"] = destination.x
            packet["Y"] = destination.y
            packet["Z"] = destination.z
            packet["_unknown1"] = destination.unknown1
            packet["Rotation"] = destination.h
            actions:append(T{packet=packet, wait_packet=0x05C, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='same-zone move request'})

            -- complete menu
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Target Index"] = npc.index
            packet["Zone"] = zone
            packet["Menu ID"] = menu

            packet["Option Index"] = destination.index
            packet["_unknown1"] = 0
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            actions:append(T{packet=packet, wait_packet=0x05C, expecting_zone=false, delay=1, description='complete menu'})
            
        else
            -- no xyz data, must be a zone warp.
            local cruor = p["Menu Parameters"]:unpack('i', 5)

            debug("cruor: "..cruor)

            if cruor < 200 then
                packet = packets.new('outgoing', 0x05B)
                packet["Target"] = npc.id
                packet["Option Index"] = 0
                packet["_unknown1"] = 16384
                packet["Target Index"] = npc.index
                packet["Automated Message"] = false
                packet["_unknown2"] = 0
                packet["Zone"] = zone
                packet["Menu ID"] = menu
                actions:append(T{packet=packet, description='cancel menu', message='Not enough cruor!'})
                return actions
            end


            local unlock_bit_start = 0

            local destination_unlocked = false
            if destination.offset ~= nil then
                destination_unlocked = has_bit(p["Menu Parameters"], unlock_bit_start + destination.offset)
            --elseif destination.invoffset then
            --    destination_unlocked = not has_bit(p["Menu Parameters"], unlock_bit_start + destination.invoffset)
            end

            debug('zone is unlocked: '..tostring(destination_unlocked))

            if not destination_unlocked then
                packet = packets.new('outgoing', 0x05B)
                packet["Target"] = npc.id
                packet["Option Index"] = 0
                packet["_unknown1"] = 16384
                packet["Target Index"] = npc.index
                packet["Automated Message"] = false
                packet["_unknown2"] = 0
                packet["Zone"] = zone
                packet["Menu ID"] = menu
                actions:append(T{packet=packet, description='cancel menu', message='Destination Zone is not unlocked yet!'})
                return actions
            end

            -- update request
            packet = packets.new('outgoing', 0x016)
            packet["Target Index"] = windower.ffxi.get_player().index
            actions:append(T{packet=packet, description='update request'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = destination.index
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = destination.index
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, wait_packet=0x05C, expecting_zone=true, delay=1, description='send options and complete menu'})
        end

        return actions
    end,
    sub_commands = {
        enter = function(current_activity, zone, p, settings)
            local actions = T{}
            local packet = nil
            local menu = p["Menu ID"]
            local npc = current_activity.npc

            
            -- update request
            packet = packets.new('outgoing', 0x016)
            packet["Target Index"] = windower.ffxi.get_player().index
            actions:append(T{packet=packet, description='update request'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='send options'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 1
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, wait_packet=0x05C, expecting_zone=true, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='complete menu', message='Entering Abyssea'})

            return actions
        end,
        exit = function(current_activity, zone, p, settings)
            local actions = T{}
            local packet = nil
            local menu = p["Menu ID"]
            local npc = current_activity.npc


                -- update request
            packet = packets.new('outgoing', 0x016)
            packet["Target Index"] = windower.ffxi.get_player().index
            actions:append(T{packet=packet, description='update request'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='send options'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 1
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, wait_packet=0x052, expecting_zone=true, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='complete menu', message='Leaving Abyssea'})

            return actions
        end,
    },
    warpdata = T{
        ['Abyssea - La Theine'] = T{
            ['Cavernous Maw'] = { index = 260, offset=64 }, 
            ['1'] = { index = 1, zone = 132, npcindex = 702, npc = 701, offset=0, x = -480.00003051758, z = -0.40000000596046, y = 764.00006103516, h = 63, unknown1 = 65538},
            ['2'] = { index = 2, zone = 132, npcindex = 703, npc = 702, offset=1, x = -593.81103515625, z = -16.300001144409, y = 30.151000976563, h = 180, unknown1 = 131074},
            ['3'] = { index = 3, zone = 132, npcindex = 704, npc = 703, offset=2, x = -122.96600341797, z = -8.6000003814697, y = -38.954002380371, h = 31, unknown1 = 196610},
            ['4'] = { index = 4, zone = 132, npcindex = 705, npc = 704, offset=3, x = -54.61600112915, z = 29.200000762939, y = 175.25001525879, h = 244, unknown1 = 262146},
            ['5'] = { index = 5, zone = 132, npcindex = 706, npc = 705, offset=4, x = 201.68101501465, z = 23.300001144409, y = -398.15502929688, h = 100, unknown1 = 327682},
            ['6'] = { index = 6, zone = 132, npcindex = 707, npc = 706, offset=5, x = 595.37701416016, z = 39.400001525879, y = -507.18603515625, h = 10, unknown1 = 393218},
            ['7'] = { index = 7, zone = 132, npcindex = 708, npc = 707, offset=6, x = 494.22302246094, z = 39.600002288818, y = 333.0940246582, h = 112, unknown1 = 458754},
            ['8'] = { index = 8, zone = 132, npcindex = 709, npc = 708, offset=7, x = 215.14500427246, z = 15.800001144409, y = -198.91801452637, h = 53, unknown1 = 524290},
        },
        ['Abyssea - Konschtat'] = T{
            ['Cavernous Maw'] = { index = 264, offset=65 }, 
            ['1'] = { index = 1, zone = 15, npcindex = 539, npc = 538, offset=0, x = 126.00000762939, z = -72.800003051758, y = -834.00006103516, h = 223, unknown1 = 65538},
            ['2'] = { index = 2, zone = 15, npcindex = 540, npc = 539, offset=1, x = -164.00001525879, z = -32.700000762939, y = -276, h = 159, unknown1 = 131074},
            ['3'] = { index = 3, zone = 15, npcindex = 541, npc = 540, offset=2, x = -644.00006103516, z = -0.70000004768372, y = 124.00000762939, h = 159, unknown1 = 196610},
            ['4'] = { index = 4, zone = 15, npcindex = 542, npc = 541, offset=3, x = 20, z = 8.7000007629395, y = 45.000003814697, h = 191, unknown1 = 262146},
            ['5'] = { index = 5, zone = 15, npcindex = 543, npc = 542, offset=4, x = -125.00000762939, z = 15.200000762939, y = 282, h = 127, unknown1 = 327682},
            ['6'] = { index = 6, zone = 15, npcindex = 544, npc = 543, offset=5, x = -316, z = 47.100002288818, y = 564, h = 223, unknown1 = 393218},
            ['7'] = { index = 7, zone = 15, npcindex = 545, npc = 544, offset=6, x = 476.00003051758, z = 7.3000001907349, y = 124.00000762939, h = 159, unknown1 = 458754},
            ['8'] = { index = 8, zone = 15, npcindex = 546, npc = 545, offset=7, x = 244.00001525879, z = 39.200000762939, y = 636, h = 31, unknown1 = 524290},
        },
        ['Abyssea - Tahrongi'] = T{
            ['Cavernous Maw'] = { index = 268, offset=66 }, 
            ['1'] = { index = 1, zone = 45, npcindex = 536, npc = 535, offset=0, x = 7.826000213623, z = 31.515001296997, y = -636.83404541016, h = 81, unknown1 = 65538},
            ['2'] = { index = 2, zone = 45, npcindex = 537, npc = 536, offset=1, x = 24.010000228882, z = -16.682001113892, y = -171.58700561523, h = 162, unknown1 = 131074},
            ['3'] = { index = 3, zone = 45, npcindex = 538, npc = 537, offset=2, x = -290.78402709961, z = -25.574001312256, y = -171.65501403809, h = 201, unknown1 = 196610},
            ['4'] = { index = 4, zone = 45, npcindex = 539, npc = 538, offset=3, x = -239.86801147461, z = 7.4700002670288, y = 166.16600036621, h = 76, unknown1 = 262146},
            ['5'] = { index = 5, zone = 45, npcindex = 540, npc = 539, offset=4, x = -56.126003265381, z = 31.085000991821, y = 547.42602539063, h = 150, unknown1 = 327682},
            ['6'] = { index = 6, zone = 45, npcindex = 541, npc = 540, offset=5, x = -64.581001281738, z = 36.774002075195, y = 331.84002685547, h = 39, unknown1 = 393218},
            ['7'] = { index = 7, zone = 45, npcindex = 542, npc = 541, offset=6, x = 120.1490020752, z = 15.776000976563, y = 155.14100646973, h = 177, unknown1 = 458754},
            ['8'] = { index = 8, zone = 45, npcindex = 543, npc = 542, offset=7, x = 324.22500610352, z = 39.661003112793, y = 433.3330078125, h = 159, unknown1 = 524290},
        },
        ['Abyssea - Vunkerl'] = T{
            ['Cavernous Maw'] = { index = 272, offset=96 }, 
            ['1'] = { index = 1, zone = 217, npcindex = 648, npc = 648, offset=0, x = -322.00003051758, z = -40.523002624512, y = 676.00006103516, h = 127, unknown1 = 65538},
            ['2'] = { index = 2, zone = 217, npcindex = 649, npc = 649, offset=1, x = -24.502000808716, z = -34.138999938965, y = 370.20001220703, h = 95, unknown1 = 131074},
            ['3'] = { index = 3, zone = 217, npcindex = 650, npc = 650, offset=2, x = 202.53201293945, z = -31.807001113892, y = 312.14300537109, h = 159, unknown1 = 196610},
            ['4'] = { index = 4, zone = 217, npcindex = 651, npc = 651, offset=3, x = -266.89801025391, z = -41.942001342773, y = -111.42200469971, h = 63, unknown1 = 262146},
            ['5'] = { index = 5, zone = 217, npcindex = 652, npc = 652, offset=4, x = -118.68200683594, z = -39.89400100708, y = -477.37503051758, h = 0, unknown1 = 327682},
            ['6'] = { index = 6, zone = 217, npcindex = 653, npc = 653, offset=5, x = -100.00000762939, z = -56.000003814697, y = -764.01605224609, h = 159, unknown1 = 393218},
            ['7'] = { index = 7, zone = 217, npcindex = 654, npc = 654, offset=6, x = -675.13201904297, z = -45.693000793457, y = -555.55200195313, h = 223, unknown1 = 458754},
            ['8'] = { index = 8, zone = 217, npcindex = 655, npc = 655, offset=7, x = -291.04000854492, z = -32.020999908447, y = 282.5710144043, h = 127, unknown1 = 524290},
            ['00'] = { index = 9, zone = 217, npcindex = 667, npc = 667, offset=8, x = 158, z = -38.100002288818, y = -158, h = 159, unknown1 = 589826},
        },
        ['Abyssea - Misareaux'] = T{
            ['Cavernous Maw'] = { index = 276, offset=97 }, 
            ['1'] = { index = 1, zone = 216, npcindex = 724, npc = 723, offset=0, x = 634, z = -16.5, y = 286, h = 159, unknown1 = 65538},
            ['2'] = { index = 2, zone = 216, npcindex = 725, npc = 724, offset=1, x = 399.44900512695, z = -6.7550001144409, y = 33.19100189209, h = 156, unknown1 = 131074},
            ['3'] = { index = 3, zone = 216, npcindex = 726, npc = 725, offset=2, x = -96.818000793457, z = -33.828002929688, y = 254.32000732422, h = 249, unknown1 = 196610},
            ['4'] = { index = 4, zone = 216, npcindex = 727, npc = 726, offset=3, x = 141.42300415039, z = -10.116000175476, y = -222.39100646973, h = 95, unknown1 = 262146},
            ['5'] = { index = 5, zone = 216, npcindex = 728, npc = 727, offset=4, x = -40.898002624512, z = -24.068000793457, y = 439.29000854492, h = 193, unknown1 = 327682},
            ['6'] = { index = 6, zone = 216, npcindex = 729, npc = 728, offset=5, x = -231.25300598145, z = -32.804000854492, y = 208.75801086426, h = 128, unknown1 = 393218},
            ['7'] = { index = 7, zone = 216, npcindex = 730, npc = 729, offset=6, x = 288.97399902344, z = 23.489000320435, y = -407.23400878906, h = 193, unknown1 = 458754},
            ['8'] = { index = 8, zone = 216, npcindex = 731, npc = 730, offset=7, x = 648.31103515625, z = -0.016000000759959, y = -476.11102294922, h = 31, unknown1 = 524290},
            ['00'] = { index = 9, zone = 216, npcindex = 743, npc = 742, offset=8, x = 276, z = -16.342000961304, y = 236.00001525879, h = 63, unknown1 = 589826},
        },
        ['Abyssea - Attohwa'] = T{
            ['Cavernous Maw'] = { index = 280, offset=98 }, 
            ['1'] = { index = 1, zone = 215, npcindex = 615, npc = 614, offset=0, x = -140, z = 19.5, y = -200.00001525879, h = 191, unknown1 = 65538},
            ['2'] = { index = 2, zone = 215, npcindex = 616, npc = 615, offset=1, x = -485.50402832031, z = -3.996000289917, y = -4.9400000572205, h = 223, unknown1 = 131074},
            ['3'] = { index = 3, zone = 215, npcindex = 617, npc = 616, offset=2, x = 258.90902709961, z = 20.94100189209, y = -21.157001495361, h = 131, unknown1 = 196610},
            ['4'] = { index = 4, zone = 215, npcindex = 618, npc = 617, offset=3, x = -603.87701416016, z = -4.3210000991821, y = 191.93600463867, h = 0, unknown1 = 262146},
            ['5'] = { index = 5, zone = 215, npcindex = 619, npc = 618, offset=4, x = 466.83102416992, z = 20.555000305176, y = 78.005004882813, h = 191, unknown1 = 327682},
            ['6'] = { index = 6, zone = 215, npcindex = 620, npc = 619, offset=5, x = -247.10301208496, z = 13.979001045227, y = 283.57202148438, h = 62, unknown1 = 393218},
            ['7'] = { index = 7, zone = 215, npcindex = 621, npc = 620, offset=6, x = 378.84503173828, z = 20, y = -141.94599914551, h = 181, unknown1 = 458754},
            ['8'] = { index = 8, zone = 215, npcindex = 622, npc = 621, offset=7, x = 1.4460000991821, z = -3.6520001888275, y = 150.79200744629, h = 191, unknown1 = 524290},
            ['00'] = { index = 9,zone = 215, npcindex = 634, npc = 633, offset=8, x = -280, z = -4.5, y = 0, h = 191, unknown1 = 589826},
        },
        ['Abyssea - Altepa'] = T{
            ['Cavernous Maw'] = { index = 284, offset=128 }, 
            ['1'] = { index = 1, zone = 218, npcindex = 564, npc = 563, offset=0, x = 404.00003051758, z = -0.30000001192093, y = 288, h = 127, unknown1 = 65538},
            ['2'] = { index = 2, zone = 218, npcindex = 565, npc = 564, offset=1, x = 639, z = 0, y = -126.00000762939, h = 159, unknown1 = 131074},
            ['3'] = { index = 3, zone = 218, npcindex = 566, npc = 565, offset=2, x = -80, z = 0, y = 437.00003051758, h = 63, unknown1 = 196610},
            ['4'] = { index = 4, zone = 218, npcindex = 567, npc = 566, offset=3, x = -323.00003051758, z = 0.87800002098083, y = -263, h = 31, unknown1 = 262146},
            ['5'] = { index = 5, zone = 218, npcindex = 568, npc = 567, offset=4, x = -477.00003051758, z = -1, y = -684.00006103516, h = 191, unknown1 = 327682},
            ['6'] = { index = 6, zone = 218, npcindex = 569, npc = 568, offset=5, x = -640, z = 0, y = -242.00001525879, h = 79, unknown1 = 393218},
            ['7'] = { index = 7, zone = 218, npcindex = 570, npc = 569, offset=6, x = -604, z = -1, y = -39, h = 0, unknown1 = 458754},
            ['8'] = { index = 8, zone = 218, npcindex = 571, npc = 570, offset=7, x = -826.00006103516, z = -10, y = -591, h = 159, unknown1 = 524290},
        },
        ['Abyssea - Uleguerand'] = T{
            ['Cavernous Maw'] = { index = 288, offset=129 }, 
            ['1'] = { index = 1, zone = 253, npcindex = 564, npc = 563, offset=0, x = -202.00001525879, z = -39.900001525879, y = -506.00003051758, h = 31, unknown1 = 65538},
            ['2'] = { index = 2, zone = 253, npcindex = 565, npc = 564, offset=1, x = -381.05502319336, z = -25.283000946045, y = -169.20001220703, h = 204, unknown1 = 131074},
            ['3'] = { index = 3, zone = 253, npcindex = 566, npc = 565, offset=2, x = -300.77301025391, z = -53.509002685547, y = -34.171001434326, h = 58, unknown1 = 196610},
            ['4'] = { index = 4, zone = 253, npcindex = 567, npc = 566, offset=3, x = 137.36601257324, z = 0.10000000149012, y = -368.51901245117, h = 243, unknown1 = 262146},
            ['5'] = { index = 5, zone = 253, npcindex = 568, npc = 567, offset=4, x = 576.00805664063, z = -36.076000213623, y = -8.3860006332397, h = 228, unknown1 = 327682},
            ['6'] = { index = 6, zone = 253, npcindex = 569, npc = 568, offset=5, x = 338.86001586914, z = -100.28800201416, y = 500.10900878906, h = 90, unknown1 = 393218},
            ['7'] = { index = 7, zone = 253, npcindex = 570, npc = 569, offset=6, x = -257.35900878906, z = -176.33500671387, y = 236.791015625, h = 23, unknown1 = 458754},
            ['8'] = { index = 8, zone = 253, npcindex = 571, npc = 570, offset=7, x = -582.97705078125, z = -40.378002166748, y = 45.543003082275, h = 89, unknown1 = 524290},
        },
        ['Abyssea - Grauberg'] = T{
            ['Cavernous Maw'] = { index = 292, offset=130 }, 
            ['1'] = { index = 1, zone = 254, npcindex = 600, npc = 599, offset=0, x = -514, z = 22.417001724243, y = -756.00006103516, h = 63, unknown1 = 65538},
            ['2'] = { index = 2, zone = 254, npcindex = 601, npc = 600, offset=1, x = 321.8330078125, z = 31.439001083374, y = -557.98303222656, h = 93, unknown1 = 131074},
            ['3'] = { index = 3, zone = 254, npcindex = 602, npc = 601, offset=2, x = 423.95001220703, z = -0.89300006628036, y = -174.13000488281, h = 159, unknown1 = 196610},
            ['4'] = { index = 4, zone = 254, npcindex = 603, npc = 602, offset=3, x = -26.465002059937, z = -0.93500006198883, y = -464.54602050781, h = 127, unknown1 = 262146},
            ['5'] = { index = 5, zone = 254, npcindex = 604, npc = 603, offset=4, x = -165.41400146484, z = -32.099002838135, y = 405.60803222656, h = 137, unknown1 = 327682},
            ['6'] = { index = 6, zone = 254, npcindex = 605, npc = 604, offset=5, x = 102.16500854492, z = 16.461999893188, y = 497.28903198242, h = 254, unknown1 = 393218},
            ['7'] = { index = 7, zone = 254, npcindex = 606, npc = 605, offset=6, x = -323.07302856445, z = -127.96900939941, y = 113.65300750732, h = 63, unknown1 = 458754},
            ['8'] = { index = 8, zone = 254, npcindex = 607, npc = 606, offset=7, x = 490.77603149414, z = -5.5460004806519, y = 340.56301879883, h = 191, unknown1 = 524290},
        },
    },
}
end,
-- ======================================================== portals
['portals'] = function()
local npc_names = T{
    warp = S{'Runic Portal'},
    ['return'] = S{'Runic Portal'},
    assault = S{'Runic Portal'},
}
return T{
    short_name = {'po','ps'},
    long_name = 'Runic portal',
    npc_plural = 'runic portals',
    npc_names = npc_names,
    zone_npc_list = function(type)
        local mlist = windower.ffxi.get_mob_list()
        mlist = table.filter(mlist, function(name)
            return name ~= "" and npc_names[type]:any(string.startswith+{name})
        end)
        mlist = table.map(mlist, function(name)
            return {name=name}
        end)
        return mlist
    end,
    validate = function(menu_id, zone, current_activity)
        if (current_activity.sub_cmd == nil or current_activity.sub_cmd == 'assault') and zone ~= 50 then
            return "Not in Whitegate!"
        end
        if current_activity.sub_cmd == 'return' and not S{79, 52, 61, 54, 72}:contains(zone) then
            return "Not in an assault staging point!"
        end
        if not (menu_id == 101 or -- no assaults

               (menu_id >= 120 and menu_id <= 215) or -- assaults.

               menu_id == 131 or -- Leujaoam
               menu_id == 134 or -- Periqia
               menu_id == 109 or -- mamool Ja
               menu_id == 109 or -- Lebros
               menu_id == 109 or -- Ilrusi
               menu_id == 117 or menu_id == 118) then -- Nyzul 
            return "Incorrect menu detected! Menu ID: "..menu_id
        end

        if current_activity.sub_cmd == nil and menu_id ~= 101 then
            return "Assault orders active. Use \"po assault\" to be taken to your assault destination."
        end
        if current_activity.sub_cmd == 'assault' and menu_id == 101 then
            return "No assault orders active."
        end
        return nil
    end,
    missing = function(warpdata, zone, p)
        local missing = T{}
        local unlock_bit_start = 32

        if zone ~= 50 then
            return nil, 'You cannot check missing destinations from here.'
        end

        for z, zd in pairs(warpdata) do
            if not zd.shortcut then
                if zd.index then
                    if not has_bit(p["Menu Parameters"], unlock_bit_start + zd.index) then
                        missing:append(z)
                    end
                end
            end
        end
        return missing
    end,
    help_text = "| Portals |\n Command options [po, ps]\n- po staging point -- warp to a designated staging point.\n- po return -- Return to Whitegate from the staging point.\n- po assault -- Head to your current assault tag location.\n-----------------------------",
    sub_zone_targets =  nil,
    auto_select_zone = function(zone)
    end,
    build_warp_packets = function(current_activity, zone, p, settings)
        local actions = T{}
        local packet = nil
        local menu = p["Menu ID"]
        local npc = current_activity.npc
        local destination = current_activity.activity_settings

        local is_stock = p["Menu Parameters"]:unpack('i', 13)
        local captain = p["Menu Parameters"]:unpack('b4', 17) == 1
        local unlock_bit_start = 32

        local portal_unlocked = has_bit(p["Menu Parameters"], unlock_bit_start + destination.index)
        debug('portal unlocked: '..tostring(portal_unlocked))

        if not portal_unlocked then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Destination Runic Portal is not unlocked yet!'})
            return actions
        end

        debug('captain: '..tostring(captain)..' imperial standing: '..is_stock)
        if not captain and is_stock < 200 then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Not enough Imperial Standing!'})
            return actions
        end

        local option = destination.index
        if not captain then
            option = option + 1000 -- use IS if not captain.
        end
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Option Index"] = option
        packet["_unknown1"] = 0
        packet["Target Index"] = npc.index
        packet["Automated Message"] = false
        packet["_unknown2"] = 0
        packet["Zone"] = zone
        packet["Menu ID"] = menu
        actions:append(T{packet=packet, delay=1+wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='warp to staging point'})

        return actions
    end,
    sub_commands = {
        ['return'] = function(current_activity, zone, p, settings)
            local actions = T{}
            local packet = nil
            local menu = p['Menu ID']
            local npc = current_activity.npc

            log("Returning to Whitegate...")

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='change menu'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 1
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, delay=1+wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='warp to whitegate'})

            return actions
        end,
        assault = function(current_activity, zone, p, settings)
            local actions = T{}
            local packet = nil
            local menu = p['Menu ID']
            local npc = current_activity.npc

            log("Warping to assault orders staging point...")            

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 1
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, delay=1+wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='warp to staging point'})
            
            return actions
        end,
    },
    warpdata = T{
        ['Azouph Isle'] = T{ index = 1},
        ['Leujaoam Sanctum'] = T{ index = 1},

        ['Dvucca Isle'] = T{ index = 2},
        ['Periqia'] = T{ index = 2},

        ['Mamool Ja Training Grounds'] = T{ index = 3},

        ['Halvung'] = T{ index = 4},
        ['Lebros Caverns'] = T{ index = 4},

        ['Ilrusi Atoll'] = T{ index = 5},

        ['Nyzul Isle'] = T{ index = 6},
    },
}
end,
-- ======================================================== campaign
['campaign'] = function()
local past_zones = S{80,81,82,83,84,87,88,89,90,91,94,95,96,97,98,136,137,164,171,175}
local past_town_zones = S{80,87,94}
local all_warp_zones = S{80,81,82,83,84,87,88,89,90,91,94,95,96,97,98,136,137,164,171,175,115,119,120,101,104,105,106,109,110}
local menu_ids = S{454,455,456,457,458}
local maw_menu_ids = S{101,102,103,903,904,905,910}
local target_ids = S{17212104,17203886}
local npc_names = T{
    warp = S{'Scarlette, C.A.', 'Wenonah, C.A.', 'Narkissa, C.A.'},
    ['return'] = S{'Estaud','Sleiney','Timid Scorpion','Yimi Jomkeh','Disserond','Gray Colossus','Moana','Luk Leotih','Myllue','Telford','Gisbert','Wayward Echo','Hdya Mhirako','Marius','Larkin','Roiloux','Stray Boar','Barnett','Dhen Kwherri','Kearney','Felicia','Toulsard','Polished Fang','Xenia','Lamurara','Wren','Arlayse','Waldo','Jagged Onyx','Uriah','Addison','Mhik Ljusihlo','Darden','Tomoa-Nomoa','Astrid','Landon','Amaliya','Renvriche'},
    port = S{'Cavernous Maw'}, -- travel through cav. maws 2-way, 1-cmd. Backward and forward in time.
}
return T{
    short_name = {'ca','cn'},
    long_name = 'Campaign',
    npc_plural = 'Campaign NPCs',
    npc_names = npc_names,
    all_warp_zones = all_warp_zones,
    target_ids = target_ids,
    zone_npc_list = function(type)
        local mlist = windower.ffxi.get_mob_list()
        mlist = table.filter(mlist, function(name)
            return name ~= "" and npc_names[type]:any(string.startswith+{name})
        end)
        mlist = table.map(mlist, function(name)
            return {name=name}
        end)
        return mlist
    end,
    validate = function(menu_id, zone, current_activity,p)
        local destination = current_activity.activity_settings
        allied_notes = p["Menu Parameters"] and p["Menu Parameters"]:unpack('I', 9)
        local warp_cost = 40 --Minimum check, warp costs vary and it gets checked again along with the destination locks.
        if allied_notes and allied_notes < warp_cost then
            return "You have less than 40 Allied Notes."
        end
        if current_activity.sub_cmd ~= 'port' then 
            if not menu_ids:contains(menu_id) then
                return "Incorrect menu detected! Menu ID: "..menu_id
            end
            if past_town_zones:contains(zone) and menu_id ~= 458 then
                return "Incorrect menu ID detected, Campaign teleports not possible."
            end
            if not past_zones:contains(zone) then
                return 'Not in past town zone.'
            end
        elseif current_activity.sub_cmd == 'port' and not maw_menu_ids:contains(menu_id) then
            return "Wrong menu."
        end
        return nil
    end,
    missing = function(warpdata, zone, p, secondcall)
        -- Little tricky since the unlocks are handled different from any other map. Two calls, one to trigger the 5C and another for the operation.
        if not secondcall then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = p['NPC']
            packet["Option Index"] = 50
            packet["_unknown1"] = 0
            packet["Target Index"] = p['NPC Index']
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = p["Menu ID"]
            packets.inject(packet)
        elseif secondcall then
            local missing = T{}
            local unlock_bits = p["Menu Parameters"]:unpack('I', 1)

            for z, zd in pairs(warpdata) do
                if not zd.shortcut then
                    if zd.permission then
                        if bit.band(unlock_bits, zd.permission) ~= 0 then

                        else
                            missing:append(z)
                        end
                    end
                end
            end
            return missing
        end
    end,
    help_text = "| Campaign |\n Command options [ca, cn]\n- ca zone name -- warp to a designated [S] zone via a Campaign Arbiter in a [S] city.\n- ca return -- return to your [S] home nation. via any [S] 2 initial field NPC i.e. Amaliya, C.A.\n- ca port -- teleport to the other side of [S] Cavernous Maws.\n-----------------------------",
    sub_zone_targets = S{},
    build_warp_packets = function(current_activity, zone, p, settings)
        local actions = T{}
        local packet = nil
        local menu = p["Menu ID"]
        local npc = current_activity.npc
        local destination = current_activity.activity_settings

        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Option Index"] = 50
        packet["_unknown1"] = 0
        packet["Target Index"] = npc.index
        packet["Automated Message"] = true
        packet["_unknown2"] = 0
        packet["Zone"] = zone
        packet["Menu ID"] = menu
        actions:append(T{packet=packet, delay = wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options'})

        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Option Index"] = destination.oi
        packet["_unknown1"] = 0
        packet["Target Index"] = npc.index
        packet["Automated Message"] = true
        packet["_unknown2"] = 0
        packet["Zone"] = zone
        packet["Menu ID"] = menu
        actions:append(T{packet=packet, wait_packet=0x05C, delay = wiggle_value(settings.simulated_response_time, settings.simulated_response_variation) + 1, description='send options'})

        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Option Index"] = destination.oi
        packet["_unknown1"] = 0
        packet["Target Index"] = npc.index
        packet["Automated Message"] = false
        packet["_unknown2"] = 0
        packet["Zone"] = zone
        packet["Menu ID"] = menu
        actions:append(T{packet=packet, wait_packet=0x052, expecting_zone=true, delay = wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='complete menu'})

        return actions
    end,

    sub_commands = {
        ['return'] = function(current_activity, zone, p, settings)
            local actions = T{}
            local packet = nil
            local menu = p["Menu ID"]
            local npc = current_activity.npc

            log("Returning to town.")
            -- update request
            packet = packets.new('outgoing', 0x016)
            packet["Target Index"] = windower.ffxi.get_player().index
            actions:append(T{packet=packet, description='update request'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 1
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 1
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, wait_packet=0x052, expecting_zone=true, delay=1+wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='complete menu'})

            return actions
        end,
        port = function(current_activity, zone, p, settings)
            local actions = T{}
            local packet = nil
            local menu = p["Menu ID"]
            local npc = current_activity.npc

            log("Traveling through time...")
            -- update request
            packet = packets.new('outgoing', 0x016)
            packet["Target Index"] = windower.ffxi.get_player().index
            actions:append(T{packet=packet, description='update request'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = true
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send options'})

            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 1
            packet["_unknown1"] = 0
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, wait_packet=0x052, expecting_zone=true, delay=1+wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='warp request'})

            return actions
        end,
    },
    warpdata = T{
        ['Xarcabard [S]'] =             {index = 1, oi=1,   menu_id =458, permission = 0x00000002},
        ['Beaucedine Glacier [S]'] =    {index = 2, oi=2,   menu_id =458, permission = 0x00000004},
        ['Batallia Downs [S]'] =        {index = 3, oi=3,   menu_id =458, permission = 0x00000008},
        ['Rolanberry Fields [S]'] =     {index = 4, oi=4,   menu_id =458, permission = 0x00000010},
        ['Sauromugue Champaign [S]'] =  {index = 5, oi=5,   menu_id =458, permission = 0x00000020},
        ['Jugner Forest [S]'] =         {index = 6, oi=6,   menu_id =458, permission = 0x00000040},
        ['Pashhow Marshlands [S]'] =    {index = 7, oi=7,   menu_id =458, permission = 0x00000080},
        ['Meriphataud Mountains [S]'] = {index = 8, oi=8,   menu_id =458, permission = 0x00000100},
        ['Vunkerl Inlet [S]'] =         {index = 9, oi=9,   menu_id =458, permission = 0x00000200},
        ['Grauberg [S]'] =              {index = 10, oi=10, menu_id =458, permission = 0x00000400},
        ['Fort Karugo-Narugo [S]'] =    {index = 11, oi=11, menu_id =458, permission = 0x00000800},
        ['East Ronfaure [S]'] =         {index = 12, oi=12, menu_id =458, permission = 0x00001000},
        ['North Gustaberg [S]'] =       {index = 13, oi=13, menu_id =458, permission = 0x00002000},
        ['West Sarutabaruta [S]'] =     {index = 14, oi=14, menu_id =458, permission = 0x00004000},
        ['Garlaige Citadel [S]'] =      {index = 15, oi=18, menu_id =458, permission = 0x00040000},
        ['Crawlers\' Nest [S]'] =       {index = 16, oi=19, menu_id =458, permission = 0x00080000},
        ['Eldieme Necropolis [S]'] =    {index = 17, oi=20, menu_id =458, permission = 0x00100000},
    },
}
end,
-- ======================================================== voidwatch
['voidwatch'] = function()
local past_warp_zones = S{80,84,87,91,94,98}
local menu_ids = S{962, 1023, 264, 16, 316, 49, 627, 24, 7, 6, -- present
                   79, 657, 46, 25, 8, 15} -- shadowreign
local npc_names = T{
    warp = S{"Atmacite Refiner"},
}
return T{ --  index: 1
    short_name = {'vw','vo'},
    long_name = 'Voidwatch',
    npc_plural = 'atmacite refiners',
    npc_names = npc_names,
    zone_npc_list = function(type)
        local mlist = windower.ffxi.get_mob_list()
        mlist = table.filter(mlist, function(name)
            return name ~= "" and npc_names[type]:any(string.startswith+{name})
        end)
        mlist = table.map(mlist, function(name)
            return {name=name}
        end)
        return mlist
    end,
    validate = function(menu_id, zone, current_activity)
        local destination = current_activity.activity_settings
        if not menu_ids:contains(menu_id) then 
            return "Incorrect menu detected! Menu ID: "..menu_id
        end
        if past_warp_zones:contains(zone) ~= (destination.shadowreign or false) then
            return "Cannot teleport from here."
        end
        return nil
    end,
    missing = function(warpdata, zone, p)
        local missing = T{}
        local unlock_bits = p["Menu Parameters"]:unpack('I', 21)

        for z, zd in pairs(warpdata) do
            if not zd.shortcut then
                if zd.unlocked then
                    if bit.band(unlock_bits, zd.unlocked) == 0 then
                        missing:append(z)
                    end
                end
            end
        end
        return missing
    end,
    help_text = "| Voidwatch |\n Command options [vw, vo]\n- vw zone name -- warp to a designated voidwatch zone.\n-----------------------------",
    sub_zone_targets = S{},
    build_warp_packets = function(current_activity, zone, p, settings)
        local actions = T{}
        local packet = nil
        local menu = p["Menu ID"]
        local npc = current_activity.npc
        local destination = current_activity.activity_settings

        local vw_unlocked = p['Menu Parameters']:unpack('b', 1, 2)
        local cruor = p["Menu Parameters"]:unpack('i', 17)
        local unlock_bits = p["Menu Parameters"]:unpack('I', 21)
        local expac_flags = p['Menu Parameters']:sub(29)

        if not vw_unlocked then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Voidwatch content is not unlocked yet!'})
            return actions
        end

        local destination_unlocked = true
        if destination.unlocked then
            destination_unlocked = bit.band(unlock_bits, destination.unlocked) ~= 0
        end

        debug('voidwatch warp is unlocked: '..tostring(destination_unlocked))

        if not destination_unlocked then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Destination is not unlocked yet!'})
            return actions
        end

        debug("cruor: "..cruor)
        if cruor < 1000 then
            packet = packets.new('outgoing', 0x05B)
            packet["Target"] = npc.id
            packet["Option Index"] = 0
            packet["_unknown1"] = 16384
            packet["Target Index"] = npc.index
            packet["Automated Message"] = false
            packet["_unknown2"] = 0
            packet["Zone"] = zone
            packet["Menu ID"] = menu
            actions:append(T{packet=packet, description='cancel menu', message='Not enough cruor!'})
            return actions
        end

        if destination.expac then
            debug('destination expac: '..destination.expac..'. has access? '..tostring(has_bit(expac_flags, destination.expac or 0)))
            if not has_bit(expac_flags, destination.expac) then
                packet = packets.new('outgoing', 0x05B)
                packet["Target"] = npc.id
                packet["Option Index"] = 0
                packet["_unknown1"] = 16384
                packet["Target Index"] = npc.index
                packet["Automated Message"] = false
                packet["_unknown2"] = 0
                packet["Zone"] = zone
                packet["Menu ID"] = menu
                actions:append(T{packet=packet, description='cancel menu', message='You do not have access to that expansion!'})
                return actions
            end
        end

        --if settings.debug then
        --    packet = packets.new('outgoing', 0x05B)
        --    packet["Target"] = npc.id
        --    packet["Option Index"] = 0
        --    packet["_unknown1"] = 16384
        --    packet["Target Index"] = npc.index
        --    packet["Automated Message"] = false
        --    packet["_unknown2"] = 0
        --    packet["Zone"] = zone
        --    packet["Menu ID"] = menu
        --    actions:append(T{packet=packet, description='cancel menu', message='Debug stop'})
        --    return actions
        --end

        local popMessage = nil
        if destination.z and destination.pops then
            popMessage = "Pops located at: "..destination.z.." "..destination.pops
        end

        -- update request
        --packet = packets.new('outgoing', 0x016)
        --packet["Target Index"] = windower.ffxi.get_player().index
        --actions:append(T{packet=packet, description='update request'})
    
        -- request warp
        packet = packets.new('outgoing', 0x05B)
        packet["Target"] = npc.id
        packet["Target Index"] = npc.index
        packet["Zone"] = zone
        packet["Menu ID"] = menu

        packet["Option Index"] = 2
        packet["_unknown1"] = destination.index
        packet["Automated Message"] = false
        packet["_unknown2"] = 0
        actions:append(T{packet=packet, expecting_zone=true, delay=wiggle_value(settings.simulated_response_time, settings.simulated_response_variation), description='send  indexs and complete menu', message=popMessage})

        return actions
    end,
    warpdata = T{
        ['East Ronfaure'] = { index = 1, unlocked = 0x000000F, },
        ['East Ronfaure [S]'] = { index = 2, unlocked = 0x000000F, shadowreign = true, },
        ['Ordelle\'s Caves'] = { index = 3, unlocked = 0x000000E, },
        ['Jugner Forest'] = { index = 4, unlocked = 0x000000C, },
        ['Jugner Forest [S]'] = { index = 5, unlocked = 0x000000C, shadowreign = true, },
        ['King Ranperre\'s Tomb'] = { index = 6, unlocked = 0x0000008, },
        ['North Gustaberg'] = { index = 7, unlocked = 0x00000F0, },
        ['North Gustaberg [S]'] = { index = 8, unlocked = 0x00000F0, shadowreign = true, },
        ['Gusgen Mines'] = { index = 9, unlocked = 0x00000E0, },
        ['Pashhow Marshlands'] = { index = 10, unlocked = 0x00000C0, },
        ['Pashhow Marshlands [S]'] = { index = 11, unlocked = 0x00000C0, shadowreign = true, },
        ['Dangruf Wadi'] = { index = 12, unlocked = 0x0000080, },
        ['West Sarutabaruta'] = { index = 13, unlocked = 0x0000F00, },
        ['West Sarutabaruta [S]'] = { index = 14, unlocked = 0x0000F00, shadowreign = true, },
        ['Maze of Shakhrami'] = { index = 15, unlocked = 0x0000E00, },
        ['Meriphataud Mountains'] = { index = 16, unlocked = 0x0000C00, },
        ['Meriphataud Mountains [S]'] = { index = 17, unlocked = 0x0000C00, shadowreign = true, },
        ['Outer Horutoto Ruins'] = { index = 18, unlocked = 0x0000800, },
        ['Batallia Downs'] = { index = 19, unlocked = 0x0707000, zone = 105, },
        ['Batallia Downs [S]'] = { index = 20, unlocked = 0x0707000, zone = 854, shadowreign = true, },
        ['Rolanberry Fields'] = { index = 21, unlocked = 0x0707000, zone = 110, },
        ['Rolanberry Fields [S]'] = { index = 22, unlocked = 0x0707000, zone = 91, shadowreign = true, },
        ['Sauromugue Champaign'] = { index = 23, unlocked = 0x0707000, zone = 120, },
        ['Sauromugue Champaign [S]'] = { index = 24, unlocked = 0x0707000, zone = 98, shadowreign = true, },
        ['Eldieme Necropolis'] = { index = 25, unlocked = 0x0706000, },
        ['Eldieme Necropolis [S]'] = { index = 26, unlocked = 0x0706000, shadowreign = true, },
        ['Crawlers\' Nest'] = { index = 27, unlocked = 0x0706000, },
        ['Crawlers\' Nest [S]'] = { index = 28, unlocked = 0x0706000, shadowreign = true, },
        ['Garlaige Citadel'] = { index = 29, unlocked = 0x0706000, },
        ['Garlaige Citadel [S]'] = { index = 30, unlocked = 0x0706000, shadowreign = true, },
        ['Qufim Island'] = { index = 31, unlocked = 0x0704000, zone = 126, },
        ['Delkfutt\'s Tower'] = { index = 32, unlocked = 0x0704000, },
        ['Behemoth\'s Dominion'] = { index = 33, unlocked = 0x0704000, },
        ['Yuhtunga Jungle'] = { index = 34, unlocked = 0x0068000, expac = 0, },
        ['Ifrit\'s Cauldron'] = { index = 35, unlocked = 0x0068000, expac = 0, },
        ['Temple of Uggalepih'] = { index = 36, unlocked = 0x0068000, expac = 0, },
        ['Western Altepa Desert'] = { index = 37, unlocked = 0x0070000, expac = 0, },
        ['Kuftal Tunnel'] = { index = 38, unlocked = 0x0070000, expac = 0, },
        ['Quicksand Caves'] = { index = 39, unlocked = 0x0070000, expac = 0, },
        ['The Sanctuary of Zi\'Tah'] = { index = 40, unlocked = 0x0060000, expac = 0, },
        ['The Boyahda Tree'] = { index = 41, unlocked = 0x0060000, expac = 0, },
        ['Ro\'Maeve'] = { index = 42, unlocked = 0x0060000, expac = 0, },
        ['The Hall of the Gods'] = { index = 43, unlocked = 0x0040000, expac = 0, },
        ['West Ronfaure'] = { index = 44, unlocked = 0x0700000, },
        ['South Gustaberg'] = { index = 45, unlocked = 0x0700000, },
        ['East Sarutabaruta'] = { index = 46, unlocked = 0x0700000, },
        ['La Theine Plateau'] = { index = 47, unlocked = 0x0600000, },
        ['Konschtat Highlands'] = { index = 48, unlocked = 0x0600000, },
        ['Tahrongi Canyon'] = { index = 49, unlocked = 0x0600000, },
        ['Vunkerl Inlet [S]'] = { index = 50, unlocked = 0x0400000, shadowreign = true, },
        ['Grauberg [S]'] = { index = 51, unlocked = 0x0400000, shadowreign = true, },
        ['Fort Karugo-Narugo [S]'] = { index = 52, unlocked = 0x0400000, shadowreign = true, },
        ['Valkurm Dunes'] = { index = 53, unlocked = 0x0400000, },
        ['Buburimu Peninsula'] = { index = 54, unlocked = 0x0400000, },
        ['Beaucedine Glacier'] = { index = 55, unlocked = 0x0400000, },
        ['Lufaise Meadows'] = { index = 56, unlocked = 0x1800000, expac = 1, },
        ['Misareaux Coast'] = { index = 57, unlocked = 0x1800000, expac = 1, },
        ['Uleguerand Range'] = { index = 58, unlocked = 0x1800000, expac = 1, },
        ['Attohwa Chasm'] = { index = 59, unlocked = 0x1800000, expac = 1, },
        ['Bibiki Bay'] = { index = 60, unlocked = 0x1000000, expac = 1, },
        ['Arrapago Reef'] = { index = 61, unlocked = 0x6000000, expac = 2, },
        ['Mount Zhayolm'] = { index = 62, unlocked = 0x6000000, expac = 2, },
        ['Mamook'] = { index = 63, unlocked = 0x6000000, expac = 2, },
        ['Caedarva Mire'] = { index = 64, unlocked = 0x6000000, expac = 2, },
        ['Aydeewa Subterrane'] = { index = 65, unlocked = 0x4000000, expac = 2, },
    },
}
end,
}
