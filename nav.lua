--[[
    nav.lua -- AutoAttack travel: aa nav (v5.06; v5.07 NPCs + unreachable zones listed, v5.08 lands closest to the way on, v5.09 walks you to a close warp, v5.10 warps inside your own zone toward the way on, v5.11 zone-moving NPCs, v5.12 trips with legs + finding NPCs, v5.13 warps not loaded yet after zoning, v5.14 checked NPC targeting, v5.15 more ways to target + updates on your own screen, v5.16 walking legs keep the goal, v5.17 hovered line highlighted, v5.18 NPCs found by what they are, v5.19 aa stop stops nav + your own /p line opens the list, v5.20 list pages, v5.21 [X] close, v5.22 learns routes you use by hand + Mog House, v5.23 ways out of Mog Garden, v5.24 Mog Garden always out to Eastern Adoulin, v5.25 stronger row highlight, v5.30 Escha / Abyssea entrances reached by ring or warp first (v5.60: + Undulating Confluences), v5.31 in-zone warp to the NPC (Eschan Portal #8 for Emporox) + craft-style rows + aa stop stops it all, v5.32 Walk of Echoes via Xarcabard [S] + Kupofried's medallion, Warp Ring / Warp home from a zone with no warp, v5.33 Mog Garden ways + nav.via preference, ring cooldowns, warp spots AA has seen, v5.34 walks around things in the way + learns the path, v5.35 Mog Garden: out by the Mog Dinghy / Green Thumb Moogle, never warped out, v5.36 Shadowhammer into Mog Garden via Eastern Adoulin, v5.37 Mog Garden always through Eastern Adoulin: in by Cunegonde, out by the Green Thumb Moogle, v5.38 or the Mog Dinghy's Eastern Adoulin choice, v5.39 the walk from where a Survival Guide lands counts too, v5.40 [X] close is a button that lights up, v5.41 Warp Ring / Instant Warp / Warp never on top when this zone has a Home Point or Survival Guide, v5.42 also with a nav.via way, v5.43 side-step off the Eastern Adoulin Mog House / Mog Garden spawn, v5.44 Warp Ring before Instant Warp, Walk of Echoes out by the conflux first, v5.45 aa buy for the Curio Vendor / Green Thumb Moogles, v5.46 in your Mog House: out the door first, v5.62 into it by the Elevator Button & co., v5.63 numbered warps by name ("kamihr drifts #4"), v5.64 nav.via per place + landing warp ("Western Adoulin #1"), v5.49 aa trade: seals / crests to Shami, Rem's Tales to Monisette, Shemo exchanges, v5.50 aa trade seals / crests both trade every seal and crest, v5.51 no 255 cap for Rem's Tales, v5.54 aa buy: several matches open a list to click, words match by their start, shop slots read right, v5.55 aa trade clicks through Shami's / Monisette's talk itself, v5.61 aa buy: Asrahd's Imperial Standing items)

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
    via           = {['Mog Garden'] = {default = 'Eastern Adoulin / Cunegonde'},
                     -- v5.64: '<zone> #<n>' = land on that warp there (Western Adoulin
                     -- Home Point #1, by the Auction House), then the Waypoint
                     ['Kamihr Drifts #4'] = {default = 'Western Adoulin #1'}},
    -- v5.37: leaving Mog Garden: always this way out (Green Thumb Moogle ->
    -- Eastern Adoulin); '' / false = the fastest of all its ways out (Mog Dinghy too)
    garden_exit   = 'Eastern Adoulin',
    -- v5.55: aa trade: AA presses Enter through Shami's / Monisette's talk after
    -- each trade (their words still show, so AA still reads the counts); false = you click
    trade_auto_talk = true,
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
SHOP_NPCS_ALL = {['Curio Vendor Moogle'] = true, ['Green Thumb Moogle'] = true, ['Asrahd'] = true}   -- v5.46 (aa buy's moogles; v5.61 + Asrahd)
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
    -- v5.60: the Undulating Confluences into Escha - Zi'Tah (Qufim Island) and
    -- Escha - Ru'Aun (Misareaux Coast), from LandSandBoat (!pos; Qufim's matches
    -- where AA saw it)
    ['escha:126'] = {name = 'Undulating Confluence', x = -205, y = 75, r = 40},
    ['escha:25']  = {name = 'Undulating Confluence', x = -49, y = 572, r = 40},
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
                                    if not num then LANDMARKS[#LANDMARKS + 1] = list[#list]
                                    else   -- v5.63: "Kamihr Drifts #4" -- searched only with a number in it
                                        LANDMARKS[#LANDMARKS + 1] = {map = m.key, zone_name = zn, sub = tostring(sub), data = sd, zone_id = list[#list].zone_id,
                                            label = list[#list].label, num = true}
                                    end
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
        elseif tgt and o.entry and o.map and o.map ~= 'transport' then
            o.time = o.time + 60   -- v5.63: lands who knows where in that zone
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
local function via_pref(T, key)
    local v = opt('via')
    if type(v) ~= 'table' then return nil end
    local e = (key and v[key]) or v[zname(T)] or v[T] or v[tostring(T)]   -- v5.64: a place's own entry first
    if type(e) == 'table' then e = e[my_name()] or e.default end
    if type(e) == 'number' then return e end
    if type(e) == 'string' and e ~= '' then
        local zn, npc = e:match('^%s*(.-)%s*/%s*(.-)%s*$')   -- v5.37: "<zone> / <NPC>"
        if not zn then zn = e end
        local zn2, num = zn:match('^(.-)%s*#(%d+)$')          -- v5.64: "<zone> #<n>"
        if zn2 then zn = zn2 end
        return ZID[zn:lower()], (npc and npc ~= '') and npc or nil, num
    end
    return nil
end
-- the zone (and NPC) an option goes through on its last step into T
local function gate_zone(o, T)
    if o.then_npc then return o.via, o.then_npc end
    if o.then_mh then return o.via, o.then_mh end
    if (o.kind == 'npc' or o.kind == 'mh') and o.tr and o.tr.to == T then return o.tr.zone, o.tr.name end
    if o.then_warp and o.via and not o.via_home then   -- v5.64: a warp there, then its own warp on
        return o.via, nil, o.entry and o.entry.sub
    end
    return nil
end

-- every way to zone T (or to a landmark lm), fastest first
local function route(T, lm, devs, tgt)
    local here = zone_id()
    -- v5.46: inside your Mog House every trip starts by leaving it through the
    -- door ("area you entered from"); where you come out a Home Point /
    -- Survival Guide is close by and AA works out the rest there (Mark,
    -- 2026-11-23: "when in mog house ... assume we need to exit")
    if here ~= 280 and in_mog_house() then
        local dest = (lm and lm.zone_id) or T
        if not dest then return {} end
        local hp = (opt('menu_seconds').homepoints or 6) + opt('zone_seconds')
        local o = {kind = 'mhexit', to = dest, hops = 0, time = 15 + hp + ((dest ~= here) and (hp + 20) or 20)}
        if lm then o.lm_code = lm end
        return {o}
    end
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
        -- v5.62: already in its zone: walking there counts too (no warp from
        -- Home Point #2 to Home Point #2 to reach the Mog House next to it)
        local me_m = windower.ffxi.get_mob_by_target('me')
        if lm.zone_id == here and lm.data and tonumber(lm.data.x) and me_m and tonumber(me_m.x) then
            local ar = math.sqrt((me_m.x - lm.data.x) ^ 2 + (me_m.y - lm.data.y) ^ 2)
            out[#out + 1] = {kind = 'here', to = here, hops = 0, arrive = ar, time = ar / spd}
        end
        local usable = false
        for _, o in ipairs(out) do if not o.locked then usable = true end end
        if usable or not lm.zone_id then return sort_opts(out) end
        T = lm.zone_id
        -- v5.63: the walk from where you land to the place counts
        if not tgt and lm.data and tonumber(lm.data.x) then tgt = {x = lm.data.x, y = lm.data.y} end
        -- v5.63: no warp of its kind here (a Waypoint for "Kamihr Drifts #4"):
        -- get to a zone that has one, then use it -- the trip carries on there
        if lm.map and lm.map ~= 'homepoints' then
            local zs, menu = opt('zone_seconds'), opt('menu_seconds')
            local done_z = {}
            for _, e in ipairs(BY_MAP[lm.map] or {}) do
                local z = e.zone_id
                if z and z ~= here and not done_z[z] and e.data and tonumber(e.data.x) and not locked(e) then
                    done_z[z] = true
                    for _, o in ipairs(options_for(z, devs, here, spd, (menu[lm.map] or 6) + zs, 1, z, {x = e.data.x, y = e.data.y})) do
                        if o.kind ~= 'npc' and o.kind ~= 'mh' and not o.locked then
                            o.to, o.then_warp = lm.zone_id, (MAPINFO[lm.map] and MAPINFO[lm.map].label or 'warp') .. ' -> ' .. lm.label
                            out[#out + 1] = o
                        end
                    end
                end
            end
        end
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
    local pnum = nil
    if T then pz, pn, pnum = via_pref(T, lm and lm.label) end
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
            local gz, gn, gsub = gate_zone(o, T)
            if not o.locked and gz == pz and (not pn or gn == pn) and (not pnum or tostring(gsub) == pnum) then o.preferred = true; a[#a + 1] = o
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
    if o.kind == 'mhexit' then return 'DOOR' end
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
    elseif o.kind == 'mhexit' then   -- v5.46
        s = 'out of your Mog House (area you entered from), then ' .. ((o.to == zone_id()) and 'walk' or ('a Home Point / Survival Guide close by -> ' .. zname(o.to)))
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
    local digits = q:find('%d') ~= nil   -- v5.63
    for i, lm in ipairs(LANDMARKS) do
        if hit(lm.label) and (not lm.num or digits) then
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
local ROW_HOT_TEXT = {255, 210, 90}   -- v5.49: aa trade's suggested exchange
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
    local title = rows.title or string.format(' AA nav "%s"   left-click: go   right-click: whole party        [X] close ', q)
    line(cs(255, 210, 90, title), {close = true}, title)
    -- v5.20: pages of max_rows lines; mouse wheel / the << >> line / aa nav next|prev
    local maxr = math.max(1, tonumber(opt('max_rows')) or 14)
    local pages = math.max(1, math.ceil(#rows / maxr))
    page = math.min(math.max(1, page or 1), pages)
    local first, last = (page - 1) * maxr + 1, math.min(#rows, page * maxr)
    local section = nil
    local hot = {}   -- v5.49: aa trade rows (text = the line, info = not clickable, hot = suggested)
    for i = first, last do
        local r = rows[i]
        if r.text then
            if r.info then
                line(cs(r.head and 120 or 200, r.head and 200 or 200, r.head and 255 or 200, r.text), nil, r.text)
            else
                line(r.text, r, r.text)
                if r.hot then hot[#lines] = true end
            end
        elseif r.section ~= section then
            section = r.section
            line(cs(120, 200, 255, section == 'zone' and ' Zones' or section == 'npc' and ' NPCs'
                                   or ' Other matches (places in a zone)'))
        end
        if not r.text then
        local o = r.opt
        local s = string.format(' %2d  %-50s %-6s %-8s %s ', i, r.label:sub(1, 50), opt_tag(o), fmt_time(o.time), opt_how(o))
        local p = s
        if o.locked then s = cs(140, 140, 140, s) end
        line(s, r, p)
        end
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
    N.gui_locked, N.gui_hot = {}, hot
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
        local c = (N.gui_locked and N.gui_locked[i]) and ROW_LOCKED or (N.gui_hot and N.gui_hot[i]) and ROW_HOT_TEXT or ROW_TEXT
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
    if l and LANDMARKS[tonumber(l)] then
        g.to = LANDMARKS[tonumber(l)].zone_id
        g.mh = (LANDMARKS[tonumber(l)].sub == 'Mog House') or nil   -- v5.62: then into the Mog House
    end
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

-- v5.46: the Mog House door. A menu that opens in your Mog House from anything
-- but the Moogle is the door's ("area you entered from" / other areas); what
-- you pick there followed by leaving the Mog House is learned
-- (data/nav_learned.lua "mhdoor:<zone>" + "mhdoor", with where you stood).
-- With aa nav running (N.mh_exit) AA answers it for you.
windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if injected or (id ~= 0x034 and id ~= 0x032) or not in_mog_house() or zone_id() == 280 then return end
    local p = packets.parse('incoming', data)
    local mob = p['NPC Index'] and windower.ffxi.get_mob_by_index(p['NPC Index'])
    local name = mob and mob.name or ''
    if name == 'Moogle' or SHOP_NPCS_ALL[name] then return end
    local m = windower.ffxi.get_mob_by_target('me')
    N.door_menu = {menu = p['Menu ID'], npc = p['NPC'], idx = p['NPC Index'], t = os.clock(),
                   x = m and tonumber(m.x) and math.floor(m.x * 10 + 0.5) / 10, y = m and tonumber(m.y) and math.floor(m.y * 10 + 0.5) / 10}
    N.door_menu_open = true
    local x = N.mh_exit
    if not (x and os.clock() - x.t < 300) then return end
    local L = N.learned['mhdoor:' .. zone_id()]
    if not (type(L) == 'table' and L.menu == p['Menu ID']) then L = N.learned['mhdoor'] end
    if not (type(L) == 'table' and L.menu == p['Menu ID']) then return end
    N.mh_exit = nil
    coroutine.schedule(function()
        local pk = packets.new('outgoing', 0x05B)
        pk['Target'] = p['NPC']
        pk['Option Index'] = L.opt
        pk['_unknown1'] = L.unk or 0
        pk['Target Index'] = p['NPC Index']
        pk['Automated Message'] = false
        pk['_unknown2'] = 0
        pk['Zone'] = zone_id()
        pk['Menu ID'] = p['Menu ID']
        packets.inject(pk)
        dbg('Mog House door: option ' .. tostring(L.opt))
    end, 0.3)
    return true
end)
windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
    if id ~= 0x05B or injected or not in_mog_house() then return end
    local p = packets.parse('outgoing', data)
    local dm = N.door_menu
    if dm and p['Menu ID'] == dm.menu and not p['Automated Message'] and os.clock() - dm.t < 120 then
        N.door_choice = {menu = dm.menu, opt = p['Option Index'], unk = p['_unknown1'] or 0, x = dm.x, y = dm.y, t = os.clock()}
    end
    N.door_menu_open = nil
end)
N.door_left = function()
    N.door_menu_open = nil
    local c = N.door_choice
    N.door_choice = nil
    if not (c and os.clock() - c.t < 30) then return end
    local z = zone_id()
    local L = {menu = c.menu, opt = c.opt, unk = c.unk, x = c.x and math.floor(c.x + 0.5), y = c.y and math.floor(c.y + 0.5)}
    local old = N.learned['mhdoor:' .. z]
    if type(old) ~= 'table' or old.menu ~= L.menu or old.opt ~= L.opt then
        N.learned['mhdoor:' .. z] = L
        N.learned['mhdoor'] = L
        save_learned()
        dbg(string.format('learned the Mog House door: menu %d option %d', L.menu, L.opt))
    end
end

-- v5.31: an in-zone warp is done (no zone change): find the goal's NPC
-- v5.62: getting INTO your Mog House where you have to press / open something
-- (Mark, 2026-11-25: "add in the step in ru'lude gardens of interacting with
-- Elevator Button to get into the mog house, and similar steps for other
-- places"). Built in: Ru'Lude Gardens Elevator Button, Al Zahbi Gate:
-- Residential Area (Topaz NPC list). Anything else: whatever you talk to /
-- open right before you end up in your Mog House is learned
-- (nav_learned "mhentry:<zone>:<name>", with its menu choice when it has one).
local MH_ENTRY = {
    [243] = {name = 'Elevator Button', x = 49, y = -75},           -- Ru'Lude Gardens
    [48]  = {name = 'Gate: Residential Area', x = 40, y = -68},    -- Al Zahbi
}
local function mh_entry(z)
    for k, v in pairs(N.learned or {}) do
        local lz, name = tostring(k):match('^mhentry:(%d+):(.+)$')
        if lz and tonumber(lz) == z and type(v) == 'table' then return {name = name, x = v.x, y = v.y, L = v} end
    end
    local e = MH_ENTRY[z]
    if e then return {name = e.name, x = e.x, y = e.y, L = N.learned['mhentry:' .. z .. ':' .. e.name]} end
    return nil
end
local function named_mob(name)
    local best, bd = nil, nil
    for idx, n in pairs(windower.ffxi.get_mob_list() or {}) do
        if n == name then
            local m = windower.ffxi.get_mob_by_index(idx)
            if m and m.valid_target and (m.id or 0) > 0 then
                local d = math.sqrt(m.distance or 0)
                if not bd or d < bd then best, bd = m, d end
            end
        end
    end
    return best, bd
end
local function enter_mh(ctx, label)
    if in_mog_house() then return end
    local z = zone_id()
    local e = mh_entry(z)
    if not e then return tell_ctx(ctx, my_name() .. ': ' .. tostring(label) .. ' -- walk into your Mog House.') end
    local me_m = windower.ffxi.get_mob_by_target('me')
    local mob, d = named_mob(e.name)
    if not d and me_m and e.x then d = math.sqrt((me_m.x - e.x) ^ 2 + (me_m.y - e.y) ^ 2) end
    if not d then return tell_ctx(ctx, my_name() .. ': walk to the ' .. e.name .. ' to get into your Mog House.') end
    if d > (tonumber(opt('walk_range')) or 50) then
        N.mh_enter = {t = os.clock(), name = e.name, L = e.L, ctx = ctx, wait = true}
        return tell_ctx(ctx, string.format('%s: %s -- walk to the %s (%dy); AA presses it when you are close.', my_name(), tostring(label), e.name, math.floor(d + 0.5)))
    end
    tell_ctx(ctx, string.format('%s: %s -- to the %s (%dy), into your Mog House.', my_name(), tostring(label), e.name, math.floor(d + 0.5)))
    local t0 = os.clock()
    while os.clock() - t0 < 30 do
        mob = named_mob(e.name)
        me_m = windower.ffxi.get_mob_by_target('me')
        if not me_m then break end
        local tx, ty = (mob and mob.x) or e.x, (mob and mob.y) or e.y
        local dd = math.sqrt((me_m.x - tx) ^ 2 + (me_m.y - ty) ^ 2)
        if dd <= 3 and mob then break end
        windower.ffxi.run(tx - me_m.x, ty - me_m.y)
        coroutine.sleep(0.1)
    end
    windower.ffxi.run(false)
    mob = named_mob(e.name)
    if not mob or math.sqrt(mob.distance or 999) > 6 then
        N.mh_enter = {t = os.clock(), name = e.name, L = e.L, ctx = ctx, wait = true}
        return tell_ctx(ctx, my_name() .. ': could not reach the ' .. e.name .. ' -- walk to it; AA presses it when you are close.')
    end
    N.mh_enter = {t = os.clock(), name = e.name, L = e.L, ctx = ctx}
    N.last_talk = {name = mob.name, zone = z, x = math.floor(mob.x + 0.5), y = math.floor(mob.y + 0.5), t = os.clock()}
    set_target(mob.index)
    coroutine.sleep(0.2)
    packets.inject(packets.new('outgoing', 0x01A, {
        ['Target'] = mob.id, ['Target Index'] = mob.index, ['Category'] = 0, ['Param'] = 0, ['_unknown1'] = 0}))
end
N.enter_mh = function(ctx, label) coroutine.schedule(function() enter_mh(ctx, label) end, 0) end
-- the entry's menu: answered when the choice is known; else you pick and AA learns it
windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if injected or (id ~= 0x034 and id ~= 0x032) then return end
    local x = N.mh_enter
    if not x or os.clock() - x.t > 60 or in_mog_house() then return end
    local p = packets.parse('incoming', data)
    local mob = p['NPC Index'] and windower.ffxi.get_mob_by_index(p['NPC Index'])
    if not (mob and mob.name == x.name) then return end
    local L = x.L
    if type(L) == 'table' and L.menu == p['Menu ID'] and L.opt then
        coroutine.schedule(function()
            local pk = packets.new('outgoing', 0x05B)
            pk['Target'] = p['NPC']
            pk['Option Index'] = L.opt
            pk['_unknown1'] = L.unk or 0
            pk['Target Index'] = p['NPC Index']
            pk['Automated Message'] = false
            pk['_unknown2'] = 0
            pk['Zone'] = zone_id()
            pk['Menu ID'] = p['Menu ID']
            packets.inject(pk)
            dbg('Mog House entry: ' .. x.name .. ' option ' .. tostring(L.opt))
        end, 0.3)
        return true
    end
    tell_ctx(x.ctx, my_name() .. ': pick the way into your Mog House -- AA remembers it.')
end)
-- every talk / open by you (and AA's own press) -- for learning the entry
windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
    if id ~= 0x01A or injected or in_mog_house() then return end
    local p = packets.parse('outgoing', data)
    if p['Category'] ~= 0 then return end
    local mob = p['Target Index'] and windower.ffxi.get_mob_by_index(p['Target Index'])
    if mob and type(mob.name) == 'string' and mob.name ~= '' and tonumber(mob.x) then
        N.last_talk = {name = mob.name, zone = zone_id(), x = math.floor(mob.x + 0.5), y = math.floor(mob.y + 0.5), t = os.clock()}
    end
end)
N.mh_entered = function()
    N.mh_enter = nil
    local t = N.last_talk
    N.last_talk = nil
    if not (t and os.clock() - t.t < 15 and t.zone == zone_id() and t.name ~= 'Moogle') then return end
    local k = 'mhentry:' .. t.zone .. ':' .. t.name
    local ch = N.choice
    local L = {x = t.x, y = t.y}
    if ch and ch.name == t.name and os.clock() - ch.t < 15 then L.menu, L.opt, L.unk = ch.menu, ch.opt, ch.unk end
    local old = N.learned[k]
    if type(old) ~= 'table' or old.x ~= L.x or old.opt ~= L.opt then
        N.learned[k] = L
        save_learned()
        dbg('learned the way into the Mog House: ' .. t.name .. ' (' .. t.x .. ',' .. t.y .. ')')
    end
end

N.on_same_zone_done = function()
    local g = N.goal
    if g and g.mh and g.to == zone_id() then   -- v5.62
        N.goal = nil
        N.enter_mh(g.ctx, g.label)
        return
    end
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
        if g and g.mh and g.to == zone_id() then return N.enter_mh(ctx, label) end   -- v5.62
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
    if o.kind == 'mhexit' then   -- v5.46: out the door; AA answers the door's menu and carries on outside
        if N.goal then N.goal.legs = math.max(N.goal.legs, 3) end
        N.mh_exit = {t = os.clock(), ctx = ctx}
        local L = N.learned['mhdoor:' .. zone_id()] or N.learned['mhdoor']
        local spot = type(L) == 'table' and L.x and L.y and {x = L.x, y = L.y} or nil
        if spot then
            N.mh_exit.spot = spot
            return tell_ctx(ctx, string.format('%s: %s -- walking out of your Mog House; AA picks "area you entered from" and carries on.', my_name(), label))
        end
        return tell_ctx(ctx, string.format('%s: %s -- walk out of your Mog House%s; AA carries on outside.', my_name(), label,
            type(L) == 'table' and ' (AA picks "area you entered from")' or ' and pick "area you entered from" (AA remembers it)'))
    end
    if o.kind == 'mh' then   -- v5.22: the player goes in; AA carries on inside
        if N.goal then N.goal.legs = math.max(N.goal.legs, 2) end
        if mh_entry(zone_id()) then return N.enter_mh(ctx, label) end   -- v5.62: AA presses the way in
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
    if N.mh_exit and N.mh_exit.spot and mh then   -- v5.46: walk to the Mog House door
        local x = N.mh_exit
        local m = windower.ffxi.get_mob_by_target('me')
        if now - x.t > 20 or N.door_menu_open then
            if x.running then windower.ffxi.run(false); x.running = false end
            x.spot = nil
        elseif m and tonumber(m.x) then
            local d = math.sqrt((m.x - x.spot.x) ^ 2 + (m.y - x.spot.y) ^ 2)
            if d > 0.8 then windower.ffxi.run(x.spot.x - m.x, x.spot.y - m.y); x.running = true
            elseif x.running then windower.ffxi.run(false); x.running = false end
        end
    end
    local xw = N.mh_enter   -- v5.62: walked there yourself: press it when close
    if xw and xw.wait and not mh and now - xw.t < 300 then
        local mob = named_mob(xw.name)
        if mob and math.sqrt(mob.distance or 999) <= 5 then
            xw.wait = nil
            local ctx = xw.ctx
            coroutine.schedule(function() enter_mh(ctx, 'Mog House') end, 0)
        end
    end
    if mh ~= N.last_mh then
        local was = N.last_mh
        N.last_mh = mh
        if was and not mh then N.door_left() end   -- v5.46
        if was == false and mh and N.mh_entered then N.mh_entered() end   -- v5.62
        local g = N.goal
        if was and not mh and g and g.npc and zone_id() == g.to and os.clock() - (N.last_zone_t or -99) > 6 then
            N.goal = nil   -- v5.46: out of the Mog House into the NPC's own zone: find it
            coroutine.schedule(function() start_seek(g.npc, g.to, g.x, g.y, g.ctx) end, 4)
        end
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
    if N.door_left then N.door_left() end   -- v5.46 (leaving the Mog House may come as a zone change)
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
            if g.mh then   -- v5.62: a Mog House: get in
                N.goal = nil
                coroutine.schedule(function() if zone_id() == g.to then N.enter_mh(g.ctx, g.label) end end, 6)
            elseif not g.npc then N.goal = nil
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
    if row.trade then return row.trade(party) end   -- v5.49: aa trade list
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
    if aa_trade_stop and aa_trade_stop() then busy = true end   -- v5.49
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

-- ===========================================================================
-- v5.45: aa buy <item or part of its name> [qty] (Mark, 2026-11-23: "This will
-- be most handy for the curio vendor moogle, and green thumb moogle, where there
-- are many sub menus of items and it's sometimes hard to know what menu to go
-- into to find which item"). AA knows what each moogle sells and in which of
-- its menus because it watched the shop lists come in -- "aa buy scan" at a
-- Curio Vendor Moogle opens every menu once by itself; menus you open by hand
-- (Green Thumb Moogle too) are learned the same way. Per character (Rhapsodies
-- unlock different items): data/shops_<name>.lua. Buying: talk to the moogle,
-- open that menu with packets (nothing shows), buy (0x083, a stack at a time),
-- close the menu.
-- ===========================================================================
local SHOP_NPCS = {['Curio Vendor Moogle'] = true, ['Green Thumb Moogle'] = true, ['Asrahd'] = true}
-- v5.61 (Mark, 2026-11-25: "for aa buy, lets include the items such as
-- reraise III scroll from Asrahd"): Asrahd (Aht Urhgan Whitegate I-8, the
-- Sanction guard) sells for Imperial Standing through his talk menu -- no shop
-- list comes in, the item is the menu answer. AA learns an item the first time
-- you buy it from him by hand (the menu answers you sent, and the item that
-- turned up in your inventory) and repeats those answers to buy it again, one
-- talk per item. The IS price is learned from his talk (your IS before/after).
local EV = {}   -- v5.61 (one local: nav.lua is at Lua's 200-locals limit)
EV.npcs = {['Asrahd'] = 'IS'}
EV.wares = {'instant reraise', 'reraise iii', 'instant warp', 'lambent', 'katana strap', 'axe grip', 'staff strap',
    'heat capacitor', 'power cooler', 'barrage turbine', 'galvanizer', 'ephramadian throne', 'glyph', 'evanessence',
    'dathaba', 'perdu', 'lieutenant', 'volunteer', 'mercenary', 'imperial dart', 'mamoolbane', 'lamiabane',
    'trollbane', 'luzaf', 'sneaking boots', 'trooper', 'sentinel shield', 'shark gun', 'puppet claws', 'singh kilij',
    'multiple ring', 'haten', 'priest', 'chaotic earring'}
EV.hint = {['Green Thumb Moogle'] = 'mog garden', ['Curio Vendor Moogle'] = "port san d'oria", ['Asrahd'] = 'asrahd'}
local SCAN_NPCS = {['Curio Vendor Moogle'] = true}   -- Green Thumb's menu also moves you out of the garden: learned by hand only
local B = {char = nil, cat = nil, ses = nil, run = nil, menu = {}}
local function shop_file() return data_file('shops_' .. my_name() .. '.lua') end
local function shop_cat()
    local n = my_name()
    if B.char ~= n then
        B.char = n
        B.cat = read_table(shop_file()) or {}
        -- v5.54: slots learned before v5.54 could carry junk in the high byte
        -- (Grain Seeds 1027 = slot 3): the shop slot is one byte
        local fixed = false
        for _, items in pairs(B.cat) do
            for _, e in pairs(items) do
                if type(e) == 'table' and (e.slot or 0) > 255 then e.slot = e.slot % 256; fixed = true end
            end
        end
        if fixed then B.fix_save = true end
    end
    return B.cat
end
local function shop_save()
    local cat = shop_cat()
    local f = io.open(shop_file(), 'w')
    if not f then return end
    f:write('-- AutoAttack aa buy: what the moogles sell to ' .. B.char .. ' ([npc] = {[item id] = {slot, price, seq = menu steps}})\nreturn {\n')
    local npcs = {}
    for k in pairs(cat) do npcs[#npcs + 1] = k end
    table.sort(npcs)
    for _, npc in ipairs(npcs) do
        f:write(string.format('    [%q] = {\n', npc))
        local ids = {}
        for id in pairs(cat[npc]) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local e = cat[npc][id]
            local it = res.items[id]
            local extra = ''
            if e.kind then extra = string.format(', kind = %q, per = %d', e.kind, e.per or 1) end   -- v5.61 (Asrahd)
            f:write(string.format('        [%d] = {slot = %d, price = %d, seq = %q%s},   -- %s\n', id, e.slot or 0, e.price or 0, e.seq or '',
                extra, it and it.en or '?'))
        end
        f:write('    },\n')
    end
    f:write('}\n')
    f:close()
end
local function parse_shop(data)
    local out = {}
    for p = 9, #data - 11, 12 do
        local price, item, slot = data:unpack('I', p), data:unpack('H', p + 4), data:byte(p + 6)   -- v5.54: slot is one byte (the next is junk)
        if item and item > 0 then out[#out + 1] = {item = item, slot = slot, price = price} end
    end
    return out
end
local function learn_list(npc, seq, list)
    local cat = shop_cat()
    cat[npc] = cat[npc] or {}
    local n = 0
    for _, e in ipairs(list) do
        cat[npc][e.item] = {slot = e.slot, price = e.price, seq = seq}
        n = n + 1
    end
    if n > 0 then shop_save() end
    return n
end

-- v5.61: Asrahd -- what is in the inventory (item id -> count)
function EV.inv_counts()
    local t = {}
    local b = windower.ffxi.get_items(0)
    if type(b) ~= 'table' then return t end
    for i = 1, (tonumber(b.max) or 80) do
        local x = b[i]
        if type(x) == 'table' and (x.id or 0) > 0 and x.id ~= 65535 then t[x.id] = (t[x.id] or 0) + (x.count or 0) end
    end
    return t
end
function EV.inv_count(id) return EV.inv_counts()[id] or 0 end
function EV.price_str(npc, e)
    local cur = EV.npcs[npc]
    if cur then return ((e.price or 0) > 0 and tostring(e.price) or '?') .. ' ' .. cur end
    return tostring(e.price or 0) .. ' gil'
end
-- a menu answer you sent Asrahd by hand: did an item turn up? (the answers
-- since the last item that turned up = how to buy it)
function EV.check(s, upto)
    if B.ses ~= s or not s.inv or #s.seq > upto then return end   -- a later answer checks instead
    local now = EV.inv_counts()
    for id, c in pairs(now) do
        local d = c - (s.inv[id] or 0)
        if d > 0 then
            local steps = {}
            for i = (s.last or 0) + 1, upto do steps[#steps + 1] = s.seq[i] end
            if #steps > 0 then
                local cat = shop_cat()
                cat[s.npc] = cat[s.npc] or {}
                local old = cat[s.npc][id]
                cat[s.npc][id] = {slot = 0, price = old and old.price or 0, seq = seq_str(steps), kind = 'event', per = d}
                shop_save()
                local pp = B.pend
                if pp and pp.npc == s.npc and pp.id == id and pp.bal == s.bal then pp.n = pp.n + d
                else B.pend = {npc = s.npc, id = id, n = d, bal = s.bal} end
                windower.add_to_chat(207, string.format('[AA] buy: learned %s from %s -- next time "aa buy %s [qty]".',
                    res.items[id] and res.items[id].en or tostring(id), s.npc, (res.items[id] and res.items[id].en or ''):lower()))
                dbg(string.format('buy: learned %d (x%d) from %s (%s)', id, d, s.npc, seq_str(steps)))
            end
        end
    end
    s.inv, s.last = now, upto
end

-- watch what the player opens by hand (and catch our own runs' packets)
windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
    if id ~= 0x05B or injected then return end
    local p = packets.parse('outgoing', data)
    local mob = p['Target Index'] and windower.ffxi.get_mob_by_index(p['Target Index'])
    if not (mob and SHOP_NPCS[mob.name]) then return end
    local s = B.ses
    if not s or s.idx ~= p['Target Index'] or os.clock() - s.t > 60 then
        s = {npc = mob.name, idx = p['Target Index'], seq = {}, t = os.clock()}
        B.ses = s
    end
    s.seq[#s.seq + 1] = {menu = p['Menu ID'], opt = p['Option Index'], unk = p['_unknown1'] or 0, auto = p['Automated Message'] and true or false}
    s.t = os.clock()
    if EV.npcs[mob.name] and not B.run then   -- v5.61
        local upto = #s.seq
        coroutine.schedule(function() EV.check(s, upto) end, 2.5)
    end
end)
windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if injected then return end
    local r = B.run
    if id == 0x034 or id == 0x032 then
        local p = packets.parse('incoming', data)
        local mob = p['NPC Index'] and windower.ffxi.get_mob_by_index(p['NPC Index'])
        if mob and SHOP_NPCS[mob.name] then
            B.menu[mob.name] = p['Menu ID']
            if not r then
                B.ses = {npc = mob.name, idx = p['NPC Index'], seq = {}, t = os.clock()}   -- a new talk: new steps
                if EV.npcs[mob.name] then   -- v5.61: what you have now + your IS (his menu's first number)
                    local bal = id == 0x034 and data:unpack('I', 9) or nil
                    B.ses.inv, B.ses.last, B.ses.bal = EV.inv_counts(), 0, bal
                    local pp = B.pend   -- bought by hand last talk: the IS it took
                    if pp and pp.npc == mob.name and pp.bal and bal and bal < pp.bal and (pp.bal - bal) % pp.n == 0 then
                        local e = shop_cat()[pp.npc] and shop_cat()[pp.npc][pp.id]
                        if e then e.price = (pp.bal - bal) / pp.n; shop_save() end
                    end
                    B.pend = nil
                end
            end
        end
        if r and r.stage == 'menu' and p['NPC'] == r.npc_id then
            if id == 0x034 then r.bal = data:unpack('I', 9) end   -- v5.61 (Asrahd: your IS)
            r.menu, r.stage = p['Menu ID'], 'shop'
            return true   -- our menu: never drawn
        end
        return
    end
    if id == 0x03C then
        local list = parse_shop(data)
        if r and r.stage == 'shop' then
            for _, e in ipairs(list) do r.items[e.item] = e end
            r.got_shop = os.clock()
            return true   -- no buy window
        end
        local s = B.ses
        if s and os.clock() - s.t < 15 and #s.seq > 0 then
            local n = learn_list(s.npc, seq_str(s.seq), list)
            if n > 0 then dbg(string.format('buy: learned %d items from %s (%s)', n, s.npc, seq_str(s.seq))) end
        end
        return
    end
    if id == 0x03F and r and r.stage == 'buying' then
        local cnt = data:unpack('I', 9) or 0
        r.ack = (r.ack or 0) + cnt
        r.ack_t = os.clock()
    end
end)

local function shop_mob(names)
    local best, bd = nil, nil
    for idx, name in pairs(windower.ffxi.get_mob_list() or {}) do
        if names[name] then
            local m = windower.ffxi.get_mob_by_index(idx)
            if m and m.valid_target and (m.id or 0) > 0 then
                local d = math.sqrt(m.distance or 0)
                if not bd or d < bd then best, bd = m, d end
            end
        end
    end
    return best, bd
end
local function wait_for(cond, secs)
    local t0 = os.clock()
    while not cond() and os.clock() - t0 < secs do coroutine.sleep(0.1) end
    return cond()
end
-- walk to a moogle 6-50y away (the nav walk is for warps; this one is short)
local function walk_to(mob, reply)
    local t0 = os.clock()
    while os.clock() - t0 < 25 do
        local m = windower.ffxi.get_mob_by_index(mob.index)
        local me_m = windower.ffxi.get_mob_by_target('me')
        if not (m and me_m) then break end
        local d = math.sqrt(m.distance or 0)
        if d <= 4 then windower.ffxi.run(false); return true end
        windower.ffxi.run(m.x - me_m.x, m.y - me_m.y)
        coroutine.sleep(0.1)
    end
    windower.ffxi.run(false)
    return false
end
local function poke(mob)
    windower.ffxi.run(false)
    set_target(mob.index)
    coroutine.sleep(0.2)
    packets.inject(packets.new('outgoing', 0x01A, {
        ['Target'] = mob.id, ['Target Index'] = mob.index, ['Category'] = 0, ['Param'] = 0, ['_unknown1'] = 0}))
end
local function send_steps(r, steps)
    for i, st in ipairs(steps) do
        local pk = packets.new('outgoing', 0x05B)
        pk['Target'] = r.npc_id
        pk['Option Index'] = st.opt
        pk['_unknown1'] = st.unk or 0
        pk['Target Index'] = r.npc_index
        pk['Automated Message'] = st.auto and true or false
        pk['_unknown2'] = 0
        pk['Zone'] = zone_id()
        pk['Menu ID'] = r.menu or st.menu
        packets.inject(pk)
        coroutine.sleep(i < #steps and 0.6 or 0.2)
    end
end
local function close_run(r)
    release_menu({menu = r.menu, npc_id = r.npc_id, npc_index = r.npc_index})
    if B.run == r then B.run = nil end
end
local function free_slots()
    local b = windower.ffxi.get_items(0)
    if type(b) ~= 'table' then return 0 end
    return (tonumber(b.max) or 80) - (tonumber(b.count) or 0)
end
local function gil_now()
    local it = windower.ffxi.get_items()
    return type(it) == 'table' and tonumber(it.gil) or nil
end
local function item_name(id) local it = res.items[id]; return it and it.en or ('item ' .. tostring(id)) end

-- one menu of a moogle: talk, open it with the remembered steps, catch the list
local function open_shop(mob, steps)
    local r = {npc_id = mob.id, npc_index = mob.index, npc = mob.name, stage = 'menu', items = {}}
    B.run = r
    poke(mob)
    if not wait_for(function() return r.stage ~= 'menu' end, 3) then
        poke(mob)
        if not wait_for(function() return r.stage ~= 'menu' end, 3) then
            if B.run == r then B.run = nil end
            return nil, mob.name .. ' did not answer'
        end
    end
    send_steps(r, steps)
    wait_for(function() return r.got_shop ~= nil end, 3)
    if r.got_shop then wait_for(function() return os.clock() - r.got_shop > 0.6 end, 1.5) end   -- big shops: several packets
    return r
end

-- v5.61: Asrahd: one talk per item -- talk (menu hidden), the learned
-- answers, wait for the item, close
function EV.talk(mob, steps)
    local r = {npc_id = mob.id, npc_index = mob.index, npc = mob.name, stage = 'menu', items = {}}
    B.run = r
    poke(mob)
    if not wait_for(function() return r.stage ~= 'menu' end, 3) then
        poke(mob)
        if not wait_for(function() return r.stage ~= 'menu' end, 3) then
            if B.run == r then B.run = nil end
            return nil
        end
    end
    return r
end
function EV.close(r, steps)
    local last = steps[#steps]
    if last and last.auto then release_menu({menu = r.menu, npc_id = r.npc_id, npc_index = r.npc_index})
    else release_menu(nil) end   -- his talk already ended with your answer
    if B.run == r then B.run = nil end
end
function EV.buy_run(ctx, npc, id, qty, reply, mob)
    local e = shop_cat()[npc][id]
    local steps = seq_parse(e.seq)
    if #steps == 0 then return reply(my_name() .. ': AA has no menu answers for ' .. item_name(id) .. ' -- buy one from ' .. npc .. ' by hand once.') end
    local it = res.items[id]
    local stack = (it and tonumber(it.stack)) or 1
    local per = math.max(1, e.per or 1)
    local free = free_slots()
    if free < 1 then return reply(my_name() .. ': no free inventory slot.') end
    local have = EV.inv_count(id)
    local room = free * stack + ((have > 0 and stack > 1) and (stack - have % stack) % stack or 0)
    if qty > room then
        qty = room
        reply(string.format('%s: room for %d only -- buying %d.', my_name(), room, qty))
    end
    local bought, prev_bal, why = 0, nil, nil
    while bought < qty do
        local before = EV.inv_count(id)
        local r = EV.talk(mob, steps)
        if not r then why = npc .. ' did not answer'; break end
        if prev_bal and r.bal and r.bal < prev_bal and (prev_bal - r.bal) % per == 0 and e.price ~= (prev_bal - r.bal) / per then
            e.price = (prev_bal - r.bal) / per; shop_save()
        end
        if e.price and e.price > 0 and r.bal and r.bal < e.price then
            EV.close(r, {{auto = true}})
            why = string.format('not enough %s (%d, one costs %d)', EV.npcs[npc] or 'points', r.bal, e.price)
            break
        end
        prev_bal = r.bal
        send_steps(r, steps)
        local got = wait_for(function() return EV.inv_count(id) > before end, 4)
        EV.close(r, steps)
        if not got then why = 'nothing came (' .. (EV.npcs[npc] or 'points') .. ', rank, or not unlocked on this character?)'; break end
        bought = bought + (EV.inv_count(id) - before)
        coroutine.sleep(1.0)
    end
    -- price not known yet: one more talk shows what the last one took
    if bought > 0 and (e.price or 0) == 0 and prev_bal then
        coroutine.sleep(0.5)
        local r = EV.talk(mob, steps)
        if r then
            if r.bal and r.bal < prev_bal then e.price = math.floor((prev_bal - r.bal) / per + 0.5); shop_save() end
            EV.close(r, {{auto = true}})
        end
    end
    if bought > 0 then
        reply(string.format('%s: bought %d %s from %s%s%s.', my_name(), bought, item_name(id), npc,
            (e.price or 0) > 0 and string.format(' for %d %s', math.floor(bought / per) * e.price, EV.npcs[npc] or '') or '',
            why and (' -- stopped: ' .. why) or ''))
    else
        reply(string.format('%s: %s did not sell %s -- %s.', my_name(), npc, item_name(id), why or '?'))
    end
end

local function buy_run(ctx, npc, id, qty, reply)
    local e = shop_cat()[npc][id]
    local mob, d = shop_mob({[npc] = true})
    if not mob then return reply(my_name() .. ': no ' .. npc .. ' here.') end
    if d > 6 then
        if d > (tonumber(opt('walk_range')) or 50) then
            return reply(string.format('%s: %s is %dy away -- walk closer (aa nav %s).', my_name(), npc, math.floor(d + 0.5), npc:lower()))
        end
        if not walk_to(mob, reply) then return reply(my_name() .. ': could not get to ' .. npc .. '.') end
    end
    if e.kind == 'event' then return EV.buy_run(ctx, npc, id, qty, reply, mob) end   -- v5.61 (Asrahd)
    local it = res.items[id]
    local stack = (it and tonumber(it.stack)) or 1
    local cost = (e.price or 0) * qty
    local gil = gil_now()
    if gil and cost > gil then
        return reply(string.format('%s: %d %s cost %d gil -- you have %d.', my_name(), qty, item_name(id), cost, gil))
    end
    local need = math.ceil(qty / math.max(1, stack))
    local free = free_slots()
    if free < 1 then return reply(my_name() .. ': no free inventory slot.') end
    if need > free then
        qty = free * stack
        reply(string.format('%s: room for %d stack(s) only -- buying %d.', my_name(), free, qty))
    end
    local r, why = open_shop(mob, seq_parse(e.seq))
    if not r then return reply(my_name() .. ': ' .. why .. '.') end
    local fresh = r.items[id]
    if not fresh then
        close_run(r)
        return reply(string.format('%s: %s is not in that menu any more -- "aa buy scan" (or open its menu once by hand).', my_name(), item_name(id)))
    end
    if fresh.slot ~= e.slot or fresh.price ~= e.price then
        e.slot, e.price = fresh.slot, fresh.price
        shop_save()
    end
    r.stage, r.ack = 'buying', 0
    local left, bought = qty, 0
    while left > 0 do
        local n = math.min(left, stack)
        local before = r.ack
        packets.inject(packets.new('outgoing', 0x083, {['Count'] = n, ['_unknown2'] = 0, ['Shop Slot'] = fresh.slot, ['_unknown3'] = 0, ['_unknown4'] = 0}))
        if not wait_for(function() return r.ack > before end, 3) then break end
        bought = bought + (r.ack - before)
        left = qty - bought
        coroutine.sleep(0.4)
    end
    close_run(r)
    if bought > 0 then
        reply(string.format('%s: bought %d %s for %d gil.', my_name(), bought, item_name(id), bought * (fresh.price or 0)))
    else
        reply(string.format('%s: %s did not sell %s (gil, inventory, or not unlocked on this character?).', my_name(), npc, item_name(id)))
    end
end

local function buy_scan(reply)
    local mob, d = shop_mob(SCAN_NPCS)
    if not mob then return reply(my_name() .. ': no Curio Vendor Moogle here (Port San d\'Oria / Port Bastok / Port Windurst). Green Thumb Moogle: open its shop menus once by hand.') end
    if d > 6 then
        if d > (tonumber(opt('walk_range')) or 50) or not walk_to(mob, reply) then
            return reply(string.format('%s: walk to the %s (%dy) and try again.', my_name(), mob.name, math.floor(d + 0.5)))
        end
    end
    reply(my_name() .. ': looking through every menu of the ' .. mob.name .. ' (a few seconds each)...')
    local found, menus, z0 = 0, 0, zone_id()
    for o = 1, 12 do
        if zone_id() ~= z0 then break end
        local r, why = open_shop(mob, {{opt = o, unk = 0, auto = false}})
        if not r then reply(my_name() .. ': scan stopped -- ' .. why .. '.'); break end
        local list = {}
        for _, e in pairs(r.items) do list[#list + 1] = e end
        close_run(r)
        if #list > 0 then
            menus = menus + 1
            found = found + learn_list(mob.name, seq_str({{menu = r.menu, opt = o, unk = 0, auto = false}}), list)
        end
        coroutine.sleep(1.5)
    end
    reply(string.format('%s: %s -- %d menus, %d items known (data/shops_%s.lua).', my_name(), mob.name, menus, found, my_name()))
end

-- aa buy [scan | list [text] | <item> [qty]]
function aa_buy_command(ctx, words, reply)
    local w = {}
    for _, x in ipairs(words or {}) do w[#w + 1] = x end
    local first = (w[1] or ''):lower()
    if first == '' then
        return reply('aa buy <item or part of its name> [qty] | aa buy list [text] | aa buy scan (at a Curio Vendor Moogle) | Asrahd: buy an item from him by hand once')
    end
    if B.run then return reply(my_name() .. ': a purchase is already running.') end
    if first == 'scan' then return coroutine.schedule(function() buy_scan(reply) end, 0) end
    local qty = 1
    if #w > 1 and tonumber(w[#w]) then qty = math.max(1, math.floor(tonumber(w[#w]))); table.remove(w) end
    local listing = (first == 'list')
    if listing then table.remove(w, 1) end
    local q = table.concat(w, ' '):lower():gsub('^%s+', ''):gsub('%s+$', '')
    if B.fix_save then B.fix_save = nil; shop_save() end   -- v5.54
    -- v5.54: every word of the text starts a word of the name, in order
    -- ("sar cot" = Saruta Cotton, "w tea" = Win. Tea Leaves)
    local qw = {}
    for x in q:gmatch('%S+') do qw[#qw + 1] = x end
    local function word_starts(name)
        if #qw == 0 then return false end
        local nw = {}
        for x in name:gmatch("[%w']+") do nw[#nw + 1] = x end
        local j = 1
        for _, x in ipairs(qw) do
            x = x:gsub('[^%w\']', '')
            while j <= #nw and nw[j]:sub(1, #x) ~= x do j = j + 1 end
            if j > #nw then return false end
            j = j + 1
        end
        return true
    end
    -- matches: the moogles here first, then by name
    local here = {}
    for name in pairs(SHOP_NPCS) do if shop_mob({[name] = true}) then here[name] = true end end
    local hits = {}
    for npc, items in pairs(shop_cat()) do
        for id, e in pairs(items) do
            local it = res.items[id]
            if it then
                local n, nl = it.en:lower(), (it.enl or ''):lower()
                if q == '' or n:find(q, 1, true) or nl:find(q, 1, true) or word_starts(n) or word_starts(nl) then
                    hits[#hits + 1] = {npc = npc, id = id, e = e, name = it.en, exact = (n == q or nl == q), here = here[npc] and true or false}
                end
            end
        end
    end
    table.sort(hits, function(a, b)
        if a.exact ~= b.exact then return a.exact end
        if a.here ~= b.here then return a.here end
        if a.name ~= b.name then return a.name < b.name end
        return a.npc < b.npc
    end)
    if next(shop_cat()) == nil then
        return reply(my_name() .. ': AA does not know any moogle shop yet -- "aa buy scan" at a Curio Vendor Moogle, or open the moogle\'s menus once by hand (Asrahd: buy the item from him by hand once).')
    end
    if #hits == 0 then
        for _, wname in ipairs(EV.wares) do   -- v5.61: one of Asrahd's, not learned yet
            if q ~= '' and (wname:find(q, 1, true) or q:find(wname, 1, true)) then
                return reply(my_name() .. ': "' .. q .. '" sounds like Asrahd\'s (Imperial Standing, Aht Urhgan Whitegate I-8) -- AA learns it when you buy one from him by hand once; then aa buy does the rest.')
            end
        end
        return reply(my_name() .. ': no shop item matches "' .. q .. '" (aa buy list shows them all).')
    end
    if listing then
        for i, h in ipairs(hits) do
            if i > 30 then reply(string.format('... %d more', #hits - 30)); break end
            reply(string.format('%s -- %s (%s)', h.name, EV.price_str(h.npc, h.e), h.npc))
        end
        return
    end
    -- one item (or an exact name): buy it; several: say which
    local pick = nil
    if hits[1].exact then pick = hits[1] else
        local ids = {}
        for _, h in ipairs(hits) do ids[h.id] = true end
        local n = 0
        for _ in pairs(ids) do n = n + 1 end
        if n == 1 then pick = hits[1] end
    end
    local function go(h)
        if B.run then return reply(my_name() .. ': a purchase is already running.') end
        if not h.here and not shop_mob({[h.npc] = true}) then
            return reply(string.format('%s: %s is sold by %s%s -- go there first (aa nav %s).', my_name(), h.name,
                EV.npcs[h.npc] and '' or 'the ', h.npc, EV.hint[h.npc] or h.npc:lower()))
        end
        coroutine.schedule(function() buy_run(ctx, h.npc, h.id, qty, reply) end, 0)
    end
    if not pick then
        -- v5.54 (Mark, 2026-11-24: "aa buy saruta 1" showed Saruta Cotton 48 gil
        -- and Saruta Orange 38 gil and bought nothing): several items match --
        -- a list to click (left-click buys that one), plus the lines in chat
        reply(my_name() .. ': "' .. q .. '" matches ' .. 'several items -- click one in the list (or type more of the name):')
        local shown, rows = {}, {}
        rows.title = string.format(' AA buy "%s"  x%d   left-click: buy   [X] close ', q, qty)
        for _, h in ipairs(hits) do
            if not shown[h.id] then
                shown[h.id] = true
                local n = 0
                for _ in pairs(shown) do n = n + 1 end
                if n <= 8 then
                    reply(string.format('  aa buy %s %d  -- %s each (%s)', h.name:lower(), qty, EV.price_str(h.npc, h.e), h.npc))
                end
                if n <= 40 then
                    local hh = h
                    rows[#rows + 1] = {
                        text = string.format('  %-24s %8s  x%-3d %9s   %s%s ', h.name, EV.price_str(h.npc, h.e), qty,
                            (h.e.price or 0) > 0 and EV.price_str(h.npc, {price = (h.e.price or 0) * qty}) or '?', h.npc, h.here and '' or '  (not here)'),
                        trade = function() go(hh) end,
                    }
                end
            end
        end
        gui_show('buy', rows)
        N.gui_party = false
        return
    end
    go(pick)
end

-- ===========================================================================
-- v5.49: aa trade seals | crests | rems (Mark, 2026-11-23: "let's add a new
-- feature 'aa trade [type]'. For this round is focused on trading items to
-- store at stuff npcs"). Takes every beastmen's seal / Kindred's seal (seals)
-- or Kindred's / High / Sacred Kindred's crest (crests) out of the inventory,
-- satchel, sack and case and trades them to Shami (Port Jeuno H-8) for
-- storage, 8 stacks per trade; Rem's Tale Ch.1-10 the same to Monisette
-- (Port Jeuno I-8). Shami holds 9999 of each kind, Monisette 255 of each
-- chapter. A kind that is full stays with you and AA says so; for seals and
-- crests a list opens with what Shami holds and an exchange at Shemo (Shami's
-- brother, next to him), who swaps STORED seals/crests 3:1 (2:1 during a
-- campaign -- AA reads the rate from Shemo's own words): the suggestion is
-- 3000 (2000) of the full kind for 1000 of the kind you have least of.
-- Shami's / Shemo's lines in chat give AA the stored counts
-- (data/trade_<name>.lua). The Shemo exchange: AA walks you to him, opens
-- his menu and tells you exactly what to pick and the number to enter (his
-- offer / balances are drawn by the game from the menu itself, so AA can't
-- check them with the menu hidden); it reads the result and records your
-- menu answers for a later version to do it alone.
-- ===========================================================================
do
local SEAL = {   -- order = Shemo's list; key = Shami's / Shemo's plural words
    {id = 1126, key = "beastmen's seals",        short = "Beastmen's Seal"},
    {id = 1127, key = "kindred's seals",         short = "Kindred's Seal"},
    {id = 2955, key = "kindred's crests",        short = "Kindred's Crest"},
    {id = 2956, key = "high kindred's crests",   short = "H. Kindred Crest"},
    {id = 2957, key = "sacred kindred's crests", short = "S. Kindred Crest"},
}
local BYKEY, BYID = {}, {}
for i, e in ipairs(SEAL) do e.n = i; BYKEY[e.key] = e; BYID[e.id] = e end
local KINDS = {
    -- v5.50: seals and crests both take every kind (Mark: "aa trade seals and aa trade crests
    -- (with trade both seals and crests)")
    seals  = {npcs = {'Shami', 'Shemo'}, ids = {1126, 1127, 2955, 2956, 2957}, cap = 9999, label = 'seals & crests'},
    rems   = {npcs = {'Monisette'}, ids = {4064, 4065, 4066, 4067, 4068, 4069, 4070, 4071, 4072, 4073}, cap = 255, label = "Rem's Tales"},
}
local FROM_BAGS = {5, 6, 7}   -- satchel, sack, case (wherever you are)
local SEAL_NPC = {Shami = true, Shemo = true}
local T = {char = nil, d = nil, run = nil, ex = nil, stop = false}
AA_TRADE = T

local function tfile() return data_file('trade_' .. my_name() .. '.lua') end
local function tdata()
    local n = my_name()
    if T.char ~= n then
        T.char = n
        T.d = read_table(tfile()) or {}
        T.d.counts = T.d.counts or {}
        T.d.learned = T.d.learned or {}
    end
    return T.d
end
local function tsave()
    local d = tdata()
    local f = io.open(tfile(), 'w')
    if not f then return end
    f:write('-- AutoAttack aa trade: what Shami holds for ' .. T.char .. ' (from his / Shemo\'s words) + the learned Shemo exchange\nreturn {\n')
    f:write('    counts = {')
    for _, e in ipairs(SEAL) do
        if d.counts[e.id] then f:write(string.format(' [%d] = %d,', e.id, d.counts[e.id])) end
    end
    f:write(' },\n')
    f:write(string.format('    counts_t = %d,\n', d.counts_t or 0))
    if d.rate then f:write(string.format('    rate = %d, rate_t = %d,   -- Shemo: %d for 1\n', d.rate, d.rate_t or 0, d.rate)) end
    if d.rate_set then f:write(string.format('    rate_set = %d,   -- aa trade rate\n', d.rate_set)) end
    f:write('    learned = {\n')
    for k, l in pairs(d.learned) do
        f:write(string.format('        [%q] = {menu = %d, qty = %d, seq = %q},\n', k, l.menu or 0, l.qty or 0, l.seq or ''))
    end
    f:write('    },\n}\n')
    f:close()
end
local function tname(id) local it = res.items[id]; return it and it.en or ('item ' .. tostring(id)) end

-- Shemo's rate: aa trade rate 2|3 wins; a rate he said in the last 3 days next; else 3:1
local function rate_now()
    local d = tdata()
    if d.rate_set then return d.rate_set, 'set by you' end
    if d.rate and os.time() - (d.rate_t or 0) < 3 * 86400 then
        return d.rate, (d.rate == 2 and 'campaign, Shemo said so ' or 'Shemo said so ') .. os.date('%m/%d %H:%M', d.rate_t)
    end
    return 3, 'normal rate'
end
local function set_rate(r, why)
    if r ~= 2 and r ~= 3 then return end
    local d = tdata()
    if d.rate ~= r then dbg('trade: Shemo rate ' .. r .. ':1 (' .. why .. ')') end
    d.rate, d.rate_t = r, os.time()
    tsave()
end
local function set_count(key, n)
    local e = BYKEY[(key or ''):lower()]
    if not (e and n) then return end
    local d = tdata()
    d.counts[e.id], d.counts_t = n, os.time()
    T.dirty = true
end

-- ---------------------------------------------------------------------------
-- what Shami / Shemo / Monisette say
-- ---------------------------------------------------------------------------
windower.register_event('incoming text', function(original, modified, mode)
    if type(original) ~= 'string' then return end
    local t = original:gsub('[%c\127-\255]', ''):gsub('^%s+', '')
    local who, msg = t:match('^(%a+) : (.+)$')
    if not who then
        -- the exchange window line (no speaker)
        local a, an, b, bn, want, mx = t:match('balance of (%d+) (.-) and (%d+) (.-)%.Enter the number of (.-) you wish to obtain: %(Maximum: (%d+)%)')
        if a then
            a, b, mx = tonumber(a), tonumber(b), tonumber(mx)
            set_count(an, a); set_count(bn, b)
            local give = (want:lower() == an:lower()) and b or a
            if mx and mx > 0 then set_rate(math.floor(give / mx + 0.001), 'Maximum ' .. mx .. ' of ' .. give) end
            if T.ex then T.ex.window = true end
            tsave()
        end
        return
    end
    if T.run then T.run.heard = os.clock() end
    if who == 'Monisette' then return end
    if not SEAL_NPC[who] then return end
    local n, key = msg:match('^(%d+) (.-)%.$')
    if n then set_count(key, tonumber(n)) end
    local k2, n2 = msg:match('total balance of (.-) to (%d+)%.')
    if k2 then set_count(k2, tonumber(n2)) end
    local n3, k3, n4, k4 = msg:match('total balance to (%d+) (.-) and (%d+) (.-)%.')
    if n3 then set_count(k3, tonumber(n3)); set_count(k4, tonumber(n4)) end
    local n5, k5 = msg:match('got a balance of (%d+) (.-)%.$')
    if n5 then set_count(k5, tonumber(n5)) end
    local r = msg:match('of your choice for (%w+) of yours')
    if r then set_rate(tonumber(r) or (r == 'two' and 2) or (r == 'three' and 3), 'Shemo: for ' .. r .. ' of yours') end
    local tk, tkey, gkey = msg:match("takin' (%d+) (.-) off your hands to give as many (.-) as ya")
    if tk and T.ex then T.ex.quote = {n = tonumber(tk), give = BYKEY[tkey:lower()], get = BYKEY[gkey:lower()], t = os.clock()} end
    if msg:find('Another satisfied customer', 1, true) and T.ex then T.ex.done = os.clock() end
    if T.dirty then T.dirty = false; tsave() end
end)

-- ---------------------------------------------------------------------------
-- items: count, pull out of satchel / sack / case, trade
-- ---------------------------------------------------------------------------
local function carried(ids, bags)
    local set = {}
    for _, id in ipairs(ids) do set[id] = true end
    local out, stacks = {}, {}
    for _, bag in ipairs(bags) do
        local b = windower.ffxi.get_items(bag)
        if type(b) == 'table' and b.enabled ~= false then
            for slot, it in ipairs(b) do
                if type(it) == 'table' and set[it.id] and (it.count or 0) > 0 then
                    out[it.id] = (out[it.id] or 0) + it.count
                    stacks[#stacks + 1] = {bag = bag, slot = slot, id = it.id, count = it.count, status = it.status or 0}
                end
            end
        end
    end
    return out, stacks
end
local function trade_npc(mob, stacks)
    local q, ix = {}, {}
    for i = 1, 9 do q[i], ix[i] = 0, 0 end
    for i, st in ipairs(stacks) do q[i], ix[i] = st.count, st.slot end
    local pk = ('C4I11C10HI'):pack(0x36, 0x20, 0, 0, mob.id,
        q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8], q[9], 0,
        ix[1], ix[2], ix[3], ix[4], ix[5], ix[6], ix[7], ix[8], ix[9], 0,
        mob.index, #stacks)
    windower.packets.inject_outgoing(0x36, pk)
end
local function in_event()
    local p = me()
    return p and p.status == 4
end
local function find_npc(names)
    local best, bd
    for _, n in ipairs(names) do
        local m, d = shop_mob({[n] = true})
        if m and (not bd or d < bd) then best, bd = m, d end
    end
    return best, bd
end
local function get_there(names, reply)
    local mob, d = find_npc(names)
    if not mob then
        return nil, string.format('no %s here -- %s is in Port Jeuno (aa nav %s).', names[1], names[1], names[1]:lower())
    end
    if d > 5.5 then
        if d > (tonumber(opt('walk_range')) or 50) then
            return nil, string.format('%s is %dy away -- walk closer (aa nav %s).', mob.name, math.floor(d + 0.5), mob.name:lower())
        end
        if not walk_to(mob, reply) then return nil, 'could not get to ' .. mob.name end
        mob = windower.ffxi.get_mob_by_index(mob.index) or mob
    end
    return mob
end

local show_list   -- forward

local function store_run(kind, reply)
    local K = KINDS[kind]
    local r = {kind = kind, t0 = os.clock()}
    T.run, T.stop = r, false
    local function done(msg)
        if T.run == r then T.run = nil end
        if msg then reply(my_name() .. ': ' .. msg) end
    end
    local p = me()
    if not p then return done() end
    if p.status ~= 0 then return done('stand still first (not fighting, resting or in a menu).') end
    local all, _ = carried(K.ids, {0, 5, 6, 7})
    local total = 0
    for _, n in pairs(all) do total = total + n end
    local far, _ = carried(K.ids, {1, 2, 4, 9})   -- Mog House only
    local farn = 0
    for _, n in pairs(far) do farn = farn + n end
    if total == 0 then
        return done(string.format('no %s in your inventory, satchel, sack or case%s.', K.label,
            farn > 0 and string.format(' (%d in your Mog Safe / Storage / Locker -- move them to your inventory first)', farn) or ''))
    end
    local mob, why = get_there(K.npcs, reply)
    if not mob then return done(why) end
    reply(string.format('%s: trading %d %s to %s...', my_name(), total, K.label, mob.name))
    local stored, full, notified = {}, {}, false
    -- never hand over more than fits: Shami's count (his own words) + what we gave
    local d = tdata()
    local known = {}
    -- v5.50: Shami refuses what doesn't fit and nothing is lost (Mark, 2026-11-23: "Shami
    -- will not accept past 9999, and extra traded will not be lost"); v5.51: Monisette
    -- the same ("rems tales traded over 255 are not lost") -- no cap for either
    local function room(id) return nil end
    local function counts_fresh()
        if kind == 'rems' then return true end
        if os.time() - (d.counts_t or 0) > 86400 then return false end
        for _, id in ipairs(K.ids) do if (all[id] or 0) > 0 and not d.counts[id] then return false end end
        return true
    end
    local probe = false   -- v5.50: no 1-item first trade any more
    for round = 1, 80 do
        if T.stop then return done('trade stopped.') end
        -- 1. top up the inventory from satchel / sack / case
        local _, inv = carried(K.ids, {0})
        local ready = {}
        for _, st in ipairs(inv) do if st.status == 0 and not full[st.id] then ready[#ready + 1] = st end end
        if #ready < 8 then
            local _, other = carried(K.ids, FROM_BAGS)
            local moved = 0
            for _, st in ipairs(other) do
                if #ready + moved >= 8 or free_slots() - moved < 1 then break end
                if not full[st.id] then
                    windower.ffxi.get_item(st.bag, st.slot, st.count)
                    moved = moved + 1
                    coroutine.sleep(0.3)
                end
            end
            if moved > 0 then
                local want = #ready + moved
                wait_for(function()
                    local _, s2 = carried(K.ids, {0})
                    local n = 0
                    for _, st in ipairs(s2) do if st.status == 0 and not full[st.id] then n = n + 1 end end
                    return n >= want
                end, 4)
                _, inv = carried(K.ids, {0})
                ready = {}
                for _, st in ipairs(inv) do if st.status == 0 and not full[st.id] then ready[#ready + 1] = st end end
            end
        end
        if #ready == 0 then break end
        while #ready > 8 do table.remove(ready) end
        -- what still fits (seals / crests: 9999 each)
        local fit, left = {}, {}
        for _, st in ipairs(ready) do
            local rm = left[st.id]
            if rm == nil then rm = room(st.id) or math.huge end
            if probe then rm = (fit[1] and 0) or 1 end   -- first trade: 1 item, Shami tells us what he holds
            if rm <= 0 then
                if not probe then full[st.id] = true end
            else
                local take = math.min(st.count, rm)
                fit[#fit + 1] = {bag = st.bag, slot = st.slot, id = st.id, count = take, status = st.status}
                left[st.id] = rm - take
            end
        end
        ready = fit
        if #ready == 0 then
            local any = false
            for _, st in ipairs(inv) do if st.status == 0 and not full[st.id] then any = true end end
            if not any then
                local _, other = carried(K.ids, FROM_BAGS)
                for _, st in ipairs(other) do if not full[st.id] then any = true end end
            end
            if not any then break end
        end
        -- 2. trade (one kind at a time once something was refused: finds the full one)
        if r.single then
            local id = ready[1].id
            local one = {}
            for _, st in ipairs(ready) do if st.id == id then one[#one + 1] = st end end
            ready = one
        end
        mob = windower.ffxi.get_mob_by_index(mob.index) or mob
        if math.sqrt(mob.distance or 0) > 6 then return done(mob.name .. ' is too far away now -- trade stopped.') end
        local before = carried(K.ids, {0})
        local cb, backup = {}, nil
        for _, id in ipairs(K.ids) do cb[id] = d.counts[id] end
        if probe then   -- Shami lists only the kinds he holds: clear ours, a kind he doesn't name is 0
            backup = cb
            for _, id in ipairs(K.ids) do d.counts[id] = nil end
        end
        local said_t = os.clock()
        local ids_in = {}
        for _, st in ipairs(ready) do ids_in[st.id] = (ids_in[st.id] or 0) + st.count end
        dbg(string.format('trade: round %d, %d stacks to %s', round, #ready, mob.name))
        trade_npc(mob, ready)
        local took = wait_for(function()
            local now = carried(K.ids, {0})
            for id in pairs(ids_in) do if (now[id] or 0) < (before[id] or 0) then return true end end
            return false
        end, 6)
        -- 3. let the NPC finish talking
        -- v5.55 (Mark, 2026-11-24: "can we streamline the trading process so we
        -- don't have to confirm on our side?"): the talk can open ~1s after the
        -- items leave (11-24 15:43:57 AA gave up before it started) -- wait for
        -- it, then press Enter through it: one press once a line has been up
        -- 0.5s (the words still show, so Shami's counts are still read)
        wait_for(function() return in_event() end, took and 3 or 1.5)
        local t1 = os.clock()
        local auto = opt('trade_auto_talk') ~= false
        local presses, last_press = 0, 0
        while in_event() and os.clock() - t1 < 30 do
            if T.stop then break end
            local nowc = os.clock()
            if auto and presses < 25 and nowc - math.max(r.heard or 0, t1) > 0.5 and nowc - last_press > 0.7 then
                presses, last_press = presses + 1, nowc
                windower.send_command('setkey enter down; wait 0.1; setkey enter up')
            end
            if not notified and nowc - t1 > (auto and 20 or 8) then
                notified = true
                reply(my_name() .. ': click through ' .. mob.name .. '\'s talk -- AA carries on after it.')
            end
            coroutine.sleep(0.1)
        end
        if presses > 0 then dbg(string.format('trade: pressed Enter %d time(s) through %s\'s talk (%.1fs)', presses, mob.name, os.clock() - t1)) end
        coroutine.sleep(0.8)
        local now = carried(K.ids, {0})
        local refused = {}
        local heard = (r.heard or 0) >= said_t
        if backup then
            if heard then
                for _, id in ipairs(K.ids) do if d.counts[id] == nil then d.counts[id] = 0 end end
                d.counts_t = os.time()
                tsave()
            else
                for id, v in pairs(backup) do d.counts[id] = v end
            end
        end
        for id, n in pairs(ids_in) do
            local gone = (before[id] or 0) - (now[id] or 0)
            if gone > 0 then
                stored[id] = (stored[id] or 0) + gone
                if d.counts[id] ~= cb[id] and heard then known[id] = d.counts[id]   -- his new total
                else known[id] = math.max(known[id] or 0, cb[id] or 0) + gone end
            end
            if gone < n then refused[#refused + 1] = id end
        end
        if not took then
            if #refused > 1 and not r.single then
                r.single = true   -- mixed trade refused: try one kind at a time
            elseif #refused >= 1 then
                for _, id in ipairs(refused) do full[id] = true end
            else
                return done(mob.name .. ' did not take the trade.')
            end
        else
            for _, id in ipairs(refused) do full[id] = true end
        end
        if in_event() then return done(mob.name .. '\'s talk is still open -- finish it and "aa trade ' .. kind .. '" again.') end
        if probe then
            probe = not counts_fresh()
            if probe and took then
                return done(mob.name .. ' did not say what he holds -- AA stopped to be safe (1 item traded, nothing lost; "aa trade ' .. kind .. '" tries again).')
            end
        end
    end
    -- summary
    local parts = {}
    for _, id in ipairs(K.ids) do
        if stored[id] then parts[#parts + 1] = string.format('%d %s', stored[id], tname(id)) end
    end
    reply(string.format('%s: stored %s with %s.', my_name(), #parts > 0 and table.concat(parts, ', ') or 'nothing', mob.name))
    for _, id in ipairs(K.ids) do
        local e = BYID[id]
        if e and d.counts[id] and d.counts[id] >= K.cap then full[id] = true end
    end
    local fl = {}
    for _, id in ipairs(K.ids) do
        if full[id] then
            local left = carried({id}, {0, 5, 6, 7})[id] or 0
            fl[#fl + 1] = string.format('%s (%d still with you)', tname(id), left)
        end
    end
    if #fl > 0 then
        reply(string.format('%s: %s is FULL on %s (%d each).', my_name(), mob.name, table.concat(fl, ', '), K.cap))
    end
    if farn > 0 then reply(string.format('%s: %d more %s are in your Mog House storage -- not traded.', my_name(), farn, K.label)) end
    done()
    if kind ~= 'rems' then
        local fid = nil
        for _, id in ipairs(K.ids) do if full[id] then fid = id; break end end
        if fid then show_list(fid, reply) end
    end
end

-- ---------------------------------------------------------------------------
-- the list: what Shami holds + exchanges at Shemo
-- ---------------------------------------------------------------------------
local exch_run   -- forward
local function count_str(n) return n and tostring(n) or '?' end
local function plan(fid)
    local d = tdata()
    local rate = rate_now()
    local rows = {}
    for _, e in ipairs(SEAL) do
        if e.id ~= fid then
            local have = d.counts[e.id]
            local room = 9999 - (have or 0)
            local get = math.min(1000, room)
            local from_have = d.counts[fid] or 9999
            get = math.min(get, math.floor(from_have / rate))
            if get > 0 then rows[#rows + 1] = {e = e, have = have, get = get, give = get * rate} end
        end
    end
    table.sort(rows, function(a, b)
        local ha, hb = a.have or 1e9, b.have or 1e9
        if ha ~= hb then return ha < hb end
        return a.e.n < b.e.n
    end)
    return rows, rate
end
show_list = function(fid, reply)
    local d = tdata()
    local rate, rwhy = rate_now()
    local carry = carried({1126, 1127, 2955, 2956, 2957}, {0, 5, 6, 7})
    local rows = {}
    local fe = fid and BYID[fid]
    rows.title = fe and string.format(' AA trade -- Shami is FULL on %s   left-click: exchange at Shemo   [X] close ', fe.short)
                     or ' AA trade -- seals & crests   left-click: exchange at Shemo   [X] close '
    rows[#rows + 1] = {info = true, head = true, text = string.format(' Stored with Shami%s (+ carried)', d.counts_t and d.counts_t > 0 and (' as of ' .. os.date('%m/%d %H:%M', d.counts_t)) or '')}
    for _, e in ipairs(SEAL) do
        local c = d.counts[e.id]
        rows[#rows + 1] = {info = true, text = string.format('   %-18s %5s%s%s', e.short, count_str(c),
            (carry[e.id] or 0) > 0 and string.format('  (+%d)', carry[e.id]) or '',
            (c and c >= 9999) and '  FULL' or '')}
    end
    if not next(d.counts) then
        rows[#rows + 1] = {info = true, text = '   (counts unknown -- trade one seal to Shami / talk to Shemo and AA reads them)'}
    end
    if fe then
        local opts = plan(fid)
        rows[#rows + 1] = {info = true, head = true, text = string.format(' Exchange at Shemo: %d for 1 (%s)', rate, rwhy)}
        for i, o in ipairs(opts) do
            rows[#rows + 1] = {
                text = string.format('   %4d %-17s -> %4d %-17s  you have %s%s', o.give, fe.short, o.get, o.e.short, count_str(o.have),
                    i == 1 and '  << least' or ''),
                hot = (i == 1),
                trade = function() coroutine.schedule(function() exch_run(fid, o.e.id, o.get, reply) end, 0) end,
            }
        end
        if #opts == 0 then rows[#rows + 1] = {info = true, text = '   nothing to exchange into (all others full?)'} end
    end
    gui_show('trade', rows)
    N.gui_party = false
    -- the suggested (lowest) exchange starts highlighted
    for li, r in pairs(N.gui_lines or {}) do
        if r and r.hot then N.hover_li = li end
    end
    N.rows_dirty = true
end

-- ---------------------------------------------------------------------------
-- Shemo's exchange: learn it once (by hand), then answer his menu ourselves
-- ---------------------------------------------------------------------------
-- watch the menu answers sent to Shemo (by hand: learning; ours are injected)
windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
    if id ~= 0x05B or injected then return end
    local x = T.ex
    if not x then return end
    local p = packets.parse('outgoing', data)
    if p['Target'] ~= x.npc_id then return end
    x.seq[#x.seq + 1] = {menu = p['Menu ID'], opt = p['Option Index'], unk = p['_unknown1'] or 0, auto = p['Automated Message'] and true or false}
end)
windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if injected or (id ~= 0x034 and id ~= 0x032) then return end
    local x = T.ex
    if not x then return end
    local p = packets.parse('incoming', data)
    if p['NPC'] ~= x.npc_id then return end
    x.menu = x.menu or p['Menu ID']
end)

exch_run = function(fid, tid, get, reply)
    if T.ex or T.run then return reply(my_name() .. ': a trade is already running.') end
    local d = tdata()
    local rate = rate_now()
    local fe, te = BYID[fid], BYID[tid]
    local mob, why = get_there({'Shemo'}, reply)
    if not mob then return reply(my_name() .. ': ' .. why) end
    -- Shemo's words (his offer, the balances) are drawn by the game from his
    -- menu, so AA can only check an exchange with the menu on screen: AA
    -- talks to him, you pick, AA reads the result (and keeps your menu
    -- answers in data/trade_<name>.lua for a later version to do it itself)
    local x = {npc_id = mob.id, npc_index = mob.index, seq = {}, t = os.clock(), fid = fid, tid = tid, get = get}
    T.ex, T.stop = x, false
    poke(mob)
    reply(string.format("%s: Shemo's menu: trade -> %s -> %s -> enter %d -> yes  (%d for 1 = %d %s)",
        my_name(), fe.short, te.short, get, rate, get * rate, fe.short))
    wait_for(function() return x.done ~= nil or T.stop or T.ex ~= x end, 180)
    if T.ex == x then T.ex = nil end
    local q = x.quote
    if x.done and q then
        local r2 = rate_now()
        local ob = math.floor(q.n / r2 + 0.5)
        if q.give == fe and q.get == te and #x.seq > 0 then
            d.learned[fid .. '>' .. tid] = {menu = x.menu or 0, qty = ob, seq = seq_str(x.seq)}
            tsave()
        end
        reply(string.format('%s: exchanged %d %s for %d %s (%d:1). aa trade list shows the new counts.', my_name(), q.n,
            q.give and q.give.short or '?', ob, q.get and q.get.short or '?', r2))
        if q.give ~= fe or q.get ~= te then reply(my_name() .. ': (not the exchange AA suggested -- fine, counts updated)') end
    elseif not x.done then
        reply(my_name() .. ': no exchange seen with Shemo (cancelled or timed out).')
    end
end

local ALIAS = {
    bs = 1126, beast = 1126, beastmen = 1126, ["beastmen's"] = 1126, beastmens = 1126,
    ks = 1127, kseal = 1127, kindredseal = 1127,
    kc = 2955, kcrest = 2955, kindredcrest = 2955,
    hkc = 2956, high = 2956, hk = 2956,
    skc = 2957, sacred = 2957, sk = 2957,
}
local function seal_arg(w)
    w = (w or ''):lower():gsub("[%s%.']", '')
    if ALIAS[w] then return ALIAS[w] end
    for _, e in ipairs(SEAL) do
        local s = e.short:lower():gsub("[%s%.']", '')
        if s == w or e.key:gsub("[%s%.']", '') == w or e.key:gsub("[%s%.']", ''):gsub('s$', '') == w then return e.id end
    end
end

function aa_trade_stop()
    local busy = T.run or T.ex
    T.stop = true
    if T.ex then T.ex = nil end
    return busy and true or false
end

-- aa trade seals | crests | rems | list | swap <from> <to> [n] | rate 2|3|auto | forget <from> <to>
function aa_trade_command(ctx, words, reply)
    local w = {}
    for _, x in ipairs(words or {}) do w[#w + 1] = x end
    local first = (w[1] or ''):lower():gsub("'", '')
    if first == '' or first == 'help' then
        return reply("aa trade seals (or crests: every seal and crest to Shami) | rem / rems (Rem's Tales to Monisette) | aa trade list | aa trade swap <from> <to> [how many you get] | aa trade rate 2|3|auto")
    end
    if (first == 'seals' or first == 'seal' or first == 'crests' or first == 'crest' or first == 'rem' or first == 'rems' or first == 'tales') then
        if T.run or T.ex then return reply(my_name() .. ': a trade is already running (aa stop stops it).') end
        local kind = (first:sub(1, 4) == 'seal' or first:sub(1, 5) == 'crest') and 'seals' or 'rems'
        return coroutine.schedule(function() store_run(kind, reply) end, 0)
    end
    if first == 'list' or first == 'status' or first == 'counts' then
        local d = tdata()
        local fid = nil
        for _, e in ipairs(SEAL) do if (d.counts[e.id] or 0) >= 9999 then fid = e.id; break end end
        if w[2] then fid = seal_arg(table.concat(w, '', 2)) or fid end
        return show_list(fid, reply)
    end
    if first == 'rate' then
        local d = tdata()
        local v = (w[2] or ''):lower():gsub(':1$', '')
        if v == '2' or v == '3' then d.rate_set = tonumber(v)
        elseif v == 'auto' or v == 'off' then d.rate_set = nil
        else
            local r, why = rate_now()
            return reply(string.format('%s: Shemo exchange %d for 1 (%s). aa trade rate 2|3|auto', my_name(), r, why))
        end
        tsave()
        local r, why = rate_now()
        return reply(string.format('%s: Shemo exchange now %d for 1 (%s).', my_name(), r, why))
    end
    if first == 'swap' or first == 'exchange' or first == 'forget' then
        local a, b = seal_arg(w[2]), seal_arg(w[3])
        if not (a and b) or a == b then
            return reply('aa trade ' .. first .. ' <from> <to> -- bs, ks, kc, hkc, skc (beastmen\'s seal, Kindred\'s seal, Kindred\'s / High / Sacred Kindred\'s crest)')
        end
        if first == 'forget' then
            tdata().learned[a .. '>' .. b] = nil
            tsave()
            return reply(string.format('%s: forgot the learned %s -> %s exchange.', my_name(), BYID[a].short, BYID[b].short))
        end
        local get = tonumber(w[4]) or 1000
        get = math.max(1, math.floor(get))
        return coroutine.schedule(function() exch_run(a, b, get, reply) end, 0)
    end
    reply(my_name() .. ': aa trade -- unknown "' .. first .. '" (aa trade help).')
end
end   -- v5.49 aa trade


N._test = {search = search, route = route, best_for = best_for, opt_how = opt_how, devices_here = devices_here,
           BY_MAP = function() return BY_MAP end, LANDMARKS = function() return LANDMARKS end,
           record_params = record_params, locked = locked}
return N
