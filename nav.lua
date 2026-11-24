--[[
    nav.lua -- AutoAttack travel: aa nav (v5.06; v5.07 NPCs + unreachable zones listed, v5.08 lands closest to the way on, v5.09 walks you to a close warp, v5.10 warps inside your own zone toward the way on, v5.11 zone-moving NPCs, v5.12 trips with legs + finding NPCs, v5.13 warps not loaded yet after zoning, v5.14 checked NPC targeting, v5.15 more ways to target + updates on your own screen, v5.16 walking legs keep the goal, v5.17 hovered line highlighted, v5.18 NPCs found by what they are, v5.19 aa stop stops nav + your own /p line opens the list, v5.20 list pages, v5.21 [X] close, v5.22 learns routes you use by hand + Mog House, v5.23 ways out of Mog Garden, v5.24 Mog Garden always out to Eastern Adoulin, v5.25 stronger row highlight, v5.30 Escha / Abyssea entrances reached by ring or warp first, v5.31 in-zone warp to the NPC (Eschan Portal #8 for Emporox) + craft-style rows + aa stop stops it all, v5.32 Walk of Echoes via Xarcabard [S] + Kupofried's medallion, Warp Ring / Warp home from a zone with no warp, v5.33 Mog Garden ways + nav.via preference, ring cooldowns, warp spots AA has seen, v5.34 walks around things in the way + learns the path, v5.35 Mog Garden: out by the Mog Dinghy / Green Thumb Moogle, never warped out, v5.36 Shadowhammer into Mog Garden via Eastern Adoulin, v5.37 Mog Garden always through Eastern Adoulin: in by Cunegonde, out by the Green Thumb Moogle, v5.38 or the Mog Dinghy's Eastern Adoulin choice, v5.39 the walk from where a Survival Guide lands counts too, v5.40 [X] close is a button that lights up, v5.41 Warp Ring / Instant Warp / Warp never on top when this zone has a Home Point or Survival Guide, v5.42 also with a nav.via way, v5.43 side-step off the Eastern Adoulin Mog House / Mog Garden spawn, v5.44 Warp Ring before Instant Warp, Walk of Echoes out by the conflux first)

    Loaded by autoattack.lua. Finds the fastest way to a zone (or a place in
    a zone, like an Auction House) from where you stand, shows the choices in
    a clickable list, and does the warp for you: it talks to the Home Point /
    Survival Guide / Waypoint / ... itself and answers its menu with packets,
    so the menu never shows.

        //aa nav tar          list every zone / place with "tar" in its name
        //aa nav 2            go with line 2 of the list (or left-click it)
        //aa nav p2           line 2 for the whole party (or right-click it)
        //aa nav party <text> every AA in the party goes to <text>, each its own fastest way
        /p aa nav <text>      the same, from party chat (friends only)
        //aa nav close        close the list (cancel stops a warp / a walk)
        //aa nav unlocks      what AA knows about this character's unlocks
        //aa nav pos <x> <y>  move the list

    Ways it knows: Home Points, Survival Guides (gil first, tabs only when
    you are short on gil), Adoulin Waypoints, Proto-Waypoints (listed last),
    Unity Concord, Escha / Reisenjima portals, Abyssea, Runic Portals,
    Campaign Arbiters, Voidwatch, plus Warp Ring, Dim. Rings, Tavnazian Ring,
    Instant Warp and your own Warp / Teleport / Recall spells. Rings go on the
    RIGHT ring (ring2) like aa warp, and your ring goes back after the warp.

    Order: fastest first -- walk to the warp, menu and zoning time, plus a
    rough walk for every zone you still have to cross. Cost does not count.
    If the warp is too far away, the list says how far; walk there and AA
    warps when you are within reach (aa nav cancel stops that).

    Unlocks: which warps a character has is server data that only shows up
    in the warp menu. The first time you touch any Home Point (by hand or by
    aa nav) AA reads every Home Point unlock at once, the same for Survival
    Guides, Waypoints and the rest, and keeps them in data/nav_<name>.lua.
    Until then every warp counts as unlocked; a locked one is cancelled
    cleanly and remembered.

    Warp data: nav_maps.lua (from SuperWarp by Akaden, BSD licence -- see
    that file). Zone connections: nav_zones.lua.
]]

local packets = require('packets')
require('tables'); require('sets'); require('lists'); require('strings'); require('functions')
local texts = require('texts')
local res = require('resources')

local N = {maps = {}, params = {}, locked = {}, learned = {}, home = nil,
           cur = nil, pending = nil, armed = nil, rows = nil, gui = nil, gui_lines = {},
           char = nil, gen = 0}
AA_NAV = N

-- ---------------------------------------------------------------------------
-- settings (aa_config.lua: nav = {...})
-- ---------------------------------------------------------------------------
local D = {
    enabled       = true,
    max_rows      = 14,     -- lines in the list
    device_range  = 6,      -- yalms: close enough to talk to a warp
    arm_timeout   = 120,    -- s AA waits for you to walk to a warp before giving up
    walk_range    = 50,     -- yalms: a warp NPC this close (and farther than device_range) -- AA walks you to it
    seek_range    = 40,     -- v5.12: yalms: an NPC you look for gets the cursor once it is this close
    seek_timeout  = 600,    -- v5.12: s AA keeps telling you the way to an NPC
    seek_every    = 5,      -- v5.15: s between "it is Ny <dir> of you" updates
    run_speed     = 5,      -- yalms/s when your speed can't be read
    zone_seconds  = 10,     -- s of zoning per warp to another zone
    hop_seconds   = 90,     -- s guessed for walking through one zone
    max_hops      = 3,      -- zones away AA looks for a warp when the zone itself has none
    use_tabs      = false,  -- Survival Guides: tabs first (false = gil first, tabs only when short)
    hide_locked   = false,  -- true = locked warps aren't listed at all
    proto_last    = true,   -- Proto-Waypoints always at the bottom
    menu_seconds  = {homepoints = 5, survivalguides = 6, waypoints = 5, protowaypoints = 6,
                     unity = 7, escha = 5, abyssea = 6, portals = 6, campaign = 7, voidwatch = 7},
    ring_seconds  = 4,      -- s from /item to the warp (after party.warp_ring_delay)
    gui           = {x = 420, y = 240, font = 'Consolas', size = 10},
    -- v5.33: the way you like into a place, per character: ['<destination>'] =
    -- {<character> = '<zone you go through>', default = ...}. Those ways are
    -- listed and used first; the rest still show in the list.
    -- v5.37: '<zone>' or '<zone> / <NPC>'; with a preference only that way (and
    -- warps that land you somewhere first) is used, the other ways in are left out
    via           = {['Mog Garden'] = {default = 'Eastern Adoulin / Cunegonde'}},
    -- v5.37: leaving Mog Garden: always this way out (Green Thumb Moogle ->
    -- Eastern Adoulin); '' / false = the fastest of all its ways out (Mog Dinghy too)
    garden_exit   = 'Eastern Adoulin',
}
local function opt(k)
    local c = AA_CFG and AA_CFG.nav
    local v = nil
    if type(c) == 'table' then v = c[k] end
    if v == nil then return D[k] end
    if type(v) == 'table' and type(D[k]) == 'table' then
        return setmetatable(v, {__index = D[k]})
    end
    return v
end

local function say(msg) if info_msg then info_msg('NAV: ' .. msg) else windower.add_to_chat(207, '[AA] NAV: ' .. msg) end end
local function dbg(msg) if aa_dbg then aa_dbg('NAV: ' .. msg) end end
local function send(str) if aa_send then aa_send(str) else windower.send_command(str) end end
local function me() return windower.ffxi.get_player() end
local function my_name() local p = me(); return p and p.name or '' end
local function zone_id() local i = windower.ffxi.get_info(); return i and i.zone or 0 end

-- ---------------------------------------------------------------------------
-- warp maps (nav_maps.lua) -- SuperWarp's map tables, run in their own environment
-- ---------------------------------------------------------------------------
local MAPS = {
    {key = 'homepoints',     tag = 'HP',  label = 'Home Point'},
    {key = 'survivalguides', tag = 'SG',  label = 'Survival Guide'},
    {key = 'waypoints',      tag = 'WP',  label = 'Waypoint'},
    {key = 'protowaypoints', tag = 'PWP', label = 'Proto-Waypoint'},
    {key = 'unity',          tag = 'UN',  label = 'Unity'},
    {key = 'escha',          tag = 'ESC', label = 'Escha'},
    {key = 'abyssea',        tag = 'ABY', label = 'Abyssea'},
    {key = 'portals',        tag = 'RP',  label = 'Runic Portal'},
    {key = 'campaign',       tag = 'CA',  label = 'Campaign'},
    {key = 'voidwatch',      tag = 'VW',  label = 'Voidwatch'},
}
local MAPINFO = {}
for _, m in ipairs(MAPS) do MAPINFO[m.key] = m end

-- what the map code gets as "settings" (SuperWarp's names)
local SW = {simulated_response_time = 0, simulated_response_variation = 0,
            enable_same_zone_teleport = true, use_tabs_at_survival_guides = false, debug = false}
local ENV = setmetatable({
    packets = packets,
    settings = SW,
    has_bit = function(data, x) return data:unpack('q', math.floor(x / 8) + 1, x % 8 + 1) end,
    wiggle_value = function(v, var) return math.max(0, v + (math.random() * 2 * var - var)) end,
    log = function(msg) say(tostring(msg)) end,
    debug = function(msg) dbg(tostring(msg)) end,
}, {__index = _G})

local function load_maps()
    local chunk, err = loadfile(windower.addon_path .. 'nav_maps.lua')
    if not chunk then return false, err end
    local ok, src = pcall(chunk)
    if not ok or type(src) ~= 'table' then return false, tostring(src) end
    for _, m in ipairs(MAPS) do
        local fn = src[m.key]
        if type(fn) == 'function' then
            setfenv(fn, ENV)
            local ok2, map = pcall(fn)
            if ok2 and type(map) == 'table' and type(map.warpdata) == 'table' then
                for _, zd in pairs(map.warpdata) do
                    if type(zd) == 'table' and not zd.index and not zd.shortcut then
                        for k, d in pairs(zd) do if type(d) == 'table' then d.key = k end end
                    end
                end
                N.maps[m.key] = map
            else
                say('warp data "' .. m.key .. '" did not load: ' .. tostring(map))
            end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- zones
-- ---------------------------------------------------------------------------
local ZID, ZLIST = {}, {}
for id, z in pairs(res.zones) do
    if type(z) == 'table' and type(z.en) == 'string' and z.en ~= '' and z.en:lower() ~= 'unknown' then
        ZID[z.en:lower()] = id
        ZLIST[#ZLIST + 1] = {id = id, name = z.en}
    end
end
table.sort(ZLIST, function(a, b) return a.name < b.name end)
local function zname(id) local z = id and res.zones[id]; return z and z.en or ('zone ' .. tostring(id)) end

local ADJ, DOORS, SPOTS = {}, {}, {}
do
    local chunk = loadfile(windower.addon_path .. 'nav_zones.lua')
    local ok, t = pcall(chunk or function() return {} end)
    if ok and type(t) == 'table' then
        ADJ = t.links or t
        DOORS = t.doors or {}
        SPOTS = t.spots or {}   -- v5.12: [zone] = {{map, x, y}} warp NPCs the warp data has no spot for
    end
end
-- v5.12: compass direction from (x1, y1) to (x2, y2) (+y = north)
local function compass(x1, y1, x2, y2)
    local a = math.deg(math.atan2(x2 - x1, y2 - y1)) % 360
    local names = {'north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west'}
    return names[math.floor((a + 22.5) / 45) % 8 + 1]
end
-- zones within max hops of a zone: {[id] = hops}, {[id] = the next zone toward 'from'}
local function nearby(from, max_h)
    local dist, par, q = {[from] = 0}, {}, {from}
    local i = 1
    while q[i] do
        local z = q[i]; i = i + 1
        if dist[z] < max_h then
            for _, n in ipairs(ADJ[z] or {}) do
                if dist[n] == nil then dist[n] = dist[z] + 1; par[n] = z; q[#q + 1] = n end
            end
        end
    end
    return dist, par
end

-- v5.11: NPCs that move you to another zone (nav_transports.lua, from the
-- server project's NPC scripts): TR_FROM[zone] = list, TR_TO[zone] = list
local TR_FROM, TR_TO = {}, {}
do
    local chunk = loadfile(windower.addon_path .. 'nav_transports.lua')
    local ok, t = pcall(chunk or function() return {} end)
    if ok and type(t) == 'table' then
        for _, r in ipairs(t) do
            if type(r) == 'table' and r[1] and r[2] and r[5] then
                local tr = {name = r[1], zone = r[2], x = r[3], y = r[4], to = r[5], tx = r[6], ty = r[7],
                            menu = r[8], option = r[9], auto = r[10] == true}
                TR_FROM[tr.zone] = TR_FROM[tr.zone] or {}
                table.insert(TR_FROM[tr.zone], tr)
                TR_TO[tr.to] = TR_TO[tr.to] or {}
                table.insert(TR_TO[tr.to], tr)
            end
        end
    end
end

-- v5.22: a route learned by hand (menu choice at any NPC followed by a zone
-- change: the Mog House moogle, the Mog Dinghy, Adoulin NPCs ...) becomes a
-- zone-moving NPC like the ones from the server data
local function in_mog_house()
    local i = windower.ffxi.get_info()
    return i and i.mog_house and true or false
end
local function add_route(key, L)
    local z, name, to = tostring(key):match('^npc:(%d+):(.-):(%d+)$')
    if not z or type(L) ~= 'table' then return end
    z, to = tonumber(z), tonumber(to)
    for _, tr in ipairs(TR_FROM[z] or {}) do
        if tr.name == name and tr.to == to then
            if L.mh ~= nil then tr.mh = (L.mh == true or L.mh == 1) end
            if not tr.x and L.x then tr.x, tr.y = L.x, L.y end
            if L.tx then tr.tx, tr.ty = L.tx, L.ty end
            return
        end
    end
    local tr = {name = name, zone = z, x = L.x, y = L.y, to = to, tx = L.tx, ty = L.ty, menu = L.menu, option = L.opt, unk = L.unk,
                auto = true, mh = (L.mh == true or L.mh == 1), learned = true}
    TR_FROM[z] = TR_FROM[z] or {}
    table.insert(TR_FROM[z], tr)
    TR_TO[to] = TR_TO[to] or {}
    table.insert(TR_TO[to], tr)
end

-- v5.23: ways out of a zone with no warp and no zone line, whose destination
-- the data doesn't have (Mog Garden: the Green Thumb Moogle's menu or the Mog
-- Dinghy). Used when nothing else gets you out: AA talks to it, you pick the
-- first time, AA learns it, and the trip carries on from wherever you land.
local EXITS = {}

-- v5.24: Mog Garden: nav always leaves by the Green Thumb Moogle to Eastern
-- Adoulin (Home Point, Survival Guide and Waypoint close by). "Return from
-- whence you came" goes back to wherever you came in from, so it is never
-- learned as a route. The first time you pick Eastern Adoulin in its menu;
-- AA remembers that choice.
local FIXED_ONLY = {['280:Green Thumb Moogle'] = {[256] = true, [257] = true},   -- learn only these destinations
                    ['280:Mog Dinghy'] = {[232] = true, [236] = true, [240] = true, [257] = true}}   -- v5.35, v5.38 Eastern Adoulin
-- v5.35: zones you leave by their own way out, never by a warp ring / item /
-- spell (Mark, 2026-11-23: "'aa nav' when player is in mog garden should first
-- be to exit mog garden via dinghy or green thumb moogle, not warping out")
local NO_WARP_OUT = {[280] = true}
-- v5.44: zones whose own way out comes before any warp (Mark, 2026-11-23: "in
-- Walk of Echoes, favor Conflux instead of warp") -- warps are still listed
local PREFER_EXIT = {[182] = true}
-- v5.37: zone-moving NPCs from zone z, without Mog Garden's ways out other
-- than nav.garden_exit (Mark, 2026-11-23: "when exiting the mog garden, lets
-- always choose 'exit to east adoulin'")
local function tr_allowed(tr)
    if tr.zone ~= 280 or tr.to == 280 then return true end
    local ge = opt('garden_exit')
    if type(ge) ~= 'string' or ge == '' then return true end
    local gz = ZID[ge:lower()]
    return not gz or tr.to == gz
end
local function tr_from(z)
    local out = {}
    for _, tr in ipairs(TR_FROM[z] or {}) do if tr_allowed(tr) then out[#out + 1] = tr end end
    return out
end
do   -- the Mog Dinghy in Mog Garden: to the three starting-town ports (you pick the first time)
    -- v5.38: and to Eastern Adoulin (Mark: "eastern adoulin is the bottom option from Dinghy")
    for _, to in ipairs({232, 236, 240, 257}) do
        local tr = {name = 'Mog Dinghy', zone = 280, x = -17, y = -24, to = to, auto = false, garden = true}
        TR_FROM[280] = TR_FROM[280] or {}
        table.insert(TR_FROM[280], tr)
        TR_TO[to] = TR_TO[to] or {}
        table.insert(TR_TO[to], tr)
    end
end
do
    local tr = {name = 'Green Thumb Moogle', zone = 280, x = 0, y = 0, to = 257, auto = false, garden = true}
    TR_FROM[280] = TR_FROM[280] or {}
    table.insert(TR_FROM[280], tr)
    TR_TO[257] = TR_TO[257] or {}
    table.insert(TR_TO[257], tr)
end

-- v5.32: Walk of Echoes (Mark, 2026-11-23: "go to xarcabard (S), go to the
-- veridical conflux nearby, buy a kupofried medallion for 1000gil, then use the
-- veridical conflux to enter Walk of Echoes"). Spots from the NPC list / AA's
-- own sightings; the menu is learned the first time (you pick). ki = the
-- temporary key item it sells (1000 gil): AA buys it first when you lack it.
local NEED_KI = {['137:Veridical Conflux'] = {id = 1599, name = "Kupofried's medallion", gil = 1000}}
do
    for _, tr in ipairs({
        {name = 'Veridical Conflux', zone = 137, x = 239, y = -248, to = 182, tx = -414, ty = -60, auto = false},
        {name = 'Veridical Conflux', zone = 182, x = -420, y = -38, to = 137, tx = 238, ty = -248, auto = false},
    }) do
        TR_FROM[tr.zone] = TR_FROM[tr.zone] or {}
        table.insert(TR_FROM[tr.zone], tr)
        TR_TO[tr.to] = TR_TO[tr.to] or {}
        table.insert(TR_TO[tr.to], tr)
    end
end
-- v5.33: Mog Garden (Mark, 2026-11-23: "You can get to mog garden from the
-- dingy at all three starting town ports, from typically any mog house, and
-- from East and West adoulin"). Menus learned the first time (you pick Mog
-- Garden); a Mog House moogle's choice learned in one town is tried in the others.
do
    local list = {
        {name = 'Mog Dinghy', zone = 232, x = 22, y = -51, to = 280, auto = false},
        {name = 'Mog Dinghy', zone = 236, x = 81, y = -174, to = 280, auto = false},
        {name = 'Mog Dinghy', zone = 240, x = -197, y = 70, to = 280, auto = false},
        -- v5.37: Eastern Adoulin, by Home Point #2 / the Survival Guide (Mark: "go to
        -- eastern adoulin HP 2, or the book, and then talk to Cunegonde")
        {name = 'Cunegonde', zone = 257, x = -56, y = -130, to = 280, auto = false},
    }
    for _, z in ipairs({230, 231, 232, 234, 235, 236, 238, 239, 240, 241, 243, 244, 245, 246, 50, 256, 257}) do
        list[#list + 1] = {name = 'Moogle', zone = z, to = 280, auto = false, mh = true}
    end
    for _, tr in ipairs(list) do
        local dup = false
        for _, t2 in ipairs(TR_FROM[tr.zone] or {}) do if t2.name == tr.name and t2.to == tr.to then dup = true end end
        if not dup then
            TR_FROM[tr.zone] = TR_FROM[tr.zone] or {}
            table.insert(TR_FROM[tr.zone], tr)
            TR_TO[tr.to] = TR_TO[tr.to] or {}
            table.insert(TR_TO[tr.to], tr)
        end
    end
end
-- v5.33: a Veridical Conflux outside Abyssea (Xarcabard [S], Walk of Echoes ...) is not an Abyssea warp
local ABY_ZONES = {[15]=1,[45]=1,[132]=1,[215]=1,[216]=1,[217]=1,[218]=1,[253]=1,[254]=1}
local function vc_not_abyssea(name, z)
    return type(name) == 'string' and name:sub(1, 17) == 'Veridical Conflux' and not ABY_ZONES[z]
end
local function has_ki(id)
    local kis = windower.ffxi.get_key_items and windower.ffxi.get_key_items()
    if type(kis) ~= 'table' then return false end
    for _, k in pairs(kis) do if k == id then return true end end
    return false
end
local function my_gil()
    local it = windower.ffxi.get_items()
    return type(it) == 'table' and tonumber(it.gil) or nil
end
-- a menu answer of several steps (buy, then enter): "menu,opt,unk,auto;..."
local function seq_str(seq)
    local t = {}
    for _, x in ipairs(seq or {}) do t[#t + 1] = string.format('%d,%d,%d,%d', x.menu or 0, x.opt or 0, x.unk or 0, x.auto and 1 or 0) end
    return table.concat(t, ';')
end
local function seq_parse(str)
    local out = {}
    for m, o, u, a in tostring(str or ''):gmatch('(%d+),(%d+),(%d+),(%d)') do
        out[#out + 1] = {menu = tonumber(m), opt = tonumber(o), unk = tonumber(u), auto = a == '1'}
    end
    return out
end

-- Escha / Abyssea "enter" and "exit": where they lead (learned when used)
local ENTER_SEED = {
    ['escha:enter:126'] = 288, ['escha:enter:25'] = 289, ['escha:enter:102'] = 291,
    ['escha:enter:108'] = 291, ['escha:enter:117'] = 291, ['escha:enter:291'] = 293,
    ['abyssea:enter:102'] = 132, ['abyssea:enter:108'] = 15, ['abyssea:enter:117'] = 45,
}
local function enter_dest(map, kind, from)
    local k = map .. ':' .. kind .. ':' .. tostring(from)
    return N.learned[k] or ENTER_SEED[k], k
end
-- v5.30: where the entrances stand (Windower x / y), so a trip can go "Dim.
-- Ring to the crag, then the Dimensional Portal" and AA can head for it before
-- it has loaded. Konschtat / Tahrongi portals and the Maws from LandSandBoat
-- (!pos); La Theine's portal is estimated (crag layout) -- a portal seen in
-- game (data/nav_npcs_seen.lua) wins. r = how far from the spot it may stand.
local ENTER_SPOTS = {
    ['escha:102'] = {name = 'Dimensional Portal', x = 420, y = -140, r = 60},
    ['escha:108'] = {name = 'Dimensional Portal', x = 220, y = 140, r = 40},
    ['escha:117'] = {name = 'Dimensional Portal', x = 260, y = 340, r = 40},
    ['abyssea:102'] = {name = 'Cavernous Maw', x = -558, y = 638, r = 40},
    ['abyssea:108'] = {name = 'Cavernous Maw', x = 95, y = -580, r = 40},
    ['abyssea:117'] = {name = 'Cavernous Maw', x = -28, y = -685, r = 40},
}
local enter_spot   -- defined after the NPC-spot file (needs SEEN)
local seen_warps   -- v5.33: warp NPC spots AA has seen in a zone (defined with SEEN)

-- ---------------------------------------------------------------------------
-- destination index
-- ---------------------------------------------------------------------------
local BY_MAP, LANDMARKS = {}, {}
local function zid_of(name, d)
    if d and d.zone then return d.zone end
    return ZID[name:lower()]
end
local function resolve_sc(zd, sd, depth)
    depth = depth or 0
    if sd and sd.shortcut and depth < 5 then return resolve_sc(zd, zd[sd.shortcut], depth + 1) end
    return sd
end
local function build_index()
    BY_MAP, LANDMARKS = {}, {}
    for _, m in ipairs(MAPS) do
        local map = N.maps[m.key]
        local list = {}
        BY_MAP[m.key] = list
        if map then
            for zn, zd in pairs(map.warpdata) do
                if type(zd) == 'table' then
                    if zd.index then
                        list[#list + 1] = {map = m.key, zone_name = zn, data = zd, zone_id = zid_of(zn, zd), label = zn}
                    elseif not zd.shortcut then
                        for sub, sd in pairs(zd) do
                            if type(sd) == 'table' then
                                local num = tostring(sub):match('^%d+$')
                                if sd.shortcut then
                                    local tgt = resolve_sc(zd, sd)
                                    if not num and tgt and tgt.index then
                                        LANDMARKS[#LANDMARKS + 1] = {map = m.key, zone_name = zn, sub = tostring(sub),
                                            data = tgt, zone_id = zid_of(zn, tgt), label = zn .. ' - ' .. tostring(sub)}
                                    end
                                elseif sd.index then
                                    list[#list + 1] = {map = m.key, zone_name = zn, sub = tostring(sub), data = sd,
                                        zone_id = zid_of(zn, sd),
                                        label = zn .. (num and (' #' .. sub) or (' - ' .. tostring(sub)))}
                                    if not num then LANDMARKS[#LANDMARKS + 1] = list[#list] end
                                end
                            end
                        end
                    end
                end
            end
        end
        table.sort(list, function(a, b) return a.label < b.label end)
    end
    table.sort(LANDMARKS, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.map < b.map
    end)
end

-- ---------------------------------------------------------------------------
-- unlocks (data/nav_<name>.lua) + learned Escha / Abyssea entrances (data/nav_learned.lua)
-- ---------------------------------------------------------------------------
local function hex(s) return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end)) end
local function unhex(h) return (h:gsub('%x%x', function(x) return string.char(tonumber(x, 16)) end)) end
local function data_file(name) return windower.addon_path .. 'data/' .. name end
local function read_table(path)
    local chunk = loadfile(path)
    if not chunk then return nil end
    local ok, t = pcall(chunk)
    return ok and type(t) == 'table' and t or nil
end
local function compute_locked(mkey)
    local map, params = N.maps[mkey], N.params[mkey]
    if not (map and map.missing and params) then N.locked[mkey] = nil; return end
    local ok, list = pcall(map.missing, map.warpdata, zone_id(), {['Menu Parameters'] = params, ['Menu ID'] = 0})
    if ok and type(list) == 'table' then
        local set = {}
        for _, n in ipairs(list) do set[tostring(n)] = true end
        N.locked[mkey] = set
    end
end
local function save_char()
    if not N.char then return end
    local f = io.open(data_file('nav_' .. N.char .. '.lua'), 'w')
    if not f then return end
    f:write('-- AutoAttack aa nav: what ' .. N.char .. ' has unlocked (menu data read from each warp menu)\n')
    f:write('return {\n    home = ' .. tostring(N.home or 'nil') .. ',\n    params = {\n')
    for _, m in ipairs(MAPS) do
        if N.params[m.key] then f:write(string.format('        %s = %q,\n', m.key, hex(N.params[m.key]))) end
    end
    f:write('    },\n    used = {\n')   -- v5.33: when rings / warp items were last used (os.time)
    for k, v in pairs(N.used or {}) do f:write(string.format('        [%q] = %d,\n', k, v)) end
    f:write('    },\n}\n')
    f:close()
end
local function save_learned()
    local f = io.open(data_file('nav_learned.lua'), 'w')
    if not f then return end
    f:write('-- AutoAttack aa nav: where Escha / Abyssea entrances and exits lead ([map:kind:from zone] = to zone),\n')
    f:write('-- and the menu choice that makes a zone-moving NPC take you somewhere ([npc:zone:name:to zone])\nreturn {\n')
    local keys = {}
    for k in pairs(N.learned) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = N.learned[k]
        if type(v) == 'table' then   -- v5.11: a zone-moving NPC's menu choice
            f:write(string.format('    [%q] = {menu = %d, opt = %d, unk = %d%s%s%s%s},\n', k, v.menu or 0, v.opt or 0, v.unk or 0,
                (v.x and v.y) and string.format(', x = %d, y = %d', v.x, v.y) or '',
                (v.tx and v.ty) and string.format(', tx = %d, ty = %d', v.tx, v.ty) or '', v.mh and ', mh = true' or '',
                (type(v.seq) == 'string' and v.seq ~= '') and string.format(', seq = %q', v.seq) or ''))
        elseif type(v) == 'string' then   -- v5.34: a learned walking path "x,y;x,y"
            f:write(string.format('    [%q] = %q,\n', k, v))
        else
            f:write(string.format('    [%q] = %d,\n', k, v))
        end
    end
    f:write('}\n')
    f:close()
end
local function load_char()
    local name = my_name()
    if name == '' then return end
    N.char, N.params, N.locked, N.home = name, {}, {}, nil
    local t = read_table(data_file('nav_' .. name .. '.lua'))
    if t then
        N.home = tonumber(t.home)
        N.used = {}
        for k, v in pairs(type(t.used) == 'table' and t.used or {}) do if tonumber(v) then N.used[k] = tonumber(v) end end
        for k, h in pairs(t.params or {}) do
            if type(h) == 'string' then N.params[k] = unhex(h) end
        end
        for k in pairs(N.params) do compute_locked(k) end
    end
    N.learned = read_table(data_file('nav_learned.lua')) or {}
    for k, v in pairs(N.learned) do if type(v) == 'table' then add_route(k, v) end end   -- v5.22
end
local function locked(e)
    local set = N.locked[e.map]
    if not set then return nil end   -- never seen this kind of menu: unknown
    if set[e.zone_name] then return true end
    local sub = (e.data and e.data.key) or e.sub   -- a place (Auction House) -> its warp number
    if sub and set[e.zone_name .. '-' .. tostring(sub)] then return true end
    return false
end

-- the menu of a warp NPC came in (ours or the player's own): keep its unlock bits
local function map_of_npc(name, kind)
    if not name then return nil end
    for _, m in ipairs(MAPS) do
        local map = N.maps[m.key]
        local names = map and map.npc_names and map.npc_names[kind or 'warp']
        if names then
            for n in pairs(names) do
                if type(n) == 'string' and name:sub(1, #n) == n then return m.key end
            end
        end
    end
    return nil
end
local function record_params(p)
    local mob = p['NPC Index'] and windower.ffxi.get_mob_by_index(p['NPC Index'])
    local mkey = mob and map_of_npc(mob.name, 'warp')
    if mkey == 'abyssea' and vc_not_abyssea(mob.name, zone_id()) then return end   -- v5.33
    local params = p['Menu Parameters']
    if not (mkey and type(params) == 'string' and #params > 0) then return end
    if N.params[mkey] == params then return end
    N.params[mkey] = params
    compute_locked(mkey)
    save_char()
    dbg('unlocks read from ' .. tostring(mob.name) .. ' (' .. mkey .. ')')
end

-- ---------------------------------------------------------------------------
-- items and spells
-- ---------------------------------------------------------------------------
local ITEMS = {   -- dest = zone id, or 'home' (your Home Point)
    {name = 'Warp Ring',         kind = 'ring', dest = 'home'},
    {name = 'Dim. Ring (Holla)', kind = 'ring', dest = 102},
    {name = 'Dim. Ring (Dem)',   kind = 'ring', dest = 108},
    {name = 'Dim. Ring (Mea)',   kind = 'ring', dest = 117},
    {name = 'Tavnazian Ring',    kind = 'ring', dest = 26},
    {name = 'Instant Warp',      kind = 'item', dest = 'home'},
}
local SPELLS = {
    {name = 'Warp', dest = 'home'}, {name = 'Warp II', dest = 'home'},
    {name = 'Teleport-Holla', dest = 102}, {name = 'Teleport-Dem', dest = 108},
    {name = 'Teleport-Mea', dest = 117}, {name = 'Teleport-Altep', dest = 114},
    {name = 'Teleport-Yhoat', dest = 124}, {name = 'Teleport-Vahzl', dest = 112},
    {name = 'Recall-Jugner', dest = 82}, {name = 'Recall-Pashh', dest = 90}, {name = 'Recall-Meriph', dest = 97},
}
local RING_BAGS = {0, 8, 10, 11, 12, 13, 14, 15, 16}
local function have_item(name, bags)
    local it = aa_item_named and aa_item_named(name)
    if not it then return false end
    for _, bag in ipairs(bags) do
        local items = windower.ffxi.get_items(bag)
        if type(items) == 'table' then
            for _, e in ipairs(items) do
                if type(e) == 'table' and e.id == it.id then return true end
            end
        end
    end
    return false
end
local function spell_ok(name)
    local sp = res.spells:with('en', name)
    local p = me()
    if not (sp and p) then return false end
    local known = windower.ffxi.get_spells()
    if not (known and known[sp.id]) then return false end
    local lv = sp.levels or {}
    local lvl_ok = (p.main_job_id and lv[p.main_job_id] and lv[p.main_job_id] <= (p.main_job_level or 0))
                or (p.sub_job_id and lv[p.sub_job_id] and lv[p.sub_job_id] <= (p.sub_job_level or 0))
    if not lvl_ok then return false end
    if (p.vitals and p.vitals.mp or 0) < (sp.mp_cost or 0) then return false end
    return true, sp
end
local function item_dest(d) if d == 'home' then return N.home end return d end
-- v5.33: rings / items on their reuse timer are left out (Mark: Warp Ring first,
-- the conflux back to Xarcabard [S] when it's on cooldown). AA notes every
-- use (action packet, also by hand / aa warp) and a ring that didn't go off.
N.used = N.used or {}
local function item_ready(name)
    local t = N.used[name]
    if not t then return true end
    local it = res.items:with('en', name)
    local cd = (it and tonumber(it.recast_delay)) or 600
    return os.time() - t >= cd
end

-- ---------------------------------------------------------------------------
-- routes
-- ---------------------------------------------------------------------------
local function speed()
    local m = windower.ffxi.get_mob_by_target('me')
    local s = m and tonumber(m.movement_speed)
    if not s or s <= 0 then s = opt('run_speed') end
    return s
end

-- the nearest warp NPC of every kind in this zone
local function devices_here()
    local list = {}
    local here = zone_id()
    for _, m in ipairs(MAPS) do
        local map = N.maps[m.key]
        if map and map.zone_npc_list and map.npc_names then
            for _, kind in ipairs({'warp', 'enter', 'exit'}) do
                if map.npc_names[kind] and (kind == 'warp' or m.key == 'escha' or m.key == 'abyssea') then
                    local ok, needles = pcall(map.zone_npc_list, kind)
                    if ok and type(needles) == 'table' then
                        local best, bd = nil, nil
                        for idx in pairs(needles) do
                            local mob = windower.ffxi.get_mob_by_index(idx)
                            if mob and mob.valid_target and (mob.id or 0) > 0 then
                                local d = math.sqrt(mob.distance or 0)
                                if not bd or d < bd then best, bd = mob, d end
                            end
                        end
                        -- v5.32: a Veridical Conflux is an Abyssea warp only inside Abyssea
                        -- (Xarcabard [S]'s goes to Walk of Echoes)
                        if best and m.key == 'abyssea' and kind == 'warp' and type(best.name) == 'string'
                           and best.name:sub(1, 17) == 'Veridical Conflux'
                           and not (map.abyssea_zones and map.abyssea_zones:contains(here)) then
                            best = nil
                        end
                        if best then
                            local useful = (kind == 'warp')
                            if m.key == 'escha' and kind ~= 'warp' then
                                local inside = map.escha_zones and map.escha_zones:contains(here)
                                useful = (kind == 'exit' and inside) or (kind == 'enter' and here ~= 293 and not (inside and here ~= 291))
                            elseif m.key == 'abyssea' and kind ~= 'warp' then
                                local inside = map.abyssea_zones and map.abyssea_zones:contains(here)
                                useful = (kind == 'exit' and inside) or (kind == 'enter' and not inside)
                            end
                            if useful then list[#list + 1] = {map = m.key, kind = kind, mob = best, dist = bd} end
                        end
                    end
                end
            end
        end
    end
    -- v5.13: right after zoning the warp NPCs aren't loaded yet -- use where
    -- the data says they stand (the NPC is picked up once it shows)
    local me_m = windower.ffxi.get_mob_by_target('me')
    if me_m and tonumber(me_m.x) then
        local have = {}
        for _, dv in ipairs(list) do if dv.kind == 'warp' then have[dv.map] = true end end
        local spots = {}
        for _, mkey in ipairs({'homepoints', 'waypoints', 'escha', 'abyssea'}) do
            for _, e in ipairs(BY_MAP[mkey] or {}) do
                local d = e.data
                if e.zone_id == here and d and tonumber(d.x) and tonumber(d.y) and d.index then
                    spots[#spots + 1] = {map = mkey, x = d.x, y = d.y}
                end
            end
        end
        for _, sp in ipairs(SPOTS[here] or {}) do spots[#spots + 1] = {map = sp[1], x = sp[2], y = sp[3]} end
        for _, sp in ipairs(seen_warps and seen_warps(here) or {}) do spots[#spots + 1] = sp end   -- v5.33
        local best = {}
        for _, sp in ipairs(spots) do
            if not have[sp.map] and N.maps[sp.map] then
                local d = math.sqrt((me_m.x - sp.x) ^ 2 + (me_m.y - sp.y) ^ 2)
                if not best[sp.map] or d < best[sp.map].dist then
                    best[sp.map] = {map = sp.map, kind = 'warp', mob = nil, dist = d, spot = {x = sp.x, y = sp.y},
                                    name = MAPINFO[sp.map] and MAPINFO[sp.map].label}
                end
            end
        end
        for _, dv in pairs(best) do list[#list + 1] = dv end
        -- v5.30: an Escha / Abyssea entrance not loaded yet: where it stands
        for _, mkey in ipairs({'escha', 'abyssea'}) do
            local live = false
            for _, dv in ipairs(list) do if dv.map == mkey and dv.kind == 'enter' then live = true end end
            local sp = (not live) and N.maps[mkey] and enter_spot(mkey, here)
            if sp then
                list[#list + 1] = {map = mkey, kind = 'enter', mob = nil, spot = {x = sp.x, y = sp.y}, radius = sp.r,
                                   dist = math.sqrt((me_m.x - sp.x) ^ 2 + (me_m.y - sp.y) ^ 2), name = sp.name}
            end
        end
    end
    return list
end
-- v5.13: the NPC an option talks to: the one seen, else the first that shows
-- up near the spot the data gives (warp NPCs load a few seconds after zoning)
local function dev_name(o)
    local dv = o.dev
    return (dv.mob and dv.mob.name) or dv.name or (o.tr and o.tr.name) or 'warp'
end
local function resolve_dev(o)
    local dv = o.dev
    if dv.mob then
        local m = windower.ffxi.get_mob_by_index(dv.mob.index)
        if m and m.valid_target then return m end
    end
    local names
    if o.kind == 'npc' then names = {[o.tr.name] = true}
    else
        local map = N.maps[o.map]
        names = map and map.npc_names and map.npc_names[dv.kind or 'warp']
    end
    if not names then return nil end
    local best, bd = nil, nil
    for idx, name in pairs(windower.ffxi.get_mob_list() or {}) do
        if type(name) == 'string' and name ~= '' then
            local hit = false
            for n in pairs(names) do if type(n) == 'string' and name:sub(1, #n) == n then hit = true; break end end
            if hit then
                local m = windower.ffxi.get_mob_by_index(idx)
                if m and m.valid_target and (m.id or 0) > 0 and tonumber(m.x) then
                    local sd = dv.spot and math.sqrt((m.x - dv.spot.x) ^ 2 + (m.y - dv.spot.y) ^ 2) or math.sqrt(m.distance or 0)
                    if (not dv.spot or sd <= (dv.radius or 20)) and (not bd or sd < bd) then best, bd = m, sd end
                end
            end
        end
    end
    if best then dv.mob = best end
    return best
end

-- v5.11/v5.12: talking to a zone-moving NPC in this zone, as an option
local function npc_option(tr, spd)
    local mob, d = nil, nil
    for idx, name in pairs(windower.ffxi.get_mob_list() or {}) do
        if name == tr.name then
            local m = windower.ffxi.get_mob_by_index(idx)
            if m and m.valid_target and (m.id or 0) > 0 then
                local md = math.sqrt(m.distance or 0)
                if not d or md < d then mob, d = m, md end
            end
        end
    end
    local myself = windower.ffxi.get_mob_by_target('me')
    if not d and myself and myself.x and tr.x then d = math.sqrt((myself.x - tr.x) ^ 2 + (myself.y - tr.y) ^ 2) end
    d = d or 0
    return {kind = 'npc', map = 'transport', tr = tr, dev = {mob = mob, dist = d, spot = tr.x and {x = tr.x, y = tr.y} or nil, name = tr.name}, to = tr.to,
            entry = {map = 'transport', zone_name = zname(tr.to), label = zname(tr.to), zone_id = tr.to, data = {x = tr.tx, y = tr.ty}},
            time = d / spd + 6 + opt('zone_seconds')}
end

-- v5.39: where a warp lands you: the warp data's spot, else where that warp
-- stands in its zone (nav_zones spots / seen in game). Survival Guides have no
-- spot in the warp data, so their walk to an NPC wasn't counted and they won
-- over Home Points that land much closer (Mark, 2026-11-23: Eastern Adoulin
-- -> Delivery Crate in Ru'Lude Gardens went Survival Guide, then Home Point #2
-- -> #1 in Ru'Lude, instead of Home Point -> Ru'Lude #1).
local function land_spot(mkey, e)
    local d = e and e.data
    if d and tonumber(d.x) and tonumber(d.y) then return d.x, d.y end
    local z = e and e.zone_id
    if not (z and mkey) then return nil end
    for _, sp in ipairs(SPOTS[z] or {}) do if sp[1] == mkey then return sp[2], sp[3] end end
    for _, sp in ipairs(seen_warps and seen_warps(z) or {}) do if sp.map == mkey then return sp.x, sp.y end end
    return nil
end

-- every way to get to zone T in one step
local function options_for(T, devs, here, spd, extra, hops, via, tgt)
    local out = {}
    local zs = opt('zone_seconds')
    local menu = opt('menu_seconds')
    local function add(o)
        o.time = (o.time or 0) + (extra or 0)
        o.hops, o.via, o.to = hops or 0, via, T
        -- an NPC / spot: walk from where the warp lands (when the warp data has it)
        local lx, ly = land_spot(o.map, o.entry)   -- v5.39
        if tgt and lx then
            o.arrive = math.sqrt((lx - tgt.x) ^ 2 + (ly - tgt.y) ^ 2)
            o.time = o.time + o.arrive / spd
        end
        out[#out + 1] = o
    end
    for _, dv in ipairs(devs) do
        local walk = dv.dist / spd
        if dv.kind == 'warp' then
            local same_ok = (dv.map == 'homepoints' or dv.map == 'waypoints' or dv.map == 'escha' or dv.map == 'abyssea')
            for _, e in ipairs(BY_MAP[dv.map] or {}) do
                if e.zone_id == T and (T ~= here or same_ok) then
                    local lk = locked(e)
                    if not (lk and opt('hide_locked')) then
                        add({kind = 'device', map = dv.map, dev = dv, entry = e, locked = lk,
                             time = walk + (menu[dv.map] or 6) + ((T ~= here) and zs or 2)})
                    end
                end
            end
        else
            local dz, key = enter_dest(dv.map, dv.kind, here)
            if dz == T then
                add({kind = 'device', map = dv.map, dev = dv, sub_cmd = dv.kind, learn_key = key,
                     entry = {map = dv.map, zone_name = zname(T), label = zname(T), zone_id = T},
                     time = walk + (menu[dv.map] or 6) + zs})
            end
        end
    end
    -- v5.11: an NPC here that takes you to T
    -- v5.22: one inside your Mog House only from in there; from outside the
    -- step is "go into your Mog House" first
    if T ~= here then
        local inside = in_mog_house()
        for _, tr in ipairs(tr_from(here)) do
            if tr.to == T then
                if not tr.mh or inside then
                    add(npc_option(tr, spd))
                else
                    add({kind = 'mh', tr = tr, to = T, time = 25 + zs})
                end
            end
        end
    end
    if T ~= here and not NO_WARP_OUT[here] then   -- v5.35: not out of Mog Garden
        local delay = (AA_CFG and type(AA_CFG.party) == 'table' and AA_CFG.party.warp_ring_delay) or 11
        for _, it in ipairs(ITEMS) do
            if item_dest(it.dest) == T and item_ready(it.name) and have_item(it.name, it.kind == 'ring' and RING_BAGS or {0}) then
                add({kind = it.kind, name = it.name, home = (it.dest == 'home'),
                     time = (it.kind == 'ring' and (delay + opt('ring_seconds')) or 4) + zs})
            end
        end
        for _, s in ipairs(SPELLS) do
            if item_dest(s.dest) == T then
                local ok, sp = spell_ok(s.name)
                if ok then
                    add({kind = 'spell', name = s.name, home = (s.dest == 'home'), time = (sp.cast_time or 5) + 2 + zs})
                end
            end
        end
    end
    return out
end

local function sort_opts(list)
    table.sort(list, function(a, b)
        local la, lb = a.locked and 1 or 0, b.locked and 1 or 0
        if la ~= lb then return la < lb end
        if opt('proto_last') then
            local pa = a.map == 'protowaypoints' and 1 or 0
            local pb = b.map == 'protowaypoints' and 1 or 0
            if pa ~= pb then return pa < pb end
        end
        return a.time < b.time
    end)
    return list
end

-- v5.12: the warps of zone z (spots from the warp data, else nav_zones.lua spots)
local function zone_devices(z)
    local list = {}
    for _, mkey in ipairs({'homepoints', 'waypoints', 'escha', 'abyssea'}) do
        for _, e in ipairs(BY_MAP[mkey] or {}) do
            local d = e.data
            if e.zone_id == z and d and tonumber(d.x) and tonumber(d.y) and d.index then
                list[#list + 1] = {map = mkey, x = d.x, y = d.y}
            end
        end
    end
    for _, sp in ipairs(SPOTS[z] or {}) do list[#list + 1] = {map = sp[1], x = sp[2], y = sp[3]} end
    for _, sp in ipairs(seen_warps and seen_warps(z) or {}) do list[#list + 1] = sp end   -- v5.33
    return list
end
-- leaving this zone: by an NPC (Faurie) or walking into a zone next door
local function first_legs(here, spd)
    local legs = {}
    local m = windower.ffxi.get_mob_by_target('me')
    local by_npc = {}
    for _, tr in ipairs(tr_from(here)) do
        local o = npc_option(tr, spd)
        by_npc[tr.to] = true
        if tr.to then
            legs[#legs + 1] = {z = tr.to, first = o, time = o.time, land = tr.tx and {x = tr.tx, y = tr.ty} or nil}
        end
    end
    for _, n in ipairs(ADJ[here] or {}) do
        if not by_npc[n] then
            local door, back = DOORS[here .. '>' .. n], DOORS[n .. '>' .. here]
            local o = {kind = 'walk', to = n, hops = 1, time = opt('hop_seconds')}
            if door and m and m.x then
                o.arrive = math.sqrt((m.x - door[1]) ^ 2 + (m.y - door[2]) ^ 2)
                o.door = door
                o.time = o.arrive / spd + 5
            end
            legs[#legs + 1] = {z = n, first = o, time = o.time, land = back and {x = back[1], y = back[2]} or nil}
        end
    end
    return legs
end
-- two legs: leave here (NPC / walk), then a warp in that zone to T
local function two_legs(T, here, spd, tgt)
    local out = {}
    local menu, zs = opt('menu_seconds'), opt('zone_seconds')
    for _, leg in ipairs(first_legs(here, spd)) do
        if leg.z ~= T then
            for _, dv in ipairs(zone_devices(leg.z)) do
                local walk = leg.land and math.sqrt((leg.land.x - dv.x) ^ 2 + (leg.land.y - dv.y) ^ 2) / spd or 30 / spd
                for _, e in ipairs(BY_MAP[dv.map] or {}) do
                    if e.zone_id == T then
                        local lk = locked(e)
                        if not (lk and opt('hide_locked')) then
                            local o = {kind = 'leg', first = leg.first, z = leg.z, map = dv.map, entry = e, locked = lk, to = T, hops = 0,
                                       time = leg.time + walk + (menu[dv.map] or 6) + zs}
                            local lx, ly = land_spot(dv.map, e)   -- v5.39
                            if tgt and lx then
                                o.arrive = math.sqrt((lx - tgt.x) ^ 2 + (ly - tgt.y) ^ 2)
                                o.time = o.time + o.arrive / spd
                            end
                            out[#out + 1] = o
                        end
                    end
                end
            end
        end
    end
    return out
end

local function is_jump(o) return o.kind == 'device' or o.kind == 'npc' or o.kind == 'mh' or o.kind == 'leg' or o.kind == 'ring' or o.kind == 'item' or o.kind == 'spell' end

-- v5.33: nav.via -- the zone this character likes to go through to reach T
local function via_pref(T)
    local v = opt('via')
    if type(v) ~= 'table' then return nil end
    local e = v[zname(T)] or v[T] or v[tostring(T)]
    if type(e) == 'table' then e = e[my_name()] or e.default end
    if type(e) == 'number' then return e end
    if type(e) == 'string' and e ~= '' then
        local zn, npc = e:match('^%s*(.-)%s*/%s*(.-)%s*$')   -- v5.37: "<zone> / <NPC>"
        if not zn then zn = e end
        return ZID[zn:lower()], (npc and npc ~= '') and npc or nil
    end
    return nil
end
-- the zone (and NPC) an option goes through on its last step into T
local function gate_zone(o, T)
    if o.then_npc then return o.via, o.then_npc end
    if o.then_mh then return o.via, o.then_mh end
    if (o.kind == 'npc' or o.kind == 'mh') and o.tr and o.tr.to == T then return o.tr.zone, o.tr.name end
    return nil
end

-- every way to zone T (or to a landmark lm), fastest first
local function route(T, lm, devs, tgt)
    local here = zone_id()
    devs = devs or devices_here()
    local spd = speed()
    local out = {}
    if lm then
        -- a place: its own warp gets you there exactly; otherwise go to its zone
        local menu = opt('menu_seconds')
        for _, dv in ipairs(devs) do
            if dv.kind == 'warp' and dv.map == lm.map then
                local lk = locked(lm)
                if not (lk and opt('hide_locked')) then
                    out[#out + 1] = {kind = 'device', map = dv.map, dev = dv, entry = lm, locked = lk, to = lm.zone_id, hops = 0,
                                     time = dv.dist / spd + (menu[dv.map] or 6) + ((lm.zone_id ~= here) and opt('zone_seconds') or 2)}
                end
            end
        end
        local usable = false
        for _, o in ipairs(out) do if not o.locked then usable = true end end
        if usable or not lm.zone_id then return sort_opts(out) end
        T = lm.zone_id
    end
    if not T then return out end
    if T == here then
        local o = {kind = 'here', to = T, hops = 0, time = 0}
        local m = tgt and windower.ffxi.get_mob_by_target('me')
        if m and m.x then
            o.arrive = math.sqrt((m.x - tgt.x) ^ 2 + (m.y - tgt.y) ^ 2)
            o.time = o.arrive / spd
        end
        out[#out + 1] = o
    end
    for _, o in ipairs(options_for(T, devs, here, spd, lm and 0.5 or 0, nil, nil, tgt)) do out[#out + 1] = o end
    local from_here = nearby(here, opt('max_hops'))
    local npc_out = false   -- v5.11: an NPC is the way out of here to T (Chateau: Faurie) -- no "walk"
    for _, tr in ipairs(tr_from(here)) do if tr.to == T then npc_out = true end end
    if from_here[T] and from_here[T] > 0 and not npc_out then
        local o = {kind = 'walk', to = T, hops = from_here[T], time = from_here[T] * opt('hop_seconds')}
        -- v5.10: next door with a known way in -- the real walk to it
        local door = from_here[T] == 1 and DOORS[here .. '>' .. T]
        local m = door and windower.ffxi.get_mob_by_target('me')
        if m and m.x then
            o.arrive = math.sqrt((m.x - door[1]) ^ 2 + (m.y - door[2]) ^ 2)
            o.time = o.arrive / spd + 5
        end
        out[#out + 1] = o
    end
    local direct = false
    for _, o in ipairs(out) do if is_jump(o) and not o.locked then direct = true end end
    if not direct and T ~= here then
        -- no warp into T: warp to a zone near it -- to the warp that lands
        -- closest to that zone's way toward T -- then walk
        -- v5.10: also the zone you are in (a Home Point / Waypoint in this
        -- zone can put you right by the way in); with a known way in, the
        -- walk to it is counted exactly and only the zones after it are guessed
        local near, par = nearby(T, opt('max_hops'))
        for z, h in pairs(near) do
            if h > 0 then
                local door = DOORS[z .. '>' .. tostring(par[z])]
                local dt = door and {x = door[1], y = door[2]} or nil
                local extra = dt and ((h - 1) * opt('hop_seconds') + 5) or (h * opt('hop_seconds'))
                for _, o in ipairs(options_for(z, devs, here, spd, extra, h, z, dt)) do
                    o.to, o.next = T, par[z]
                    out[#out + 1] = o
                end
            end
        end
        -- v5.12: nothing here gets you there (Chateau has no warp): first leave
        -- by an NPC or on foot, then use a warp in the next zone
        for _, o in ipairs(two_legs(T, here, spd, tgt)) do out[#out + 1] = o end
        -- v5.30: get to a zone with an Escha / Abyssea entrance into T (Dim.
        -- Ring to the crag), then use it -- AA carries on there by itself
        local seen_k = {}
        local function try_enter(k, dest)
            local mkey, kind, fz = tostring(k):match('^(%a+):(%a+):(%d+)$')
            fz = tonumber(fz)
            if not (mkey and kind == 'enter' and fz and dest == T and fz ~= here and fz ~= T and not seen_k[k]) then return end
            seen_k[k] = true
            local sp = enter_spot(mkey, fz)
            local menu = opt('menu_seconds')
            local extra = (menu[mkey] or 6) + opt('zone_seconds')
            for _, o in ipairs(options_for(fz, devs, here, spd, extra, 1, fz, sp and {x = sp.x, y = sp.y} or nil)) do
                if o.kind ~= 'npc' and o.kind ~= 'mh' then
                    o.to, o.then_npc = T, (sp and sp.name) or (mkey == 'abyssea' and 'Cavernous Maw') or 'the entrance'
                    out[#out + 1] = o
                end
            end
        end
        for k, dest in pairs(N.learned or {}) do if type(dest) == 'number' then try_enter(k, dest) end end
        for k, dest in pairs(ENTER_SEED) do if not (N.learned and N.learned[k]) then try_enter(k, dest) end end
        -- v5.11: get to a zone with an NPC that takes you to T, then talk to it
        for _, tr in ipairs(TR_TO[T] or {}) do
            if tr.zone ~= here and tr_allowed(tr) then
                local tgt2, extra, then_txt = (tr.x and {x = tr.x, y = tr.y}) or nil, 6, tr.name
                if tr.mh then   -- v5.22: land by the Mog House, go in, talk to it
                    tgt2, extra, then_txt = nil, 25, nil
                    for _, lm in ipairs(LANDMARKS) do
                        if lm.zone_id == tr.zone and lm.sub == 'Mog House' and lm.data and lm.data.x then
                            tgt2 = {x = lm.data.x, y = lm.data.y}
                            break
                        end
                    end
                end
                for _, o in ipairs(options_for(tr.zone, devs, here, spd, extra, 1, tr.zone, tgt2)) do
                    if o.kind ~= 'npc' and o.kind ~= 'mh' then
                        o.to, o.then_npc, o.then_mh = T, then_txt, tr.mh and tr.name or nil
                        out[#out + 1] = o
                    end
                end
            end
        end
    end
    -- v5.32: no Home Point / book / warp in this zone: Warp Ring (or Warp) to
    -- your Home Point, then the Home Point there (Mark, 2026-11-23)
    if T ~= here and N.home ~= T and not NO_WARP_OUT[here] then   -- v5.35
        local warp_here = false
        for _, dv in ipairs(devs) do if dv.kind == 'warp' then warp_here = true end end
        local hz = N.home
        local ok_t = false
        local onward = false   -- v5.33: T has no Home Point (Mog Garden): warp home, then on from there
        if not warp_here and hz ~= here then
            for _, e in ipairs(BY_MAP.homepoints or {}) do
                if e.zone_id == T and not locked(e) then ok_t = true; break end
            end
            if not ok_t then ok_t, onward = true, true end
        end
        if ok_t then
            local zs = opt('zone_seconds')
            local hp = (opt('menu_seconds').homepoints or 6) + zs
            local delay = (AA_CFG and type(AA_CFG.party) == 'table' and AA_CFG.party.warp_ring_delay) or 11
            local function add_home(o)
                o.home, o.via_home, o.via, o.to, o.hops = true, true, hz, T, 0
                o.then_warp = onward and ('on to ' .. zname(T)) or ('Home Point -> ' .. zname(T))
                o.time = o.time + hp + (onward and 30 or 0)
                out[#out + 1] = o
            end
            for _, it in ipairs(ITEMS) do
                if it.dest == 'home' and item_ready(it.name) and have_item(it.name, it.kind == 'ring' and RING_BAGS or {0}) then
                    add_home({kind = it.kind, name = it.name, time = (it.kind == 'ring' and (delay + opt('ring_seconds')) or 4) + zs})
                end
            end
            for _, sp in ipairs(SPELLS) do
                if sp.dest == 'home' then
                    local ok, sd = spell_ok(sp.name)
                    if ok then add_home({kind = 'spell', name = sp.name, time = (sd.cast_time or 5) + 2 + zs}) end
                end
            end
        end
    end
    -- v5.44: Walk of Echoes: its conflux even when a warp would do
    local prefer_exit = PREFER_EXIT[here] and T ~= here
    local legs_n = 0
    if prefer_exit and direct then
        for _, o in ipairs(two_legs(T, here, spd, tgt)) do out[#out + 1] = o; legs_n = legs_n + 1 end
    elseif prefer_exit then
        for _, o in ipairs(out) do if o.kind == 'leg' then legs_n = legs_n + 1 end end
    end
    -- v5.23: still nothing (Mog Garden): leave by its way out, then carry on
    local any = false
    for _, o in ipairs(out) do if is_jump(o) or o.kind == 'walk' or o.kind == 'here' then any = true end end
    if (not any or (prefer_exit and legs_n == 0)) and T ~= here then
        -- v5.24: an NPC way out of here (Mog Garden: Green Thumb Moogle ->
        -- Eastern Adoulin), then work out the rest from where it lands
        local inside = in_mog_house()
        for _, tr in ipairs(tr_from(here)) do
            local back = N.came_from and tr.to == N.came_from and os.clock() - (N.came_t or -999) < 180   -- v5.33
            if tr.to and (not tr.mh or inside) and not back then
                local o = npc_option(tr, spd)
                o.exit, o.to, o.time = true, T, o.time + 2 * opt('hop_seconds')
                o.entry = {map = 'transport', zone_name = zname(tr.to), label = zname(tr.to), zone_id = tr.to, data = {}}
                out[#out + 1] = o
            end
        end
        for _, ex in ipairs(EXITS[here] or {}) do
            local tr = {name = ex.name, zone = here, x = ex.x, y = ex.y, to = nil, auto = false, exit = true}
            local o = npc_option(tr, spd)
            o.kind, o.exit, o.to, o.time = 'npc', true, T, o.time + opt('hop_seconds')
            o.entry = {map = 'transport', zone_name = 'out of ' .. zname(here), label = 'out of ' .. zname(here), zone_id = nil, data = {}}
            out[#out + 1] = o
        end
    end
    sort_opts(out)
    -- v5.33: your preferred way in (nav.via) first
    local pz, pn = nil, nil
    if T then pz, pn = via_pref(T) end
    if pz and pz ~= here and T ~= here then
        -- v5.37: your way in even when another way is right here (Port San
        -- d'Oria's Mog Dinghy): get to that zone, then talk to the NPC
        local have = false
        for _, o in ipairs(out) do if gate_zone(o, T) == pz then have = true end end
        if not have then
            for _, tr in ipairs(TR_TO[T] or {}) do
                if tr.zone == pz and (not pn or tr.name == pn) and not tr.mh then
                    for _, o in ipairs(options_for(pz, devs, here, spd, 6, 1, pz, tr.x and {x = tr.x, y = tr.y} or nil)) do
                        if o.kind ~= 'npc' and o.kind ~= 'mh' then
                            o.to, o.then_npc = T, tr.name
                            out[#out + 1] = o
                        end
                    end
                end
            end
            sort_opts(out)
        end
    end
    -- v5.41 (v5.42: after every re-sort): a Home Point or Survival Guide in this zone: Warp Ring / Instant
    -- Warp / Warp / Warp II (to your Home Point) go below the other ways (Mark,
    -- 2026-11-23: "make sure that Instant Warp or Warp Ring or Warp option are
    -- not the top option, when there are HPs or Books that a player can access")
    local book_here = false
    for _, dv in ipairs(devs or {}) do
        if dv.kind == 'warp' and (dv.map == 'homepoints' or dv.map == 'survivalguides') then book_here = true end
    end
    if book_here then
        local a, b, c = {}, {}, {}   -- usable ways, home warps, locked ones
        for _, o in ipairs(out) do
            if o.home and (o.kind == 'ring' or o.kind == 'item' or o.kind == 'spell') then b[#b + 1] = o
            elseif o.locked then c[#c + 1] = o
            else a[#a + 1] = o end
        end
        if #a > 0 then
            for _, o in ipairs(b) do a[#a + 1] = o end
            for _, o in ipairs(c) do a[#a + 1] = o end
            out = a
        end
    end
    -- v5.44: Walk of Echoes: ways out by its conflux first, warps after
    if prefer_exit then
        local a, b = {}, {}
        for _, o in ipairs(out) do
            local by_npc = (o.kind == 'npc') or (o.kind == 'leg' and o.first and o.first.kind == 'npc')
            if by_npc and not o.locked then a[#a + 1] = o else b[#b + 1] = o end
        end
        if #a > 0 then for _, o in ipairs(b) do a[#a + 1] = o end; out = a end
    end
    -- v5.44: Warp Ring before Instant Warp (Mark: "favor Warp Ring before
    -- Instant Warp scroll"): an Instant Warp row goes right after the last
    -- Warp Ring row (when the ring isn't on its reuse timer it is listed)
    do
        local last_ring, items = nil, {}
        for i, o in ipairs(out) do
            if o.kind == 'ring' and o.home then last_ring = i end
        end
        if last_ring then
            local a, moved = {}, {}
            for i, o in ipairs(out) do
                if o.kind == 'item' and o.home and i < last_ring then moved[#moved + 1] = o
                else
                    a[#a + 1] = o
                    if i == last_ring then for _, m in ipairs(moved) do a[#a + 1] = m end end
                end
            end
            out = a
        end
    end
    if pz then
        -- v5.37: only your way in -- other ways in are left out (warps that
        -- land you somewhere first stay: the trip carries on from there)
        local a, b = {}, {}
        for _, o in ipairs(out) do
            local gz, gn = gate_zone(o, T)
            if not o.locked and gz == pz and (not pn or gn == pn) then o.preferred = true; a[#a + 1] = o
            elseif gz == nil then b[#b + 1] = o
            else o.not_pref = true end
        end
        if #a + #b > 0 then
            for _, o in ipairs(b) do a[#a + 1] = o end
            out = a
        end
    end
    return out
end

local function tr_key(tr) return 'npc:' .. tr.zone .. ':' .. tr.name .. ':' .. tostring(tr.to) end

-- ---------------------------------------------------------------------------
-- describing an option
-- ---------------------------------------------------------------------------
local function fmt_time(s)
    if not s or s == math.huge then return '?' end
    s = math.floor(s + 0.5)
    if s >= 60 then return string.format('~%dm%02ds', math.floor(s / 60), s % 60) end
    return string.format('~%ds', s)
end
local function opt_tag(o)
    if o.kind == 'device' then return MAPINFO[o.map].tag end
    if o.kind == 'npc' then return 'NPC' end
    if o.kind == 'mh' then return 'MOGH' end
    if o.kind == 'leg' then return (o.first.kind == 'npc' and 'NPC+' or 'WALK+') .. MAPINFO[o.map].tag end
    if o.kind == 'ring' then return 'RING' end
    if o.kind == 'item' then return 'ITEM' end
    if o.kind == 'spell' then return 'MAGIC' end
    if o.kind == 'walk' then return 'WALK' end
    if o.kind == 'here' then return 'HERE' end
    return '--'
end
local function opt_how(o)
    local s
    if o.kind == 'device' then
        local d = o.dev.dist
        local where = (d <= opt('device_range')) and 'here' or string.format('%dy away', math.floor(d + 0.5))
        if o.sub_cmd then
            s = string.format('%s %s (%s) -> %s', MAPINFO[o.map].label, o.sub_cmd, where, o.entry.label)
        else
            s = string.format('%s %s -> %s', MAPINFO[o.map].label, where, o.entry.label)
        end
    elseif o.kind == 'npc' then
        local d = o.dev.dist
        local where = (d <= opt('device_range')) and 'here' or string.format('%dy away', math.floor(d + 0.5))
        s = string.format('talk to %s (%s) -> %s', o.tr.name, where, o.entry.label)
        if o.exit and not o.tr.to then s = s .. ', then on from there [you pick]'
        elseif o.exit then
            s = s .. ', then on from there'
            if not o.tr.auto and type(N.learned[tr_key(o.tr)]) ~= 'table' then s = s .. ' [1st time: you pick]' end
        elseif not o.tr.auto and type(N.learned[tr_key(o.tr)]) ~= 'table' then s = s .. ' [1st time: you pick]' end
    elseif o.kind == 'mh' then
        s = string.format('go into your Mog House, then talk to %s -> %s', o.tr.name, zname(o.to))
    elseif o.kind == 'leg' then
        local f = o.first
        if f.kind == 'npc' then
            local d = f.dev.dist
            s = string.format('talk to %s (%s) -> %s', f.tr.name, d <= opt('device_range') and 'here' or string.format('%dy away', math.floor(d + 0.5)), zname(o.z))
        else
            s = 'walk to ' .. zname(o.z) .. (f.arrive and string.format(' (way in %dy)', math.floor(f.arrive + 0.5)) or '')
        end
        s = s .. ', then ' .. MAPINFO[o.map].label .. ' -> ' .. o.entry.label
    elseif o.kind == 'ring' or o.kind == 'item' or o.kind == 'spell' then
        local dz = o.via or o.to
        if o.via_home then dz = o.via or nil end
        s = o.name .. ' -> ' .. (dz and zname(dz) or 'your Home Point')
    elseif o.kind == 'walk' then
        s = o.arrive and string.format('walk (next zone, way in %dy from you)', math.floor(o.arrive + 0.5))
            or string.format('walk (%d zone%s from here)', o.hops, o.hops == 1 and '' or 's')
    elseif o.kind == 'here' then
        s = o.arrive and string.format('in this zone, %dy from you', math.floor(o.arrive + 0.5)) or 'you are in this zone'
    elseif o.kind == 'none' then
        s = 'no warp or walking route known from here'
    else
        s = '?'
    end
    if o.arrive and o.kind ~= 'here' and o.kind ~= 'walk' and not o.via and o.arrive >= 15 then
        s = s .. string.format(' (+%dy walk)', math.floor(o.arrive + 0.5))
    end
    if o.then_warp then   -- v5.32: Warp Ring / Warp home, then a warp there
        s = s .. ', then ' .. o.then_warp
    elseif o.then_mh then
        s = s .. ', then go into your Mog House and talk to ' .. o.then_mh
    elseif o.then_npc then
        s = s .. ', then talk to ' .. o.then_npc
    elseif o.via and o.kind ~= 'walk' then
        if o.hops == 1 then s = s .. ', then walk in'
        else s = s .. string.format(', then walk %d zones (via %s)', o.hops, zname(o.next)) end
    end
    if o.locked then s = s .. ' [LOCKED]' end
    if o.preferred then s = s .. ' [your way]' end   -- v5.33
    return s
end

-- ---------------------------------------------------------------------------
-- NPCs: nav_npcs.lua (server project data, read only while searching) +
-- data/nav_npcs_seen.lua (every NPC AA has seen in game, with its spot)
-- ---------------------------------------------------------------------------
local SEEN = nil
local function seen_load()
    if not SEEN then SEEN = read_table(data_file('nav_npcs_seen.lua')) or {} end
    return SEEN
end
-- v5.33: warp NPCs AA has seen in zone z (Home Point #1 in Xarcabard [S] has
-- no spot in the warp data; after zoning it may not have loaded yet)
seen_warps = function(z)
    local ok, S = pcall(seen_load)
    if not (ok and type(S) == 'table') then return {} end
    local out = {}
    local suffix = '\t' .. tostring(z)
    for k, p in pairs(S) do
        if type(k) == 'string' and k:sub(-#suffix) == suffix and type(p) == 'table' then
            local name = k:sub(1, -#suffix - 1)
            local mkey = map_of_npc(name, 'warp')
            if mkey and not (mkey == 'abyssea' and vc_not_abyssea(name, z)) and tonumber(p[1]) and tonumber(p[2]) then
                out[#out + 1] = {map = mkey, x = p[1], y = p[2]}
            end
        end
    end
    return out
end
-- v5.30: an entrance's spot: where AA saw it, else the built-in spot
enter_spot = function(mkey, z)
    local b = ENTER_SPOTS[mkey .. ':' .. tostring(z)]
    if not b then return nil end
    local ok, S = pcall(seen_load)
    local p = ok and type(S) == 'table' and S[b.name .. '\t' .. tostring(z)]
    if type(p) == 'table' and tonumber(p[1]) and tonumber(p[2]) then
        return {name = b.name, x = p[1], y = p[2], r = 25}
    end
    return b
end
local function seen_save()
    local f = io.open(data_file('nav_npcs_seen.lua'), 'w')
    if not f then return end
    local keys = {}
    for k in pairs(SEEN) do keys[#keys + 1] = k end
    table.sort(keys)
    f:write('-- AutoAttack aa nav: NPCs seen in game ["name\\tzone"] = {x, y} (added by AA as you play)\nreturn {\n')
    for _, k in ipairs(keys) do f:write(string.format('    [%q] = {%d, %d},\n', k, SEEN[k][1], SEEN[k][2])) end
    f:write('}\n')
    f:close()
end
local function npc_scan()
    local z = zone_id()
    if z == 0 or not me() then return end
    local S, added = seen_load(), 0
    local party = {}
    for _, m in pairs(windower.ffxi.get_party() or {}) do
        if type(m) == 'table' and m.name then party[m.name] = true end
    end
    for idx, name in pairs(windower.ffxi.get_mob_list() or {}) do
        if type(name) == 'string' and name ~= '' and name ~= '???' and not name:find('\t') and not party[name] then
            local m = windower.ffxi.get_mob_by_index(idx)
            if m and m.is_npc and m.spawn_type ~= 16 and m.spawn_type ~= 14 and tonumber(m.x) and not (m.x == 0 and m.y == 0) then
                local k = name .. '\t' .. z
                if not S[k] then S[k] = {math.floor(m.x + 0.5), math.floor(m.y + 0.5)}; added = added + 1 end
            end
        end
    end
    if added > 0 then seen_save(); dbg('learned ' .. added .. ' NPC spots in ' .. zname(z)) end
end
local function npc_matches(hit, max)
    -- v5.18: an NPC matches by its name or by what it is ("mystery" -> the
    -- Gobbie Mystery Box NPCs; "tenshodo" -> NPCs in that quest ...)
    local chunk = loadfile(windower.addon_path .. 'nav_npcs.lua')
    local ok, list = pcall(chunk or function() return {} end)
    if not (ok and type(list) == 'table') then list = {} end
    local rows, desc_of = {}, {}
    for _, line in ipairs(list) do
        local name, z, x, y, d = line:match('^([^\t]+)\t(%d+)\t(%-?%d+)\t(%-?%d+)\t?(.*)$')
        if name then
            if d == '' then d = nil end
            rows[#rows + 1] = {name, tonumber(z), tonumber(x), tonumber(y), d}
            if d and not desc_of[name] then desc_of[name] = d end
        end
    end
    local hits, have = {}, {}
    local function add(name, z, x, y, d)
        local k = name .. '\t' .. z
        if have[k] or not res.zones[z] or #hits >= max then return end
        have[k] = true
        hits[#hits + 1] = {name = name, zone = z, x = x, y = y, desc = d}
    end
    for k, v in pairs(seen_load()) do   -- seen in game first (newest spot)
        local name, z = k:match('^(.-)\t(%d+)$')
        local d = name and desc_of[name]
        if name and (hit(name) or (d and hit(d))) then add(name, tonumber(z), v[1], v[2], d) end
    end
    for _, r in ipairs(rows) do
        if hit(r[1]) or (r[5] and hit(r[5])) then add(r[1], r[2], r[3], r[4], r[5]) end
        if #hits >= max then break end
    end
    return hits
end

-- ---------------------------------------------------------------------------
-- search -> rows {label, section, opt, code}
-- ---------------------------------------------------------------------------
local function search_with(q, hit)
    local devs = devices_here()
    local zones, others = {}, {}
    for _, z in ipairs(ZLIST) do
        if hit(z.name) then
            local opts = route(z.id, nil, devs)
            if #opts == 0 then opts = {{kind = 'none', to = z.id, hops = 0, time = math.huge}} end
            zones[#zones + 1] = {label = z.name, opts = opts, code = '#z' .. z.id}
        end
    end
    local npcs = {}
    for _, n in ipairs(npc_matches(hit, 150)) do
        local tgt = {x = n.x, y = n.y}
        local opts = route(n.zone, nil, devs, tgt)
        if #opts == 0 then opts = {{kind = 'none', to = n.zone, hops = 0, time = math.huge}} end
        local what = n.desc and n.desc:match('^[^;]+') or nil   -- v5.18: "Gobbie Mystery Box"
        npcs[#npcs + 1] = {label = n.name .. (what and (' [' .. what:sub(1, 24) .. ']') or '') .. ' (' .. zname(n.zone) .. ')',
                           name = n.name, opts = opts, code = string.format('#n%d:%d:%d:%s', n.zone, n.x, n.y, n.name)}
    end
    for i, lm in ipairs(LANDMARKS) do
        if hit(lm.label) then
            local opts = route(nil, lm, devs)
            if #opts > 0 then others[#others + 1] = {label = lm.label, opts = opts, code = '#l' .. i} end
        end
    end
    local function rank(r)
        local n = (r.name or r.label):lower():gsub(' %(.*%)$', '')
        if n == q then return 0 elseif n:sub(1, #q) == q then return 1 end
        return 2
    end
    local function by(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        local la, lb = a.opts[1].locked and 1 or 0, b.opts[1].locked and 1 or 0
        if la ~= lb then return la < lb end
        if a.opts[1].time ~= b.opts[1].time then return a.opts[1].time < b.opts[1].time end
        return a.label < b.label
    end
    table.sort(zones, by)
    table.sort(others, by)
    table.sort(npcs, by)
    -- the same place from two warp systems (HP and WP Auction House ...): keep the fastest
    local kept, seen = {}, {}
    for _, r in ipairs(others) do
        if not seen[r.label] then seen[r.label] = true; kept[#kept + 1] = r end
    end
    others = kept
    local rows = {}
    if #zones == 1 and #others == 0 and #npcs == 0 then
        for _, o in ipairs(zones[1].opts) do
            rows[#rows + 1] = {label = zones[1].label, section = 'zone', opt = o, code = zones[1].code}
        end
    else
        for _, r in ipairs(zones) do rows[#rows + 1] = {label = r.label, section = 'zone', opt = r.opts[1], code = r.code} end
        for _, r in ipairs(others) do rows[#rows + 1] = {label = r.label, section = 'other', opt = r.opts[1], code = r.code} end
        for _, r in ipairs(npcs) do rows[#rows + 1] = {label = r.label, section = 'npc', opt = r.opts[1], code = r.code} end
    end
    return rows
end
-- v5.12: the name as typed; nothing found -> every word's first 4 letters
-- (a typo later in a word: "ghebi damonohe" finds Ghebi Damomohe)
local function search(q)
    q = (q or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    if q == '' then return {} end
    local rows = search_with(q, function(name) return name:lower():find(q, 1, true) ~= nil end)
    if #rows > 0 then return rows end
    local parts = {}
    for w in q:gmatch('%S+') do parts[#parts + 1] = w:sub(1, 4) end
    return search_with(q, function(name)
        local n = name:lower()
        for _, w in ipairs(parts) do if not n:find(w, 1, true) then return false end end
        return true
    end)
end

-- "#z117", "#l12" or a name -> best option, label (party lines)
local function best_for(q)
    q = q or ''
    local z = q:match('^#z(%d+)$')
    if z then return route(tonumber(z))[1], zname(tonumber(z)) end
    local nz, nx, ny, nn = q:match('^#n(%d+):(%-?%d+):(%-?%d+):?(.*)$')
    if nz then
        nz = tonumber(nz)
        local label = (nn and nn ~= '') and (nn .. ' (' .. zname(nz) .. ')') or (zname(nz) .. ' (NPC spot)')
        return route(nz, nil, nil, {x = tonumber(nx), y = tonumber(ny)})[1], label
    end
    local l = q:match('^#l(%d+)$')
    if l then
        local lm = LANDMARKS[tonumber(l)]
        if not lm then return nil, q end
        return route(nil, lm)[1], lm.label
    end
    local rows = search(q)
    if #rows == 0 then return nil, q end
    return rows[1].opt, rows[1].label
end

-- v5.12: the code (#z / #l / #n) behind a party / tell target
local function code_for(q)
    if q:match('^#[zl]%d+$') or q:match('^#n%d+:') then return q end
    local rows = search(q)
    return rows[1] and rows[1].code or nil
end

-- ---------------------------------------------------------------------------
-- the list (texts box; click a line)
-- ---------------------------------------------------------------------------
local hl_hide_fn = nil   -- v5.19: set once the highlight bar exists
-- v5.31: rows drawn the craft GUI way: every clickable line is its own box
-- (dark blue-grey, light text); the one under the mouse gets a lighter box
-- (+50) and white text. The window (N.gui) gives the size and background.
local ROW_BG, ROW_TEXT, ROW_HOVER_TEXT = {24, 24, 36}, {225, 225, 225}, {255, 255, 255}
local ROW_LOCKED = {140, 140, 140}
N.row_objs = {}
local function row_obj(i)
    local t = N.row_objs[i]
    if not t then
        local g = opt('gui')
        t = texts.new('', {
            pos = {x = 0, y = 0},
            bg = {alpha = 255, red = ROW_BG[1], green = ROW_BG[2], blue = ROW_BG[3], visible = true},
            text = {font = g.font, size = g.size, red = ROW_TEXT[1], green = ROW_TEXT[2], blue = ROW_TEXT[3],
                    stroke = {width = 1, alpha = 160, red = 0, green = 0, blue = 0}},
            flags = {draggable = false},
            padding = 0,
        })
        N.row_objs[i] = t
    end
    return t
end
local function rows_hide()
    for _, t in pairs(N.row_objs) do t:hide() end
end
local function gui_close()
    if N.gui then N.gui:hide() end
    rows_hide()
    if hl_hide_fn then hl_hide_fn() end
    N.rows, N.gui_lines = nil, {}
end
local function cs(r, g, b, s) return string.format('\\cs(%d,%d,%d)%s\\cr', r, g, b, s) end
local function gui_show(q, rows, page)
    local g = opt('gui')
    if not N.gui then
        N.gui = texts.new('', {
            pos = {x = g.x, y = g.y},
            bg = {alpha = 215, red = 10, green = 12, blue = 20, visible = true},
            text = {font = g.font, size = g.size, red = 235, green = 235, blue = 235,
                    stroke = {width = 1, alpha = 160, red = 0, green = 0, blue = 0}},
            flags = {draggable = false},
            padding = 3,
        })
    end
    local lines, map, plain = {}, {}, {}
    local function line(s, row, p) lines[#lines + 1] = s; map[#lines] = row; plain[#lines] = p end
    -- v5.21: the title line is the close button ([X])
    local title = string.format(' AA nav "%s"   left-click: go   right-click: whole party        [X] close ', q)
    line(cs(255, 210, 90, title), {close = true}, title)
    -- v5.20: pages of max_rows lines; mouse wheel / the << >> line / aa nav next|prev
    local maxr = math.max(1, tonumber(opt('max_rows')) or 14)
    local pages = math.max(1, math.ceil(#rows / maxr))
    page = math.min(math.max(1, page or 1), pages)
    local first, last = (page - 1) * maxr + 1, math.min(#rows, page * maxr)
    local section = nil
    for i = first, last do
        local r = rows[i]
        if r.section ~= section then
            section = r.section
            line(cs(120, 200, 255, section == 'zone' and ' Zones' or section == 'npc' and ' NPCs'
                                   or ' Other matches (places in a zone)'))
        end
        local o = r.opt
        local s = string.format(' %2d  %-50s %-6s %-8s %s ', i, r.label:sub(1, 50), opt_tag(o), fmt_time(o.time), opt_how(o))
        local p = s
        if o.locked then s = cs(140, 140, 140, s) end
        line(s, r, p)
    end
    if pages > 1 then
        local pl = string.format(' %s  page %d of %d (%d found)  %s    mouse wheel / click << >> / aa nav next | prev ',
            page > 1 and '<< prev' or '       ', page, pages, #rows, page < pages and 'next >>' or '       ')
        line(cs(255, 210, 90, pl), {pager = true}, pl)
    end
    -- v5.31: every line the same width, so the row boxes line up
    local wmax = 0
    for i = 1, #lines do
        local v = plain[i] or lines[i]:gsub('\\cs%(%d+,%d+,%d+%)', ''):gsub('\\cr', '')
        plain[i] = plain[i] or v
        if #v > wmax then wmax = #v end
    end
    local padded = {}
    for i = 1, #lines do
        local pad = string.rep(' ', wmax - #plain[i])
        lines[i] = lines[i] .. pad
        padded[i] = plain[i] .. pad
    end
    N.gui_q, N.gui_page, N.gui_pages = q, page, pages
    N.gui_text, N.gui_plain, N.hover_li = lines, padded, nil
    N.gui:text(table.concat(lines, '\n'))
    N.gui_lines, N.gui_count = map, #lines
    N.rows = rows
    N.gui_locked = {}
    for i, r in pairs(map) do if r and r.opt and r.opt.locked then N.gui_locked[i] = true end end
    N.rows_dirty = true
    N.gui:show()
end
-- v5.20: another page of the list
local function gui_page(step)
    if not (N.gui and N.rows and N.gui_pages and N.gui_pages > 1) then return false end
    local p = math.min(math.max(1, (N.gui_page or 1) + step), N.gui_pages)
    if p == N.gui_page then return true end
    local party = N.gui_party
    gui_show(N.gui_q, N.rows, p)
    N.gui_party = party
    if hl_hide_fn then hl_hide_fn() end
    return true
end

-- v5.17: the line under the mouse is highlighted; v5.19: as a coloured bar
-- behind the line (a Windower prim the size of one line), plus a > in front
local HL = 'aa_nav_hl'
local hl_made = false
local function hl_hide()
    if hl_made then windower.prim.set_visibility(HL, false) end
end
-- v5.31: the craft GUI look -- one box per clickable row; under the mouse
-- the box lights up (+50) and the text turns white. Title / section / page
-- lines stay on the window background.
local CLOSE_BG, CLOSE_TEXT, CLOSE_HOVER_TEXT = {170, 20, 20}, {255, 255, 255}, {255, 225, 60}   -- v5.40: craft's red button
local function row_style(i)
    if i == 1 or i == 'close' then   -- v5.40: the title line's [X] close button
        local t = N.row_objs.close
        if not t then return end
        if N.hover_li == 1 then
            t:bg_color(math.min(255, CLOSE_BG[1] + 50), math.min(255, CLOSE_BG[2] + 50), math.min(255, CLOSE_BG[3] + 50))
            t:color(CLOSE_HOVER_TEXT[1], CLOSE_HOVER_TEXT[2], CLOSE_HOVER_TEXT[3])
        else
            t:bg_color(CLOSE_BG[1], CLOSE_BG[2], CLOSE_BG[3])
            t:color(CLOSE_TEXT[1], CLOSE_TEXT[2], CLOSE_TEXT[3])
        end
        return
    end
    local t = N.row_objs[i]
    if not t then return end
    local hot = (i == N.hover_li)
    local bg = ROW_BG
    if hot then
        t:bg_color(math.min(255, bg[1] + 50), math.min(255, bg[2] + 50), math.min(255, bg[3] + 50))
        t:color(ROW_HOVER_TEXT[1], ROW_HOVER_TEXT[2], ROW_HOVER_TEXT[3])
    else
        t:bg_color(bg[1], bg[2], bg[3])
        local c = (N.gui_locked and N.gui_locked[i]) and ROW_LOCKED or ROW_TEXT
        t:color(c[1], c[2], c[3])
    end
end
-- lay the row boxes over the window's lines (again whenever it moved / changed)
local function rows_layout()
    if not (N.gui and N.gui_text and N.gui:visible()) then return end
    local px, py = N.gui:pos()
    local w, h = N.gui:extents()
    local n = N.gui_count or 0
    if n == 0 or not h or h <= 0 then return end
    local key = px .. ',' .. py .. ',' .. h
    if not N.rows_dirty and key == N.rows_key then return end
    N.rows_dirty, N.rows_key = false, key
    local lh = h / n
    local used = {}
    for i = 1, n do
        local r = N.gui_lines[i]
        if r and not r.close and not r.pager then
            local t = row_obj(i)
            t:text(N.gui_plain[i])
            t:pos(math.floor(px + 0.5), math.floor(py + (i - 1) * lh + 0.5))
            row_style(i)
            t:show()
            used[i] = true
        end
    end
    -- v5.40: [X] close on the title line as its own button (lights up under the mouse)
    local r1, p1 = N.gui_lines[1], N.gui_plain[1]
    local cs_at = (r1 and r1.close and p1) and p1:find('[X] close', 1, true)
    if cs_at and w and w > 0 and #p1 > 0 then
        local t = row_obj('close')
        t:text('[X] close')
        t:pos(math.floor(px + (cs_at - 1) * (w / #p1) + 0.5), math.floor(py + 0.5))
        row_style('close')
        t:show()
        used.close = true
    end
    for i, t in pairs(N.row_objs) do if not used[i] then t:hide() end end
end
N.rows_layout = rows_layout
local function gui_hover(li)
    if not (N.gui and N.gui_text) or li == N.hover_li then return end
    local old = N.hover_li
    N.hover_li = li
    if old then row_style(old) end
    if li then row_style(li) end
end
windower.register_event('unload', function()
    if hl_made then windower.prim.delete(HL) end
    for _, t in pairs(N.row_objs) do t:destroy() end
end)
hl_hide_fn = hl_hide

-- ---------------------------------------------------------------------------
-- doing the warp (a port of SuperWarp's menu runner)
-- ---------------------------------------------------------------------------
local function tell_ctx(ctx, text)
    if ctx and ctx.reply then ctx.reply(text) else windower.add_to_chat(207, '[AA] ' .. text) end
end

local function set_target(index)
    local player = windower.ffxi.get_mob_by_target('me')
    local target = windower.ffxi.get_mob_by_index(index)
    if not (player and target) then return end
    packets.inject(packets.new('incoming', 0x058, {
        ['Player'] = player.id, ['Target'] = target.id, ['Player Index'] = player.index}))
end

-- close whatever menu is open (SuperWarp's reset)
local function release_menu(c)
    windower.packets.inject_incoming(0x052, string.char(0, 0, 0, 0, 0, 0, 0, 0))
    windower.packets.inject_incoming(0x052, string.char(0, 0, 0, 0, 1, 0, 0, 0))
    if c and c.menu and c.npc_id then
        windower.packets.inject_incoming(0x052, ('ICHC'):pack(0, 2, c.menu, 0))
        windower.packets.inject_incoming(0x052, string.char(0, 0, 0, 0, 1, 0, 0, 0))
        local pk = packets.new('outgoing', 0x05B)
        pk['Target'] = c.npc_id
        pk['Option Index'] = 0
        pk['_unknown1'] = 16384
        pk['Target Index'] = c.npc_index
        pk['Automated Message'] = false
        pk['_unknown2'] = 0
        pk['Zone'] = zone_id()
        pk['Menu ID'] = c.menu
        packets.inject(pk)
    end
end

local start_device   -- forward

local function fail(c, why)
    if N.cur == c then N.cur = nil end
    if N.pending and N.pending.c == c then N.pending = nil end
    tell_ctx(c.ctx, my_name() .. ': nav failed -- ' .. why)
end

local function retry_or_fail(c, why)
    release_menu(c)
    if N.cur == c then N.cur = nil end
    if (c.retries or 0) < 1 then
        say(why .. ' -- trying once more.')
        coroutine.schedule(function() start_device(c.opt, c.ctx, (c.retries or 0) + 1) end, 2)
    else
        fail(c, why .. '.')
    end
end

local function next_action()
    local c = N.cur
    if not (c and c.running) then return end
    local a = c.queue[c.i]
    if a == nil then
        dbg('all warp steps sent')
        c.running = false
        N.cur = nil
        if c.on_done then   -- v5.32: a step that doesn't move you (bought a key item)
            if N.pending and N.pending.c == c then N.pending.t = os.clock() end
            return c.on_done()
        end
        if not (c.last and c.last.expecting_zone) then
            if N.pending and N.pending.c == c then N.pending = nil end
            tell_ctx(c.ctx, my_name() .. ': at ' .. c.label .. '.')
            if N.on_same_zone_done then N.on_same_zone_done() end   -- v5.31: then find the NPC
        end
        return
    end
    if a.wait_packet then
        if not a.waiting then
            a.waiting = true
            local i = c.i
            coroutine.schedule(function()
                if N.cur == c and c.i == i and a.wait_packet then
                    dbg(string.format('no answer 0x%03X (step %d %s)', a.wait_packet, i, tostring(a.description)))
                    retry_or_fail(c, 'the warp menu did not answer')
                end
            end, a.timeout or 3)
        end
        return
    end
    if a.delay and a.delay > 0 then
        local d = a.delay
        a.delay = nil
        coroutine.schedule(next_action, d)
        return
    end
    if a.packet then
        dbg('step ' .. c.i .. ': ' .. tostring(a.description))
        packets.inject(a.packet)
        c.i = c.i + 1
        c.last = a
        if a.message then say(a.message) end
        return next_action()
    end
    if a.fn then
        local ok, cont = pcall(a.fn, a.incoming_packet)
        c.i = c.i + 1
        c.last = a
        if ok and cont then return next_action() end
        release_menu(c)
        return fail(c, 'warp step failed' .. (ok and '' or (': ' .. tostring(cont))))
    end
    c.i = c.i + 1
    return next_action()
end

start_device = function(o, ctx, retries)
    if N.cur then return tell_ctx(ctx, my_name() .. ': a warp is already running.') end
    local mob = windower.ffxi.get_mob_by_index(o.dev.mob.index)
    if not (mob and mob.valid_target and mob.id) then return tell_ctx(ctx, my_name() .. ': the warp NPC is gone.') end
    local d = math.sqrt(mob.distance or 0)
    if d > opt('device_range') then
        return tell_ctx(ctx, my_name() .. string.format(': %s is %dy away.', mob.name, math.floor(d + 0.5)))
    end
    N.gen = N.gen + 1
    local c = {gen = N.gen, type = o.map, npc = mob, activity_settings = o.entry.data or {}, zone = o.entry.zone_name,
               sub_zone = o.entry.sub, sub_cmd = o.sub_cmd, args = {}, poked_npc_id = mob.id, poked_npc_index = mob.index,
               ctx = ctx, opt = o, retries = retries or 0, label = o.entry.label, running = false}
    N.cur = c
    N.pending = {c = c, ctx = ctx, label = o.entry.label, to = o.to, learn_key = o.learn_key, from = zone_id(), t = os.clock()}
    windower.ffxi.run(false)
    set_target(mob.index)
    coroutine.sleep(0.2)
    for try = 1, 3 do
        if N.cur ~= c or c.caught then return end
        dbg('talking to ' .. mob.name .. ' (try ' .. try .. ')')
        packets.inject(packets.new('outgoing', 0x01A, {
            ['Target'] = mob.id, ['Target Index'] = mob.index, ['Category'] = 0, ['Param'] = 0, ['_unknown1'] = 0}))
        coroutine.sleep(try == 1 and 1.5 or 1.75)
    end
    if N.cur == c and not c.caught then fail(c, mob.name .. ' did not answer.') end
end

-- menus: ours are answered by packets (and never drawn); every warp menu's unlock bits are kept
windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if injected then return end
    local c = N.cur
    if c and c.running then
        local a = c.queue[c.i]
        if a and a.wait_packet == id then
            local okp = (id == 0x05C) or (id == 0x052 and data:unpack('b4', 5) ~= 2)
            if id == 0x05B then
                local pp = packets.parse('incoming', data)
                local my = windower.ffxi.get_mob_by_target('me')
                okp = my and pp['ID'] == my.id
            end
            if okp then
                a.wait_packet = nil
                a.incoming_packet = packets.parse('incoming', data)
                coroutine.schedule(next_action, 0)
            end
        end
        if id == 0x052 and data:unpack('b4', 5) == 2 then   -- event skipped (hit, moved ...)
            coroutine.schedule(function() retry_or_fail(c, 'the warp was interrupted') end, 0)
        end
    end
    if id ~= 0x034 and id ~= 0x032 then return end
    local p = packets.parse('incoming', data)
    pcall(record_params, p)
    if not c then return end
    if c.running then return true end   -- no second menu over ours
    if c.caught then return end
    c.caught = true
    c.menu, c.npc_id, c.npc_index = p['Menu ID'], p['NPC'], p['NPC Index']
    if c.poked_npc_id ~= p['NPC'] then
        dbg('menu from another NPC (' .. tostring(p['NPC']) .. ') -- stopping')
        coroutine.schedule(function() release_menu(c); fail(c, 'a different NPC answered.') end, 0.5)
        return true
    end
    local zone = zone_id()
    if c.type == 'transport' then
        -- v5.11: a zone-moving NPC: answer with the remembered / scripted choice,
        -- or (first time, conditions in its script) show the menu and learn
        local tr = c.opt.tr
        local L = N.learned[tr_key(tr)]
        if type(L) ~= 'table' and tr.mh then   -- v5.33: the same moogle menu learned in another town
            for k, v in pairs(N.learned) do
                if type(v) == 'table' and v.menu == p['Menu ID'] and tostring(k):match('^npc:%d+:' .. tr.name:gsub('%p', '%%%0') .. ':' .. tostring(tr.to) .. '$') then L = v; break end
            end
        end
        -- v5.32: a key item to buy first (Kupofried's medallion)
        local need = NEED_KI[tr.zone .. ':' .. tr.name]
        local buying = false
        if need and not has_ki(need.id) then
            local Lb, Bb = N.learned[tr_key(tr) .. ':buy'], N.learned['buy:' .. tr.zone .. ':' .. tr.name]
            if type(Lb) == 'table' then L = Lb
            elseif type(Bb) == 'table' then L, buying = Bb, true
            else L = nil end
        end
        local steps = nil
        if type(L) == 'table' and L.menu == p['Menu ID'] then
            steps = (type(L.seq) == 'string' and L.seq ~= '') and seq_parse(L.seq) or {{menu = L.menu, opt = L.opt, unk = L.unk, auto = false}}
        elseif not need and tr.auto and tr.menu == p['Menu ID'] then
            steps = {{menu = tr.menu, opt = tr.option, unk = tr.unk or 0, auto = false}}
        end
        if steps and #steps > 0 then
            c.queue = {}
            for i, st in ipairs(steps) do
                local pk = packets.new('outgoing', 0x05B)
                pk['Target'] = c.npc_id
                pk['Option Index'] = st.opt
                pk['_unknown1'] = st.unk or 0
                pk['Target Index'] = c.npc_index
                pk['Automated Message'] = st.auto and true or false
                pk['_unknown2'] = 0
                pk['Zone'] = zone
                pk['Menu ID'] = st.menu or p['Menu ID']
                c.queue[#c.queue + 1] = {packet = pk, delay = (i == 1) and 0.3 or 1, expecting_zone = (i == #steps) and not buying,
                                         description = 'choose option ' .. tostring(st.opt)}
            end
            if buying then   -- bought, no zone change: wait for the key item, then talk again to go in
                c.on_done = function()
                    coroutine.schedule(function()
                        local t0 = os.clock()
                        while os.clock() - t0 < 8 and not has_ki(need.id) do coroutine.sleep(0.5) end
                        if not has_ki(need.id) then return fail(c, need.name .. ' did not show up after buying') end
                        tell_ctx(c.ctx, my_name() .. ': bought ' .. need.name .. ' -- going in.')
                        start_device(c.opt, c.ctx)
                    end, 1)
                end
            end
            c.i, c.running = 1, true
            coroutine.schedule(next_action, 0)
            return true
        end
        N.cur = nil
        if N.pending then N.pending.t = os.clock() + 120 end   -- the player is choosing
        coroutine.schedule(function()
            if tr.exit then   -- v5.23: a way out: the goal carries on after the zone change
                tell_ctx(c.ctx, string.format('%s: pick where %s should take you; AA remembers it and carries on from there.', my_name(), tr.name))
            elseif need and not has_ki(need.id) then   -- v5.32
                tell_ctx(c.ctx, string.format('%s: first time with %s -- buy %s (%d gil), then pick %s; AA remembers both.',
                    my_name(), tr.name, need.name, need.gil or 0, zname(tr.to)))
            else
                tell_ctx(c.ctx, string.format('%s: first time with %s -- pick %s%s; AA remembers it.',
                    my_name(), tr.name, zname(tr.to), tr.garden and ' (not "return from whence you came")' or ''))
            end
        end, 0)
        return   -- the menu shows
    end
    local map = N.maps[c.type]
    if map.validate then
        local okv, msg = pcall(map.validate, p['Menu ID'], zone, c, p, SW)
        if okv and msg then
            coroutine.schedule(function() release_menu(c); fail(c, tostring(msg)) end, 0)
            return true
        end
    end
    -- Survival Guides: gil first, tabs only when short on gil (or nav.use_tabs = true)
    SW.use_tabs_at_survival_guides = false
    if c.type == 'survivalguides' and type(p['Menu Parameters']) == 'string' then
        local gil = p['Menu Parameters']:unpack('I', 9) or 0
        local valor = p['Menu Parameters']:unpack('H', 7) or 0
        SW.use_tabs_at_survival_guides = (opt('use_tabs') == true) or (gil < 200 and valor >= 10)
        if SW.use_tabs_at_survival_guides then say('using tabs (' .. (opt('use_tabs') == true and 'nav.use_tabs' or 'under 200 gil') .. ').') end
    end
    local build = c.sub_cmd and map.sub_commands and map.sub_commands[c.sub_cmd] or map.build_warp_packets
    local okb, q = pcall(build, c, zone, p, SW)
    if not okb or type(q) ~= 'table' then
        coroutine.schedule(function() release_menu(c); fail(c, 'could not build the warp: ' .. tostring(q)) end, 0)
        return true
    end
    c.queue, c.i, c.running = q, 1, true
    if #q == 1 and q[1].description == 'cancel menu' then
        -- the map code only cancels (locked / no gil ...): its message says why
        c.label = c.label .. ' (cancelled)'
    end
    coroutine.schedule(next_action, 0)
    return true
end)

-- v5.11: what the player picks at a zone-moving NPC (by nav or by hand) --
-- learned when a zone change follows within 30s
windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
    if id ~= 0x05B or injected then return end
    local p = packets.parse('outgoing', data)
    local mob = p['Target Index'] and windower.ffxi.get_mob_by_index(p['Target Index'])
    if not (mob and type(mob.name) == 'string' and mob.name ~= '') then return end
    -- v5.22: any NPC / object (Mog House moogle, Mog Dinghy, Adoulin NPCs ...),
    -- except the warp systems nav already drives with their own packets
    local z = zone_id()
    local wm = map_of_npc(mob.name, 'warp')
    if wm == 'abyssea' and mob.name:sub(1, 17) == 'Veridical Conflux' then   -- v5.32: not inside Abyssea = not its warp
        local am = N.maps.abyssea
        if not (am and am.abyssea_zones and am.abyssea_zones:contains(z)) then wm = nil end
    end
    if wm or map_of_npc(mob.name, 'enter') or map_of_npc(mob.name, 'exit') then return end
    -- v5.32: every step of this menu (an "update" step like buying, then the
    -- final choice), so a menu of several steps can be replayed
    local ses = N.menu_ses
    if not ses or ses.idx ~= p['Target Index'] or os.clock() - ses.t > 120 then
        local need = NEED_KI[z .. ':' .. mob.name]
        local hk = nil
        if need then hk = has_ki(need.id) end
        ses = {idx = p['Target Index'], seq = {}, t = os.clock(), had_ki = hk}
        N.menu_ses = ses
    end
    ses.seq[#ses.seq + 1] = {menu = p['Menu ID'], opt = p['Option Index'], unk = p['_unknown1'] or 0, auto = p['Automated Message'] and true or false}
    if p['Automated Message'] then return end
    N.choice = {name = mob.name, zone = z, menu = p['Menu ID'], opt = p['Option Index'], unk = p['_unknown1'] or 0,
                x = tonumber(mob.x) and math.floor(mob.x + 0.5), y = tonumber(mob.y) and math.floor(mob.y + 0.5),
                mh = in_mog_house(), t = os.clock(), seq = ses.seq, had_ki = ses.had_ki}
    N.menu_ses = nil   -- a final choice closes the menu
    -- v5.32: a choice that sells the key item (no zone change): learned once it shows up
    local need = NEED_KI[z .. ':' .. mob.name]
    if need and not ses.had_ki then
        N.buy_watch = {key = 'buy:' .. z .. ':' .. mob.name, need = need, seq = ses.seq, t = os.clock()}
    end
end)

-- ---------------------------------------------------------------------------
-- running an option
-- ---------------------------------------------------------------------------
-- v5.09: stop the walk to a warp NPC (only ever stops AA's own walking)
local function walk_stop(a)
    if a and a.running then windower.ffxi.run(false); a.running = false end
end

-- ---------------------------------------------------------------------------
-- v5.12: finding an NPC / object in your zone: where it is, which way to walk,
-- and the cursor on it once it's close enough to target
-- ---------------------------------------------------------------------------
local function seek_find(sk)
    local best, bd = nil, nil
    for idx, name in pairs(windower.ffxi.get_mob_list() or {}) do
        if name == sk.name then
            local m = windower.ffxi.get_mob_by_index(idx)
            if m and (m.id or 0) > 0 and tonumber(m.x) then
                local d = math.sqrt(m.distance or 0)
                if not bd or d < bd then best, bd = m, d end
            end
        end
    end
    return best, bd
end
local function start_seek(name, zone, x, y, ctx, guide)
    N.seek = {name = name, zone = zone, x = x, y = y, ctx = ctx, t_end = os.clock() + opt('seek_timeout'), said = 0, first = true,
              guide = guide}
end
-- v5.16: walking on toward the goal: guide to the way into the next zone (every
-- seek_every s) and keep the goal, so AA carries on after the zone change
local function guide_walk(to, ctx)
    local here = zone_id()
    local near, par = nearby(to, opt('max_hops'))
    local nxt = (near[here] == 1) and to or par[here]   -- the next zone on the way
    local door = nxt and DOORS[here .. '>' .. nxt]
    if N.goal then N.goal.legs = math.max(N.goal.legs, (near[here] or 1) + 1) end
    if door then
        start_seek('the way into ' .. zname(nxt), here, door[1], door[2], ctx, true)
        return true
    end
    return false
end
-- v5.15: ways to put the cursor on an NPC, tried in turn (each logged at level 2)
local TARGET_WAYS = {'packet', 'name', 'first name', 'targetnpc'}
local function seek_tick(now)
    local sk = N.seek
    if not sk then return end
    if zone_id() ~= sk.zone or now > sk.t_end then N.seek = nil; return end
    local m = windower.ffxi.get_mob_by_target('me')
    if not (m and m.x) then return end
    local mob, d = nil, nil
    if not sk.guide then mob, d = seek_find(sk) end
    local cur = windower.ffxi.get_mob_by_target('t')
    if mob and cur and cur.id == mob.id then
        N.seek = nil
        return tell_ctx(sk.ctx, string.format('%s: %s is targeted -- %dy %s of you.', my_name(), sk.name,
            math.floor(d + 0.5), compass(m.x, m.y, mob.x, mob.y)))
    end
    if mob and mob.valid_target and d <= opt('seek_range') and not sk.busy and now >= (sk.retry_at or 0) then
        sk.busy = true
        coroutine.schedule(function()
            local ok = false
            for _, way in ipairs(TARGET_WAYS) do
                local t0 = windower.ffxi.get_mob_by_index(mob.index)
                local me_m = windower.ffxi.get_mob_by_target('me')
                if N.seek ~= sk or not (t0 and t0.valid_target and me_m and me_m.x) then break end
                local skip = false
                if way == 'packet' then
                    set_target(t0.index)
                elseif way == 'name' then
                    send('input /target "' .. t0.name .. '"')
                elseif way == 'first name' then
                    if not t0.name:find(' ') then skip = true else send('input /target ' .. t0.name:match('^(%S+)')) end
                else
                    windower.ffxi.turn(-math.atan2(t0.y - me_m.y, t0.x - me_m.x))
                    send('input /targetnpc')
                end
                if not skip then
                    coroutine.sleep(0.7)
                    local c = windower.ffxi.get_mob_by_target('t')
                    dbg(string.format('target %s (%dy) by %s: cursor on %s', t0.name,
                        math.floor(math.sqrt(t0.distance or 0) + 0.5), way, c and tostring(c.name) or 'nothing'))
                    if c and c.id == t0.id then ok = true; break end
                end
            end
            sk.busy = false
            sk.tries = (sk.tries or 0) + 1
            if N.seek ~= sk then return end
            if ok then
                N.seek = nil
                local me_m = windower.ffxi.get_mob_by_target('me')
                local t1 = windower.ffxi.get_mob_by_index(mob.index)
                local dd = (me_m and t1 and me_m.x) and math.sqrt((t1.x - me_m.x) ^ 2 + (t1.y - me_m.y) ^ 2) or d
                tell_ctx(sk.ctx, string.format('%s: %s is targeted -- %dy %s of you.', my_name(), sk.name, math.floor(dd + 0.5),
                    (me_m and t1 and me_m.x) and compass(me_m.x, me_m.y, t1.x, t1.y) or '?'))
            else
                sk.retry_at = os.clock() + 2   -- keep trying as you get closer
            end
        end, 0)
    end
    if sk.first or now - sk.said >= opt('seek_every') then
        sk.first, sk.said = false, now
        local tx, ty = (mob and mob.x) or sk.x, (mob and mob.y) or sk.y
        if not tx then return end
        local dist = math.sqrt((m.x - tx) ^ 2 + (m.y - ty) ^ 2)
        local note = sk.guide and ' -- walk that way'
                     or ((sk.tries or 0) > 0) and ' -- could not put the cursor on it yet, still trying'
                     or string.format(' -- walk that way; AA targets it at %dy', opt('seek_range'))
        tell_ctx(sk.ctx, string.format('%s: %s is %dy %s of you (X %d, Y %d)%s.',
            my_name(), sk.name, math.floor(dist + 0.5), compass(m.x, m.y, tx, ty), math.floor(tx + 0.5), math.floor(ty + 0.5), note))
    end
end

-- v5.12: the goal of a nav (zone, and the NPC when it is one) -- kept over
-- zone changes so a trip with several legs carries on by itself
local function goal_of(code, label, ctx)
    if not code then return nil end
    local g = {code = code, label = label, ctx = ctx, legs = 3, t = os.clock()}
    local z = code:match('^#z(%d+)$')
    if z then g.to = tonumber(z) end
    local nz, nx, ny, nn = code:match('^#n(%d+):(%-?%d+):(%-?%d+):?(.*)$')
    if nz then
        g.to, g.x, g.y = tonumber(nz), tonumber(nx), tonumber(ny)
        g.npc = (nn and nn ~= '') and nn or nil
    end
    local l = code:match('^#l(%d+)$')
    if l and LANDMARKS[tonumber(l)] then g.to = LANDMARKS[tonumber(l)].zone_id end
    return g.to and g or nil
end

-- v5.34: walking to a warp NPC around things in the way (Mark, 2026-11-23:
-- "there is a BOX obstruction in the way to getting to Dangueubert, so we need
-- to walk wide to the right"). Stuck: turn right (70, then 90 degrees), a little
-- longer each time, then left; still stuck: you walk and AA follows. Every walk that
-- needed a way around is kept as a path (data/nav_learned.lua "path:<zone>:<npc>")
-- and walked point by point next time.
local function path_key(o) return 'path:' .. zone_id() .. ':' .. dev_name(o) end
local function arm_path(a)
    a.crumbs, a.needed = {}, false
    local str = N.learned[path_key(a.o)]
    if type(str) ~= 'string' then return end
    local pts = {}
    for x, y in str:gmatch('(%-?%d+),(%-?%d+)') do pts[#pts + 1] = {x = tonumber(x), y = tonumber(y)} end
    if #pts == 0 then return end
    -- start at the path point nearest to you
    local m = windower.ffxi.get_mob_by_target('me')
    local bi, bd = 1, nil
    if m and tonumber(m.x) then
        for i, pt in ipairs(pts) do
            local d = math.sqrt((m.x - pt.x) ^ 2 + (m.y - pt.y) ^ 2)
            if not bd or d < bd then bi, bd = i, d end
        end
    end
    a.path, a.pi = pts, bi
end
local function crumb(a, m)
    local c = a.crumbs
    local last = c[#c]
    if not last or math.sqrt((m.x - last.x) ^ 2 + (m.y - last.y) ^ 2) >= 4 then
        c[#c + 1] = {x = math.floor(m.x + 0.5), y = math.floor(m.y + 0.5)}
    end
end
local function save_path(a)
    if not (a.needed and a.crumbs and #a.crumbs >= 2) then return end
    local t = {}
    for _, pt in ipairs(a.crumbs) do t[#t + 1] = pt.x .. ',' .. pt.y end
    N.learned[path_key(a.o)] = table.concat(t, ';')
    save_learned()
    dbg('learned a walking path to ' .. dev_name(a.o) .. ' (' .. #t .. ' points)')
end
N.save_path = save_path
local DETOURS = {{70, 2}, {90, 3}, {90, 5}, {-70, 3}, {-90, 5}, {-90, 8}}   -- {degrees right (+) / left (-), seconds}
-- v5.43: walks that start at a known spot with something right in front: bear
-- right (deg) for the first yalms (Mark, 2026-11-23: a post / column right
-- outside the Eastern Adoulin Mog House / Mog Garden spawn -- "side stepping to
-- the right a little as they are walking forward for the 1st 5 yalms")
local START_NUDGES = {
    [257] = {{x = -56, y = -136, r = 6, deg = 35, dist = 5}},   -- Eastern Adoulin: out of the Mog House / Mog Garden
}
local function start_nudge(z, x, y)
    for _, n in ipairs(START_NUDGES[z] or {}) do
        if math.sqrt((x - n.x) ^ 2 + (y - n.y) ^ 2) <= n.r then return n end
    end
    return nil
end

-- v5.31: an in-zone warp is done (no zone change): find the goal's NPC
N.on_same_zone_done = function()
    local g = N.goal
    if g and g.npc and g.to == zone_id() then
        N.goal = nil
        coroutine.schedule(function() start_seek(g.npc, g.to, g.x, g.y, g.ctx) end, 3)
    end
end

local function run_option(o, ctx, label, code, keep_goal)
    local p = me()
    if not p then return end
    if code and not keep_goal then N.goal = goal_of(code, label, ctx) end
    N.seek = nil
    if not o then return tell_ctx(ctx, my_name() .. ': no way to ' .. tostring(label) .. ' from here.') end
    if p.status == 1 then return tell_ctx(ctx, my_name() .. ' is fighting -- not travelling.') end
    if N.cur then return tell_ctx(ctx, my_name() .. ': a warp is already running.') end
    walk_stop(N.armed)
    N.armed = nil
    local what = opt_how(o)
    if o.kind == 'none' then return tell_ctx(ctx, my_name() .. ': no known way to ' .. tostring(label) .. ' from here.') end
    if o.kind == 'here' then
        local g = N.goal
        N.goal = nil
        if g and g.npc and g.to == zone_id() then   -- v5.12: find the NPC
            start_seek(g.npc, g.to, g.x, g.y, ctx)
            return
        end
        return tell_ctx(ctx, my_name() .. ': already in ' .. zname(o.to) .. (o.arrive and string.format(' -- it is %dy from you.', math.floor(o.arrive + 0.5)) or '.'))
    end
    if o.kind == 'leg' then   -- v5.12: first leg now, the rest after the zone change
        if N.goal then N.goal.legs = math.max(N.goal.legs, 2) end
        tell_ctx(ctx, string.format('%s: %s -- %s', my_name(), label, opt_how(o)))
        o = o.first
        label = zname(o.to)
        if o.kind == 'walk' then
            tell_ctx(ctx, my_name() .. ': walk to ' .. label .. '; AA carries on from there.')
            guide_walk(o.to, ctx)
            return
        end
        what = opt_how(o)
    end
    if o.kind == 'mh' then   -- v5.22: the player goes in; AA carries on inside
        if N.goal then N.goal.legs = math.max(N.goal.legs, 2) end
        return tell_ctx(ctx, string.format('%s: %s -- go into your Mog House; inside AA talks to %s for you.', my_name(), label, o.tr.name))
    end
    if o.kind == 'walk' then
        -- v5.16: walking is the way: keep the goal (an NPC at the end still gets
        -- found) and guide to the way into the next zone
        tell_ctx(ctx, string.format('%s: %s -- walk (%d zone%s); AA carries on from there.', my_name(), label, o.hops, o.hops == 1 and '' or 's'))
        if not guide_walk(o.to, ctx) and not N.goal then
            tell_ctx(ctx, my_name() .. ': (no map spot for the way in -- head for ' .. zname(o.to) .. ')')
        end
        return
    end
    if o.locked then return tell_ctx(ctx, my_name() .. ': ' .. what .. ' -- not unlocked on this character.') end
    if aa_running and aa_running() then N.stop_guard = os.clock(); send('aa stop') end   -- v5.19: not a nav stop
    if p.status == 85 or p.status == 5 then send('input /dismount'); coroutine.sleep(1.5) end
    if o.exit and N.goal then N.goal.legs = math.max(N.goal.legs, 3) end   -- v5.23
    if (o.kind == 'npc' or o.kind == 'device') and not o.dev.mob and not o.dev.spot then
        return tell_ctx(ctx, my_name() .. ': can\'t see ' .. dev_name(o) .. ' -- walk closer and try again.')
    end
    if o.kind == 'npc' and o.tr then   -- v5.32: a key item to buy first: enough gil?
        local need = NEED_KI[o.tr.zone .. ':' .. o.tr.name]
        if need and not has_ki(need.id) and need.gil then
            local g = my_gil()
            if g and g < need.gil then
                return tell_ctx(ctx, string.format('%s: %s costs %d gil -- you have %d.', my_name(), need.name, need.gil, g))
            end
        end
    end
    if o.kind == 'device' or o.kind == 'npc' then
        if o.dev.dist > opt('device_range') or not o.dev.mob then
            local walk = o.dev.dist <= (tonumber(opt('walk_range')) or 0)   -- v5.09: close -- AA walks you there
            N.armed = {o = o, ctx = ctx, label = label, t_end = os.clock() + opt('arm_timeout'),
                       walk = walk, best = o.dev.dist, best_t = os.clock()}
            arm_path(N.armed)   -- v5.34
            if walk then
                return tell_ctx(ctx, string.format('%s: %s -- walking to the %s (%dy), then warping.',
                    my_name(), label, dev_name(o), math.floor(o.dev.dist + 0.5)))
            end
            return tell_ctx(ctx, string.format('%s: %s -- walk to the %s (%dy); AA warps when you are within %dy.',
                my_name(), label, dev_name(o), math.floor(o.dev.dist + 0.5), opt('device_range')))
        end
        tell_ctx(ctx, my_name() .. ': going to ' .. label .. ' -- ' .. what)
        return start_device(o, ctx)
    end
    N.pending = {ctx = ctx, label = label, to = o.to, home = o.home, from = zone_id(), t = os.clock()}
    tell_ctx(ctx, my_name() .. ': going to ' .. label .. ' -- ' .. what)
    if o.home then AA_NAV_EXPECT_HOME = os.clock() end
    if o.kind == 'ring' then
        if not aa_nav_ring then N.pending = nil; return tell_ctx(ctx, my_name() .. ': rings need aa_party.lua.') end
        local ok, why = aa_nav_ring(o.name, function(msg)
            N.pending = nil
            tell_ctx(ctx, my_name() .. ': ' .. msg)
            N.used[o.name] = N.used[o.name] or os.time()   -- v5.33: on its timer: another way
            if os.time() - N.used[o.name] > 5 then N.used[o.name] = os.time() end
            save_char()
            local g = N.goal
            if g then
                coroutine.schedule(function()
                    if N.goal ~= g then return end
                    tell_ctx(g.ctx, my_name() .. ': trying another way to ' .. g.label .. '.')
                    run_option(best_for(g.code), g.ctx, g.label, g.code, true)
                end, 2)
            end
        end)
        if not ok then N.pending = nil; tell_ctx(ctx, my_name() .. ': ' .. tostring(why)) end
    elseif o.kind == 'item' then
        send('input /item "' .. o.name .. '" <me>')
    elseif o.kind == 'spell' then
        send('input /ma "' .. o.name .. '" <me>')
    end
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
local function gui_line_at(y)
    local _, py = N.gui:pos()
    local _, h = N.gui:extents()   -- the text itself (the padding is drawn outside it)
    local n = N.gui_count or 0
    if n == 0 or not h or h <= 0 then return nil end
    return math.floor((y - py) / (h / n)) + 1
end
windower.register_event('mouse', function(typ, x, y, delta, blocked)
    if blocked or not (N.gui and N.rows and N.gui:visible()) then return end
    if typ == 10 then   -- v5.20: mouse wheel over the list: up = previous page, down = next
        if N.gui:hover(x, y) and (N.gui_pages or 1) > 1 then
            gui_page(((delta or 0) > 0) and -1 or 1)
            return true
        end
        return
    end
    if typ == 0 then   -- v5.17: mouse moved: highlight the line under it
        if N.gui:hover(x, y) then
            local li = gui_line_at(y)
            gui_hover((li and N.gui_lines[li]) and li or nil)
        elseif N.hover_li then
            gui_hover(nil)
        end
        return
    end
    if typ ~= 1 and typ ~= 2 and typ ~= 4 and typ ~= 5 then return end
    if not N.gui:hover(x, y) then return end
    if typ == 1 or typ == 4 then return true end   -- the press: keep it from the game
    local li = gui_line_at(y)
    if not li then return true end
    local row = N.gui_lines[li]
    if row and row.close then   -- v5.21: [X] on the title line
        gui_close()
    elseif row and row.pager then   -- v5.20: left half = previous page, right half = next
        local px = N.gui:pos()
        local w = N.gui:extents()
        gui_page((x < px + (w or 0) / 2) and -1 or 1)
    elseif row then
        local party = (typ == 5)
        coroutine.schedule(function() N.pick(row, party) end, 0)
    end
    return true
end)

local next_tick, next_scan = 0, 0
windower.register_event('prerender', function()
    if N.rows_layout and N.gui then N.rows_layout() end   -- v5.31
    local bw = N.buy_watch   -- v5.32: the key item showed up after a menu choice: that choice buys it
    if bw then
        if os.clock() - bw.t > 15 then N.buy_watch = nil
        elseif has_ki(bw.need.id) then
            N.buy_watch = nil
            local last = bw.seq[#bw.seq] or {}
            N.learned[bw.key] = {menu = last.menu, opt = last.opt, unk = last.unk, seq = seq_str(bw.seq)}
            save_learned()
            dbg('learned: buying ' .. bw.need.name .. ' = ' .. seq_str(bw.seq))
        end
    end
    local now = os.clock()
    if now < next_tick then return end
    next_tick = now + ((N.armed and N.armed.walk) and 0.1 or 0.5)
    if now >= next_scan then
        next_scan = now + 60
        pcall(npc_scan)
    end
    if N.seek then pcall(seek_tick, now) end
    local mh = in_mog_house()   -- v5.22
    if mh ~= N.last_mh then
        local was = N.last_mh
        N.last_mh = mh
        local g = N.goal
        if was ~= nil and g and g.legs > 1 and zone_id() ~= g.to and os.clock() - (N.last_zone_t or -99) > 6 then
            g.legs = g.legs - 1
            coroutine.schedule(function()
                if N.goal ~= g then return end
                tell_ctx(g.ctx, my_name() .. ': carrying on to ' .. g.label .. '.')
                run_option(best_for(g.code), g.ctx, g.label, g.code, true)
            end, 4)
        end
    end
    local a = N.armed
    if a then
        -- v5.13: the NPC may not be loaded yet (just zoned): head for the spot
        -- the data gives and pick the NPC up once it shows
        local mob = resolve_dev(a.o)
        local m = windower.ffxi.get_mob_by_target('me')
        local d, tx, ty
        if mob then
            d, tx, ty = math.sqrt(mob.distance or 0), mob.x, mob.y
        elseif a.o.dev.spot and m and tonumber(m.x) then
            tx, ty = a.o.dev.spot.x, a.o.dev.spot.y
            d = math.sqrt((m.x - tx) ^ 2 + (m.y - ty) ^ 2)
        end
        local p = me()
        local range = opt('device_range')
        if now > a.t_end or not d then
            walk_stop(a)
            N.armed = nil
            tell_ctx(a.ctx, my_name() .. ': gave up ' .. (a.walk and 'walking' or 'waiting') .. ' to reach the ' .. dev_name(a.o) .. '.')
        elseif a.walk and p and p.status ~= 0 then
            -- fighting / resting / mounted again: stop walking, leave it to the player
            walk_stop(a)
            a.walk = false
            tell_ctx(a.ctx, my_name() .. ': stopped walking to the ' .. dev_name(a.o) .. ' -- walk there and AA warps.')
        elseif mob and d <= range - (a.walk and 2 or 0) then
            walk_stop(a)
            N.armed = nil
            a.o.dev.dist = d
            if N.save_path then pcall(N.save_path, a) end   -- v5.34
            coroutine.schedule(function()
                tell_ctx(a.ctx, my_name() .. ': at the ' .. mob.name .. ' -- warping to ' .. a.label .. '.')
                start_device(a.o, a.ctx)
            end, 0.5)
        elseif a.walk then
            if not mob and d <= range - 2 then
                -- on the spot, the NPC hasn't shown yet: wait here
                walk_stop(a)
                a.best_t = now
            elseif m and tonumber(m.x) then
                -- v5.34: a learned path first, point by point
                local gx, gy = tx, ty
                if a.path then
                    local pt = a.path[a.pi]
                    while pt and math.sqrt((m.x - pt.x) ^ 2 + (m.y - pt.y) ^ 2) <= 2.5 do
                        a.pi = a.pi + 1; pt = a.path[a.pi]
                        a.best, a.best_t = math.huge, now
                    end
                    if pt then gx, gy = pt.x, pt.y else a.path = nil end
                end
                crumb(a, m)
                if not a.start then   -- v5.43
                    a.start = {x = m.x, y = m.y}
                    a.nudge = start_nudge(zone_id(), m.x, m.y)
                end
                local gd = math.sqrt((m.x - gx) ^ 2 + (m.y - gy) ^ 2)
                if a.det and now < a.det.t_end then
                    -- going around: keep turning that way for a moment
                    local th = math.rad(a.det.deg)
                    local dx, dy = gx - m.x, gy - m.y
                    windower.ffxi.run(dx * math.cos(th) + dy * math.sin(th), -dx * math.sin(th) + dy * math.cos(th))
                    a.running = true
                else
                    if a.det then a.det = nil; a.best, a.best_t = gd, now end
                    if gd < a.best - 1 then a.best, a.best_t = gd, now end
                    if now - a.best_t > 1.5 then
                        -- stuck (not 1y closer in 1.5s): go around, right first
                        a.tries = (a.tries or 0) + 1
                        a.needed = true
                        local dt = DETOURS[a.tries]
                        local deg = dt and dt[1]
                        if deg then
                            a.det = {deg = deg, t_end = now + dt[2]}
                            dbg(string.format('walk: stuck %dy from %s -- going around (%d deg)', math.floor(d + 0.5), dev_name(a.o), deg))
                        else
                            walk_stop(a)
                            a.walk = false
                            tell_ctx(a.ctx, string.format('%s: stuck %dy from the %s -- walk there and AA warps (and remembers the way).', my_name(), math.floor(d + 0.5), dev_name(a.o)))
                        end
                    else
                        local dx, dy = gx - m.x, gy - m.y
                        local nu = a.nudge
                        if nu and math.sqrt((m.x - a.start.x) ^ 2 + (m.y - a.start.y) ^ 2) < nu.dist then
                            local th = math.rad(nu.deg)   -- v5.43: bear right off the spawn spot
                            dx, dy = dx * math.cos(th) + dy * math.sin(th), -dx * math.sin(th) + dy * math.cos(th)
                        end
                        windower.ffxi.run(dx, dy)
                        a.running = true
                    end
                end
            end
        elseif m and tonumber(m.x) and a.crumbs then
            crumb(a, m)   -- v5.34: you walk: AA keeps your way for next time
        end
    end
    local pd = N.pending
    if pd and now - pd.t > 90 and not N.cur then
        N.pending = nil
        tell_ctx(pd.ctx, my_name() .. ': no zone change after 90s -- ' .. pd.label .. ' did not happen.')
    end
end)

-- v5.33: an item used by you (ring, Instant Warp -- by nav, aa warp or by hand): its reuse timer starts
windower.register_event('action', function(act)
    if not (act and act.category == 5) then return end
    local m = windower.ffxi.get_mob_by_target('me')
    if not (m and act.actor_id == m.id) then return end
    local it = res.items[act.param]
    if not it then return end
    for _, x in ipairs(ITEMS) do
        if x.name == it.en then
            N.used[x.name] = os.time()
            pcall(save_char)
            dbg(x.name .. ' used -- reuse timer started')
        end
    end
end)

windower.register_event('zone change', function(new_id, old_id)
    N.last_zone_t = os.clock()   -- v5.22
    N.came_from, N.came_t = old_id, os.clock()   -- v5.33
    walk_stop(N.armed)
    N.armed = nil
    local ch = N.choice
    N.choice = nil
    local fixed = ch and FIXED_ONLY[ch.zone .. ':' .. ch.name]   -- v5.24: "return from whence you came" isn't a route
    if ch and fixed and not fixed[new_id] then ch = nil end
    if ch and os.clock() - ch.t < 30 and new_id ~= ch.zone then
        local k = 'npc:' .. ch.zone .. ':' .. ch.name .. ':' .. new_id
        -- v5.32: NPCs that sell a key item: the choice made WITHOUT it (buy and
        -- go in one menu) is kept apart from the one made with it
        if NEED_KI[ch.zone .. ':' .. ch.name] and ch.had_ki == false then k = k .. ':buy' end
        local sq = (ch.seq and #ch.seq > 1) and seq_str(ch.seq) or nil
        local L = N.learned[k]
        if type(L) ~= 'table' or L.menu ~= ch.menu or L.opt ~= ch.opt or L.unk ~= ch.unk or (ch.mh and not L.mh) or L.seq ~= sq then
            N.learned[k] = {menu = ch.menu, opt = ch.opt, unk = ch.unk, x = ch.x, y = ch.y, mh = ch.mh or nil, seq = sq}
            add_route(k, N.learned[k])   -- v5.22: usable right away
            save_learned()
            local Lk = N.learned[k]
            coroutine.schedule(function()   -- v5.23: where it put you (for the walk to the next warp)
                local m = windower.ffxi.get_mob_by_target('me')
                if m and tonumber(m.x) and zone_id() == new_id and N.learned[k] == Lk then
                    Lk.tx, Lk.ty = math.floor(m.x + 0.5), math.floor(m.y + 0.5)
                    for _, tr in ipairs(TR_TO[new_id] or {}) do
                        if tr.name == ch.name and tr.zone == ch.zone then tr.tx, tr.ty = Lk.tx, Lk.ty end
                    end
                    save_learned()
                end
            end, 6)
            dbg('learned: ' .. ch.name .. ' -> ' .. zname(new_id) .. ' = menu ' .. tostring(ch.menu) .. ' option ' .. tostring(ch.opt))
        end
    end
    next_scan = os.clock() + 20   -- NPC spots: once the new zone has loaded
    local pd = N.pending
    N.pending, N.cur = nil, nil
    if AA_NAV_EXPECT_HOME and os.clock() - AA_NAV_EXPECT_HOME < 120 and (not pd or pd.home) then
        AA_NAV_EXPECT_HOME = nil
        if N.home ~= new_id then N.home = new_id; save_char() end
    end
    -- v5.12: a trip with more legs / an NPC to find at the end
    local g = N.goal
    if g then
        if new_id == g.to then
            -- v5.31: in the NPC's zone: an in-zone warp that lands closer
            -- (Reisenjima: Eschan Portal #8 by Emporox) when that is faster
            -- than walking, then find the NPC
            if not g.npc then N.goal = nil
            else
                coroutine.schedule(function()
                    if N.goal ~= g then return end
                    if zone_id() ~= g.to then N.goal = nil; return end
                    local o = best_for(g.code)
                    if o and o.kind == 'device' and not o.locked and o.to == g.to then
                        tell_ctx(g.ctx, my_name() .. ': ' .. g.label .. ' -- ' .. opt_how(o) .. ' first.')
                        run_option(o, g.ctx, g.label, g.code, true)
                    else
                        N.goal = nil
                        start_seek(g.npc, g.to, g.x, g.y, g.ctx)
                    end
                end, 8)
            end
        elseif g.legs > 1 and os.clock() - g.t < 900 then
            g.legs = g.legs - 1
            coroutine.schedule(function()
                if N.goal ~= g or zone_id() ~= new_id then return end
                local o2 = best_for(g.code)
                tell_ctx(g.ctx, my_name() .. ': carrying on to ' .. g.label .. '.')
                run_option(o2, g.ctx, g.label, g.code, true)
            end, 8)
        else
            N.goal = nil
        end
    end
    if pd then
        if pd.learn_key and N.learned[pd.learn_key] ~= new_id then
            N.learned[pd.learn_key] = new_id
            save_learned()
        end
        coroutine.schedule(function() tell_ctx(pd.ctx, my_name() .. ': arrived in ' .. zname(new_id) .. '.') end, 6)
    end
end)

windower.register_event('login', function() coroutine.schedule(load_char, 3) end)

-- ---------------------------------------------------------------------------
-- commands (called by aa_party.lua for //aa nav ..., /tell and /p "aa nav ...")
-- ---------------------------------------------------------------------------
function N.pick(row, party)
    gui_close()
    if party or N.gui_party then   -- v5.19: a list opened by your own "/p aa nav ..." picks for the whole party
        if aa_party_run then aa_party_run('aa nav ' .. row.code) else say('party commands are not loaded.') end
        return
    end
    run_option(row.opt, {reply = function(t) windower.add_to_chat(207, '[AA] ' .. t) end}, row.label, row.code)
end

local function show_unlocks()
    for _, m in ipairs(MAPS) do
        local set = N.locked[m.key]
        local total = #(BY_MAP[m.key] or {})
        if set then
            local n = 0
            for _ in pairs(set) do n = n + 1 end
            say(string.format('%-15s %d of %d unlocked', m.label, math.max(total - n, 0), total))
        else
            say(string.format('%-15s not read yet (touch any %s once)', m.label, m.label))
        end
    end
    say('Home Point (Warp Ring / Warp): ' .. (N.home and zname(N.home) or 'not known yet (warp home once)'))
end

-- v5.19: aa stop (typed, /p or /tell) also stops nav: walking, waiting, a
-- warp in progress, a trip with more legs, looking for an NPC. Not the
-- "aa stop" nav itself sends to stop AutoAttack's loop before travelling.
-- v5.31: true while the "aa stop" nav sent itself (before a warp) is going through
function aa_nav_guarded() return N.stop_guard ~= nil and os.clock() - N.stop_guard < 3 end
function aa_nav_stop()
    if N.stop_guard and os.clock() - N.stop_guard < 3 then return false end
    local busy = N.armed or N.cur or N.goal or N.seek or N.pending
    walk_stop(N.armed)
    N.armed = nil
    if N.cur then release_menu(N.cur); N.cur = nil end
    N.pending, N.goal, N.seek = nil, nil, nil
    gui_close()
    if busy then windower.add_to_chat(207, '[AA] nav stopped.') end
    return busy and true or false
end

-- ctx = {src = 'local' | 'party' | 'tell', sender}; reply(text) answers the sender
function aa_nav_command(ctx, words, reply)
    if opt('enabled') == false then return reply(my_name() .. ': nav is off (nav.enabled = false).') end
    if not N.char then load_char() end
    ctx = {src = ctx.src, sender = ctx.sender, self = ctx.self, reply = reply}
    local q = table.concat(words or {}, ' ')
    local low = q:lower()
    if low == 'cancel' or low == 'stop' then
        gui_close()
        walk_stop(N.armed)
        N.armed = nil
        if N.cur then release_menu(N.cur); N.cur = nil end
        N.pending, N.goal, N.seek = nil, nil, nil
        return reply(my_name() .. ': nav cancelled.')
    end
    local is_code = q:match('^#[zl]%d+$') or q:match('^#n%d+:')
    if ctx.src == 'party' and not is_code and q ~= '' then
        -- v5.19: a name in party chat. The one who said it gets the list and
        -- picks (the pick goes to everyone as "aa nav #<code>"); the others go
        -- only when the name is clear (one match, or an exact name), else they
        -- wait for that pick.
        local rows = search(q)
        if #rows == 0 then return reply('nav: nothing matches "' .. q .. '".') end
        if ctx.self then
            gui_show(q, rows)
            N.gui_party = true
            return
        end
        local exact = nil
        for _, r in ipairs(rows) do
            local n = r.label:lower():gsub(' %[.*$', ''):gsub(' %(.*%)$', '')
            if n == low then exact = r; break end
        end
        local r = exact or (#rows == 1 and rows[1]) or nil
        if not r then return reply(string.format('nav "%s": %d matches -- waiting for %s to pick one.', q, #rows, tostring(ctx.sender))) end
        return run_option(r.opt, ctx, r.label, r.code)
    end
    if ctx.src ~= 'local' then
        -- a code from a party pick, or a /tell: this character goes there its own fastest way
        if q == '' then return reply(my_name() .. ': aa nav <zone or place>') end
        local o, label = best_for(q)
        return run_option(o, ctx, label, code_for(q))
    end
    if low == '' or low == 'help' then
        return reply('aa nav <name> | <n> | p<n> | party <name> | next | prev | close | cancel | unlocks | routes | forget <name> | pos <x> <y>')
    end
    if low == 'close' then return gui_close() end
    if low == 'next' or low == 'prev' or low == 'previous' then   -- v5.20
        if not gui_page(low == 'next' and 1 or -1) then reply('nav: no other page.') end
        return
    end
    if low == 'unlocks' then return show_unlocks() end
    if low == 'routes' then   -- v5.22: routes learned by hand
        local n = 0
        for k, v in pairs(N.learned) do
            local z, name, to = tostring(k):match('^npc:(%d+):(.-):(%d+)$')
            if z and type(v) == 'table' then
                n = n + 1
                reply(string.format('%s (%s%s) -> %s', name, zname(tonumber(z)), v.mh and ', Mog House' or '', zname(tonumber(to))))
            end
        end
        if n == 0 then reply('nav: no routes learned yet -- use an NPC by hand once and AA remembers it.') end
        return
    end
    local fq = q:match('^[Ff]orget%s+(.+)$')
    if fq then   -- v5.22: drop a learned route that is wrong (a quest cutscene that moved you ...)
        local n, fl = 0, fq:lower()
        for k, v in pairs(N.learned) do
            local z, name, to = tostring(k):match('^npc:(%d+):(.-):(%d+)$')
            if z and type(v) == 'table' and name:lower():find(fl, 1, true) then
                N.learned[k] = nil
                n = n + 1
                for _, list in ipairs({TR_FROM[tonumber(z)] or {}, TR_TO[tonumber(to)] or {}}) do
                    for i = #list, 1, -1 do
                        if list[i].learned and list[i].name == name and list[i].to == tonumber(to) then table.remove(list, i) end
                    end
                end
            end
        end
        if n > 0 then save_learned() end
        return reply(string.format('nav: forgot %d learned route%s matching "%s".', n, n == 1 and '' or 's', fq))
    end
    local px, py = low:match('^pos%s+(%-?%d+)%s+(%-?%d+)$')
    if px then
        if N.gui then N.gui:pos(tonumber(px), tonumber(py)) end
        return reply('nav list moved to ' .. px .. ', ' .. py .. ' (nav.gui.x / y in aa_config.lua keeps it there).')
    end
    local pq = q:match('^[Pp][Aa][Rr][Tt][Yy]%s+(.+)$')
    if pq then
        if aa_party_run then return aa_party_run('aa nav ' .. pq) end
        return reply('party commands are not loaded.')
    end
    local pn, n = low:match('^(p?)(%d+)$')
    if n then
        local row = N.rows and N.rows[tonumber(n)]
        if not row then return reply('no line ' .. n .. ' -- search first: aa nav <name>') end
        return N.pick(row, pn == 'p')
    end
    if q:match('^#[zl]%d+$') or q:match('^#n%d+:') then
        local o, label = best_for(q)
        return run_option(o, ctx, label, q)
    end
    local rows = search(q)
    if #rows == 0 then
        gui_close()
        return reply('nav: nothing matches "' .. q .. '".')
    end
    gui_show(q, rows)
    N.gui_party = false
end

-- ---------------------------------------------------------------------------
-- start
-- ---------------------------------------------------------------------------
do
    local ok, err = load_maps()
    if not ok then
        windower.add_to_chat(167, '[AA] nav: nav_maps.lua did not load (' .. tostring(err) .. ') -- aa nav is off.')
        function aa_nav_command(ctx, words, reply) reply('nav: warp data missing (nav_maps.lua) -- try "aa update force".') end
        return N
    end
    build_index()
    if windower.ffxi.get_info().logged_in then load_char() end
end

N._test = {search = search, route = route, best_for = best_for, opt_how = opt_how, devices_here = devices_here,
           BY_MAP = function() return BY_MAP end, LANDMARKS = function() return LANDMARKS end,
           record_params = record_params, locked = locked}
return N
