--[[
    AutoAttack

    A Windower 4 addon for Final Fantasy XI that runs your combat loop for
    you: assist your party's battle target, or pull and fight mobs on your
    own, while it keeps weapon skills, job abilities, magic, healing, food
    and EXP/CP/Emporox rings going for the job you're on.

    Author:   Mark Williams
    Version:  4.53

    Requires: nothing beyond Windower 4 and its standard libraries.
    (v3.84: facing is built in -- the Facing addon is no longer needed.)
    (v3.95: targeting is built in -- the SetTarget addon is no longer needed.)

    Commands:
        //aa assist        follow the party's current battle target
        //aa pull           find and pull mobs on your own
        //aa stop           stop the loop
        //aa dumpinv        dump your inventory to the log (for debugging)
        //aa id             show the current target's mob ID (for mob_blacklist)
        //aa pet            show your pet's HP / TP / status (pet jobs)
        //aa debug [0|1|2]  debug level: 0 off, 1 release (minimal), 2 dev (deep + timing)
        //aa ds [clear]     Dread Spikes tracking: list the mobs it knows about / clear it
        //aa ws [off|on]    weapon skills off / back on until the addon is reloaded
        //aa config new     settings your aa_config.lua doesn't have yet (defaults in use)
        //aa version        this version and the newest on GitHub (= aa update check)
        //aa rollback       back to the version before the last aa update

    Party commands (v4.44, aa_party.lua) -- also sent by friends as
    "/tell <you> aa <command>" or "/p aa <command>" (party.friends in aa_config.lua):
        //aa invite me|<name> [sync <name>] [leader <name>] [fight]
        //aa fight | stop | stack (on the leader) | follow [name] | unfollow | cancel
        //aa disband | leave | leader <name> | sync <name> | unsync
        //aa trusts [group] | retr | retrust | rest | mount [name] | dismount | pass | lot
        //aa sneak | invis | sneak invis | warp (or 299)
        //aa nav <zone or place> | nav <n> | nav p<n> | nav party <name> | nav cancel   (v5.06, nav.lua)
        //aa buy <item> [qty] | buy list [text] | buy scan   (v5.45: Curio Vendor / Green Thumb Moogle)
        //aa trade seals | crests | rems | trade list | trade swap <from> <to> [n] | trade rate 2|3|auto   (v5.49)
        //aa status | ping | party | reload [all] | update [all|force|check] | rollback [all]

        ("//aa" works directly; "//lua c autoattack <command>" also works.)

    Configuration (whitelist / blacklist, Domain Invasion, elemental
    farming, master pull method, ws_mode, healing outside battle,
    move_to_target, and every job's trusts / pull / abilities / spells /
    weapon skills / rings / food) is in aa_config.lua -- edit that file,
    not this one. aa_config_defaults.lua is the shipped safe copy (v4.29).
    See README.md for full documentation.

    NOTE: Automating gameplay may violate the game's Terms of Service.
    Use at your own risk -- the author is not responsible for any
    consequences of using this addon.
]]

-- ===========================================================================
-- v4.65: SAFE START + ROLLBACK. Everything below runs inside AA_MAIN()
-- (closed at the bottom of this file) under xpcall. If AutoAttack fails to
-- start right after an "aa update" (data/reload_notify.txt, or AA_RELOAD_NOTE
-- if aa_party.lua already read it, names the version it came from), the files
-- that update backed up are put back, the sender is told why, and AutoAttack
-- reloads on the old version. aa_party.lua failing to load after an update
-- does the same. "aa rollback" uses these functions to go back by hand.
-- Kept small and outside AA_MAIN on purpose: it has to work when the rest
-- doesn't. Globals on purpose.
-- ===========================================================================
AA_UPDATE_FILES = {'autoattack.lua', 'aa_party.lua', 'aa_config_defaults.lua', 'README.md',
                   'nav.lua', 'nav_maps.lua', 'nav_zones.lua', 'nav_npcs.lua',
                   'nav_transports.lua'}   -- v5.06: aa nav files (v5.11: transports)
-- newest set of files an "aa update" backed up (backups/<file>_v<ver>_pre-update_<stamp>)
-- whose version isn't skip_ver; nil if none
function aa_rollback_find(skip_ver)
    local names = windower.get_dir and windower.get_dir(windower.addon_path .. 'backups/')
    if type(names) ~= 'table' then return nil end
    local best = nil
    for _, n in pairs(names) do
        local v, st = tostring(n):match('^autoattack_v(.-)_pre%-update_(.-)%.lua$')
        if v and v ~= skip_ver and (not best or st > best.stamp) then best = {ver = v, stamp = st} end
    end
    return best
end
-- copy that set back over the live files; true or false, why
function aa_rollback_restore(set)
    local dir, n_ok = windower.addon_path, 0
    for _, n in ipairs(AA_UPDATE_FILES) do
        local stem, ext = n:match('^(.-)(%.[^.]+)$')
        local src = io.open(dir .. 'backups/' .. stem .. '_v' .. set.ver .. '_pre-update_' .. set.stamp .. ext, 'rb')
        if src then
            local data = src:read('*a'); src:close()
            local dst = io.open(dir .. n, 'wb')
            if not dst then return false, 'could not write ' .. n end
            dst:write(data); dst:close()
            n_ok = n_ok + 1
        elseif n == 'autoattack.lua' then
            return false, 'backup of autoattack.lua not found'
        end
    end
    return n_ok > 0, (n_ok == 0) and 'no backup files found' or nil
end
function aa_safe_say(src, sender, text)
    text = tostring(text):gsub('[%c";]', ' '):sub(1, 180)
    if src == 'tell' and sender and sender ~= '' then
        windower.send_command('input /tell ' .. sender .. ' ' .. text)
    elseif src == 'party' then
        windower.send_command('input /p ' .. text)
    end
    windower.add_to_chat(167, text)
end
-- called when AA_MAIN (or aa_party.lua) fails to load; true = rolling back
function aa_start_failed(err)
    if AA_ROLLING_BACK then return true end
    local first = tostring(err):match('^[^\n]*') or tostring(err)
    windower.add_to_chat(167, '[AA] AutoAttack failed to start: ' .. tostring(err))
    local dir = windower.addon_path
    local note = AA_RELOAD_NOTE
    local f = io.open(dir .. 'data/reload_notify.txt', 'r')
    if f then
        local line = f:read('*l') or ''
        f:close()
        local a, b, c, d = line:match('^(%a+)\t([^\t]*)\t(%d+)\t?([^\t]*)')
        if a then note = {src = a, sender = b, t = tonumber(c), from = d} end
    end
    local new_ver = tostring(_addon and _addon.version or '?')
    if not (note and note.from and note.from ~= '' and note.from ~= new_ver
            and note.t and os.time() - note.t <= 600) then
        return false   -- not right after an aa update: nothing to roll back
    end
    local p = windower.ffxi.get_player()
    local me = (p and p.name) or 'AutoAttack'
    local set = aa_rollback_find(new_ver)
    local ok, why = false, 'no backup from the update found'
    if set then ok, why = aa_rollback_restore(set) end
    if not ok then
        aa_safe_say(note.src, note.sender, '[AA] ' .. me .. ': v' .. new_ver .. ' failed to start (' .. first ..
            ') and could not roll back (' .. tostring(why) .. ') -- install by hand.')
        return false
    end
    AA_ROLLING_BACK = true
    -- the restored version answers "reloaded -- AutoAttack v<old>"
    local nf = io.open(dir .. 'data/reload_notify.txt', 'w')
    if nf then nf:write(note.src, '\t', note.sender or '', '\t', tostring(os.time()), '\t\n'); nf:close() end
    aa_safe_say(note.src, note.sender, '[AA] ' .. me .. ': v' .. new_ver .. ' failed to start (' .. first ..
        ') -- rolled back to v' .. set.ver .. ', reloading.')
    local folder = dir:match('([^/\\]+)[/\\]*$') or 'autoattack'
    coroutine.schedule(function() windower.send_command('lua r ' .. folder) end, 2)
    return true
end

function AA_MAIN()   -- v4.65: the whole addon (closed at the bottom of this file)

_addon.name     = 'AutoAttack'
_addon.author   = 'Mark Williams'
_addon.version  = '5.53'
_addon.commands = {'autoattack', 'aa'}



-- v4.29: the commonly changed settings (whitelist / blacklist, Domain
-- Invasion, elemental farming, master_pull_method, ws_mode,
-- heal_buff_outside_battle, move_to_target and job_config) now live in
-- aa_config.lua next to this file. aa_config_defaults.lua is the shipped,
-- safe copy: it creates aa_config.lua on first load, fills in any setting
-- aa_config.lua is missing, and is used whole if aa_config.lua won't load.
-- Globals on purpose (main chunk / main loop are at the local/upvalue limit).
AA_CONFIG_FILE   = 'aa_config.lua'
AA_DEFAULTS_FILE = 'aa_config_defaults.lua'
-- v4.63: settings missing from aa_config.lua are filled from the defaults at
-- EVERY level (was top level only), so a new setting inside an existing
-- block (party.xyz, a job's pull.xyz ...) works after "aa update" without
-- anyone editing their file. It only ever ADDS what is missing -- never
-- changes a value the player set -- and never adds:
--   * list items (abilities / magic / item_food / cure entries -- numbered)
--   * lists (trust groups, ws_list modes, mob lists, friends ...)
--   * whole jobs under job_config (a job the player removed stays removed)
-- AA_CFG_NEW lists what was filled in; //aa config new shows it.
AA_CFG_COLLECTIONS = {job_config = true}   -- keys under these are the player's own
AA_CFG_NEW = {}
function aa_cfg_islist(t) return type(t) == 'table' and t[1] ~= nil end
function aa_cfg_copy(v)
    if type(v) ~= 'table' then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = aa_cfg_copy(x) end
    return t
end
function aa_cfg_fill(cfg, def, path, depth)
    for k, dv in pairs(def) do
        if type(k) == 'string' then
            local p = (path == '') and k or (path .. '.' .. k)
            local cv = cfg[k]
            if cv == nil then
                if depth == 0 or not (AA_CFG_COLLECTIONS[path] or aa_cfg_islist(dv)) then
                    cfg[k] = aa_cfg_copy(dv)
                    AA_CFG_NEW[#AA_CFG_NEW + 1] = {path = p, value = dv}
                end
            elseif type(cv) == 'table' and type(dv) == 'table' and depth < 8
                   and not aa_cfg_islist(cv) and not aa_cfg_islist(dv) then
                aa_cfg_fill(cv, dv, p, depth + 1)
            end
        end
    end
end
function aa_cfg_fmt(v)
    if type(v) == 'string' then return string.format('%q', v) end
    if type(v) ~= 'table' then return tostring(v) end
    local parts, n = {}, 0
    for k, x in pairs(v) do
        n = n + 1
        if #parts < 4 and type(x) ~= 'table' then parts[#parts + 1] = tostring(k) .. ' = ' .. aa_cfg_fmt(x) end
    end
    if n == 0 then return '{}' end
    return '{' .. table.concat(parts, ', ') .. ((n > #parts) and ((#parts > 0) and ', ...' or '...') or '') .. '}'
end
function aa_load_config()
    local dir = windower.addon_path
    local function try(name)
        local chunk, err = loadfile(dir .. name)
        if not chunk then return nil, err end
        local ok, cfg = pcall(chunk)
        if not ok then return nil, cfg end
        if type(cfg) ~= 'table' then return nil, name .. ' did not return a settings table' end
        return cfg
    end
    -- first load: make aa_config.lua from the defaults file
    if not windower.file_exists(dir .. AA_CONFIG_FILE) then
        local src = io.open(dir .. AA_DEFAULTS_FILE, 'rb')
        if src then
            local data = src:read('*a'); src:close()
            local dst = io.open(dir .. AA_CONFIG_FILE, 'wb')
            if dst then
                dst:write(data); dst:close()
                windower.add_to_chat(207, '[AA] Created ' .. AA_CONFIG_FILE .. ' from ' .. AA_DEFAULTS_FILE .. ' -- edit ' .. AA_CONFIG_FILE .. ' for your own settings.')
            end
        end
    end
    local def, derr = try(AA_DEFAULTS_FILE)
    local cfg, err  = try(AA_CONFIG_FILE)
    if not cfg then
        windower.add_to_chat(167, '[AA] Could not load ' .. AA_CONFIG_FILE .. ': ' .. tostring(err))
        if def then
            windower.add_to_chat(167, '[AA] Using ' .. AA_DEFAULTS_FILE .. ' instead. Fix ' .. AA_CONFIG_FILE .. ', then //lua r autoattack')
            return def
        end
        error('[AA] Could not load ' .. AA_DEFAULTS_FILE .. ' either: ' .. tostring(derr))
    end
    -- v4.63: a setting missing from aa_config.lua comes from the defaults, at
    -- every level (see aa_cfg_fill); one summary line instead of one per setting
    AA_CFG_NEW = {}
    if def then aa_cfg_fill(cfg, def, '', 0) end
    if #AA_CFG_NEW > 0 then
        windower.add_to_chat(207, string.format('[AA] %s: %d new setting%s using defaults -- //aa config new to see them',
            AA_CONFIG_FILE, #AA_CFG_NEW, (#AA_CFG_NEW == 1) and '' or 's'))
    end
    return cfg
end
AA_CFG = aa_load_config()

local domain_invasion          = AA_CFG.domain_invasion   or {toggle = "false", moblist = {}}
local elemental_farming        = AA_CFG.elemental_farming or {toggle = "false", moblist = {}}
local mob_whitelist            = AA_CFG.mob_whitelist     or {}
local mob_blacklist            = AA_CFG.mob_blacklist     or {}
local master_pull_method       = AA_CFG.master_pull_method or {type = ''}
local ws_mode                  = AA_CFG.ws_mode           or {type = "Normal", lockout = "true"}
local heal_buff_outside_battle = AA_CFG.heal_buff_outside_battle == true

-- v4.25: debug_level -- how much the addon logs.
--   0 = OFF      nothing but command replies and warnings.
--   1 = RELEASE  minimal, high-level: loaded, mode start/stop, PULLING /
--                ATTACKING, target switches, weapon skills, emergencies,
--                trusts, ring / food use, config problems and errors.
--                Shown as '[AA] ...'. Releases always ship with 1.
--   2 = DEV      everything: every TARGET / HOLD / MOVE / PULL-WAIT / RINGS
--                trace line, stamped '[DEBUG 23:33:41.512 +0.084]' (clock
--                time to the ms, seconds since the previous line); TIMING
--                lines for slow main-loop passes (with the stage it was in)
--                and client frame stalls; [CMD] lines and everything else go
--                to data/logs/aa_<Character>_<date>.log as well (v4.59:
--                one file per character per day).
-- //aa debug 0|1|2 (or off|release|dev) changes it for this session.
-- Globals on purpose (main loop is at the upvalue limit).
debug_level       = 1
DEBUG_LOG_FILE    = false   -- level 2: also write every line to data/logs/aa_<Character>_<date>.log (//aa debug file on|off)
DEBUG_SLOW_TICK   = 3.0    -- level 2: TIMING line when one main-loop pass takes longer than this (s)
DEBUG_FRAME_STALL = 0.5    -- level 2: TIMING line when the client goes this long between frames (s)

-- v4.29: move_to_target ('off' | 'pull' | 'provoke' | 'melee' | 'target' |
-- <yalms>) and job_config are set in aa_config.lua (see the loader above).
-- //aa move off|pull|provoke|melee|target|<yalms> changes it for the session.
-- Global on purpose (main loop is at the upvalue limit).
move_to_target = AA_CFG.move_to_target
if move_to_target == nil then move_to_target = 'off' end

local job_config = AA_CFG.job_config or {}

-- Build a lowercase set for O(1) lookup. Empty whitelist = pull everything.
-- If domain_invasion.toggle or elemental_farming.toggle is "true", those moblists
-- override mob_whitelist. Both can be active at once; their lists are merged.
local mob_whitelist_set = {}
local _di_on  = domain_invasion    and domain_invasion.toggle    == "true"
local _ef_on  = elemental_farming  and elemental_farming.toggle  == "true"
if _di_on or _ef_on then
    if _di_on then
        for _, name in ipairs(domain_invasion.moblist)   do mob_whitelist_set[name:lower()] = true end
    end
    if _ef_on then
        for _, name in ipairs(elemental_farming.moblist) do mob_whitelist_set[name:lower()] = true end
    end
else
    for _, name in ipairs(mob_whitelist) do mob_whitelist_set[name:lower()] = true end
end
local function is_mob_whitelisted(mob_name)
    if not mob_name then return false end
    if next(mob_whitelist_set) == nil then return true end  -- empty list = allow all
    return mob_whitelist_set[mob_name:lower()] == true
end

-- v3.04: User-managed permanent name blacklist (set at top of file; script never modifies).
-- Mobs listed here are skipped by ALL scan paths regardless of whitelist.
-- v3.86: Entries may also be numeric mob IDs (stored in mob_blacklist_ids).
local mob_blacklist_set = {}
local mob_blacklist_ids = {}
for _, entry in ipairs(mob_blacklist) do
    if type(entry) == 'number' then
        mob_blacklist_ids[entry] = true
    elseif type(entry) == 'string' then
        local _n = tonumber(entry)  -- also accept "17584150" written as a string
        if _n then mob_blacklist_ids[_n] = true
        else mob_blacklist_set[entry:lower()] = true end
    end
end
local function is_mob_name_blacklisted(mob_name, mob_id)
    if mob_id and mob_blacklist_ids[mob_id] then return true end
    if not mob_name then return false end
    return mob_blacklist_set[mob_name:lower()] == true
end

-- v2.94: State tables for cant-see blacklist (must be before helper functions)
local cant_target_counts = {} -- [mob_id] = {count, first_time}: consecutive cant-see hits
local cant_target_ids   = {} -- [mob_id] = expiry_clock: mobs auto-blocked (cant-see / stale-pull)

-- v2.94: Out-of-sight / elevation constants (must be before helper functions)
local CANT_SEE_LIMIT         = 3    -- blacklist after this many cant-see hits on same mob
local CANT_SEE_WINDOW        = 8    -- seconds: reset hit counter if no cant-see in this window
local CANT_SEE_BLACKLIST_DUR = 10   -- seconds to blacklist a persistently-unreachable mob
-- v3.26: Pull-LOS detection — "Unable to see" (geometry) vs "You cannot see" (facing).
-- When script fires //facing f then pulls and still gets "Unable to see", it's a wall.
-- Blacklist that mob for 30s immediately (single hit, no CANT_SEE_LIMIT counter needed).
local last_pull_next_mob_id   = nil  -- mob ID of the most recent confirmed PullNext pull
local last_pull_next_mob_time = 0    -- os.clock() when pull was fired (after //facing f)
local PULL_LOS_WINDOW         = 5.0  -- seconds after pull to accept "Unable to see" as LOS
local PULL_LOS_BLACKLIST_DUR  = 30.0 -- seconds to skip a geometry-blocked pull mob
-- v3.83: Escalating unreachable-mob blacklist. Each time the same mob is blacklisted
-- as unreachable (cant-see counter or stuck watchdog) the skip gets longer, and from
-- the 2nd strike on it is NOT lifted early just because the mob is hitting you.
local CANT_SEE_ESCALATION = {10, 30, 120, 300} -- skip seconds for strike 1, 2, 3, 4+
local cant_see_strikes    = {}   -- [mob_id] = times this mob was blacklisted as unreachable
cant_see_strike_time  = {}        -- v4.18: [mob_id] = os.clock() of the last strike (global: local limit)
CANT_SEE_STRIKE_DECAY = 900       -- v4.18: strikes older than this (s) are forgotten
-- v3.83: Stuck-engage watchdog (PULL mode). Engaged, mob in melee range, and no
-- melee round / WS / ranged attack / offensive spell from you for STUCK_TIMEOUT
-- seconds = the game won't let you hit it. Disengage and blacklist it.
local STUCK_TIMEOUT       = 30
local STUCK_SKIP_BUFFS    = {[2]=true, [7]=true, [10]=true, [19]=true, [28]=true} -- sleep, petrify, stun, sleep II, terror
local last_offense_time   = 0    -- os.clock() of your last melee/WS/ranged/offensive spell action
local stuck_watch_id      = 0    -- mob ID the watchdog is timing
local stuck_watch_start   = 0    -- os.clock() when timing started for stuck_watch_id
-- v3.83: Low-HP stop. If your HP% is at or below LOW_HP_STOP_PCT and has not gone up
-- (no cure/regen/drain) for LOW_HP_NO_HEAL_SECS, stop AutoAttack and warn loudly.
local LOW_HP_STOP         = true
local LOW_HP_STOP_PCT     = 25
local LOW_HP_NO_HEAL_SECS = 30
local low_hp_last_hp      = 0
local low_hp_last_rise    = 0

-- v3.83: Blacklist a mob as unreachable with an escalating duration.
-- Returns (duration_seconds, strike_number).
local function blacklist_unreachable(mob_id)
    if not mob_id then return 0, 0 end
    -- v4.18: strikes decay. Escha mobs respawn with the same ID, so without this
    -- a mob that was unreachable once kept its strikes for the whole session.
    local _last = cant_see_strike_time[mob_id]
    if _last and (os.clock() - _last) > CANT_SEE_STRIKE_DECAY then cant_see_strikes[mob_id] = nil end
    cant_see_strike_time[mob_id] = os.clock()
    local n = (cant_see_strikes[mob_id] or 0) + 1
    cant_see_strikes[mob_id] = n
    local dur = CANT_SEE_ESCALATION[math.min(n, #CANT_SEE_ESCALATION)]
    cant_target_ids[mob_id] = os.clock() + dur
    cant_target_counts[mob_id] = nil
    return dur, n
end
-- v2.96: Stale pull detection — if the same mob is picked by the scan N times in X seconds
-- without engaging (status never advances to 1), feed it into cant_target_ids.
local STALE_PULL_LIMIT  = 3   -- selections before blacklisting
local STALE_PULL_WINDOW = 12  -- seconds for the selection window
local REPULL_LIMIT      = 3   -- re-pulls without mob reaching melee range before giving up

-- v2.94: Returns true if this mob ID is currently blacklisted from repeated cant-see.
-- Expired entries are cleaned up on first access.
local function is_cant_target_blocked(mob_id)
    if not mob_id then return false end
    local expiry = cant_target_ids[mob_id]
    if not expiry then return false end
    if os.clock() >= expiry then
        cant_target_ids[mob_id] = nil
        cant_target_counts[mob_id] = nil
        return false
    end
    return true
end
-- v5.48: seconds left on a mob's temporary block (0 = not blocked); for ENGAGE-STUCK
function aa_mob_blocked(mob_id)
    local e = mob_id and cant_target_ids[mob_id]
    if type(e) ~= 'number' then return 0 end
    return math.max(0, e - os.clock())
end
-- v5.00: leave a mob alone for secs (scans skip it, set_target refuses it).
-- Global so the main loop can call it without another upvalue.
function aa_block_mob(mob_id, secs, why)
    if not mob_id then return end
    -- v5.47: counted for PARTY-STATS; an aa fight member never blocks the leader's
    -- mob (11-23: Myth stood idle ~20s -- TARGET_GIVEUP_SECS -- on every other bat)
    if PSTAT then PSTAT.tgu = (PSTAT.tgu or 0) + 1 end
    if aa_lead_mob_is and aa_lead_mob_is(mob_id) then
        if PSTAT then PSTAT.tgl = (PSTAT.tgl or 0) + 1 end
        if NATIVE_GIVEUP then NATIVE_GIVEUP[mob_id] = nil end
        cant_target_ids[mob_id] = nil
        local lm = windower.ffxi.get_mob_by_id(mob_id)
        info_msg('TARGET-GIVEUP not done: ' .. tostring(lm and lm.name or '?') .. ' (' .. tostring(mob_id) ..
                 ') is the leader\'s mob -- ' .. tostring(why) .. '; trying again.')
        return
    end
    cant_target_ids[mob_id] = os.clock() + (secs or 20)
    local m = windower.ffxi.get_mob_by_id(mob_id)
    info_msg('TARGET-GIVEUP ' .. tostring(m and m.name or '?') .. ' (' .. tostring(mob_id) .. '): ' ..
             tostring(why) .. ' -- skipping it for ' .. math.floor(secs or 20) .. 's.')
end

-- v3.98: Drop expired cant-see blacklist entries and stale hit counters
-- (counters for mobs that never reached CANT_SEE_LIMIT were never removed).
-- Called between fights. Global on purpose: main loop is at the upvalue limit.
function prune_blacklists()
    local now = os.clock()
    for id, exp in pairs(cant_target_ids) do
        if type(exp) ~= 'number' or now >= exp then cant_target_ids[id] = nil end
    end
    if pull_in_nolift then  -- v3.99
        for id, exp in pairs(pull_in_nolift) do
            if type(exp) ~= 'number' or now >= exp then pull_in_nolift[id] = nil end
        end
    end
    for id, rec in pairs(cant_target_counts) do
        if not cant_target_ids[id]
           and (type(rec) ~= 'table' or (now - (rec.first_time or 0)) > CANT_SEE_WINDOW) then
            cant_target_counts[id] = nil
        end
    end
    -- v4.18: decayed unreachable strikes (see CANT_SEE_STRIKE_DECAY)
    for id, t in pairs(cant_see_strike_time) do
        if type(t) ~= 'number' or (now - t) > CANT_SEE_STRIKE_DECAY then
            cant_see_strike_time[id] = nil
            cant_see_strikes[id] = nil
        end
    end
    -- v4.18: mob_hits had one entry per actor (every mob, Trust, player and pet
    -- that ever swung or cast near you) and was never cleared.
    if mob_hits then
        for id, h in pairs(mob_hits) do
            if type(h) ~= 'table' or (now - (h.t or 0)) > (MOB_HIT_WINDOW or 10) then mob_hits[id] = nil end
        end
    end
    if ds_prune then ds_prune() end  -- v4.32: Dread Spikes records with no news for forget_after
end

-- Purple-escape exclusion list: mobs on this list will NOT trigger the
-- "claimed by another party" disengage check. Add any open-world shared
-- mobs here (Domain Invasion monsters, NMs, battlefields, etc.) so the
-- script keeps fighting them even when another group's claim_id shows up.
local purple_escape_exclusions = {
    -- Domain Invasion monsters
    "Volatile Anubian",
    "Volatile Flayer",
    "Volatile Twitherym",
    "Volatile Craklaw",
    "Volatile Myrmeleo",
    "Volatile Jagil",
    "Volatile Corse",
    -- Add NM or event mob names here as needed:
    "Tiamat",
    "Cerberus",
	"Azi Dahaka",
	"Naga Raja",
	"Quetzalcoatl",
	"Mireu",
	"Colkhab",
	"Tchakka",
	"Achuka",
	"Yumcax",
	"Hurkan",
	"Kumhau",
	"Azi Dahaka's Dragon",
	"Naga Raja's Lamia",
	"Quetzalcoatl's Sibilus",
}
local purple_escape_exclusion_set = {}
for _, name in ipairs(purple_escape_exclusions) do
    purple_escape_exclusion_set[name:lower()] = true
end
local function is_purple_excluded(mob_name)
    if not mob_name then return false end
    return purple_escape_exclusion_set[mob_name:lower()] == true
end



-- Zone IDs that restrict trusts.
-- = 0  : trusts completely disallowed (towns, BCNMs, instanced areas)
-- = 3  : trusts limited to 3 (Apollyon, Dynamis, etc.)
-- Zone IDs sourced from res/zones.lua; trust availability inferred from can_pet flag.
local restricted_trust_zones = {
    -- ── Limbus ──────────────────────────────────────────────────────────────
    [37]  = 3,  -- Temenos
    [38]  = 3,  -- Apollyon
    -- ── Dynamis (classic) ───────────────────────────────────────────────────
    [39]  = 3,  -- Dynamis - Valkurm
    [40]  = 3,  -- Dynamis - Buburimu
    [41]  = 3,  -- Dynamis - Qufim
    [42]  = 3,  -- Dynamis - Tavnazia
    [134] = 3,  -- Dynamis - Beaucedine
    [135] = 3,  -- Dynamis - Xarcabard
    [185] = 3,  -- Dynamis - San d'Oria
    [186] = 3,  -- Dynamis - Bastok
    [187] = 3,  -- Dynamis - Windurst
    [188] = 3,  -- Dynamis - Jeuno
    -- ── BCNMs / instanced battlefields ──────────────────────────────────────
    [78]  = 0,  -- Hazhalm Testing Grounds
    [86]  = 0,  -- Everbloom Hollow
    [93]  = 0,  -- Ruhotz Silvermines
    [129] = 0,  -- Ghoyu's Reverie
    [139] = 0,  -- Horlais Peak
    [144] = 0,  -- Waughroon Shrine
    [146] = 0,  -- Balga's Dais
    [163] = 0,  -- Sacrificial Chamber
    [165] = 0,  -- Throne Room
    [168] = 0,  -- Chamber of Oracles
    [170] = 0,  -- Full Moon Fountain
    [179] = 0,  -- Stellar Fulcrum
    [180] = 0,  -- La'Loff Amphitheater
    [181] = 0,  -- The Celestial Nexus
    [206] = 0,  -- Qu'Bia Arena
    -- ── Three Nations ────────────────────────────────────────────────────────
    [230] = 0,  -- Southern San d'Oria
    [231] = 0,  -- Northern San d'Oria
    [232] = 0,  -- Port San d'Oria
    [233] = 0,  -- Chateau d'Oraguille
    [234] = 0,  -- Bastok Mines
    [235] = 0,  -- Bastok Markets
    [236] = 0,  -- Port Bastok
    [237] = 0,  -- Metalworks
    [238] = 0,  -- Windurst Waters
    [239] = 0,  -- Windurst Walls
    [240] = 0,  -- Port Windurst
    [241] = 0,  -- Windurst Woods
    [242] = 0,  -- Heavens Tower
    -- ── Jeuno ────────────────────────────────────────────────────────────────
    [243] = 0,  -- Ru'Lude Gardens
    [244] = 0,  -- Upper Jeuno
    [245] = 0,  -- Lower Jeuno
    [246] = 0,  -- Port Jeuno
    -- ── Outposts & smaller towns ─────────────────────────────────────────────
    [247] = 0,  -- Rabao
    [248] = 0,  -- Selbina
    [249] = 0,  -- Mhaura
    [250] = 0,  -- Kazham
    [251] = 0,  -- Hall of the Gods
    [252] = 0,  -- Norg
    -- ── Aht Urhgan ───────────────────────────────────────────────────────────
    [50]  = 0,  -- Aht Urhgan Whitegate
    [53]  = 0,  -- Nashmau
    -- ── Adoulin ──────────────────────────────────────────────────────────────
    [256] = 0,  -- Western Adoulin
    [257] = 0,  -- Eastern Adoulin
    [281] = 0,  -- Leafallia
    [282] = 0,  -- Mount Kamihr
    [283] = 0,  -- Silver Knife
    [284] = 0,  -- Celennia Memorial Library
    [285] = 0,  -- Feretory
    -- ── Other non-combat / special areas ─────────────────────────────────────
    [26]  = 0,  -- Tavnazian Safehold
    [70]  = 0,  -- Chocobo Circuit
    [71]  = 0,  -- The Colosseum
    [131] = 0,  -- Mordion Gaol
    [280] = 0,  -- Mog Garden
    -- ── Airships (transit zones) ──────────────────────────────────────────────
    [223] = 0,  -- San d'Oria-Jeuno Airship
    [224] = 0,  -- Bastok-Jeuno Airship
    [225] = 0,  -- Windurst-Jeuno Airship
    [226] = 0,  -- Kazham-Jeuno Airship
}




-- SC Elements: Direct ID-to-element map based on known Windower skillchain animation IDs:
local sc_id_to_element = {
    [1]  = 'light',      -- Light
    [2]  = 'dark',   -- Darkness  
    [3]  = 'fire',       -- Liquefaction
    [4]  = 'earth',      -- Scission
    [5]  = 'water',      -- Reverberation
    [6]  = 'wind',       -- Detonation
    [7]  = 'lightning',  -- Impaction
    [8]  = 'light',      -- Transfixion
    [9]  = 'dark',       -- Compression
    [10] = 'light',      -- Fusion
    [11] = 'ice',        -- Distortion
    [12] = 'lightning',  -- Fragmentation
    [13] = 'earth',      -- Gravitation
    [14] = 'light',      -- Radiance
    [15] = 'dark',       -- Umbra
}




local mob_weaknesses = {
    -- ICE
    ['Apex Crab']        = 'ice',   -- Outer Ra'Kaznar, Reisenjima
    ['Crab']             = 'ice',   -- Various zones
    ['Snipper']          = 'ice',   -- Various zones
    ['Robber Crab']      = 'ice',   -- Various zones
    ['Land Crab']        = 'ice',   -- Various zones
    ['Pugil']            = 'ice',   -- Various zones
    ['Bastore Bream']    = 'ice',   -- Batallia Downs, etc
    ['Orobon']           = 'ice',   -- Various coastal zones

    -- FIRE
    ['Apex Bat']         = 'fire',  -- Various caves
    ['Bat']              = 'fire',  -- Various zones
    ['Bat Eye']          = 'fire',  -- Various zones
    ['Fly']              = 'fire',  -- Various zones
    ['Gnat']             = 'fire',  -- Various zones
    ['Chigoe']           = 'fire',  -- Various zones
    ['Leech']            = 'fire',  -- Various zones
    ['Slug']             = 'fire',  -- Various zones
    ['Worm']             = 'fire',  -- Various zones
    ['Crawler']          = 'fire',  -- Various zones
    ['Caterpillar']      = 'fire',  -- Various zones

    -- LIGHTNING
    ['Apex Rabbit']      = 'lightning',  -- Various zones
    ['Rabbit']           = 'lightning',  -- Various zones
    ['Hare']             = 'lightning',  -- Various zones
    ['Sheep']            = 'lightning',  -- Various zones
    ['Coeurl']           = 'lightning',  -- Various zones
    ['Lynx']             = 'lightning',  -- Various zones
    ['Tiger']            = 'lightning',  -- Various zones
    ['Dhalmel']          = 'lightning',  -- Various zones
    ['Goobbue']          = 'lightning',  -- Various zones

    -- EARTH
    ['Golem']            = 'earth',  -- Various zones
    ['Elemental']        = 'earth',  -- Various zones (varies by element)
    ['Funguar']          = 'earth',  -- Various zones
    ['Morbol']           = 'earth',  -- Various zones
    ['Treant']           = 'earth',  -- Various zones
    ['Antica']           = 'earth',  -- Quicksand Caves, etc

    -- WIND
    ['Bird']             = 'wind',   -- Various zones
    ['Cockatrice']       = 'wind',   -- Various zones
    ['Roc']              = 'wind',   -- Various zones
    ['Hippogryph']       = 'wind',   -- Various zones
    ['Valkurm Emperor']  = 'wind',   -- Valkurm Dunes
    ['Bee']              = 'wind',   -- Various zones
    ['Wasp']             = 'wind',   -- Various zones
    ['Weapon']           = 'wind',   -- Various zones (animated weapons)

    -- WATER
    ['Lizard']           = 'water',  -- Various zones
    ['Raptor']           = 'water',  -- Various zones
    ['Adamantoise']      = 'water',  -- Various zones
    ['Toucan']           = 'water',  -- Various zones
    ['Sabotender']       = 'water',  -- Various zones
    ['Cactuar']          = 'water',  -- Various zones
    ['Apex Sapling']     = 'water',  -- Outer Ra'Kaznar
    ['Sapling']          = 'water',  -- Various zones

	-- LIGHT
	['Skeleton']         = 'light',  -- Various zones
	['Zombie']           = 'light',  -- Various zones
	['Ghost']            = 'light',  -- Various zones
	['Lich']             = 'light',  -- Various zones
	['Wight']            = 'light',  -- Various zones
	['Revenant']         = 'light',  -- Various zones
	['Specter']          = 'light',  -- Various zones
	['Troll']            = 'light',  -- Various zones
	['Lamia']            = 'light',  -- Various zones
	['Undead']           = 'light',  -- Various zones

	-- DARK
	['Slime']            = 'dark',   -- Various zones
	['Ooze']             = 'dark',   -- Various zones
	['Flan']             = 'dark',   -- Various zones
	['Amoeba']           = 'dark',   -- Various zones
	['Hecteyes']         = 'dark',   -- Various zones
	['Leech']            = 'dark',   -- Various zones (also fire)
	['Dvergr']           = 'dark',   -- Various zones	
}



-- Ninja tool table: spell name -> { tool, toolbag }
local ninja_tools = {
    -- Elemental Ichi (Inoshishinofuda)
    ['Katon: Ichi']    = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Hyoton: Ichi']   = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Raiton: Ichi']   = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Doton: Ichi']    = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Huton: Ichi']    = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Suiton: Ichi']   = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    -- Elemental Ni (Inoshishinofuda)
    ['Katon: Ni']      = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Hyoton: Ni']     = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Raiton: Ni']     = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Doton: Ni']      = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Huton: Ni']      = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Suiton: Ni']     = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    -- Elemental San (Inoshishinofuda)
    ['Katon: San']     = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Hyoton: San']    = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Raiton: San']    = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Doton: San']     = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Huton: San']     = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    ['Suiton: San']    = { tool = 'Inoshishinofuda', toolbag = 'Toolbag (Ino)' },
    -- Buff spells (confirmed from game logs)
    ['Utsusemi: Ichi'] = { tool = 'Shihei',      toolbag = 'Toolbag (Shihe)' },  -- v3.15: Ichi/Ni use Shihei
    ['Utsusemi: Ni']   = { tool = 'Shihei',      toolbag = 'Toolbag (Shihe)' },  -- v3.15: Ichi/Ni use Shihei
    ['Utsusemi: San']  = { tool = 'Shikanofuda', toolbag = 'Toolbag (Shika)' },   -- v3.15: San uses Shikanofuda
    ['Monomi: Ichi']   = { tool = 'Shikanofuda', toolbag = 'Toolbag (Shika)' },
    ['Migawari: Ichi'] = { tool = 'Shikanofuda', toolbag = 'Toolbag (Shika)' },
    -- Debuff spells (Chonofuda)
    ['Kurayami: Ichi'] = { tool = 'Chonofuda', toolbag = 'Toolbag (Cho)' },
    ['Kurayami: Ni']   = { tool = 'Chonofuda', toolbag = 'Toolbag (Cho)' },
    ['Yurin: Ichi']    = { tool = 'Chonofuda', toolbag = 'Toolbag (Cho)' },
    ['Dokumori: Ichi'] = { tool = 'Chonofuda', toolbag = 'Toolbag (Cho)' },
    ['Jubaku: Ichi']   = { tool = 'Chonofuda', toolbag = 'Toolbag (Cho)' },
    ['Hojo: Ichi']     = { tool = 'Chonofuda', toolbag = 'Toolbag (Cho)' },
    ['Aisha: Ichi']    = { tool = 'Chonofuda', toolbag = 'Toolbag (Cho)' },
}


-- At the top of the file with other locals
local skillchain_element = nil
local skillchain_time = nil
local low_hp_pull_done = false  -- tracks whether we've already pulled the next mob during low-HP phase
local low_hp_skip_logged = false  -- suppresses repeat low-HP skip debug_msg spam; reset whenever low_hp_pull_done resets
local last_pull_next_time = 0   -- timestamp of last PullNext_OnLowHP pull; suppresses cascade pulls on freshly-damaged mobs
-- v4.76: PullNext log -- one line per current mob and reason (the scan line
-- used to print every tick and hid every skip reason)
LHP_SAID = {id = 0}
function lhp_note(id, key, msg)
    if LHP_SAID.id ~= id then LHP_SAID = {id = id} end
    if LHP_SAID[key] == msg then return end
    LHP_SAID[key] = msg
    if aa_dbg then aa_dbg(msg) end   -- debug_msg is declared further down
end
local PULL_NEXT_COOLDOWN = 5.0 -- seconds after a PullNext pull before another is allowed (prevents cascade pulls)
local skip_combat_this_tick = false  -- NOTE: shadowed by a local re-declaration inside status==1 block; per-tick flag lives there
local ws_sc_locked = false  -- true after a WS with LockOut=1 fires; blocks all non-WS actions until a WS with LockOut=0 fires
local ws_index = 1             -- moved here from below use_weapon_skill to guarantee initialization order
local current_ws_use_count = 0 -- moved here from below use_weapon_skill to guarantee initialization order
local last_ws_time = 0         -- moved here from below use_weapon_skill to guarantee initialization order
local ws_mode_last_type = nil  -- tracks last ws_mode.type; resets ws_index when type changes
local ws_cmd_off = false        -- v4.33: //aa ws off -- no WS until //aa ws on or a reload
local cant_see_flag = false    -- set true by incoming chunk 0x017 when game prints 'Unable to see'
local last_ability_time = 0    -- tracks when the last job ability fired, for ring equip lockout
local food_last_used_time = {} -- in-memory backup for food min_time; settings.item_timers can be 0 after reload
local SC_WINDOW = 3  -- seconds the MB window is open




-- Current active settings pointer
local current_config = nil 
local script_name = 'autoattack'
local auto_attack = false
local cmd_mode = false  -- set to true to log [CMD] lines to chat for troubleshooting
local ws_blocked_debug = false  -- set to true to show 'WS BLOCKED: needs X TP' messages
-- v4.62: dev = {...} in aa_config.lua overrides debug_level, DEBUG_LOG_FILE,
-- cmd_mode and ws_blocked_debug, so "aa update" (which replaces this file
-- with the release copy) never resets your own debug settings.
do
    local dv = type(AA_CFG) == 'table' and type(AA_CFG.dev) == 'table' and AA_CFG.dev or {}
    if dv.debug_level ~= nil then debug_level = tonumber(dv.debug_level) or debug_level end
    if dv.debug_log_file ~= nil then DEBUG_LOG_FILE = (dv.debug_log_file == true) end
    if dv.cmd_mode ~= nil then cmd_mode = (dv.cmd_mode == true) end
    if dv.ws_blocked_debug ~= nil then ws_blocked_debug = (dv.ws_blocked_debug == true) end
end
local res = require('resources')
-- v3.98: cached resource lookups. res.<table>:with() is a full linear scan of the
-- resource table (res.items is ~28k entries) and was being run every combat tick
-- for every ring / spell / ability entry. Resources never change at runtime.
local _res_cache = {}
-- v4.74: never a Lua error. 2026-11-18 (ASUS, v4.73): "autoattack.lua:768
-- attempt to call method 'with' (a nil value)" -- a resource table that
-- can't be searched (the item list failed to load and the slim item proxy
-- handed back an empty table). Items by name now go through aa_item_named();
-- any other table without :with logs once and returns nil (not cached, so
-- it is tried again later).
res_with_warned = {}
local function res_with(tbl_name, field, value)
    if value == nil then return nil end
    local key = tbl_name .. '|' .. field .. '|' .. tostring(value)
    local hit = _res_cache[key]
    if hit ~= nil then return hit or nil end
    local found
    if tbl_name == 'items' and (field == 'english' or field == 'en' or field == 'name') then
        found = aa_item_named(value)
        if found == nil and aa_items_failed then return nil end   -- list didn't load: try again later
    else
        local tbl = res[tbl_name]
        local f = type(tbl) == 'table' and tbl.with or nil
        if type(f) ~= 'function' then
            if not res_with_warned[tbl_name] then
                res_with_warned[tbl_name] = true
                if info_msg then info_msg('RES: res.' .. tostring(tbl_name) .. ' could not be searched (' ..
                    tostring(field) .. ' = ' .. tostring(value) .. ') -- skipped, will try again.') end
            end
            return nil
        end
        found = f(tbl, field, value)
    end
    _res_cache[key] = found or false
    return found
end
-- v4.61: SLIM ITEM LOOKUPS. res.items (the game's ~23,500-item list) is about
-- 20 MB of Lua memory once loaded, and Windower keeps it until the addon
-- unloads. AutoAttack only needs a handful of items, so res.items is replaced
-- by a small proxy: res.items[id] / res.items:with(...) -- here, in
-- aa_party.lua and in Windower's extdata lib (ring charges) -- go through
-- aa_item(), which keeps only the entries looked up. On a miss the full list
-- is loaded, the entry kept, and the list released again ITEMS_KEEP_SECS
-- after its last use (prerender). Globals on purpose (main chunk is at the
-- local / upvalue limit).
ITEMS_KEEP_SECS    = 10
aa_item_cache      = {}    -- [id] = res entry | false (no such item)
aa_item_name_cache = {}    -- [lowercase english name] = res entry | false
aa_items_real      = nil   -- the full res.items while it is loaded
aa_items_failed    = false -- v4.74: the last load failed
aa_items_retry_at  = 0     -- v4.74: no new load before this os.clock()
ITEMS_RETRY_SECS   = 120
aa_items_loaded_at = nil   -- os.clock() of the last use of the full list
aa_items_loads     = 0     -- times the full list was loaded (HEARTBEAT line)
function aa_items_full(why)
    if not aa_items_real then
        -- v4.74: after a failed load wait ITEMS_RETRY_SECS before trying 20 MB again
        -- (ASUS 11-18 16:29: "not enough memory" every 1-2s)
        if aa_items_failed and os.clock() < aa_items_retry_at then return {} end
        local t0 = os.clock()
        rawset(res, 'items', nil)
        local ok, full = pcall(function() return res.items end)   -- Windower loads res/items.lua
        rawset(res, 'items', aa_items_proxy)
        if not ok or type(full) ~= 'table' or type(full.with) ~= 'function' then
            aa_items_failed = true   -- v4.74: misses aren't cached while the list is down
            aa_items_retry_at = os.clock() + ITEMS_RETRY_SECS
            if aa_log then aa_log(1, 'ITEMS: could not load the item list: ' .. tostring(ok and type(full) or full) ..
                ' -- next try in ' .. ITEMS_RETRY_SECS .. 's (rings / food wait; restarting the game client frees memory).') end
            return {}
        end
        aa_items_failed = false
        aa_items_real = full
        aa_items_loads = aa_items_loads + 1
        if aa_log then aa_log(2, string.format('ITEMS: full item list loaded (%s) in %.2fs', tostring(why), os.clock() - t0)) end
    end
    aa_items_loaded_at = os.clock()
    return aa_items_real
end
function aa_item(id)
    id = tonumber(id)
    if not id then return nil end
    local hit = aa_item_cache[id]
    if hit ~= nil then return hit or nil end
    local it = aa_items_full('item ' .. id)[id]
    if it == nil and aa_items_failed then return nil end   -- v4.74
    aa_item_cache[id] = it or false
    return it
end
-- English name, any capitalization (an exact match wins)
function aa_item_named(name)
    if type(name) ~= 'string' or name == '' then return nil end
    local key = name:lower()
    local hit = aa_item_name_cache[key]
    if hit ~= nil then return hit or nil end
    local found = nil
    for _, it in pairs(aa_items_full('"' .. name .. '"')) do
        if type(it) == 'table' and type(it.en) == 'string' and it.en:lower() == key then
            found = it
            if it.en == name then break end
        end
    end
    if found == nil and aa_items_failed then return nil end   -- v4.74: list didn't load
    aa_item_name_cache[key] = found or false
    if found and found.id then aa_item_cache[found.id] = found end
    return found
end
aa_items_proxy = setmetatable({}, {__index = function(_, k)
    if type(k) == 'number' then return aa_item(k) end
    local v = aa_items_full('res.items.' .. tostring(k))[k]
    if v == nil and type(k) == 'string' and type(table[k]) == 'function' then
        return function() return nil end   -- v4.74: item list didn't load -- no Lua error
    end
    if type(v) == 'function' then   -- res.items:with(...) and the other table methods
        return function(self, ...)
            if self == aa_items_proxy then self = aa_items_full() end
            return v(self, ...)
        end
    end
    return v
end})
function aa_items_release()
    local full = aa_items_real
    aa_items_real, aa_items_loaded_at = nil, nil
    if not full then return end
    -- keep what is in the inventory now (tools, food, oils, ammo ...) so the
    -- next checks don't load the list again
    local inv = windower.ffxi.get_items(0)
    if type(inv) == 'table' then
        for _, sl in pairs(inv) do
            if type(sl) == 'table' and sl.id and sl.id > 0 and aa_item_cache[sl.id] == nil then
                aa_item_cache[sl.id] = full[sl.id] or false
            end
        end
    end
    full = nil
    collectgarbage('collect')
    if aa_log then aa_log(2, string.format('ITEMS: full item list released -- AA lua now %.0f KB', collectgarbage('count'))) end
end
do
    local already = rawget(res, 'items')   -- loaded before this point by a library
    if already then aa_items_real, aa_items_loaded_at = already, os.clock() end
    rawset(res, 'items', aa_items_proxy)
end
-- v4.61: fetch only the bags asked for (get_items() with no argument builds
-- every bag -- safe, storage, locker, satchel, sack, case, 8 wardrobes ...)
AA_BAG_IDS = {inventory = 0, safe = 1, storage = 2, temporary = 3, locker = 4,
              satchel = 5, sack = 6, case = 7, wardrobe = 8, safe2 = 9,
              wardrobe2 = 10, wardrobe3 = 11, wardrobe4 = 12, wardrobe5 = 13,
              wardrobe6 = 14, wardrobe7 = 15, wardrobe8 = 16}
function aa_get_bags(names)
    local t = {}
    for _, n in ipairs(names) do
        local id = AA_BAG_IDS[n]
        if id then t[n] = windower.ffxi.get_items(id) end
    end
    return t
end
AA_RING_BAGS = {'inventory', 'wardrobe', 'wardrobe2', 'wardrobe3', 'wardrobe4',
                'wardrobe5', 'wardrobe6', 'wardrobe7', 'wardrobe8'}
-- v4.61: collect garbage sooner (default pause 200 = wait until memory has
-- doubled). Lower peaks for a little more GC work.
collectgarbage('setpause', 150)
local extdata = require('extdata')
local config = require('config')
-- local packets = require('packets')
local defaults = { 
	locks = {},
	item_timers = {},
	ring_charges = {},  -- v4.05: [ring_id] = charges left after our last use
	ring_max = {},      -- v4.05: [ring_id] = most charges ever seen on that ring
	target_mode = 'packet', -- v4.07: 'packet' = injected 0x058 lock, 'native' = /targetbnpc (no injection). //aa target
	}
local settings = config.load(defaults)
local autoattack_type = 'assist'
local initial_direction = nil
local fight_subcmd = nil  --Added per Claude: "fight_subcmd is set as a global but never declared with local at the top of the file, meaning if the loop runs before a command is issued, it could be nil or an unexpected type. The and short-circuit should protect it, but declaring it explicitly at the top is safer:"

local magic_use_tracker = {}
local ability_use_tracker = {}
-- v3.94: pet state. tp / hpp / target_id come from the 0x067/0x068 pet status
-- packets; last_* are the pet_logic() retry timers.
local pet_state = {tp = 0, hpp = 0, target_id = 0, time = 0,
                   last_summon = 0, last_engage = 0, last_retreat = 0}
local item_mob_use_count = {} 

local ability_last_used = {}
local magic_last_used = {}

local weakness_spell_index = {}  -- keyed by element, tracks position in the list

local last_target_id = 0
-- v2.96: Stale pull state — tracks if the same mob keeps being selected without engaging
local stale_pull_id    = 0
local whitelist_cursor_id = 0  -- last mob ID set as the out-of-range whitelist cursor target;
                                -- avoids re-setting settarget every tick on the same mob so
                                -- the player can manually target other things while running.
local stale_pull_count = 0
local stale_pull_time  = 0
local repull_count     = 0   -- consecutive re-pulls on the same mob without melee contact
local purple_limbo_until = 0  -- os.clock() deadline; while active, hold /attack off and skip combat chain
local purple_from_packet = false  -- set true by 0x017 "already claimed" message; triggers escape on next tick

-- Sync existing locks from settings into your ring_locks table on load
local ring_locks = settings.locks
local last_operation = 'none'

local last_weakness_cast_time = 0
local last_ring_fallback_time = 0  -- declared for compatibility; no longer used since v2.47 removed the default ring fallback
local last_trust_check_time = 0    -- rate-limits call_trusts to once every 10s instead of every tick
-- v4.34: a Trust still missing after TRUST_MAX_FAILS calls in a row is skipped
-- for TRUST_FAIL_SKIP seconds (2026-11-13: Shantotto II called 5x in 7 min).
local TRUST_MAX_FAILS = 3
local TRUST_FAIL_SKIP = 600
local trust_fails   = {}   -- [mob key] = calls in a row that didn't stick
local trust_skip    = {}   -- [mob key] = os.time() until which it is skipped
local trust_pending = {}   -- [mob key] = cast name, called at the last check
local WEAKNESS_GLOBAL_LOCKOUT = 6  -- seconds between any weakness spell casts




-- v4.25: logging by level (see debug_level at the top).
--   debug_msg(msg)  level 2 (DEV) detail
--   info_msg(msg)   level 1 (RELEASE) high-level event; also shown at level 2
-- Wall clock to the ms: os.time() is whole seconds, so aa_wc_* is re-anchored
-- to os.clock() each time prerender sees the second roll over (one frame of
-- error, ~16ms), and the fraction comes from os.clock().
aa_wc_wall, aa_wc_clock, aa_wc_sec = os.time(), os.clock(), 0
aa_dbg_last        = 0      -- os.clock() of the previous dev line (for +delta)
aa_dbg_file        = nil    -- open log file handle (level 2 + DEBUG_LOG_FILE)
aa_dbg_file_path   = nil
aa_dbg_file_failed = false
-- v4.59: per-character, per-day log files: data/logs/aa_<Character>_<YYYY-MM-DD>.log
-- (you play different characters on different PCs sharing one log folder).
-- aa_dbg_file_key is '<Character>_<date>' of the open file; when the
-- character (login/logout) or the date (midnight) changes, the file is
-- closed and the right one opened. Before a character is loaded (title
-- screen) lines go to aa_NoChar_<date>.log.
aa_dbg_file_key    = nil
aa_log_char        = nil    -- cached character name (reset on login/logout)
function aa_log_char_name()
    if aa_log_char then return aa_log_char end
    local p = windower.ffxi.get_player()
    local n = p and p.name
    if not n or n == '' then return 'NoChar' end   -- not cached: try again next line
    aa_log_char = (n:gsub('[^%w]', ''))
    return aa_log_char
end
function aa_wall_clock(now)
    local w = aa_wc_wall + ((now or os.clock()) - aa_wc_clock)
    local sec = math.floor(w)
    return os.date('%H:%M:%S', sec) .. string.format('.%03d', math.floor((w - sec) * 1000))
end
function aa_log_close()
    if aa_dbg_file then pcall(function() aa_dbg_file:close() end) end
    aa_dbg_file = nil
end
function aa_log_file(line)
    if (debug_level or 0) < 2 or not DEBUG_LOG_FILE then return end
    local key = aa_log_char_name() .. '_' .. os.date('%Y-%m-%d')   -- v4.59
    if key ~= aa_dbg_file_key then
        aa_log_close()
        aa_dbg_file_key = key
        aa_dbg_file_failed = false   -- new file: try opening it
    end
    if aa_dbg_file_failed then return end
    if not aa_dbg_file then
        local dir = windower.addon_path .. 'data/logs/'
        if windower.dir_exists and windower.create_dir and not windower.dir_exists(dir) then
            windower.create_dir(dir)
        end
        aa_dbg_file_path = dir .. 'aa_' .. key .. '.log'   -- v4.59: aa_<Character>_<date>.log
        local f = io.open(aa_dbg_file_path, 'a')
        if not f then
            aa_dbg_file_failed = true
            windower.add_to_chat(167, '[AutoAttack] debug log file could not be opened: ' .. aa_dbg_file_path)
            return
        end
        aa_dbg_file = f
        f:write('\n==== AutoAttack v' .. _addon.version .. ' log opened ' .. os.date('%Y-%m-%d %H:%M:%S')
            .. ' (' .. aa_log_char_name() .. ') ====\n')
    end
    aa_dbg_file:write(line, '\n')
    aa_dbg_file:flush()  -- every line, so a client crash still leaves the last lines on disk
end
function aa_log(lvl, msg)
    msg = tostring(msg)
    if pstat_count_err then pcall(pstat_count_err, msg) end   -- v4.99: errors go to the party report
    local dl = debug_level or 0
    if dl < lvl then return end
    if dl >= 2 then
        local now = os.clock()
        local d = (aa_dbg_last > 0) and (now - aa_dbg_last) or 0
        aa_dbg_last = now
        local stamp = aa_wall_clock(now) .. string.format(' +%.3f', d)
        windower.add_to_chat(8, '[DEBUG ' .. stamp .. '] ' .. msg)
        aa_log_file(stamp .. ' L' .. lvl .. ' ' .. msg)
    else
        windower.add_to_chat(8, '[AA] ' .. msg)
    end
end
function info_msg(msg) aa_log(1, msg) end
local function debug_msg(msg)
    aa_log(2, msg)
end

-- v4.25: DEV timing. aa_stage(name) marks where the main loop is; at the top
-- of each pass aa_tick_check() logs 'TIMING: loop pass #n took X.XXs' when a
-- pass ran longer than DEBUG_SLOW_TICK, naming the last stage and how long
-- the pass had been in it. Level 2 only.
aa_tick_n, aa_tick_stage, aa_tick_stage_t = 0, 'start', 0
function aa_stage(name)
    if (debug_level or 0) >= 2 then aa_tick_stage = name; aa_tick_stage_t = os.clock() end
end
function aa_tick_check()
    local now  = os.clock()
    local prev = aa_loop_beat or 0
    aa_tick_n = aa_tick_n + 1
    if prev > 0 and (now - prev) > DEBUG_SLOW_TICK then
        debug_msg(string.format('TIMING: loop pass #%d took %.2fs -- last stage \'%s\' (%.2fs in it).',
            aa_tick_n - 1, now - prev, tostring(aa_tick_stage), now - (aa_tick_stage_t or now)))
    end
    aa_tick_stage, aa_tick_stage_t = 'top', now
end



-- cmd(str): logs the command string then sends it.
-- When 'Invalid argument' appears in the console, look one line above in the
-- log for '[CMD]' to see exactly which command the game rejected.
-- Chat only when cmd_mode = true. v4.25: at debug_level 2 every [CMD] line also
-- goes to the log file (with the ms clock), even with cmd_mode off.
-- v4.43: STALE-LOOP GUARD. The watchdog (or a stop + start) starts a new main
-- loop while the old one may still be alive inside a long wait; the old one
-- only noticed at the top of its next pass, so both could send commands for a
-- tick. main_logic_loop registers its coroutine with its generation; anything
-- a superseded loop tries to send (cmd, target packets, unequip packets,
-- movement) is dropped. Globals on purpose (main loop upvalue limit).
aa_loop_co     = setmetatable({}, {__mode = 'k'})   -- [coroutine] = loop generation
aa_stale_drops = 0
function aa_stale_loop()
    local co = coroutine.running()
    local g = co and aa_loop_co[co]
    return g ~= nil and g ~= aa_loop_gen
end
local function cmd(str)
    if aa_stale_loop() then   -- v4.43
        aa_stale_drops = aa_stale_drops + 1
        debug_msg('STALE-LOOP: dropped "' .. tostring(str) .. '" (old loop, superseded by a restart).')
        return
    end
    if cmd_mode then
        windower.add_to_chat(8, '[CMD] ' .. tostring(str))
    end
    if (debug_level or 0) >= 2 then aa_log_file(aa_wall_clock() .. ' CMD ' .. tostring(str)) end
    windower.send_command(str)
end

-- v3.95: built-in SetTarget. Does what Windower's SetTarget addon does (it
-- replaces every 'lua c settarget <id>' call): injects an incoming 0x058
-- (assist / target lock) packet so the client puts the cursor on that mob.
-- v3.96: hardened after the 2026-10-10 21:48:02 FFXiMain.dll access violation
-- (0xc0000005 @ 0x76a75), which hit the instant a mob died and a treasure
-- casket spawned. The client's entity table is changing at that moment, and a
-- target-lock packet pointing at a dying/despawning entity is the prime suspect.
--   * Every call logs 'TARGET-SET' (or 'TARGET-SKIP <reason>') so the last
--     targeting action before any future crash is in the log.
--   * Skips dead / untargetable / non-mob entities (fresh re-read by ID).
--   * Skips during TARGET_QUIET_WINDOW seconds after any defeat, a treasure
--     casket appearing, or a dead cursor (target_quiet_until). Callers already
--     retry on the next tick, so a skip only delays targeting by ~1s.
--   * SET_TARGET_VIA_ADDON = true routes through the SetTarget addon instead
--     (the pre-v3.95 behaviour; SetTarget must then be loaded).
-- Returns true if the target was sent.
SET_TARGET_VIA_ADDON = false
-- v4.30: packet-miss fallback. When PACKET_MISS_LIMIT target packets (0x058)
-- in a row miss the same mob (cursor still not on it at the next try), the
-- next try uses /targetbnpc (native_target: turn toward the mob, then
-- /targetbnpc) for that mob once, then goes straight back to packets.
-- 0 turns it off. Globals on purpose (main loop is at the upvalue limit).
PACKET_MISS_LIMIT = 3
pkt_miss_id       = 0   -- mob the current miss streak is on
pkt_miss_count    = 0   -- packets sent to pkt_miss_id that did not take
pkt_fallbacks     = 0   -- /targetbnpc fallbacks this session (heartbeat)
TARGET_QUIET_WINDOW  = 1.0
DEAD_CURSOR_TARGETOFF_DELAY = 3     -- v4.11
dead_cursor_pending_id = nil        -- v4.11
dead_cursor_count      = 0          -- v4.11 (heartbeat)
target_quiet_until   = 0
-- v4.11: last_kill_clock = os.clock() of the most recent defeat / casket /
-- dead cursor. Ring /item waits RING_KILL_HOLD seconds past it (2026-10-11
-- 01:03 crash: /item 3s after a kill). secs overrides TARGET_QUIET_WINDOW.
last_kill_clock      = 0
RING_KILL_HOLD       = 5
RING_HOLD_MAX        = 20   -- v4.43: longest a ring /item waits for a kill-free RING_KILL_HOLD
RING_HOLD_RETRY      = 60   -- v4.43: then skip it, re-try that ring this many seconds later
function target_quiet(reason, secs)
    secs = secs or TARGET_QUIET_WINDOW
    last_kill_clock = os.clock()
    local _until = os.clock() + secs
    if _until > target_quiet_until then target_quiet_until = _until end
    if reason then debug_msg('TARGET-QUIET ' .. string.format('%.1f', secs) .. 's: ' .. reason) end
end
-- v4.19: fast re-target after a kill. The TARGET_QUIET_WINDOW (no target
-- packet for 1s after a defeat / casket) is NOT shortened -- that's the
-- FFXiMain.dll crash guard. What changes is the dead time around it: fixed
-- sleeps that ran after the mob was already dead, and the 1s loop tick that
-- made the next scan land anywhere up to ~1s after the quiet window ended.
-- FAST_RETARGET = false restores the v4.18 timing exactly.
FAST_RETARGET    = true
FAST_KILL_WINDOW = 4.0   -- seconds after our kill that the loop ticks fast
fast_kill_until  = 0
fast_kill_id     = 0
aa_quick_next    = false -- one short (0.1s) loop tick, e.g. right after engaging
-- Called from the 0x029 defeat handler with the dead entity's ID.
function aa_kill_seen(dead_id)
    if not dead_id or dead_id == 0 then return end
    local t = windower.ffxi.get_mob_by_target('t')
    local ours = dead_id == last_target_id or (t and t.id == dead_id) or dead_id == melee_swing.id
    if ours then hot_switch_start(dead_id) end  -- v4.20
    if not FAST_RETARGET then return end
    if ours then
        fast_kill_id    = dead_id
        fast_kill_until = os.clock() + FAST_KILL_WINDOW
        debug_msg('FAST-RETARGET: our target (' .. dead_id .. ') died -- next scan as soon as the quiet window ends.')
    end
end
-- Wait until the cursor is on want_id (max max_secs). Replaces fixed 0.5s
-- "wait for target lock" sleeps: returns the moment the lock is seen.
function wait_cursor(want_id, max_secs)
    if not FAST_RETARGET or not want_id then coroutine.sleep(max_secs); return false end
    local t0 = os.clock()
    while true do
        local t = windower.ffxi.get_mob_by_target('t')
        if t and t.id == want_id then return true end
        if (os.clock() - t0) >= max_secs then return false end
        coroutine.sleep(0.05)
    end
end
-- Sleep secs, but stop early if <t> dies (e.g. the WS animation lockout
-- after a killing-blow WS -- nothing left to lock out for).
function nap_while_alive(secs)
    if not FAST_RETARGET then coroutine.sleep(secs); return end
    local t0 = windower.ffxi.get_mob_by_target('t')
    local sid = t0 and t0.id
    local c0 = os.clock()
    while (os.clock() - c0) < secs do
        coroutine.sleep(0.1)
        local t = windower.ffxi.get_mob_by_target('t')
        if not t or (sid and t.id ~= sid) or not t.hpp or t.hpp <= 0
           or (sid and sid == fast_kill_id and os.clock() < fast_kill_until) then
            debug_msg(string.format('FAST-RETARGET: target down %.1fs into a %.1fs wait -- moving on.',
                os.clock() - c0, secs))
            return
        end
    end
end
-- End-of-tick sleep for main_logic_loop (was a flat coroutine.sleep(1)).
function aa_loop_nap()
    if not FAST_RETARGET then coroutine.sleep(1); return end
    if aa_quick_next then
        aa_quick_next = false
        coroutine.sleep(0.1)
        return
    end
    local now = os.clock()
    if now < fast_kill_until then
        -- wake right as the quiet window ends (or in 0.25s if it already has)
        local s = target_quiet_until - now + 0.05
        if s < 0.25 then s = 0.25 end
        if s > 1 then s = 1 end
        coroutine.sleep(s)
        return
    end
    coroutine.sleep(1)
end
-- Turn toward a mob without targeting it (no 0x058 packet -- safe inside
-- the quiet window).
function face_mob_direct(m)
    local me = windower.ffxi.get_mob_by_target('me')
    if not me or not me.x or not m or not m.x then return false end
    windower.ffxi.turn(-math.atan2(m.y - me.y, m.x - me.x))
    return true
end
-- v4.07: native targeting -- no packet injection. Used when target_mode is
-- 'native' (//aa target native). Turns toward the mob and sends the game's own
-- /targetbnpc (target nearest enemy) until the cursor is on that mob ID, up to
-- NATIVE_TARGET_TRIES times. Runs in its own coroutine; callers already
-- re-check <t> and retry on the next tick. Test mode for the 2026-10-10/11
-- FFXiMain.dll crashes: if they stop in native mode, the 0x058 packet is it.
NATIVE_TARGET_TRIES = 4
NATIVE_TARGET_WAIT  = 0.4
native_target_busy  = false
native_target_busy_at = 0   -- v4.18: busy flag expires after NATIVE_TARGET_BUSY_MAX s
NATIVE_TARGET_BUSY_MAX = 5
-- v5.00: a mob the /targetbnpc fallback could not reach -> skipped for TARGET_GIVEUP_SECS
-- (11-21 10:53: 19s retargeting one bat while /targetbnpc kept landing on another)
NATIVE_GIVEUP      = {}
TARGET_GIVEUP_SECS = 20
-- v4.18: one /targetbnpc attempt (never yields). false = mob gone or dead, stop.
function native_target_try(want_id, want_name)
    local me = windower.ffxi.get_mob_by_target('me')
    local m  = windower.ffxi.get_mob_by_id(want_id)
    if not me or not m or not m.valid_target or not m.hpp or m.hpp <= 0 then
        debug_msg('TARGET-NATIVE-MISS ' .. want_name .. ' (' .. want_id .. '): gone or dead.')
        return false
    end
    if m.x and m.y and me.x and me.y then
        windower.ffxi.turn(-math.atan2(m.y - me.y, m.x - me.x))
    end
    cmd('input /targetbnpc')
    return true
end
function native_target(target, fallback)   -- v5.00: fallback = set_target's packet-miss fallback
    local _cur = windower.ffxi.get_mob_by_target('t')
    if _cur and _cur.id == target.id then return true end
    if native_target_busy and (os.clock() - native_target_busy_at) < NATIVE_TARGET_BUSY_MAX then
        debug_msg('TARGET-NATIVE ' .. tostring(target.name) .. ' (' .. target.id .. '): already cycling, skipped.')
        return false
    end
    native_target_busy = true
    native_target_busy_at = os.clock()
    local want_id, want_name = target.id, tostring(target.name)
    -- v4.18: coroutine.sleep() is OUTSIDE pcall now. Windower's Lua 5.1 can't
    -- yield inside pcall ("attempt to yield across metamethod/C-call boundary"),
    -- so before v4.18 native mode errored out after its first /targetbnpc.
    coroutine.schedule(function()
        local finished = false
        for i = 1, NATIVE_TARGET_TRIES do
            local ok, go = pcall(native_target_try, want_id, want_name)
            if not ok then info_msg('TARGET-NATIVE error: ' .. tostring(go)) end
            if not ok or not go then finished = true; break end
            coroutine.sleep(NATIVE_TARGET_WAIT)
            local t = windower.ffxi.get_mob_by_target('t')
            if t and t.id == want_id then
                debug_msg('TARGET-NATIVE-OK ' .. want_name .. ' (' .. want_id .. ') after ' .. i .. ' try(s).')
                finished = true
                break
            end
        end
        if not finished then
            local t = windower.ffxi.get_mob_by_target('t')
            debug_msg('TARGET-NATIVE-MISS ' .. want_name .. ' (' .. want_id .. '): cursor on ' ..
                (t and (tostring(t.name) .. ' (' .. tostring(t.id) .. ')') or 'nothing') ..
                ' after ' .. NATIVE_TARGET_TRIES .. ' tries.')
            if fallback then NATIVE_GIVEUP[want_id] = os.clock() end   -- v5.00
        end
        native_target_busy = false
    end, 0)
    return true
end
function set_target(mob_id, ignore_quiet)  -- v4.20: ignore_quiet = hot switch only
    if aa_stale_loop() then return false end  -- v4.43
    mob_id = tonumber(mob_id)
    if not mob_id or mob_id <= 0 then return false end
    local target = windower.ffxi.get_mob_by_id(mob_id)
    if not target or not target.id or not target.index or target.index == 0 then
        debug_msg('TARGET-SKIP ID ' .. mob_id .. ': entity not found.')
        return false
    end
    local _name = tostring(target.name)
    -- v3.99: never put the cursor on a mob_blacklist entry (name or ID) or a
    -- temporarily blacklisted mob, whichever path asked for it.
    if is_mob_name_blacklisted(target.name, target.id) then
        debug_msg('TARGET-SKIP ' .. _name .. ' (' .. target.id .. '): on mob_blacklist.')
        return false
    end
    if is_cant_target_blocked(target.id) then
        -- v5.47: the leader's mob (aa fight member) is never left blocked
        if aa_lead_mob_is and aa_lead_mob_is(target.id) then
            cant_target_ids[target.id] = nil
            if NATIVE_GIVEUP then NATIVE_GIVEUP[target.id] = nil end
            debug_msg('TARGET-UNBLOCK ' .. _name .. ' (' .. target.id .. '): the leader\'s mob (aa fight) -- block lifted.')
        else
            debug_msg('TARGET-SKIP ' .. _name .. ' (' .. target.id .. '): temporarily blacklisted.')
            return false
        end
    end
    -- v5.00: target packets AND the /targetbnpc fallback already failed on this mob: move on
    if not ignore_quiet and NATIVE_GIVEUP[target.id] then
        local _ga = NATIVE_GIVEUP[target.id]
        NATIVE_GIVEUP[target.id] = nil
        local _cur = windower.ffxi.get_mob_by_target('t')
        if os.clock() - _ga < 15 and not (_cur and _cur.id == target.id) then
            aa_block_mob(target.id, TARGET_GIVEUP_SECS, 'target packets and /targetbnpc both missed it')
            return false
        end
    end
    if not ignore_quiet and os.clock() < target_quiet_until then
        debug_msg('TARGET-SKIP ' .. _name .. ' (' .. target.id .. '): quiet window after kill/spawn.')
        return false
    end
    if target.spawn_type ~= 16 or not target.valid_target or not target.hpp or target.hpp <= 0
       or not target.distance or target.distance > 2500 then  -- distance is squared (50y)
        debug_msg('TARGET-SKIP ' .. _name .. ' (' .. target.id .. '): dead, untargetable or out of range.')
        return false
    end
    local player = windower.ffxi.get_player()
    if not player or not player.id or not player.index then return false end
    debug_msg('TARGET-SET ' .. _name .. ' (' .. target.id .. ', ' ..
              string.format('%.1f', target.distance:sqrt()) .. 'y, ' .. target.hpp .. '%)' ..
              (SET_TARGET_VIA_ADDON and ' via SetTarget' or '') ..
              (settings.target_mode == 'native' and ' [native]' or ''))
    if settings.target_mode == 'native' then
        return native_target(target)   -- v4.07: no packet injection
    end
    if SET_TARGET_VIA_ADDON then
        cmd('lua c settarget ' .. target.id)
        return true
    end
    -- v4.30: packet-miss fallback (see PACKET_MISS_LIMIT). Not for the hot
    -- switch (ignore_quiet): it needs the packet to stay engaged.
    if not ignore_quiet and PACKET_MISS_LIMIT and PACKET_MISS_LIMIT > 0 then
        local _cur = windower.ffxi.get_mob_by_target('t')
        if _cur and _cur.id == target.id then
            pkt_miss_id, pkt_miss_count = 0, 0
        else
            if pkt_miss_id == target.id then
                pkt_miss_count = pkt_miss_count + 1   -- last packet to this mob missed
            else
                pkt_miss_id, pkt_miss_count = target.id, 0
            end
            if pkt_miss_count >= PACKET_MISS_LIMIT then
                pkt_miss_id, pkt_miss_count = 0, 0    -- next 3 tries are packets again
                pkt_fallbacks = pkt_fallbacks + 1
                info_msg('TARGET-FALLBACK ' .. _name .. ' (' .. target.id .. '): ' .. PACKET_MISS_LIMIT ..
                         ' target packets missed -- /targetbnpc once, then back to packets.')
                return native_target(target, true)
            end
        end
    end
    local packets = require('packets')
    packets.inject(packets.new('incoming', 0x058, {
        ['Player']       = player.id,
        ['Target']       = target.id,
        ['Player Index'] = player.index,
    }))
    return true
end

-- v4.20: HOT SWITCH -- switch to the next mob the moment ours dies, while
-- still engaged, so weapons stay out. Same thing the game's own Auto-target
-- does for mobs already on you (log 10/10 21:47:48 "Auto-targeting the
-- Goblin Leecher" -- switched at the kill, stayed engaged, no crash).
--   * Only a LIVE mob within melee reach (3.0 + model_size + HOT_SWITCH_EXTRA)
--     is used; otherwise the normal re-target path runs.
--   * Mobs in our fight (on you / a party member / party-claimed) first;
--     a fresh mob only if fresh_pull_hold() allows a new pull.
--   * Cursor: one 0x058 to the NEW mob (quiet window bypassed for this call
--     only). Engagement: outgoing 0x01A category 0x0F 'Switch target', the
--     packet the client itself sends when you change targets while engaged.
--   * Nothing is ever sent at the corpse. /targetoff, rings and casket
--     handling keep their quiet windows (the 3 crashes: /targetoff on a
--     despawning corpse x2, /item 3s after a kill x1).
--   * PULL mode, packet target mode only. HOT_SWITCH = false turns it off.
HOT_SWITCH        = true
HOT_SWITCH_EXTRA  = 1.0   -- yalms past melee range a candidate may be ('melee' range)
-- v4.21: 'pull' = any mob out to your pull distance (Provoke 17.8 / ranged
-- 24.9 / Dia 20). You stay engaged and engaged_pull_logic() Provokes / pulls
-- it in, instead of sheathing and re-drawing. 'melee' = v4.20 behaviour.
HOT_SWITCH_RANGE  = 'pull'
aa_pull_dist      = 17.8  -- set by main_logic_loop each tick
HOT_SWITCH_VERIFY = 0.8   -- seconds before checking the switch took
hot_switch_until  = 0     -- main loop won't /attack off while this is open
hot_switch_dead   = 0
-- v4.24: party entity IDs (ids) and mob indexes (idx), you included.
function hs_party_sets(me)
    local party = windower.ffxi.get_party()
    local ids, idx = {[me.id] = true}, {}
    if me.index then idx[me.index] = true end
    if party then
        for key, member in pairs(party) do
            if type(key) == 'string' and type(member) == 'table' and key:match('^p[0-5]$') then
                local eid = member.mob and member.mob.id
                local ei  = member.mob_index or (member.mob and member.mob.index)
                if not eid and ei and ei > 0 then
                    local pm = windower.ffxi.get_mob_by_index(ei)
                    eid = pm and pm.id
                end
                if eid then ids[eid] = true end
                if ei and ei > 0 then idx[ei] = true end
            end
        end
    end
    return ids, idx
end
-- v4.24: a mob in our fight -- hitting you / a party member (mob_hits), claimed
-- by the party, or targeting one of you.
function hs_is_hot(m, ids, idx)
    if mob_hit_victim(m) ~= nil then return true end
    if m.claim_id and m.claim_id ~= 0 and ids[m.claim_id] then return true end
    return m.target_index and m.target_index > 0 and idx[m.target_index] or false
end
function hot_switch_pick(dead_id)
    local me = windower.ffxi.get_player()
    local mobs = windower.ffxi.get_mob_array()
    if not me or not me.id or not mobs then return nil end
    unblacklist_hitters(mobs)  -- v4.24: a blacklisted mob that is hitting you is fair game
    local ids, idx = hs_party_sets(me)
    local hot_m, hot_d, new_m, new_d = nil, math.huge, nil, math.huge
    for _, m in pairs(mobs) do
        if m and m.id ~= dead_id and m.spawn_type == 16 and m.hpp and m.hpp > 0
           and m.valid_target and m.distance and m.index
           and is_mob_whitelisted(m.name)
           and not is_mob_name_blacklisted(m.name, m.id)
           and not is_cant_target_blocked(m.id)
           and (m.claim_id == 0 or ids[m.claim_id] or is_purple_excluded(m.name)) then
            local d = m.distance:sqrt()
            local reach = 3.0 + (m.model_size or 2.0) + HOT_SWITCH_EXTRA
            if HOT_SWITCH_RANGE == 'pull' and (aa_pull_dist or 0) > reach then reach = aa_pull_dist end
            if d <= reach then
                if mob_is_ours(m, ids, idx) then   -- v4.83 (was hs_is_hot)
                    if d < hot_d then hot_m, hot_d = m, d end
                elseif d < new_d then
                    new_m, new_d = m, d
                end
            end
        end
    end
    if hot_m then return hot_m, hot_d, true end
    if new_m and not fresh_pull_hold(mobs) then return new_m, new_d, false end
    return nil
end
-- one try, never yields (runs inside pcall). Returns the mob ID sent to, or nil.
function hot_switch_send(dead_id)
    if not (HOT_SWITCH and auto_attack and autoattack_type == 'pull') then return nil end
    if settings.target_mode == 'native' then return nil end
    local p = windower.ffxi.get_player()
    if not p or p.status ~= 1 then return nil end
    local m, d, hot = hot_switch_pick(dead_id)
    if not m then
        debug_msg('HOT-SWITCH: nothing alive within ' .. (HOT_SWITCH_RANGE == 'pull' and
                  string.format('%.1fy (pull range)', aa_pull_dist or 0) or 'melee reach') .. ' -- normal re-target.')
        return nil
    end
    if not engaged_switch(m) then return nil end
    info_msg('HOT-SWITCH >>>> ' .. tostring(m.name) .. ' (' .. m.id .. ', ' ..
              string.format('%.1f', d) .. 'y, ' .. (hot and 'in our fight' or 'fresh') .. ') at kill of ' .. dead_id .. '.')
    return m.id
end
-- v5.00: one look at a hot switch in progress; true = finished (st.ok / st.why)
HOT_SWITCH_REATTACK = true
function hs_verify_step(want, st)
    local p = windower.ffxi.get_player()
    local t = windower.ffxi.get_mob_by_target('t')
    local m = windower.ffxi.get_mob_by_id(want)
    if not m or not m.hpp or m.hpp <= 0 then st.why = 'new mob gone'; return true end
    if p and p.status == 1 and t and t.id == want then st.ok = true; return true end
    if not HOT_SWITCH_REATTACK or not auto_attack then return false end
    if p and p.status == 0 and t and t.id == want and not st.attacked then
        st.attacked = os.clock() - st.t0
        cmd('input /attack on')
    elseif p and p.status == 1 and (not t or t.id ~= want) and not st.resent and os.clock() - st.t0 >= 0.35 then
        st.resent = true
        engaged_switch(m)
    end
    return false
end
function hs_verify_log(want, st)
    local p = windower.ffxi.get_player()
    local t = windower.ffxi.get_mob_by_target('t')
    local extra = (st.attacked and string.format(' (dropped out of attack -- /attack on after %.1fs)', st.attacked) or '') ..
                  (st.resent and ' (switch sent twice)' or '')
    if st.ok then
        debug_msg('HOT-SWITCH-OK: engaged on ' .. tostring(t and t.name) .. string.format(' after %.1fs', os.clock() - st.t0) .. extra .. '.')
    else
        debug_msg('HOT-SWITCH-MISS: status ' .. tostring(p and p.status) .. ', cursor ' .. tostring(t and t.id) ..
                  (st.why and (' -- ' .. st.why) or '') .. extra .. ' -- normal re-target takes over.')
    end
end
-- v4.24: switch the engaged target to m without disengaging (cursor 0x058 +
-- outgoing 0x01A 'Switch target' + turn). Live mob only, never a corpse.
function engaged_switch(m)
    if not m or not m.id or not m.index or aa_stale_loop() then return false end  -- v4.43
    if not set_target(m.id, true) then return false end
    local packets = require('packets')
    packets.inject(packets.new('outgoing', 0x01A, {
        ['Target']       = m.id,
        ['Target Index'] = m.index,
        ['Category']     = 0x0F,   -- Switch target
        ['Param']        = 0,
    }))
    face_mob_direct(m)  -- v4.21: turn now (v4.20 log: "Unable to see" right after the switch)
    return true
end
-- v4.24: CLOSER SWITCH. While engaged (PULL), every tick: if we are not
-- hitting the current target, switch to
--   (a) a mob in our fight (hitting you / a Trust, or claimed by us and
--       targeting one of you) that is CLOSER_THREAT_MARGIN+ yalms closer, or
--   (b) when the current target is still unclaimed (not pulled yet), a fresh
--       mob CLOSER_FRESH_MARGIN+ yalms closer, if fresh_pull_hold() allows.
-- Both within pull range. Kill it, then the hot switch / scan picks the next
-- closest. 10/25 23:33:41-45: hit in melee by a Limule for 12s while held on
-- one 25y away (PROVOKE-WAIT). CLOSER_SWITCH = false turns it off.
CLOSER_SWITCH          = true
CLOSER_THREAT_MARGIN   = 2.0
CLOSER_FRESH_MARGIN    = 5.0
CLOSER_SWITCH_COOLDOWN = 3.0
closer_switch_last     = 0
function closer_target_check(pull_dist)
    if not CLOSER_SWITCH or autoattack_type ~= 'pull' or settings.target_mode == 'native' then return false end
    local now = os.clock()
    if (now - closer_switch_last) < CLOSER_SWITCH_COOLDOWN or now < hot_switch_until then return false end
    local t = windower.ffxi.get_mob_by_target('t')
    if not t or not t.id or not t.hpp or t.hpp <= 0 or not t.distance then return false end
    if melee_swing.id == t.id and (now - melee_swing.time) < MELEE_HIT_WAIT then return false end  -- we're on it
    local me = windower.ffxi.get_player()
    local mobs = windower.ffxi.get_mob_array()
    if not me or not me.id or not mobs then return false end
    unblacklist_hitters(mobs)
    local ids, idx = hs_party_sets(me)
    local td = t.distance:sqrt()
    local reach = math.max(pull_dist or 0, 3.0 + (t.model_size or 2.0))
    local thr, thr_d, frs, frs_d = nil, math.huge, nil, math.huge
    for _, m in pairs(mobs) do
        if type(m) == 'table' and m.id ~= t.id and m.spawn_type == 16 and m.hpp and m.hpp > 0
           and m.valid_target and m.distance and m.index
           and is_mob_whitelisted(m.name)
           and not is_mob_name_blacklisted(m.name, m.id)
           and not is_cant_target_blocked(m.id)
           and (m.claim_id == 0 or ids[m.claim_id] or is_purple_excluded(m.name)) then
            local d = m.distance:sqrt()
            if d <= reach then
                if hs_is_hot(m, ids, idx) then
                    if d < thr_d then thr, thr_d = m, d end
                elseif m.claim_id == 0 and d < frs_d then
                    frs, frs_d = m, d
                end
            end
        end
    end
    local pick, pd, why = nil, nil, nil
    if thr and thr_d <= td - CLOSER_THREAT_MARGIN then
        pick, pd, why = thr, thr_d, (mob_hit_victim(thr) == 'me' and 'hitting you' or 'in our fight')
    elseif frs and (t.claim_id or 0) == 0 and not hs_is_hot(t, ids, idx)
           and frs_d <= td - CLOSER_FRESH_MARGIN and not fresh_pull_hold(mobs) then
        pick, pd, why = frs, frs_d, 'fresh, current not pulled yet'
    end
    if not pick then return false end
    closer_switch_last = now
    if not engaged_switch(pick) then return false end
    info_msg(string.format('CLOSER-SWITCH >>>> %s (%d, %.1fy, %s) -- leaving %s at %.1fy.',
        tostring(pick.name), pick.id, pd, why, tostring(t.name), td))
    return true
end
-- v4.70: face the hot-switched mob if it is still our live target
function hs_reface(id)
    local t = windower.ffxi.get_mob_by_target('t')
    if t and t.id == id and t.hpp and t.hpp > 0 then face_mob_direct(t) end
end
function hot_switch_start(dead_id)
    if not HOT_SWITCH or not auto_attack or autoattack_type ~= 'pull' then return end
    if dead_id == hot_switch_dead then return end   -- several defeat msgs, one switch
    hot_switch_dead  = dead_id
    hot_switch_until = os.clock() + 1.5
    coroutine.schedule(function()
        local ok, want = pcall(hot_switch_send, dead_id)
        if not ok then info_msg('HOT-SWITCH error: ' .. tostring(want)); want = nil end
        if not want then hot_switch_until = 0; return end
        -- v4.70: turn again once the switch has gone through (2026-11-18:
        -- "Unable to see" 0.5-1s after hot switches)
        coroutine.schedule(function() pcall(hs_reface, want) end, 0.4)
        coroutine.schedule(function() pcall(hs_reface, want) end, 1.0)
        if HOT_SWITCH_PROVOKE then   -- v4.40: Provoke it on the next loop tick
            hs_provoke.id = want; hs_provoke.until_t = os.clock() + HOT_SWITCH_PROVOKE_WINDOW
        end
        if HOT_SWITCH_HOLD then      -- v4.41: nothing else until our first melee round on it
            hs_hold.id = want; hs_hold.since = os.clock(); hs_hold.logged = false
        end
        -- v5.00: look every 0.1s instead of once at 0.8s. 391 of 605 switches on 11-21
        -- were "misses"; most had the cursor on the new mob but the game had dropped
        -- us out of attack -> /attack on right away. Still engaged on the corpse
        -- after 0.35s -> send the switch once more.
        local st = {t0 = os.clock()}
        while true do
            coroutine.sleep(0.1)
            local okc, done = pcall(hs_verify_step, want, st)
            if not okc then info_msg('HOT-SWITCH verify error: ' .. tostring(done)); break end
            if done then break end
            if os.clock() - st.t0 >= HOT_SWITCH_VERIFY + (st.attacked and 0.8 or 0) then break end
        end
        pcall(hs_verify_log, want, st)
        hot_switch_until = 0
    end, 0)
end

-- v4.42: DEAD-MOB GUARDS. The FFXiMain.dll crashes (10/10, 10/11) hit when a
-- command was sent at a mob that was dying / despawning. PULL got guards for
-- that in v3.96-v4.11 (quiet window, deferred /targetoff); ASSIST never did:
-- it sent /target <bt> every ~1s idle, every 1-3s engaged, and right at the
-- kill when <t> went dead -- unchecked, for hours (other characters crashing
-- in ASSIST after hours/days). These helpers put ASSIST and the last PULL
-- paths behind the same rules. Globals on purpose (main loop upvalue limit).
-- DEAD_MOB_GUARD = false restores the v4.41 behaviour.
DEAD_MOB_GUARD   = true
assist_bt_skip   = ''     -- last skip reason logged (no log spam every tick)
assist_bt_skips  = 0      -- /target <bt> skipped (heartbeat / //aa debug)
corpse_hold      = {id = 0, since = 0, logged = false}
-- /target <bt> only when <bt> is a live, targetable mob and no kill / casket
-- quiet window is open. Returns ok, sent:
--   ok   = <bt> is a live mob (cursor already on it, or the command was sent)
--   sent = /target <bt> was actually sent
function assist_target_bt(why)
    if not DEAD_MOB_GUARD then
        cmd('input /target <bt>')
        return true, true
    end
    local skip = nil
    local bt = windower.ffxi.get_mob_by_target('bt')
    if os.clock() < target_quiet_until then
        skip = 'quiet window after kill/casket'
    elseif not bt or not bt.id then
        skip = 'no battle target'
    elseif bt.spawn_type ~= 16 or not bt.valid_target or not bt.hpp or bt.hpp <= 0 then
        skip = 'battle target ' .. tostring(bt.name) .. ' (' .. tostring(bt.id) .. ') dead or untargetable'
    end
    if skip then
        assist_bt_skips = assist_bt_skips + 1
        if skip ~= assist_bt_skip then
            assist_bt_skip = skip
            debug_msg('ASSIST-BT-SKIP (' .. tostring(why) .. '): ' .. skip .. '.')
        end
        return false, false
    end
    assist_bt_skip = ''
    local t = windower.ffxi.get_mob_by_target('t')
    if t and t.id == bt.id then return true, false end  -- already on it: nothing to send
    cmd('input /target <bt>')
    return true, true
end
-- v4.50: after /target <bt>, go on as soon as the cursor is on <bt> (max 1s)
-- instead of always sleeping 1s. Function on purpose (main loop local limit).
function assist_wait_cursor()
    local bt = windower.ffxi.get_mob_by_target('bt')
    for _ = 1, 10 do
        coroutine.sleep(0.1)
        local t = windower.ffxi.get_mob_by_target('t')
        if t and bt and t.id == bt.id then return true end
    end
    return false
end
-- Right before ASSIST's /attack on: cursor still on mob_id, alive, no quiet window.
function assist_engage_ok(mob_id)
    if not DEAD_MOB_GUARD then return true end
    local t = windower.ffxi.get_mob_by_target('t')
    if os.clock() < target_quiet_until or not t or t.id ~= mob_id
       or not t.hpp or t.hpp <= 0 or not t.valid_target then
        debug_msg('ASSIST-ENGAGE-SKIP: target died or changed before /attack on.')
        return false
    end
    return true
end
-- PULL engaged-but-no-valid-target branch: true = hold /attack off + /targetoff
-- because the cursor is on a corpse (or a kill quiet window is open). The game
-- disengages on its own when the mob dies. After DEAD_CURSOR_TARGETOFF_DELAY
-- seconds on the same corpse it lets the caller send them (same as v4.11).
function corpse_hold_check(why)
    if not DEAD_MOB_GUARD then return false end
    local t = windower.ffxi.get_mob_by_target('t')
    local dead = t and t.id and (not t.hpp or t.hpp <= 0)
    local now = os.clock()
    if not dead and now >= target_quiet_until then corpse_hold.id = 0; return false end
    local key = dead and t.id or -1
    if corpse_hold.id ~= key then
        corpse_hold.id, corpse_hold.since, corpse_hold.logged = key, now, false
    end
    if (now - corpse_hold.since) < DEAD_CURSOR_TARGETOFF_DELAY then
        if not corpse_hold.logged then
            corpse_hold.logged = true
            debug_msg('CORPSE-HOLD (' .. tostring(why) .. '): ' ..
                (dead and ('cursor on dead ' .. tostring(t.name) .. ' (' .. t.id .. ')') or 'quiet window after kill/casket') ..
                ' -- no /attack off or /targetoff for up to ' .. DEAD_CURSOR_TARGETOFF_DELAY .. 's.')
        end
        return true
    end
    return false
end
-- /targetoff for a cursor known to be on a corpse: wait DEAD_CURSOR_TARGETOFF_DELAY,
-- then only if the cursor is STILL on that same dead ID (the v4.11 dead-cursor rule).
function deferred_targetoff(dead_id, why)
    if not DEAD_MOB_GUARD then cmd('input /targetoff'); return end
    if not dead_id or dead_id == 0 or dead_cursor_pending_id == dead_id then return end
    dead_cursor_pending_id = dead_id
    dead_cursor_count = (dead_cursor_count or 0) + 1
    debug_msg('Dead cursor (ID ' .. dead_id .. ', ' .. tostring(why) .. '): /targetoff deferred ' ..
        DEAD_CURSOR_TARGETOFF_DELAY .. 's.')
    target_quiet(nil, DEAD_CURSOR_TARGETOFF_DELAY + 0.5)
    coroutine.schedule(function()
        local ok_d, err_d = pcall(function()
            local t = windower.ffxi.get_mob_by_target('t')
            if t and t.id == dead_id then
                debug_msg('TARGETOFF dead cursor ' .. dead_id .. ' (still on cursor after ' ..
                    DEAD_CURSOR_TARGETOFF_DELAY .. 's).')
                cmd('input /targetoff')
            else
                debug_msg('TARGETOFF skipped: dead cursor ' .. dead_id .. ' already cleared.')
            end
        end)
        if dead_cursor_pending_id == dead_id then dead_cursor_pending_id = nil end
        if not ok_d then info_msg('TARGETOFF error: ' .. tostring(err_d)) end
    end, DEAD_CURSOR_TARGETOFF_DELAY)
end

-- v3.84: Built-in facing. Replaces every '//facing ...' command so the separate
-- Facing addon is no longer required (2026-10-09 death: Facing wasn't loaded, so
-- every //facing f silently did nothing). Same math as Facing v0.3.1:
-- FFXI heading 0 = east, pi/2 = south, pi = west, 3pi/2 = north.
--   face('f')                   turn toward <st> (if open) or <t>
--   face('left') / face('right') turn 45 degrees
--   face('n'|'ne'|'e'|'se'|'s'|'sw'|'w'|'nw') or the full word ('north', ...)
-- Returns true if a turn was sent.
local FACE_STEP = math.pi / 4
local FACE_DIRECTIONS = {
    e = 0,                   east = 0,
    se = math.pi / 4,        southeast = math.pi / 4,
    s = math.pi / 2,         south = math.pi / 2,
    sw = 3 * math.pi / 4,    southwest = 3 * math.pi / 4,
    w = math.pi,             west = math.pi,
    nw = 5 * math.pi / 4,    northwest = 5 * math.pi / 4,
    n = 3 * math.pi / 2,     north = 3 * math.pi / 2,
    ne = 7 * math.pi / 4,    northeast = 7 * math.pi / 4,
}
-- Global (not local) on purpose: the main loop is at Lua 5.1's 60-upvalue limit.
function face(dir)
    dir = dir and tostring(dir):lower() or 'f'
    local me = windower.ffxi.get_mob_by_target('me')
    if not me or not me.x or not me.y then return false end
    local angle
    if dir == 'f' then
        local t = windower.ffxi.get_mob_by_target('st') or windower.ffxi.get_mob_by_target('t')
        if not t or t.id == me.id or not t.x or not t.y then return false end
        angle = -math.atan2(t.y - me.y, t.x - me.x)
    elseif dir == 'left' then
        angle = (me.facing or 0) - FACE_STEP
    elseif dir == 'right' then
        angle = (me.facing or 0) + FACE_STEP
    elseif FACE_DIRECTIONS[dir] then
        angle = FACE_DIRECTIONS[dir]
    else
        return false
    end
    if cmd_mode then
        windower.add_to_chat(8, '[CMD] face ' .. dir .. string.format(' (%.2f rad)', angle))
    end
    windower.ffxi.turn(angle)
    return true
end



local FACE_JA_LOCKOUT   = 4.0   -- don't face within this many seconds of a job ability
local FACE_COMBAT_RATE = 3.0   -- face every N seconds during combat
local last_face_combat_time = 0
local assist_face_burst_until = 0  -- v3.25: clock() deadline for 1s/tick facing burst on new engage

-- face_combat(): fires //facing f every FACE_COMBAT_RATE seconds while engaged.
-- Guards (checked AFTER run_combat_chain so timestamps are already updated):
--   1. Rate limit: FACE_COMBAT_RATE (3s)
--   2. JA lockout: FACE_JA_LOCKOUT (2s) -- face+JA same tick -> invalid arg
--   3. Target must be alive -- avoids nil/invalid arg on dead mob
-- NO WS lockout: face_combat() runs AFTER run_combat_chain() so last_ws_time
-- is already updated before this runs -- same-tick collision is impossible by
-- ordering alone. The WS lockout was causing death: SC chain fires every ~4s,
-- WS lockout (2s) + rate limit (3s) = 5s minimum gap needed, but WSs arrive
-- every 3-4s -> face was permanently starved for the entire SC chain duration.
-- Log confirmed: 35s death window, 8 WSs, 13 'Unable to see', zero //facing f.
-- No angle check. Called AFTER run_combat_chain() each tick.
local function face_combat()
    local now = os.clock()
    if (now - last_face_combat_time) < FACE_COMBAT_RATE then return end
    if (now - last_ability_time) < FACE_JA_LOCKOUT then return end
    local t = windower.ffxi.get_mob_by_target('t')
    if not t or not t.hpp or t.hpp <= 0 then return end
    face('f')
    last_face_combat_time = now
end


-- facing_emergency(): unconditional //facing f, bypasses all rate limits,
-- WS lockout, and JA lockout. Called when the game explicitly says 'Unable to see'.
local function facing_emergency()
    local t = windower.ffxi.get_mob_by_target('t')
    if not t or not t.hpp or t.hpp <= 0 then return end
    face('f')
    debug_msg('CANT SEE: emergency face')
end








local info = windower.ffxi.get_info()
-- debug_msg('Current zone ID: ' .. tostring(info and info.zone or 'nil'))



-- v3.98: Main-loop generation token + watchdog heartbeat (globals on purpose:
-- the main loop is at Lua 5.1's 60-upvalue limit).
--   aa_loop_gen   bumped on every start; an older loop still sleeping inside
--                 coroutine.sleep() exits at its next check instead of running
--                 alongside the new one (stop + quick restart = two loops).
--   aa_loop_beat  os.clock() stamped every loop iteration. If it goes silent for
--                 AA_WATCHDOG_STALL seconds while auto_attack is on, the loop
--                 died (a Lua error kills the coroutine but leaves auto_attack
--                 true, so //aa pull said "Already running" until a reload).
aa_loop_gen       = 0
aa_loop_beat      = 0
AA_WATCHDOG_STALL = 120   -- seconds; longest legit tick is ~30-40s (trust calls)
aa_wd_restarts    = {}    -- os.clock() of recent watchdog restarts
aa_wd_next        = 0
function start_main_loop()
    -- v4.43: a loop that died (Lua error) mid-move left auto-run on, and the
    -- watchdog restart never turned it off. Always stop running first.
    pcall(windower.ffxi.run, false)
    if type(mv) == 'table' then mv.active = false end
    if type(step_home) == 'table' then step_home.active = false end
    aa_loop_gen  = aa_loop_gen + 1
    aa_loop_beat = os.clock()
    local gen = aa_loop_gen
    coroutine.schedule(function() main_logic_loop(gen) end, 0)
end

function toggle_auto_attack()
    if auto_attack then
        if (os.clock() - (aa_loop_beat or 0)) < AA_WATCHDOG_STALL then
            info_msg('Already running in ' .. autoattack_type .. ' mode — ignoring start command.')
            return
        end
        -- v3.98: the flag is on but the loop is dead -- start a fresh one
        windower.add_to_chat(167, '[AutoAttack] Previous loop is not responding -- starting a fresh one.')
    end
    auto_attack = true
    -- v3.83: fresh low-HP-stop and stuck-watchdog timers on every start
    low_hp_last_rise = os.clock(); low_hp_last_hp = 0
    low_hp_below_since = 0; low_hp_emerg_done = false   -- v4.12
    stuck_watch_id = 0; stuck_watch_start = os.clock()
    local _mode_label = autoattack_type:upper() .. ' mode'
    if autoattack_type == 'pull' then
        local _di = domain_invasion   and domain_invasion.toggle   == "true"
        local _ef = elemental_farming and elemental_farming.toggle == "true"
        if _di and _ef then
            _mode_label = _mode_label .. ': DI Farming + Elemental Farming'
        elseif _di then
            _mode_label = _mode_label .. ': DI Farming'
        elseif _ef then
            _mode_label = _mode_label .. ': Elemental Farming'
        elseif next(mob_whitelist_set) ~= nil then
            -- Normal whitelist active: list the mob names from mob_whitelist
            local _names = {}
            for _, _n in ipairs(mob_whitelist) do _names[#_names+1] = _n end
            _mode_label = _mode_label .. ': Hunting ' .. table.concat(_names, ', ')
        end
    end
    info_msg('Auto-attack loop starting: ' .. _mode_label .. '.')
    start_main_loop()  -- v3.98: generation-tagged start
end



function table.contains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end



function update_job_configs()
    local player = windower.ffxi.get_player()
    if not player then return end
    
    local main_job = player.main_job
    if not main_job then return end  -- v4.18: still loading in (login / zoning)
    if job_config[main_job] then
        current_config = job_config[main_job]
        info_msg("Settings loaded for: " .. main_job)
        -- Reset all per-fight state when job changes
        ws_index = 1
        current_ws_use_count = 0
        ws_sc_locked = false
        ability_use_tracker = {}
        ability_last_used = {}
        magic_use_tracker = {}
        magic_last_used = {}
        pet_state.last_summon = 0; pet_state.last_engage = 0; pet_state.last_retreat = 0  -- v3.94
    else
        info_msg("No config found for " .. main_job .. ". Defaulting to WAR.")
        current_config = job_config['WAR']
    end
end



function get_max_trusts()
    local info = windower.ffxi.get_info()
    if not info then return 5 end
    local zone_id = info.zone
    if not zone_id then return 5 end
    return restricted_trust_zones[zone_id] or 5
end
-- =========================================================================
-- v4.54: FULL PARTY RULE. In PULL mode no NEW mob is pulled while the party
-- is short of Trusts (job max_trusts, the zone limit, 6 per party). Mobs that
-- are already fighting you / the party (hitting, claimed by, or targeting one
-- of you) are still fought. Off: party.full_party_pull = false in
-- aa_config.lua, or //aa fullparty off for the session.
-- GHOST SLOT: a disconnected player can leave a slot the party list doesn't
-- show -- the party reads 4/6 or 5/6 but the game says the maximum Trusts are
-- out. Only /retr all and calling the Trusts again fixes it. Triggered by that
-- game line, or by FP_STALL_SECS of Trust calls that all failed (none joined).
-- =========================================================================
FULL_PARTY_PULL = not (type(AA_CFG) == 'table' and type(AA_CFG.party) == 'table'
                       and AA_CFG.party.full_party_pull == false)
FP_REFIX_WINDOW = 600   -- s: "max" again this soon after a /retr all fix = no retry
FP_STALL_SECS   = 60    -- s of failed Trust calls (none joined) before the fix
FP_STALL_FAILS  = 3     -- failed calls needed for the stall fix
FP_TEXT_SECS    = 10    -- v4.55: s after our Trust call that "party is full" counts

-- v4.55: true = a chat line AutoAttack printed itself (never a game message)
function aa_own_line(t)
    t = t:gsub('^%s+', '')
    return t:sub(1, 7) == '[DEBUG ' or t:sub(1, 4) == '[AA]' or t:sub(1, 5) == '[CMD]'
        or t:sub(1, 12) == '[AutoAttack]' or t:find('TRUST TEXT:', 1, true) ~= nil
end
fp = {log = 0, since = 0, fails = 0, joins = 0, ghost = false, ghost_line = '',
      fix_at = -1e9, fix_zone = nil, stuck_zone = nil, blocked_id = 0,
      cast_at = -1e9}  -- v4.55: os.clock() of our last Trust /ma

function fp_zone()
    local info = windower.ffxi.get_info()
    return info and info.zone
end

-- full?, Trusts in, Trusts wanted, members in the party
function full_party_state()
    local tc = current_config and current_config.trusts
    if not tc or not tc.enabled then return true, 0, 0, 0 end
    local party = windower.ffxi.get_party()
    if not party then return true, 0, 0, 0 end
    local total, n = 0, 0
    for i = 0, 5 do
        local m = party['p' .. i]
        if m and m.name then
            total = total + 1
            local mob = m.mob
            if mob and (mob.is_npc == true or (mob.id or 0) >= 0x1000000) then n = n + 1 end
        end
    end
    local want = math.min(tc.max_trusts or 5, get_max_trusts(), 6 - math.max(1, total - n))
    if want < 0 then want = 0 end
    return (total >= 6 or n >= want), n, want, total
end

-- true = no new pull (PULL mode and the party is not full). Level-1 line every 10s.
function full_party_hold()
    if not FULL_PARTY_PULL or autoattack_type ~= 'pull' then return false end
    local full, n, want, total = full_party_state()
    if full then fp.since = 0; return false end
    local now = os.clock()
    if fp.since == 0 then fp.since = now; fp.fails = 0; fp.joins = 0 end
    if now - fp.log >= 10 then
        fp.log = now
        local why = ' -- calling Trusts'
        local hold = aa_trust_hold and aa_trust_hold() or 0
        if hold > 0 then
            why = string.format(' -- a player joined, Trusts in %ds', math.ceil(hold))
        elseif fp.stuck_zone and fp.stuck_zone == fp_zone() then
            why = ' -- /retr all did not fix it: remove the disconnected member, or //aa fullparty off'
        end
        info_msg(string.format('PULL HOLD: party not full (%d/%d Trusts, %d/6 in party)%s. No new pulls.',
                 n, want, total, why))
    end
    return true
end

-- false = this target must not be pulled now (party not full and the mob is
-- not already fighting the party).
function fp_pull_ok(t)
    if not t or not full_party_hold() then return true end
    local me = windower.ffxi.get_player()
    if not me or not me.id then return false end
    local ids, idx = hs_party_sets(me)
    if hs_is_hot(t, ids, idx) then return true end
    if fp.blocked_id ~= t.id then
        fp.blocked_id = t.id
        debug_msg('PULL HOLD: ' .. (t.name or '?') .. ' (ID ' .. tostring(t.id) ..
                  ') is not fighting the party -- not pulling it until the party is full.')
    end
    return false
end

function ghost_fix_reason()
    if fp.ghost then return 'game says the maximum Trusts are out' end
    if fp.since > 0 and fp.fails >= FP_STALL_FAILS and fp.joins == 0
       and os.clock() - fp.since >= FP_STALL_SECS then
        -- not when we simply can't cast (silence 6, mute 29, mounted 252)
        local p = windower.ffxi.get_player()
        for _, b in ipairs((p and p.buffs) or {}) do
            if b == 6 or b == 29 or b == 252 then return nil end
        end
        return fp.fails .. ' Trust calls failed in ' .. math.floor(os.clock() - fp.since) .. 's, none joined'
    end
    return nil
end

-- Runs from call_trusts() (idle, leader). true = it acted this tick.
function ghost_fix(player)
    local why = ghost_fix_reason()
    if not why then return false end
    local full, n, want, total = full_party_state()
    if full then fp.ghost = false; return false end
    local mobs = windower.ffxi.get_mob_array()   -- never while a mob is on the party
    if mobs and player and player.id then
        local ids, idx = hs_party_sets(player)
        for _, m in pairs(mobs) do
            if type(m) == 'table' and m.spawn_type == 16 and m.hpp and m.hpp > 0
               and m.valid_target and hs_is_hot(m, ids, idx) then
                return false
            end
        end
    end
    fp.ghost = false
    local z = fp_zone()
    if (os.clock() - fp.fix_at) < FP_REFIX_WINDOW and fp.fix_zone == z then
        if fp.stuck_zone ~= z then
            fp.stuck_zone = z
            info_msg('TRUSTS: ' .. why .. ' again after /retr all (' .. n .. '/' .. want .. ' Trusts, ' ..
                     total .. '/6) -- not retrying for ' .. math.floor(FP_REFIX_WINDOW / 60) ..
                     ' min. Remove the disconnected member, or //aa fullparty off.')
        end
        fp.since = os.clock(); fp.fails = 0; fp.joins = 0
        return false
    end
    fp.fix_at, fp.fix_zone, fp.stuck_zone = os.clock(), z, nil
    info_msg('TRUSTS: ghost slot? ' .. why .. ' with ' .. n .. '/' .. want .. ' Trusts, ' .. total ..
             '/6 in party -- /retr all, then calling Trusts again.')
    cmd('input /retr all')
    local t0 = os.clock()
    repeat
        coroutine.sleep(0.5)
        local _, n2 = full_party_state()
    until n2 == 0 or os.clock() - t0 > 15
    coroutine.sleep(3)
    trust_fails = {}; trust_skip = {}; trust_pending = {}
    fp.since = os.clock(); fp.fails = 0; fp.joins = 0
    last_trust_check_time = 0
    return true
end

function call_trusts()
    local trust_config = current_config.trusts
    if not trust_config then return end
    if not trust_config.enabled then return end

    -- v2.57: Removed early-return for ASSIST mode. The leader check below
    -- (is_leader) is the correct guard -- it already blocks trust-calling when
    -- the player is not party leader, which is the actual risk in ASSIST mode.
    -- If the player IS the party leader in ASSIST mode, trusts should be called
    -- exactly as in PULL mode. The in-combat guard (player.status == 1) still
    -- prevents trust-casting mid-fight regardless of mode.

    -- Rate-limit: only run the full trust check once every 10 seconds.
    -- call_trusts is invoked every loop tick (1s) so this avoids hammering
    -- get_party/get_spell_recasts on every tick while idle between fights.
    local now_t = os.time()
    if (now_t - last_trust_check_time) < 10 then return end
    last_trust_check_time = now_t

    local party = windower.ffxi.get_party()
    local player = windower.ffxi.get_player()

    if not party then return end
    if not player then return end

    -- Guard in-combat BEFORE the leader check so a mid-fight leader promotion
    -- never reaches the trust casting loop.
    if player.status == 1 then return end

    -- Leader Check: p0 is always the local player.
    -- Allow summoning if: (a) p0.is_leader is true, OR (b) no real players in p1-p5 (solo/trust-only).
    local has_real_party_member = false
    for i = 1, 5 do
        local m = party['p' .. i]
        if m and m.name and m.zone then
            has_real_party_member = true
            break
        end
    end
    local is_leader = (party.p0 and party.p0.is_leader == true) or (not has_real_party_member)

    if not is_leader then return end

    -- v3.00: Re-verify after potential leader-change race condition
    if not (party.p0 and party.p0.is_leader == true) and has_real_party_member then
        debug_msg('TRUSTS: leader status changed mid-check, skipping.')
        return
    end

    -- v4.46: the game blocks Trust magic for 120s after a player joins the
    -- party. Calls made then all fail and put every Trust on the 10-minute
    -- skip list (2026-11-16 22:16 invite: pulled with no Trusts). Wait it out.
    local _hold = aa_trust_hold and aa_trust_hold() or 0
    if _hold > 0 then
        info_msg(string.format('TRUSTS: a player joined the party -- no Trusts for %ds more.', math.ceil(_hold)))  -- v4.49: level 1, every 10s
        return
    end

    if ghost_fix(player) then return end  -- v4.54: ghost slot -> /retr all + call again

    -- Get the correct trust group.
    -- domain_invasion.toggle == "true" overrides to 'dragon' group regardless of job default.
    local group_name
    if domain_invasion and domain_invasion.toggle == "true" then
        group_name = 'dragons'
    else
        group_name = trust_config.trust_group or 'hastecap'
    end
    local trust_list = trust_config[group_name]
    if not trust_list or #trust_list == 0 then
        info_msg('TRUSTS: No trust list found for group: ' .. group_name)
        return
    end

    local zone_limit = get_max_trusts()
	local config_limit = trust_config.max_trusts or 5
	local max_trusts = math.min(zone_limit, config_limit)

    -- Build current party names
    local current_party_names = {}
    local total_count = 0

    for i = 0, 5 do
        local member = party['p' .. i]
        if member and member.name then
            total_count = total_count + 1
            current_party_names[member.name:lower():gsub('[%s%p]', '')] = true
        end
    end

    -- v4.34: did the Trusts we called last time stick?
    for key, cast in pairs(trust_pending) do
        if current_party_names[key] then
            trust_fails[key] = nil
            fp.joins = fp.joins + 1  -- v4.54
        else
            fp.fails = fp.fails + 1  -- v4.54
            trust_fails[key] = (trust_fails[key] or 0) + 1
            if trust_fails[key] >= TRUST_MAX_FAILS then
                trust_skip[key] = now_t + TRUST_FAIL_SKIP
                trust_fails[key] = nil
                info_msg('TRUSTS: ' .. cast .. ' still not in the party after ' .. TRUST_MAX_FAILS ..
                         ' calls -- skipping it for ' .. math.floor(TRUST_FAIL_SKIP / 60) .. ' min.')
            end
        end
    end
    trust_pending = {}
    for key in pairs(current_party_names) do trust_fails[key] = nil end

    -- v4.44: max_trusts counts Trusts only (was party members - 1, which
    -- undercounted with other players in the party); a party holds 6 in all.
    local trust_n = 0
    for i = 0, 5 do
        local member = party['p' .. i]
        local mob = member and member.mob
        if mob and (mob.is_npc == true or (mob.id or 0) >= 0x1000000) then trust_n = trust_n + 1 end
    end

    -- Already at max trusts
    if trust_n >= max_trusts or total_count >= 6 then
        return
    end

    -- Summoning loop
    debug_msg('TRUSTS: Checking group \'' .. group_name .. '\' (' .. trust_n .. '/' .. max_trusts .. ' trusts, ' .. total_count .. '/6 in party)')

    for _, trust in ipairs(trust_list) do
        if trust_n >= max_trusts or total_count >= 6 then break end

        local mob_id = (trust.mob or ''):lower():gsub('[%s%p]', '')

        if not current_party_names[mob_id] and (trust_skip[mob_id] or 0) > now_t then
            debug_msg('TRUSTS: ' .. trust.cast .. ' skipped (failed ' .. TRUST_MAX_FAILS ..
                      'x) for ' .. (trust_skip[mob_id] - now_t) .. 's more.')
        elseif not current_party_names[mob_id] then
            local spell_data = res_with('spells', 'english', trust.cast)
            if not spell_data or not spell_data.id then
                info_msg('TRUSTS: Spell not found in resources: ' .. tostring(trust.cast))
            else
                local spell_recasts = windower.ffxi.get_spell_recasts()
                if not spell_recasts then return end

                if (spell_recasts[spell_data.id] or -1) == 0 then
                    info_msg('TRUSTS: Calling ' .. tostring(trust.cast))
                    cmd('input /ma "' .. tostring(trust.cast) .. '" <me>')
                    fp.cast_at = os.clock()  -- v4.55
                    trust_pending[mob_id] = tostring(trust.cast)  -- v4.34
                    coroutine.sleep(6)
                    total_count = total_count + 1
                    trust_n = trust_n + 1  -- v4.44
                else
                    debug_msg('TRUSTS: ' .. trust.cast .. ' is on cooldown, skipping.')
                end
            end
        else
            -- debug_msg('TRUSTS: ' .. trust.cast .. ' already in party.')
        end
    end
end




function heal_party(outside_battle)
    -- v3.44: Config-driven. Requires current_config.cure table with enabled flag and
    -- spell entries: {name='Cure IV', hpp_threshold=40, min_mp=88}
    -- Spells are tried in listed order; first qualifying spell is cast.
    -- v3.69: outside_battle=true overrides hp thresholds to 100 so any member
    -- below full HP triggers a heal (proactive top-off between pulls).
    if not current_config or not current_config.cure then return false end
    if current_config.cure.enabled == false then return false end

    local player = windower.ffxi.get_player()
    if not player or not player.vitals then return false end

    local spells = windower.ffxi.get_spells()
    if not spells then return false end

    local party = windower.ffxi.get_party()
    if not party then return false end

    local recasts = windower.ffxi.get_spell_recasts()
    if not recasts then return false end

    -- Find the party member with the lowest HP%
    local lowest_hpp = 100
    local target_name = nil

    for i = 0, 5 do
        local member = party['p' .. i]
        if member and member.hpp and member.hpp > 0 and member.hpp < lowest_hpp then
            lowest_hpp = member.hpp
            target_name = member.name
        end
    end

    if not target_name then return false end

    -- Iterate cure entries in priority order; cast first qualifying spell
    for _, entry in ipairs(current_config.cure) do
        if not entry or not entry.name then break end
        local spell_data = res_with('spells', 'english', entry.name)
        if spell_data then
            local sid       = spell_data.id
            -- Outside battle: use 100 as threshold so any member below full HP triggers
            -- a heal. In battle: respect the configured per-entry threshold.
            local hp_thresh = outside_battle and 100 or (entry.hpp_threshold or 75)
            local mp_req    = entry.min_mp or 0
            if lowest_hpp < hp_thresh
               and (player.vitals.mp or 0) >= mp_req
               and spells[sid]
               and (recasts[sid] or 1) == 0 then
                debug_msg('PARTY HEAL: ' .. entry.name .. ' on ' .. target_name ..
                    ' (hpp=' .. lowest_hpp .. '%)')
                cmd('input /ma "' .. entry.name .. '" "' .. tostring(target_name) .. '"')
                coroutine.sleep(4)
                return true
            end
        end
    end

    return false
end





-- =========================================================================
-- v3.94: PET SUPPORT (DRG / BST / SMN / PUP)
-- =========================================================================

-- Count how many copies of a buff are up (PUP maneuvers stack up to 3).
function count_buffs(buffs, buff_id)
    local n = 0
    if not buffs then return 0 end
    for _, b in ipairs(buffs) do
        if b == buff_id then n = n + 1 end
    end
    return n
end

-- The live pet mob, or nil if no pet / pet is dead.
function get_live_pet()
    local pet = windower.ffxi.get_mob_by_target('pet')
    if pet and pet.hpp and pet.hpp > 0 then return pet end
    -- v4.13: fallback through your own entity's pet_index -- the <pet> target
    -- can come back empty while the wyvern is out (06:06 death: Spirit Surge and
    -- Restoring Breath, the two pet=true emergency entries, never fired).
    local me = windower.ffxi.get_mob_by_target('me')
    if me and me.pet_index and me.pet_index > 0 then
        pet = windower.ffxi.get_mob_by_index(me.pet_index)
        if pet and pet.hpp and pet.hpp > 0 then return pet end
    end
    return nil
end

-- Command prefix for a JA/pet command/Ready move/Blood Pact: '/pet' when the
-- resource says so (pet commands), else '/ja'.
function ja_prefix(ability_data)
    if ability_data and ability_data.prefix == '/pet' then return '/pet' end
    return '/ja'
end

-- Pet / player condition fields on an `abilities` entry (see the PET JOBS
-- notes above job_config['DRG']). Returns true when every field present passes.
function pet_entry_ok(entry, player)
    if not entry or not player then return false end
    local v = player.vitals or {}

    -- Player-side limits (work on any job)
    if entry.tp_max    and (v.tp  or 0)   > entry.tp_max    then return false end
    if entry.hpp_above and (v.hpp or 0)   < entry.hpp_above then return false end
    if entry.hpp_below and (v.hpp or 100) >= entry.hpp_below then return false end
    if entry.mpp_above and (v.mpp or 0)   < entry.mpp_above then return false end

    local needs_pet = entry.pet == true or entry.pet_name or entry.pet_hpp_below
        or entry.pet_hpp_above or entry.pet_tp_min or entry.pet_engaged ~= nil
    if entry.pet == nil and not needs_pet then return true end

    local pet = get_live_pet()
    if entry.pet == false then return pet == nil end
    if not pet then return false end

    if entry.pet_name and not tostring(pet.name or ''):lower():find(entry.pet_name:lower(), 1, true) then
        return false
    end
    if entry.pet_hpp_below and pet.hpp >= entry.pet_hpp_below then return false end
    if entry.pet_hpp_above and pet.hpp <  entry.pet_hpp_above then return false end
    if entry.pet_tp_min    and (pet_state.tp or 0) < entry.pet_tp_min then return false end
    if entry.pet_engaged ~= nil and ((pet.status == 1) ~= entry.pet_engaged) then return false end
    return true
end

-- True when `name` (JA / pet command or spell) can be used right now.
-- Returns ok, command_prefix.
function pet_action_ready(name, player)
    if not name or not player then return false end
    local ja = res_with('job_abilities', 'name', name)
    if ja then
        local ab = windower.ffxi.get_abilities()
        if not ab or not ab.job_abilities or not table.contains(ab.job_abilities, ja.id) then return false end
        local rc = windower.ffxi.get_ability_recasts()
        if not rc or ja.recast_id == nil or (rc[ja.recast_id] or -1) ~= 0 then return false end
        return true, ja_prefix(ja)
    end
    local sp = res_with('spells', 'name', name)
    if sp then
        local known = windower.ffxi.get_spells()
        if not known or not known[sp.id] then return false end
        local rc = windower.ffxi.get_spell_recasts()
        if not rc or (rc[sp.recast_id] or -1) ~= 0 then return false end
        if player.vitals and (player.vitals.mp or 0) < (sp.mp_cost or 0) then return false end
        return true, '/ma'
    end
    return false
end

-- Summon / engage / retreat the pet according to current_config.pet.
-- engaged = true while you're fighting (status 1). Returns true if it acted.
function pet_logic(engaged)
    local pc = current_config and current_config.pet
    if not pc or pc.enabled == false then return false end
    local player = windower.ffxi.get_player()
    if not player or not player.buffs or not player.vitals then return false end
    if table.contains(player.buffs, 16) or table.contains(player.buffs, 470) then return false end
    local now = os.clock()
    local pet = get_live_pet()

    -- 1. No pet: (re)summon it
    if not pet then
        pet_state.tp = 0
        pet_state.target_id = 0
        if not pc.summon then return false end
        if not engaged and pc.summon_idle == false then return false end
        if (now - pet_state.last_summon) < (pc.summon_retry or 6) then return false end
        if pc.summon_block_buffs then
            for _, bid in ipairs(pc.summon_block_buffs) do
                if table.contains(player.buffs, bid) then return false end
            end
        end
        local list = type(pc.summon) == 'table' and pc.summon or {pc.summon}
        for _, name in ipairs(list) do
            local ok, pfx = pet_action_ready(name, player)
            if ok then
                pet_state.last_summon = now
                last_ability_time = os.clock()
                info_msg('PET: summoning with ' .. name)
                cmd('input ' .. pfx .. ' "' .. name .. '" <me>')
                coroutine.sleep(pfx == '/ma' and 4.0 or 2.0)
                return true
            end
        end
        return false
    end

    -- 2. Engaged: send the pet at our target if it's idle or on another mob
    if engaged and pc.engage then
        local t = windower.ffxi.get_mob_by_target('t')
        if t and t.id and t.hpp and t.hpp > 0 and t.spawn_type == 16 then
            local on_target = pet.status == 1 and (pet_state.target_id == 0 or pet_state.target_id == t.id)
            if not on_target and (now - pet_state.last_engage) >= (pc.engage_retry or 4) then
                local ok, pfx = pet_action_ready(pc.engage, player)
                if ok then
                    pet_state.last_engage = now
                    last_ability_time = os.clock()
                    debug_msg('PET: ' .. pc.engage .. ' -> ' .. tostring(t.name))
                    cmd('input ' .. pfx .. ' "' .. pc.engage .. '" <t>')
                    coroutine.sleep(1.0)
                    return true
                end
            end
        end
    end

    -- 3. Not engaged: call the pet back if it's still fighting
    if not engaged and pc.retreat and pet.status == 1
       and (now - pet_state.last_retreat) >= (pc.retreat_retry or 4) then
        local ok, pfx = pet_action_ready(pc.retreat, player)
        if ok then
            pet_state.last_retreat = now
            debug_msg('PET: ' .. pc.retreat)
            cmd('input ' .. pfx .. ' "' .. pc.retreat .. '" <me>')
            coroutine.sleep(1.0)
            return true
        end
    end
    return false
end

-- v4.14: opener gate. true = '<t>' JAs may fire on this target.
-- 'faced' = we just turned to the mob this tick (no JA this tick: face + JA on
-- the same tick -> invalid argument). false = still waiting for the first swing.
function opener_ready(target)
    if not target or not target.id then return false end
    if melee_contact.id == target.id then return true end
    local now = os.clock()
    if opener_state.id ~= target.id then
        opener_state.id = target.id
        opener_state.since = now
        opener_state.face_time = 0
        opener_state.logged = false
    end
    if (now - opener_state.since) >= OPENER_FALLBACK then
        if not opener_state.logged then
            debug_msg('OPENER: no melee round on ' .. (target.name or '?') .. ' after ' ..
                OPENER_FALLBACK .. 's -- allowing <t> abilities anyway.')
            opener_state.logged = true
        end
        return true
    end
    if (now - opener_state.face_time) >= OPENER_FACE_EVERY then
        face('f')
        opener_state.face_time = now
        last_face_combat_time = now
        debug_msg('OPENER: facing ' .. (target.name or '?') .. ' -- holding <t> abilities until the first melee round.')
        return 'faced'
    end
    return false
end

-- =========================================================================
-- v4.70: JOB ABILITY TIMING AND CONFLICTS
-- * no JA within JA_AFTER_WS_GAP s of our own WS: on 2026-11-18 every one of
--   Myth's 193 "Unable to use job ability" came 3.0-3.9s after his WS, and
--   every JA tried 4s+ after a WS went off
-- * a JA the game refuses gets its min_time back (it used to wait the full
--   recast, e.g. Berserk 250s); after JA_FAIL_MAX refusals in a row within
--   60s the normal min_time wait applies again
-- * JA_STACKS: buff_any IDs ignored because the buffs stack (Berserk and
--   Aggressor kept skipping each other)
-- * JA_YIELD / an entry's yield_to = {'Berserk'}: hold this JA while that one
--   is up or ready within yield_secs (default JA_YIELD_SECS) -- Defender and
--   Berserk cancel each other, so Defender only fills the gap between Berserks
-- Globals on purpose (main chunk is at the local / upvalue limit).
-- =========================================================================
JA_AFTER_WS_GAP = 4.0
-- v4.77: seconds since our own last WS (global, for code past the upvalue limit)
function aa_ws_ago() return os.clock() - last_ws_time end
JA_TRY          = {name = nil, at = 0, last = 0, uses = 0}
JA_FAILS        = {}
JA_FAIL_MAX     = 3
JA_BUFF_IDS     = {Berserk = 56, Defender = 57, Aggressor = 58, ['Last Resort'] = 64, Warcry = 68}
JA_STACKS       = {Berserk = {[58] = true}, Aggressor = {[56] = true}}
JA_YIELD        = {Defender = {'Berserk'}}
JA_YIELD_SECS   = 30
ja_yield_said   = {}
function ja_stacks(name, bid)
    local st = JA_STACKS[name]
    return st ~= nil and st[bid] == true
end
function ja_yield_skip(entry, buffs, recasts, avail)
    local list = entry.yield_to or JA_YIELD[entry.name]
    if type(list) ~= 'table' then return false end
    for _, other in ipairs(list) do
        local conf
        for _, e in ipairs(current_config.abilities or {}) do
            if type(e) == 'table' and e.name == other then conf = e; break end
        end
        if conf then   -- only yield to a JA this job's config really uses
            local bid = conf.buff_id or JA_BUFF_IDS[other]
            local state, why
            if bid and table.contains(buffs, bid) then
                state, why = 'up', other .. ' is up'
            else
                local d = res_with('job_abilities', 'name', other)
                if d and d.recast_id and table.contains(avail, d.id) then
                    local rc = recasts[d.recast_id]
                    if rc and rc <= (entry.yield_secs or JA_YIELD_SECS) then
                        state, why = 'soon', other .. ' is ready in ' .. math.floor(rc) .. 's'
                    end
                end
            end
            if state then
                if ja_yield_said[entry.name] ~= state then
                    ja_yield_said[entry.name] = state
                    debug_msg('JA: holding ' .. entry.name .. ' -- ' .. why .. ' (they cancel each other).')
                end
                return true
            end
        end
    end
    ja_yield_said[entry.name] = nil
    return false
end
-- "Unable to use job ability." right after use_job_abilities sent one
function ja_failed_text()
    if not JA_TRY.name or (os.clock() - JA_TRY.at) > 2.5 then return end
    local n, now = JA_TRY.name, os.clock()
    JA_TRY.name = nil
    local f = JA_FAILS[n]
    if not f or now - f.t > 60 then f = {n = 0, t = now}; JA_FAILS[n] = f end
    f.n = f.n + 1
    if f.n <= JA_FAIL_MAX then
        ability_last_used[n] = JA_TRY.last
        ability_use_tracker[n] = JA_TRY.uses
        debug_msg('JA: ' .. n .. ' refused ("Unable to use job ability") -- trying again after the gap (' ..
                  f.n .. '/' .. JA_FAIL_MAX .. ').')
    else
        debug_msg('JA: ' .. n .. ' refused ' .. f.n .. 'x in a row -- waiting its normal min_time.')
    end
end

function use_job_abilities()
    if not current_config.abilities then return end
    if current_config.abilities.enabled == false then return end  
	
    local player = windower.ffxi.get_player()
	-- debug_msg('Current buffs: ' .. table.concat(player.buffs, ', '))
	
    local target = windower.ffxi.get_mob_by_target('t')
	

    if not player or not target then return end
	if not target.hpp or target.hpp <= 0 then return end
    if not player.buffs then return end
    if table.contains(player.buffs, 16) or table.contains(player.buffs, 470) then return end

    local abil_recasts = windower.ffxi.get_ability_recasts()
	if not abil_recasts then return end  
	
    local abilities_data = windower.ffxi.get_abilities()
	if not abilities_data or not abilities_data.job_abilities then return end
	local available_abilities = abilities_data.job_abilities
    local current_time = os.time()
    -- v4.14: face the mob first; no JA on the tick we turn
    local opener = opener_ready(target)
    if opener == 'faced' then return false end
    -- v4.70: no JA right after our own WS (animation lock -> "Unable to use job ability")
    if (os.clock() - last_ws_time) < JA_AFTER_WS_GAP then return false end

    for i, entry in ipairs(current_config.abilities) do
        if not entry or not entry.name then break end
        local ability_data = res_with('job_abilities', 'name', entry.name)
        -- v4.14: '<t>' abilities wait for the first melee round (Provoke exempt)
        local opener_blocked = (opener ~= true) and (entry.target == '<t>') and entry.name ~= 'Provoke'
        
        if ability_data and not opener_blocked and table.contains(available_abilities, ability_data.id) then
            local wait_period = entry.min_time or 0
            local last_call = ability_last_used[entry.name] or 0
            local current_uses = ability_use_tracker[entry.name] or 0
			
			-- Single buff + buff_any check
			local has_buff = entry.buff_id and table.contains(player.buffs, entry.buff_id) or false
			-- v3.94: buff_stack = N -> only counts as "have it" once N copies are up (PUP maneuvers)
			if entry.buff_id and entry.buff_stack then
				has_buff = count_buffs(player.buffs, entry.buff_id) >= entry.buff_stack
			end
			-- v3.94: need_buff -> only usable WHILE that buff is up (e.g. Cooldown when Overloaded)
			if entry.need_buff and not table.contains(player.buffs, entry.need_buff) then
				has_buff = true
			end
			if not has_buff and entry.buff_any then
				for _, bid in ipairs(entry.buff_any) do
					if table.contains(player.buffs, bid) and not ja_stacks(entry.name, bid) then  -- v4.70
						has_buff = true
						break
					end
				end
			end
			-- v4.70: hold a JA that would cancel a stronger one (Defender -> Berserk)
			if not has_buff and ja_yield_skip(entry, player.buffs, abil_recasts, available_abilities) then
				has_buff = true
			end

            -- Standard checks
			local recast_ready = false
			if ability_data.recast_id ~= nil then
				if entry.max_recast then
					-- v3.94: charge abilities (Ready, Maneuvers): usable while a charge is up
					local _rc = abil_recasts[ability_data.recast_id]
					recast_ready = _rc ~= nil and _rc <= entry.max_recast
				else
					recast_ready = (abil_recasts[ability_data.recast_id] or -1) == 0
				end
			end

			-- Check TP threshold if specified (e.g. Haste Samba needs 350 TP)
			local tp_ok = true
			if entry.tp and entry.tp > 0 then
				tp_ok = player.vitals and (player.vitals.tp or 0) >= entry.tp
			end
			local can_use = not has_buff and
				recast_ready and
				tp_ok and
				(current_time - last_call) >= wait_period and
				current_uses < (entry.uses_per_mob or 999) and
				pet_entry_ok(entry, player) and  -- v3.94: pet_* / tp_max / hpp / mpp fields
				ja_in_range_logged(entry)        -- v4.13/v4.15: no Jump at a mob out of reach (max_dist)

            -- SPECIAL LOGIC FOR CONVERT
			if entry.name == 'Convert' and can_use then
				if player.vitals and (player.vitals.max_mp or 0) > 0 then
					local mp_perc = (player.vitals.mp / player.vitals.max_mp) * 100
					if mp_perc > (entry.mp_threshold or 15) or player.vitals.hpp < (entry.hp_threshold or 80) then
						can_use = false
					end
				else
					can_use = false  -- can't evaluate Convert without valid vitals
				end
			end

            if can_use then
                -- Block Provoke in ASSIST mode: would steal hate from the party tank
                if entry.name == 'Provoke' and autoattack_type == 'assist' then
                    -- debug_msg('PROVOKE: Skipped in ASSIST mode.')
                else
                JA_TRY.name, JA_TRY.at, JA_TRY.last, JA_TRY.uses = entry.name, os.clock(), last_call, current_uses  -- v4.70
                ability_last_used[entry.name] = current_time
                ability_use_tracker[entry.name] = current_uses + 1
                last_ability_time = os.clock()  -- track for ring equip lockout
                
                debug_msg('Using: ' .. entry.name)
                local ja_target = entry.target or '<me>'
                if ja_target:sub(1,1) ~= '<' then ja_target = '"' .. ja_target .. '"' end
                -- If targeting mob, recheck alive before firing
                if ja_target == '<t>' then
                    local t_ja = windower.ffxi.get_mob_by_target('t')
                    if not t_ja or not t_ja.hpp or t_ja.hpp <= 0 then return false end
                end
                local ja_cmd = 'input ' .. ja_prefix(ability_data) .. ' "' .. tostring(entry.name) .. '" ' .. tostring(ja_target)  -- v3.94: /pet for pet commands
                cmd(ja_cmd)
                
                -- IF CONVERT: Wait for animation and fire emergency Cure IV
                if entry.name == 'Convert' then
                    coroutine.sleep(1.2)
                    debug_msg('Convert detected: Casting emergency Cure IV...')
                    cmd('input /ma "Cure IV" <me>')
                    coroutine.sleep(4) -- Wait for heal to land before doing anything else
                else
                    coroutine.sleep(1.5)
                end
                
                return true
                end  -- closes: if not Provoke-in-ASSIST
            end
        end
    end
    return false
end

-- =========================================================================
-- v4.13: EMERGENCY ABILITIES (2026-10-11 06:06 death follow-up)
-- Spirit Surge (hpp_below=35) never fired: abilities only ran inside the
-- combat chain (needs a live /t), one per tick, and Jump at an out-of-range
-- mob took the tick. Now every entry with hpp_below is checked at the top of
-- every main-loop tick -- target or not -- and a skipped one logs WHY.
-- =========================================================================
EMERGENCY_LOG_EVERY = 10   -- s between "skipped: <reason>" lines per ability
JUMP_REACH_PAD      = 1.5  -- Jumps reach melee range (3.0 + model size) + this
emergency_log = {}

RANGE_LOG_EVERY     = 10   -- v4.15: s between "RANGE: holding X" lines per ability
range_log = {}

-- '<t>' Jumps (or any entry with max_dist=N) only when the target is in reach.
-- v4.15: max_dist is measured from the mob's EDGE (center distance minus its
-- model size), the same way the default Jump reach always was. Without
-- max_dist, Jumps use 3.0 + JUMP_REACH_PAD. Returns ok, edge_distance, limit.
function ja_in_range(entry)
    if not entry or (entry.target or '<me>') ~= '<t>' then return true end
    local limit = tonumber(entry.max_dist)
    if not limit and not tostring(entry.name):find('Jump', 1, true) then return true end
    local t = windower.ffxi.get_mob_by_target('t')
    if not t or not t.distance then return false end
    if not limit then limit = 3.0 + JUMP_REACH_PAD end
    local edge = t.distance:sqrt() - (t.model_size or 2.0)
    return edge <= limit, edge, limit
end

-- v4.15: ja_in_range() plus a rate-limited debug line when it holds an ability.
function ja_in_range_logged(entry)
    local ok, edge, limit = ja_in_range(entry)
    if not ok and edge and limit then
        local now_c = os.clock()
        if now_c - (range_log[entry.name] or 0) >= RANGE_LOG_EVERY then
            range_log[entry.name] = now_c
            debug_msg('RANGE: holding ' .. tostring(entry.name) .. ' -- ' .. string.format('%.1f', edge) ..
                      'y from the mob\'s edge, max_dist ' .. string.format('%.1f', limit) .. 'y.')
        end
    end
    return ok
end

-- nil, data when the entry can fire right now; otherwise a reason string.
function emergency_block_reason(entry, player, recasts, available, now_t)
    local data = res_with('job_abilities', 'name', entry.name)
    if not data then return 'unknown ability name' end
    if not table.contains(available, data.id) then return 'not available (job/level)' end
    local buffs = player.buffs or {}
    if entry.buff_id and table.contains(buffs, entry.buff_id) then return 'buff already up' end
    if data.recast_id ~= nil then
        local r = recasts[data.recast_id]
        if r == nil then return 'recast unknown (recast_id ' .. data.recast_id .. ')' end
        if r > 0 then return 'recast ' .. string.format('%.0f', r) .. 's' end
    end
    local ago = now_t - (ability_last_used[entry.name] or 0)
    if ago < (entry.min_time or 0) then
        return 'used ' .. ago .. 's ago (min_time ' .. entry.min_time .. ')'
    end
    if (ability_use_tracker[entry.name] or 0) >= (entry.uses_per_mob or 999) then return 'uses_per_mob reached' end
    local needs_pet = entry.pet == true or entry.pet_name or entry.pet_hpp_below
        or entry.pet_hpp_above or entry.pet_tp_min or entry.pet_engaged ~= nil
    if needs_pet and not get_live_pet() then return 'no live pet' end
    if not pet_entry_ok(entry, player) then return 'pet / HP / MP / TP condition' end
    if (entry.target or '<me>') == '<t>' then
        local t = windower.ffxi.get_mob_by_target('t')
        if not t or not t.hpp or t.hpp <= 0 then return 'no live target' end
        local _ok, _edge, _lim = ja_in_range(entry)
        if not _ok then
            return 'target out of reach (' .. string.format('%.1f', _edge or 0) .. 'y from edge, max_dist ' ..
                   string.format('%.1f', _lim or 0) .. 'y)'
        end
    end
    return nil, data
end

-- Fire the first ready hpp_below entry (list order). Returns true if one fired.
function emergency_abilities(player)
    if not current_config or not current_config.abilities or current_config.abilities.enabled == false then return false end
    if not player or not player.vitals or (player.vitals.hp or 0) <= 0 then return false end
    local hpp = player.vitals.hpp or 100
    local buffs = player.buffs or {}
    if table.contains(buffs, 16) or table.contains(buffs, 470) then return false end  -- same gate as use_job_abilities
    local any = false
    for _, entry in ipairs(current_config.abilities) do
        if not entry or not entry.name then break end
        if entry.hpp_below and hpp < entry.hpp_below then any = true; break end
    end
    if not any then return false end
    local recasts = windower.ffxi.get_ability_recasts()
    local ad = windower.ffxi.get_abilities()
    if not recasts or not ad or not ad.job_abilities then return false end
    local now_t = os.time()
    for _, entry in ipairs(current_config.abilities) do
        if not entry or not entry.name then break end
        if entry.hpp_below and hpp < entry.hpp_below
           and not (entry.name == 'Provoke' and autoattack_type == 'assist') then
            local reason, data = emergency_block_reason(entry, player, recasts, ad.job_abilities, now_t)
            if not reason then
                ability_last_used[entry.name] = now_t
                ability_use_tracker[entry.name] = (ability_use_tracker[entry.name] or 0) + 1
                last_ability_time = os.clock()
                info_msg('EMERGENCY: HP ' .. hpp .. '% -- using ' .. entry.name)
                cmd('input ' .. ja_prefix(data) .. ' "' .. tostring(entry.name) .. '" ' .. (entry.target or '<me>'))
                coroutine.sleep(1.5)
                return true
            elseif (os.clock() - (emergency_log[entry.name] or 0)) >= EMERGENCY_LOG_EVERY then
                emergency_log[entry.name] = os.clock()
                debug_msg('EMERGENCY: HP ' .. hpp .. '% -- ' .. entry.name .. ' skipped: ' .. reason)
            end
        end
    end
    return false
end



-- Attempts to use Provoke as a pull instead of the default pull_command when:
--   1. The player is WAR main or sub
--   2. The mob is within Provoke range (17.8y)
--   3. Provoke's recast is ready
-- Returns true and fires Provoke if all conditions are met; returns false otherwise
-- so the caller can fall back to the configured pull_command.
-- Shares ability_last_used['Provoke'] with use_provoke_for_hate and use_job_abilities
-- so the three never conflict over the recast timer.
local PROVOKE_PULL_RANGE = 17.8  -- v3.91: v3.90's 9.0 reverted (misread log)

-- v3.85: Provoke-pull hold. When Provoke is ready and the pull target is inside
-- the configured pull range (e.g. 24.9y for /ra) but outside Provoke range,
-- hold the pull for up to wait seconds so the mob can come into Provoke range
-- (you running toward it, or it wandering closer). After wait seconds on the
-- same mob, the normal pull_command (/ra, Dia) fires as before.
provoke_hold_state = {id = 0, start = 0, last = 0, wait = 6.0}
RA_PULL_RANGE = 24.9   -- v4.27: /ra reach, for the Provoke-down fallback
RA_PULL_WAIT  = 4.5

-- True when the player can Provoke right now: WAR main/sub, recast ready and
-- the shared 30s ability_last_used lock clear. No range check.
function provoke_pull_ready()
    local player = windower.ffxi.get_player()
    if not player then return false end

    -- Only WAR main or sub has Provoke
    if player.main_job ~= 'WAR' and player.sub_job ~= 'WAR' then return false end

    -- Check Provoke recast
    local provoke_data = res_with('job_abilities', 'name', 'Provoke')
    if not provoke_data or not provoke_data.recast_id then return false end

    local abil_recasts = windower.ffxi.get_ability_recasts()
    if not abil_recasts then return false end

    local prov_recast = abil_recasts[provoke_data.recast_id]
    if prov_recast and prov_recast > 0 then return false end  -- 0/nil = ready

    -- Respect the shared 30s min_time lock
    local last_call = ability_last_used['Provoke'] or 0
    if (os.time() - last_call) < 30 then return false end
    return true
end

-- v3.85: Returns true if the pull on target should be HELD (not fired) this
-- tick because Provoke is ready and the mob is just outside Provoke range.
-- Times out after provoke_hold_state.wait seconds on the same mob, then
-- returns false so the configured pull_command fires.
function provoke_pull_hold(target, dist, pull_cmd)
    if autoattack_type ~= 'pull' then return false end
    if not target or not target.id or not dist then return false end
    if dist <= PROVOKE_PULL_RANGE then return false end           -- Provoke can land now
    if pull_cmd and pull_cmd:lower():find('provoke') then return false end  -- provoke method already uses 17.8y
    if not provoke_pull_ready() then return false end             -- on recast: use /ra as normal
    local hs  = provoke_hold_state
    local now = os.clock()
    -- v4.27: only wait for Provoke range when the mob is coming to us (claimed
    -- by us and targeting us, or hitting you / a Trust). An idle mob just sits
    -- out there, so waiting only cost up to 6s: pull with pull_command now
    -- (if it can fire; if not -- no ammo etc. -- keep the old hold).
    local coming = mob_claimed_on_me(target) or mob_hit_victim(target) ~= nil or mob_fighting_trust(target)
    if not coming and main_pull_ready(pull_cmd, dist) then
        if hs.skip_id ~= target.id then
            hs.skip_id = target.id
            debug_msg('PROVOKE-SKIP: ' .. (target.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                      'y is not coming to you -- ' .. (pull_cmd or 'pull') .. ' now instead of waiting for Provoke range.')
        end
        return false
    end
    -- New mob, or we stopped holding a while ago -> start a fresh timer
    if hs.id ~= target.id or (now - hs.last) > 3.0 then
        hs.id = target.id
        hs.start = now
    end
    hs.last = now
    local left = hs.wait - (now - hs.start)
    if left > 0 then
        debug_msg('PROVOKE-WAIT: ' .. (target.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                  'y -- holding pull for Provoke range (' .. string.format('%.1f', PROVOKE_PULL_RANGE) ..
                  'y), ' .. string.format('%.0f', left) .. 's before ' .. (pull_cmd or 'pull') .. '.')
        return true
    end
    debug_msg('PROVOKE-WAIT: ' .. (target.name or '?') .. ' stayed out of Provoke range for ' ..
              string.format('%.0f', hs.wait) .. 's. Using ' .. (pull_cmd or 'pull') .. '.')
    return false
end

-- v3.87: Provoke confirmation. The old code stamped the 30s lock and reported
-- success the moment the /ja command was SENT. If the game dropped it (e.g. sent
-- 0.15s after /attack on, mid-engage), nothing pulled the mob and Provoke stayed
-- locked for 30s. Now we send Provoke, then wait up to PROVOKE_CONFIRM_WAIT for
-- our own category-6 (job ability) action packet with Provoke's ID (set by the
-- 'action' event handler). Confirmed -> keep the 30s lock, return true.
-- Not confirmed -> shorten the lock to ~3s and return false so the caller can
-- fall back to its normal pull/re-pull command.
-- Globals (not locals) on purpose: the main loop is at Lua 5.1's upvalue limit.
provoke_pending = {active = false, confirmed = false, ja_id = nil}
PROVOKE_CONFIRM_WAIT = 2.0
PROVOKE_FAIL_RETRY   = 3   -- seconds before Provoke may be tried again after a miss
-- v3.88: delay between /attack on and the Provoke / pull_command follow-up.
-- v3.86 used 0.15s (Provoke got dropped mid-engage). Tune this: lower = faster
-- pull, too low = more PROVOKE-FAIL lines (then /ra fires as the fallback).
-- v3.91: PULL_FOLLOWUP_DELAY is now a short settle AFTER the game reports you
-- engaged (player.status == 1), not a fixed guess after /attack on. Fixed delays
-- of 0.15 / 0.5 / 0.7s all had Provoke silently dropped mid-engage.
PULL_FOLLOWUP_DELAY  = 0.2
ENGAGE_WAIT_MAX      = 3.0   -- give up waiting for engage after this; pull anyway

-- v3.91: after /attack on, wait until the player is actually engaged, then
-- PULL_FOLLOWUP_DELAY, so the Provoke / pull_command that follows isn't dropped.
function wait_for_engage()
    local t0 = os.clock()
    while (os.clock() - t0) < ENGAGE_WAIT_MAX do
        local p = windower.ffxi.get_player()
        if p and p.status == 1 then
            debug_msg('ENGAGED after ' .. string.format('%.1f', os.clock() - t0) .. 's.')
            coroutine.sleep(PULL_FOLLOWUP_DELAY)
            return true
        end
        coroutine.sleep(0.1)
    end
    debug_msg('ENGAGE-WAIT: not engaged after ' .. string.format('%.1f', ENGAGE_WAIT_MAX) .. 's; pulling anyway.')
    return false
end

-- v3.92: Engage at max melee range. The pull (Provoke / /ra / Dia) now fires while
-- UNENGAGED (Provoke works reliably then), and /attack on is held until the
-- pulled mob walks into melee range (3.0 + model_size, same formula as the pull
-- code), so the first swing happens at the edge of melee range instead of when
-- the mob is on top of you. Faces the mob every 1s while it approaches (replaces
-- the v3.24 5x1s facing loop). If it hasn't arrived after APPROACH_WAIT_MAX
-- seconds, /attack on fires anyway so the normal re-pull logic takes over.
-- already_sent = true when the caller already sent /attack on (melee pull).
APPROACH_WAIT_MAX = 8.0
function engage_at_melee_range(already_sent)
    local t0 = os.clock()
    local last_face = 0
    local sent = already_sent and true or false
    while (os.clock() - t0) < APPROACH_WAIT_MAX do
        local t = windower.ffxi.get_mob_by_target('t')
        if not t or not t.hpp or t.hpp <= 0 then return false end  -- mob gone / dead
        local p = windower.ffxi.get_player()
        if p and p.status == 1 then return true end               -- engaged
        local d = t.distance and t.distance:sqrt() or 999
        local mr = 3.0 + (t.model_size or 2.0)
        if not sent and d <= mr then
            info_msg('ATTACKING >>>> (melee edge ' .. string.format('%.1f', d) .. 'y / ' ..
                      string.format('%.1f', mr) .. 'y) ' .. (t.name or '?'))
            cmd('input /attack on')
            sent = true
        end
        if (os.clock() - last_face) >= 1.0 then
            face('f')
            last_face = os.clock()
        end
        coroutine.sleep(0.1)
    end
    if not sent then
        local t = windower.ffxi.get_mob_by_target('t')
        if t and t.hpp and t.hpp > 0 then
            info_msg('ATTACKING >>>> (approach timeout ' .. string.format('%.0f', APPROACH_WAIT_MAX) ..
                      's) ' .. (t.name or '?'))
            cmd('input /attack on')
        end
    end
    return false
end

-- v3.93: Two-stage pull (PULL mode).
--   Stage 1 (not engaged): when the target is within ENGAGE_RANGE, /attack on only
--     (draws weapons). No Provoke / /ra here. wait_for_engage() lets it settle.
--   Stage 2 (engaged, every tick): engaged_pull_logic() decides whether to pull:
--     * Mob within melee range (3.0 + model_size): DON'T pull. Give the character
--       MELEE_HIT_WAIT seconds to swing. Pull only if no swing lands in that time,
--       or the game says "<mob> is out of range." (msg 4/154) while we think it's close.
--     * Mob outside melee range: Provoke if within PROVOKE_PULL_RANGE and ready;
--       if Provoke is ready but the mob is farther, hold up to provoke_hold_state.wait
--       (v3.85 hold); otherwise pull_command when within pull_dist. After a pull,
--       wait PULL_APPROACH_WAIT for the mob to walk in before pulling again.
--     * A swing (melee round or WS) on the mob resets everything; REPULL_LIMIT still
--       blacklists + disengages a mob that never reaches us.
ENGAGE_RANGE       = 29.0   -- /attack on (draw weapons) within this distance
MELEE_HIT_WAIT     = 4.0    -- seconds in melee range with no swing before re-facing the mob
-- v3.97: Provoke / pull_command are NEVER used on a mob already in melee range.
-- In melee range with no contact (melee round, WS or JA on it) for
-- MELEE_STALL_LIMIT seconds, the mob is treated as unreachable (e.g. floating):
-- blacklisted and disengaged, the same as the re-pull limit.
MELEE_STALL_LIMIT  = 15.0
PULL_APPROACH_WAIT = 6.0    -- seconds after a pull before pulling again (mob walking in)
pull_state  = {id = 0, engaged_at = 0, last_pull = 0, pulls = 0, far_logged = 0}
melee_swing = {id = 0, time = 0}   -- last melee round / WS from us (action event)
melee_round = {id = 0, time = 0}   -- v4.35: last real melee round (cat 1 only) and on which mob
-- v4.14: OPENER GATE. '<t>' job abilities (Jump, High Jump, Dragon Breaker,
-- Smiting Breath, ...) wait until we have FACED the mob and landed a melee
-- round (or WS) on it, so Trusts are engaged before the JAs start. Provoke is
-- exempt (pull tool). hpp_below emergency entries (Super Jump) are exempt.
-- Globals on purpose: the main loop is at the Lua 5.1 upvalue limit.
melee_contact  = {id = 0, time = 0}   -- last cat 1 melee round / cat 3 WS from us (NOT JAs)
opener_state   = {id = 0, since = 0, face_time = 0, logged = false}
OPENER_FACE_EVERY = 2.0    -- s between opener faces while waiting for the first swing
OPENER_FALLBACK   = 12.0   -- s on a mob with no swing before '<t>' JAs are allowed anyway
oor_msg     = {id = 0, time = 0}   -- last "<mob> is out of range." for us (0x029)

-- v3.99: Pull-in timeout (PULL mode). Once a mob is chosen and within pull
-- range, it has PULL_IN_TIMEOUT seconds to be "pulled in": reach your melee
-- range, take a swing from you, or be fighting a party member (Trust) in its
-- own melee range. While it is targeting you / a party member and still
-- walking closer, the clock restarts. Otherwise it is blacklisted for
-- PULL_IN_BLACKLIST seconds (not lifted early), you disengage / clear the
-- cursor, and the next tick picks the closest mob again.
-- Globals on purpose: the main loop is at the Lua 5.1 upvalue limit.
PULL_IN_TIMEOUT   = 20.0   -- v4.01: was 10
PULL_IN_BLACKLIST = 30.0   -- v4.01: was 10
pull_in        = {id = 0, since = 0, done = false, last_d = 999, first = 0, claimed_logged = false,
                  provoke_tried = false, hold_logged = false}   -- v4.39
-- v4.39: Provoke before giving up. A pull-in timeout or the re-pull limit no
-- longer blacklists a mob in Provoke range that Provoke was never tried on:
-- Provoke ready -> fire it first (fresh pull-in window if it lands); Provoke
-- back within PULL_GIVEUP_PROVOKE_WAIT s -> hold the give-up for it.
PULL_GIVEUP_PROVOKE_WAIT = 8.0
-- v4.39: a /ra pull just got "Unable to see"/"You cannot see" and Provoke is
-- back within RA_CANT_SEE_PROVOKE_WAIT s -> wait for Provoke, don't re-/ra.
RA_CANT_SEE_PROVOKE_WAIT = 8.0
RA_CANT_SEE_WINDOW       = 10.0   -- s a cant-see on the target stays fresh
ra_cant_see    = {id = 0, time = 0}   -- v4.39: last cant-see on our target (never cleared by STEP-IN)
pull_in_nolift = {}   -- [mob_id] = expiry: pull-in timeouts the unblacklist rule must not lift

-- Returns the party entity (you or a Trust/member) this mob is targeting, or nil.
function pull_in_victim(t)
    if not t or not t.target_index or t.target_index == 0 then return nil end
    local me = windower.ffxi.get_player()
    if me and me.index and t.target_index == me.index then
        return windower.ffxi.get_mob_by_target('me')
    end
    local party = windower.ffxi.get_party()
    if not party then return nil end
    for key, m in pairs(party) do
        if type(key) == 'string' and type(m) == 'table' and key:match('^p[0-5]$') then
            local idx = m.mob_index or (m.mob and m.mob.index)
            if idx and idx > 0 and idx == t.target_index then
                return windower.ffxi.get_mob_by_index(idx)
            end
        end
    end
    return nil
end

-- v4.39: called right before a pull is given up on (pull-in timeout or re-pull
-- limit). Returns 'fired' (Provoke landed), 'hold' (Provoke back soon, wait),
-- or nil (give up as before: no /WAR, out of Provoke range, already tried,
-- not on the cursor, or held too long).
function giveup_provoke_first(t, dist, label)
    if autoattack_type ~= 'pull' or not t or not t.id then return nil end
    if pull_in.id ~= t.id then return nil end
    if pull_in.provoke_tried then return nil end
    if not dist or dist > PROVOKE_PULL_RANGE then return nil end
    -- a confirmed Provoke already landed on it since we picked it
    if provoke_last.id == t.id and provoke_last.time >= (pull_in.first or 0) then
        pull_in.provoke_tried = true
        return nil
    end
    local cur = windower.ffxi.get_mob_by_target('t')
    if not cur or cur.id ~= t.id then return nil end
    local left = provoke_wait_left()
    if left == nil then return nil end   -- no /WAR
    local now = os.clock()
    pull_in.hold_since = pull_in.hold_since or now
    if (now - pull_in.hold_since) > PULL_GIVEUP_PROVOKE_WAIT + 3.0 then return nil end  -- never hold forever
    if left <= 0 and provoke_pull_ready() then
        pull_in.provoke_tried = true
        debug_msg('GIVEUP-PROVOKE: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                  'y -- ' .. label .. ', but Provoke was never tried on it. Provoking first.')
        if try_provoke_pull(t) then
            pull_in.since = os.clock()        -- fresh window to walk in
            pull_in.hold_since = nil
            repull_count = 0
            if pull_state.id == t.id then pull_state.last_pull = os.clock(); pull_state.pulls = pull_state.pulls + 1 end
            return 'fired'
        end
        return nil
    end
    if left <= PULL_GIVEUP_PROVOKE_WAIT then
        if not pull_in.hold_logged then
            pull_in.hold_logged = true
            debug_msg('GIVEUP-HOLD: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                      'y -- ' .. label .. ', Provoke ready in ' .. string.format('%.0f', left) ..
                      's. Waiting to Provoke before giving up.')
        end
        return 'hold'
    end
    return nil
end

-- Returns true if the timeout fired (mob blacklisted, cursor cleared).
function pull_in_check(t, pull_dist, engaged)
    if autoattack_type ~= 'pull' or not t or not t.id then return false end
    local now = os.clock()
    if pull_in.id ~= t.id then
        pull_in.id = t.id; pull_in.since = now; pull_in.done = false; pull_in.last_d = 999
        pull_in.first = now; pull_in.claimed_logged = false   -- v4.12
        pull_in.provoke_tried = false; pull_in.hold_logged = false; pull_in.hold_since = nil  -- v4.39
    end
    if pull_in.done then return false end
    local dist = t.distance and t.distance:sqrt() or 999
    local mr   = 3.0 + (t.model_size or 2.0)
    local swung = melee_swing.id == t.id and (now - melee_swing.time) < MELEE_HIT_WAIT
    if dist <= mr or swung then
        pull_in.done = true          -- pulled in; melee stall / stuck watchdog take over
        return false
    end
    if not engaged and dist > math.max(pull_dist or 0, ENGAGE_RANGE) then
        pull_in.since = now          -- only a far cursor (whitelist): no pull attempted yet
        pull_in.last_d = dist
        return false
    end
    if mob_hit_victim(t) then        -- v4.02: it is hitting you / a party member
        pull_in.done = true
        return false
    end
    -- v4.12: it targets YOU and your party has claimed it -- e.g. a Provoked
    -- caster that stops at casting range (2026-10-11 06:06 death: the Eschan
    -- Corse sat at 7.0y casting Flood, was timed out + blacklisted, then meleed
    -- us while we pulled a 2nd mob). It is in our fight: no pull-in timeout for
    -- up to PULL_IN_CLAIMED_MAX s (an unreachable cliff mob still times out).
    if mob_claimed_on_me(t) and (now - (pull_in.first or now)) < PULL_IN_CLAIMED_MAX then
        pull_in.since = now
        pull_in.last_d = dist
        if not pull_in.claimed_logged then
            pull_in.claimed_logged = true
            debug_msg('PULL-IN: ' .. (t.name or '?') .. ' targets you and is claimed by your party at ' ..
                      string.format('%.1f', dist) .. 'y -- in our fight, no pull timeout (max ' ..
                      string.format('%.0f', PULL_IN_CLAIMED_MAX) .. 's).')
        end
        return false
    end
    local victim = pull_in_victim(t)
    if victim and victim.x and victim.y and t.x and t.y then
        local dx, dy = victim.x - t.x, victim.y - t.y
        if math.sqrt(dx * dx + dy * dy) <= mr + 1.0 then
            pull_in.done = true      -- it is fighting a party member
            return false
        end
        if dist < pull_in.last_d - 0.3 then pull_in.since = now end  -- walking in
    end
    pull_in.last_d = dist
    if (now - pull_in.since) < PULL_IN_TIMEOUT then return false end
    if giveup_provoke_first(t, dist, 'pull-in timeout') then return false end  -- v4.39
    debug_msg('PULL-TIMEOUT: ' .. (t.name or '?') .. ' (ID ' .. t.id .. ') still at ' ..
              string.format('%.1f', dist) .. 'y after ' .. string.format('%.0f', PULL_IN_TIMEOUT) ..
              's -- not pulled in. Blacklisting ' .. string.format('%.0f', PULL_IN_BLACKLIST) ..
              's, picking the closest mob again.')
    cant_target_ids[t.id]    = now + PULL_IN_BLACKLIST
    cant_target_counts[t.id] = nil
    pull_in_nolift[t.id]     = now + PULL_IN_BLACKLIST
    pull_in.id = 0
    pull_state.id = 0
    repull_count = 0
    if engaged then
        cmd('input /attack off')
        coroutine.sleep(0.3)
    end
    cmd('input /targetoff')
    return true
end

-- v4.02: Who the mob has actually HIT (melee / TP move / spell) recently, from
-- the action event: mob_hits[mob_id] = {t = os.clock(), tid = target id}.
-- Far more reliable than the mob's target_index, which missed Death Jackets
-- that were hitting Valaineral the whole time (2026-10-10 23:37 / 23:38 log).
MOB_HIT_WINDOW = 10.0   -- seconds a hit on you / a party member counts as "in our fight"
mob_hits = {}
function mob_hit_victim(t)  -- 'me' | 'party' | nil
    if not t or not t.id then return nil end
    local h = mob_hits[t.id]
    if not h or (os.clock() - h.t) > MOB_HIT_WINDOW then return nil end
    local me = windower.ffxi.get_player()
    if me and h.tid == me.id then return 'me' end
    local party = windower.ffxi.get_party()
    if not party then return nil end
    for key, m in pairs(party) do
        if type(key) == 'string' and type(m) == 'table' and key:match('^p[1-5]$') then
            local id = m.id or (m.mob and m.mob.id)
            if id and id == h.tid then return 'party' end
        end
    end
    return nil
end

-- v4.02: True if the mob is hitting you or a Trust/party member right now.
-- Such a mob is in our fight: it is never blacklisted (re-pull limit, STUCK,
-- MELEE-STALL); if we can't hit it we re-pull it with Provoke instead.
-- A mob that can't reach anyone (v3.83 cliff mob) never hits, so it is still
-- blacklisted as before.
function mob_in_our_fight(t)
    return mob_hit_victim(t) ~= nil or mob_fighting_trust(t)
end

-- ===================================================================
-- v4.12: "a mob is on you" helpers (2026-10-11 06:06 Escha Zi'Tah death)
-- ===================================================================
PULL_IN_CLAIMED_MAX = 60.0  -- s a claimed mob targeting you is exempt from the pull-in timeout
LOW_HP_NO_PULL_PCT  = 50    -- no NEW pulls while your HP% is below this (0 = off)
FRESH_HOLD_RANGE    = 25.0  -- a mob on you within this range blocks new pulls
FRESH_HOLD_MAX      = 45.0  -- ...for at most this many seconds per mob (unreachable-mob safety)
LOW_HP_EMERGENCY_CMD = ''   -- Windower command run once when HP drops to LOW_HP_STOP_PCT with a
                            -- mob on you, e.g. 'input /ja "Super Jump" <t>'  ('' = none)
fresh_hold     = {id = 0, since = 0, expired_logged = 0}
fresh_hold_log = 0
low_hp_below_since  = 0
low_hp_emerg_done   = false
low_hp_fight_logged = 0

-- True if this entity ID is you or a party member / Trust.
function is_party_entity_id(id)
    if not id or id == 0 then return false end
    local me = windower.ffxi.get_player()
    if me and me.id == id then return true end
    local party = windower.ffxi.get_party()
    if not party then return false end
    for key, m in pairs(party) do
        if type(key) == 'string' and type(m) == 'table' and key:match('^p[0-5]$') then
            local mid = m.id or (m.mob and m.mob.id)
            if mid and mid == id then return true end
        end
    end
    return false
end

-- True if the mob is targeting YOU and is claimed by you / your party.
function mob_claimed_on_me(t)
    if not t or not t.target_index or t.target_index == 0 then return false end
    if not t.claim_id or t.claim_id == 0 then return false end
    local me = windower.ffxi.get_player()
    if not me or not me.index or t.target_index ~= me.index then return false end
    return is_party_entity_id(t.claim_id)
end

-- Closest live mob within FRESH_HOLD_RANGE that has hit you recently or is
-- targeting you while claimed by your party. Returns mob, distance (or nil).
function mob_on_me(mobs)
    mobs = mobs or windower.ffxi.get_mob_array()
    if not mobs then return nil end
    local me = windower.ffxi.get_player()
    if not me or not me.index then return nil end
    local best, best_d = nil, 999
    for _, m in pairs(mobs) do
        if type(m) == 'table' and m.spawn_type == 16 and m.hpp and m.hpp > 0 and m.distance then
            local d = m.distance:sqrt()
            if d <= FRESH_HOLD_RANGE and d < best_d then
                local on = mob_hit_victim(m) == 'me'
                if not on and m.target_index == me.index and m.claim_id and m.claim_id ~= 0 then
                    on = is_party_entity_id(m.claim_id)
                end
                if on then best, best_d = m, d end
            end
        end
    end
    return best, best_d
end

-- A mob that HIT you in the last MOB_HIT_WINDOW s is in your fight: lift any
-- temporary blacklist on it so the priority scan picks it up (06:06:11 the
-- blacklisted Corse meleed us and was ignored). Repeat offenders (2+
-- unreachable strikes, v3.83 cliff mob) and mob_blacklist entries stay blocked.
function unblacklist_hitters(mobs)
    if not mobs then return end
    local me = windower.ffxi.get_player()
    for id, _ in pairs(cant_target_ids) do
        local m = windower.ffxi.get_mob_by_id(id)  -- v4.24: get_mob_array() is keyed by index, so mobs[id] was always nil
        -- v4.24: 'on you' = same test as mob_on_me()/HOLD: hit you recently, OR
        -- targets you and is claimed by your party (e.g. a mob you Provoked that
        -- was then LOS-blacklisted and walked over to you).
        local on = type(m) == 'table' and mob_hit_victim(m) == 'me'
        if not on and type(m) == 'table' and me and me.index and m.target_index == me.index
           and m.claim_id and m.claim_id ~= 0 then
            on = is_party_entity_id(m.claim_id)
        end
        if type(m) == 'table' and m.hpp and m.hpp > 0 and (cant_see_strikes[id] or 0) < 2 and on then
            debug_msg('UNBLACKLIST: ' .. (m.name or '?') .. ' (' .. id .. ') is on you -- back in the fight.')
            cant_target_ids[id] = nil
            cant_target_counts[id] = nil
            if pull_in_nolift then pull_in_nolift[id] = nil end
        end
    end
end

-- No NEW pull while (a) your HP is below LOW_HP_NO_PULL_PCT, or (b) a mob is
-- on you (hit you / targets you + claimed). (b) is capped at FRESH_HOLD_MAX s
-- per mob so an unreachable mob can't freeze the addon. Returns true = hold.
function fresh_pull_hold(mobs)
    if full_party_hold() then return true end  -- v4.54: party not full
    local now = os.clock()
    local me = windower.ffxi.get_player()
    if not me then return false end
    local hpp = (me.vitals and me.vitals.hpp) or 100
    if LOW_HP_NO_PULL_PCT > 0 and hpp < LOW_HP_NO_PULL_PCT then
        if (now - fresh_hold_log) >= 5 then
            debug_msg('HOLD: HP ' .. hpp .. '% -- no new pull below ' .. LOW_HP_NO_PULL_PCT .. '%.')
            fresh_hold_log = now
        end
        return true
    end
    local m, d = mob_on_me(mobs)
    if not m then fresh_hold.id = 0; return false end
    if fresh_hold.id ~= m.id then fresh_hold.id = m.id; fresh_hold.since = now end
    if (now - fresh_hold.since) >= FRESH_HOLD_MAX then
        if fresh_hold.expired_logged ~= m.id then
            debug_msg('HOLD: ' .. (m.name or '?') .. ' has been on you ' .. string.format('%.0f', FRESH_HOLD_MAX) ..
                      's without reaching melee -- allowing new pulls.')
            fresh_hold.expired_logged = m.id
        end
        return false
    end
    if (now - fresh_hold_log) >= 5 then
        debug_msg('HOLD: ' .. (m.name or '?') .. ' (' .. string.format('%.1f', d) ..
                  'y) is on you -- no new pull until it is dead or gone.')
        fresh_hold_log = now
    end
    return true
end

-- One debug line with every party member / Trust: HP%, MP%, distance.
function log_party_status()
    local party = windower.ffxi.get_party()
    if not party then return end
    local parts = {}
    for i = 1, 5 do
        local m = party['p' .. i]
        if type(m) == 'table' and m.name then
            local d = (m.mob and m.mob.distance) and string.format('%.1fy', m.mob.distance:sqrt()) or 'out of zone/range'
            parts[#parts + 1] = m.name .. ' ' .. (m.hpp or '?') .. '%HP ' .. (m.mpp or '?') .. '%MP ' .. d
        end
    end
    debug_msg('PARTY: ' .. (#parts > 0 and table.concat(parts, ' | ') or 'no party members'))
end

-- v3.83 Low-HP stop, reworked in v4.12. Returns true = stop the main loop.
--  * The 30s clock starts when HP drops to LOW_HP_STOP_PCT (or at the last
--    heal), not at the last HP rise -- at full HP nothing can "rise", so the
--    old check fired 11s after the damage started.
--  * A mob on you: never stop (stopping = standing there until you die).
--    Run LOW_HP_EMERGENCY_CMD once, warn, keep fighting.
--  * Nothing on you: stop as before.
function low_hp_check(player)
    if not LOW_HP_STOP or not player or not player.vitals or (player.vitals.hp or 0) <= 0 then return false end
    local now = os.clock()
    local hp  = player.vitals.hp
    if hp > low_hp_last_hp then low_hp_last_rise = now end
    low_hp_last_hp = hp
    local hpp = player.vitals.hpp or 100
    if hpp > LOW_HP_STOP_PCT then
        low_hp_below_since = 0; low_hp_emerg_done = false
        return false
    end
    if low_hp_below_since == 0 then low_hp_below_since = now end
    local on = mob_on_me()
    if on and LOW_HP_EMERGENCY_CMD ~= '' and not low_hp_emerg_done then
        low_hp_emerg_done = true
        info_msg('LOW HP: ' .. hpp .. '% with ' .. (on.name or '?') .. ' on you -- emergency: ' .. LOW_HP_EMERGENCY_CMD)
        cmd(LOW_HP_EMERGENCY_CMD)
    end
    local quiet = now - math.max(low_hp_below_since, low_hp_last_rise)
    if quiet < LOW_HP_NO_HEAL_SECS then return false end
    if on then
        if (now - low_hp_fight_logged) >= 10 then
            windower.add_to_chat(167, '[AutoAttack] LOW HP: ' .. hpp .. '% and no healing for ' ..
                string.format('%.0f', quiet) .. 's, but ' .. (on.name or '?') ..
                ' is on you -- fighting on (stopping would leave you standing there).')
            log_party_status()
            low_hp_fight_logged = now
        end
        return false
    end
    local _t_lh = windower.ffxi.get_mob_by_target('t')
    windower.add_to_chat(167, '[AutoAttack] LOW HP STOP: ' .. hpp .. '% HP and no healing for ' ..
        LOW_HP_NO_HEAL_SECS .. 's' .. (_t_lh and (' (target: ' .. (_t_lh.name or '?') .. ')') or '') ..
        '. AutoAttack stopped -- //aa pull or //aa assist to resume.')
    info_msg('LOW HP STOP: hpp=' .. hpp .. ', ' .. string.format('%.0f', quiet) .. 's below ' ..
              LOW_HP_STOP_PCT .. '% without healing, nothing on you.')
    log_party_status()
    auto_attack = false
    cmd('input /attack off')
    return true
end

-- v4.02: seconds until Provoke can be used (0 = ready, nil = no Provoke: not WAR main/sub).
function provoke_wait_left()
    local player = windower.ffxi.get_player()
    if not player or (player.main_job ~= 'WAR' and player.sub_job ~= 'WAR') then return nil end
    local pd = res_with('job_abilities', 'name', 'Provoke')
    if not pd or not pd.recast_id then return nil end
    local rc = windower.ffxi.get_ability_recasts()
    local left = (rc and rc[pd.recast_id]) or 0
    local lock = 30 - (os.time() - (ability_last_used['Provoke'] or 0))
    if lock > left then left = lock end
    if left < 0 then left = 0 end
    return left
end

-- =========================================================================
-- v4.17: BACKUP PULL. Mob targeted, weapons out, sitting just outside melee
-- range, and the main pull can't fire right now (Provoke on recast or no
-- /WAR, no ranged weapon / ammo for /ra, Dia on recast / no MP). Instead of
-- waiting, fire the first ready entry of job_config[job].backup_pull (Jump,
-- a spell, /ra ...) to tag the mob and pull it in.
--   backup_pull = { {name='Jump', max_dist=9.5}, {name='Ranged Attack', max_dist=20}, ... }
--   name      JA / pet command / spell name, or 'Ranged Attack' for /ra <t>
--   max_dist  yalms from the mob's EDGE (center distance minus model size)
--   pet=..., hpp_above=... etc. work as in `abilities` (pet_entry_ok)
-- Never fires in melee range, in ASSIST mode, or within PULL_APPROACH_WAIT of
-- the last pull (the mob may already be walking in).
-- =========================================================================
BACKUP_PULL_LOG_EVERY = 5
backup_pull_log       = 0

-- Spell usable at your current main / sub job level?
function spell_level_ok(sp, player)
    if not sp or type(sp.levels) ~= 'table' or not player then return true end
    local ml = player.main_job_id and sp.levels[player.main_job_id]
    local sl = player.sub_job_id and sp.levels[player.sub_job_id]
    if ml and ml <= (player.main_job_level or 0) then return true end
    if sl and sl <= (player.sub_job_level or 0) then return true end
    return false
end

-- Resource entry of the item equipped in `slot` ('range', 'ammo'), or nil.
function equipped_item_res(slot)
    local items = {equipment = windower.ffxi.get_items('equipment')}   -- v4.61: equipment only
    if type(items.equipment) ~= 'table' then return nil end
    local idx = items.equipment[slot]
    local bag = items.equipment[slot .. '_bag']
    if not idx or idx == 0 or bag == nil then return nil end
    local it = windower.ffxi.get_items(bag, idx)
    if type(it) ~= 'table' or not it.id or it.id == 0 then return nil end
    return aa_item(it.id)   -- v4.61
end

-- True when /ra can work: bow/crossbow/gun with ammo, a throwing weapon in the
-- range slot, or a throwing item alone in the ammo slot. (A PUP animator or
-- BST pet food doesn't count.) Skill ids: 25 Archery, 26 Marksmanship, 27 Throwing.
function ranged_attack_ready()
    local r = equipped_item_res('range')
    local a = equipped_item_res('ammo')
    if r and (r.skill == 25 or r.skill == 26) then return a ~= nil end
    if r and r.skill == 27 then return true end
    if not r and a and a.skill == 27 then return true end
    return false
end

-- Can the configured main pull fire right now at this distance?
function main_pull_ready(pull_command, dist)
    local pc = tostring(pull_command or ''):lower()
    if pc:find('provoke', 1, true) then
        local left = provoke_wait_left()
        return left ~= nil and left <= 0 and dist <= PROVOKE_PULL_RANGE
    elseif pc:find('/ra', 1, true) then
        return ranged_attack_ready()
    elseif pc:find('dia', 1, true) then
        local player = windower.ffxi.get_player()
        local sp = res_with('spells', 'name', 'Dia')
        if not player or not sp or not spell_level_ok(sp, player) then return false end
        return (pet_action_ready('Dia', player)) == true
    end
    return true
end

-- ok, prefix  (prefix = '/ja' | '/pet' | '/ma' | '/ra')   or   false, reason
function backup_pull_ready(entry, player)
    local name = entry.name
    local buffs = player.buffs or {}
    if name == 'Ranged Attack' then
        if not ranged_attack_ready() then return false, 'no ranged weapon / ammo' end
        return true, '/ra'
    end
    local ja = res_with('job_abilities', 'name', name)
    if ja then
        if table.contains(buffs, 16) or table.contains(buffs, 261) then return false, 'amnesia' end
        local ok, pre = pet_action_ready(name, player)
        if not ok then return false, 'not available / recast' end
        if not pet_entry_ok(entry, player) then return false, 'pet / HP / TP condition' end
        return true, pre
    end
    local sp = res_with('spells', 'name', name)
    if not sp then return false, 'unknown name' end
    if table.contains(buffs, 6) or table.contains(buffs, 29) then return false, 'silenced' end
    if not spell_level_ok(sp, player) then return false, 'job level' end
    if not pet_action_ready(name, player) then return false, 'not known / recast / MP' end
    if not pet_entry_ok(entry, player) then return false, 'HP / MP condition' end
    return true, '/ma'
end

-- Fire the first ready backup_pull entry at t. Returns true if one fired.
function try_backup_pull(t, dist, ps, label)
    if hs_hold_active() then return false end   -- v4.41
    local list = current_config and current_config.backup_pull
    if type(list) ~= 'table' or #list == 0 then return false end
    if autoattack_type ~= 'pull' then return false end
    if not t or not t.id or not t.hpp or t.hpp <= 0 or not dist then return false end
    if ps and ps.last_pull and ps.last_pull > 0 and (os.clock() - ps.last_pull) < PULL_APPROACH_WAIT then return false end
    local player = windower.ffxi.get_player()
    if not player or not player.vitals then return false end
    local mr = 3.0 + (t.model_size or 2.0)
    if ps and ps.id == t.id and ps.reach and ps.reach < mr then mr = ps.reach end
    if dist <= mr then return false end                      -- in melee range: never pull
    local edge = dist - (t.model_size or 2.0)
    local why = {}
    for _, e in ipairs(list) do
        if type(e) == 'table' and e.name then
            local lim = tonumber(e.max_dist) or 4.5
            local ok, pre = backup_pull_ready(e, player)
            if ok and edge > lim then
                ok = false
                pre = string.format('%.1f', edge) .. 'y from edge > ' .. string.format('%.1f', lim) .. 'y'
            end
            if ok and pre == '/ma' and ninja_tools[e.name] and not check_ninja_tools(e.name) then
                ok = false; pre = 'no ninja tools'
            end
            if ok then
                debug_msg('BACKUP-PULL (' .. label .. '): ' .. (t.name or '?') .. ' at ' ..
                          string.format('%.1f', dist) .. 'y -- main pull not ready, using ' .. e.name .. '.')
                face('f')
                coroutine.sleep(0.3)
                local t2 = windower.ffxi.get_mob_by_target('t')
                if not t2 or t2.id ~= t.id or not t2.hpp or t2.hpp <= 0 then return true end
                if pre == '/ra' then
                    cmd('input /ra <t>')
                else
                    cmd('input ' .. pre .. ' "' .. e.name .. '" <t>')
                end
                if pre == '/ja' or pre == '/pet' then
                    ability_last_used[e.name] = os.time()
                    last_ability_time = os.clock()   -- ring equip lockout
                end
                if ps then ps.last_pull = os.clock(); ps.pulls = (ps.pulls or 0) + 1 end
                coroutine.sleep((pre == '/ma' or pre == '/ra') and 3.0 or 1.5)
                return true
            end
            why[#why + 1] = e.name .. ': ' .. tostring(pre)
        end
    end
    if (os.clock() - backup_pull_log) >= BACKUP_PULL_LOG_EVERY then
        backup_pull_log = os.clock()
        debug_msg('BACKUP-PULL (' .. label .. '): nothing ready for ' .. (t.name or '?') .. ' at ' ..
                  string.format('%.1f', dist) .. 'y -- ' .. table.concat(why, '; ') .. '.')
    end
    return false
end

-- v4.02: Close mob hitting you / a Trust that we are not hitting: re-pull it
-- with Provoke. Provoke on cooldown -> wait for it (logged every 5s) instead of
-- firing it into "Unable to use job ability" and burning re-pull attempts.
-- Returns true if handled (Provoked, or waiting on Provoke); false when you
-- have no Provoke (caller falls back to its normal pull_command, never limited).
close_fight_log = 0
function close_fight_repull(t, dist, ps, why)
    local left = provoke_wait_left()
    if not left then return false end
    if dist > PROVOKE_PULL_RANGE then return false end
    if left <= 0 then
        debug_msg('CLOSE-REPULL: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                  'y is hitting ' .. why .. ' and we are not hitting it -- Provoke.')
        if try_provoke_pull(t) then
            ps.last_pull = os.clock(); ps.pulls = ps.pulls + 1
        end
        return true
    end
    -- v4.17: Provoke on recast and the mob is just outside melee range: backup pull
    if try_backup_pull(t, dist, ps, 'close fight') then return true end
    if (os.clock() - close_fight_log) >= 5 then
        debug_msg('CLOSE-REPULL: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                  'y is hitting ' .. why .. ' -- Provoke ready in ' .. string.format('%.0f', left) ..
                  's, waiting (no blacklist).')
        close_fight_log = os.clock()
    end
    return true
end

-- v4.01: True if the mob is fighting a Trust / party member (NOT you) in that
-- member's melee range -- i.e. it is part of our fight and is not coming to us.
-- Such a mob is never blacklisted for "no contact"; we step in to it instead.
-- v4.02: also true if it has actually hit a Trust in the last MOB_HIT_WINDOW s.
function mob_fighting_trust(t)
    if mob_hit_victim(t) == 'party' then return true end
    if not t or not t.x or not t.y then return false end
    local v = pull_in_victim(t)
    if not v or not v.x or not v.y then return false end
    local me = windower.ffxi.get_player()
    if me and me.index and v.index == me.index then return false end
    local dx, dy = v.x - t.x, v.y - t.y
    return math.sqrt(dx * dx + dy * dy) <= 3.0 + (t.model_size or 2.0) + 1.0
end

-- v4.01: Step-in. Walk toward the target in a short burst (<= APPROACH_STEP_TIME)
-- until it is within stop_at yalms, then stop and face it. Only for mobs within
-- APPROACH_MAX_DIST. Used when a mob sits just outside your reach (game says
-- "out of range") or is tanked by a Trust a few yalms away.
APPROACH_ENABLED   = false
APPROACH_MAX_DIST  = 10.0
APPROACH_STEP_TIME = 1.5
APPROACH_COOLDOWN  = 1.0
approach_last      = 0
-- v4.34: a mob in "melee range" that is hitting YOU while none of your swings
-- land gets a short step in after STEP_IN_HIT_WAIT seconds, even with
-- APPROACH_ENABLED = false (2026-11-13 death: a bat sat at 3.8y for 80s).
STEP_IN_WHEN_HIT   = true
-- v4.38: STEP-IN no longer fires on a timer. It needs TROUBLE first: the mob
-- has hit you STEP_IN_MOB_HITS times (attack rounds on you, hit or miss) with
-- no melee round of yours landing on it, OR the game said "out of range" /
-- "Unable to see" / "You cannot see" / "unable to reach" about it. Then
-- Provoke goes first; only if a Provoke landed STEP_IN_AFTER_PROVOKE s ago and
-- you still aren't hitting (or Provoke can't fire within STEP_IN_PROVOKE_MAXWAIT
-- s of the trouble, or you have no /WAR) do you take the step in.
STEP_IN_MOB_HITS        = 4
STEP_IN_AFTER_PROVOKE   = 3.0
STEP_IN_PROVOKE_MAXWAIT = 8.0
STEP_IN_MSG_WINDOW      = 3.0    -- s a trouble message stays fresh
-- v4.75: stepping in is an EMERGENCY (Mark, 11-18). On trouble: Provoke first,
-- then a ranged attack; step in only when the mob keeps hitting you
-- (STEP_IN_MOB_HITS rounds, none of yours landing) after those, or nothing
-- fixed it in STEP_IN_EMERGENCY_WAIT s. "Out of range" alone (a mob still
-- walking in) never steps in. false = v4.74 behaviour.
STEP_IN_EMERGENCY      = true
STEP_IN_EMERGENCY_WAIT = 12.0
melee_msg    = {id = 0, time = 0, kind = ''}   -- v4.38: last cant-see / unable-to-reach on our target
provoke_last = {id = 0, time = 0}              -- v4.38: last CONFIRMED Provoke and on which mob
-- v4.35: engaged, in melee range, but no melee ROUND (weapon skills don't
-- count) on the target for REENGAGE_WAIT seconds -> /attack off, re-target,
-- /attack on. 2026-11-13 20:04 death: 2 min at 1.2y, WSs landed, zero melee
-- rounds -- the swings weren't going to the mob in front of us.
REENGAGE_WHEN_STUCK = true
REENGAGE_WAIT       = 15.0
-- v4.37: after a STEP-IN, go back to the exact spot you stood on before it,
-- as soon as a melee round lands on that mob (or it dies / you switch
-- targets). Once per mob (STEP_IN_RETURN_MAX); a mob that still can't be hit
-- after you went back gets stepped in to again and you stay there.
STEP_IN_RETURN      = true
STEP_IN_RETURN_MAX  = 1      -- returns per mob
STEP_IN_RETURN_TOL  = 0.35   -- yalms: close enough to the old spot
STEP_IN_RETURN_TIME = 4.0    -- s: longest run back
STEP_IN_RETURN_WAIT = 60.0   -- s: no hit landed in this long -> forget the spot
-- v4.81: the once-per-mob limit was kept by mob ID forever, but bats respawn
-- with the same IDs (17555777-84 at King Ranperre's Tomb): after one return
-- per ID, every later step-in saved no spot and never stepped back.
STEP_IN_RETURN_FORGET = 30.0 -- s after a return before that mob ID gets another one
step_home = {active = false, id = 0, x = 0, y = 0, at = 0, mob = '', returns = {}}
-- v4.37: engaged, in melee range, and no melee round on it yet (or none in
-- MELEE_HIT_WAIT s): keep Provoking every time Provoke is ready (PULL mode,
-- WAR main/sub). v3.97 never Provoked in melee range.
-- v4.40: OFF. Provoke is held for pulls / re-pulls (and the hot-switch
-- Provoke below) so it is ready for the next mob. Provoke listed in your
-- job's `abilities` still fires as configured. With this off, STEP-IN no
-- longer waits for a Provoke before stepping in.
MELEE_PROVOKE_NO_HIT = false
-- v4.40: HOT-SWITCH -> Provoke the new mob right away (PULL mode, WAR main/sub,
-- Provoke ready, mob within 17.8y, melee range or not). Tried for
-- HOT_SWITCH_PROVOKE_WINDOW s after the switch (fires if Provoke comes off
-- recast inside that window), then normal pull logic only.
HOT_SWITCH_PROVOKE        = true
HOT_SWITCH_PROVOKE_WINDOW = 6.0
-- v4.56: no hot-switch Provoke until this many s after our last /ws. A WS that
-- kills the mob still has its animation running when the switch happens, and
-- the game drops a Provoke sent inside it (logs 11-15..17: sent 1.5-3.0s after
-- the /ws = 1,728 of 1,782 failed; 3.25s+ = 0 of ~600 failed).
HOT_SWITCH_PROVOKE_WS_GAP = 3.5
hs_provoke = {id = 0, until_t = 0}
-- v4.41: HOT-SWITCH HOLD. After a hot-switch (and its Provoke) do NOTHING else
-- -- no WS, JAs, magic, rings/food, pet, heals, PullNext, closer-switch or
-- backup pull -- until one of YOUR melee rounds lands on the new mob, so the
-- Trusts and party engage it. Only the pull logic (hot-switch Provoke, facing,
-- re-pull / step-in) keeps running. Released early by: target changed or
-- died, HOT_SWITCH_HOLD_MAX s with no melee round, or your HP below
-- HOT_SWITCH_HOLD_HPP %.
HOT_SWITCH_HOLD     = true
HOT_SWITCH_HOLD_MAX = 15.0
HOT_SWITCH_HOLD_HPP = 40
-- v5.00: also released (after 1s) once every party PLAYER in range is on the mob --
-- engaged on it or has acted on it (Mark, 11-21: OK'd). Solo with Trusts: unchanged.
HOT_SWITCH_HOLD_PARTY = true
hs_hold = {id = 0, since = 0, logged = false}
function hs_hold_active()
    if hs_hold.id == 0 then return false end
    local now = os.clock()
    local t   = windower.ffxi.get_mob_by_target('t')
    local me  = windower.ffxi.get_player()
    local why = nil
    if melee_round.id == hs_hold.id and melee_round.time >= hs_hold.since then
        why = 'first melee round landed'
    elseif HOT_SWITCH_HOLD_PARTY and (now - hs_hold.since) >= 1.0 and party_all_on and party_all_on(hs_hold.id, hs_hold.since) then
        why = 'whole party on it'   -- v5.00
    elseif (not t or t.id ~= hs_hold.id or not t.hpp or t.hpp <= 0) and (now - hs_hold.since) > 1.5 then
        why = 'target changed'
    elseif (now - hs_hold.since) >= HOT_SWITCH_HOLD_MAX then
        why = 'no melee round in ' .. string.format('%.0f', HOT_SWITCH_HOLD_MAX) .. 's'
    elseif me and me.vitals and me.vitals.hpp and me.vitals.hpp < HOT_SWITCH_HOLD_HPP then
        why = 'your HP ' .. me.vitals.hpp .. '%'
    end
    if why then
        debug_msg('HOT-SWITCH-HOLD: released after ' .. string.format('%.1f', now - hs_hold.since) .. 's -- ' .. why .. '.')
        hs_hold.id = 0
        return false
    end
    if not hs_hold.logged then
        hs_hold.logged = true
        info_msg('HOT-SWITCH-HOLD: ' .. ((t and t.name) or '?') .. ' -- no other actions until your first melee round lands.')
    end
    return true
end
-- v4.22: move_in_range engine. move_toward_mob(t, stop_at, engaged) runs
-- toward t for up to MOVE_BURST seconds per loop tick, then stops (so trusts,
-- heals and the loop's checks still run) and asks for a quick next tick.
--   Stall detection: every MOVE_STUCK_CHECK s, < MOVE_STUCK_MIN yalms moved
--   (X/Y) = stuck; MOVE_NOPROGRESS s without getting 1y closer = stuck too
--   (circling / sliding along a slope -- Z is tracked for that).
--   Smart detour: new obstacle -> turn MOVE_DETOUR_ANGLES[1] to the side that
--   worked last time. Stuck again near the same spot -> same side, wider
--   angle (follows the obstacle edge); out of angles -> back up, then try the
--   other side. MOVE_GIVEUP_STUCKS stalls, MOVE_MAX_TIME s, or a big height
--   gap (MOVE_Z_LIMIT, cliff) with stalls -> give up: blacklist_unreachable().
-- Returns true while it is (still) moving this mob, false when in range,
-- gone, given up or not allowed.
MOVE_STOP_MARGIN   = 1.5    -- stop this far inside pull range
MOVE_SCAN_DIST     = 50.0   -- far scan radius when nothing is in pull range (v4.26: 50 = client entity range; mobs past ~50y aren't in the mob array)
MOVE_BURST         = 2.0
MOVE_STUCK_CHECK   = 0.5
MOVE_STUCK_MIN     = 0.5
MOVE_NOPROGRESS    = 4.0
MOVE_GIVEUP_STUCKS = 8
MOVE_MAX_TIME      = 30.0
MOVE_Z_LIMIT       = 8.0
MOVE_DETOUR_ANGLES = {50, 80, 110, 140}   -- degrees off the direct line
MOVE_DETOUR_TIME   = 0.9
MOVE_BACKUP_TIME   = 0.7
mv = {id = 0, active = false, side = 1}
MOVE_TARGET_STOP = 1.5    -- v4.28: 'target' mode stop distance (yalms, center to center)
-- v4.28: 'off' | 'pull' | 'provoke' | 'melee' | 'target' | 'custom'
function move_mode()
    local m = move_to_target
    if m == nil or m == false then return 'off' end
    if m == true then return 'pull' end
    if type(m) == 'number' then return (m > 0) and 'custom' or 'off' end
    m = tostring(m):lower()
    if m == 'pull' or m == 'provoke' or m == 'melee' or m == 'target' then return m end
    local n = tonumber(m)
    if n and n > 0 then move_to_target = n; return 'custom' end
    return 'off'
end
local function mv_reset(id, d, me)
    mv.id = id; mv.start = os.clock(); mv.stucks = 0; mv.level = 0
    mv.detour_until = 0; mv.detour_off = 0; mv.back_until = 0
    mv.best_d = d; mv.best_t = os.clock(); mv.chk_t = os.clock()
    mv.lx, mv.ly, mv.lz = me.x, me.y, me.z or 0
    mv.pts = {}; mv.logged = false
end
local function mv_giveup(m, why)
    windower.ffxi.run(false)
    mv.active = false
    local dur, n = blacklist_unreachable(m.id)
    info_msg('MOVE-GIVEUP: ' .. tostring(m.name) .. ' (ID ' .. m.id .. ') -- ' .. why ..
              '. Blacklisting ' .. tostring(dur) .. 's (strike ' .. tostring(n) .. ').')
    mv.id = 0
    return false
end
local function mv_stuck(me, m, d, why)
    mv.stucks = mv.stucks + 1
    local x, y = me.x, me.y
    local near = nil
    for _, pt in ipairs(mv.pts) do
        local dx, dy = pt.x - x, pt.y - y
        if dx * dx + dy * dy <= 4.0 then near = pt end   -- within 2y of an earlier stall
    end
    if near then
        mv.level = near.level + 1            -- same obstacle: widen, same side
        mv.side  = near.side
    else
        mv.level = 1                         -- new obstacle: last good side
    end
    if mv.level > #MOVE_DETOUR_ANGLES then
        mv.back_until = os.clock() + MOVE_BACKUP_TIME
        mv.side  = -mv.side
        mv.level = 2
        debug_msg(string.format('MOVE-BACKUP: %s stall %d at (%.1f, %.1f) -- backing up, then trying the %s side.',
            why, mv.stucks, x, y, mv.side > 0 and 'left' or 'right'))
    end
    local ang = MOVE_DETOUR_ANGLES[mv.level]
    mv.detour_off   = math.rad(ang) * mv.side
    mv.detour_until = math.max(mv.back_until, os.clock()) + MOVE_DETOUR_TIME * (1 + 0.25 * (mv.level - 1))
    mv.pts[#mv.pts + 1] = {x = x, y = y, side = mv.side, level = mv.level}
    if #mv.pts > 12 then table.remove(mv.pts, 1) end
    debug_msg(string.format('MOVE-STUCK (%s) %d/%d at (%.1f, %.1f, z %.1f), %.1fy from %s -- detour %s %d deg.',
        why, mv.stucks, MOVE_GIVEUP_STUCKS, x, y, me.z or 0, d, tostring(m.name),
        mv.side > 0 and 'left' or 'right', ang))
    mv.best_t = os.clock()
end
function move_toward_mob(t, stop_at, engaged)
    if move_mode() == 'off' or autoattack_type ~= 'pull' or not t or not t.id then return false end
    local me0 = windower.ffxi.get_mob_by_target('me')
    local m0  = windower.ffxi.get_mob_by_id(t.id)
    if not me0 or not me0.x or not m0 or not m0.x then return false end
    local d0 = m0.distance and m0.distance:sqrt() or 999
    if d0 <= stop_at then return false end
    -- v4.26: also restart when this mob's last run ended 3s+ ago (a proximity
    -- scan / engage can take over mid-run without MOVE-OK clearing mv.id, and
    -- the old mv.start then made MOVE-GIVEUP fire on the very next run).
    if mv.id ~= t.id or (os.clock() - (mv.last or 0)) > 3 then mv_reset(t.id, d0, me0) end
    if not mv.logged then
        mv.logged = true
        debug_msg(string.format('MOVE: running to %s (%.1fy -> %.1fy%s).', tostring(m0.name), d0, stop_at,
            engaged and ', engaged' or ''))
    end
    mv.active = true
    local burst_end = os.clock() + MOVE_BURST
    local result = true
    while true do
        local now = os.clock()
        local p  = windower.ffxi.get_player()
        local me = windower.ffxi.get_mob_by_target('me')
        local m  = windower.ffxi.get_mob_by_id(t.id)
        if not auto_attack or aa_stale_loop() or not p or not me or not me.x then result = false; break end  -- v4.43
        if not m or not m.x or not m.hpp or m.hpp <= 0 or not m.valid_target then
            debug_msg('MOVE: ' .. tostring(t.name) .. ' gone or dead -- stopping.')
            mv.id = 0; result = false; break
        end
        if m.claim_id and m.claim_id ~= 0 and m.claim_id ~= p.id and not is_party_entity_id(m.claim_id)
           and not is_purple_excluded(m.name) then
            debug_msg('MOVE: ' .. tostring(m.name) .. ' was claimed by someone else -- stopping.')
            mv.id = 0; result = false; break
        end
        local hpp = (p.vitals and p.vitals.hpp) or 100
        if LOW_HP_NO_PULL_PCT > 0 and hpp < LOW_HP_NO_PULL_PCT then
            debug_msg('MOVE: HP ' .. hpp .. '% -- not running to a far mob.')
            result = false; break
        end
        local d = m.distance and m.distance:sqrt() or 999
        if d <= stop_at then
            debug_msg(string.format('MOVE-OK: %s in range at %.1fy after %.1fs (%d stall%s).', tostring(m.name), d,
                now - mv.start, mv.stucks, mv.stucks == 1 and '' or 's'))
            mv.id = 0; result = false; break
        end
        if (now - mv.start) > MOVE_MAX_TIME then
            result = mv_giveup(m, string.format('still %.1fy away after %.0fs', d, MOVE_MAX_TIME)); break
        end
        -- progress toward the mob
        if d < mv.best_d - 1.0 then
            mv.best_d = d; mv.best_t = now
            if pull_in.id == m.id then pull_in.since = now end   -- moving in counts as pulling in
            if now >= mv.detour_until and mv.level > 0 then mv.level = 0 end   -- detour worked
        end
        -- stall checks
        if (now - mv.chk_t) >= MOVE_STUCK_CHECK then
            local dx, dy = me.x - mv.lx, me.y - mv.ly
            local moved = math.sqrt(dx * dx + dy * dy)
            local dz = math.abs((me.z or 0) - (mv.lz or 0))
            mv.lx, mv.ly, mv.lz, mv.chk_t = me.x, me.y, me.z or 0, now
            if now >= mv.back_until then
                if moved < MOVE_STUCK_MIN then
                    mv_stuck(me, m, d, dz > 0.3 and 'blocked, slope' or 'blocked')
                elseif (now - mv.best_t) >= MOVE_NOPROGRESS and now >= mv.detour_until then
                    mv_stuck(me, m, d, 'no progress')
                end
            end
            if mv.stucks >= MOVE_GIVEUP_STUCKS then
                result = mv_giveup(m, mv.stucks .. ' stalls'); break
            end
            local gap = math.abs((m.z or 0) - (me.z or 0))
            if gap > MOVE_Z_LIMIT and mv.stucks >= 3 then
                result = mv_giveup(m, string.format('%.1fy height difference (cliff / other level)', gap)); break
            end
        end
        if now >= burst_end then break end
        -- steer
        local h = math.atan2(m.y - me.y, m.x - me.x)
        if now < mv.back_until then
            h = h + math.pi
        elseif now < mv.detour_until then
            h = h + mv.detour_off
        end
        windower.ffxi.run(math.cos(h), math.sin(h))
        coroutine.sleep(0.1)
    end
    windower.ffxi.run(false)
    mv.last = os.clock()  -- v4.26
    if not result then mv.active = false end
    local mf = windower.ffxi.get_mob_by_id(t.id)
    if mf and mf.hpp and mf.hpp > 0 then face_mob_direct(mf) end
    if result then aa_quick_next = true end   -- keep moving next tick without a 1s pause
    return result
end
-- v4.22: nothing in pull range -> nearest valid mob out to MOVE_SCAN_DIST.
function move_far_pick(scan_all, party_ids, pull_dist)
    if move_mode() == 'off' or autoattack_type ~= 'pull' or not scan_all then return nil end
    local best, best_d = nil, MOVE_SCAN_DIST + 1
    for _, m in pairs(scan_all) do
        if m and m.spawn_type == 16 and m.hpp and m.hpp > 0 and m.valid_target and m.distance
           and is_mob_whitelisted(m.name)
           and not is_mob_name_blacklisted(m.name, m.id)
           and not is_cant_target_blocked(m.id)
           and (m.claim_id == 0 or (party_ids and party_ids[m.claim_id]) or is_purple_excluded(m.name)) then
            local d = m.distance:sqrt()
            if d > pull_dist and d < best_d then best, best_d = m, d end
        end
    end
    if not best then return nil end
    if stale_pull_id == best.id then stale_pull_id = 0 end   -- a long run is not a stale pull
    if mv.id ~= best.id then
        debug_msg(string.format('MOVE-SCAN: nothing in pull range -- %s at %.1fy.', tostring(best.name), best_d))
    end
    set_target(best.id)
    return best
end
windower.register_event('unload', function()
    if mv and mv.active then windower.ffxi.run(false) end
    if ds_leave then pcall(ds_leave, 'unloaded') end  -- v4.32: give GearSwap its slots back
    pcall(gsc_k_save)   -- v4.90: keep what this session learned
    aa_log_close()  -- v4.25
end)

function step_toward(t, stop_at, force)
    if not (APPROACH_ENABLED or force) or not t or not t.id then return false end
    if (os.clock() - approach_last) < APPROACH_COOLDOWN then return true end
    local d0 = t.distance and t.distance:sqrt() or 999
    if d0 > APPROACH_MAX_DIST or d0 <= stop_at then return false end
    debug_msg('APPROACH: stepping in to ' .. (t.name or '?') .. ' (' ..
              string.format('%.1f', d0) .. 'y -> ' .. string.format('%.1f', stop_at) .. 'y).')
    local t0 = os.clock()
    while (os.clock() - t0) < APPROACH_STEP_TIME do
        local m  = windower.ffxi.get_mob_by_id(t.id)
        local me = windower.ffxi.get_mob_by_target('me')
        if not m or not me or not m.hpp or m.hpp <= 0 or not m.x or not me.x then break end
        local d = m.distance and m.distance:sqrt() or 999
        if d <= stop_at or d > APPROACH_MAX_DIST then break end
        windower.ffxi.run(m.x - me.x, m.y - me.y)
        coroutine.sleep(0.1)
    end
    windower.ffxi.run(false)
    approach_last = os.clock()
    face('f')
    return true
end

-- v4.37: remember where we stood before a STEP-IN (first one on this mob only,
-- so a second step-in still returns to the original spot). Returns true if a
-- new spot was recorded.
function step_home_mark(t)
    if not STEP_IN_RETURN or not t or not t.id then return false end
    if step_home.active and step_home.id == t.id then return false end
    local _r = step_home.returns[t.id]   -- v4.81: {n, at}
    if type(_r) == 'table' and os.clock() - _r.at < STEP_IN_RETURN_FORGET and _r.n >= STEP_IN_RETURN_MAX then return false end
    local me = windower.ffxi.get_mob_by_target('me')
    if not me or not me.x then return false end
    step_home.active = true; step_home.id = t.id; step_home.mob = t.name or '?'
    step_home.x = me.x; step_home.y = me.y; step_home.at = os.clock()
    debug_msg(string.format('STEP-HOME: spot saved (%.2f, %.2f) before stepping in to %s.',
        me.x, me.y, step_home.mob))
    return true
end

-- v4.37: run back to the saved spot. Fine 0.05s steering so it stops on the spot.
function step_home_go(why)
    local hx, hy, id = step_home.x, step_home.y, step_home.id
    step_home.active = false
    local _r = step_home.returns[id]   -- v4.81
    if type(_r) ~= 'table' or os.clock() - _r.at >= STEP_IN_RETURN_FORGET then _r = {n = 0} end
    _r.n, _r.at = _r.n + 1, os.clock()
    step_home.returns[id] = _r
    local me = windower.ffxi.get_mob_by_target('me')
    if not me or not me.x then return end
    local d0 = math.sqrt((hx - me.x) ^ 2 + (hy - me.y) ^ 2)
    if d0 <= STEP_IN_RETURN_TOL then
        debug_msg(string.format('STEP-BACK: %s -- already on the old spot (%.2fy).', why, d0))
        return
    end
    info_msg(string.format('STEP-BACK: %s -- moving back %.1fy to where you stood before the step-in.', why, d0))
    local t0, chk_t = os.clock(), os.clock()
    local lx, ly = me.x, me.y
    local d = d0
    while (os.clock() - t0) < STEP_IN_RETURN_TIME do
        me = windower.ffxi.get_mob_by_target('me')
        local p = windower.ffxi.get_player()
        if not auto_attack or not me or not me.x or not p or (p.vitals and p.vitals.hp == 0) then break end
        local dx, dy = hx - me.x, hy - me.y
        d = math.sqrt(dx * dx + dy * dy)
        if d <= STEP_IN_RETURN_TOL then break end
        if (os.clock() - chk_t) >= 0.6 then
            local mx, my = me.x - lx, me.y - ly
            if math.sqrt(mx * mx + my * my) < 0.15 then
                debug_msg(string.format('STEP-BACK: blocked %.2fy from the spot -- stopping here.', d))
                break
            end
            lx, ly, chk_t = me.x, me.y, os.clock()
        end
        windower.ffxi.run(dx, dy)
        coroutine.sleep(0.05)
    end
    windower.ffxi.run(false)
    me = windower.ffxi.get_mob_by_target('me')
    if me and me.x then d = math.sqrt((hx - me.x) ^ 2 + (hy - me.y) ^ 2) end
    debug_msg(string.format('STEP-BACK: done, %.2fy from the saved spot.', d))
    local t = windower.ffxi.get_mob_by_target('t')
    if t and t.hpp and t.hpp > 0 then face_mob_direct(t) end
    pull_state.melee_face = os.clock()
end

-- =========================================================================
-- v4.75: FIGHT ANCHOR (Mark, 2026-11-18: "When Fight command is started, log
-- the start position of the leader, and keep the leader there even if he
-- moves a little to engage a mob.") aa fight on the leader saves the spot;
-- in PULL mode the leader runs back to it whenever it is more than
-- ANCHOR_TOL yalms away -- between mobs always, while engaged only if the
-- mob can still be hit from the spot (so it never walks off a mob). Party
-- members stack on the leader, so they stay on the spot too.
-- Cleared by //aa stop, aa stop and zoning. Globals on purpose.
-- =========================================================================
ANCHOR_TOL      = 1.0    -- yalms from the fight spot that count as "on it"
ANCHOR_COOLDOWN = 3.0    -- s between two returns
ANCHOR_RUN_TIME = 6.0    -- s: longest run back
AA_ANCHOR       = nil    -- {x, y, zone}
anchor_last     = 0
-- v4.78: one POSITION line a minute while the spot is set: the leader's
-- distance from it and each player's distance from the leader (chat when
-- anyone is off the stack, log file otherwise)
ANCHOR_REPORT_SECS = 60
ANCHOR_FAR         = 4.0    -- yalms: a player farther than this from the leader is "not stacked"
anchor_report_at   = 0
function anchor_report(me, d)
    local now = os.clock()
    if now - anchor_report_at < ANCHOR_REPORT_SECS then return end
    anchor_report_at = now
    local party = windower.ffxi.get_party()
    local parts, far = {}, 0
    local _info = windower.ffxi.get_info()   -- v4.94: members in another zone aren't "not stacked"
    local _z = _info and _info.zone
    for k = 1, 5 do
        local m = party and party['p' .. k]
        if type(m) == 'table' and m.name then
            local mob = m.mob
            if m.zone and _z and m.zone ~= _z then
                parts[#parts + 1] = m.name .. ' in another zone'
            elseif mob and mob.is_npc then
                -- a Trust: not reported
            elseif mob and mob.x then
                local dm = math.sqrt((mob.x - me.x) ^ 2 + (mob.y - me.y) ^ 2)
                parts[#parts + 1] = string.format('%s %.1fy', m.name, dm)
                if dm > ANCHOR_FAR then far = far + 1 end
            else
                parts[#parts + 1] = m.name .. ' not in view'
                far = far + 1
            end
        end
    end
    local line = string.format('POSITION: leader %.1fy from the fight spot; %s', d,
        #parts > 0 and table.concat(parts, ', ') or 'no other players')
    if far > 0 or d > 3 then info_msg(line .. ' -- NOT STACKED') else debug_msg(line) end
end
-- v4.97: ENGAGE TIMING (leader, PULL mode). Mark, 11-21: "why is it taking
-- so long for other party members to engage sometimes?" -- only the leader's
-- box is reachable, so the leader times it: from switching to a new mob until
-- each party player (not Trusts, same zone) is engaged on that mob
-- (status 1, target_index = the mob). One ENGAGE-LAG line per mob (log file),
-- an ENGAGE summary in chat every ENGAGE_SUM_SECS.
ENGAGE_SUM_SECS = 600
ENGAGE_GIVEUP   = 60     -- s: still not on it -> "never"
ENGAGE_LAG   = {mob = 0}
ENGAGE_STATS = {}        -- [name] = {lags = {...}, never = n}
ENGAGE_SLOW, ENGAGE_SLOW_AWAY = 0, 0   -- v4.99: slow mobs / of them still on the way in
ENGAGE_AWAY = 6         -- v4.99: y from the leader = still on its way in
engage_sum_at = nil
local function _eng_players()
    local out = {}
    local party = windower.ffxi.get_party()
    local info = windower.ffxi.get_info()
    local z = info and info.zone
    for k = 1, 5 do
        local m = party and party['p' .. k]
        if type(m) == 'table' and m.name and m.mob and not m.mob.is_npc and (not m.zone or not z or m.zone == z) then
            out[#out + 1] = m
        end
    end
    return out
end
function engage_lag_flush()
    local E = ENGAGE_LAG
    if not E.mob or E.mob == 0 then return end
    local parts = {}
    local names = {}
    for n in pairs(E.seen or {}) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        local st = ENGAGE_STATS[n] or {lags = {}, never = 0}
        ENGAGE_STATS[n] = st
        local lag = E.got[n]
        -- v5.01 (debug 2): how they got on it, and where they were at 3s when slow
        local _x = ''
        if (debug_level or 0) >= 2 then
            local bits = {}
            if lag and E.how and E.how[n] then bits[#bits + 1] = E.how[n] end
            if E.snap and E.snap[n] and (not lag or lag > PSTAT_SLOW) then bits[#bits + 1] = 'then: ' .. E.snap[n] end
            if #bits > 0 then _x = ' [' .. table.concat(bits, '; ') .. ']' end
        end
        if lag then
            parts[#parts + 1] = string.format('%s %.1fs', n, lag) .. _x
            st.lags[#st.lags + 1] = lag
        else
            parts[#parts + 1] = n .. ' never' .. _x
            st.never = st.never + 1
        end
    end
    if #parts > 0 then
        -- v4.99: slow because the mob was still flying / walking in?
        local _slow = false
        for _, n in ipairs(names) do if not E.got[n] or E.got[n] > PSTAT_SLOW then _slow = true end end
        if _slow then
            ENGAGE_SLOW = ENGAGE_SLOW + 1
            if (E.away or 0) > ENGAGE_AWAY then ENGAGE_SLOW_AWAY = ENGAGE_SLOW_AWAY + 1 end
        end
        debug_msg('ENGAGE-LAG: ' .. tostring(E.name) .. ' -- ' .. table.concat(parts, ', ') ..
                  string.format(' (mob %.1fy from us when picked)', E.away or 0) .. '.')
        -- v5.01 (debug 2): melee rounds each player landed on it (misses count) while it was our target
        if (debug_level or 0) >= 2 and E.rounds and E.t0 then
            local rn, rs = {}, {}
            for n in pairs(E.rounds) do rn[#rn + 1] = n end
            table.sort(rn)
            for _, n in ipairs(rn) do rs[#rs + 1] = n .. ' ' .. E.rounds[n] end
            for _, n in ipairs(names) do if not E.rounds[n] then rs[#rs + 1] = n .. ' 0' end end
            debug_msg(string.format('MELEE-ROUNDS: %s, %.0fs as our target -- %s.', tostring(E.name), os.clock() - E.t0,
                (#rs > 0) and table.concat(rs, ', ') or 'none seen'))
        end
    end
    ENGAGE_LAG = {mob = 0}
end
function engage_summary()
    local names, parts = {}, {}
    for n in pairs(ENGAGE_STATS) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        local st = ENGAGE_STATS[n]
        local l = st.lags
        table.sort(l)
        if #l > 0 or st.never > 0 then
            local med = #l > 0 and l[math.floor((#l + 1) / 2)] or nil
            local p90 = #l > 0 and l[math.max(1, math.ceil(#l * 0.9))] or nil
            parts[#parts + 1] = string.format('%s %s (slowest 10%%: %s, never %d of %d)', n,
                med and string.format('%.1fs', med) or '-', p90 and string.format('%.1fs', p90) or '-',
                st.never, #l + st.never)
        end
    end
    if #parts > 0 then
        info_msg('ENGAGE (last ' .. math.floor(ENGAGE_SUM_SECS / 60) .. ' min, median time to engage the leader\'s mob): ' ..
                 table.concat(parts, '; ') .. '.' ..
                 ((ENGAGE_SLOW > 0) and string.format(' Slow mobs (over %ds): %d, %d of them still %dy+ away when picked.',
                     PSTAT_SLOW, ENGAGE_SLOW, ENGAGE_SLOW_AWAY, ENGAGE_AWAY) or ''))
    end
    ENGAGE_STATS = {}
    ENGAGE_SLOW, ENGAGE_SLOW_AWAY = 0, 0
end
function engage_lag_tick()
    local now = os.clock()
    engage_sum_at = engage_sum_at or now
    if now - engage_sum_at >= ENGAGE_SUM_SECS then engage_sum_at = now; engage_summary() end
    if not auto_attack or autoattack_type ~= 'pull' then return end
    local p = windower.ffxi.get_player()
    local t = windower.ffxi.get_mob_by_target('t')
    if not p or p.status ~= 1 or not t or not t.id or not t.index or (t.hpp or 0) <= 0 then return end
    local E = ENGAGE_LAG
    if E.mob ~= t.id then
        engage_lag_flush()
        E = {mob = t.id, idx = t.index, name = t.name, t0 = now, got = {}, seen = {}, done = false,
             how = {}, snap = {}, rounds = {},   -- v5.01 (debug 2)
             first = {},                         -- v5.03: first action per member
             away = t.distance and math.sqrt(t.distance) or 0}   -- v4.99: how far the mob was when picked
        ENGAGE_LAG = E
    end
    if E.done then return end
    local waiting = 0
    for _, m in ipairs(_eng_players()) do
        E.seen[m.name] = true
        if not E.got[m.name] then
            -- v5.00: engaged on it, or first action on it (melee / WS / spell), whichever comes first
            -- v5.03: the member's FIRST action on the mob, recorded as it happened
            -- (v5.00-5.02 read the latest action whenever the main loop got here,
            -- so a late look reported 18-20s for members who had been swinging)
            local _f = E.first and E.first[m.name]
            if _f then
                E.got[m.name] = math.max(0, _f.t - E.t0)
                if E.how then E.how[m.name] = ENGAGE_HOW[_f.cat] or 'action' end
            elseif m.mob.status == 1 and m.mob.target_index == E.idx then
                E.got[m.name] = now - E.t0
                if E.how then E.how[m.name] = 'engaged' end
            else
                waiting = waiting + 1
                -- v5.01 (debug 2): where a member still not on it was, 3s in
                if E.snap and not E.snap[m.name] and now - E.t0 >= 3 and now - E.t0 < 6 and (debug_level or 0) >= 2 then   -- v5.03: only a real 3-6s look
                    local st = (m.mob.status == 1) and 'engaged' or ((m.mob.status == 0) and 'idle' or ('status ' .. tostring(m.mob.status)))
                    local on = ''
                    if m.mob.status == 1 then
                        on = ((m.mob.target_index or 0) == E.idx and ' on it') or (((m.mob.target_index or 0) > 0) and ' on another mob') or ''
                    end
                    local d = (m.mob.x and t.x) and math.sqrt((m.mob.x - t.x) ^ 2 + (m.mob.y - t.y) ^ 2) or nil
                    E.snap[m.name] = st .. on .. (d and string.format(', %.1fy from it', d) or '') .. string.format(' (%.0fs in)', now - E.t0)
                end
            end
        end
    end
    if waiting == 0 or now - E.t0 > ENGAGE_GIVEUP then E.done = true end
end
-- v5.00: PARTY ACTIONS. The last time each party member acted on a mob (melee
-- round, WS, spell, JA, casting begins), from the action packets this client
-- gets for everyone nearby. Used for the leader's engage timing (first action
-- on the mob, more exact than the other PCs' target fields) and to release the
-- hot-switch hold once the whole party is on the mob.
PARTY_ACT = {}      -- [actor_id] = {mob = mob id, t = os.clock()}
PARTY_ACT_CATS = {[1] = true, [3] = true, [4] = true, [6] = true, [8] = true}
function party_act_note(act)
    local t1 = act.targets and act.targets[1]
    if not t1 or not t1.id or t1.id == act.actor_id or not PARTY_ACT_CATS[act.category] then return end
    local m = windower.ffxi.get_mob_by_id(t1.id)
    if m and m.spawn_type == 16 then PARTY_ACT[act.actor_id] = {mob = t1.id, t = os.clock(), cat = act.category} end
    local E = ENGAGE_LAG
    if E and E.mob == t1.id then
        local who = windower.ffxi.get_mob_by_id(act.actor_id)
        local n = who and who.name
        -- v5.03: first action on the leader's mob, timed when it happens
        if n and E.first and not E.first[n] then E.first[n] = {t = os.clock(), cat = act.category} end
        -- v5.01 (debug 2): melee rounds per player on the leader's mob
        if n and act.category == 1 and E.rounds and (debug_level or 0) >= 2 then E.rounds[n] = (E.rounds[n] or 0) + 1 end
    end
end
ENGAGE_HOW = {[1] = 'swing', [3] = 'WS', [4] = 'spell', [6] = 'JA', [8] = 'casting'}
-- the other real players in the party (no Trusts), same zone, within 30y
function party_players()
    local out, party = {}, windower.ffxi.get_party()
    local info = windower.ffxi.get_info()
    local z = info and info.zone
    for k = 1, 5 do
        local m = party and party['p' .. k]
        if type(m) == 'table' and m.name and m.mob and not m.mob.is_npc and (not m.zone or not z or m.zone == z)
           and m.mob.distance and m.mob.distance <= 900 then
            out[#out + 1] = m
        end
    end
    return out
end
-- true when there is at least one other player and every one of them is engaged
-- on mob_id or has acted on it since (since - 5s)
function party_all_on(mob_id, since)
    local mob = windower.ffxi.get_mob_by_id(mob_id)
    if not mob or not mob.index then return false end
    local list = party_players()
    if #list == 0 then return false end
    for _, m in ipairs(list) do
        local a = PARTY_ACT[m.mob.id]
        local on = (m.mob.status == 1 and m.mob.target_index == mob.index) or
                   (a and a.mob == mob_id and a.t >= (since or 0) - 5)
        if not on then return false end
    end
    return true
end
-- v5.00: TP each party player had at 1000+, last seen (for TP-banded learning)
GSC_TPS = {}
-- v5.04: each player's TP gain per second, from the TP changes the party list shows
GSC_TPR = {}   -- [name] = {tp = last TP, t = when it last changed, rate = TP/s (smoothed)}
function gsc_tp_track()
    local party = windower.ffxi.get_party()
    if not party then return end
    local now = os.clock()
    for k = 0, 5 do
        local m = party['p' .. k]
        if type(m) == 'table' and m.name and (tonumber(m.tp) or 0) >= 1000 then GSC_TPS[m.name] = {tp = m.tp, t = now} end
        local tp = type(m) == 'table' and m.name and tonumber(m.tp)
        if tp then
            local r = GSC_TPR[m.name]
            if not r then
                GSC_TPR[m.name] = {tp = tp, t = now}
            elseif tp > r.tp then
                local dt = now - r.t
                if dt >= 0.5 and dt <= 20 then
                    local inst = (tp - r.tp) / dt
                    r.rate = r.rate and (0.7 * r.rate + 0.3 * inst) or inst
                end
                r.tp, r.t = tp, now
            elseif tp < r.tp then
                r.tp, r.t = tp, now   -- spent on a WS: new baseline
            end
        end
    end
end
-- v5.04: TP a teammate should have by time `at` (nil when we have no rate yet)
function gsc_tp_by(name, tp, at)
    local r = name and GSC_TPR[name]
    if not r or not r.rate then return nil end
    return (tp or 0) + r.rate * math.max(0, at - os.clock())
end
function gsc_tp_at(who)
    local e = who and GSC_TPS[who]
    if e and os.clock() - e.t <= 5 then return e.tp end
    return nil
end
-- v4.99: PARTY STATS / EVENTS / REPORT (Mark, 2026-11-21: the other PCs' log
-- files can't be had, so "use party chat to send updates from the other clients
-- over to shadowhammer and vice versa"). Each AA tells the party, in hidden
-- aa~g lines, what only its own client sees:
--   "aa~g s ..." every PSTAT_SECS (and when asked): its own engage time after the
--      party leader picks a mob (and why, when slower than PSTAT_SLOW), WS landed /
--      missed / interrupted, "out of range" and "can't see" messages, deaths,
--      errors, version, learned samples not yet in the master.
--   "aa~g e <kind> <text>" right away: death, error, watchdog restart.
--   "aa~g q" = send your stats now (//aa report).
-- The leader (PULL mode) writes a PARTY REPORT every PSTAT_SECS from what its own
-- client sees of everyone (WS, skillchains, magic bursts, kills) plus the
-- members' lines. Globals on purpose (main chunk is at the local limit).
PSTAT_SECS = 600
PSTAT_SLOW = 5
PSTAT, REP = nil, nil
PSTAT_PEER = {}          -- [name] = {t = os.clock(), line = "<version> e.. r.. w.."}
PSTAT_EV_AT = {}         -- [kind] = os.clock() of the last event sent
PSTAT_EV_GAP = {death = 30, error = 300, watchdog = 60, stuck = 15}   -- v5.48: stuck
pstat_at, pstat_q_at, pstat_ask_at = nil, -100, -100
function pstat_reset()
    local old = PSTAT
    PSTAT = {land = 0, miss = 0, intr = 0, oor = 0, cant = 0, deaths = 0, errs = 0,
             oorm = 0, oorw = 0, oord = {},   -- v5.01
             tgu = 0, tgl = 0,                -- v5.47: target give-ups / of them on the leader's mob
             lags = {}, never = 0, why = {}, S = old and old.S or nil, cast_at = old and old.cast_at or -100}
end
function rep_reset()
    REP = {t0 = os.clock(), kills = 0, hit = {}, ws = {}, sc = {}, mb = 0, closed = 0, wsn = 0}
end
pstat_reset(); rep_reset()
-- an error from a pcall ("X error: ..." / "X failed: ...") -> counted + one event per 5 min
function pstat_count_err(msg)
    if not PSTAT or msg:find('^PARTY%-') then return end
    local low = msg:lower()
    if low:find(' error: ', 1, true) or low:find('failed: ', 1, true) then
        PSTAT.errs = PSTAT.errs + 1
        pstat_event('error', msg:sub(1, 90))
    end
end
-- what the leader's client sees of the party (and our own WS / casts)
function pstat_on_action(act)
    if not act or not act.actor_id or type(act.targets) ~= 'table' or not PSTAT then return end
    local cat, pl = act.category, windower.ffxi.get_player()
    if not pl then return end
    local me = act.actor_id == pl.id
    if me and cat == 8 then PSTAT.cast_at = os.clock() end
    if me and cat == 7 and act.param == 28787 then PSTAT.intr = PSTAT.intr + 1 end
    local t1 = act.targets[1]
    local a1 = t1 and type(t1.actions) == 'table' and t1.actions[1]
    if cat == 7 and gsc_tp_track then pcall(gsc_tp_track) end   -- v5.00: TP before the WS
    if not t1 or not a1 or not gsc_party_ids()[act.actor_id] then return end
    if party_act_note then party_act_note(act) end   -- v5.00
    if (cat == 1 or cat == 3 or cat == 4) and t1.id and t1.id ~= act.actor_id then REP.hit[t1.id] = true end
    if cat == 3 and GSC_WS_MSG[a1.message] then
        if me then
            if a1.message == 188 then PSTAT.miss = PSTAT.miss + 1 else PSTAT.land = PSTAT.land + 1 end
        end
        local who, r = gsc_player_name(act.actor_id), res.weapon_skills[act.param]
        if who and r and r.en then
            local k = who .. '|' .. r.en
            local e = REP.ws[k] or {n = 0, s = 0, who = who, ws = r.en}
            REP.ws[k] = e
            e.n = e.n + 1
            if a1.message ~= 188 then e.s = e.s + (tonumber(a1.param) or 0) end
            REP.wsn = REP.wsn + 1
        end
        local sc = a1.has_add_effect and GSC_SC_MSG[a1.add_effect_message]
        if sc then
            local e = REP.sc[sc] or {n = 0, s = 0}
            REP.sc[sc] = e
            e.n, e.s = e.n + 1, e.s + (tonumber(a1.add_effect_param) or 0)
            REP.closed = REP.closed + 1
        end
    elseif cat == 4 and a1.message == 252 then
        REP.mb = REP.mb + 1
    end
end
function pstat_kill(dead_id)
    if REP and dead_id and REP.hit[dead_id] then REP.kills = REP.kills + 1; REP.hit[dead_id] = nil end
end
-- the party leader's mob (nil when we are the leader / no party)
function pstat_leader()
    local party, pl = windower.ffxi.get_party(), windower.ffxi.get_player()
    local lid = party and party.party1_leader
    if not lid or not pl or lid == pl.id then return nil end
    return windower.ffxi.get_mob_by_id(lid)
end
function pstat_tick()
    local now = os.clock()
    if gsc_tp_track then pcall(gsc_tp_track) end   -- v5.00
    pstat_at = pstat_at or now
    if now - pstat_at >= PSTAT_SECS then
        pstat_at = now
        if autoattack_type == 'pull' then pcall(rep_print, false) end
        pstat_send('every ' .. math.floor(PSTAT_SECS / 60) .. ' min', 1 + gsc_slot() * 1.5, true)
    end
    local lm, pl = pstat_leader(), windower.ffxi.get_player()
    if not lm or not pl or not PSTAT then return end
    local S = PSTAT.S
    if lm.status == 1 and (lm.target_index or 0) > 0 and (not S or S.idx ~= lm.target_index) then
        local mob = windower.ffxi.get_mob_by_index(lm.target_index)
        if mob and (mob.hpp or 0) > 0 then
            if S and not S.done then PSTAT.never = PSTAT.never + 1 end   -- the leader moved on first
            -- why we may be slow, as things stand when the leader picks it
            local mt, why = windower.ffxi.get_mob_by_target('t'), 'other'
            if pl.vitals and pl.vitals.hp == 0 then why = 'dead'
            elseif pl.status == 1 and mt and mt.index ~= lm.target_index and (mt.hpp or 0) > 0 then why = 'other mob'
            elseif pl.status == 1 then why = 'last mob'   -- v5.00: still engaged on the one that just died
            elseif now - PSTAT.cast_at < 3 then why = 'casting'
            elseif lm.x and mob.x and math.sqrt((lm.x - mob.x) ^ 2 + (lm.y - mob.y) ^ 2) > ENGAGE_AWAY then why = 'mob coming'
            elseif mob.distance and math.sqrt(mob.distance) > 20 then why = 'far'
            elseif not auto_attack then why = 'AA off'
            elseif pl.status == 0 then why = 'idle' end   -- v5.00: was 'other'
            PSTAT.S = {idx = lm.target_index, t0 = now, why = why, done = false}
            S = PSTAT.S
        end
    end
    if S and not S.done then
        local mt = windower.ffxi.get_mob_by_target('t')
        if pl.status == 1 and mt and mt.index == S.idx then
            local lag = now - S.t0
            S.done = true
            PSTAT.lags[#PSTAT.lags + 1] = lag
            if lag > PSTAT_SLOW then PSTAT.why[S.why] = (PSTAT.why[S.why] or 0) + 1 end
        elseif now - S.t0 > ENGAGE_GIVEUP then
            S.done = true
            PSTAT.never = PSTAT.never + 1
            PSTAT.why[S.why] = (PSTAT.why[S.why] or 0) + 1
        end
    end
end
function pstat_news()
    local n = 0
    if not GSC_KO then return 0 end
    for _, kind in ipairs(GSC_KINDS_SYNC) do
        for who, tw in pairs(GSC_KO[kind]) do
            for key in pairs(tw) do n = n + (gsc_k_delta(kind, who, key)) end
        end
    end
    return n
end
-- "aa~g s 4.99 e5.2/12/0 rmob_coming:2 w31/0/1 o4 c2 d0 x0 n120"
function pstat_line()
    local l = {}
    for i, v in ipairs(PSTAT.lags) do l[i] = v end
    table.sort(l)
    local med = #l > 0 and l[math.floor((#l + 1) / 2)] or nil
    local why = {}
    for k, v in pairs(PSTAT.why) do why[#why + 1] = (k:gsub(' ', '_')) .. ':' .. v end
    table.sort(why)
    -- v5.01: + " m<melee>/<ws>/<median y x10>" (older AAs ignore the extra token)
    local od = {}
    for i, v in ipairs(PSTAT.oord or {}) do od[i] = v end
    table.sort(od)
    local omed = #od > 0 and math.floor(od[math.floor((#od + 1) / 2)] * 10 + 0.5) or 0
    -- v5.47: + " t<target give-ups>/<of them on the leader's mob>"
    return string.format('aa~g s %s e%s/%d/%d r%s w%d/%d/%d o%d c%d d%d x%d n%d m%d/%d/%d t%d/%d', tostring(_addon and _addon.version or '?'),
        med and string.format('%.1f', med) or '-', #l, PSTAT.never, (#why > 0) and table.concat(why, ',') or '-',
        PSTAT.land, PSTAT.miss, PSTAT.intr, PSTAT.oor, PSTAT.cant, PSTAT.deaths, PSTAT.errs, pstat_news(),
        PSTAT.oorm or 0, PSTAT.oorw or 0, omed, PSTAT.tgu or 0, PSTAT.tgl or 0)
end
function pstat_human(rest)
    local v, e, r, w, o, c, d, x, n = tostring(rest):match('^(%S+) e(%S+) r(%S+) w(%S+) o(%d+) c(%d+) d(%d+) x(%d+) n(%d+)')
    if not v then return tostring(rest) end
    -- v5.01 (debug 2): out of range split
    local om, ow, od = tostring(rest):match(' m(%d+)/(%d+)/(%d+)')
    if om and (debug_level or 0) >= 2 and tonumber(o) > 0 then
        o = string.format('%s (melee %s / WS %s, median %.1fy)', o, om, ow, tonumber(od) / 10)
    end
    local med, cnt, nev = e:match('^([^/]+)/(%d+)/(%d+)')
    local wl, wm, wi = w:match('^(%d+)/(%d+)/(%d+)')
    local out = string.format('v%s, engage %s (%s mobs, never %s)', v, (med == '-' or not med) and '-' or (med .. 's'), cnt or '?', nev or '?')
    if r ~= '-' then out = out .. ', slow: ' .. r:gsub('_', ' '):gsub(':', ' x'):gsub(',', ', ') end
    local tg, tl = tostring(rest):match(' t(%d+)/(%d+)')   -- v5.47
    return out .. string.format(', WS %s landed / %s missed / %s interrupted, out of range %s, can\'t see %s, deaths %s, errors %s, %s learned not in the master yet',
        tostring(wl), tostring(wm), tostring(wi), o, c, d, x, n) ..
        (tg and string.format(', target give-ups %s (leader\'s mob %s)', tg, tl) or '')
end
function pstat_send(why, delay, reset)
    if not PSTAT then return end
    if not gsc_has_players() then if reset then pstat_reset() end return end
    local line = pstat_line()
    if reset then pstat_reset() end
    coroutine.schedule(function() pcall(gsc_party_line, line) end, delay or 0)
    debug_msg('PARTY-STATS sent (' .. tostring(why) .. '): ' .. pstat_human(line:sub(8)))
end
function pstat_event(kind, text)
    local now = os.clock()
    if now - (PSTAT_EV_AT[kind] or -1e9) < (PSTAT_EV_GAP[kind] or 60) then return end
    PSTAT_EV_AT[kind] = now
    if not gsc_has_players() then return end
    local line = ('aa~g e ' .. tostring(kind) .. ' ' .. tostring(text or '')):gsub('%c', ' '):sub(1, 110)
    coroutine.schedule(function() pcall(gsc_party_line, line) end, 0.5)
end
function pstat_on_stats(sender, rest)
    PSTAT_PEER[sender] = {t = os.clock(), line = rest}
    debug_msg('PARTY-STATS ' .. sender .. ': ' .. pstat_human(rest) .. '.')
end
function pstat_on_event(sender, rest)
    local kind, text = tostring(rest):match('^(%S+)%s*(.*)$')
    info_msg('PARTY-EVENT ' .. tostring(sender) .. ': ' .. tostring(kind) .. ((text and text ~= '') and (' -- ' .. text) or '') .. '.')
end
function pstat_on_query(sender)
    local now = os.clock()
    if now - pstat_q_at < 20 then return end
    pstat_q_at = now
    pstat_send('asked by ' .. tostring(sender), 1 + gsc_slot() * 1.5, false)
end
-- //aa report: ask the party for their stats, print the report ~10s later
function pstat_report()
    local now = os.clock()
    if gsc_has_players() and now - pstat_ask_at > 5 then
        pstat_ask_at = now
        pstat_q_at = now   -- we answer our own question with the report itself
        coroutine.schedule(function() pcall(gsc_party_line, 'aa~g q') end, 0.3)
    end
    windower.add_to_chat(8, '[AutoAttack] Party report in about 10 seconds (asking the party for their stats).')
    coroutine.schedule(function()
        local ok, err = pcall(rep_print, true)
        if not ok then windower.add_to_chat(8, '[AutoAttack] report failed -- ' .. tostring(err)) end
    end, 10)
end
function rep_print(asked)
    if not REP or not PSTAT then return end
    local now = os.clock()
    local mins = math.max((now - REP.t0) / 60, 0.1)
    local L = {}
    L[#L + 1] = string.format('PARTY REPORT (last %.0f min): %d kills (%.0f/h); %d WS, %d closed a skillchain (%d%%); %d magic bursts.',
        mins, REP.kills, REP.kills * 60 / mins, REP.wsn, REP.closed,
        REP.wsn > 0 and math.floor(REP.closed * 100 / REP.wsn + 0.5) or 0, REP.mb)
    local by, names = {}, {}
    for _, e in pairs(REP.ws) do
        if not by[e.who] then by[e.who] = {}; names[#names + 1] = e.who end
        table.insert(by[e.who], e)
    end
    table.sort(names)
    local parts = {}
    for _, n in ipairs(names) do
        table.sort(by[n], function(a, b) return a.n > b.n end)
        local ws = {}
        for _, e in ipairs(by[n]) do ws[#ws + 1] = string.format('%s %d x %.1fk', e.ws, e.n, e.s / e.n / 1000) end
        parts[#parts + 1] = n .. ': ' .. table.concat(ws, ', ')
    end
    if #parts > 0 then L[#L + 1] = 'PARTY REPORT WS -- ' .. table.concat(parts, ' | ') .. '.' end
    local sc = {}
    for k, e in pairs(REP.sc) do sc[#sc + 1] = {k = k, n = e.n, a = e.s / e.n / 1000} end
    table.sort(sc, function(a, b) return a.n > b.n end)
    local sp = {}
    for _, e in ipairs(sc) do sp[#sp + 1] = string.format('%s %d x %.1fk', e.k, e.n, e.a) end
    if #sp > 0 then L[#L + 1] = 'PARTY REPORT skillchains -- ' .. table.concat(sp, ', ') .. '.' end
    local pl = windower.ffxi.get_player()
    if pl then L[#L + 1] = 'PARTY REPORT ' .. pl.name .. ' (this PC) -- ' .. pstat_human(pstat_line():sub(8)) .. '.' end
    local mn = {}
    for n in pairs(PSTAT_PEER) do mn[#mn + 1] = n end
    table.sort(mn)
    for _, n in ipairs(mn) do
        local p = PSTAT_PEER[n]
        if now - p.t < PSTAT_SECS + 60 then
            L[#L + 1] = string.format('PARTY REPORT %s (%ds ago) -- %s.', n, math.floor(now - p.t), pstat_human(p.line))
        end
    end
    for _, l in ipairs(L) do info_msg(l) end
    if not asked then rep_reset() end
end
function aa_set_anchor()
    local me = windower.ffxi.get_mob_by_target('me')
    local info = windower.ffxi.get_info()
    if not me or not me.x then return false end
    AA_ANCHOR = {x = me.x, y = me.y, zone = info and info.zone}
    info_msg(string.format('ANCHOR: fight spot saved (%.2f, %.2f) -- the leader comes back here after any move.', me.x, me.y))
    return true
end
function aa_clear_anchor(why)
    if AA_ANCHOR then
        AA_ANCHOR = nil
        debug_msg('ANCHOR: cleared -- ' .. tostring(why) .. '.')
    end
end
function anchor_check()
    local A = AA_ANCHOR
    if not A or not auto_attack or autoattack_type ~= 'pull' then return end
    local info = windower.ffxi.get_info()
    if info and A.zone and info.zone ~= A.zone then aa_clear_anchor('zoned'); return end
    if step_home.active or (mv and mv.active) then return end
    local now = os.clock()
    if now - anchor_last < ANCHOR_COOLDOWN then return end
    local me = windower.ffxi.get_mob_by_target('me')
    local p = windower.ffxi.get_player()
    if not me or not me.x or not p or (p.vitals and p.vitals.hp == 0) then return end
    local d = math.sqrt((A.x - me.x) ^ 2 + (A.y - me.y) ^ 2)
    anchor_report(me, d)   -- v4.78
    if d <= ANCHOR_TOL then return end
    -- v4.78: not inside our own WS animation -- we can't move then, and 9 of
    -- the "blocked on the way back" stops on 11-18 were right after a WS
    if aa_ws_ago() < 3.0 then return end
    local t = windower.ffxi.get_mob_by_target('t')
    if p.status == 1 and t and t.hpp and t.hpp > 0 and t.x then
        -- engaged: go back if the mob can still be hit from the fight spot,
        -- v4.78: or if it is in our fight -- it follows us back. With hot
        -- switching there was never a moment between mobs, so the leader
        -- only went back 13 times in 3 hours and stayed 1-3y off the spot.
        local reach = 3.0 + (t.model_size or 2.0)
        if math.sqrt((A.x - t.x) ^ 2 + (A.y - t.y) ^ 2) > reach then
            local ids, idx = hs_party_sets(p)
            if not hs_is_hot(t, ids, idx) then return end
        end
    end
    anchor_last = now
    info_msg(string.format('ANCHOR: %.1fy from the fight spot -- moving back.', d))
    -- v4.78: first "blocked" check after 1s, not 0.6s (running takes a moment to start)
    local t0, lx, ly, chk = os.clock(), me.x, me.y, os.clock() + 0.4
    while os.clock() - t0 < ANCHOR_RUN_TIME do
        me = windower.ffxi.get_mob_by_target('me')
        if not auto_attack or not me or not me.x then break end
        local dx, dy = A.x - me.x, A.y - me.y
        if math.sqrt(dx * dx + dy * dy) <= 0.3 then break end
        if os.clock() - chk >= 0.6 then
            if math.sqrt((me.x - lx) ^ 2 + (me.y - ly) ^ 2) < 0.15 then
                debug_msg('ANCHOR: blocked on the way back -- stopping here.')
                break
            end
            lx, ly, chk = me.x, me.y, os.clock()
        end
        aa_loop_beat = os.clock()
        windower.ffxi.run(dx, dy)
        coroutine.sleep(0.05)
    end
    windower.ffxi.run(false)
    t = windower.ffxi.get_mob_by_target('t')
    if t and t.hpp and t.hpp > 0 then face_mob_direct(t) end
    if type(pull_state) == 'table' then pull_state.melee_face = os.clock() end
end

-- v4.37: every loop tick. Go back once the step-in mob is engaged for real
-- (a melee round landed on it), died, or we are on another target.
function step_home_check()
    if not step_home.active then return end
    if not auto_attack or autoattack_type ~= 'pull' then step_home.active = false; return end
    local now = os.clock()
    local m = windower.ffxi.get_mob_by_id(step_home.id)
    if melee_round.id == step_home.id and melee_round.time > step_home.at then
        step_home_go(step_home.mob .. ' engaged (melee round landed)')
    elseif not m or not m.hpp or m.hpp <= 0 or not m.valid_target then
        step_home_go(step_home.mob .. ' is gone')
    else
        local t = windower.ffxi.get_mob_by_target('t')
        if t and t.id and t.id ~= step_home.id then
            step_home_go('switched from ' .. step_home.mob .. ' to ' .. (t.name or '?'))
        elseif (now - step_home.at) > STEP_IN_RETURN_WAIT then
            step_home.active = false
            debug_msg(string.format('STEP-HOME: no hit on %s in %.0fs -- forgetting the saved spot.',
                step_home.mob, STEP_IN_RETURN_WAIT))
        end
    end
end

-- v4.38: in melee range, can't hit. Trouble = STEP_IN_MOB_HITS rounds from the
-- mob on you with none of your melee rounds landing, or a fresh "out of range" /
-- cant-see / unable-to-reach message. Provoke goes first (the MELEE-PROVOKE
-- block right before this call); the step in only follows if that didn't fix it.
-- Returns true if it stepped in.
function melee_trouble_step(t, dist, mr, ps, now, oor_recent)
    if not STEP_IN_WHEN_HIT or not t or not t.id then return false end
    local _mr_t = (melee_round.id == t.id) and melee_round.time or 0
    if (ps.trouble_at or 0) > 0 and _mr_t > ps.trouble_at then
        debug_msg('TROUBLE: ' .. (t.name or '?') .. ' -- melee round landed, fixed.')
        ps.trouble_at = 0
    end
    local h = mob_hits[t.id]
    local n = (h and h.mn) or 0
    local msg = melee_msg.id == t.id and (now - melee_msg.time) < STEP_IN_MSG_WINDOW and melee_msg.time > _mr_t
    local why = nil
    if n >= STEP_IN_MOB_HITS then why = n .. ' hits on you, none from you'
    elseif oor_recent then why = '"out of range"'
    elseif msg then why = '"' .. melee_msg.kind .. '"' end
    if not why and (ps.trouble_at or 0) == 0 then return false end
    if (ps.trouble_at or 0) == 0 then
        ps.trouble_at = now
        info_msg('TROUBLE: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                 'y -- ' .. why .. (STEP_IN_EMERGENCY and '. Provoke / ranged attack first; stepping in only as an emergency.'
                 or (MELEE_PROVOKE_NO_HIT and '. Provoke first, then step in if still not hitting.' or '. Stepping in.')))
    end
    -- v4.75: emergency-only step in
    if STEP_IN_EMERGENCY then
        if dist <= PROVOKE_PULL_RANGE and provoke_pull_ready() and (now - (ps.trouble_prov or 0)) >= 5 then
            ps.trouble_prov = now
            info_msg('TROUBLE: ' .. (t.name or '?') .. ' -- Provoke (no stepping in).')
            if try_provoke_pull(t) then return true end
        end
        if ranged_attack_ready() and (now - (ps.trouble_ra or 0)) >= 5 then
            ps.trouble_ra = now
            info_msg('TROUBLE: ' .. (t.name or '?') .. ' -- ranged attack (no stepping in).')
            cmd('input /ra <t>')
            return true
        end
        local tried = math.max(ps.trouble_prov or 0, ps.trouble_ra or 0)
        local hit_by_it = n >= STEP_IN_MOB_HITS and (tried == 0 or (now - tried) >= STEP_IN_AFTER_PROVOKE)
        if not hit_by_it and (now - ps.trouble_at) < STEP_IN_EMERGENCY_WAIT then return false end
        if not ps.emerg_said or ps.emerg_said ~= ps.trouble_at then
            ps.emerg_said = ps.trouble_at
            info_msg('EMERGENCY STEP-IN: ' .. (t.name or '?') .. ' -- ' .. (hit_by_it and (n .. ' hits on you, none from you')
                     or ('nothing fixed it in ' .. STEP_IN_EMERGENCY_WAIT .. 's')) .. '.')
        end
    end
    -- Provoke first
    local _pl = provoke_wait_left()            -- nil = no /WAR
    if _pl then
        local pv = (provoke_last.id == t.id) and provoke_last.time or 0
        local since = math.max(ps.engaged_at or 0, _mr_t)
        if pv > since then
            if (now - pv) < STEP_IN_AFTER_PROVOKE then return false end   -- give it a moment
        elseif MELEE_PROVOKE_NO_HIT and (now - ps.trouble_at) < STEP_IN_PROVOKE_MAXWAIT then
            return false                                                 -- wait for Provoke (v4.40: only if MELEE-PROVOKE is on)
        end
    end
    local _stop = math.max(1.5, math.min(mr - 1.0, dist - 1.5))
    if dist <= _stop + 0.1 then return false end
    local _fresh = step_home_mark(t)   -- v4.37
    if step_toward(t, _stop, true) then
        info_msg('STEP-IN: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                 'y, still not hitting after ' .. ((_pl and MELEE_PROVOKE_NO_HIT) and 'Provoke' or 'trouble') ..
                 ' -- moving in to ' .. string.format('%.1f', _stop) .. 'y.')
        if h then h.mn = 0 end         -- needs fresh trouble before the next step
        melee_msg.id = 0
        ps.trouble_at = 0
        ps.melee_face = now
        return true
    end
    if _fresh then step_home.active = false end
    return false
end

-- v4.34: you were KO'd. Log it loudly and stop the loop (it used to keep
-- auto on and log nothing until the 60-minute auto-homepoint zoned you).
aa_defeated_at = 0
function aa_on_defeated(how, killer_id)
    if (os.clock() - aa_defeated_at) < 30 then return end
    aa_defeated_at = os.clock()
    local who = ''
    if killer_id and killer_id > 0 then
        local k = windower.ffxi.get_mob_by_id(killer_id)
        if k and k.name then who = ' by ' .. k.name end
    end
    if PSTAT then PSTAT.deaths = PSTAT.deaths + 1 end   -- v4.99: tell the party
    if pstat_event then pcall(pstat_event, 'death', 'defeated' .. who) end
    local was_on = auto_attack
    auto_attack = false
    fight_subcmd = nil
    if mv and mv.active then windower.ffxi.run(false); mv.active = false end
    if step_home then step_home.active = false end  -- v4.37
    if ds_leave then pcall(ds_leave, 'defeated') end
    info_msg('YOU WERE DEFEATED' .. who .. ' (' .. how .. ').' ..
             (was_on and ' Auto-attack stopped.' or ''))
    windower.add_to_chat(167, '[AutoAttack] You were defeated' .. who .. '. Auto-attack stopped.')
end

-- v4.83: a mob we Provoked in the last PROVOKED_HOT_SECS is in our fight even
-- before the game shows it claimed / targeting us. 11-19 00:00:54: PullNext
-- Provoked a bat at 8.3y, the current bat died 0.7s later, and HOT-SWITCH
-- took an unaggroed bat at 4.6y ("fresh") -- then sat in PULL-WAIT on it
-- (Provoke on recast) while the Provoked bat hit us from behind.
PROVOKED_HOT_SECS  = 20
FRESH_RETARGET_GAP = 2.0   -- s between two checks
fresh_rt_at = 0
function mob_is_ours(m, ids, idx)   -- v4.85: renamed (mob_in_our_fight(t) is v4.01's)
    if hs_is_hot(m, ids, idx) then return true end
    return provoke_last and provoke_last.id == m.id and (os.clock() - provoke_last.time) < PROVOKED_HOT_SECS or false
end
-- v4.83: engaged on a mob that isn't fighting us while another one is --
-- switch to the one that is (it is hitting us; the fresh one can wait).
function fresh_target_retarget(t, now)
    if now - fresh_rt_at < FRESH_RETARGET_GAP then return false end
    fresh_rt_at = now
    local p = windower.ffxi.get_player()
    if not p or p.status ~= 1 or not t or not t.id then return false end
    local ids, idx = hs_party_sets(p)
    if mob_is_ours(t, ids, idx) then return false end
    local m, d, hot = hot_switch_pick(t.id)
    if not m or not hot then return false end
    if not engaged_switch(m) then return false end
    info_msg('RETARGET >>>> ' .. tostring(m.name) .. ' (' .. m.id .. ', ' .. string.format('%.1f', d or 0) ..
             'y) is fighting us -- leaving ' .. tostring(t.name) .. ' (' .. t.id .. '), which is not.')
    return true
end

function engaged_pull_logic(pull_command, pull_dist, pull_wait, method)
    if autoattack_type ~= 'pull' then return end
    local t = windower.ffxi.get_mob_by_target('t')
    if not t or not t.id or not t.hpp or t.hpp <= 0 then return end
    if not fp_pull_ok(t) then return end  -- v4.54: party not full, mob not on the party
    if pull_in_check(t, pull_dist, true) then return end  -- v3.99
    local now = os.clock()
    local ps = pull_state
    if ps.id ~= t.id then
        ps.id = t.id; ps.engaged_at = now; ps.last_pull = 0; ps.pulls = 0; ps.far_logged = 0; ps.melee_face = 0
        ps.reach = nil
        ps.reengages = 0; ps.reengage_at = 0  -- v4.35
        ps.trouble_at = 0                     -- v4.38
        ps.trouble_prov = 0; ps.trouble_ra = 0 -- v4.75
    end
    local dist = t.distance and t.distance:sqrt() or 999
    if fresh_target_retarget(t, now) then return end   -- v4.83
    -- v4.40: HOT-SWITCH-PROVOKE: Provoke the hot-switched mob right away
    if hs_provoke.id ~= 0 then
        if os.clock() > hs_provoke.until_t then
            hs_provoke.id = 0
        elseif hs_provoke.id == t.id and dist <= PROVOKE_PULL_RANGE and provoke_pull_ready()
               and (now - last_ws_time) < HOT_SWITCH_PROVOKE_WS_GAP then
            -- v4.56: WS animation still running -- wait for it (HOLD keeps
            -- everything else quiet), keep the window open past the wait.
            local left = HOT_SWITCH_PROVOKE_WS_GAP - (now - last_ws_time)
            hs_provoke.until_t = math.max(hs_provoke.until_t, now + left + 2.0)
            if hs_provoke.ws_wait_id ~= t.id then
                hs_provoke.ws_wait_id = t.id
                debug_msg('HOT-SWITCH-PROVOKE: waiting ' .. string.format('%.1f', left) ..
                          's for the WS animation (Provoke sent inside it is dropped).')
            end
            return
        elseif hs_provoke.id == t.id and dist <= PROVOKE_PULL_RANGE and provoke_pull_ready() then
            hs_provoke.id = 0
            local _mr = ps.reach or (3.0 + (t.model_size or 2.0))
            info_msg('HOT-SWITCH-PROVOKE: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) .. 'y -- Provoke.')
            face_mob_direct(t)   -- v4.70: turn now (face('f') may land after the Provoke)
            face('f')
            if try_provoke_pull(t) then
                if dist > _mr then ps.last_pull = os.clock(); ps.pulls = ps.pulls + 1 end
                return
            end
        end
    end
    local mr   = 3.0 + (t.model_size or 2.0)
    local last_swing = (melee_swing.id == t.id) and melee_swing.time or 0
    local oor_recent = oor_msg.id == t.id and (now - oor_msg.time) < 1.5 and oor_msg.time > last_swing
    -- v4.01: learn the real reach. "<mob> is out of range." at a distance we
    -- counted as melee means our estimate is too big for this mob: shrink it.
    if oor_recent and dist <= mr then
        local _r = math.max(1.0, dist - 0.5)
        if not ps.reach or _r < ps.reach then
            ps.reach = _r
            debug_msg('REACH: ' .. (t.name or '?') .. ' out of range at ' .. string.format('%.1f', dist) ..
                      'y -- using ' .. string.format('%.1f', _r) .. 'y as melee range.')
        end
    end
    if ps.reach and ps.reach < mr then mr = ps.reach end
    local fighting_trust = mob_fighting_trust(t)
    local hit_who  = mob_hit_victim(t)                      -- v4.02
    local claimed_me = mob_claimed_on_me(t)                 -- v4.12
    local in_fight = fighting_trust or hit_who ~= nil or claimed_me
    local why      = (hit_who == 'me' or (hit_who == nil and not fighting_trust)) and 'you' or 'a Trust'

    -- Swinging on it recently: we're in contact, nothing to do
    if last_swing > 0 and (now - last_swing) < MELEE_HIT_WAIT and not oor_recent then
        repull_count = 0
        return
    end

    local ref = math.max(ps.engaged_at, ps.last_pull, last_swing)
    if dist <= mr then
        -- v4.38: MELEE-PROVOKE right away: in melee range and not hitting it
        -- (never since engage, or no swing in MELEE_HIT_WAIT -- the return
        -- above already left if we're swinging). Doesn't touch ps.last_pull.
        if MELEE_PROVOKE_NO_HIT and dist <= PROVOKE_PULL_RANGE and provoke_pull_ready() then
            info_msg('MELEE-PROVOKE: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                     'y (melee range), ' .. (last_swing > 0 and ('no swing in ' ..
                     string.format('%.0f', now - last_swing) .. 's') or 'not hitting it yet') .. ' -- Provoke.')
            face('f')
            if try_provoke_pull(t) then return end
        end
        -- v4.38: Provoke didn't fix it -> slight step in (STEP-IN)
        if melee_trouble_step(t, dist, mr, ps, now, oor_recent) then return end
    end
    if dist <= mr and not oor_recent and REENGAGE_WHEN_STUCK then
        -- v4.35: in range but no melee round on this mob (WSs don't count; a
        -- Provoke doesn't reset it) -> re-engage it.
        local _mr_t = (melee_round.id == t.id) and melee_round.time or 0
        local _midle = now - math.max(ps.engaged_at, _mr_t)
        if _midle >= REENGAGE_WAIT and (now - (ps.reengage_at or 0)) >= REENGAGE_WAIT then
            local _bt = windower.ffxi.get_mob_by_target('bt')
            local _bts = _bt and ((_bt.name or '?') .. ' ' .. tostring(_bt.id) ..
                         (_bt.id == t.id and ' (same)' or ' (DIFFERENT)')) or 'none'
            local _last = (melee_round.id ~= 0) and (tostring(melee_round.id) .. ' ' ..
                          string.format('%.0f', now - melee_round.time) .. 's ago') or 'never'
            ps.reengage_at = now
            ps.reengages = (ps.reengages or 0) + 1
            info_msg('RE-ENGAGE #' .. ps.reengages .. ': no melee round on ' .. (t.name or '?') ..
                     ' (' .. t.id .. ') at ' .. string.format('%.1f', dist) .. 'y in ' ..
                     string.format('%.0f', _midle) .. 's (battle target: ' .. _bts ..
                     '; last melee round: ' .. _last .. ') -- /attack off, re-target, /attack on.')
            cmd('input /attack off')
            coroutine.sleep(1.2)
            local _t2 = windower.ffxi.get_mob_by_id(t.id)
            if not _t2 or not _t2.hpp or _t2.hpp <= 0 then return end
            set_target(t.id, true)
            coroutine.sleep(0.5)
            cmd('input /attack on')
            ps.engaged_at = os.clock()   -- give the new engage a full window
            ps.melee_face = os.clock()
            face('f')
            return
        end
    end
    if dist <= mr and not oor_recent then
        -- v3.97: In melee range: NEVER Provoke or pull. Provoke is only for
        -- pulling mobs that are outside melee range. (Slow weapons -- e.g. DRG
        -- at ~5s delay -- routinely go 4s+ between rounds, and every one of
        -- those gaps used to fire a wasted Provoke / "Unable to use job ability".)
        local idle = now - ref
        -- v4.38: MELEE-PROVOKE and STEP-IN moved above (melee_trouble_step).
        if idle < MELEE_HIT_WAIT then return end
        if idle >= MELEE_STALL_LIMIT and fighting_trust then
            -- v4.01: it is fighting a Trust next to us -- never blacklist; step in.
            if step_toward(t, math.max(1.5, mr - 1.0)) then ps.melee_face = now; return end
        end
        if idle >= MELEE_STALL_LIMIT and in_fight then
            -- v4.02: close, hitting you / a Trust, and we can't land a hit: Provoke it
            -- (or wait for Provoke); never blacklist. Falls through to the re-face.
            close_fight_repull(t, dist, ps, why)
        end
        if idle >= MELEE_STALL_LIMIT and not in_fight then
            debug_msg('MELEE-STALL: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                      'y, no contact in ' .. string.format('%.0f', MELEE_STALL_LIMIT) ..
                      's -- unreachable, blacklisting and disengaging.')
            cant_target_ids[t.id] = os.clock() + CANT_SEE_BLACKLIST_DUR
            cant_target_counts[t.id] = nil
            repull_count = 0
            ps.id = 0
            cmd('input /attack off')
            coroutine.sleep(0.3)
            cmd('input /targetoff')
            return
        end
        if (now - (ps.melee_face or 0)) >= MELEE_HIT_WAIT then
            debug_msg('MELEE-CHECK: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                      'y, no contact in ' .. string.format('%.0f', idle) .. 's -- facing (no Provoke in melee range).')
            face('f')
            ps.melee_face = now
        end
        return
    end
    -- v4.01: just out of reach (game said "out of range") or tanked by a Trust a
    -- few yalms away: it is NOT coming to us, so pulling / Provoke is pointless and
    -- the re-pull limit would blacklist a mob that is in our fight. Step in instead.
    if dist > mr and dist <= APPROACH_MAX_DIST and (fighting_trust or oor_recent or ps.reach or claimed_me) then
        if step_toward(t, math.max(1.5, mr - 1.0)) then
            repull_count = 0
            return
        end
    end
    -- v4.02: close (<= APPROACH_MAX_DIST) and hitting you / a Trust, but we are not
    -- hitting it: re-pull with Provoke, or wait for Provoke's recast. Never counts
    -- toward the re-pull limit and never blacklists.
    if in_fight and dist <= APPROACH_MAX_DIST then
        repull_count = 0
        if close_fight_repull(t, dist, ps, why) then return end
    end
    -- v4.28: move_to_target 'provoke' / 'melee' / 'target' / <number>: run in
    -- instead of pulling from where we stand ('pull' runs further down, only
    -- when the mob is beyond pull range).
    local _mm = move_mode()
    if _mm == 'provoke' then
        if dist > PROVOKE_PULL_RANGE and not in_fight and provoke_pull_ready() then
            if move_toward_mob(t, PROVOKE_PULL_RANGE - MOVE_STOP_MARGIN, true) then return end
        end
    elseif _mm == 'melee' or _mm == 'target' or _mm == 'custom' then
        local _stop = (_mm == 'melee' and math.max(1.0, mr - 0.5))
                   or (_mm == 'target' and MOVE_TARGET_STOP)
                   or tonumber(move_to_target) or mr
        if dist > _stop then
            -- Provoke on the way (claims it and turns it toward you); JAs work while running
            if dist <= PROVOKE_PULL_RANGE and not in_fight and provoke_pull_ready() then
                if try_provoke_pull(t) then ps.last_pull = os.clock(); ps.pulls = ps.pulls + 1 end
            end
            if move_toward_mob(t, _stop, true) then return end
        end
    end
    if dist <= mr then
        -- Game says "<mob> is out of range." while we estimate melee range:
        -- it really is out of reach, so a pull (Provoke allowed) is legitimate.
        debug_msg('PULL-CHECK: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                  'y -- "out of range" from game. Pulling.')
    else
        -- Out of melee range: if we just pulled, let it walk in
        if ps.last_pull > 0 and (now - ps.last_pull) < PULL_APPROACH_WAIT then return end
    end

    -- Dia (mage) method: only the first pull, no projectile re-pulls (v2.86 rule)
    if method == 'dia' and ps.pulls > 0 then return end

    -- Provoke first (WAR main/sub, in range, ready) -- confirmed by the game
    if dist <= PROVOKE_PULL_RANGE and provoke_pull_ready() then
        if try_provoke_pull(t) then
            ps.last_pull = os.clock(); ps.pulls = ps.pulls + 1
            return
        end
    elseif provoke_pull_hold(t, dist, pull_command) then
        return  -- Provoke ready, mob just outside Provoke range: wait for it (logged)
    end

    -- v4.17: main pull can't fire right now (Provoke recast / no /WAR, no ammo,
    -- Dia recast): tag it with a backup_pull ability (Jump, a spell, /ra ...).
    -- v4.27: pull method is Provoke but Provoke is down (recast / 30s lock / no
    -- /WAR): use /ra right away when a ranged weapon is ready and the mob is in
    -- /ra range, instead of waiting for the recast (PULL-WAIT).
    if pull_command and pull_command:lower():find('provoke') and dist <= RA_PULL_RANGE then
        local _pl = provoke_wait_left()
        if (_pl == nil or _pl > 0) and ranged_attack_ready() then
            debug_msg('PULL-RA: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) .. 'y -- Provoke ' ..
                      (_pl and ('ready in ' .. string.format('%.0f', _pl) .. 's') or 'unavailable') .. ', using /ra <t>.')
            pull_command = '/ra <t>'
            pull_dist    = math.max(pull_dist, RA_PULL_RANGE)
            pull_wait    = RA_PULL_WAIT
        end
    end

    if not main_pull_ready(pull_command, dist) and try_backup_pull(t, dist, ps, 'engaged') then
        return
    end

    if dist > pull_dist then
        -- v4.22: out of reach of both pulls -> run in (move_in_range)
        if move_toward_mob(t, pull_dist - MOVE_STOP_MARGIN, true) then return end
        if (now - ps.far_logged) > 5 then
            debug_msg('PULL-WAIT: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                      'y, beyond pull range (' .. string.format('%.1f', pull_dist) .. 'y).')
            ps.far_logged = now
        end
        return
    end

    -- v4.02: pull_command is Provoke but it is on cooldown: don't send it
    -- ("Unable to use job ability") and don't count a re-pull for nothing.
    if pull_command and pull_command:lower():find('provoke') then
        local _pl = provoke_wait_left()
        if _pl and _pl > 0 then
            if (now - ps.far_logged) > 5 then
                debug_msg('PULL-WAIT: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                          'y -- Provoke ready in ' .. string.format('%.0f', _pl) .. 's.')
                ps.far_logged = now
            end
            return
        end
    end

    -- v4.39: the last /ra re-pull got "Unable to see" / "You cannot see" and
    -- Provoke is back soon: wait for Provoke instead of another /ra that won't land.
    if ps.pulls > 0 and ra_cant_see.id == t.id and (now - ra_cant_see.time) < RA_CANT_SEE_WINDOW
       and dist <= PROVOKE_PULL_RANGE and not (pull_command and pull_command:lower():find('provoke')) then
        local _pl = provoke_wait_left()
        if _pl and _pl > 0 and _pl <= RA_CANT_SEE_PROVOKE_WAIT then
            if (now - ps.far_logged) > 5 then
                debug_msg('PULL-WAIT: ' .. (t.name or '?') .. ' at ' .. string.format('%.1f', dist) ..
                          'y -- last pull "can\'t see", Provoke ready in ' .. string.format('%.0f', _pl) ..
                          's. Waiting for Provoke instead of re-pulling.')
                ps.far_logged = now
            end
            return
        end
    end

    face('f')
    coroutine.sleep(0.3)
    local t2 = windower.ffxi.get_mob_by_target('t')
    if not t2 or t2.id ~= t.id or not t2.hpp or t2.hpp <= 0 then return end
    if ps.pulls > 0 then
        -- v4.39: about to hit the re-pull limit: Provoke first if never tried
        if (repull_count + 1) >= REPULL_LIMIT and not in_fight
           and giveup_provoke_first(t2, dist, 're-pull limit') then return end
        repull_count = repull_count + 1
        if repull_count >= REPULL_LIMIT and not in_fight then
            info_msg('Re-pull limit reached (' .. repull_count .. 'x) for ' ..
                      (t2.name or '?') .. ' -- blacklisting and disengaging.')
            cant_target_ids[t2.id] = os.clock() + CANT_SEE_BLACKLIST_DUR
            cant_target_counts[t2.id] = nil
            repull_count = 0
            cmd('input /attack off')
            coroutine.sleep(0.3)
            cmd('input /targetoff')
            return
        end
        info_msg('RE-PULLING >>>> ' .. (t2.name or '?') .. ' (attempt ' .. repull_count .. '/' .. REPULL_LIMIT .. ')')
    else
        info_msg('PULLING >>>> ' .. (t2.name or '?') .. ' (' .. string.format('%.1f', dist) .. 'y)')
    end
    cmd('input ' .. pull_command)
    ps.last_pull = os.clock(); ps.pulls = ps.pulls + 1
    coroutine.sleep(pull_wait)
end

function provoke_fire_confirmed(label)
    local pd = res_with('job_abilities', 'name', 'Provoke')
    provoke_pending.ja_id     = pd and pd.id or nil
    provoke_pending.confirmed = false
    provoke_pending.active    = true
    cmd('input /ja "Provoke" <t>')
    ability_last_used['Provoke'] = os.time()  -- block other Provoke paths while we wait
    local t0 = os.clock()
    while not provoke_pending.confirmed and (os.clock() - t0) < PROVOKE_CONFIRM_WAIT do
        coroutine.sleep(0.1)
    end
    provoke_pending.active = false
    if provoke_pending.confirmed then
        local _pt = windower.ffxi.get_mob_by_target('t')   -- v4.38
        if _pt and _pt.id then provoke_last.id = _pt.id; provoke_last.time = os.clock() end
        debug_msg('PROVOKE-OK (' .. label .. '): landed after ' ..
                  string.format('%.1f', os.clock() - t0) .. 's.')
        return true
    end
    ability_last_used['Provoke'] = os.time() - (30 - PROVOKE_FAIL_RETRY)
    debug_msg('PROVOKE-FAIL (' .. label .. '): no Provoke action seen in ' ..
              string.format('%.1f', PROVOKE_CONFIRM_WAIT) .. 's. Lock cleared (retry in ~' ..
              PROVOKE_FAIL_RETRY .. 's); falling back.')
    return false
end

-- v4.76: Provoke a mob by ID without touching <t> (outgoing 0x01A, category
-- 0x09 job ability -- what the client sends for /ja). PullNext used to move
-- the cursor to the next mob, but while engaged <t> never followed ("target
-- lock failed", 11-18), then /targetoff + /attack on cost ~5s with no Provoke.
-- Confirmed the same way as provoke_fire_confirmed (our Provoke action seen).
function provoke_by_id(m, label)
    local pd = res_with('job_abilities', 'name', 'Provoke')
    if not pd or not pd.id or not m or not m.id or not m.index or m.index == 0 then return false end
    local packets = require('packets')
    provoke_pending.ja_id, provoke_pending.confirmed, provoke_pending.active = pd.id, false, true
    ability_last_used['Provoke'] = os.time()
    packets.inject(packets.new('outgoing', 0x01A, {
        ['Target']       = m.id,
        ['Target Index'] = m.index,
        ['Category']     = 0x09,   -- job ability
        ['Param']        = pd.id,
    }))
    local t0 = os.clock()
    while not provoke_pending.confirmed and (os.clock() - t0) < PROVOKE_CONFIRM_WAIT do
        coroutine.sleep(0.1)
    end
    provoke_pending.active = false
    if provoke_pending.confirmed then
        provoke_last.id = m.id; provoke_last.time = os.clock()
        info_msg('PROVOKE-OK (' .. label .. '): ' .. tostring(m.name) .. ' (' .. m.id .. ') after ' ..
                 string.format('%.1f', os.clock() - t0) .. 's -- still on our target.')
        return true
    end
    ability_last_used['Provoke'] = os.time() - (30 - PROVOKE_FAIL_RETRY)
    info_msg('PROVOKE-FAIL (' .. label .. '): no Provoke seen on ' .. tostring(m.name) .. ' in ' ..
             string.format('%.1f', PROVOKE_CONFIRM_WAIT) .. 's -- it gets the after-kill Provoke.')
    return false
end

function try_provoke_pull(target)
    if not target or not target.hpp or target.hpp <= 0 then return false end
    if not target.distance then return false end

    -- Only use Provoke if mob is within Provoke range
    local dist = target.distance:sqrt()
    if dist > PROVOKE_PULL_RANGE then return false end

    -- WAR main/sub, recast ready, shared 30s lock clear
    if not provoke_pull_ready() then return false end

    -- All clear -- fire Provoke as the pull
    debug_msg('PROVOKE-PULL: ' .. (target.name or '?') .. ' in range (' .. string.format('%.1f', dist) .. 'y). Using Provoke instead of /ra.')
    -- v3.87: returns true only if the game confirms Provoke went off
    return provoke_fire_confirmed('pull')
end



-- Fires Provoke on the current target when:
--   1. The player is WAR main or sub
--   2. The script is in PULL mode (never in ASSIST mode -- would steal hate from the tank)
--   3. The mob is outside melee range
--   4. Provoke's recast is ready
-- Shares ability_last_used['Provoke'] with use_job_abilities so the two never
-- double-fire or conflict over the recast timer.
function use_provoke_for_hate()
    -- Never provoke in ASSIST mode -- that would pull hate off the party's tank
    if autoattack_type ~= 'pull' then return false end

    local player = windower.ffxi.get_player()
    if not player then return false end

    -- Only WAR main or sub has Provoke
    if player.main_job ~= 'WAR' and player.sub_job ~= 'WAR' then return false end

    local target = windower.ffxi.get_mob_by_target('t')
    if not target or not target.hpp or target.hpp <= 0 then return false end
    if not target.distance then return false end

    -- Only fire when mob is outside melee range but still within Provoke's cast range
    local dist = target.distance:sqrt()
    local melee_range = 3.0 + (target.model_size or 2.0)
    if dist <= melee_range then return false end
    if dist > PROVOKE_PULL_RANGE then return false end  -- too far for Provoke to land

    -- Check Provoke recast via the ability resources (same path as use_job_abilities)
    local provoke_data = res_with('job_abilities', 'name', 'Provoke')
    if not provoke_data or not provoke_data.recast_id then return false end

    local abil_recasts = windower.ffxi.get_ability_recasts()
    if not abil_recasts then return false end

    local prov_recast2 = abil_recasts[provoke_data.recast_id]
    if prov_recast2 and prov_recast2 > 0 then return false end  -- nil = ready in Windower API

    -- Respect the shared min_time lock (30s matches Provoke's in-game recast)
    local last_call = ability_last_used['Provoke'] or 0
    if (os.time() - last_call) < 30 then return false end

    -- All clear -- fire Provoke
    debug_msg('PROVOKE: Mob out of melee range (' .. string.format('%.1f', dist) .. 'y). Provoking to regain hate.')
    -- v3.87: only report success if the game confirms Provoke went off
    if not provoke_fire_confirmed('hate') then return false end
    coroutine.sleep(0.5)
    return true
end



ws_once_done = {}   -- v4.70: [mob id|WS name] = true for once_per_mob entries
ws_once_n = 0

function use_weapon_skill()
    if not current_config.ws_list then return false end
    if current_config.ws_list.enabled == false then return false end

    -- v4.31: ws_mode.type = "Off" -> no weapon skills on any job (and no
    -- skillchain lockout holding back abilities).
    if ws_mode and type(ws_mode.type) == 'string' and ws_mode.type:lower() == 'off' then
        if ws_mode_last_type ~= ws_mode.type then
            ws_mode_last_type = ws_mode.type
            debug_msg('WS mode Off -- weapon skills disabled.')
        end
        ws_sc_locked = false
        return false
    end

    -- v4.33: //aa ws off -- session-only switch, reset by a reload.
    if ws_cmd_off then
        ws_sc_locked = false
        return false
    end

    -- v4.32: no weapon skills while the target has Dread Spikes
    if ds_state and ds_state.on then
        ws_sc_locked = false
        return false
    end

    -- v4.70: group skillchain is planning the party's weapon skills
    if gsc_active() then
        ws_sc_locked = false
        return false
    end

    local player = windower.ffxi.get_player()
    if not player or not player.vitals then return false end

    -- ws_mode.type selects a named sub-list (e.g. "Normal", "AoE", "Odin").
    -- Falls back to the flat ws_list for jobs not yet using sub-lists.
    local active_type = ws_mode and ws_mode.type or nil
    local active_list = (active_type and current_config.ws_list[active_type]) or current_config.ws_list

    -- Reset ws_index when the selected type changes mid-session.
    if active_type ~= ws_mode_last_type then
        ws_index = 1
        current_ws_use_count = 0
        ws_sc_locked = false
        ws_mode_last_type = active_type
        debug_msg('WS mode changed to: ' .. tostring(active_type) .. ' — resetting WS index.')
    end

    if not active_list or #active_list == 0 then return false end
    local current_ws = active_list[ws_index]
    if not current_ws then
        ws_index = 1
        current_ws = active_list[1]
        if not current_ws then return false end
    end
    if not current_ws.name then return false end  -- v3.98: malformed ws_list entry

    -- v4.70: once_per_mob = true -> that entry fires once on each mob (Full Break opener)
    do
        local _t = windower.ffxi.get_mob_by_target('t')
        local _tries = 0
        while current_ws and current_ws.once_per_mob and _t and _t.id
              and ws_once_done[_t.id .. '|' .. tostring(current_ws.name)] and _tries < #active_list do
            ws_index = ws_index % #active_list + 1
            current_ws_use_count = 0
            current_ws = active_list[ws_index]
            _tries = _tries + 1
        end
        if not current_ws or not current_ws.name or (current_ws.once_per_mob and _tries >= #active_list) then return false end
    end

    -- ws_mode.lockout == "false" suppresses SC chain locking entirely.
    local lockout_enabled = not (ws_mode and ws_mode.lockout == "false")

    -- TP check AFTER current_ws is resolved so we can log the WS name
    if player.vitals.tp < 1000 then
        return false
    end

    -- Per-WS minimum TP check (optional; omit min_tp to fire at 1000)
    if current_ws.min_tp and player.vitals.tp < current_ws.min_tp then
        if ws_blocked_debug then debug_msg('WS BLOCKED: ' .. current_ws.name .. ' needs ' .. current_ws.min_tp .. ' TP (have ' .. player.vitals.tp .. ')') end
        return false
    end

    local now = os.clock()

    -- 1. Check if enough time has passed since the PREVIOUS weapon skill
    local time_since_last = now - last_ws_time
    if time_since_last < (current_ws.min_time or 0) then  -- v3.98: nil-safe
        return false
    end

    -- 2. Handle Sneak Attack (SA) check if table entry says SA=1
    if current_ws.SA == 1 then
        local sa_data = res_with('job_abilities', 'name', 'Sneak Attack')
        local abil_recasts = windower.ffxi.get_ability_recasts()
        if not abil_recasts then return false end

        if sa_data and sa_data.recast_id ~= nil and abil_recasts[sa_data.recast_id] == 0 then
            debug_msg('Pre-buffing: Sneak Attack')
            cmd('input /ja "Sneak Attack" <me>')
            coroutine.sleep(1.2)
        end
    end

    -- 3. Execute Weapon Skill
	local target = windower.ffxi.get_mob_by_target('t')
	if not target or not target.hpp or target.hpp <= 0 then return false end
    local p_ws = windower.ffxi.get_player()
    if not p_ws or not p_ws.vitals or p_ws.vitals.hp <= 0 then return false end
    info_msg('Using WS (' .. (current_ws_use_count + 1) .. '/' .. (current_ws.uses or 1) .. '): ' .. current_ws.name)
    face_mob_direct(target)   -- v4.70: turn first ("You cannot see" right after engaging / a switch)
    if current_ws.once_per_mob and target.id then   -- v4.70
        ws_once_n = ws_once_n + 1
        if ws_once_n > 400 then ws_once_done, ws_once_n = {}, 1 end
        ws_once_done[target.id .. '|' .. current_ws.name] = true
    end
    local ws_cmd = 'input /ws "' .. current_ws.name .. '" <t>'
    cmd(ws_cmd)
    
    -- 4. Update the timestamp and counters
    last_ws_time = os.clock() 
    
    -- Update SC lockout state based on this WS's LockOut flag.
    -- Suppressed entirely when ws_mode.lockout == "false".
    --   LockOut=1 -> entering a SC chain, block all non-WS actions until the closing WS
    --   LockOut=0 -> closing WS fired, SC chain is complete, unblock everything
    if lockout_enabled then
        if current_ws.LockOut == 1 then
            ws_sc_locked = true
            debug_msg('SC LOCK: engaged after ' .. current_ws.name .. '. Non-WS actions suppressed.')
        elseif current_ws.LockOut == 0 then
            ws_sc_locked = false
            debug_msg('SC LOCK: released after ' .. current_ws.name .. '. Resuming normal actions.')
        end
        -- (no LockOut key = no change to ws_sc_locked)
    else
        ws_sc_locked = false  -- lockout disabled globally; never block
    end

    current_ws_use_count = current_ws_use_count + 1
    if current_ws_use_count >= (current_ws.uses or 1) then  -- v3.98: nil-safe
        current_ws_use_count = 0
        ws_index = ws_index + 1
        if ws_index > #active_list then
            ws_index = 1
        end
    end

    nap_while_alive(2) -- Standard animation lockout delay (v4.19: ends early if the WS killed it)
    return true
end




-- =========================================================================
-- v4.70: GROUP SKILLCHAIN  (aa_config.lua -> group_skillchain)
-- With another player in the party, each AutoAttack plans the party's weapon
-- skills together and job_config's ws_list is not used:
--   * the chain comes from what the party really does: every party member's
--     and Trust's WS on our target, and the skillchain it made
--   * a live chain is continued by whoever adds the most: skillchain level,
--     the harder-hitting closer, and what can still follow it (melee before
--     fillers); if they don't go, the next best gets a turn handoff_wait s later
--   * no live chain: the opener whose WS leads to the best 2-4 step chain
--     with players who are ready (or nearly: soon_tp) goes first; the next
--     best opener gets a turn opener_wait s later
--   * once_per_mob: a WS used once on each new mob before it chains
--     (Great Axe: Full Break)
--   * filler_jobs (RDM, BLM ...): magic burst first; WS to keep a chain going
--     only when no melee can, otherwise only while the melee are far from
--     1000 TP (or its own TP is near the cap)
-- Every AutoAttack works out the same plan from the party list, jobs (party
-- packets 0x0DD / 0x0DF), TP and the config -- no messages between them.
-- //aa gsc [on|off|auto] (this session) -- no argument shows the plan inputs.
-- Globals on purpose (main chunk is at the local / upvalue limit).
-- =========================================================================
GSC_LEVEL = {Liquefaction = 1, Impaction = 1, Detonation = 1, Scission = 1, Reverberation = 1,
             Induration = 1, Compression = 1, Transfixion = 1,
             Fusion = 2, Fragmentation = 2, Gravitation = 2, Distortion = 2,
             Light = 3, Darkness = 3}
-- [resonance on the mob][property of the next WS] = skillchain
GSC_COMBO = {
    Liquefaction  = {Scission = 'Scission', Impaction = 'Fusion'},
    Impaction     = {Liquefaction = 'Liquefaction', Detonation = 'Detonation'},
    Detonation    = {Scission = 'Scission', Compression = 'Gravitation'},
    Scission      = {Liquefaction = 'Liquefaction', Detonation = 'Detonation', Reverberation = 'Reverberation'},
    Reverberation = {Impaction = 'Impaction', Induration = 'Induration'},
    Induration    = {Compression = 'Compression', Impaction = 'Impaction', Reverberation = 'Fragmentation'},
    Compression   = {Transfixion = 'Transfixion', Detonation = 'Detonation'},
    Transfixion   = {Compression = 'Compression', Reverberation = 'Reverberation', Scission = 'Distortion'},
    Fusion        = {Gravitation = 'Gravitation', Fragmentation = 'Light'},
    Fragmentation = {Distortion = 'Distortion', Fusion = 'Light'},
    Gravitation   = {Fragmentation = 'Fragmentation', Distortion = 'Darkness'},
    Distortion    = {Fusion = 'Fusion', Gravitation = 'Darkness'},
    Light         = {Light = 'Light'},
    Darkness      = {Darkness = 'Darkness'},
}
-- skillchain add-effect messages
GSC_SC_MSG = {[288] = 'Light', [289] = 'Darkness', [290] = 'Gravitation', [291] = 'Fragmentation',
    [292] = 'Distortion', [293] = 'Fusion', [294] = 'Compression', [295] = 'Liquefaction',
    [296] = 'Induration', [297] = 'Reverberation', [298] = 'Transfixion', [299] = 'Scission',
    [300] = 'Detonation', [301] = 'Impaction',
    [385] = 'Light', [386] = 'Darkness', [387] = 'Gravitation', [388] = 'Fragmentation',
    [389] = 'Distortion', [390] = 'Fusion', [391] = 'Compression', [392] = 'Liquefaction',
    [393] = 'Induration', [394] = 'Reverberation', [395] = 'Transfixion', [396] = 'Scission',
    [397] = 'Detonation', [398] = 'Impaction', [767] = 'Light', [768] = 'Darkness',
    [769] = 'Light', [770] = 'Darkness'}
-- weapon skill -> skillchain properties
GSC_WS = {
    -- Great Axe
    ['Upheaval'] = {'Fusion', 'Compression'}, ["Ukko's Fury"] = {'Light', 'Fragmentation'},
    ['Full Break'] = {'Distortion'}, ['Steel Cyclone'] = {'Distortion', 'Detonation'},
    ["King's Justice"] = {'Fragmentation', 'Scission'}, ['Fell Cleave'] = {'Scission', 'Detonation'},
    ['Metatron Torment'] = {'Light', 'Fusion'}, ['Raging Rush'] = {'Induration', 'Reverberation'},
    ['Armor Break'] = {'Impaction'}, ['Weapon Break'] = {'Impaction'}, ['Shield Break'] = {'Impaction'},
    ['Sturmwind'] = {'Reverberation', 'Scission'}, ['Iron Tempest'] = {'Scission'}, ['Keen Edge'] = {'Compression'},
    -- Great Katana
    ['Tachi: Shoha'] = {'Fragmentation', 'Compression'}, ['Tachi: Fudo'] = {'Light', 'Distortion'},
    ['Tachi: Kasha'] = {'Fusion', 'Compression'}, ['Tachi: Rana'] = {'Gravitation', 'Induration'},
    ['Tachi: Gekko'] = {'Distortion', 'Reverberation'}, ['Tachi: Yukikaze'] = {'Induration', 'Detonation'},
    ['Tachi: Kaiten'] = {'Light', 'Fragmentation'}, ['Tachi: Ageha'] = {'Compression', 'Scission'},
    ['Tachi: Jinpu'] = {'Scission', 'Detonation'}, ['Tachi: Koki'] = {'Reverberation', 'Impaction'},
    ['Tachi: Goten'] = {'Transfixion', 'Impaction'}, ['Tachi: Kagero'] = {'Liquefaction'},
    ['Tachi: Enpi'] = {'Transfixion', 'Scission'}, ['Tachi: Hobaku'] = {'Induration'},
    -- Sword
    ['Savage Blade'] = {'Fragmentation', 'Scission'}, ['Chant du Cygne'] = {'Light', 'Distortion'},
    ['Requiescat'] = {'Gravitation', 'Scission'}, ['Knights of Round'] = {'Light', 'Fusion'},
    ['Death Blossom'] = {'Fragmentation', 'Distortion'}, ['Red Lotus Blade'] = {'Liquefaction', 'Detonation'},
    ['Circle Blade'] = {'Reverberation', 'Impaction'}, ['Vorpal Blade'] = {'Scission', 'Impaction'},
    ['Swift Blade'] = {'Gravitation'}, ['Fast Blade'] = {'Scission'}, ['Burning Blade'] = {'Liquefaction'},
    ['Flat Blade'] = {'Impaction'}, ['Shining Blade'] = {'Scission'}, ['Seraph Blade'] = {'Scission'},
    -- Great Sword
    ['Resolution'] = {'Fragmentation', 'Scission'}, ['Torcleaver'] = {'Light', 'Distortion'},
    ['Ground Strike'] = {'Fragmentation', 'Distortion'}, ['Scourge'] = {'Light', 'Fusion'},
    ['Dimidiation'] = {'Light', 'Fragmentation'},
    -- Scythe
    ['Cross Reaper'] = {'Distortion'}, ['Entropy'] = {'Gravitation', 'Reverberation'},
    ['Insurgency'] = {'Fusion', 'Compression'}, ['Quietus'] = {'Darkness', 'Distortion'},
    ['Catastrophe'] = {'Darkness', 'Gravitation'},
    -- Polearm
    ['Stardiver'] = {'Gravitation', 'Transfixion'}, ["Camlann's Torment"] = {'Light', 'Fragmentation'},
    ['Impulse Drive'] = {'Gravitation', 'Induration'}, ['Drakesbane'] = {'Fusion', 'Transfixion'},
    ['Sonic Thrust'] = {'Transfixion', 'Scission'}, ['Geirskogul'] = {'Light', 'Distortion'},
    -- Dagger
    ["Rudra's Storm"] = {'Darkness', 'Distortion'}, ['Evisceration'] = {'Gravitation', 'Transfixion'},
    ['Exenterator'] = {'Fragmentation', 'Scission'}, ['Mandalic Stab'] = {'Fusion', 'Compression'},
    -- Katana
    ['Blade: Shun'] = {'Fusion', 'Impaction'}, ['Blade: Hi'] = {'Darkness', 'Gravitation'},
    ['Blade: Ten'] = {'Gravitation'}, ['Blade: Ku'] = {'Gravitation', 'Transfixion'},
    ['Blade: Metsu'] = {'Darkness', 'Fragmentation'}, ['Blade: Kamu'] = {'Fragmentation', 'Compression'},
    ['Blade: Chi'] = {'Impaction', 'Transfixion'},
    -- Hand-to-Hand
    ['Victory Smite'] = {'Light', 'Fragmentation'}, ['Shijin Spiral'] = {'Fusion', 'Reverberation'},
    ['Asuran Fists'] = {'Gravitation', 'Liquefaction'}, ['Howling Fist'] = {'Transfixion', 'Impaction'},
    ['Final Heaven'] = {'Light', 'Fusion'}, ["Ascetic's Fury"] = {'Fusion', 'Transfixion'},
    ['Raging Fists'] = {'Impaction'},
    -- Club
    ['Black Halo'] = {'Fragmentation', 'Compression'}, ['Realmrazer'] = {'Fusion', 'Impaction'},
    ['Judgment'] = {'Impaction'}, ['Hexa Strike'] = {'Fusion'}, ['Randgrith'] = {'Light', 'Fragmentation'},
    -- Axe
    ['Decimation'] = {'Fusion', 'Reverberation'}, ['Ruinator'] = {'Distortion', 'Detonation'},
    ['Cloudsplitter'] = {'Darkness', 'Fragmentation'}, ['Rampage'] = {'Scission'},
    ['Mistral Axe'] = {'Fusion'}, ['Onslaught'] = {'Darkness', 'Gravitation'},
    -- Staff
    ['Shattersoul'] = {'Gravitation', 'Induration'}, ['Cataclysm'] = {'Compression', 'Reverberation'},
    ['Retribution'] = {'Gravitation', 'Reverberation'}, ['Full Swing'] = {'Liquefaction', 'Impaction'},
    ['Vidohunir'] = {'Darkness', 'Distortion'},
}
-- res.skills ids of melee weapons
GSC_SKILL = {[1] = 'Hand-to-Hand', [2] = 'Dagger', [3] = 'Sword', [4] = 'Great Sword', [5] = 'Axe',
             [6] = 'Great Axe', [7] = 'Scythe', [8] = 'Polearm', [9] = 'Katana', [10] = 'Great Katana',
             [11] = 'Club', [12] = 'Staff'}
-- v4.72: damage model from the 2026-11-18 logs (thousands).
-- GSC_POWER   = the WS's own average damage (others count as 6)
-- GSC_SCPOWER = average Light skillchain damage when this WS closes it (others
--               18). Skillchain damage follows the closer, not its WS damage:
--               Savage Blade closes for 32k, Upheaval 25k, Shoha only 16k.
-- GSC_MULT    = skillchain damage by level, relative to Light (Fusion closed
--               by Upheaval 13.4k = 0.55); 'end' = Light from two Light WS
--               (no further step, ~1.25x)
-- v4.77: refit on 227 kills (11-18 18:14-21:11, ~1,150 Light). Savage Blade
-- closing a Light is 11.9k, not 31.9k (the v4.72 figure came from a handful);
-- Light-on-Light is ~1.35x (Ukko 36.8k) to ~1.55x (Fudo 26.2k) the plain Light.
GSC_POWER = {['Upheaval'] = 16.5, ["Ukko's Fury"] = 13.4, ['Full Break'] = 3.5,
             ['Tachi: Shoha'] = 8.8, ['Tachi: Fudo'] = 8.2, ['Tachi: Kasha'] = 7.3, ['Tachi: Rana'] = 3.7,
             ['Savage Blade'] = 7.6, ['Requiescat'] = 3.0, ['Knights of Round'] = 9.0}
GSC_SCPOWER = {['Upheaval'] = 28.4, ["Ukko's Fury"] = 27.3, ['Tachi: Fudo'] = 16.7, ['Tachi: Shoha'] = 20.6,
               ['Tachi: Kasha'] = 14.7, ['Savage Blade'] = 11.9, ['Knights of Round'] = 35.7,
               ['Full Break'] = 8.0, ['Tachi: Rana'] = 10.0}
GSC_MULT = {[1] = 0.25, [2] = 0.55, [3] = 1.0, ['end'] = 1.4}
-- defaults for anything missing from aa_config.lua -> group_skillchain
GSC_DEF = {
    enabled = true, min_players = 2, soon_tp = 750,
    window_open = 3.2, window_close = 10.0, window_step = 0, window_min = 8.0, ws_lead = 1.2,
    handoff_wait = 1.5, opener_wait = 2.0, max_steps = 8, plan_depth = 3, filler_wait_tp = 600,
    bank_hpp = 10, noshow_max = 3, block_tp = 500, pre_wait = 6.0, tp_cap = 2900,
    min_sc = 5.0,   -- v5.28: skip a level-1 skillchain worth less than this (k) unless at tp_cap
    burst = true, nuke_hold = true, tp_band = 500, band_min = 5,   -- v5.00
    tp_project = true,   -- v5.04
    handoff_learn = true, handoff_max = 3.0,   -- v5.53: learned per-player handoff
    once_per_mob = {['Great Axe'] = 'Full Break'},
    filler_jobs = {'RDM', 'BLM', 'WHM', 'SCH', 'GEO', 'BRD', 'SMN'},
    fillers = {},
    weapons = {},
    job_weapons = {WAR = 'Great Axe', SAM = 'Great Katana', RDM = 'Sword', PLD = 'Sword', BLU = 'Sword',
                   COR = 'Sword', DRK = 'Scythe', DRG = 'Polearm', MNK = 'Hand-to-Hand', PUP = 'Hand-to-Hand',
                   THF = 'Dagger', DNC = 'Dagger', BRD = 'Dagger', RNG = 'Dagger', NIN = 'Katana',
                   WHM = 'Club', GEO = 'Club', BST = 'Axe', RUN = 'Great Sword',
                   BLM = 'Staff', SCH = 'Staff', SMN = 'Staff'},
    pools = {
        ['Great Axe']    = {'Upheaval', "Ukko's Fury", 'Full Break'},
        ['Great Katana'] = {'Tachi: Shoha', 'Tachi: Fudo', 'Tachi: Kasha'},
        ['Sword']        = {'Savage Blade'},   -- v4.71: Scrach has no Requiescat
        ['Great Sword']  = {'Resolution', 'Torcleaver', 'Ground Strike'},
        ['Scythe']       = {'Cross Reaper', 'Entropy', 'Insurgency'},
        ['Polearm']      = {'Stardiver', 'Impulse Drive', 'Drakesbane', "Camlann's Torment"},
        ['Dagger']       = {"Rudra's Storm", 'Evisceration', 'Shark Bite', 'Exenterator'},   -- v5.28: Shark Bite
        ['Katana']       = {'Blade: Shun', 'Blade: Hi', 'Blade: Ku'},
        ['Hand-to-Hand'] = {'Victory Smite', 'Shijin Spiral', 'Asuran Fists', 'Howling Fist'},
        ['Club']         = {'Black Halo', 'Realmrazer', 'Judgment'},
        ['Axe']          = {'Decimation', 'Ruinator', 'Cloudsplitter'},
        ['Staff']        = {'Shattersoul', 'Cataclysm', 'Retribution'},
    },
    power = {}, sc_power = {}, players = {},
    -- v4.90: profiles, learning, knowledge sync
    announce = true, learn = true, sync = true, learn_min = 3, learn_cap = 200, learn_save_secs = 120,
    -- v4.98: learn_window replaces learn_cap; mob_k blends a mob type's own figure with the
    -- party-wide toughness of that mob; odd_* skip a sample far under a settled average
    learn_window = 60, mob_k = 5, odd_min = 20, odd_ratio = 0.25, odd_repeat = 3,
    sync_min = 5, pool_max = 6, weapon_hold = 3, mb_weight = 0.5,
}
GSC = {on = nil, chain = nil, jobs = {}, began = {}, pre_done = {}, pre_n = 0, mob = 0, mob_since = 0,
       fired_at = 0, said = {}, ids = {}, ids_at = -10, act_at = -10, act_val = false, act_last = nil,
       learned = nil, learned_at = -100, expect = nil, noshow = {},
       lag = {}, rel = {}, my_lead = 0.9, stomps = 0, stomp_by = {}}   -- v5.53

function gsc_cfg(k)
    local c = AA_CFG and AA_CFG.group_skillchain
    local v = nil
    if type(c) == 'table' then v = c[k] end   -- v5.04: 'x and c[k] or nil' turned false into nil
    if v == nil then return GSC_DEF[k] end
    return v
end
function gsc_num(k) return tonumber(gsc_cfg(k)) or tonumber(GSC_DEF[k]) or 0 end
-- one debug line per key until its text changes
function gsc_dbg(key, msg)
    if GSC.said[key] == msg then return end
    GSC.said[key] = msg
    debug_msg(msg)
end
-- v5.53: LEARNED HANDOFF. Review of 11-24 (THF + SAM + RDM, 731 kills): 454
-- of 3949 live skillchain steps (11.5%) were wiped by a second WS landing
-- 0-3s after it (311 of them a level-3 Darkness / Light that Rudra's Storm or
-- Fudo would have ended for ~19-24k). The next player's turn came 1.5s after
-- the first one's (handoff_wait), but Myth's WS lands 1-3s after his turn
-- opens (remote PC + SAM animation) and his "readying" is seen only ~0.5s
-- before it lands -- so Shadow sent into Myth's WS. Now each AA learns, per
-- teammate, how long after their turn opens their WS lands (r) and gives
-- them p80(r) - 0.5s (handoff_wait .. handoff_max) before the next turn.
GSC_LAG_N = 40
function gsc_lag_note(name, r)
    if not name or not r or r < 0 or r > 8 then return end
    local key = name:lower()
    local l = GSC.lag[key] or {}
    l[#l + 1] = r
    if #l > GSC_LAG_N then table.remove(l, 1) end
    GSC.lag[key] = l
end
-- how often a teammate we waited on (first in line, 1000+ TP) came: decayed
-- counts. Scrach came 189 of 968 times on 11-24 -- a longer turn for a player
-- who mostly doesn't come would only slow the chain, so they keep handoff_wait.
function gsc_rel_note(id, came)
    local name = gsc_player_name(id)
    if not name then return end
    local key = name:lower()
    local r = GSC.rel[key] or {a = 0, c = 0, n = 0}
    r.a = r.a * 0.97 + 1
    r.c = r.c * 0.97 + (came and 1 or 0)
    r.n = r.n + 1
    GSC.rel[key] = r
end
function gsc_rel(name)
    local r = name and GSC.rel[name:lower()]
    if not r or r.n < 10 or r.a <= 0 then return nil end
    return r.c / r.a
end
-- seconds a teammate gets before the next player's turn
function gsc_gap(m, base)
    base = base or gsc_num('handoff_wait')
    if not m or m.me or gsc_cfg('handoff_learn') == false then return base end
    local rate = gsc_rel(m.name)
    if rate and rate < 0.5 then return base end
    local l = GSC.lag[(m.name or ''):lower()]
    if not l or #l < 8 then return base end
    local s = {}
    for i = 1, #l do s[i] = l[i] end
    table.sort(s)
    local p80 = s[math.max(1, math.ceil(#s * 0.8))]
    return math.max(base, math.min(gsc_num('handoff_max'), p80 - 0.5))
end
-- turn start for each place in a ranked list (continuers or openers)
function gsc_slots(list, start, base)
    local go, at = {}, start
    for k, cd in ipairs(list) do
        go[k] = at
        at = at + gsc_gap(cd.m, base)
    end
    return go
end
-- v5.53: my turn is here, but I'm late (wasn't ready when it opened). A
-- teammate ranked after me whose turn has opened may already be sending --
-- give them their full turn before I go (their "readying" shows ~0.5s before
-- it lands). nil = go.
function gsc_late_guard(list, go, k, now, base)
    for j = k + 1, #list do
        local cd = list[j]
        if not cd.m.me and cd.m.tp >= 1000 and go[j] <= now and now < go[j] + gsc_gap(cd.m, base) then
            return cd.m.name
        end
    end
    return nil
end
function gsc_power(ws, who)
    local p = gsc_cfg('power')
    local v = type(p) == 'table' and tonumber(p[ws]) or nil
    return v or gsc_k_est('ws', who, ws) or GSC_POWER[ws] or 6   -- v4.90: learned damage (v4.98: blended for this mob type)
end
-- v4.72: Light skillchain damage when this WS closes it
function gsc_scpower(ws, who, l, term)
    local p = gsc_cfg('sc_power')
    local v = type(p) == 'table' and tonumber(p[ws]) or nil
    -- v5.28: learned per skillchain level first (Evisceration: Transfixion 13.1k
    -- but Darkness 20.6k -- one Light-equivalent per closer said 10.8k / 43k)
    if not v and l and gsc_k_est then v = gsc_k_est('sc', who, gsc_lkey(ws, l, term)) end
    return v or gsc_k_est('sc', who, ws) or GSC_SCPOWER[ws] or 18   -- v4.90: learned (v4.98: blended for this mob type)
end
-- v4.72: damage of a WS that makes skillchain r (level l, term = chain ends)
-- v5.28: knowledge key for a closer at one skillchain level ('E' = Light on Light)
function gsc_lkey(ws, l, term) return tostring(ws) .. '#' .. (term and 'E' or tostring(l or 0)) end
-- v5.28: a level-1 skillchain too small to spend a WS on (11-23: Myth's Shoha /
-- Kasha closing Compression after Evisceration's Transfixion -- 668 times, 2.3k
-- each, 35% of his WS). Kept when the player is at the TP cap.
function gsc_weak(ws, who, l, term, tp)
    if term or (l or 0) ~= 1 then return false end
    local min = gsc_num('min_sc')
    if min <= 0 or (tp or 0) >= gsc_num('tp_cap') then return false end
    return gsc_scpower(ws, who, l, term) * (GSC_MULT[1] or 0.25) < min
end
function gsc_value(ws, l, term, who)
    -- v4.90: who = the player (their learned damage); each skillchain also
    -- gives the fillers a magic burst (GSC_MBV, from gsc_members)
    return gsc_power(ws, who) + gsc_scpower(ws, who, l, term) * (term and GSC_MULT['end'] or (GSC_MULT[l] or 0))
        + (((l or 0) > 0) and (GSC_MBV or 0) or 0)
end
-- best skillchain this WS makes on a resonance (list of properties): name, level,
-- term. v4.72: term = true when it is Light on Light (or Darkness on Darkness):
-- the 11-18 logs show a Light made that way is never continued (1 of 156),
-- while a Light made from Fusion + Fragmentation continues ~80% of the time.
function gsc_result(props, ws)
    local wp = gsc_props(ws)
    if not wp or type(props) ~= 'table' then return nil, 0, false end
    local best, bl, term = nil, 0, false
    for _, a in ipairs(props) do
        local row = GSC_COMBO[a]
        if row then
            for _, b in ipairs(wp) do
                local r = row[b]
                local lv = r and (GSC_LEVEL[r] or 0) or 0
                local t = (a == 'Light' or a == 'Darkness')
                if r and (lv > bl or (lv == bl and term and not t)) then best, bl, term = r, lv, t end
            end
        end
    end
    return best, bl, term
end
-- party IDs (players and Trusts), cached 2s
function gsc_party_ids()
    local now = os.clock()
    if now - GSC.ids_at < 2 then return GSC.ids end
    local ids, party = {}, windower.ffxi.get_party()
    if party then
        for i = 0, 5 do
            local m = party['p' .. i]
            if m and m.mob and m.mob.id then ids[m.mob.id] = true end
        end
    end
    GSC.ids, GSC.ids_at = ids, now
    return ids
end
-- 0x0DD / 0x0DF: a party member's main job
function gsc_job_packet(id, data)
    if not data or #data < 0x24 then return end
    local pid = data:byte(5) + data:byte(6) * 256 + data:byte(7) * 65536 + data:byte(8) * 16777216
    local jb = (id == 0x0DD) and data:byte(0x23) or data:byte(0x21)
    local j = jb and jb > 0 and res.jobs[jb]
    if pid > 0 and j and j.ens then GSC.jobs[pid] = j.ens end
end
-- weapon skills this character knows: [name] = skill id, cached 30s
function gsc_learned()
    local now = os.clock()
    if GSC.learned and now - GSC.learned_at < 30 then return GSC.learned end
    local set = {}
    local ab = windower.ffxi.get_abilities()
    for _, wid in ipairs((ab and ab.weapon_skills) or {}) do
        local r = res.weapon_skills[wid]
        if r and r.en then set[r.en] = r.skill or true end
    end
    GSC.learned, GSC.learned_at = set, now
    return set
end
-- you: the weapon in your hand; others: their job (job_weapons), then weapons[name]
function gsc_weapon(name, job, isme)
    if isme then
        local it = equipped_item_res('main')
        local w = it and GSC_SKILL[it.skill]
        if w then return w end
    end
    if not isme and name and GSC_P then   -- v4.90: what they told us
        local pr = GSC_P.prof[name:lower()]
        if pr and pr.weapon then return pr.weapon end
    end
    local jw = gsc_cfg('job_weapons')
    if job and type(jw) == 'table' and jw[job] then return jw[job] end
    local nw = gsc_cfg('weapons')
    if type(nw) == 'table' and name then
        for k, v in pairs(nw) do
            if type(k) == 'string' and k:lower() == name:lower() then return v end
        end
    end
    return nil
end
function gsc_is_filler(job, name)
    local f = gsc_cfg('fillers')
    if type(f) == 'table' and name then
        for _, n in ipairs(f) do if type(n) == 'string' and n:lower() == name:lower() then return true end end
    end
    local fj = gsc_cfg('filler_jobs')
    for _, j in ipairs(type(fj) == 'table' and fj or {}) do if j == job then return true end end
    return false
end
-- the WS a player brings: pools[weapon]; yours only the ones you know
function gsc_pool(weapon, isme, id, name)
    local pools = gsc_cfg('pools')
    local list = (type(pools) == 'table' and weapon and pools[weapon]) or {}
    -- v4.73: players = {Name = {'WS', ...}} replaces the weapon pool for that player
    local pp, explicit = gsc_cfg('players'), false   -- v4.90: explicit = set by hand, kept exact
    if type(pp) == 'table' and name then
        for k, v in pairs(pp) do
            if type(k) == 'string' and k:lower() == name:lower() and type(v) == 'table' and #v > 0 then list = v; explicit = true end
        end
    end
    if not isme and name and GSC_P then   -- v4.90: their profile, else add what we saw them use
        local key = name:lower()
        local pr = GSC_P.prof[key]
        if pr and #pr.ws > 0 then
            list = pr.ws
        elseif GSC_P.seen[key] and not explicit then
            local have, l2 = {}, {}
            for _, ws in ipairs(list) do have[ws] = true; l2[#l2 + 1] = ws end
            for ws in pairs(GSC_P.seen[key]) do if not have[ws] and gsc_props(ws) then l2[#l2 + 1] = ws end end
            list = l2
        end
    end
    if not isme then   -- v4.71: minus WS this player passed on noshow_max times
        local out, mx = {}, gsc_num('noshow_max')
        for _, ws in ipairs(list) do
            if mx <= 0 or ((GSC.noshow[tostring(id) .. '|' .. ws] or 0) < mx and not gsc_ns_has(name, ws)) then out[#out + 1] = ws end
        end
        return out
    end
    local learned, out = gsc_learned(), {}
    for _, ws in ipairs(list) do if learned[ws] and gsc_props(ws) then out[#out + 1] = ws end end
    if #out == 0 and weapon then   -- none from the pool: anything you know for this weapon
        local sk
        for id, nm in pairs(GSC_SKILL) do if nm == weapon then sk = id end end
        for ws, s in pairs(learned) do
            if gsc_props(ws) and s == sk then out[#out + 1] = ws end
        end
        table.sort(out, function(a, b) return gsc_power(a, name) > gsc_power(b, name) end)
        out = gsc_prune(out, name)   -- v4.90: any weapon -- the strongest pool_max
    end
    return out
end
-- players in the party (no Trusts) with what the plan needs; number of players
function gsc_members()
    local out, n = {}, 0
    local party, pl = windower.ffxi.get_party(), windower.ffxi.get_player()
    if not party or not pl then return out, 0 end
    for i = 0, 5 do
        local m = party['p' .. i]
        local mob = m and m.mob
        if m and m.name and mob and mob.id and mob.is_npc ~= true and mob.spawn_type ~= 14 then
            n = n + 1
            local isme = mob.id == pl.id
            local _pr = GSC_P and GSC_P.prof[m.name:lower()]   -- v4.90
            local job = isme and pl.main_job or GSC.jobs[mob.id] or (_pr and _pr.job)
            local weapon = gsc_weapon(m.name, job, isme)
            out[#out + 1] = {id = mob.id, name = m.name, job = job, me = isme, weapon = weapon,
                tp = (isme and pl.vitals and pl.vitals.tp) or m.tp or 0,
                engaged = (isme and pl.status == 1) or ((not isme) and mob.status == 1),
                filler = gsc_is_filler(job, m.name), pool = gsc_pool(weapon, isme, mob.id, m.name)}
        end
    end
    -- v4.90: what one skillchain is worth to the fillers' magic bursts (learned)
    local mbv = 0
    for _, x in ipairs(out) do
        if x.filler and x.engaged then mbv = mbv + (gsc_k_value('mb', x.name, 'MB') or 0) end
    end
    GSC_MBV = mbv * gsc_num('mb_weight')
    return out, n
end
function gsc_active()
    if GSC.on == false then return false end
    if GSC.on == nil and gsc_cfg('enabled') ~= true then return false end
    if not current_config or not current_config.ws_list or current_config.ws_list.enabled == false then return false end
    if ws_cmd_off then return false end
    if ws_mode and type(ws_mode.type) == 'string' and ws_mode.type ~= 'Normal' then return false end
    local now = os.clock()
    if now - GSC.act_at >= 2 then
        local _, n = gsc_members()
        GSC.act_val = n >= gsc_num('min_players')
        GSC.act_at = now
        if GSC.act_val ~= GSC.act_last then
            GSC.act_last = GSC.act_val
            info_msg('GROUP SKILLCHAIN ' .. (GSC.act_val and ('ON -- ' .. n .. ' players in the party; job_config ws_list paused.')
                     or 'OFF -- no other player in the party; using job_config ws_list.'))
        end
    end
    return GSC.act_val
end
-- chain window of a resonance: open, close (os.clock)
function gsc_window(c)
    local close = math.max(gsc_num('window_min'),
        gsc_num('window_close') - (math.max(c.step or 1, 1) - 1) * gsc_num('window_step'))
    return c.t + gsc_num('window_open'), c.t + close
end
-- value of the best chain that can follow a resonance, up to depth more steps
function gsc_follow(props, depth, prev_id, mem, step)
    if depth <= 0 or not props then return 0 end
    local best, soon = 0, gsc_num('soon_tp')
    for _, m in ipairs(mem) do
        -- v4.77: a later step counts only players already at block_tp (500): with
        -- everyone counted, Shadow's Ukko closing Fusion scored a Fudo from Myth at
        -- 0 TP, and beat Scrach's Light + Shadow's Ukko Light-on-Light (36.8k)
        local ok = m.engaged and m.id ~= prev_id and m.tp >= (step > 1 and gsc_num('block_tp') or soon)
        -- v5.47: the look-ahead uses the same TP projection as gsc_continuers (11-23:
        -- Shadow closed Gravitation with Shark Bite = Fragmentation (~5k) instead of
        -- Rudra's Storm = Darkness (~20k), counting on a Light from Myth at 534 TP,
        -- +37 TP/s, who couldn't reach 1000 in time). A step after this one has
        -- until about a window after now to get there.
        if ok and not m.me and m.tp < 1000 and gsc_cfg('tp_project') ~= false then
            local at = os.clock() + gsc_num('window_close') - gsc_num('ws_lead') +
                math.max(0, step - 2) * gsc_num('window_open')
            local proj = gsc_tp_by(m.name, m.tp, at)
            if proj and proj < 1000 then ok = false end
        end
        if ok then
            for _, ws in ipairs(m.pool) do
                local r, l, term = gsc_result(props, ws)
                if r and gsc_weak(ws, m.name, l, term, m.tp) then r = nil end   -- v5.28
                if r then
                    local v = gsc_value(ws, l, term, m.name) - (m.filler and 2 or 0)
                        + (term and 0 or 0.8 * gsc_follow({r}, depth - 1, m.id, mem, step + 1))
                    if v > best then best = v end
                end
            end
        end
    end
    return best
end
function gsc_sort(list)
    table.sort(list, function(a, b)
        if a.key ~= b.key then return a.key > b.key end
        return a.m.name < b.m.name
    end)
    return list
end
-- who can continue this resonance: best WS per player, best first
function gsc_continuers(mem, props, last_actor)
    local out, soon = {}, gsc_num('soon_tp')
    for _, m in ipairs(mem) do
        -- v4.73: a teammate keeps their place from block_tp (their TP is seen late)
        -- v4.92: a filler (Scrach) only from 1000 TP: in Sortie he was the
        -- expected closer 21 times and delivered 2 (busy casting)
        local ok_tp = m.engaged and m.tp >= (m.me and soon or (m.filler and 1000) or gsc_num('block_tp'))
        -- v5.04: a teammate under 1000 TP only keeps a place when their TP gain gets
        -- them to 1000 before the window closes (11-22: Shadow held for Vayne -- DRK,
        -- great sword, slow TP -- 141 times; Vayne came 33 times)
        if ok_tp and not m.me and m.tp < 1000 and GSC_CLOSE_AT and gsc_cfg('tp_project') ~= false then
            local proj = gsc_tp_by(m.name, m.tp, GSC_CLOSE_AT - gsc_num('ws_lead'))
            if proj and proj < 1000 then
                ok_tp = false
                local r = GSC_TPR[m.name]
                gsc_dbg('tpproj' .. m.name, string.format('GSC: %s at %d TP (+%.0f TP/s) won\'t reach 1000 before the window closes -- not waiting for them.',
                    m.name, m.tp, r and r.rate or 0))
            end
        end
        if ok_tp then
            local best
            for _, ws in ipairs(m.pool) do
                local r, l, term = gsc_result(props, ws)
                if r and gsc_weak(ws, m.name, l, term, m.tp) then   -- v5.28
                    gsc_dbg('weak' .. m.name, string.format('GSC: %s skips %s (%s, ~%.1fk) -- saving TP for a bigger skillchain.',
                        m.name, ws, tostring(r), gsc_scpower(ws, m.name, l, term) * (GSC_MULT[1] or 0.25)))
                    r = nil
                end
                if r then
                    -- same value as the opener plan (damage of this WS and its skillchain,
                    -- plus what can still follow), plus a little for being ready now
                    local key = gsc_value(ws, l, term, m.name) - (m.filler and 2 or 0) + ((m.tp >= 1000) and 2 or 0)
                        + (term and 0 or 0.8 * gsc_follow({r}, gsc_num('plan_depth') - 1, m.id, mem, 2))
                    -- v4.71: the player who made the last WS goes after everyone else: the
                    -- others see their TP a moment late and would go at the same time
                    if last_actor and m.id == last_actor then key = key - 100 end
                    if not best or key > best.key then best = {m = m, ws = ws, res = r, key = key} end
                end
            end
            if best then out[#out + 1] = best end
        end
    end
    return gsc_sort(out)
end
-- openers: best opening WS per ready melee player, best plan first
function gsc_openers(mem)
    local out = {}
    for _, m in ipairs(mem) do
        -- v4.71: a teammate within soon_tp of 1000 keeps their turn -- you see their TP
        -- a moment late (both opened in the same second 5 times on 11-18)
        -- v4.73: from block_tp (500) -- 56 same-second WS on v4.72, mostly two openers
        if m.engaged and not m.filler and (m.tp >= 1000 or (not m.me and m.tp >= gsc_num('block_tp'))) then
            local best
            for _, ws in ipairs(m.pool) do
                local key = gsc_follow(gsc_props(ws), gsc_num('plan_depth'), m.id, mem, 1) + gsc_power(ws, m.name)
                if not best or key > best.key then best = {m = m, ws = ws, key = key} end
            end
            -- v4.96: at the TP cap, every melee round's TP is lost -- that player
            -- opens first. On 11-21 Vayne (DRK, Cross Reaper only -- it can't
            -- continue the party's Light / Fusion) ranked below Shadow and Myth
            -- every time, sat at 3000 TP, used 22 WS in 30 min (Shadow 151) and
            -- 19 of them landed on top of someone else's chain.
            if best and m.tp >= gsc_num('tp_cap') then best.key = best.key + 100; best.capped = true end
            if best then out[#out + 1] = best end
        end
    end
    return gsc_sort(out)
end
-- once_per_mob WS this player still owes on this mob, or nil
-- v4.84: a mark is a time, forgotten after GSC_PRE_FORGET s. It used to be
-- kept until 400 marks: the bats respawn with the same 8 IDs, so after the
-- first Full Break on each ID it never fired again -- 9 Full Breaks in 9
-- hours on 11-19 (Mark asked for one on every mob).
GSC_PRE_FORGET = 120
function gsc_pre_ws(m, mob_id)
    local pre = gsc_cfg('once_per_mob')
    local pw = type(pre) == 'table' and m.weapon and pre[m.weapon] or nil
    local done = GSC.pre_done[mob_id .. '|' .. m.id]
    if done and (type(done) ~= 'number' or os.clock() - done < GSC_PRE_FORGET) then return nil end
    if not pw then return nil end
    if m.me then return gsc_learned()[pw] and pw or nil end
    for _, ws in ipairs(m.pool) do if ws == pw then return pw end end
    return nil
end
function gsc_pre_mark(mob_id, actor_id)
    GSC.pre_n = GSC.pre_n + 1
    if GSC.pre_n > 400 then GSC.pre_done, GSC.pre_n = {}, 1 end
    GSC.pre_done[mob_id .. '|' .. actor_id] = os.clock()   -- v4.84: a time, not true
end
function gsc_fire(t, ws, why, quiet)
    local cur = windower.ffxi.get_mob_by_target('t')
    if not cur or cur.id ~= t.id or not cur.hpp or cur.hpp <= 0 then return 'wait' end
    face_mob_direct(cur)   -- v4.70: turn first ("You cannot see" right after a switch)
    -- v4.76: a chain step's "sending" line goes to the log file only at debug 2;
    -- the "GSC: step N <SC> -- <WS> (<who>)" line when it lands is the one chat line
    if quiet and (debug_level or 0) >= 2 then
        aa_log_file(aa_wall_clock(os.clock()) .. ' L2 GSC: ' .. why)
    else
        info_msg('GSC: ' .. why)
    end
    cmd('input /ws "' .. ws .. '" <t>')
    last_ws_time = os.clock()
    GSC.fired_at = last_ws_time
    ws_sc_locked = false
    return 'fired'
end
-- One combat tick. false = not active (job_config ws_list runs);
-- 'fired' = WS sent; 'hold' = our WS is due in a moment (no JAs now);
-- 'wait' = nothing for us to do (JAs etc. may run).
function gsc_tick()
    if not gsc_active() then return false end
    ws_sc_locked = false
    if ds_state and ds_state.on then return 'wait' end
    local pl = windower.ffxi.get_player()
    local t = windower.ffxi.get_mob_by_target('t')
    if not pl or not pl.vitals or not t or not t.id or not t.hpp or t.hpp <= 0 then return 'wait' end
    local now = os.clock()
    if GSC.mob ~= t.id then GSC.mob, GSC.mob_since = t.id, now end
    GSC_MOB = t.name   -- v4.92: learned damage for this mob type
    if gsc_tp_track then pcall(gsc_tp_track) end   -- v5.04: TP gain rates
    local mem = gsc_members()
    local me
    for _, m in ipairs(mem) do if m.me then me = m end end
    if not me or #me.pool == 0 then
        gsc_dbg('pool', 'GSC: no weapon skills for ' .. tostring(me and me.weapon or '?') ..
                ' in group_skillchain.pools -- not weaponskilling.')
        return 'wait'
    end
    local my_tp = pl.vitals.tp or 0
    local ready = my_tp >= 1000 and (now - last_ws_time) >= 3.0
    -- a party WS is on its way: let it land first
    for id, bt in pairs(GSC.began) do
        if now - bt > 3.0 then GSC.began[id] = nil
        elseif id ~= pl.id then return ready and 'hold' or 'wait' end
    end
    local c = GSC.chain
    local idle_since = GSC.mob_since
    if c and c.target == t.id then
        local open_t, close_t = gsc_window(c)
        local live = #(c.props or {}) > 0 and (c.step or 1) < gsc_num('max_steps')
                     and now < close_t - gsc_num('ws_lead')
        if live then
            GSC_CLOSE_AT = close_t   -- v5.04: for the teammates' TP projection
            local cands = gsc_continuers(mem, c.props, c.actor)
            GSC_CLOSE_AT = nil
            local slots = gsc_slots(cands, open_t)   -- v5.53: learned turn lengths
            for k, cd in ipairs(cands) do
                if cd.m.me then
                    local go_at = slots[k]
                    -- v4.72: continuing your own WS: always one handoff later (teammates
                    -- see your TP late and may already be going)
                    if c.actor == me.id then go_at = math.max(go_at, open_t + gsc_num('handoff_wait')) end
                    -- v4.84: a filler (Scrach) continues one handoff late too: it sees
                    -- the melees' TP late, and Savage Blade + Shoha / Ukko's Fury on the
                    -- same resonance within 3s was the top chain-breaker (64 of 133 on
                    -- 11-19). A melee WS starting in that time holds it (GSC.began).
                    if me.filler then go_at = math.max(go_at, open_t + gsc_num('handoff_wait')) end
                    if ready and now >= go_at then
                        local late = gsc_late_guard(cands, slots, k, now)
                        if late then
                            gsc_dbg('late', 'GSC: late for my turn -- ' .. late .. "'s turn is open, giving them time first.")
                            return 'hold'
                        end
                        return gsc_fire(t, cd.ws, string.format('%s >> %s = %s (step %d, turn %d)',
                            tostring(c.label), cd.ws, cd.res, (c.step or 1) + 1, k), true)
                    end
                    if now >= go_at - 1.5 then return 'hold' end
                    return 'wait'
                end
            end
            if #cands > 0 then
                if cands[1].m.tp >= 1000 then GSC.expect = {id = cands[1].m.id, ws = cands[1].ws, t = c.t} end
                gsc_dbg('next', 'GSC: ' .. cands[1].m.name .. ' continues ' .. tostring(c.label) ..
                        ' with ' .. cands[1].ws .. ' -- holding.')
                return 'wait'
            end
        end
        c.dead_at = c.dead_at or now
        if c.dead_at > idle_since then idle_since = c.dead_at end
    end
    if not ready or (now - GSC.fired_at) < 3.0 then return 'wait' end
    -- v4.71: no new chain on a mob that is nearly dead -- keep the TP to open the next one
    if gsc_num('bank_hpp') > 0 and t.hpp <= gsc_num('bank_hpp') and my_tp < 2000 then
        gsc_dbg('bank', 'GSC: ' .. tostring(t.name or 'mob') .. ' at ' .. t.hpp .. '% -- keeping TP for the next mob.')
        return 'wait'
    end
    -- once per mob (Full Break) before chaining: players who still owe theirs
    -- on this mob open first (seen from the WS landing, so every AA agrees)
    local forced, owed_soon = {}, nil
    for _, m in ipairs(mem) do
        local pw = m.engaged and not m.filler and gsc_pre_ws(m, t.id)
        if pw and m.tp >= 1000 then
            forced[#forced + 1] = {m = m, ws = pw, key = 0}
        elseif pw and not m.me and m.tp >= gsc_num('block_tp') then
            owed_soon = owed_soon or {m = m, ws = pw}   -- v4.87: almost ready (seen late)
        end
    end
    gsc_sort(forced)
    for k, f in ipairs(forced) do
        if f.m.me and now >= idle_since + (k - 1) * gsc_num('opener_wait') then
            gsc_pre_mark(t.id, me.id)
            return gsc_fire(t, f.ws, f.ws .. ' (once per mob, opens the chain)')
        end
    end
    if #forced > 0 and now < idle_since + #forced * gsc_num('opener_wait') then
        gsc_dbg('pre', 'GSC: ' .. forced[1].m.name .. ' opens with ' .. forced[1].ws .. ' (once per mob) -- waiting.')
        return 'wait'
    end
    -- v4.87: a teammate who still owes Full Break and is at block_tp or more:
    -- wait up to pre_wait from the start of the mob (Mark, 11-19: "let's do a
    -- slightly longer wait so shadow can open with full break, since it is the
    -- best sc we have"). The 2s opener_wait ran out just as Shadow went --
    -- 32 opener collisions in 308 kills. Below block_tp: no long wait.
    local who = (#forced > 0 and not forced[1].m.me and forced[1]) or owed_soon
    if who and now < idle_since + gsc_num('pre_wait') then
        gsc_dbg('pre', 'GSC: ' .. who.m.name .. ' opens with ' .. who.ws .. ' (once per mob) -- waiting up to ' ..
                string.format('%.0f', gsc_num('pre_wait')) .. 's.')
        return 'wait'
    end
    if me.filler then
        -- magic burst first, then save the opener for a melee who is close to 1000 TP
        if skillchain_time and (now - skillchain_time) < (SC_WINDOW + 0.5) then return 'wait' end
        -- v4.72: give the melee two opener turns first (8 of 24 v4.71 collisions)
        if now < idle_since + 2 * gsc_num('opener_wait') then return 'wait' end
        if my_tp < 2900 then
            for _, m in ipairs(mem) do
                if not m.me and not m.filler and m.engaged and m.tp >= gsc_num('filler_wait_tp') then
                    gsc_dbg('filler', 'GSC: filler -- ' .. m.name .. ' is near 1000 TP, saving the opener for them.')
                    return 'wait'
                end
            end
        end
        local best, bk = nil, -1
        for _, ws in ipairs(me.pool) do
            local k = gsc_follow(gsc_props(ws), gsc_num('plan_depth'), me.id, mem, 2) + 0.1 * gsc_power(ws)
            if k > bk then best, bk = ws, k end
        end
        if best then return gsc_fire(t, best, best .. ' (filler -- no chain to wait for)') end
        return 'wait'
    end
    local ops = gsc_openers(mem)
    local oslots = gsc_slots(ops, idle_since, gsc_num('opener_wait'))   -- v5.53
    for k, op in ipairs(ops) do
        if op.m.me then
            if now >= oslots[k] then
                local late = gsc_late_guard(ops, oslots, k, now, gsc_num('opener_wait'))
                if late then
                    gsc_dbg('late', 'GSC: late for my opener turn -- ' .. late .. "'s turn is open, giving them time first.")
                    return 'wait'
                end
                return gsc_fire(t, op.ws, op.ws .. ' (opener' .. (op.capped and ', TP capped' or
                    ((op.key >= 10) and string.format(', plan value %.0f', op.key) or '')) .. ')')
            end
            gsc_dbg('open', 'GSC: ' .. ops[1].m.name .. ' opens with ' .. ops[1].ws .. ' -- waiting my turn.')
            return 'wait'
        end
    end
    return 'wait'
end
-- action event: party WS starts / lands, and the skillchain it made
function gsc_on_action(act)
    if not act or not act.actor_id or type(act.targets) ~= 'table' then return end
    local cat = act.category
    if cat == 4 then pcall(gsc_learn_mb, act); return end   -- v4.90: magic bursts
    if cat ~= 3 and cat ~= 7 and cat ~= 11 then return end
    if not gsc_party_ids()[act.actor_id] then return end
    local now = os.clock()
    if cat == 7 then   -- readying: 24931 starts, 28787 interrupted
        if act.param == 28787 then GSC.began[act.actor_id] = nil else GSC.began[act.actor_id] = now end
        return
    end
    GSC.began[act.actor_id] = nil
    local t1 = act.targets[1]
    local a1 = t1 and type(t1.actions) == 'table' and t1.actions[1]
    if not t1 or not t1.id or not a1 or t1.id == act.actor_id then return end
    -- v4.98: a job ability sent as category 3 (DRK Weapon Bash: its ID is Ruinator's)
    -- isn't a WS -- only WS messages count (185 damage, 188 miss, ...)
    if cat == 3 and not GSC_WS_MSG[a1.message] then
        local _wn = res.weapon_skills[act.param]
        gsc_dbg('notws' .. tostring(act.param) .. '|' .. tostring(a1.message),
                'GSC: action ' .. tostring(act.param) .. ' (' .. tostring(_wn and _wn.en) .. ') message ' ..
                tostring(a1.message) .. ' -- not a weapon skill (job ability), ignored.')
        return
    end
    local r = (cat == 3) and res.weapon_skills[act.param] or res.monster_abilities[act.param]
    local name = r and r.en
    local props = name and gsc_props(name)
    if cat == 3 and name then pcall(gsc_learn_ws, act, name, a1) end   -- v4.90
    if cat == 3 and name then   -- someone's once_per_mob WS landed on this mob
        local pre = gsc_cfg('once_per_mob')
        for _, pw in pairs(type(pre) == 'table' and pre or {}) do
            if pw == name then gsc_pre_mark(t1.id, act.actor_id) end
        end
    end
    if not props then
        if cat == 3 and name then   -- a WS we have no data for: the old resonance is gone
            GSC.chain = {target = t1.id, t = now, props = {}, step = 1, label = name}
        end
        return
    end
    if a1.message == 188 then return end   -- missed: no resonance
    local sc = a1.has_add_effect and GSC_SC_MSG[a1.add_effect_message] or nil
    local c = GSC.chain
    -- v5.53: learn how long after a turn opens each player's WS lands; count
    -- chain steps wiped by a WS landing too soon after them
    if cat == 3 and c and c.target == t1.id and c.t then
        local since = now - c.t
        local pid = windower.ffxi.get_player()
        pid = pid and pid.id
        if act.actor_id == pid then
            if GSC.fired_at and now - GSC.fired_at < 3 then
                GSC.my_lead = 0.8 * (GSC.my_lead or 0.9) + 0.2 * (now - GSC.fired_at)
            end
        elseif sc and c.actor ~= act.actor_id and #(c.props or {}) > 0 then
            pcall(gsc_lag_note, gsc_player_name(act.actor_id), since - gsc_num('window_open'))
        end
        if not sc and c.actor and c.actor ~= act.actor_id and #(c.props or {}) > 0 and (c.step or 1) > 1
           and since < 3.0 then
            local who = gsc_player_name(act.actor_id) or tostring(act.actor_id)
            GSC.stomps = (GSC.stomps or 0) + 1
            GSC.stomp_by[who] = (GSC.stomp_by[who] or 0) + 1
            debug_msg(string.format('GSC-STOMP: %s %s landed %.1fs after %s (step %d) -- that step was lost.',
                who, name, since, tostring(c.label), c.step or 1))
        end
    end
    -- v4.71: no-show learning -- the player we waited on used something else
    GSC.noshow[act.actor_id .. '|' .. name] = nil
    gsc_ns_set(gsc_player_name(act.actor_id), name, false)   -- v4.92: they use it again
    local ex = GSC.expect
    if ex and c and ex.t == c.t then
        pcall(gsc_rel_note, ex.id, act.actor_id == ex.id)   -- v5.53
        if not (act.actor_id == ex.id and name == ex.ws) then
            local k = ex.id .. '|' .. ex.ws
            GSC.noshow[k] = (GSC.noshow[k] or 0) + 1
            if GSC.noshow[k] == gsc_num('noshow_max') then
                local _pm = windower.ffxi.get_mob_by_id and windower.ffxi.get_mob_by_id(ex.id)
                if _pm and _pm.name then gsc_ns_set(_pm.name, ex.ws, true); pcall(gsc_k_save) end   -- v4.92: kept across reloads
                info_msg('GSC: ' .. tostring(_pm and _pm.name or ex.id) .. ' passed on ' .. ex.ws .. ' ' .. GSC.noshow[k] ..
                         'x -- not planning it for them for ' .. math.floor(NOSHOW_KEEP / 3600) .. 'h (or until they use it).')
            end
        end
        GSC.expect = nil
    end
    if sc then
        local step = ((c and c.target == t1.id) and (c.step or 1) or 1) + 1
        -- v4.72: Light made on Light (Darkness on Darkness) can't be continued
        local _, _, term = gsc_result((c and c.target == t1.id) and c.props or {}, name)
        local ends = term and (sc == 'Light' or sc == 'Darkness')
        if cat == 3 then pcall(gsc_learn_sc, act, name, a1, sc, ends) end   -- v4.90
        GSC.chain = {target = t1.id, t = now, props = ends and {} or {sc}, step = step,
                     label = ends and (sc .. ' (end)') or sc, actor = act.actor_id}
        -- v4.76: one line per step, with who closed it (Mark: one line to spot the SC damage)
        local _am = windower.ffxi.get_mob_by_id(act.actor_id)
        debug_msg(string.format('GSC: step %d %s -- %s (%s)%s', step, sc, name,
            tostring(_am and _am.name or act.actor_id), ends and ', chain ends' or ''))
    else
        GSC.chain = {target = t1.id, t = now, props = props, step = 1, label = name, actor = act.actor_id}
    end
end
-- //aa gsc [on|off|auto]
function gsc_command(arg)
    local a = arg and arg:lower()
    if a == 'on' then GSC.on = true; GSC.act_at = -10
    elseif a == 'off' then GSC.on = false; GSC.act_at = -10
    elseif a == 'auto' or a == 'config' then GSC.on = nil; GSC.act_at = -10
    elseif a == '?' then   -- v4.90: send our profile again (every AA does on "/p aa gsc ?")
        gsc_announce('asked (aa gsc ?)', 0.5 + gsc_slot() * 1.5, true)
    elseif a == 'k' or a == 'knowledge' then
        for _, l in ipairs(gsc_knowledge_lines()) do windower.add_to_chat(8, '[AutoAttack]  ' .. l) end
        return
    elseif a == 'sync' then
        gsc_sync_start('aa gsc sync', 0.5 + gsc_slot() * 1.5)
        windower.add_to_chat(8, '[AutoAttack] Group skillchain: comparing learned damage with the party.')
        return
    elseif a == 'report' or a == 'r' then   -- v4.99
        pstat_report()
        return
    elseif a == 'save' then
        GSC_KS.dirty = true; gsc_k_save()
        windower.add_to_chat(8, '[AutoAttack] Group skillchain: learning saved to ' .. gsc_k_path(GSC_KS.char or '?'))
        return
    elseif a then
        windower.add_to_chat(8, '[AutoAttack] Usage: //aa gsc [on|off|auto|?|k|sync|save|report]')
        return
    end
    local mem, n = gsc_members()
    local state = (GSC.on == false and 'OFF (//aa gsc off)') or (GSC.on == true and 'ON (//aa gsc on)')
        or ('from config (enabled = ' .. tostring(gsc_cfg('enabled')) .. ')')
    windower.add_to_chat(8, '[AutoAttack] Group skillchain ' .. state .. ' -- ' .. n .. ' player(s), ' ..
        (gsc_active() and 'ACTIVE.' or 'not active.'))
    for _, m in ipairs(mem) do
        windower.add_to_chat(8, string.format('[AutoAttack]  %s %s %s %s TP %d%s: %s',
            m.name .. ((not m.me and GSC_P.prof[m.name:lower()]) and ' (profile)' or ''), tostring(m.job or '?'),
            tostring(m.weapon or '?'), m.engaged and 'engaged' or 'idle', m.tp, m.filler and ' (filler)' or '',
            (#m.pool > 0) and table.concat(m.pool, ', ') or 'no WS'))
    end
    local c = GSC.chain
    if c then
        windower.add_to_chat(8, string.format('[AutoAttack]  last: %s, %.1fs ago, step %d.', tostring(c.label),
            os.clock() - c.t, c.step or 1))
    end
    -- v5.53: learned turn lengths and steps lost to a WS landing too soon
    local parts = {}
    for _, m in ipairs(mem) do
        if not m.me then
            local l = GSC.lag[m.name:lower()]
            local rate = gsc_rel(m.name)
            parts[#parts + 1] = string.format('%s %.1fs (%d seen%s)', m.name, gsc_gap(m), l and #l or 0,
                rate and string.format(', came %d%%', math.floor(rate * 100 + 0.5)) or '')
        end
    end
    windower.add_to_chat(8, string.format('[AutoAttack]  turns: %s; my WS lands %.1fs after sending; steps lost to a too-soon WS: %d.',
        (#parts > 0) and table.concat(parts, ', ') or '-', GSC.my_lead or 0, GSC.stomps or 0))
end


-- =========================================================================
-- v4.90: DYNAMIC GROUP SKILLCHAIN (Mark, 2026-11-20: "any of our 4 friends
-- may have different jobs and weapons ... scan the players in the party for
-- jobs, weapons, weaponskills, and then determine a plan for most damage")
-- * Skillchain properties come from Windower's res.weapon_skills
--   (skillchain_a/b/c), so every weapon works. GSC_WS above only overrides.
-- * PROFILES: each AA says its job, level, weapon and the WS it brings in a
--   hidden party line ("aa~g p ..."): on aa fight, when a player joins, after
--   zoning, on "aa gsc ?", and when its job / main hand changes while idle
--   (held weapon_hold s; Dread Spikes and mid-fight swaps such as Abyssea
--   red-proc weapons are ignored). A teammate's profile comes before the
--   job_weapons / pools guesses; without one, the WS we see them use are added.
-- * KNOWLEDGE: every AA learns each player's WS damage, the skillchain damage
--   each closing WS makes (as Light-equivalent) and magic burst damage.
--     aa_knowledge.lua                 master: shipped, read only, aa update replaces it
--     data/aa_learned_<Character>.lua  this character's learning, never shipped
--   Both are read at load. v4.98: the learning file keeps counts since the
--   master (the master lists what it already holds), so nothing is counted
--   twice or lost; the newest learn_window samples count.
--   On aa fight / a join every AA sends a digest ("aa~g d"); whoever knows the
--   most about a player sends those entries ("aa~g k"), merged the same way.
--   The release merges Shadow's (and every other) learning file on MarksPC
--   into aa_knowledge.lua, so aa update hands it to everyone.
-- * The plan values a WS by learned damage first (this player's, then the
--   party's), then the built-in tables; every skillchain step adds the
--   party's fillers' learned magic burst damage x mb_weight.
-- Hidden lines: aa_party.lua keeps every "aa~g" line out of the chat window.
-- Globals on purpose (main chunk is at the local / upvalue limit).
-- =========================================================================
GSC_PROTO = 1
GSC_KINDS = {'ws', 'sc', 'mb', 'wsm', 'scm'}
-- v4.92: wsm / scm = the same as ws / sc for one mob type ("Upheaval@Locus Dire
-- Bat"): Demisang mobs in Sortie took about half the damage of the bats
-- (Light 12.6k vs 31k). Local only -- not sent by the knowledge sync.
GSC_KINDS_SYNC = {'ws', 'sc', 'mb'}
GSC_MOB = nil   -- name of the mob the plan is for (set by gsc_tick)
GSC_RESPROPS, GSC_WSID = nil, nil
GSC_MBV = 0
GSC_K  = {ws = {}, sc = {}, mb = {}, wsm = {}, scm = {}}   -- what the plan reads (v4.98: built from the three below)
-- v4.98: GSC_KB = master + teammates' entries (more samples wins); GSC_KO = what this PC
-- learned for this character, {c = samples ever, s = their sum, a = recent average, t};
-- GSC_KP = entries taken from teammates (aa~g k), saved for the release; GSC_KU = own
-- counts the master already holds (master.used). Own samples not yet in the master =
-- c - used.c, so a file is never counted twice and a smaller file never loses its news.
GSC_KB, GSC_KO, GSC_KP, GSC_KU = nil, nil, nil, {}
GSC_KODD = {}   -- v4.98: run of low samples per entry (outlier guard)
GSC_RMOB = {}   -- v4.98: toughness of a mob type, cached
GSC_KPRE = {ws = 'pws', sc = 'psc', mb = 'pmb', wsm = 'pwsm', scm = 'pscm'}
-- v4.98: messages a real WS lands with (damage, drain, miss, no effect, resisted, MP / HP)
GSC_WS_MSG = {[185] = true, [187] = true, [188] = true, [189] = true, [197] = true,
              [224] = true, [225] = true, [226] = true, [238] = true}
GSC_KS = {char = nil, dirty = false, saved = 0, base_ver = nil}
GSC_P  = {prof = {}, seen = {}, sent = -100, pend = nil, sig = nil, sig_at = 0, sig_sent = nil,
          dig = {}, dig_mine_at = -100, dig_eval = nil, watch_at = 0}

-- skillchain properties of a WS: GSC_WS override, else Windower's resources
function gsc_props(name)
    if not name then return nil end
    local o = GSC_WS[name]
    if o then return o end
    if not GSC_RESPROPS then
        GSC_RESPROPS, GSC_WSID = {}, {}
        for id, r in pairs(res.weapon_skills or {}) do
            if type(r) == 'table' and type(r.en) == 'string' then
                GSC_WSID[r.en] = tonumber(r.id) or id
                local l = {}
                for _, k in ipairs({'skillchain_a', 'skillchain_b', 'skillchain_c'}) do
                    local v = r[k]
                    if type(v) == 'string' and GSC_LEVEL[v] then l[#l + 1] = v end
                end
                if #l > 0 then GSC_RESPROPS[r.en] = l end
            end
        end
    end
    return GSC_RESPROPS[name]
end
function gsc_ws_id(name)
    if not GSC_WSID then gsc_props('-') end
    return GSC_WSID[name]
end
function gsc_ws_name(id)
    local r = id and res.weapon_skills[id]
    return r and r.en
end
function gsc_ws_level(ws)
    local l = 0
    for _, x in ipairs(gsc_props(ws) or {}) do l = math.max(l, GSC_LEVEL[x] or 0) end
    return l
end

-- ---------------------------------------------------------------- knowledge
-- v4.92: "passed on X noshow_max times" survives a reload (Mark reloads after
-- every battle; on 11-21 it was re-learned 3 times in an hour). Kept per
-- player name for NOSHOW_KEEP s; cleared when that player uses the WS again.
GSC_NS, GSC_NS_DIRTY = {}, false
NOSHOW_KEEP = 6 * 3600
function gsc_ns_key(name, ws) return tostring(name):lower() .. '|' .. tostring(ws) end
function gsc_ns_has(name, ws)
    local t = name and GSC_NS[gsc_ns_key(name, ws)]
    return t ~= nil and os.time() - t < NOSHOW_KEEP
end
function gsc_ns_set(name, ws, on)
    if not name then return end
    local k = gsc_ns_key(name, ws)
    local v = on and os.time() or nil
    if GSC_NS[k] ~= v then GSC_NS[k] = v; GSC_NS_DIRTY = true end
end
function gsc_ns_path(char) return (windower.addon_path or '') .. 'data/aa_noshow_' .. char .. '.lua' end
function gsc_ns_load(char)
    GSC_NS, GSC_NS_DIRTY = {}, false
    local t = gsc_k_read(gsc_ns_path(char))
    for k, v in pairs(type(t) == 'table' and t or {}) do
        if type(k) == 'string' and tonumber(v) and os.time() - tonumber(v) < NOSHOW_KEEP then GSC_NS[k] = tonumber(v) end
    end
end
function gsc_ns_save(char)
    if not char or not GSC_NS_DIRTY then return end
    local out = {'-- AutoAttack: weapon skills a teammate kept passing on (group skillchain), by ' .. char,
                 '-- ["player|weapon skill"] = os.time() when it was marked; kept ' .. NOSHOW_KEEP .. 's', 'return {'}
    local keys = {}
    for k in pairs(GSC_NS) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do out[#out + 1] = string.format('  [%q] = %d,', k, GSC_NS[k]) end
    out[#out + 1] = '}'
    local fh = io.open(gsc_ns_path(char), 'wb')
    if fh then fh:write(table.concat(out, '\n') .. '\n'); fh:close(); GSC_NS_DIRTY = false end
end
function gsc_k_path(name)
    local dir = windower.addon_path or ''
    if not name then return dir .. 'aa_knowledge.lua' end
    return dir .. 'data/aa_learned_' .. name .. '.lua'
end
function gsc_k_read(path)
    local fh = io.open(path, 'rb')
    if not fh then return nil end
    local s = fh:read('*a')
    fh:close()
    local f = loadstring(s, '=' .. path)
    if not f then return nil end
    setfenv(f, {})
    local ok, t = pcall(f)
    if ok and type(t) == 'table' then return t end
    return nil
end
-- merge src into dst: per entry the one with more samples wins (tie: newer)
function gsc_k_merge(dst, src)
    local changed = 0
    for _, kind in ipairs(GSC_KINDS) do
        dst[kind] = dst[kind] or {}
        for who, tw in pairs(type(src[kind]) == 'table' and src[kind] or {}) do
            if type(who) == 'string' and type(tw) == 'table' then
                local dw = dst[kind][who] or {}
                dst[kind][who] = dw
                for key, e in pairs(tw) do
                    local n = type(e) == 'table' and tonumber(e.n)
                    local a = type(e) == 'table' and tonumber(e.a)
                    if type(key) == 'string' and n and a and n > 0 then
                        local d, t = dw[key], tonumber(e.t) or 0
                        if not d or n > d.n or (n == d.n and t > (d.t or 0)) then
                            dw[key] = {n = n, a = a, t = t}
                            changed = changed + 1
                        end
                    end
                end
            end
        end
    end
    return changed
end
-- v4.98: knowledge parts
function gsc_k_empty() return {ws = {}, sc = {}, mb = {}, wsm = {}, scm = {}} end
function gsc_k_win() return math.max(gsc_num('learn_window'), 1) end
-- own samples of this entry the master doesn't hold yet: count, recent average
function gsc_k_delta(kind, who, key)
    local o = GSC_KO and GSC_KO[kind] and GSC_KO[kind][who] and GSC_KO[kind][who][key]
    if not o then return 0, nil end
    local u = GSC_KU[kind] and GSC_KU[kind][who] and GSC_KU[kind][who][key]
    local d = (o.c or 0) - (u or 0)
    if d <= 0 then return 0, nil end
    return d, o.a
end
-- master (nb, ab) + own news (nd, ad): the newest learn_window samples count
function gsc_k_combine(nb, ab, nd, ad)
    nb, nd = nb or 0, nd or 0
    local W = gsc_k_win()
    local wo = math.min(nd, W)
    local wm = math.min(nb, math.max(W - wo, 0))
    if wo + wm <= 0 then return 0, nil end
    return nb + nd, ((wo > 0) and wo * ad or 0) / (wo + wm) + ((wm > 0) and wm * ab or 0) / (wo + wm)
end
function gsc_k_view(kind, who, key)
    local b = GSC_KB[kind][who] and GSC_KB[kind][who][key]
    local nd, ad = gsc_k_delta(kind, who, key)
    local n, a = gsc_k_combine(b and b.n or 0, b and b.a, nd, ad)
    local tw = GSC_K[kind][who]
    if n <= 0 or not a then
        if tw then tw[key] = nil end
        return
    end
    if not tw then tw = {}; GSC_K[kind][who] = tw end
    local o = GSC_KO[kind][who] and GSC_KO[kind][who][key]
    tw[key] = {n = n, a = a, t = math.max(b and b.t or 0, o and o.t or 0)}
end
function gsc_k_rebuild()
    GSC_K, GSC_RMOB = gsc_k_empty(), {}
    for _, kind in ipairs(GSC_KINDS) do
        local seen = {}
        for _, src in ipairs({GSC_KB, GSC_KO}) do
            for who, tw in pairs(src[kind] or {}) do
                for key in pairs(tw) do
                    local id = who .. '\0' .. key
                    if not seen[id] then seen[id] = true; gsc_k_view(kind, who, key) end
                end
            end
        end
    end
end
-- master.used = {{character, kind, player, key, count}, ...}: this character's part
function gsc_k_used(base, name)
    local U = gsc_k_empty()
    for _, u in ipairs(type(base) == 'table' and type(base.used) == 'table' and base.used or {}) do
        if type(u) == 'table' and u[1] == name and U[u[2]] and type(u[3]) == 'string' and type(u[4]) == 'string' then
            U[u[2]][u[3]] = U[u[2]][u[3]] or {}
            U[u[2]][u[3]][u[4]] = tonumber(u[5]) or 0
        end
    end
    return U
end
-- v4.98 learning file (format 2)
function gsc_k_own_load(own)
    for _, kind in ipairs(GSC_KINDS) do
        for who, tw in pairs(type(own[kind]) == 'table' and own[kind] or {}) do
            for key, e in pairs(type(tw) == 'table' and tw or {}) do
                local c = type(e) == 'table' and tonumber(e.c)
                if type(who) == 'string' and type(key) == 'string' and c and c > 0 then
                    GSC_KO[kind][who] = GSC_KO[kind][who] or {}
                    GSC_KO[kind][who][key] = {c = c, s = tonumber(e.s) or 0, a = tonumber(e.a) or 0, t = tonumber(e.t) or 0}
                end
            end
        end
    end
    local p = {}
    for kind, pk in pairs(GSC_KPRE) do p[kind] = own[pk] end
    gsc_k_merge(GSC_KP, p)
end
-- a pre-v4.98 learning file (totals): what it has beyond the master is this PC's news.
-- Ruinator under 1k is DRK Weapon Bash read as a WS before v4.98: dropped.
function gsc_k_legacy(own)
    local n = 0
    for _, kind in ipairs(GSC_KINDS) do
        for who, tw in pairs(type(own[kind]) == 'table' and own[kind] or {}) do
            for key, e in pairs(type(tw) == 'table' and tw or {}) do
                local en, ea = type(e) == 'table' and tonumber(e.n), type(e) == 'table' and tonumber(e.a)
                local junk = type(key) == 'string' and key:find('^Ruinator') and ea and ea < 1
                if type(who) == 'string' and type(key) == 'string' and en and ea and not junk then
                    local b = GSC_KB[kind][who] and GSC_KB[kind][who][key]
                    local d = en - (b and b.n or 0)
                    if d > 0 then
                        local u = GSC_KU[kind] and GSC_KU[kind][who] and GSC_KU[kind][who][key] or 0
                        GSC_KO[kind][who] = GSC_KO[kind][who] or {}
                        GSC_KO[kind][who][key] = {c = d + u, s = d * ea, a = ea, t = tonumber(e.t) or 0}
                        n = n + 1
                    end
                end
            end
        end
    end
    return n
end
-- load the master + this character's learning (again when the character changes)
function gsc_k_ensure()
    local pl = windower.ffxi.get_player()
    local name = pl and pl.name
    if not name or name == GSC_KS.char then return end
    if GSC_KS.char and GSC_KS.dirty then gsc_k_save() end
    GSC_KB, GSC_KO, GSC_KP, GSC_KODD = gsc_k_empty(), gsc_k_empty(), gsc_k_empty(), {}
    local base = gsc_k_read(gsc_k_path(nil))
    if base then gsc_k_merge(GSC_KB, base) end
    GSC_KU = gsc_k_used(base, name)
    local own = gsc_k_read(gsc_k_path(name))
    local legacy = 0
    if own and tonumber(own.format) == 2 then gsc_k_own_load(own)
    elseif own then legacy = gsc_k_legacy(own) end
    gsc_k_merge(GSC_KB, GSC_KP)
    gsc_k_rebuild()
    GSC_KS.char, GSC_KS.dirty, GSC_KS.saved = name, legacy > 0, os.clock()
    gsc_ns_load(name)   -- v4.92
    GSC_KS.base_ver = base and base.version or nil
    local n, news = 0, 0
    for _, v in pairs(gsc_k_totals()) do n = n + v end
    for _, kind in ipairs(GSC_KINDS_SYNC) do
        for who, tw in pairs(GSC_KO[kind]) do
            for key in pairs(tw) do news = news + (gsc_k_delta(kind, who, key)) end
        end
    end
    debug_msg('GSC: knowledge loaded for ' .. name .. ' -- master ' .. (base and ('v' .. tostring(base.version)) or 'missing') ..
              ', own file ' .. (own and ((legacy > 0) and ('converted from the old format, ' .. legacy .. ' entries') or 'found') or 'new') ..
              ', ' .. n .. ' samples (' .. news .. ' learned here, not in the master yet).')
end
function gsc_k_write(path, what)
    local ver = tostring(_addon and _addon.version or '?')
    local out = {'-- AutoAttack ' .. what .. ' -- written by AutoAttack v' .. ver .. ' on ' .. os.date('%Y-%m-%d %H:%M'),
                 '-- v4.98 format 2. [kind][player][weapon skill] = {c = samples learned here (ever),',
                 '-- s = their sum, a = recent average (thousands), t = last update}; the master holds',
                 '-- "used" counts, so only c - used counts as new. pws / psc / pmb / pwsm / pscm =',
                 '-- entries teammates sent ({n, a, t}). ws = WS damage; sc = skillchain damage when',
                 '-- this WS closes it, as Light-equivalent (Light 1.0, level 2 0.55, level 1 0.25,',
                 '-- Light on Light 1.4); mb = magic bursts; wsm / scm = per mob type ("WS@mob").',
                 'return {', string.format('version = %q,', ver), 'format = 2,',
                 string.format('master = %q,', tostring(GSC_KS.base_ver or '-'))}
    local function block(name, K, fmt)
        out[#out + 1] = name .. ' = {'
        local whos = {}
        for w in pairs(K or {}) do whos[#whos + 1] = w end
        table.sort(whos)
        for _, w in ipairs(whos) do
            out[#out + 1] = string.format('  [%q] = {', w)
            local keys = {}
            for k in pairs(K[w]) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do out[#out + 1] = string.format('    [%q] = ', k) .. fmt(K[w][k]) .. ',' end
            out[#out + 1] = '  },'
        end
        out[#out + 1] = '},'
    end
    for _, kind in ipairs(GSC_KINDS) do
        block(kind, GSC_KO[kind], function(e) return string.format('{c = %d, s = %.3f, a = %.3f, t = %d}', e.c, e.s, e.a, e.t or 0) end)
    end
    for _, kind in ipairs(GSC_KINDS) do
        block(GSC_KPRE[kind], GSC_KP[kind], function(e) return string.format('{n = %d, a = %.3f, t = %d}', e.n, e.a, e.t or 0) end)
    end
    out[#out + 1] = '}'
    local fh = io.open(path, 'wb')
    if not fh then return false end
    fh:write(table.concat(out, '\n') .. '\n')
    fh:close()
    return true
end
function gsc_k_save()
    if GSC_KS.char then gsc_ns_save(GSC_KS.char) end   -- v4.92
    if not GSC_KS.char or not GSC_KS.dirty or not GSC_KO then return end
    local dir = (windower.addon_path or '') .. 'data'
    if windower.dir_exists and windower.create_dir and not windower.dir_exists(dir) then windower.create_dir(dir) end
    if gsc_k_write(gsc_k_path(GSC_KS.char), 'learning for ' .. GSC_KS.char) then
        GSC_KS.dirty = false
    else
        debug_msg('GSC: could not write ' .. gsc_k_path(GSC_KS.char))
    end
    GSC_KS.saved = os.clock()
end
function gsc_k_add(kind, who, key, x)
    if gsc_cfg('learn') == false or not who or not key or not x or x <= 0 then return end
    gsc_k_ensure()
    local K = GSC_KO and GSC_KO[kind]
    if not K then return end
    local tw = K[who]
    if not tw then tw = {}; K[who] = tw end
    local e = tw[key]
    if not e then e = {c = 0, s = 0, a = 0, t = 0}; tw[key] = e end
    e.c, e.s = e.c + 1, e.s + x
    -- recent average: plain over the new samples, then rolling over learn_window (gear changes)
    local nd = gsc_k_delta(kind, who, key)
    e.a = e.a + (x - e.a) / math.min(math.max(nd, 1), gsc_k_win())
    e.t = os.time()
    gsc_k_view(kind, who, key)
    if kind == 'wsm' or kind == 'scm' then GSC_RMOB = {} end
    GSC_KS.dirty = true
    if os.clock() - GSC_KS.saved > gsc_num('learn_save_secs') then gsc_k_save() end
end
-- learned value: this player's (learn_min+ samples), else every player's together, else nil
function gsc_k_value(kind, who, key)
    local K = GSC_K[kind]
    if not K or not key then return nil end
    local mn = math.max(gsc_num('learn_min'), 1)
    local e = who and K[who] and K[who][key]
    if e and e.n >= mn then return e.a end
    local n, s = 0, 0
    for _, tw in pairs(K) do
        local x = tw[key]
        if x and x.n > 0 then n = n + x.n; s = s + x.a * x.n end
    end
    if n >= mn then return s / n end
    return nil
end
-- v4.98: how hard this mob type is hit, against the same WS everywhere -- all players'
-- per-mob samples together (Demisang ~0.5, bats ~1.1). 1 until learn_min samples.
function gsc_k_ratio(kind, mob)
    local id = kind .. '|' .. mob
    local c = GSC_RMOB[id]
    if c then return c end
    local mk, suf = (kind == 'ws') and 'wsm' or 'scm', '@' .. mob
    local num, den, n = 0, 0, 0
    for who, tw in pairs(GSC_K[mk] or {}) do
        for key, e in pairs(tw) do
            if #key > #suf and key:sub(-#suf) == suf then
                local all = GSC_K[kind][who] and GSC_K[kind][who][key:sub(1, -#suf - 1)]
                if all and all.a > 0 then
                    local w = math.min(e.n, gsc_k_win())
                    num, den, n = num + w * e.a, den + w * all.a, n + e.n
                end
            end
        end
    end
    local r = (n >= gsc_num('learn_min') and den > 0) and (num / den) or 1
    GSC_RMOB[id] = r
    return r
end
-- v4.98: learned figure for the mob type being planned for (GSC_MOB): this player's
-- figure for that mob, blended with (their all-mob figure x the mob's toughness) at
-- mob_k samples' weight -- one kill already moves it, and a new mob type starts from
-- the toughness the party has seen on it.
function gsc_k_est(kind, who, ws)
    local all = gsc_k_value(kind, who, ws)
    local mob = GSC_MOB
    if not mob or not ws then return all end
    local mk = (kind == 'ws') and 'wsm' or 'scm'
    local e = who and GSC_K[mk][who] and GSC_K[mk][who][ws .. '@' .. mob]
    if not all then
        if e and e.n >= math.max(gsc_num('learn_min'), 1) then return e.a end
        return nil
    end
    local prior = all * gsc_k_ratio(kind, mob)
    if not e or e.n <= 0 then return prior end
    local n, k = math.min(e.n, gsc_k_win()), math.max(gsc_num('mob_k'), 0)
    return (n * e.a + k * prior) / (n + k)
end
-- v4.98: a sample far under a settled average (odd_ratio of it, odd_min+ samples) is
-- skipped -- unless odd_repeat come in a row (then it's real: a weapon / gear change)
GSC_KBAND = {}   -- v5.00: [kind|who|ws|band] = {n, a} this session
function gsc_k_odd(kind, who, key, x, tp)
    -- v5.00: with the TP the WS was used at known, compare only with samples at
    -- similar TP (tp_band). 11-21: a 2.8k Upheaval at ~1000 TP (step 2 after Full
    -- Break) was thrown out against its 16k all-TP average -- it was normal.
    local band = gsc_num('tp_band')
    if tp and band > 0 then
        local bid = kind .. '|' .. tostring(who) .. '|' .. tostring(key) .. '|' .. math.floor(tp / band)
        local b = GSC_KBAND[bid]
        if b and b.n >= gsc_num('band_min') and x < b.a * gsc_num('odd_ratio') then
            debug_msg(string.format('GSC: %s %s %.1fk not learned -- under %d%% of its %.1fk average at %d-%d TP.', tostring(who),
                tostring(key), x, gsc_num('odd_ratio') * 100, b.a, math.floor(tp / band) * band, math.floor(tp / band) * band + band - 1))
            return true
        end
        b = b or {n = 0, a = 0}
        GSC_KBAND[bid] = b
        b.n = b.n + 1
        b.a = b.a + (x - b.a) / math.min(b.n, 30)
        return false
    end
    local e = GSC_K[kind] and GSC_K[kind][who] and GSC_K[kind][who][key]
    local id = kind .. '|' .. tostring(who) .. '|' .. tostring(key)
    if not e or e.n < gsc_num('odd_min') or x >= e.a * gsc_num('odd_ratio') then GSC_KODD[id] = nil; return false end
    local run = (GSC_KODD[id] or 0) + 1
    GSC_KODD[id] = run
    if run >= gsc_num('odd_repeat') then
        if run == gsc_num('odd_repeat') then
            debug_msg(string.format('GSC: %s %s -- %d low samples in a row, learning them (%.1fk vs %.1fk).', tostring(who), tostring(key), run, x, e.a))
        end
        return false
    end
    debug_msg(string.format('GSC: %s %s %.1fk not learned -- under %d%% of its %.1fk average.', tostring(who), tostring(key), x, gsc_num('odd_ratio') * 100, e.a))
    return true
end
-- v4.92: name of the mob an action hit
function gsc_mob_of(act)
    local t1 = act and type(act.targets) == 'table' and act.targets[1]
    local m = t1 and t1.id and windower.ffxi.get_mob_by_id(t1.id)
    return m and m.name or nil
end
function gsc_k_totals()
    local tot = {}
    for _, kind in ipairs(GSC_KINDS_SYNC) do   -- v4.92: per-mob kinds aren't synced
        for who, tw in pairs(GSC_K[kind] or {}) do
            -- v5.28: per-level keys ("WS#1") are local copies of the same samples
            for k, e in pairs(tw) do if not tostring(k):find('#', 1, true) then tot[who] = (tot[who] or 0) + e.n end end
        end
    end
    return tot
end
-- a real player in our party (not a Trust): name, else nil
function gsc_player_name(id)
    if not id or not gsc_party_ids()[id] then return nil end
    local m = windower.ffxi.get_mob_by_id(id)
    if not m or not m.name or m.is_npc or m.spawn_type == 14 then return nil end
    return m.name
end
-- WS landed (cat 3): its damage, and the WS seen for players without a profile
function gsc_learn_ws(act, name, a1)
    local who = gsc_player_name(act.actor_id)
    if not who then return end
    local key = who:lower()
    if not GSC_P.prof[key] then
        GSC_P.seen[key] = GSC_P.seen[key] or {}
        GSC_P.seen[key][name] = true
    end
    if a1.message ~= 188 and (tonumber(a1.param) or 0) > 0 then
        gsc_k_ensure()
        if gsc_k_odd('ws', who, name, a1.param / 1000, gsc_tp_at and gsc_tp_at(who)) then return end   -- v4.98 (v5.00: TP band)
        gsc_k_add('ws', who, name, a1.param / 1000)
        local mn = gsc_mob_of(act)   -- v4.92
        if mn then gsc_k_add('wsm', who, name .. '@' .. mn, a1.param / 1000) end
    end
end
-- skillchain damage, as Light-equivalent, credited to the closing WS
function gsc_learn_sc(act, name, a1, sc, ends)
    local who = gsc_player_name(act.actor_id)
    local dmg = tonumber(a1.add_effect_param) or 0
    if not who or dmg <= 0 then return end
    local mult = ends and GSC_MULT['end'] or GSC_MULT[GSC_LEVEL[sc] or 0]
    if mult and mult > 0 then
        gsc_k_ensure()
        -- v5.28: also per skillchain level, before the all-level odd check (which
        -- threw out Shoha's real 2.3k Compressions against its Light average)
        local lk = gsc_lkey(name, GSC_LEVEL[sc] or 0, ends)
        if not gsc_k_odd('sc', who, lk, dmg / 1000 / mult, gsc_tp_at and gsc_tp_at(who)) then
            gsc_k_add('sc', who, lk, dmg / 1000 / mult)
        end
        if gsc_k_odd('sc', who, name, dmg / 1000 / mult, gsc_tp_at and gsc_tp_at(who)) then return end   -- v4.98 (v5.00: TP band)
        gsc_k_add('sc', who, name, dmg / 1000 / mult)
        local mn = gsc_mob_of(act)   -- v4.92
        if mn then gsc_k_add('scm', who, name .. '@' .. mn, dmg / 1000 / mult) end
    end
end
-- magic burst damage by a party player (spell, message 252)
function gsc_learn_mb(act)
    local who = gsc_player_name(act.actor_id)
    if not who then return end
    local t1 = act.targets[1]
    local a1 = t1 and type(t1.actions) == 'table' and t1.actions[1]
    if a1 and a1.message == 252 and (tonumber(a1.param) or 0) > 0 then gsc_k_add('mb', who, 'MB', a1.param / 1000) end
end

-- ----------------------------------------------------------------- profiles
function gsc_prune(list, who)
    local mx = gsc_num('pool_max')
    if mx <= 0 or #list <= mx then return list end
    local key, out = {}, {}
    for _, ws in ipairs(list) do key[ws] = gsc_ws_level(ws) * 10 + gsc_power(ws, who); out[#out + 1] = ws end
    table.sort(out, function(a, b) return key[a] > key[b] end)
    for i = #out, mx + 1, -1 do out[i] = nil end
    return out
end
function gsc_is_trust_slot(m)
    return m.mob and (m.mob.is_npc == true or m.mob.spawn_type == 14)
end
-- our place among the party's players (0 = first): staggers our lines
function gsc_slot()
    local party, pl = windower.ffxi.get_party(), windower.ffxi.get_player()
    local k = 0
    for i = 0, 5 do
        local m = party and party['p' .. i]
        if m and m.name and not gsc_is_trust_slot(m) then
            if pl and m.name == pl.name then return k end
            k = k + 1
        end
    end
    return 0
end
function gsc_has_players()
    local party, n = windower.ffxi.get_party(), 0
    for i = 0, 5 do
        local m = party and party['p' .. i]
        if m and m.name and not gsc_is_trust_slot(m) then n = n + 1 end
    end
    return n >= 2
end
function gsc_self_profile()
    local pl = windower.ffxi.get_player()
    if not pl then return nil end
    local weapon = gsc_weapon(pl.name, pl.main_job, true)
    local sk = 0
    for id, nm in pairs(GSC_SKILL) do if nm == weapon then sk = id end end
    local pool = gsc_pool(weapon, true, pl.id, pl.name)
    local ids = {}
    for _, ws in ipairs(pool) do
        local id = gsc_ws_id(ws)
        if id then ids[#ids + 1] = id end
    end
    return {job = pl.main_job or '-', sub = pl.sub_job or '-', lvl = tonumber(pl.main_job_level) or 0,
            skill = sk, weapon = weapon, ids = ids, ws = pool}
end
function gsc_prof_sig(p)
    return p.job .. '/' .. p.sub .. ' ' .. p.lvl .. ' ' .. p.skill .. ' ' .. table.concat(p.ids, ',')
end
function gsc_hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 65536 end
    return string.format('%04x', h)
end
-- what this AA knows of the party's loadouts, as 4 hex digits (equal on every
-- AA once everyone has everyone's profile)
function gsc_view_hash()
    local party, pl = windower.ffxi.get_party(), windower.ffxi.get_player()
    local parts = {}
    for i = 0, 5 do
        local m = party and party['p' .. i]
        if m and m.name and not gsc_is_trust_slot(m) then
            local sig
            if pl and m.name == pl.name then
                local sp = gsc_self_profile()
                sig = sp and gsc_prof_sig(sp)
            else
                local pr = GSC_P.prof[m.name:lower()]
                sig = pr and pr.sig
            end
            parts[#parts + 1] = m.name:lower() .. '=' .. (sig or '?')
        end
    end
    table.sort(parts)
    return gsc_hash(table.concat(parts, ';'))
end
function gsc_party_line(line)
    if aa_party_say then aa_party_say(line) else windower.send_command('input /p ' .. line) end
end
-- send our profile in delay s (one pending send; the sooner wins).
-- force: send even if the same profile went out in the last 15s.
function gsc_announce(why, delay, force)
    if gsc_cfg('announce') == false then return end
    delay = delay or 1
    local due = os.clock() + delay
    if GSC_P.pend and GSC_P.pend.due <= due then
        GSC_P.pend.force = GSC_P.pend.force or force
        return
    end
    local job = {due = due, force = force}
    GSC_P.pend = job
    coroutine.schedule(function()
        if GSC_P.pend ~= job then return end
        GSC_P.pend = nil
        local ok, err = pcall(gsc_send_profile, why, job.force)
        if not ok then debug_msg('GSC: profile send failed: ' .. tostring(err)) end
    end, delay)
end
function gsc_send_profile(why, force)
    if not gsc_has_players() then return end
    local p = gsc_self_profile()
    if not p then return end
    local sig = gsc_prof_sig(p)
    if not force and sig == GSC_P.sig_sent and os.clock() - GSC_P.sent < 15 then return end
    GSC_P.sent, GSC_P.sig_sent, GSC_P.sig = os.clock(), sig, sig
    gsc_party_line(string.format('aa~g p %d %s/%s %d %d %s %s', GSC_PROTO, p.job, p.sub, p.lvl, p.skill,
        (#p.ids > 0) and table.concat(p.ids, ',') or '-', gsc_view_hash()))
    debug_msg('GSC: profile sent (' .. tostring(why) .. '): ' .. p.job .. ' ' .. p.lvl .. ' ' ..
              tostring(p.weapon or 'no weapon') .. ' -- ' .. ((#p.ws > 0) and table.concat(p.ws, ', ') or 'no WS'))
end
function gsc_on_profile(sender, rest)
    local ver, job, sub, lvl, sk, ids, h = rest:match('^(%d+)%s+(%S+)/(%S+)%s+(%d+)%s+(%d+)%s+(%S+)%s*(%x*)')
    if not ver then return end
    sk = tonumber(sk)
    local ws, idl = {}, {}
    if ids ~= '-' then
        for id in ids:gmatch('%d+') do
            local n = gsc_ws_name(tonumber(id))
            if n then ws[#ws + 1] = n; idl[#idl + 1] = tonumber(id) end
        end
    end
    local p = {job = job, sub = sub, lvl = tonumber(lvl), skill = sk, weapon = GSC_SKILL[sk], ws = ws, ids = idl,
               t = os.clock(), name = sender}
    p.sig = job .. '/' .. sub .. ' ' .. lvl .. ' ' .. sk .. ' ' .. table.concat(idl, ',')
    local key = sender:lower()
    local old = GSC_P.prof[key]
    GSC_P.prof[key] = p
    GSC_P.seen[key] = nil
    GSC.act_at = -10
    if not old or old.sig ~= p.sig then
        info_msg('GSC: ' .. sender .. ' -- ' .. job .. ' ' .. lvl .. ', ' .. tostring(p.weapon or 'no weapon') .. ': ' ..
                 ((#ws > 0) and table.concat(ws, ', ') or 'no WS'))
    end
    -- they see the party differently from us: make sure they have ours
    if h ~= '' and h ~= gsc_view_hash() and os.clock() - GSC_P.sent > 20 then
        gsc_announce('their party view differs', 1 + gsc_slot() * 1.5, true)
    end
end
-- once a second: our job / weapon / WS changed and stayed that way while idle -> announce
function gsc_watch()
    local now = os.clock()
    if now < GSC_P.watch_at then return end
    GSC_P.watch_at = now + 1
    if gsc_cfg('announce') == false then return end
    if ds_state and ds_state.on then return end   -- Dread Spikes weapon swap
    if not gsc_has_players() then GSC_P.sig = nil; GSC_P.sig_sent = nil; return end
    local pl = windower.ffxi.get_player()
    -- mid-fight swaps (red procs) don't count -- but the first profile after a
    -- load goes out even while engaged (v4.94: after a reload mid-fight the
    -- profiles came 2 min late, and Shadow held 5 times for Vayne's Entropy /
    -- Insurgency, which Vayne doesn't have -- he only has Cross Reaper)
    if not pl or (pl.status ~= 0 and GSC_P.sig_sent) then return end
    local p = gsc_self_profile()
    if not p or not p.weapon then return end
    local sig = gsc_prof_sig(p)
    if sig ~= GSC_P.sig then GSC_P.sig, GSC_P.sig_at = sig, now; return end
    if sig ~= GSC_P.sig_sent and now - GSC_P.sig_at >= gsc_num('weapon_hold') and not GSC_P.pend then
        gsc_announce(GSC_P.sig_sent and 'job / weapon change' or 'in a party', 0.5 + gsc_slot() * 1.5)
    end
end

-- ---------------------------------------------------------------- knowledge sync
function gsc_sync_start(why, delay)
    if gsc_cfg('sync') == false then return end
    GSC_P.dig_mine_at = os.clock() + (delay or 0)
    coroutine.schedule(function()
        local ok, err = pcall(gsc_send_digest, why)
        if not ok then debug_msg('GSC: digest failed: ' .. tostring(err)) end
    end, delay or 0)
end
function gsc_send_digest(why)
    if not gsc_has_players() then return end
    gsc_k_ensure()
    local parts = {}
    for who, n in pairs(gsc_k_totals()) do parts[#parts + 1] = who .. '=' .. n end
    table.sort(parts)
    local line = 'aa~g d ' .. ((#parts > 0) and table.concat(parts, ',') or '-')
    while #line > 110 and line:find(',') do line = line:gsub(',[^,]*$', '') end
    GSC_P.dig_mine_at = os.clock()
    gsc_party_line(line)
    debug_msg('GSC: knowledge digest sent (' .. tostring(why) .. '): ' .. line:sub(8))
    local due = os.clock() + 8
    GSC_P.dig_eval = due
    coroutine.schedule(function()
        if GSC_P.dig_eval ~= due then return end
        local ok, err = pcall(gsc_sync_eval)
        if not ok then debug_msg('GSC: sync failed: ' .. tostring(err)) end
    end, 8)
end
function gsc_on_digest(sender, rest)
    local d = {}
    for who, n in rest:gmatch('(%a+)=(%d+)') do d[who] = tonumber(n) end
    GSC_P.dig[sender:lower()] = {t = os.clock(), tot = d, name = sender}
    -- a round we didn't start (we missed the join / aa fight): answer once
    if os.clock() - GSC_P.dig_mine_at > 30 then gsc_sync_start('digest from ' .. sender, 1 + gsc_slot() * 1.5) end
end
-- for every player: if we know the most about them (digests from the last 30s;
-- a tie goes to the name first in the alphabet), send our entries for them
function gsc_sync_eval()
    local now = os.clock()
    local pl = windower.ffxi.get_player()
    local mine, myname = gsc_k_totals(), (pl and pl.name or '?'):lower()
    local others = {}
    for k, d in pairs(GSC_P.dig) do
        if now - d.t < 30 and k ~= myname then others[#others + 1] = d end
    end
    if #others == 0 then return {} end
    local gap = math.max(gsc_num('sync_min'), 1)
    local send = {}
    for who, n in pairs(mine) do
        local best, low, tie_lose = 0, math.huge, false
        for _, d in ipairs(others) do
            local x = d.tot[who] or 0
            if x > best then best = x end
            if x < low then low = x end
            if x == n and d.name:lower() < myname then tie_lose = true end
        end
        if (n > best or (n == best and not tie_lose)) and n - low >= gap then send[#send + 1] = who end
    end
    table.sort(send)
    for _, who in ipairs(send) do gsc_send_entries(who) end
    return send
end
GSC_KCODE = {ws = 'w', sc = 's', mb = 'm'}
GSC_KKIND = {w = 'ws', s = 'sc', m = 'mb'}
function gsc_send_entries(who)
    local items = {}
    for _, kind in ipairs(GSC_KINDS_SYNC) do   -- v4.92
        for key, e in pairs(GSC_K[kind][who] or {}) do
            local id = (kind == 'mb') and 0 or gsc_ws_id(key)
            if id then items[#items + 1] = string.format('%d%s%d:%.2f', id, GSC_KCODE[kind], e.n, e.a) end
        end
    end
    table.sort(items)
    -- v4.99: per mob type too: "@Locus_Dire_Bat 93W12:16.20 94S9:27.70" (W = wsm,
    -- S = scm). Older AAs skip both kinds of token.
    local mobs = {}
    for _, kind in ipairs({'wsm', 'scm'}) do
        for key, e in pairs(GSC_K[kind][who] or {}) do
            local ws, mob = key:match('^(.-)@(.+)$')
            local id = ws and gsc_ws_id(ws)
            if id and not mob:find('_', 1, true) then
                local tag = '@' .. (mob:gsub(' ', '_'))
                mobs[tag] = mobs[tag] or {}
                table.insert(mobs[tag], string.format('%d%s%d:%.2f', id, (kind == 'wsm') and 'W' or 'S', e.n, e.a))
            end
        end
    end
    local tags = {}
    for tag, l in pairs(mobs) do table.sort(l); tags[#tags + 1] = tag end
    table.sort(tags)
    local head = 'aa~g k ' .. who
    local line, n, cur = head, 0, nil
    local function put(it, tag)
        local pre = (tag and tag ~= cur) and (tag .. ' ') or ''
        if #line + 1 + #pre + #it > 110 then
            gsc_party_line(line); n = n + 1; line = head; cur = nil
            pre = tag and (tag .. ' ') or ''
        end
        line = line .. ' ' .. pre .. it
        if tag then cur = tag end
    end
    for _, it in ipairs(items) do put(it, nil) end
    for _, tag in ipairs(tags) do
        for _, it in ipairs(mobs[tag]) do put(it, tag); items[#items + 1] = it end
    end
    if line ~= head then gsc_party_line(line); n = n + 1 end
    debug_msg('GSC: sent ' .. #items .. ' learned entries for ' .. who .. ' (' .. n .. ' party lines).')
end
function gsc_on_entries(sender, rest)
    local who, body = rest:match('^(%a+)%s+(.*)$')
    if not who then return end
    gsc_k_ensure()
    local src = {ws = {[who] = {}}, sc = {[who] = {}}, mb = {[who] = {}}, wsm = {[who] = {}}, scm = {[who] = {}}}
    local mob
    for tok in body:gmatch('%S+') do
        if tok:sub(1, 1) == '@' then mob = tok:sub(2):gsub('_', ' ')   -- v4.99: per mob type
        else
            local id, c, n, a = tok:match('^(%d+)([wsmWS])(%d+):([%d%.]+)$')
            local key = id and ((c == 'm') and 'MB' or gsc_ws_name(tonumber(id)))
            if key and (c == 'W' or c == 'S') then
                if mob then src[(c == 'W') and 'wsm' or 'scm'][who][key .. '@' .. mob] = {n = tonumber(n), a = tonumber(a), t = 0} end
            elseif key then src[GSC_KKIND[c]][who][key] = {n = tonumber(n), a = tonumber(a), t = 0} end
        end
    end
    local ch = gsc_k_merge(GSC_KB, src)   -- v4.98: into the base (and kept for the release)
    gsc_k_merge(GSC_KP, src)
    if ch > 0 then
        gsc_k_rebuild()
        GSC_KS.dirty = true
        debug_msg('GSC: ' .. ch .. ' learned entries for ' .. who .. ' taken from ' .. sender .. '.')
    end
end
-- "aa~g ..." party line from a friend in the party (aa_party.lua checks who sent it)
function gsc_proto(sender, text)
    local verb, rest = text:match('^[Aa][Aa]~[Gg]%s+(%a)%s*(.*)$')
    if not verb or not sender then return end
    verb = verb:lower()
    if verb == 'p' then gsc_on_profile(sender, rest)
    elseif verb == 'd' then gsc_on_digest(sender, rest)
    elseif verb == 'k' then gsc_on_entries(sender, rest)
    elseif verb == 's' then pstat_on_stats(sender, rest)   -- v4.99
    elseif verb == 'e' then pstat_on_event(sender, rest)
    elseif verb == 'q' then pstat_on_query(sender) end
end
-- aa_party.lua calls these (each AA waits by its place in the party: 1.5s apart)
function gsc_on_fight()
    local s = gsc_slot()
    gsc_announce('aa fight', 1 + s * 1.5, true)
    gsc_sync_start('aa fight', 9 + s * 1.5)
end
function gsc_on_join(name)
    local s = gsc_slot()
    gsc_announce(tostring(name) .. ' joined', 3 + s * 1.5, true)
    gsc_sync_start(tostring(name) .. ' joined', 11 + s * 1.5)
end
function gsc_on_zone()
    gsc_k_save()
    gsc_announce('zoned', 20 + gsc_slot() * 1.5, true)
end
-- //aa gsc k: what we have learned about the party's players
function gsc_knowledge_lines()
    gsc_k_ensure()
    local lines = {}
    for _, m in ipairs((gsc_members())) do
        local parts = {}
        for ws, e in pairs(GSC_K.ws[m.name] or {}) do
            local s = GSC_K.sc[m.name] and GSC_K.sc[m.name][ws]
            parts[#parts + 1] = string.format('%s %.1fk x%d%s', ws, e.a, e.n,
                s and string.format(' (SC %.1fk x%d)', s.a, s.n) or '')
        end
        local mb = GSC_K.mb[m.name] and GSC_K.mb[m.name].MB
        if mb then parts[#parts + 1] = string.format('MB %.1fk x%d', mb.a, mb.n) end
        table.sort(parts)
        lines[#lines + 1] = m.name .. ': ' .. ((#parts > 0) and table.concat(parts, '; ') or 'nothing learned yet')
    end
    return lines
end


-- v5.00: MAGIC BURST rework (11-21: Scrach's Fire IV did 9-10k as a burst, 2.7k
-- without; half his Fire IVs burst only by luck).
--   * A skillchain bursts every element it carries: Light = fire / lightning /
--     wind / light, Fusion = fire / light, Distortion = ice / water, ... (the
--     old code looked up one element -- "light" -- which RDM has no list for).
--   * MB_WINDOW s to start the cast (was 3s), and the cast must end inside it.
--   * The strongest ready spell from those lists (MP cost), the mob's weakness
--     element first on a near tie.
--   * group_skillchain.burst = true turns bursting on for a filler job (RDM,
--     BLM, ...) while the group skillchain is active, even when that job's
--     weakness_spells.mb_enabled is false.
MB_WINDOW = 7.0
MB_SC = nil
SC_BURST = {
    Light = {'fire', 'lightning', 'wind', 'light'}, Darkness = {'ice', 'water', 'earth', 'dark'},
    Gravitation = {'earth', 'dark'}, Fragmentation = {'lightning', 'wind'},
    Distortion = {'ice', 'water'}, Fusion = {'fire', 'light'},
    Compression = {'dark'}, Liquefaction = {'fire'}, Induration = {'ice'}, Reverberation = {'water'},
    Transfixion = {'light'}, Scission = {'earth'}, Detonation = {'wind'}, Impaction = {'lightning'},
}
-- a filler job bursting because the group skillchain is on
function mb_party_burst()
    if not gsc_cfg or gsc_cfg('burst') == false then return false end
    local pl = windower.ffxi.get_player()
    local job = pl and pl.main_job
    local list = gsc_cfg('filler_jobs')
    local filler = false
    for _, j in ipairs(type(list) == 'table' and list or {}) do if j == job then filler = true end end
    return filler and gsc_active and gsc_active() or false
end
function mb_enabled_now()
    local w = current_config and current_config.weakness_spells
    if not w then return false end
    if w.mb_enabled ~= false then return true end
    return mb_party_burst()
end
local function mb_clear() MB_SC = nil; skillchain_element = nil; skillchain_time = nil end
function use_magic_burst()
    local sc = MB_SC
    if not sc and not (skillchain_element and skillchain_time) then return false end
    if not mb_enabled_now() then mb_clear(); return false end
    local now = os.clock()
    local t0 = (sc and sc.t) or skillchain_time
    if not t0 or (now - t0) > MB_WINDOW then mb_clear(); return false end
    local w = current_config.weakness_spells
    local player = windower.ffxi.get_player()
    if not player or not player.vitals then return false end
    local target = windower.ffxi.get_mob_by_target('t')
    if not target or not target.name or not target.hpp or target.hpp <= 0 then return false end
    if sc and sc.mob and sc.mob ~= target.id then return false end   -- the chain was on another mob
    local elems = (sc and SC_BURST[sc.name]) or {skillchain_element}
    local weak = nil
    for pattern, el in pairs(mob_weaknesses) do
        if target.name:find(pattern, 1, true) then weak = el; break end
    end
    local recasts = windower.ffxi.get_spell_recasts()
    if not recasts then return false end
    local fc = (current_config.magic and current_config.magic.fast_cast_pct) or 0
    local best, best_data, best_score
    for _, el in ipairs(elems) do
        for _, e in ipairs(type(w[el]) == 'table' and w[el] or {}) do
            if type(e) == 'table' and e.name then
                local sd = res_with('spells', 'english', e.name)
                if sd and sd.id and (recasts[sd.id] or -1) == 0 and (player.vitals.mp or 0) >= (sd.mp_cost or 0)
                   and check_ninja_tools(e.name) then
                    local cast = (sd.cast_time or 3.0) * math.max(0.1, (100 - fc) / 100)
                    local score = (sd.mp_cost or 0) * ((el == weak) and 1.15 or 1)
                    if (now - t0) + cast <= MB_WINDOW + 0.5 and (not best_score or score > best_score) then
                        best, best_data, best_score = e, sd, score
                    end
                end
            end
        end
    end
    if not best then
        if gsc_dbg then gsc_dbg('mbnone', 'MB: nothing ready for ' .. tostring(sc and sc.name or skillchain_element) ..
            ' (' .. table.concat(elems, '/') .. ').') end
        return false
    end
    info_msg(string.format('MB: %s on %s (%s, %.1fs into the window)', best.name, tostring(target.name),
        tostring(sc and sc.name or skillchain_element), now - t0))
    face('f')
    coroutine.sleep(0.1)  -- let face resolve before spell fires (prevents invalid arg)
    cmd('input /ma "' .. tostring(best.name) .. '" <t>')
    magic_last_used[best.name] = os.time()
    magic_use_tracker[best.name] = (magic_use_tracker[best.name] or 0) + 1
    mb_clear()
    local bct = best_data.cast_time or 3.0
    local act = bct * math.max(0.1, (100 - fc) / 100)
    coroutine.sleep(best.cast_time or math.max(act + 1.5, 2.5))
    return true
end
-- v5.00: hold weakness nukes while a skillchain step is live on our mob, so they
-- go off as bursts (group_skillchain.nuke_hold; a filler only, bursting on)
function nuke_hold_active()
    if not gsc_cfg or gsc_cfg('nuke_hold') == false or not gsc_active or not gsc_active() then return false end
    if not mb_enabled_now() then return false end
    local w = current_config and current_config.weakness_spells
    if not (w and w.mb_enabled ~= false) and not mb_party_burst() then return false end
    local pl = windower.ffxi.get_player()
    local job = pl and pl.main_job
    local filler = false
    for _, j in ipairs(type(gsc_cfg('filler_jobs')) == 'table' and gsc_cfg('filler_jobs') or {}) do if j == job then filler = true end end
    if not filler then return false end
    local t = windower.ffxi.get_mob_by_target('t')
    local c = GSC and GSC.chain
    if not t or not c or c.target ~= t.id or #(c.props or {}) == 0 or (c.step or 1) >= gsc_num('max_steps') then return false end
    local _, close_t = gsc_window(c)
    if os.clock() >= close_t then return false end
    gsc_dbg('nukehold', string.format('MB-HOLD: %s live (step %d) -- holding nukes for the burst.', tostring(c.label), c.step or 1))
    return true
end




-- Helper function to check for the buff
local function has_buff(player_buffs, buff_id)
    if not player_buffs or not buff_id then return false end
    for _, id in pairs(player_buffs) do
        if id == buff_id then return true end
    end
    return false
end

function use_item_food()
    local player = windower.ffxi.get_player()
    local target = windower.ffxi.get_mob_by_target('t')
    
    if not player or not player.name then return false end

    local item_cfg = current_config
    if not item_cfg or not item_cfg.item_food then
        -- debug_msg('No item_food config found for ' .. player.main_job)
        return false
    end
	if item_cfg.item_food.enabled == false then return false end
	-- v4.42: same kill hold as rings -- no /item within RING_KILL_HOLD s of a
	-- kill / casket / dead cursor (10/11 01:03 crash: /item 3s after a kill)
	if DEAD_MOB_GUARD and (os.clock() - last_kill_clock) < (RING_KILL_HOLD or 5) then return false end
	
    local now = os.time()
    local player_name = player.name:lower()

    for _, entry in ipairs(item_cfg.item_food) do
        local item_name = entry.name
        local xml_key = item_name:lower():gsub("[%s%p]", "")
        
        item_mob_use_count[xml_key] = item_mob_use_count[xml_key] or {}

        -- A. Check min_time logic -- use in-memory timer as primary (more reliable than settings after reload)
        local min_time = entry.min_time or 0
        local last_use_mem  = food_last_used_time[xml_key] or 0
        local last_use_disk = settings.item_timers[xml_key] or 0
        local last_use = math.max(last_use_mem, last_use_disk)  -- whichever is more recent
        local time_passed = now - last_use
        local ready_on_time = time_passed >= min_time

        -- B. Check uses_per_mob
        local ready_for_mob = true
        local current_mob_uses = 0
        if target and entry.uses_per_mob then
            current_mob_uses = item_mob_use_count[xml_key][target.id] or 0
            if current_mob_uses >= entry.uses_per_mob then
                ready_for_mob = false
            end
        end

        -- C. Check if buff is already active
        local has_active_buff = has_buff(player.buffs, entry.buff_id)

        -- DEBUG LOGGING
        -- debug_msg(string.format('Checking %s: TimeReady: %s (%ds left), MobReady: %s (Used %d/%s), HasBuff: %s', 
            -- item_name, 
            -- tostring(ready_on_time), 
            -- ready_on_time and 0 or (min_time - time_passed),
            -- tostring(ready_for_mob), 
            -- current_mob_uses, 
            -- tostring(entry.uses_per_mob or 'N/A'),
            -- tostring(has_active_buff)
        -- ))

        -- D. Execution
        if ready_on_time and ready_for_mob and not has_active_buff then
			local info = windower.ffxi.get_info()
			if info and info.moving then
				debug_msg('Skipping ' .. item_name .. ': Player is moving.')
				return false
			end

            -- v3.27: Inventory stock check — skip (don't burn the cooldown timer)
            -- if we have none of the item. Catches empty food / Silt Pouch stocks.
            local stock = get_tool_count(item_name)
            if stock == 0 then return false end

            info_msg('SUCCESS: Using ' .. item_name .. ' (' .. stock .. ' in inventory).')
            local item_target = entry.target or '<me>'
            if item_target:sub(1,1) ~= '<' then item_target = '"' .. item_target .. '"' end
            cmd('input /item "' .. item_name .. '" ' .. item_target)
            
            settings.item_timers[xml_key] = now
            food_last_used_time[xml_key] = now  -- in-memory backup
            config.save(settings) 			
            
            if target then
                item_mob_use_count[xml_key][target.id] = (item_mob_use_count[xml_key][target.id] or 0) + 1
            end
            
            return true 
        end
    end

    return false
end




function get_tool_count(tool_name, debug_dump)
    -- v4.61: inventory only (was every bag), and items compared by ID: the
    -- tool's ID is looked up once by name (cached) instead of looking up the
    -- name of every inventory slot on every check.
    local inv = windower.ffxi.get_items(0)
    if type(inv) ~= 'table' then return 0 end
    if debug_dump then
        for _, slot in pairs(inv) do
            if type(slot) == 'table' and slot.id and slot.id > 0 then
                local item_data = aa_item(slot.id)
                info_msg('INV SLOT: "' .. tostring(item_data and item_data.en or slot.id) .. '" x' .. (slot.count or 1))
            end
        end
    end
    local want = aa_item_named(tostring(tool_name or ''))
    if not want or not want.id then return 0 end
    local count = 0
    for _, slot in pairs(inv) do
        if type(slot) == 'table' and slot.id == want.id then
            count = count + (slot.count or 1)
        end
    end
    return count
end

-- Call once to dump full inventory to log (for debugging tool name mismatches)
function dump_inventory()
    info_msg('=== INVENTORY DUMP START ===')
    get_tool_count('__none__', true)
    info_msg('=== INVENTORY DUMP END ===')
end

function restock_ninja_tool(spell_name)
    local tool_info = ninja_tools[spell_name]
    if not tool_info or not tool_info.toolbag then
        debug_msg('TOOLS: No toolbag defined for ' .. tostring(spell_name))
        return false
    end

    -- v3.19: Universal toolbags only work when NIN is main job.
    -- Sub-NIN (e.g. WAR/NIN) must carry raw tools directly in inventory.
    local p = windower.ffxi.get_player()
    if not p or p.main_job ~= 'NIN' then
        debug_msg('TOOLS: Sub-NIN detected (' .. (p and p.main_job or '?') .. '/' .. (p and p.sub_job or '?') .. ') — toolbag unpack skipped, carry raw ' .. tool_info.tool .. ' in inventory')
        return false
    end

    local toolbag_count = get_tool_count(tool_info.toolbag)
    debug_msg('TOOLS: Toolbag check: ' .. tool_info.toolbag .. ' = ' .. toolbag_count .. ' in inventory')
    if toolbag_count == 0 then
        info_msg('TOOLS: Toolbag not in inventory — add ' .. tool_info.toolbag .. ' to main bag to auto-unpack')
        return false
    end

    debug_msg('TOOLS: Unpacking ' .. tool_info.tool .. ' from ' .. tool_info.toolbag)
    cmd('input /item "' .. tool_info.toolbag .. '" <me>')
    coroutine.sleep(1.5)
    return true
end

function check_ninja_tools(spell_name)
    local player = windower.ffxi.get_player()
    -- v3.14: check sub_job too — WAR/NIN and other /NIN combos need tool validation
    if not player or (player.main_job ~= 'NIN' and player.sub_job ~= 'NIN') then return true end

    local tool_info = ninja_tools[spell_name]
    if not tool_info then
        debug_msg('TOOLS: No tool entry for ' .. tostring(spell_name) .. ' — allowing cast')
        return true
    end

    local count = get_tool_count(tool_info.tool)
    debug_msg('TOOLS: ' .. spell_name .. ' needs ' .. tool_info.tool .. ', found ' .. count .. ' in inventory')

    if count == 0 then
        debug_msg('TOOLS: Out of ' .. tool_info.tool .. ' — attempting restock from ' .. tool_info.toolbag)
        local restocked = restock_ninja_tool(spell_name)
        if restocked then
            count = get_tool_count(tool_info.tool)
            debug_msg('TOOLS: After unpack, ' .. tool_info.tool .. ' count = ' .. count)
        end
        if count == 0 then
            info_msg('TOOLS: Still 0 ' .. tool_info.tool .. ' after restock — skipping ' .. spell_name)
            return false
        end
    elseif count < 10 then
        debug_msg('TOOLS: Low supply (' .. count .. ') of ' .. tool_info.tool .. ' — proactive restock')
        restock_ninja_tool(spell_name)
    end

    return true
end





-- v3.40: Helper — returns the buff array for a named party member using get_party()
-- data, which is populated from packet 0x076 and contains real buff IDs for ALL
-- party members. get_mob_by_name() does NOT carry .buffs for non-local players.
-- v3.42: For the LOCAL player, the server does NOT send a 0x076 party buff packet
-- for their own slot, so party[pX].buffs is nil/empty for them. Return player.buffs
-- (from get_player()) directly when the name matches the local character.
-- v4.95: party members' buffs from packet 0x076 (Party Buffs). Windower's
-- get_party() has no .buffs, so Scrach's Haste II on Shadow ran on the
-- buff_duration timer alone (300s, while it lasted ~256s on him) and never
-- noticed a cast that didn't land. 0x076: up to 5 entries of 48 bytes from
-- offset 4 -- ID (4), index (2), 2 unused, 64-bit mask (2 high bits per buff),
-- 32 buff low bytes (255 = none). Buff ID = low + 256 * high bits.
PARTY_BUFFS = {}   -- [player id] = {at = os.clock(), ids = {...}}
PARTY_BUFFS_FRESH = 600   -- s: older data is ignored (left the party, packet stopped)
function party_buffs_parse(data)
    if type(data) ~= 'string' then return end
    for e = 0, 4 do
        local b = 4 + e * 48            -- 0-based offset of the entry
        if #data < b + 48 then break end
        local id = data:byte(b + 1) + data:byte(b + 2) * 256 + data:byte(b + 3) * 65536 + data:byte(b + 4) * 16777216
        if id > 0 then
            local ids = {}
            for k = 0, 31 do
                local low = data:byte(b + 17 + k)
                if low ~= 255 then
                    local mb = data:byte(b + 9 + math.floor(k / 4))
                    local hi = math.floor(mb / (2 ^ ((k % 4) * 2))) % 4
                    ids[#ids + 1] = low + 256 * hi
                end
            end
            PARTY_BUFFS[id] = {at = os.clock(), ids = ids}
        end
    end
end
function party_buffs_of(member)
    local id = member and ((member.mob and member.mob.id) or member.id)
    local e = id and PARTY_BUFFS[id]
    if e and os.clock() - e.at < PARTY_BUFFS_FRESH then return e.ids end
    return nil
end
-- v4.95: can this party member be buffed right now? (same zone, in view, alive,
-- in range). A member who can't was still picked first, the cast was skipped,
-- and the timer never moved -- so one member away (Mythrandiir in another zone)
-- blocked Haste II for everyone after him in the party list.
function buff_member_ok(member, entry, player_data)
    if not member or not member.name then return false end
    if player_data and player_data.name and member.name:lower() == player_data.name:lower() then return true end
    local info = windower.ffxi.get_info()
    if member.zone and info and info.zone and member.zone ~= info.zone then return false end
    local mob = member.mob or windower.ffxi.get_mob_by_name(member.name)
    if not mob or not mob.distance then return false end
    if (member.hpp or mob.hpp or 1) <= 0 then return false end
    if mob.distance:sqrt() > ((entry and entry.max_dist) or 21) then return false end
    return true
end
local function get_member_buffs(t_name, player_data, party_data)
    if not t_name then return nil end
    if t_name == '<me>' then
        return player_data and player_data.buffs or nil
    end
    -- v3.42: Local player's party slot has no 0x076 buff data — use get_player() directly.
    if player_data and player_data.name and
       player_data.name:lower() == t_name:lower() then
        return player_data.buffs or nil
    end
    if party_data then
        for key, member in pairs(party_data) do
            if type(member) == 'table' and type(key) == 'string' and key:match('^p[0-5]$') then
                if member.name and member.name:lower() == t_name:lower() then
                    return member.buffs or party_buffs_of(member)   -- v4.95: 0x076
                end
            end
        end
    end
    return nil  -- not found in party or no buff data
end

function use_magic(buff_only)
    if not current_config.magic then return end
    if current_config.magic.enabled == false then return end

    local player = windower.ffxi.get_player()
    -- Abort if player unavailable, or Silenced (6) or Omerta (592)
    if not player or not player.buffs then return false end
    if table.contains(player.buffs, 6) or table.contains(player.buffs, 592) then return false end

    local target = windower.ffxi.get_mob_by_target('t')
    local party = windower.ffxi.get_party()
	if not party then return false end
	
	local spell_recasts = windower.ffxi.get_spell_recasts()
	if not spell_recasts then return false end

    local current_time = os.time()

    for i, entry in ipairs(current_config.magic) do
        if not entry or not entry.name then break end
        -- v3.69: Outside battle, skip debuffs and damage — no enemy target exists.
        if buff_only and (entry.type == 'debuff' or entry.type == 'damage') then
            -- skip this entry; continue to next
        else
        local spell_data = res_with('spells', 'english', entry.name)
        if spell_data then
            -- v3.40: Resolve effective_target.
            -- Three resolution modes, checked in order:
            --   1. 'targets' array on a buff entry  → first member without the buff
            --   2. type='buff_party'                → first party member without the buff
            --   3. type='buff_party_mages'          → same but only members with mp > 0
            -- In all cases the per-target composite key keeps timers independent.
            local effective_target = entry.target

            if entry.type == 'buff' and type(entry.targets) == 'table' then
                -- Explicit targets list: iterate until someone needs it
                -- v3.43: same two-path logic — buff data present → check buff,
                -- buff data nil → use buff_duration as the recast gate
                effective_target = nil
                for _, t_name in ipairs(entry.targets) do
                    local tk    = entry.name .. '||' .. t_name
                    local t_now = os.time()
                    local t_last = magic_last_used[tk] or 0
                    local t_buffs = get_member_buffs(t_name, player, party)
                    local needs_buff = false
                    if t_buffs ~= nil then
                        local has_buff = entry.buff_id and table.contains(t_buffs, entry.buff_id)
                        -- dur_expired: stale-0x076 safety net for REMOTE party members only.
                        -- Local player buff data (get_player()) is always accurate — skip override.
                        local is_self_t = player and player.name and t_name:lower() == player.name:lower()
                        local dur_expired = not is_self_t and entry.buff_duration and (t_now - t_last) >= entry.buff_duration
                        if (not has_buff or dur_expired) and (t_now - t_last) >= (entry.min_time or 0) then
                            needs_buff = true
                        end
                    else
                        local dur = entry.buff_duration or 180
                        if (t_now - t_last) >= dur then needs_buff = true end
                    end
                    if needs_buff then effective_target = t_name; break end
                end

            elseif entry.type == 'buff_party' or entry.type == 'buff_party_mages' then
                -- Auto-rotate through all party slots (p0-p5).
                -- Both real players AND trusts appear in party slots and are considered.
                --
                -- buff_party_mages: only members whose ESTIMATED max MP >= min_mp_pool.
                --   Estimate = member.mp * 100 / member.mpp (requires mpp > 0).
                --   Default threshold 400 — filters melees with small ML/gear MP pools
                --   while including any job with a meaningful mage-scale MP pool.
                --   Set entry.min_mp_pool to override per-entry.
                --
                -- only_names (table): whitelist — only buff names in this list.
                -- skip_names (table): blacklist — always skip names in this list.
                local check_min_mp = (entry.type == 'buff_party_mages')
                local min_mp_pool  = entry.min_mp_pool or 400
                effective_target = nil
                for _, slot in ipairs({'p0','p1','p2','p3','p4','p5'}) do
                    local member = party[slot]
                    if member and member.name then
                        local name_lower = member.name:lower()

                        -- only_names whitelist check
                        local passes_only = true
                        if type(entry.only_names) == 'table' then
                            passes_only = false
                            for _, n in ipairs(entry.only_names) do
                                if n:lower() == name_lower then passes_only = true; break end
                            end
                        end

                        -- skip_names blacklist check
                        local in_skip = false
                        if passes_only and type(entry.skip_names) == 'table' then
                            for _, n in ipairs(entry.skip_names) do
                                if n:lower() == name_lower then in_skip = true; break end
                            end
                        end

                        -- Mage filter: estimated max MP must meet threshold.
                        -- If mpp==0 (member at 0% MP), can't estimate — include them
                        -- conservatively (they may be a mage who burned all MP).
                        local passes_mage = true
                        if check_min_mp and passes_only and not in_skip then
                            local mpp = member.mpp or 0
                            if mpp > 0 then
                                local est_max_mp = math.floor((member.mp or 0) * 100 / mpp)
                                passes_mage = (est_max_mp >= min_mp_pool)
                            end
                        end

                        if passes_only and not in_skip and passes_mage and buff_member_ok(member, entry, player) then   -- v4.95
                            local tk    = entry.name .. '||' .. member.name
                            local t_now = os.time()
                            local t_last = magic_last_used[tk] or 0
                            local t_buffs = get_member_buffs(member.name, player, party)
                            local needs_buff = false

                            -- v3.43: Two-path buff check:
                            --   A) buff data available → check buff presence, use min_time as anti-spam
                            --   B) buff data nil (trust or untracked) → use buff_duration (default 180s)
                            --      so we cast once then wait the full duration before re-evaluating
                            if t_buffs ~= nil then
                                local has_buff = entry.buff_id and table.contains(t_buffs, entry.buff_id)
                                -- dur_expired: stale-0x076 safety net for REMOTE party members only.
                                -- Local player buff data (get_player()) is always accurate — skip override.
                                local is_self_m = player and player.name and member.name:lower() == player.name:lower()
                                local dur_expired = not is_self_m and entry.buff_duration and (t_now - t_last) >= entry.buff_duration
                                if (not has_buff or dur_expired) and (t_now - t_last) >= (entry.min_time or 0) then
                                    needs_buff = true
                                end
                            else
                                -- No buff data (trust or untracked) — use buff_duration as the recast gate
                                local dur = entry.buff_duration or 180
                                if (t_now - t_last) >= dur then
                                    needs_buff = true
                                end
                            end

                            if needs_buff then
                                effective_target = member.name
                                break
                            end
                        end
                    end
                end
            end

            -- v3.40: Per-target composite key so each spell+person pair has its own timer.
            -- e.g. 'Haste II||Mythrandiir' and 'Haste II||Shadowhammer' are independent.
            local magic_key = entry.name .. '||' .. (effective_target or '')
            local last_call = magic_last_used[magic_key] or 0
            local max_uses = entry.uses_per_mob or 999
            local current_uses = magic_use_tracker[magic_key] or 0
            local skip_spell = false

            -- 1. Identify Target
            local target_mob = nil
            local cast_target = nil

            if not effective_target then skip_spell = true
            elseif effective_target:match('^p[0-5]$') then
                -- Convert 'p1' -> '<p1>' for game command
                cast_target = '<' .. effective_target .. '>'
                if party[effective_target] and party[effective_target].mob then
                    target_mob = party[effective_target].mob
                end
            elseif effective_target == '<me>' or effective_target == '<t>' then
                cast_target = effective_target
                if effective_target == '<me>' then
                    target_mob = player
                else
                    target_mob = target
                end
            else
                -- Named target: wrap in quotes for the game command
                cast_target = '"' .. effective_target .. '"'
                target_mob = windower.ffxi.get_mob_by_name(effective_target)
            end

            -- 2. Safety Guard: Skip if target or cast_target is missing
            if not target_mob or not cast_target then 
                skip_spell = true 
            end
			

			-- 4. Distance and Logic Checks
			if not skip_spell then
                local dist = 0
			
                
                -- Guard for line 587: Player object has no .distance field
                if target_mob and target_mob.id ~= player.id then
                    if target_mob.distance then
                        dist = target_mob.distance:sqrt()
                    else
                        skip_spell = true
                    end
                end

                if not skip_spell then
                    local max_range = entry.max_dist or 21
                    
                    if dist > max_range then
                        skip_spell = true
                    elseif entry.type == 'heal' and entry.hp_threshold then
                        local hpp = target_mob and target_mob.hpp or 100
						if effective_target and effective_target:match('^p[0-5]$') and party[effective_target] then
							hpp = party[effective_target].hpp or 100
						end
                        if hpp >= entry.hp_threshold then skip_spell = true end
					elseif entry.type == 'buff'
					    or entry.type == 'buff_party'
					    or entry.type == 'buff_party_mages' then
						-- v3.40: Named targets use get_party() for accurate buff data.
						-- get_mob_by_name() does NOT populate .buffs for other players.
						local check_buffs = nil
						if effective_target == '<me>' then
							check_buffs = player.buffs
						elseif effective_target and effective_target:match('^p[0-5]$') and party[effective_target] then
							check_buffs = party[effective_target] and party[effective_target].buffs or nil
						else
							check_buffs = get_member_buffs(effective_target, player, party)
							if not check_buffs and target_mob then
								check_buffs = target_mob.buffs  -- fallback (usually nil for non-local players)
							end
						end
						-- v3.46: Compute dur_expired here too, using the already-resolved magic_key.
						-- When dur_expired=true (buff_duration elapsed or fresh session t_last=0),
						-- we allow the cast to proceed even if buff data shows it as active.
						-- This is the Section-4 counterpart to the resolution-loop dur_expired fix.
						-- v3.46b: Suppress for local player — their buff data (get_player()) is
						-- always accurate, so the stale-data override must never fire for self.
						local is_self_s4 = player and player.name and effective_target and
						    effective_target:lower() == player.name:lower()
						local dur_expired_s4 = not is_self_s4 and
						    entry.buff_duration and (current_time - last_call) >= entry.buff_duration
						-- Check single buff_id — skip only when buff is present AND NOT expired
						if entry.buff_id and check_buffs and table.contains(check_buffs, entry.buff_id)
						   and not dur_expired_s4 then
							skip_spell = true
						end
						-- Check buff_any list - skip if ANY of these buffs are active (and not expired)
						if not skip_spell and entry.buff_any and check_buffs then
							for _, bid in ipairs(entry.buff_any) do
								if table.contains(check_buffs, bid) and not dur_expired_s4 then
									skip_spell = true
									break
								end
							end
						end
						-- Check min_time for buff spells
                        if not skip_spell and (current_time - last_call) < (entry.min_time or 0) then
                            skip_spell = true
                        end
					end
                end
            end

            -- 5. MP Safety for Damage Spells
            if entry.type == 'damage' then
				-- v2.74: guard max_mp == 0 (divide-by-zero on non-MP jobs)
				if not player.vitals or (player.vitals.max_mp or 0) == 0
				   or (player.vitals.mp / player.vitals.max_mp) * 100 < 30 then
					skip_spell = true
				end
			end

            -- v3.20: Ninja tool check runs here (after buff/distance checks) so we
            -- only scan inventory when we're actually about to cast, not every tick.
            if not skip_spell and not check_ninja_tools(entry.name) then
                skip_spell = true
            end

            -- 6. Final Verification & Execution
            if not skip_spell and
			   spell_data.id ~= nil and
			   current_uses < max_uses and
			   (spell_recasts[spell_data.id] or -1) == 0 and
               ((player.vitals and player.vitals.mp) or 0) >= spell_data.mp_cost and
               (current_time - last_call) >= (entry.min_time or 0) then
                
                -- Auto-face target for offensive spells
                if entry.type == 'debuff' or entry.type == 'damage' then
                    face('f')
                    coroutine.sleep(0.1)  -- let face resolve before spell fires (prevents invalid arg)
                end

                magic_last_used[magic_key] = current_time   -- v3.40: per-target key
                magic_use_tracker[magic_key] = current_uses + 1

                -- If targeting the mob, recheck it's still alive right before firing
                if cast_target == '<t>' then
                    local t_mg = windower.ffxi.get_mob_by_target('t')
                    if not t_mg or not t_mg.hpp or t_mg.hpp <= 0 then return false end
                end
                debug_msg('Casting: ' .. entry.name .. ' on ' .. (effective_target or 'Unknown'))
                -- Uses dynamic target (e.g., <p1> or <me>) instead of hardcoded <t>
                local magic_cmd = 'input /ma "' .. tostring(entry.name) .. '" ' .. tostring(cast_target)
                cmd(magic_cmd)
                -- v3.45: cast_time in res.spells is in seconds. Apply fast_cast_pct from
                -- magic config to get actual cast time, then add a 1.5s animation-lock buffer.
                -- entry.cast_time overrides the computed value for a specific spell.
                do
                    local fc  = (current_config.magic and current_config.magic.fast_cast_pct) or 0
                    local bct = spell_data.cast_time or 3.0
                    local act = bct * math.max(0.1, (100 - fc) / 100)
                    coroutine.sleep(entry.cast_time or math.max(act + 1.5, 2.5))
                end

                -- v3.48: Post-cast buff verification for buff spells.
                -- Problem: the timer is set when /ma is SENT, but if a WS animation lock is
                -- active the game queues the spell and executes it 2-6s later. By the time
                -- the timer's min_time elapses the 0x076 packet hasn't arrived yet
                -- (has_buff=false), so the resolution loop re-selects the same member and
                -- queues a second cast — causing the double-buff spam seen on Mythrandiir.
                --
                -- Fix: sleep an extra 5s (covers WS anim lock + spell execution + 0x076
                -- round-trip), then check if the buff actually landed.
                --   • Buff confirmed  → leave the timer alone; normal rotation resumes.
                --   • Buff not found  → set timer for a 30s retry instead of full buff_duration.
                --     This also unblocks the rotation so other members get their turn.
                --   • Buff data nil   → trust or untracked slot; can't verify — leave timer.
                if entry.buff_id
                   and (entry.type == 'buff' or entry.type == 'buff_party' or entry.type == 'buff_party_mages')
                   and effective_target then
                    coroutine.sleep(5.0)
                    local vp     = windower.ffxi.get_player()
                    local vparty = windower.ffxi.get_party()
                    if vp and vparty then
                        local vbuffs = get_member_buffs(effective_target, vp, vparty)
                        if vbuffs ~= nil then
                            if table.contains(vbuffs, entry.buff_id) then
                                debug_msg('BUFF VERIFY: ' .. entry.name .. ' on ' ..
                                    effective_target .. ' confirmed')
                            else
                                -- Not found — interrupted, resisted, or still in queue.
                                -- Set timer so a retry fires in 30s.
                                local retry_in  = 30
                                local bd        = entry.buff_duration or 300
                                magic_last_used[magic_key] = os.time() - math.max(bd - retry_in, 0)
                                debug_msg('BUFF VERIFY: ' .. entry.name .. ' on ' ..
                                    effective_target .. ' NOT confirmed — retry in ' .. retry_in .. 's')
                            end
                        end
                    end
                end

                return true
            end
        end -- if spell_data
        end -- buff_only guard (else branch)
    end
    return false
end





function use_weakness_magic()
    if not current_config.weakness_spells then return false end
    if current_config.weakness_spells.enabled == false then
        -- debug_msg('WEAKNESS: Disabled in config.')
        return false
    end
    if nuke_hold_active and nuke_hold_active() then return false end   -- v5.00: save it for the burst

    local player = windower.ffxi.get_player()
    if not player or not player.vitals then return false end

    local target = windower.ffxi.get_mob_by_target('t')
    if not target or not target.name then return false end

    -- Find weakness element for this mob
    local element = nil
    for pattern, weak in pairs(mob_weaknesses) do
        if target.name:find(pattern, 1, true) then
            element = weak
            break
        end
    end
    if not element then
        -- debug_msg('WEAKNESS: No weakness found for: ' .. (target.name or '?'))
        return false
    end

    -- Get spell list for this element
    local spell_list = current_config.weakness_spells[element]
    if not spell_list or #spell_list == 0 then
        debug_msg('WEAKNESS: No spells configured for element: ' .. element)
        return false
    end

    -- Check distance
    local dist = target.distance and target.distance:sqrt() or 999
    if dist > 21 then
        debug_msg('WEAKNESS: Target out of range (' .. string.format("%.1f", dist) .. 'y)')
        return false
    end

    -- Global lockout between weakness spell casts  -- ADD THIS BLOCK
    if (os.time() - last_weakness_cast_time) < WEAKNESS_GLOBAL_LOCKOUT then
        return false
    end

    -- Initialize index for this element if needed
    weakness_spell_index[element] = weakness_spell_index[element] or 1

    -- Try each spell in the list starting from current index
    local spell_recasts = windower.ffxi.get_spell_recasts()
    if not spell_recasts then return false end

	local attempts = 0
    local num_spells = #spell_list
    local all_min_time = true  -- ADD THIS

-- Try each spell in the list from the TOP every call, cast first ready one
    for _, spell_entry in ipairs(spell_list) do
        if not spell_entry or not spell_entry.name then break end

        local spell_name = spell_entry.name
        local spell_min_time = spell_entry.min_time or 10
        local spell_uses_per_mob = spell_entry.uses_per_mob or 999

        local spell_data = res_with('spells', 'english', spell_name)
        local can_cast = true
        local skip_reason = ''

        -- Check spell data exists
        if not spell_data or not spell_data.id then
            can_cast = false
            skip_reason = 'not found in resources'
        end

        -- Check recast
        if can_cast and spell_data and (spell_recasts[spell_data.id] or -1) ~= 0 then
            can_cast = false
            skip_reason = 'on cooldown'
        end

        -- Check MP
        if can_cast and spell_data and (((player.vitals and player.vitals.mp) or 0) < spell_data.mp_cost) then
            can_cast = false
            skip_reason = 'not enough MP'
        end

        -- Check min time since last cast
        local time_since_last = os.time() - (magic_last_used[spell_name] or 0)
        if can_cast and time_since_last < spell_min_time then
            can_cast = false
            skip_reason = 'min_time (' .. time_since_last .. '/' .. spell_min_time .. 's)'
        end

        -- Check uses per mob
        local spell_uses = magic_use_tracker[spell_name] or 0
        if can_cast and spell_uses >= spell_uses_per_mob then
            can_cast = false
            skip_reason = 'uses_per_mob reached'
        end

        -- Check ninja tools
        if can_cast and not check_ninja_tools(spell_name) then
            can_cast = false
            skip_reason = 'no ninja tools'
        end

        -- Check global lockout
        if can_cast and (os.time() - last_weakness_cast_time) < WEAKNESS_GLOBAL_LOCKOUT then
            can_cast = false
            skip_reason = 'global lockout'
        end

        if can_cast then
            local t_wm = windower.ffxi.get_mob_by_target('t')
            if not t_wm or not t_wm.hpp or t_wm.hpp <= 0 then return false end
            debug_msg('WEAKNESS: Casting ' .. spell_name .. ' on ' .. (t_wm.name or '?') .. ' [' .. element .. ']')
            face('f')
            coroutine.sleep(0.1)  -- let face resolve before spell fires (prevents invalid arg)
            local wm_cmd = 'input /ma "' .. tostring(spell_name) .. '" <t>'
            cmd(wm_cmd)
            magic_last_used[spell_name] = os.time()
            last_weakness_cast_time = os.time()
            magic_use_tracker[spell_name] = spell_uses + 1
            do
                local fc  = (current_config.magic and current_config.magic.fast_cast_pct) or 0
                local bct = spell_data and spell_data.cast_time or 3.0
                local act = bct * math.max(0.1, (100 - fc) / 100)
                coroutine.sleep(spell_entry.cast_time or math.max(act + 1.5, 2.5))
            end
            return true
        else
            -- debug_msg('WEAKNESS: Skipping ' .. spell_name .. ' -> ' .. skip_reason)
        end
    end

    return false
end



-- v4.00: case-insensitive item lookup for ring_config names (cached).
ring_name_warned = ring_name_warned or {}
local _ring_ci_cache = {}
function ring_name_ci_lookup(name)
    local key = tostring(name):lower()
    local hit = _ring_ci_cache[key]
    if hit ~= nil then return hit or nil end
    local found = nil
    for _, it in pairs(aa_items_full('ring ' .. tostring(name))) do   -- v4.61
        if type(it) == 'table' and it.en and it.en:lower() == key then found = it break end
    end
    _ring_ci_cache[key] = found or false
    if found and not ring_name_warned[name] then
        ring_name_warned[name] = true
        info_msg('RINGS: "' .. tostring(name) .. '" matched "' .. found.en .. '" (fix the capitalization in ring_config)')
    end
    return found
end

-- v4.05: the 2h lock in settings.xml stays the cooldown tracker (the ring's
-- extdata reuse timer isn't reliable). It is cleared when the ring's charges
-- show it was replaced: more charges than we left it with, or full charges.
-- Max charges for rings we know; others are learned (most charges ever seen).
RING_MAX_CHARGES = {
    ['Emperor Band'] = 3,
}
ring_cmd_error = false          -- v4.07: set by 'incoming text' on "A command error occurred" after our /item
ring_item_pending_until = 0     -- v4.07: os.clock() deadline for that watch
RING_RETRY_SECS = 120          -- wait after a use that didn't go off
RING_MAX_FAILS  = 3            -- misses in a row before a 2h lock
ring_fail_count = ring_fail_count or {}
-- v4.08: a used ring is no longer locked 2h. The EXP/CP/Emporox buff check in
-- use_rings() keeps it from firing while its buff is up; once the buff is gone
-- the ring is tried, and if the game refuses the /item (reuse timer) it is
-- locked for RING_REFUSE_BACKOFF[n] seconds, doubling up to 2h on each refusal
-- in a row. Emperor Band's reuse is far shorter than 2h, so the old fixed lock
-- left it idle long after its in-game timer was up.
RING_REFUSE_BACKOFF = {600, 1200, 2400, 4800, 7200}
-- v4.09: known reuse times (seconds). A known ring waits exactly this long after
-- a use, and a refused /item retries after RING_KNOWN_RETRY (its timer has less
-- than the full reuse left) instead of the long backoff above.
RING_REUSE_SECS = {
    ['Emperor Band'] = 900,   -- 15 min
}
RING_KNOWN_RETRY = 120
ring_refuse_level = ring_refuse_level or {}
-- v4.66: rings not in RING_REUSE_SECS use the reuse time from res/items.lua
-- (recast_delay: Echad / Trizek / Endorsement Ring = 7200s). Before, those had
-- no known reuse, so a used ring got no lock and was swapped in and out every
-- few minutes for its whole 2h recast.
RING_SHORT_REUSE = 1800   -- v4.66: reuse at or under this keeps the 120s refusal retry
RING_EQUIP_GAP   = 2      -- v4.66: min seconds between two ring /equip commands
ring_last_equip_clock = ring_last_equip_clock or 0
function ring_reuse_secs(item_res, name)
    local s = RING_REUSE_SECS[item_res.en] or RING_REUSE_SECS[name]
    if s then return s end
    local rd = tonumber(item_res.recast_delay)
    if rd and rd > 0 then return rd end
    return nil
end
function ring_wait_after_refusal(ring_id, item_res, name)
    local reuse = ring_reuse_secs(item_res, name)
    if reuse and reuse <= RING_SHORT_REUSE then return RING_KNOWN_RETRY end
    local lvl = math.min((ring_refuse_level[ring_id] or 0) + 1, #RING_REFUSE_BACKOFF)
    ring_refuse_level[ring_id] = lvl
    local wait = RING_REFUSE_BACKOFF[lvl]
    if reuse and reuse < wait then wait = reuse end   -- v4.66: never longer than the ring's reuse
    return wait
end
-- v4.66: ring /equip with a gap. The default-ring restore and the next ring's
-- /equip went out 3ms apart (2026-11-18 00:57:34 pol.exe crash, Mythrandiir,
-- right after 'equip ring1 Karieyh ring +1' + 'equip ring1 Echad Ring').
function ring_equip(name, no_wait)
    local wait = RING_EQUIP_GAP - (os.clock() - ring_last_equip_clock)
    if wait > 0 and not no_wait then
        debug_msg(string.format('RINGS: %.1fs gap before /equip "%s".', wait, tostring(name)))
        aa_loop_beat = os.clock()
        coroutine.sleep(wait)
    end
    cmd('input /equip ring1 "' .. tostring(name) .. '"')
    ring_last_equip_clock = os.clock()
end
ring_retry_at = ring_retry_at or {}
ring_warned   = ring_warned or {}   -- [ring_id] = last note key, so each state logs once

function ring_note(ring_id, key, text)
    if ring_warned[ring_id] == key then return end
    ring_warned[ring_id] = key
    debug_msg(text)
end

-- Decode the first copy of item_id found in inventory/wardrobes (nil if none).
function ring_read(item_id)
    local all_items = aa_get_bags(AA_RING_BAGS)   -- v4.61: was every bag
    if not all_items then return nil end
    for _, bag_id in ipairs({'inventory','wardrobe','wardrobe2','wardrobe3','wardrobe4',
                             'wardrobe5','wardrobe6','wardrobe7','wardrobe8'}) do
        local bag = all_items[bag_id]
        if type(bag) == 'table' then
            for i = 1, #bag do
                local slot = bag[i]
                if type(slot) == 'table' and slot.id == item_id then
                    local ok, info = pcall(extdata.decode, slot)
                    return ok and info or nil
                end
            end
        end
    end
    return nil
end

function check_and_use_ring(name, use_lock)
    -- DEBUG: Confirm we are actually looking at a specific ring name
    if not name then 
        info_msg("Error: check_and_use_ring called with NIL name")
        return false 
    end
    -- debug_msg("Searching for: " .. tostring(name))

    local item_res = res_with('items', 'english', name)
    if not item_res then
        -- v4.00: names in ring_config are matched exactly against res/items.lua
        -- ('Emperor band' never matched 'Emperor Band'). Fall back to a
        -- case-insensitive lookup once, cache it, and warn so the config can be fixed.
        item_res = ring_name_ci_lookup(name)
        if not item_res then
            if not ring_name_warned[name] then
                ring_name_warned[name] = true
                info_msg('RINGS: no item named "' .. tostring(name) .. '" in resources -- check spelling in ring_config')
            end
            return false
        end
    end
    
    local ring_id = tostring(item_res.id)
    -- debug_msg("Ring ID found: " .. ring_id)
	

    -- 1. LOCK CHECK -- v4.04+: done after the item decode (section 3), so a
    --    traded-in ring with fresh charges can clear the old 2h lock first.

    -- 2. SEARCH ALL BAGS
	-- Replace your current bags list with this one:
	-- local bags = {0, 8, 10, 11, 12, 13, 14, 15, 16, 
              -- 'inventory', 'wardrobe', 'wardrobe2', 'wardrobe3', 
              -- 'wardrobe4', 'wardrobe5', 'wardrobe6', 'wardrobe7', 'wardrobe8'}
	local bags = {
		'inventory',
		'wardrobe', 'wardrobe2', 'wardrobe3', 'wardrobe4',
		'wardrobe5', 'wardrobe6', 'wardrobe7', 'wardrobe8',
	}			  
    local target_item_data = nil
    local all_items = aa_get_bags(bags)   -- v4.61: only these bags (was every bag)
	-- debug_msg('TRACE: check_and_use_ring get_items')  -- ADD THIS LINE
	if not all_items then return false end  -- add this line

    -- for _, bag_id in ipairs(bags) do
        -- local bag = all_items[bag_id]
        -- if bag then
            -- for i = 1, #bag do
                -- local slot = bag[i]
                -- if type(slot) == 'table' and slot.id == item_res.id then
                    -- target_item_data = slot
                    -- break
                -- end
            -- end
        -- end
        -- if target_item_data then break end
    -- end

	for _, bag_id in ipairs(bags) do
		local bag = all_items[bag_id]
		if bag and type(bag) == 'table' then   -- added type check as extra safety
			for i = 1, #bag do
				local slot = bag[i]
				if type(slot) == 'table' and slot.id == item_res.id then
					target_item_data = slot
					break
				end
			end
		end
		if target_item_data then break end
	end

    if not target_item_data then 
        -- debug_msg("Not Found: " .. name .. " is not in inventory/wardrobes.")
        return false 
    end

    -- 3. DECODE & EXECUTE
    local ok, info = pcall(extdata.decode, target_item_data)
	if not ok or type(info) ~= 'table' then
		debug_msg('RINGS: extdata.decode failed for: ' .. tostring(name))
		return false
	end

    local now     = os.time()
    local charges = tonumber(info.charges_remaining) or 0
    settings.ring_charges = settings.ring_charges or {}
    settings.ring_max     = settings.ring_max or {}
    local last_left = tonumber(settings.ring_charges[ring_id])
    local learned   = tonumber(settings.ring_max[ring_id]) or 0
    local max_chg   = RING_MAX_CHARGES[item_res.en] or RING_MAX_CHARGES[name]
    if charges > learned then
        settings.ring_max[ring_id] = charges
        config.save(settings)
        learned = charges
    end
    max_chg = max_chg or learned

    if charges <= 0 then
        ring_note(ring_id, 'empty', 'RINGS: ' .. name .. ' has 0 charges -- skipped.')
        return false
    end

    -- v4.05: recharge detection. A lock is only stale if the ring now has more
    -- charges than we left it with, or is full (never used since trade-in).
    local lock_until = tonumber(ring_locks[ring_id]) or 0
    -- v4.10: a saved lock longer than the ring's known reuse time is left over
    -- from the old fixed 2h lock -- clamp it so the ring isn't held back.
    local _reuse = ring_reuse_secs(item_res, name)
    if _reuse and lock_until - now > _reuse then
        debug_msg(string.format('RINGS: %s had a %dm wait saved but its reuse is %dm -- clearing it.',
            name, math.floor((lock_until - now) / 60), math.floor(_reuse / 60)))
        lock_until = 0
        ring_locks[ring_id] = 0
        settings.locks = ring_locks
        config.save(settings)
        ring_warned[ring_id] = nil
    end
    if lock_until > now then
        local why = nil
        if last_left and charges > last_left then
            why = 'charges went up (' .. last_left .. ' -> ' .. charges .. ')'
        elseif RING_MAX_CHARGES[item_res.en] and charges >= max_chg then
            why = 'full charges (' .. charges .. '/' .. max_chg .. ')'
        end
        if why then
            debug_msg('RINGS: ' .. name .. ' recharged -- ' .. why .. '. Clearing lock (' ..
                math.floor((lock_until - now) / 60) .. 'm left on it).')
            ring_locks[ring_id] = 0          -- 0, not nil: overrides a lock in the <global> section
            settings.locks = ring_locks
            settings.ring_charges[ring_id] = charges
            config.save(settings)
            ring_warned[ring_id] = nil
        elseif use_lock then
            local left = lock_until - now
            ring_note(ring_id, 'lock', string.format('RINGS: %s waiting: %dh %02dm until next try (%d/%s charges).',
                name, math.floor(left / 3600), math.floor((left % 3600) / 60), charges, tostring(max_chg)))
            return false
        end
    end

    -- v4.04: short guard after an attempt that didn't take
    if ring_retry_at[ring_id] and ring_retry_at[ring_id] > now then return false end

    local function exp_cp_buffs()
        local pl = windower.ffxi.get_player()
        local b = {}
        for _, id in ipairs((pl and pl.buffs) or {}) do
            if id == 249 or id == 579 or id == 618 then b[id] = true end
        end
        return b
    end
    local buffs_before = exp_cp_buffs()

    ring_attempted = true   -- v4.70: use_rings tries one ring per pass
    debug_msg('RINGS: using ' .. name .. ' (' .. charges .. '/' .. tostring(max_chg) .. ' charges).')
    ring_equip(name)   -- v4.66: waits RING_EQUIP_GAP after the last ring /equip
    coroutine.sleep(11)
    -- v4.07: watch for the game refusing the /item ("...A command error occurred.")
    -- v4.11: never /item within RING_KILL_HOLD s of a kill / dead cursor
    -- (corpse despawn window -- 2026-10-11 01:03:15 crash).
    local _hold = RING_KILL_HOLD - (os.clock() - last_kill_clock)
    if _hold > 0 then
        debug_msg(string.format('RINGS: holding /item "%s" %.1fs (corpse despawn window).', name, _hold))
        -- v4.43: capped. Any nearby defeat restarts the hold, so in a busy camp
        -- this waited forever with no watchdog heartbeat -> watchdog restart ->
        -- two loops. Now: give up after RING_HOLD_MAX s (or if this loop was
        -- replaced / stopped), put the default ring back, retry in RING_HOLD_RETRY s.
        local _h0 = os.clock()
        while (os.clock() - last_kill_clock) < RING_KILL_HOLD do
            if (os.clock() - _h0) >= RING_HOLD_MAX or aa_stale_loop() or not auto_attack then
                local _dr = current_config and current_config.ring_config and current_config.ring_config.default_ring
                info_msg(string.format('RINGS: /item "%s" held %.0fs (kills keep coming) -- skipped, retry in %ds.',
                    name, os.clock() - _h0, RING_HOLD_RETRY))
                if _dr and _dr ~= '' and _dr ~= tostring(name) then
                    ring_equip(_dr, true)   -- v4.66: restore now, stamp the gap
                end
                ring_retry_at[ring_id] = os.time() + RING_HOLD_RETRY
                return false
            end
            aa_loop_beat = os.clock()   -- still alive: don't trip the watchdog
            coroutine.sleep(0.5)
        end
    end
    ring_cmd_error = false
    ring_item_pending_until = os.clock() + 3
    cmd('input /item "' .. tostring(name) .. '" <me>')
    local _waited = 0
    while _waited < 7 and not ring_cmd_error do
        coroutine.sleep(0.5)
        _waited = _waited + 0.5
    end
    ring_item_pending_until = 0
    -- Restore default ring immediately after the exp/cp/emporox ring is used.
    -- This is the only moment ring1 is knowingly not the default ring (v2.47).
    local default_ring = current_config.ring_config and current_config.ring_config.default_ring
    if default_ring and default_ring ~= '' and default_ring ~= tostring(name) then
        ring_equip(default_ring, true)   -- v4.66: restore now, stamp the gap
    end

    -- v4.07: the client itself refused the /item (no packet was sent), so the
    -- ring can't be used right now (reuse timer, level, etc.). Lock it at once
    -- instead of retrying every 120s -- the old retry/fail counters were lost on
    -- every //lua r, so a refused ring got swapped in and out all night.
    if ring_cmd_error then
        ring_cmd_error = false
        ring_fail_count[ring_id] = nil
        local wait = ring_wait_after_refusal(ring_id, item_res, name)
        if use_lock then
            ring_locks[ring_id] = os.time() + wait
            settings.locks = ring_locks
            settings.ring_charges[ring_id] = charges
            config.save(settings)
        else
            ring_retry_at[ring_id] = os.time() + wait
        end
        ring_warned[ring_id] = nil
        debug_msg('RINGS: game refused /item "' .. name .. '" (command error) -- reuse timer not up. Retry in ' ..
            (wait >= 60 and (math.floor(wait / 60) .. 'm') or (wait .. 's')) .. '.')
        return false
    end

    -- v4.05: confirm the use: a charge was spent, or a new EXP/CP/Emporox buff appeared.
    local after   = ring_read(item_res.id)
    local a_chg   = after and tonumber(after.charges_remaining)
    local new_buff = false
    for id in pairs(exp_cp_buffs()) do
        if not buffs_before[id] then new_buff = true end
    end
    if (a_chg and a_chg < charges) or new_buff then
        ring_retry_at[ring_id] = nil
        ring_fail_count[ring_id] = nil
        ring_warned[ring_id] = nil
        ring_refuse_level[ring_id] = nil
        -- v4.66: buff-only confirmation (charge count unchanged, e.g. 1/1 rings
        -- like Echad) keeps the real count -- saving charges-1 made the next
        -- read look like 'charges went up' and cleared the reuse lock.
        local left_now = (a_chg and a_chg < charges) and a_chg or charges
        settings.ring_charges[ring_id] = left_now
        -- v4.08: no 2h lock after a use; the buff check holds it until the buff wears off.
        -- v4.09: a ring with a known reuse time waits exactly that long.
        local reuse = ring_reuse_secs(item_res, name)
        if use_lock and reuse then
            ring_locks[ring_id] = os.time() + reuse
            settings.locks = ring_locks
        elseif use_lock and (tonumber(ring_locks[ring_id]) or 0) > 0 then
            ring_locks[ring_id] = 0
            settings.locks = ring_locks
        end
        config.save(settings)
        info_msg('RINGS: ' .. name .. ' used. ' .. left_now .. ' charges left' ..
            (reuse and string.format(', next use in %dm.', math.floor(reuse / 60)) or '.'))
        return true
    end

    -- Didn't go off. Retry in RING_RETRY_SECS; after RING_MAX_FAILS misses in a
    -- row, assume it's on cooldown and lock it 2h like before.
    ring_fail_count[ring_id] = (ring_fail_count[ring_id] or 0) + 1
    if use_lock and ring_fail_count[ring_id] >= RING_MAX_FAILS then
        ring_fail_count[ring_id] = nil
        local wait = ring_wait_after_refusal(ring_id, item_res, name)
        ring_locks[ring_id] = os.time() + wait
        settings.locks = ring_locks
        settings.ring_charges[ring_id] = charges
        config.save(settings)
        info_msg('RINGS: ' .. name .. ' failed ' .. RING_MAX_FAILS .. 'x (no charge used, no buff) -- assuming cooldown, retry in ' ..
            math.floor(wait / 60) .. 'm.')
        return false
    end
    ring_retry_at[ring_id] = os.time() + RING_RETRY_SECS
    debug_msg('RINGS: ' .. name .. ' did not go off (no charge used, no buff) -- retry in ' .. RING_RETRY_SECS .. 's.')
    return false
end



-- =========================================================================
-- v4.70: RING PASSES (2026-11-18, Mythrandiir: Trizek -> Endorsement -> Echad
-- tried back to back, ~18s each, none went off -- the combat loop was held
-- ~54s and ring1 was off the default ring 11% of the night)
-- * one ring /item per pass; a try that doesn't go off blocks every ring
--   for RING_PASS_GAP s
-- * CP rings are skipped while no capacity points come in (exemplar points
--   seen, none of the other in RING_POINTS_WINDOW s) or job points are capped
-- =========================================================================
RING_PASS_GAP      = 60
RING_POINTS_WINDOW = 1800
ring_next_pass     = 0
ring_attempted     = false
RING_EP_SEEN       = nil
RING_CP_SEEN       = nil
function ring_cp_useless(player)
    local now = os.clock()
    if RING_EP_SEEN and (now - RING_EP_SEEN) < RING_POINTS_WINDOW
       and not (RING_CP_SEEN and (now - RING_CP_SEEN) < RING_POINTS_WINDOW) then
        return 'earning EP, no CP seen for 30 min'
    end
    local jp = player.job_points and player.main_job and player.job_points[player.main_job:lower()]
    if type(jp) == 'table' and (tonumber(jp.jp_spent) or 0) >= 2100 and (tonumber(jp.jp) or 0) >= 500 then
        return 'job points capped (2100 spent, 500 banked)'
    end
    return nil
end

function use_rings()
    if not current_config.ring_config then return end
    if current_config.ring_config.enabled == false then return end
    -- Don't equip rings within 3s of a WS or 2s of a job ability - animation lock causes 'Invalid argument'
    if (os.clock() - last_ws_time) < 3 then return end
    if (os.clock() - last_ability_time) < 2 then return end
    if os.clock() < ring_next_pass then return end   -- v4.70

	local player = windower.ffxi.get_player()
    if not player or not player.buffs then
        return  -- player data transiently unavailable; skip quietly
    end
    local buffs = player.buffs
    -- 249: Dedicated/Exp, 579: Commitment/CP, 618: Emporox
    local has_exp_buff = table.contains(buffs, 249)
    local has_cp_buff = table.contains(buffs, 579)
    local has_emporox_buff = table.contains(buffs, 618)
	local ring_cfg = current_config.ring_config

    -- v4.70: true when a ring was used or tried (one /item per pass)
    local function try(name, lock)
        ring_attempted = false
        local ok = check_and_use_ring(name, lock)
        if not ok and ring_attempted then ring_next_pass = os.clock() + RING_PASS_GAP end
        return ok or ring_attempted
    end

    -- 1. Emporox Check
    if ring_cfg.emporox_ring and not has_emporox_buff then
        if try(ring_cfg.emporox_ring, false) then return end
    end

    -- 2. CP Check (v4.06: CP only builds at level 99; v4.70: not while no CP comes in)
    local main_lvl = tonumber(player.main_job_level) or 0
    if not has_cp_buff and not has_exp_buff and main_lvl >= 99
       and type(ring_cfg.cp_rings) == 'table' and #ring_cfg.cp_rings > 0 then
        local why = ring_cp_useless(player)
        if why then
            ring_note('cp', 'cp|' .. why, 'RINGS: CP rings skipped -- ' .. why .. '.')
        else
            for _, ring_name in ipairs(ring_cfg.cp_rings) do
                if try(ring_name, true) then return end
            end
        end
    end

    -- 3. EXP Check
    if not has_cp_buff and not has_exp_buff and type(ring_cfg.exp_rings) == 'table' then
        for _, ring_name in ipairs(ring_cfg.exp_rings) do
            if try(ring_name, true) then return end
        end
    end
	-- Default ring fallback removed (v2.47): check_and_use_ring puts the default
	-- ring back right after the /item; GearSwap handles every other ring1 change.
end









-- =========================================================================
-- v4.32: DREAD SPIKES MODE  (aa_config.lua -> dread_spikes, and each job's
-- job_config -> dread_spikes block)
-- The game never sends a monster's buffs to the client, so Dread Spikes
-- (status 173) is tracked per mob ID from what we can see:
--   gains it   "<mob> gains the effect of Dread Spikes" (spell or TP move)
--   still up   anyone's melee hit on it shows "spikes drain N HP" (msg 132)
--   gone       a wear-off / dispel message (action or 0x029), the mob dies,
--              clear_hits landed melee hits in a row with no drain, or
--              max_duration seconds since it was last seen (cast or drain)
--   forgotten  no news about that mob for forget_after seconds (60 min)
-- While the mob you are fighting has it: the job's dread_spikes gear goes on
-- (GearSwap is locked on those slots), no weapon skills, and the order is
-- Dispel > nukes > /ra -- with melee rounds left in between nukes / shots so
-- the drain messages keep the record current.
-- Globals on purpose (main chunk / main loop are at the local/upvalue limit).
-- =========================================================================
DS_BUFF_ID   = 173
DS_DRAIN_MSG = 132   -- "<target>'s spikes drain N HP from <actor>."
DS_GAIN_MSGS = {[166] = true, [186] = true, [194] = true, [205] = true, [230] = true,
                [266] = true, [280] = true, [319] = true}
DS_LOSE_MSGS = {[64] = true, [159] = true, [168] = true, [204] = true, [206] = true,
                [321] = true, [322] = true, [341] = true, [342] = true, [343] = true,
                [344] = true, [350] = true, [378] = true, [531] = true, [647] = true,
                [805] = true, [806] = true}
DS_HIT_MSGS  = {[1] = true, [67] = true}   -- melee hit / critical hit landed
DS_AUTO_DISPEL = {'Dispel', 'Magic Finale', 'Dark Shot'}
-- config slot name -> get_items().equipment key
DS_SLOT_KEY = {main = 'main', sub = 'sub', range = 'range', ammo = 'ammo', head = 'head',
               neck = 'neck', ear1 = 'left_ear', ear2 = 'right_ear', left_ear = 'left_ear',
               right_ear = 'right_ear', body = 'body', hands = 'hands', ring1 = 'left_ring',
               ring2 = 'right_ring', left_ring = 'left_ring', right_ring = 'right_ring',
               back = 'back', waist = 'waist', legs = 'legs', feet = 'feet',
               -- v4.36 aliases
               weapon = 'main', ranged = 'range', lear = 'left_ear', rear = 'right_ear',
               lring = 'left_ring', rring = 'right_ring'}
-- v4.36: equip order (main before sub: a grip needs a two-handed main) and
-- the client slot IDs (res.slots) for taking an item off
DS_SLOT_ORDER = {'main', 'sub', 'range', 'ammo', 'head', 'neck', 'left_ear', 'right_ear',
                 'body', 'hands', 'left_ring', 'right_ring', 'back', 'waist', 'legs', 'feet'}
DS_SLOT_ID = {main = 0, sub = 1, range = 2, ammo = 3, head = 4, body = 5, hands = 6, legs = 7,
              feet = 8, neck = 9, waist = 10, left_ear = 11, right_ear = 12, left_ring = 13,
              right_ring = 14, back = 15}
-- equipment key -> /equip and //gs disable slot name
DS_EQUIP_NAME = {left_ear = 'ear1', right_ear = 'ear2', left_ring = 'ring1', right_ring = 'ring2'}

DS_CFG = (type(AA_CFG.dread_spikes) == 'table') and AA_CFG.dread_spikes or {enabled = false}
ds_mobs  = {}   -- [mob_id] = {up, seen, last_any, clean, name, how}
ds_state = {on = false, mob = 0, want = {}, worn = {}, slots = {}, gear_next = 0,
            gear_tries = 0, rounds = 0, last_round = 0, last_act = 0, next_try = {}, warned = {}}

function ds_enabled() return DS_CFG.enabled == true end
function ds_num(k, d) return tonumber(DS_CFG[k]) or d end

-- this job's job_config dread_spikes block (or an empty one)
function ds_job()
    local j = current_config and current_config.dread_spikes
    return (type(j) == 'table') and j or {}
end

function ds_is_mob(id)
    local m = id and windower.ffxi.get_mob_by_id(id)
    return m and m.spawn_type == 16, m
end

-- Is Dread Spikes believed to be up on this mob right now?
function ds_is_up(id)
    local r = id and ds_mobs[id]
    if not r or not r.up then return false end
    local maxd = ds_num('max_duration', 180)
    if (os.clock() - (r.seen or 0)) > maxd then
        r.up = false; r.clean = 0
        debug_msg('DREAD SPIKES: ' .. tostring(r.name) .. ' -- not seen for ' .. maxd .. 's, assuming it wore off.')
        return false
    end
    return true
end

function ds_mark(id, how)
    local r = ds_mobs[id]
    if not r then
        local is_mob, m = ds_is_mob(id)
        if not is_mob then return end   -- a player / Trust with Dread Spikes: not ours to track
        r = {name = m.name or tostring(id)}
        ds_mobs[id] = r
    end
    local now = os.clock()
    if not r.up then
        local t = windower.ffxi.get_mob_by_target('t')
        local line = 'DREAD SPIKES on ' .. tostring(r.name) .. ' (ID ' .. tostring(id) .. ') -- ' .. how .. '.'
        if t and t.id == id then info_msg(line) else debug_msg(line) end
    end
    r.up = true; r.seen = now; r.last_any = now; r.clean = 0; r.how = how
end

function ds_clear(id, why)
    local r = ds_mobs[id]
    if not r then return end
    r.last_any = os.clock()
    if r.up then
        r.up = false; r.clean = 0
        local line = 'DREAD SPIKES gone from ' .. tostring(r.name) .. ' -- ' .. why .. '.'
        if ds_state.on and ds_state.mob == id then info_msg(line) else debug_msg(line) end
    end
end

-- From the 'action' event (0x028).
function ds_on_action(action)
    if not ds_enabled() or not action or type(action.targets) ~= 'table' then return end
    local now   = os.clock()
    local cat   = action.category
    local actor = action.actor_id
    if actor and ds_mobs[actor] then ds_mobs[actor].last_any = now end
    local me = (cat == 1) and windower.ffxi.get_player() or nil
    for _, t in ipairs(action.targets) do
        local tid = t and t.id
        if tid and type(t.actions) == 'table' then
            local r = ds_mobs[tid]
            if r then r.last_any = now end
            for _, a in ipairs(t.actions) do
                if a.param == DS_BUFF_ID and DS_GAIN_MSGS[a.message] then
                    ds_mark(tid, 'gained it')
                    r = ds_mobs[tid]
                elseif a.param == DS_BUFF_ID and DS_LOSE_MSGS[a.message] then
                    ds_clear(tid, 'removed (msg ' .. tostring(a.message) .. ')')
                elseif cat == 1 and actor ~= tid then
                    if a.has_spike_effect and a.spike_effect_message == DS_DRAIN_MSG then
                        ds_mark(tid, 'spikes drained HP')
                        r = ds_mobs[tid]
                    elseif r and r.up and DS_HIT_MSGS[a.message] then
                        -- a landed hit with no drain: count toward "it wore off"
                        r.clean = (r.clean or 0) + 1
                        if r.clean >= ds_num('clear_hits', 4) then
                            ds_clear(tid, r.clean .. ' melee hits landed with no HP drain')
                        end
                    end
                end
            end
            -- our own melee round on the Dread Spikes mob (spacing for nukes / /ra)
            if me and actor == me.id and ds_state.on and tid == ds_state.mob then
                ds_state.rounds = ds_state.rounds + 1
                ds_state.last_round = now
            end
        end
    end
end

-- From the 0x029 action-message packet (wear-off etc.; param 1 = status ID).
function ds_on_msg(target_id, msg, param)
    if not ds_enabled() then return end
    local r = ds_mobs[target_id]
    if not r then return end
    r.last_any = os.clock()
    if param == DS_BUFF_ID and DS_LOSE_MSGS[msg] then
        ds_clear(target_id, 'wore off (msg ' .. tostring(msg) .. ')')
    end
end

-- Drop mobs with no news for forget_after seconds (called from prune_blacklists).
function ds_prune()
    local now, keep = os.clock(), ds_num('forget_after', 3600)
    for id, r in pairs(ds_mobs) do
        if type(r) ~= 'table' or (now - (r.last_any or 0)) > keep then ds_mobs[id] = nil end
    end
end

-- English name of the item worn in an equipment slot ('left_ring', 'body' ...)
function ds_worn(key)
    local it = equipped_item_res(key)
    return it and it.en or nil
end

-- v4.36: is `item` ('Name' or 'empty') what is in that slot now?
function ds_slot_has(key, item)
    local w = ds_worn(key)
    if item == 'empty' then return w == nil end
    return w ~= nil and w:lower() == item:lower()
end

-- job gear table {main = 'Item', sub = 'empty'} -> {equipment_key = 'Item' | 'empty'}
-- v4.36: slot aliases (weapon = main, ranged = range, lear / rear / lring /
-- rring); 'empty' (any case) takes the slot's item off; '' / nil = leave it.
function ds_gear_list(tbl)
    local out = {}
    if type(tbl) ~= 'table' then return out end
    for slot, item in pairs(tbl) do
        local key = DS_SLOT_KEY[tostring(slot):lower()]
        if key and type(item) == 'string' and item ~= '' then
            out[key] = (item:lower() == 'empty') and 'empty' or item
        elseif not key and not ds_state.warned['slot:' .. tostring(slot)] then
            ds_state.warned['slot:' .. tostring(slot)] = true
            info_msg('dread_spikes gear: unknown slot "' .. tostring(slot) .. '" -- use main, sub, range, ammo, ' ..
                     'head, neck, ear1, ear2, body, hands, ring1, ring2, back, waist, legs, feet.')
        end
    end
    return out
end

-- v4.36: take the item out of one slot (outgoing 0x050 with item index 0,
-- the same packet GearSwap sends for 'empty').
function ds_unequip(key)
    local sid = DS_SLOT_ID[key]
    if sid == nil or aa_stale_loop() then return end  -- v4.43
    if (debug_level or 0) >= 2 then aa_log_file(aa_wall_clock() .. ' CMD [unequip ' .. key .. ']') end
    windower.packets.inject_outgoing(0x50, string.char(0x50, 4, 0, 0, 0, sid, 0, 0))
end

-- Put on each slot that isn't already right. v4.36: always in DS_SLOT_ORDER
-- (main before sub -- a grip only goes on with a two-handed main), and
-- 'empty' slots are cleared. `tail` runs after the /equip chain.
-- Returns how many slots needed a change.
function ds_send_equip(want, tail)
    local parts, n = {}, 0
    for _, key in ipairs(DS_SLOT_ORDER) do
        local item = want[key]
        if item and not ds_slot_has(key, item) then
            n = n + 1
            if item == 'empty' then
                ds_unequip(key)
            else
                parts[#parts + 1] = 'input /equip ' .. (DS_EQUIP_NAME[key] or key) .. ' "' .. item .. '"'
            end
        end
    end
    if tail then parts[#parts + 1] = tail end
    if #parts > 0 then cmd(table.concat(parts, '; wait 0.4; ')) end
    return n
end

function ds_enter(t)
    local want = ds_gear_list(ds_job().gear)
    -- v4.36: what to put back. Snapshot every swapped slot ('empty' when it
    -- was empty), plus sub when main is swapped (the grip / off-hand the game
    -- takes off) and ammo when range is swapped.
    local snap = {}
    for key in pairs(want) do snap[key] = true end
    if want.main then snap.sub = true end
    if want.range then snap.ammo = true end
    local worn, slots = {}, {}
    for _, key in ipairs(DS_SLOT_ORDER) do
        if snap[key] then worn[key] = ds_worn(key) or 'empty' end
        if want[key] then slots[#slots + 1] = DS_EQUIP_NAME[key] or key end
    end
    local now = os.clock()
    ds_state.restore = nil   -- a restore still in progress is replaced by this fight
    ds_state.on, ds_state.mob = true, t.id
    ds_state.want, ds_state.worn, ds_state.slots = want, worn, slots
    ds_state.rounds, ds_state.last_round, ds_state.last_act = 0, now, 0
    ds_state.gear_tries, ds_state.gear_next = 0, now + 3
    ws_sc_locked = false
    info_msg('DREAD SPIKES MODE ON -- ' .. tostring(t.name) .. ': no weapon skills' ..
             ((#slots > 0) and (', gear on: ' .. table.concat(slots, ' ')) or '') .. '.')
    if #slots > 0 then
        if DS_CFG.lock_gearswap ~= false then cmd('gs disable ' .. table.concat(slots, ' ')) end
        ds_send_equip(want)
    end
end

-- Re-equip any dread_spikes gear that didn't go on (casting / animation lock).
function ds_gear_check()
    local now = os.clock()
    if now < ds_state.gear_next or ds_state.gear_tries >= 5 then return end
    ds_state.gear_next = now + 3
    if ds_send_equip(ds_state.want) > 0 then
        ds_state.gear_tries = ds_state.gear_tries + 1
        if ds_state.gear_tries >= 5 then
            info_msg('dread_spikes gear: still not all on after 5 tries -- check the item names and that ' ..
                     'they are in your inventory or a wardrobe.')
        end
    end
end

function ds_leave(why)
    if not ds_state.on then return end
    -- v4.36: after_gear slots go on over the snapshot; a slot after_gear
    -- doesn't name goes back to what was worn before.
    local back = {}
    for k, v in pairs(ds_state.worn or {}) do back[k] = v end
    for k, v in pairs(ds_gear_list(ds_job().after_gear)) do back[k] = v end
    local tail = nil
    if #ds_state.slots > 0 and DS_CFG.lock_gearswap ~= false then
        tail = 'gs enable ' .. table.concat(ds_state.slots, ' ')
    end
    ds_send_equip(back, tail)
    info_msg('DREAD SPIKES MODE OFF -- ' .. tostring(why) .. '.')
    ds_state.on, ds_state.mob = false, 0
    ds_state.want, ds_state.worn, ds_state.slots = {}, {}, {}
    -- v4.36: check it all went back on (a grip refused before the 2H weapon,
    -- animation lock ...) and retry -- see ds_restore_check()
    ds_state.restore = (next(back) ~= nil) and {want = back, tries = 0, next = os.clock() + 3} or nil
end

-- v4.36: main-loop hook. Re-sends after-Dread-Spikes gear that didn't go on,
-- every 3s, up to 5 times.
function ds_restore_check()
    local r = ds_state.restore
    if not r or ds_state.on then return end
    local now = os.clock()
    if now < r.next then return end
    r.next = now + 3
    if ds_send_equip(r.want) == 0 then ds_state.restore = nil; return end
    r.tries = r.tries + 1
    if r.tries >= 5 then
        ds_state.restore = nil
        info_msg('dread_spikes after_gear: still not all back on after 5 tries -- check the item names.')
    end
end

-- nil / 'auto' -> auto list; 'Name' -> {'Name'}; table -> itself
function ds_list(v, auto)
    if v == nil or v == 'auto' then return auto end
    if type(v) == 'string' then return {v} end
    if type(v) == 'table' then return v end
    return {}
end

function ds_auto_nukes()
    local out = {}
    local mg = current_config and current_config.magic
    if type(mg) == 'table' and mg.enabled ~= false then
        for _, e in ipairs(mg) do
            if e and e.name and e.type == 'damage' then out[#out + 1] = e.name end
        end
    end
    return out
end

function ds_spell_ready(name, player, recasts, dist)
    local sp = res_with('spells', 'english', name)
    if not sp or not spell_level_ok(sp, player) then return nil end
    if sp.recast_id and (recasts[sp.recast_id] or 0) > 0 then return nil end
    if (sp.mp_cost or 0) > ((player.vitals and player.vitals.mp) or 0) then return nil end
    if dist > ds_num('cast_range', 20) then return nil end
    return sp
end

function ds_cast(sp, why)
    debug_msg('DREAD SPIKES: ' .. why .. ' -- ' .. sp.en .. '.')
    cmd('input /ma "' .. sp.en .. '" <t>')
    local fc = (current_config.magic and current_config.magic.fast_cast_pct) or 0
    coroutine.sleep(math.max((sp.cast_time or 3) * math.max(0.1, (100 - fc) / 100) + 1.5, 2.5))
end

-- Leave room for melee rounds between nukes / shots: their spike-drain
-- messages are what keep the Dread Spikes record current. A character that
-- isn't swinging (out of reach, pure caster) waits melee_wait seconds at most.
function ds_spacing_ok()
    local need = ds_num('melee_rounds', 1)
    if need <= 0 or ds_state.rounds >= need then return true end
    return (os.clock() - math.max(ds_state.last_round, ds_state.last_act)) >= ds_num('melee_wait', 8)
end

function ds_acted(name)
    local now = os.clock()
    ds_state.rounds, ds_state.last_act = 0, now
    ds_state.next_try[name] = now + 5   -- no re-sending the same thing every tick
end

-- Main-loop hook (run_combat_chain, engaged). Puts Dread Spikes mode on / off
-- for the current target and takes its action. Returns true when it used the
-- tick (the rest of the combat chain waits for the next one).
function ds_tick()
    local p = windower.ffxi.get_player()
    local t = windower.ffxi.get_mob_by_target('t')
    local jc = ds_job()
    if not ds_enabled() or jc.enabled == false or not p or p.status ~= 1
       or not t or not t.id or not t.hpp or t.hpp <= 0 or not ds_is_up(t.id) then
        if ds_state.on then
            ds_leave((t and t.id == ds_state.mob and t.hpp and t.hpp > 0)
                     and 'Dread Spikes is down' or 'not fighting a Dread Spikes mob')
        end
        return false
    end
    if not ds_state.on then
        ds_enter(t)
    elseif ds_state.mob ~= t.id then
        ds_state.mob, ds_state.rounds, ds_state.last_round = t.id, 0, os.clock()
        info_msg('DREAD SPIKES MODE -- now on ' .. tostring(t.name) .. '.')
    end
    ws_sc_locked = false
    ds_gear_check()

    local now  = os.clock()
    local dist = t.distance and t.distance:sqrt() or 99
    local buffs = p.buffs or {}
    local silenced = table.contains(buffs, 6) or table.contains(buffs, 592)
    local recasts = windower.ffxi.get_spell_recasts() or {}

    -- 1. Dispel (spell or JA) -- first, every time it is ready
    local dl = ds_list(jc.dispel, DS_AUTO_DISPEL)
    if #dl > 0 then
        local ab = windower.ffxi.get_abilities()
        local avail = (ab and ab.job_abilities) or {}
        local jar = windower.ffxi.get_ability_recasts() or {}
        for _, name in ipairs(dl) do
            if (ds_state.next_try[name] or 0) <= now then
                local sp = (not silenced) and ds_spell_ready(name, p, recasts, dist)
                if sp then
                    info_msg('DREAD SPIKES: ' .. sp.en .. ' on ' .. tostring(t.name) .. '.')
                    ds_acted(name)
                    ds_cast(sp, 'dispel')
                    return true
                end
                local ja = res_with('job_abilities', 'name', name)
                if ja and table.contains(avail, ja.id) and dist <= ds_num('cast_range', 20)
                   and not (ja.recast_id and (jar[ja.recast_id] or 0) > 0) then
                    info_msg('DREAD SPIKES: ' .. ja.en .. ' on ' .. tostring(t.name) .. '.')
                    ds_acted(name)
                    cmd('input ' .. ja_prefix(ja) .. ' "' .. ja.en .. '" <t>')
                    coroutine.sleep(1.5)
                    return true
                end
            end
        end
    end

    if not ds_spacing_ok() then return false end

    -- 2. Nukes, strongest first
    if not silenced then
        for _, name in ipairs(ds_list(jc.nukes, ds_auto_nukes())) do
            if (ds_state.next_try[name] or 0) <= now then
                local sp = ds_spell_ready(name, p, recasts, dist)
                if sp then
                    ds_acted(name)
                    ds_cast(sp, 'nuke')
                    return true
                end
            end
        end
    end

    -- 3. Ranged attack (no spikes on /ra)
    if jc.ranged ~= false and (ds_state.next_try['/ra'] or 0) <= now
       and dist <= (RA_PULL_RANGE or 24.9) and ranged_attack_ready() then
        debug_msg('DREAD SPIKES: /ra on ' .. tostring(t.name) .. '.')
        ds_acted('/ra')
        ds_state.next_try['/ra'] = now + 2
        cmd('input /ra <t>')
        coroutine.sleep(3.0)
        return true
    end
    return false
end

-- //aa ds [clear]
function ds_command(sub)
    if sub == 'clear' then
        ds_leave('cleared by //aa ds clear')
        ds_mobs = {}
        windower.add_to_chat(8, '[AutoAttack] Dread Spikes tracking cleared.')
        return
    end
    local now, n = os.clock(), 0
    windower.add_to_chat(8, '[AutoAttack] Dread Spikes: ' .. (ds_enabled() and 'ON' or 'OFF (aa_config dread_spikes.enabled)') ..
        ' | mode ' .. (ds_state.on and ('ON (' .. tostring((ds_mobs[ds_state.mob] or {}).name) .. ')') or 'off'))
    for id, r in pairs(ds_mobs) do
        n = n + 1
        local up = ds_is_up(id)
        windower.add_to_chat(8, string.format('[AutoAttack]   %s (ID %d): %s%s, last news %ds ago',
            tostring(r.name), id, up and 'UP' or 'down',
            up and string.format(' (seen %ds ago, %s, clean hits %d)', math.floor(now - (r.seen or now)), tostring(r.how), r.clean or 0) or '',
            math.floor(now - (r.last_any or now))))
    end
    if n == 0 then windower.add_to_chat(8, '[AutoAttack]   no mobs tracked.') end
end

function main_logic_loop(my_gen)
    -- v4.43: register this coroutine (see aa_stale_loop)
    local _co = coroutine.running()
    if _co and my_gen then aa_loop_co[_co] = my_gen end
    -- v3.98: exit if a newer loop has been started (see aa_loop_gen)
    while auto_attack and (my_gen == nil or my_gen == aa_loop_gen) do
        if debug_level >= 2 then aa_tick_check() end  -- v4.25: TIMING slow-pass check
        aa_loop_beat = os.clock()  -- v3.98: watchdog heartbeat
        local player = windower.ffxi.get_player()

        if not player or not current_config then
            -- Player data temporarily unavailable (zoning, disconnect, loading screen).
            -- Retry up to 10 times at 3s intervals (~30s total) before giving up.
            local retry_count = 0
            while (not player or not current_config) and retry_count < 10
                  and auto_attack and (my_gen == nil or my_gen == aa_loop_gen) do
                coroutine.sleep(3)
                aa_loop_beat = os.clock()
                player = windower.ffxi.get_player()
                retry_count = retry_count + 1
            end
            -- v3.98: stopped or superseded while waiting -- leave quietly (don't
            -- clear auto_attack: that would stop the newer loop)
            if not auto_attack or (my_gen and my_gen ~= aa_loop_gen) then return end
            if not player or not current_config then
                info_msg('Auto-attack: player unavailable after retries. Stopping.')
                auto_attack = false
                return
            end
        end

        local cfg = current_config  -- declared here, after nil checks, in scope for rest of loop

        -- v3.83 Low-HP stop / v4.12 rework: see low_hp_check()
        aa_stage('emergency')  -- v4.25
        emergency_abilities(player)  -- v4.13: hpp_below abilities every tick, target or not
        if low_hp_check(player) then break end
        -- v4.32: out of the fight -> Dread Spikes gear / GearSwap lock off
        if ds_state.on and player.status ~= 1 then ds_leave('out of combat') end
        ds_restore_check()  -- v4.36: after-Dread-Spikes gear that didn't go back on
        step_home_check()   -- v4.37: back to the pre-STEP-IN spot once engaged
        anchor_check()      -- v4.75: leader back on the aa fight spot
        pcall(engage_lag_tick)   -- v4.97: how long the party takes to engage our mob
        pcall(pstat_tick)        -- v4.99: own engage timing, stats line, party report

        --Configure pull type and range
        local pull_command = '/ra <t>'
        local pull_dist = 24.9
        local pull_wait = 4.5
        local pull_next_on_low_hp = false
        local low_hp_prcnt = 20
        local pull_next_max = 2
        if autoattack_type == 'pull' and cfg.pull then
            -- v4.23: each master_pull_method field overrides the job's pull field on
            -- its own, whenever it has a value (not nil). type also needs to be
            -- non-empty ('' = use the job's method). false counts as a value, so
            -- PullNext_OnLowHP = false turns PullNext off for every job.
            local _mpm = master_pull_method or {}
            local _jp  = cfg.pull
            local eff_method = (_mpm.type ~= nil and _mpm.type ~= '') and _mpm.type or _jp.method
            local eff_pullnext = _jp.PullNext_OnLowHP
            if _mpm.PullNext_OnLowHP ~= nil then eff_pullnext = _mpm.PullNext_OnLowHP end
            local eff_lowhpprcnt = _jp.LowHPPrcnt
            if _mpm.LowHPPrcnt ~= nil then eff_lowhpprcnt = _mpm.LowHPPrcnt end
            local eff_pullnextmax = _jp.PullNextMax
            if _mpm.PullNextMax ~= nil then eff_pullnextmax = _mpm.PullNextMax end

            if eff_method == 'ranged_attack' then
				pull_command = '/ra <t>'
				pull_dist = 24.9
				pull_wait = 4.5
			elseif eff_method == 'provoke' then
				pull_command = '/ja provoke <t>'
				pull_dist = 17.8
				pull_wait = 2.0
			elseif eff_method == 'dia' then
				pull_command = '/ma dia <t>'
				pull_dist = 20.0  -- v3.35: was 21.8; log showed "out of range" at 21.9y. Dia cap ~20.7y; 20.0 gives safe buffer against mob drift.
				pull_wait = 2.0
			end
			pull_next_on_low_hp = eff_pullnext == true
			low_hp_prcnt = tonumber(eff_lowhpprcnt) or 20
			pull_next_max = tonumber(eff_pullnextmax) or 2
		end

        aa_pull_dist = pull_dist  -- v4.21: hot switch reach
        -- Logic: If not engaged (Status 0), try to find and pull a target
        if not player.status then
            -- Status nil means player data is degraded (zoning/loading); skip tick
            coroutine.sleep(1)
        elseif player.status == 0 then
            aa_stage('trusts')  -- v4.25
            call_trusts()
			-- no longer using callTankDistance
            aa_stage('pet')  -- v4.25
            pet_logic(false)  -- v3.94: re-summon / call back pet between fights

            -- Heal/buff outside battle: runs heal_party() and use_magic() in
            -- buff-only mode (debuff/damage entries are skipped — no enemy target).
            aa_stage('heal-outside')  -- v4.25
            if heal_buff_outside_battle then
                heal_party(true)  -- outside_battle=true: heals anyone below 100% HP
                use_magic(true)   -- buff_only=true: skips debuffs/damage entries
            end

			aa_stage('assist-engage')  -- v4.25
			-- If Autoattack started with ASSIST command
			if autoattack_type == 'assist' then
				-- v4.42: /target <bt> only for a live <bt>, never in the kill quiet window
				local _bt_ok, _bt_sent = assist_target_bt('idle')
				if _bt_sent then assist_wait_cursor() end  -- v4.50: was a flat coroutine.sleep(1)
				local bt = _bt_ok and windower.ffxi.get_mob_by_target('t') or nil
				if bt and bt.spawn_type == 16 and bt.hpp and bt.hpp > 0
				   and bt.claim_id ~= 0 then
					face('f')
					coroutine.sleep(0.3)
					if assist_engage_ok(bt.id) then cmd('input /attack on') end  -- v4.42
					-- v3.25: face every 1s for 5s after initial engage
					for _fi = 1, 5 do
						coroutine.sleep(1.0)
						local _ft = windower.ffxi.get_mob_by_target('t')
						if _ft and _ft.hpp and _ft.hpp > 0 then
							face('f')
						end
					end
				end
				
			elseif autoattack_type == 'pull' then
                aa_stage('pull-scan')  -- v4.25
                -- debug_msg("main_logic_loop: begin with PULL command..")
                
				-- 1. Scan for any mob targeting you or your Trusts
				local party = windower.ffxi.get_party()
				local mobs = windower.ffxi.get_mob_array()
				-- Transient API failure: skip this tick's pull logic but keep the loop alive
				if party and mobs then

	-- v2.98: Build pull_party_ids BEFORE the aggro scan so every scan path
				-- can filter purple mobs (claimed by other parties) correctly.
				local my_id = player and player.id or 0
				local pull_party_ids = {}
				do
					local pull_pdata = windower.ffxi.get_party()
					if pull_pdata then
						for key, member in pairs(pull_pdata) do
							if type(member) == 'table' and key:match('^p[0-5]$') then
								local eid = member.mob and member.mob.id
								if not eid and member.mob_index and member.mob_index > 0 then
									local pm = windower.ffxi.get_mob_by_index(member.mob_index)
									eid = pm and pm.id
								end
								if eid then pull_party_ids[eid] = true end
							end
						end
					end
					if my_id > 0 then pull_party_ids[my_id] = true end
				end

				local aggro_target = nil
				-- v2.76: player.index is reliable for p0; party.p0.mob_index is nil in get_party()
				-- for the local player, so mobs targeting Shadowhammer were invisible to the aggro scan.
				local me_index = player and player.index or nil

				-- v3.99: Priority scan. Candidates are mobs targeting you or a party member
				-- (Trusts), mobs already claimed by your party, and any mob already inside
				-- your melee range. The CLOSEST candidate wins (was: first match in mob-array
				-- order, whatever its distance). Fresh mobs are handled further down.
				unblacklist_hitters(mobs)  -- v4.12: a mob hitting you is always back in the fight
				local _aggro_d = math.huge
				for _, mob in pairs(mobs) do
					if mob and mob.spawn_type == 16 and mob.hpp and mob.hpp > 0 and mob.valid_target and mob.distance
					   and is_mob_whitelisted(mob.name)
					   and not is_mob_name_blacklisted(mob.name, mob.id)
					   and not is_cant_target_blocked(mob.id)  -- v3.83: don't lock back onto an unreachable mob
					   and (mob.claim_id == 0 or pull_party_ids[mob.claim_id] or is_purple_excluded(mob.name)) then
						local _d = mob.distance:sqrt()
						local _hot = (mob.claim_id ~= 0 and pull_party_ids[mob.claim_id])
						          or (_d <= 3.0 + (mob.model_size or 2.0) and not full_party_hold())  -- v4.54
						if not _hot and mob.target_index and mob.target_index > 0 then
							if me_index and mob.target_index == me_index then
								_hot = true
							else
								for key, member in pairs(party) do
									if type(key) == 'string' and type(member) == 'table' and key:match('^p[0-5]$')
									   and member.mob_index and mob.target_index == member.mob_index then
										_hot = true
										break
									end
								end
							end
						end
						if _hot and _d < _aggro_d then
							_aggro_d = _d
							aggro_target = mob
						end
					end
				end


				-- 2. Handle the found mob or look for a new one
				local target = nil
				-- v3.73: Declared here (same scope as target) so it survives into the
				-- get_mob_by_id fallback at step 3. v3.71/v3.72 declared this inside the
				-- else/no-aggro block, so it went out of scope before step 3 ran — the
				-- fallback was always dead code.
				local pull_candidate = nil

				if aggro_target and aggro_target.id then
					-- v3.99: target by ID. '/target <bt>' and '/target "name"' are game-native,
					-- ignore mob_blacklist, and name-targeting picks ANY mob with that name --
					-- e.g. the blacklisted Death Jacket over the cliff instead of the one in the fight.
					pull_candidate = aggro_target
					local _cur_t = windower.ffxi.get_mob_by_target('t')
					if not _cur_t or _cur_t.id ~= aggro_target.id then
						debug_msg('Priority target: ' .. (aggro_target.name or 'Unknown') .. ' (' ..
						          string.format('%.1f', _aggro_d) .. 'y) - ID ' .. aggro_target.id)
						if set_target(aggro_target.id) then
							wait_cursor(aggro_target.id, 0.5)  -- v4.19: was a fixed 0.5s
						else
							coroutine.sleep(FAST_RETARGET and 0 or 0.5)
						end
					end
				else
					-- No active aggro: find closest mob within pull_dist
					local valid_facing = {n=true,s=true,e=true,w=true,ne=true,nw=true,se=true,sw=true,
					                      north=true,south=true,east=true,west=true,left=true,right=true,f=true}
					if fight_subcmd and fight_subcmd ~= ''
					   and valid_facing[fight_subcmd:lower()] then
						face(fight_subcmd)
					end

					-- v2.79: Fetch mob array once; reuse for melee cap check and proximity scan.
					local scan_all = windower.ffxi.get_mob_array()

					-- v3.02: Unblacklist mobs that are now reachable. The blacklist exists only
					-- to skip mobs that can't be targeted (wall-clip, LoS). Remove a mob when:
					--   (a) it is now targeting the player — it's aggro'd, definitely interactable
					--   (b) it moved into pull_dist — likely repositioned around the obstacle
					if scan_all then
						local _player = windower.ffxi.get_player()
						local _pidx = _player and _player.index
						for _bid, _bexp in pairs(cant_target_ids) do
							local _bm = scan_all[_bid]
							if _bm and _bm.hpp and _bm.hpp > 0 then
								local _targets_us = _pidx and _bm.target_index == _pidx
								local _in_range   = _bm.distance and _bm.distance:sqrt() <= pull_dist
								-- v3.83: never lift early for a repeat offender (2+ strikes). In the
								-- 2026-10-09 death the unreachable mob was hitting us at 3y, so this
								-- rule re-engaged it the moment it was blacklisted.
								if (cant_see_strikes[_bid] or 0) >= 2 then
									_targets_us = false; _in_range = false
								end
								-- v3.99: a pull-in timeout always runs its full 10s.
								if pull_in_nolift[_bid] and os.clock() < pull_in_nolift[_bid] then
									_targets_us = false; _in_range = false
								end
								if _targets_us or _in_range then
									local _reason = _targets_us and 'targeting player' or 'moved into range'
									debug_msg('Unblacklisting ' .. (_bm.name or '?') .. ': ' .. _reason)
									cant_target_ids[_bid] = nil
									cant_target_counts[_bid] = nil
								end
							end
						end
					end

					-- v2.79: Melee cap — if 2+ mobs ALREADY IN OUR FIGHT are within 6y, don't scan for
					-- new targets. Engage the nearest existing mob instead. Prevents pulling a 3rd mob
					-- when trusts have already dragged 2 into melee range while the player was
					-- status 0 (dead/raised).
					-- v3.70: Only count party-CLAIMED mobs (pull_party_ids[claim_id]). Unclaimed /
					-- non-aggro mobs nearby have claim_id == 0 and are valid pull targets — letting
					-- them trigger the cap caused an infinite settarget loop (target stays nil on the
					-- same tick as settarget fires, so the final gate never resolved).
					local melee_cap_count = 0
					local nearest_cap_mob = nil
					local nearest_cap_d   = 999
					if scan_all then
						for _, m in pairs(scan_all) do
							-- v2.98: Exclude purple mobs from melee cap count/selection.
						if m and m.spawn_type == 16 and m.hpp and m.hpp > 0 and m.valid_target and m.distance
							   and is_mob_whitelisted(m.name)
             and not is_mob_name_blacklisted(m.name, m.id)
							   and not is_cant_target_blocked(m.id)
							   and pull_party_ids[m.claim_id] then  -- v3.70: only party-claimed mobs
								local d = m.distance:sqrt()
								if d <= 6.0 then
									melee_cap_count = melee_cap_count + 1
									if d < nearest_cap_d then nearest_cap_d = d; nearest_cap_mob = m end
								end
							end
						end
					end

					if melee_cap_count >= 2 then
						debug_msg('Melee cap: ' .. melee_cap_count .. ' mobs in range. Engaging nearest without new pull.')
						if nearest_cap_mob and nearest_cap_mob.id and nearest_cap_mob.id > 0 then
							pull_candidate = nearest_cap_mob  -- v3.71: fallback for final gate
							set_target(nearest_cap_mob.id)
						else
							cmd('input /target <bt>')
						end
					elseif fresh_pull_hold(scan_all) then
						-- v4.12: low HP, or a mob is on you -- no new pull this tick
					else
						-- v2.79: Two-pass proximity scan: prefer mobs already in our party's fight
						-- (trust/player-claimed, partially damaged) over fresh unclaimed mobs. Within
						-- each group pick by shortest distance. This prevents jumping to a fresh spawn
						-- when a trust-hit mob at the same or lesser range is available.
						local closest_eng = nil  -- already engaged (claim_id != 0, in our party)
						local closest_eng_d = pull_dist + 1
						local closest_new = nil  -- fresh / unclaimed
						local closest_new_d = pull_dist + 1
						if scan_all then
							for _, mob in pairs(scan_all) do
								if mob and mob.spawn_type == 16
									and mob.hpp and mob.hpp > 0
									and mob.valid_target
									and mob.distance
									and is_mob_whitelisted(mob.name)
            and not is_mob_name_blacklisted(mob.name, mob.id)
									and not is_cant_target_blocked(mob.id)
									and (mob.claim_id == 0 or pull_party_ids[mob.claim_id] or is_purple_excluded(mob.name)) then
									local d = mob.distance:sqrt()
									if mob.claim_id ~= 0 then  -- already in our fight
										if d < closest_eng_d then closest_eng_d = d; closest_eng = mob end
									else                        -- fresh / unclaimed
										if d < closest_new_d then closest_new_d = d; closest_new = mob end
									end
								end
							end
						end
						local closest   = closest_eng or closest_new
						local closest_d = closest_eng and closest_eng_d or closest_new_d
						if closest then
							-- v2.96: Stale-pull guard. If the same mob is selected 3+ times within
							-- 12s without ever engaging, it's likely unreachable (floating, walled,
							-- despawned-but-still-in-array). Feed it into cant_target_ids so every
							-- scan path skips it for 10s.
							-- v3.36: Track mob selection here; count/blacklist moved to final-gate block.
							-- Old code incremented before claim_id was verified, so trust-claimed mobs
							-- looped at ~1s/iter and hit STALE_PULL_LIMIT before Dia ever fired.
							local now_sp = os.clock()
							if closest.id ~= stale_pull_id then
								stale_pull_id    = closest.id
								stale_pull_count = 0
								stale_pull_time  = now_sp
							end
							if not is_cant_target_blocked(closest.id) then
								debug_msg('Proximity scan: ' .. (closest.name or '?') .. ' (' .. string.format('%.1f', closest_d) .. 'y) - ID ' .. closest.id)
								if closest.id and closest.id > 0 then
									whitelist_cursor_id = 0  -- reset so out-of-range cursor re-locks on next gap
									pull_candidate = closest  -- v3.71: fallback for final gate
									set_target(closest.id)
								end
							end
						else
							if next(mob_whitelist_set) == nil then
								-- v3.99: nothing valid in pull range: wait for the next tick.
								-- /targetbnpc removed -- it is game-native, ignores mob_blacklist
								-- and the temporary blacklists, and kept landing on blacklisted
								-- or far-away mobs ("Target too far away (41.0y)" loop).
								-- v4.22: move_in_range -> pick the nearest mob out to MOVE_SCAN_DIST
								pull_candidate = move_far_pick(scan_all, pull_party_ids, pull_dist)
							else
								-- Whitelist active and nothing in pull range.
								-- Point the cursor at the closest whitelisted mob at ANY distance
								-- so the player can see it and run toward it. The final gate will
								-- not pull until it enters pull_dist.
								local _nearest_wl   = nil
								local _nearest_wl_d = math.huge
								if scan_all then
									for _, _m in pairs(scan_all) do
										if _m and _m.spawn_type == 16 and _m.hpp and _m.hpp > 0
										   and _m.valid_target and _m.distance
										   and is_mob_whitelisted(_m.name)
										   and not is_mob_name_blacklisted(_m.name, _m.id)
										   and not is_cant_target_blocked(_m.id)
										   and (_m.claim_id == 0 or pull_party_ids[_m.claim_id]
										        or is_purple_excluded(_m.name)) then
											local _d = _m.distance:sqrt()
											if _d < _nearest_wl_d then
												_nearest_wl_d = _d
												_nearest_wl   = _m
											end
										end
									end
								end
								if _nearest_wl then
									-- Only call settarget when the nearest mob changes.
									-- If it's the same mob as last tick, skip — the player
									-- may have manually re-targeted something else while
									-- running and we don't want to override them every second.
									if _nearest_wl.id ~= whitelist_cursor_id then
										whitelist_cursor_id = _nearest_wl.id
										debug_msg('Whitelist cursor: ' .. (_nearest_wl.name or '?') ..
											' (' .. string.format('%.1f', _nearest_wl_d) .. 'y)')
										if not set_target(_nearest_wl.id) then whitelist_cursor_id = 0 end  -- v3.96: retry next tick if skipped
									end
								else
									whitelist_cursor_id = 0  -- no mob found; reset so next find re-targets
								end
							end
						end
					end
					wait_cursor(pull_candidate and pull_candidate.id, 0.5)  -- v4.19: was a fixed 0.5s
				end



				-- 3. Update our local 'target' variable from the game's current target.
				-- v3.79: Pure cursor read (no get_mob_by_id substitution). If cursor is on
				-- a dead mob, /targetoff so settarget can resolve to the live mob next tick.
				-- v3.80: Also immediately blacklist the dead mob when found on cursor.
				-- Without blacklisting, the proximity scan (seeing stale hpp > 0 in the API)
				-- re-selects the same dead mob every tick: settarget resolves to dead mob →
				-- step 3 fires /targetoff → repeat forever with no PULL ABORTED ever firing
				-- (stale-pull and PULL ABORTED only increment inside the pull path, which
				-- step 3's dead-cursor check short-circuits before reaching). Blacklisting
				-- here forces the scan to skip the dead mob and pick a different live one.
				-- v4.11: /targetoff is no longer sent the same instant. 2 of 3
				-- FFXiMain.dll crashes (10/10 21:48:02 and 10/11 04:23:33, both
				-- @ 0x00076a75) hit the same second as this line, while the corpse
				-- was despawning. Now: quiet 3s, then /targetoff only if the
				-- cursor is STILL on that same dead ID (logged as TARGETOFF).
				target = windower.ffxi.get_mob_by_target('t')
				if target and target.hpp and target.hpp <= 0 then
					if target.id then
						cant_target_ids[target.id] = os.clock() + 5.0
						if dead_cursor_pending_id ~= target.id then
							dead_cursor_pending_id = target.id
							dead_cursor_count = (dead_cursor_count or 0) + 1
							debug_msg('Dead cursor (ID ' .. target.id .. '): blacklisting 5s, /targetoff deferred ' ..
								DEAD_CURSOR_TARGETOFF_DELAY .. 's.')
							target_quiet(nil, DEAD_CURSOR_TARGETOFF_DELAY + 0.5)
							local _dead_id = target.id
							coroutine.schedule(function()
								local ok_d, err_d = pcall(function()
									local t = windower.ffxi.get_mob_by_target('t')
									if t and t.id == _dead_id then
										debug_msg('TARGETOFF dead cursor ' .. _dead_id .. ' (still on cursor after ' ..
											DEAD_CURSOR_TARGETOFF_DELAY .. 's).')
										cmd('input /targetoff')
									else
										debug_msg('TARGETOFF skipped: dead cursor ' .. _dead_id .. ' already cleared.')
									end
								end)
								if dead_cursor_pending_id == _dead_id then dead_cursor_pending_id = nil end
								if not ok_d then info_msg('TARGETOFF error: ' .. tostring(err_d)) end
							end, DEAD_CURSOR_TARGETOFF_DELAY)
						end
					else
						target_quiet()
					end
					target = nil
				end

				-- 4. Final verification: Ensure target exists, is alive, and is claimable.
				-- v2.71: Added claim_id check -- the last gate before any pull fires.
				-- Catches all targeting paths (/target <bt>, /targetbnpc, name-target)
				-- since every path resolves through this block. A pink mob claimed by
				-- another party has their entity ID as claim_id; we skip it entirely.
				-- v2.79: pull_party_ids is now hoisted above both branches and includes the
				-- player's own ID; simplified check: claim_id == 0 OR in pull_party_ids.
				-- v4.54: party not full -> only mobs already fighting the party (cursor kept)
				if target and target.id and target.spawn_type == 16 and target.hpp and target.hpp > 0
				   and not fp_pull_ok(target) then
					-- PULL HOLD (logged by full_party_hold / fp_pull_ok)
				elseif target and target.id and target.hpp and target.hpp > 0
					and (target.spawn_type == 16)  -- v3.38: guard against targeting trusts/NPCs when settarget fails
					and is_mob_whitelisted(target.name)
        and not is_mob_name_blacklisted(target.name, target.id)
					and not is_cant_target_blocked(target.id)
					and (target.claim_id == 0 or pull_party_ids[target.claim_id] or is_purple_excluded(target.name)) then
					-- v3.36: Stale-pull count fires HERE (after claim_id gate), not in proximity scan.
					-- Trust-claimed mobs failed the gate and looped at ~1s/iter, hitting the limit
					-- before a single Dia was ever cast. Now only genuine 'pull fired, no engage'
					-- situations accumulate toward the blacklist threshold.
					local stale_blocked = false
					if target.id == stale_pull_id then
						local _now_sp = os.clock()
						if (_now_sp - stale_pull_time) <= STALE_PULL_WINDOW then
							stale_pull_count = stale_pull_count + 1
							if stale_pull_count >= STALE_PULL_LIMIT then
								debug_msg('Stale pull: ' .. (target.name or '?') .. ' ID ' .. target.id ..
								          ' attempted ' .. stale_pull_count .. 'x in ' ..
								          string.format('%.1f', _now_sp - stale_pull_time) ..
								          's with no engage. Blacklisting 10s.')
								cant_target_ids[target.id] = _now_sp + CANT_SEE_BLACKLIST_DUR
								cant_target_counts[target.id] = nil
								stale_pull_id = 0; stale_pull_count = 0; stale_pull_time = 0
								cmd('input /targetoff')
								stale_blocked = true
							end
						else
							-- Window expired — reset so this mob gets a fresh count
							stale_pull_count = 1; stale_pull_time = os.clock()
						end
					end

					-- v3.99: pull-in timeout (10s to get the mob in, then blacklist + rescan)
					if not stale_blocked and pull_in_check(target, pull_dist, false) then
						stale_blocked = true
					end

					if not stale_blocked then
					-- v2.62: t_face1 removed. It fired //facing f here, then t_face2 (below)
					-- fired again right before the Provoke/ra pull -- two //facing f commands
					-- within the same second. The game rejected one -> invalid arg. t_face2
					-- immediately before the pull is the correct and only face needed.
					coroutine.sleep(0.1)  -- v3.00: minimal settle before dist check

					--local dist = target.distance:sqrt() --Fix per Claude: "target.distance is a userdata vector in Windower's API. If it's unexpectedly nil (e.g., the mob just died or desynced), calling :sqrt() on it will error. You already guard against this in use_magic() (lines 811–815), but the same guard is missing in the main loop and is_target_valid. Wrap these like:"
					local dist = target.distance and target.distance:sqrt() or 999
					
					-- Calculate dynamic melee range based on the monster's size
					-- Default is ~3.0 yalms for players, plus the mob's scale
					local melee_range = 3.0 + (target.model_size or 2.0)

					-- v3.85: hold the pull (no /attack, no /ra) while Provoke is ready
					-- and the mob is in pull range but outside Provoke range.
					-- v3.93: Provoke hold moved to engaged_pull_logic(); here we only
					-- draw weapons (/attack on) once the mob is within ENGAGE_RANGE.
					local _prov_hold = false

                    if dist <= math.max(pull_dist, ENGAGE_RANGE) then
                        -- SYSTEMATIC CHECK: Only pull if outside dynamic melee range
						-- v2.97: pull_aborted flag gates /attack on so a range-miss doesn't
						-- silently engage a mob that's already out of pull range.
						local pull_aborted = false
						if dist > melee_range then
                            -- v2.58: pre-pull face is unconditional. WS lockout removed --
                            -- it applies to try_face_mob() during combat, not pull setup.
                            -- Without a guaranteed face, /ra fires blind when a WS just
                            -- killed the previous mob -> 'You cannot see the Apex Bats'.
                            do
                                local t_face2 = windower.ffxi.get_mob_by_target('t')
                                if t_face2 and t_face2.hpp and t_face2.hpp > 0 then
                                    face('f')
                                    coroutine.sleep(0.3)  -- let face resolve before pull fires
                                end
                            end
							info_msg('PULLING >>>> ' .. (target.name or '?'))
                            wait_cursor(target.id, 0.5) -- Wait for target lock (v4.19: returns once locked)
							local t_check1 = windower.ffxi.get_mob_by_target('t')
							if t_check1 and t_check1.hpp and t_check1.hpp > 0 then
								-- v2.97: Re-verify distance right before the pull command fires.
								-- The mob may have walked out of range during the face/sleep delays
								-- (~0.8-1.3s). If it's now beyond pull_dist, abort and re-scan.
								local pre_pull_d = t_check1.distance and t_check1.distance:sqrt() or 999
								if pre_pull_d > math.max(pull_dist, ENGAGE_RANGE) then
									debug_msg('Pull aborted: ' .. (t_check1.name or '?') ..
									          ' moved to ' .. string.format('%.1f', pre_pull_d) ..
									          'y (limit ' .. string.format('%.1f', pull_dist) .. 'y). /targetoff.')
									cmd('input /targetoff')
									pull_aborted = true
								else
									-- v3.93: draw weapons only. engaged_pull_logic() does the
									-- Provoke / pull_command once we're engaged.
									info_msg('ATTACKING >>>> (draw weapons at ' ..
									          string.format('%.1f', pre_pull_d) .. 'y) ' .. (t_check1.name or '?'))
									cmd('input /attack on')
									wait_for_engage()
									aa_quick_next = true  -- v4.19: run the engaged pull next, not 1s later
								end
							else
								debug_msg('PULL ABORTED: target died before pull fired. Blacklisting ID ' .. (target and target.id or '?') .. ' for 5s.')
								-- v3.77: Immediately blacklist the dead mob so the proximity scan
								-- doesn't re-select the same corpse on the very next tick.
								if target and target.id then
									cant_target_ids[target.id] = os.clock() + 5.0
								end
								-- v3.78: /targetoff here (where we know the mob is dead) to clear
								-- the cursor from the corpse before the next scan tick runs.
								-- Moved from melee path where it was racing against settarget.
								-- v4.42: deferred like the v4.11 dead cursor (was immediate)
								deferred_targetoff(target and target.id, 'pull aborted, mob died')
								pull_aborted = true
							end
						else
							-- Within melee range: /attack on fires below
                        end

						if not pull_aborted then
							if dist <= melee_range then
								-- v3.79: Reverted to v3.53 approach. The cursor is already set by
								-- the proximity scan's settarget + the 0.5s sleep before step 3.
								-- Step 3 only reaches here with a live mob (hpp > 0 gate passed),
								-- so the cursor IS on a live mob. Just fire /attack on directly.
								info_msg('ATTACKING >>>> (melee) ' .. (target.name or '?'))
								face_mob_direct(target)   -- v4.70: face before engaging ("Unable to see" on the first swing)
								cmd('input /attack on')
								if FAST_RETARGET then  -- v4.19
									wait_for_engage()
									aa_quick_next = true
								end
							end
							-- v3.93: no pull here; engaged_pull_logic() takes over next tick
						end

					elseif _prov_hold then
						-- v3.85: keep the cursor on the mob; provoke_pull_hold() logged
						-- PROVOKE-WAIT. Next tick pulls with Provoke once in range, or
						-- with pull_command once the hold times out.
						-- Undo this tick's stale-pull count: holding is not a failed pull,
						-- and 3 held ticks would otherwise blacklist the mob.
						if target.id == stale_pull_id and stale_pull_count > 0 then
							stale_pull_count = stale_pull_count - 1
						end
					else
						if move_mode() ~= 'off' and autoattack_type == 'pull' then
							-- v4.22: beyond weapon-draw range: run toward it (move_toward_mob logs)
							move_toward_mob(target, pull_dist - MOVE_STOP_MARGIN, false)
						elseif next(mob_whitelist_set) ~= nil then
							-- Whitelist active: keep cursor on this out-of-range whitelisted mob
							-- so the player can see it and run toward it. No pull or /attack until
							-- dist <= pull_dist, handled by the branch above.
							debug_msg('Whitelist cursor: ' .. (target.name or '?') ..
								' (' .. string.format('%.1f', dist) .. 'y — run toward it)')
						else
							debug_msg("Target too far away (" .. string.format("%.1f", dist) .. "y). /targetoff, skipping it 10s.")
							if target.id then cant_target_ids[target.id] = os.clock() + 10 end  -- v4.24
							cmd('input /targetoff')
						end
					end
				end  -- if not stale_blocked
				else
					-- v3.06: Target failed whitelist/blacklist/valid_target — clear cursor immediately
					-- v3.99: log it when the cursor was on a mob_blacklist entry
					if target and target.id and is_mob_name_blacklisted(target.name, target.id) then
						debug_msg('Cursor on blacklisted mob ' .. (target.name or '?') .. ' (ID ' .. target.id .. '). /targetoff.')
					end
					cmd('input /targetoff')
				end	
				
				-- target = windower.ffxi.get_mob_by_target('t')
				-- if not target or not target.id or not target.hpp or target.hpp > 0
				 
				-- v3.96: spin pull (//aa pull spin) removed -- nearest-mob targeting covers it.

				end  -- closes: if party and mobs then
            end

			
        -- Logic: If engaged (Status 1), perform combat actions
		elseif player.status == 1 then
			aa_stage('engaged')  -- v4.25
			-- v3.11: ASSIST facing — /target <bt> then //facing f every
            -- FACE_COMBAT_RATE seconds, unconditional at top of status==1.
            -- v3.25: use 1s rate for first 5s after new target (burst window).
            if autoattack_type == 'assist' then
                local _now_af = os.clock()
                local _face_rate = (_now_af < assist_face_burst_until) and 1.0 or FACE_COMBAT_RATE
                if (_now_af - last_face_combat_time) >= _face_rate then
                    local _, _bt_sent = assist_target_bt('face')  -- v4.42
                    if _bt_sent then coroutine.sleep(0.3) end
                    face('f')
                    last_face_combat_time = _now_af
                end
            end

            -- v2.96: Clear stale-pull state on engage so the same mob can be targeted
			-- normally in future fights (different encounter, new spawn, etc.)
			stale_pull_id = 0; stale_pull_count = 0; stale_pull_time = 0
			-- Reset per-mob trackers when target changes
			local current_target = windower.ffxi.get_mob_by_target('t')
			if current_target and current_target.id ~= last_target_id then
				last_target_id = current_target.id
				ability_use_tracker = {}
				magic_use_tracker = {}
				-- v3.45: Clear debuff-spell timers so every new mob gets a fresh debuff
				-- rotation regardless of how recently they were cast on the previous mob.
				-- Buff-spell timers are intentionally preserved across mobs (buffs persist).
				if current_config.magic then
					for _, mg_entry in ipairs(current_config.magic) do
						if mg_entry and mg_entry.name and mg_entry.type == 'debuff' then
							magic_last_used[mg_entry.name .. '||' .. (mg_entry.target or '<t>')] = nil
						end
					end
				end
				item_mob_use_count = {}
				weakness_spell_index = {} 
				ws_index = 1
				current_ws_use_count = 0
				ws_sc_locked = false  -- clear SC lockout for new mob
					cant_see_flag = false  -- clear cant-see flag for new mob
				low_hp_pull_done = false   -- v2.74: reset so PullNext can fire for each new mob in a chain
				low_hp_skip_logged = false -- v2.74: matching reset so the scan message re-fires cleanly
				repull_count = 0           -- v3.13: reset re-pull counter for each new mob
				last_face_combat_time = os.clock()  -- v2.70: don't face immediately on new target; t_face2 already faced during pull, firing face_combat() 1s later causes double-face -> invalid arg
				-- v3.25: ASSIST mode — arm 5s facing burst so periodic block uses 1s rate on new mob
				if autoattack_type == 'assist' then
					assist_face_burst_until = os.clock() + 5.0
				end
				fast_kill_until = 0  -- v4.19: engaged on the next mob, normal tick rate again
				debug_msg('New target detected: resetting WS index.')  -- optional but helpful
			end

			-- v2.90: Purple-mob escape. If the current target got claimed by another
			-- party while we were engaging (race condition on a contested pull), disengage
			-- immediately so we don't waste time attacking a mob we can't claim XP from.
			-- v2.94: purple_limbo_until timer. When no replacement is found after escaping,
			-- hold /attack off for 15s instead of re-firing the escape every 2-3s and
			-- spamming /attack off while the purple mob keeps auto-retargeting the player.
			-- v3.34: Purple escape — redesigned so rescue scan runs from ALL three
			-- paths (packet, limbo, claim_id). Previously the packet path only cleared
			-- the flag and skipped the tick; the limbo path only fired /attack off.
			-- Neither ever scanned for a replacement, so Shadowhammer sat idle for
			-- the full 15s limbo even when other mobs were in range. Now:
			--   • run_rescue_scan = true from any escape path
			--   • rescue scan runs every tick until a replacement is found or 15s expires
			--   • limbo is only set AFTER the scan comes up empty (not pre-emptively)
			--   • ASSIST mode skips rescue scan (follows leader, doesn't pull solo)
			local skip_combat_this_tick = false
			local run_rescue_scan = false

			if purple_from_packet then
				-- Packet handler already fired /attack off + /targetoff.
				-- Suppress combat this tick and immediately scan for a replacement.
				purple_from_packet = false
				skip_combat_this_tick = true
				run_rescue_scan = true

			elseif os.clock() < purple_limbo_until then
				-- In limbo: hold /attack off and keep scanning every tick.
				-- As soon as a replacement mob appears, we exit limbo and engage.
				cmd('input /attack off')
				skip_combat_this_tick = true
				run_rescue_scan = true

			elseif current_target and current_target.claim_id and current_target.claim_id ~= 0 then
				local esc_party_ids = {}
				local esc_pdata = windower.ffxi.get_party()
				if esc_pdata then
					for key, member in pairs(esc_pdata) do
						if type(member) == 'table' and key:match('^p[0-5]$') then
							local eid = member.mob and member.mob.id
							if not eid and member.mob_index and member.mob_index > 0 then
								local pm = windower.ffxi.get_mob_by_index(member.mob_index)
								eid = pm and pm.id
							end
							if eid then esc_party_ids[eid] = true end
						end
					end
				end
				if player and player.id then esc_party_ids[player.id] = true end
				if not esc_party_ids[current_target.claim_id]
				   and not is_purple_excluded(current_target.name) then
					info_msg('Purple mob: ' .. (current_target.name or '?') .. ' claimed by another party. Disengaging.')
					aa_block_mob(current_target.id, 60, 'claimed by another party')   -- v5.00
					cmd('input /attack off')
					cmd('input /targetoff')
					coroutine.sleep(0.5)  -- brief settle (down from 1.0s)
					skip_combat_this_tick = true
					run_rescue_scan = true
				end
			end

			-- Rescue scan: find nearest unclaimed whitelisted mob and engage it.
			-- Only runs in PULL mode — ASSIST follows the leader's target, not solo mobs.
			if run_rescue_scan and autoattack_type == 'pull' then
				local rsc_party_ids = {}
				local rsc_pdata = windower.ffxi.get_party()
				if rsc_pdata then
					for key, member in pairs(rsc_pdata) do
						if type(member) == 'table' and key:match('^p[0-5]$') then
							local eid = member.mob and member.mob.id
							if not eid and member.mob_index and member.mob_index > 0 then
								local pm = windower.ffxi.get_mob_by_index(member.mob_index)
								eid = pm and pm.id
							end
							if eid then rsc_party_ids[eid] = true end
						end
					end
				end
				if player and player.id then rsc_party_ids[player.id] = true end
				local rescue_mob  = nil
				local rescue_dist = pull_dist + 1
				local rsc_mobs = windower.ffxi.get_mob_array()
				if rsc_mobs then
					for _, m in pairs(rsc_mobs) do
						if m and m.spawn_type == 16
						   and m.hpp and m.hpp > 0
						   and m.valid_target
						   and m.distance
						   and is_mob_whitelisted(m.name)
						   and not is_mob_name_blacklisted(m.name, m.id)
						   and not is_cant_target_blocked(m.id)
						   and (m.claim_id == 0 or rsc_party_ids[m.claim_id]) then
							local d = m.distance:sqrt()
							if d <= pull_dist and d < rescue_dist then
								rescue_dist = d
								rescue_mob  = m
							end
						end
					end
				end
				if rescue_mob then
					info_msg('Purple escape: switching to ' .. (rescue_mob.name or '?') .. ' (' .. string.format('%.1f', rescue_dist) .. 'y)')
					purple_limbo_until = 0
					set_target(rescue_mob.id)
					coroutine.sleep(0.6)
					-- v5.00: only attack once the cursor is really on it (11-21 10:53: /attack on
					-- went to the wrong bat, then off again, then 19s of retargeting)
					local _pc = windower.ffxi.get_mob_by_target('t')
					if not (_pc and _pc.id == rescue_mob.id) then
						coroutine.sleep(0.4)
						_pc = windower.ffxi.get_mob_by_target('t')
					end
					if _pc and _pc.id == rescue_mob.id then
						face('f')
						coroutine.sleep(0.3)
						cmd('input /attack on')
						coroutine.sleep(0.5)
						skip_combat_this_tick = false  -- new target engaged, allow combat this tick
					else
						debug_msg('Purple escape: cursor did not move to ' .. (rescue_mob.name or '?') .. ' -- no /attack on, the normal scan takes over.')
					end
				else
					-- Nothing in range yet. Start (or maintain) 15s limbo.
					-- The scan will keep running each tick, so the moment a mob
					-- appears we exit limbo without waiting the full 15s.
					if purple_limbo_until <= os.clock() then
						purple_limbo_until = os.clock() + 15
						debug_msg('Purple escape: no replacement in range — scanning each tick, up to 15s.')
					end
				end
			end

            -- v3.83: Stuck-engage watchdog (PULL mode only; ASSIST just follows <bt>).
            -- 2026-10-09: engaged on a Death Jacket 3y away for 71 minutes -- every melee
            -- round "Unable to see", every WS "You cannot see", zero damage dealt.
            if autoattack_type == 'pull' and not skip_combat_this_tick then
                local _sw_t   = windower.ffxi.get_mob_by_target('t')
                local _sw_now = os.clock()
                if _sw_t and _sw_t.id and _sw_t.hpp and _sw_t.hpp > 0 then
                    if _sw_t.id ~= stuck_watch_id then
                        stuck_watch_id = _sw_t.id
                        stuck_watch_start = _sw_now
                    end
                    local _sw_dist  = _sw_t.distance and _sw_t.distance:sqrt() or 999
                    local _sw_melee = 3.0 + (_sw_t.model_size or 2.0)
                    local _sw_disabled = false
                    for _, _b in ipairs(player.buffs or {}) do
                        if STUCK_SKIP_BUFFS[_b] then _sw_disabled = true; break end
                    end
                    if _sw_dist > _sw_melee or _sw_disabled or mob_in_our_fight(_sw_t) then  -- v4.01/v4.02
                        stuck_watch_start = _sw_now  -- only count time we could/should be hitting
                    elseif (_sw_now - math.max(stuck_watch_start, last_offense_time)) >= STUCK_TIMEOUT then
                        local _dur, _n = blacklist_unreachable(_sw_t.id)
                        info_msg('STUCK: no attacks landed on ' .. (_sw_t.name or '?') .. ' (ID ' .. _sw_t.id ..
                            ') for ' .. STUCK_TIMEOUT .. 's in melee range. Strike ' .. _n ..
                            ' -- blacklisting ' .. _dur .. 's and disengaging.')
                        stuck_watch_id = 0
                        cmd('input /attack off')
                        coroutine.sleep(0.3)
                        cmd('input /targetoff')
                        skip_combat_this_tick = true
                    end
                end
            end

            -- v3.09: ASSIST mode: if <t> is missing while status==1 (e.g. cursor was
            -- cleared by UI/escape/death), re-acquire via <bt> before is_target_valid()
            -- runs. Without this, is_target_valid() returns false → the else branch
            -- fires /attack off + /targetoff every tick, and //facing never runs.
            if autoattack_type == 'assist' and not skip_combat_this_tick then
                local _t = windower.ffxi.get_mob_by_target('t')
                if not _t or not _t.hpp or _t.hpp <= 0 then
                    -- v4.42: was an unchecked /target <bt> the instant <t> died
                    local _, _bt_sent = assist_target_bt('cursor lost')
                    if _bt_sent then coroutine.sleep(0.2) end
                end
            end

            if not skip_combat_this_tick and is_target_valid(math.max(pull_dist, ENGAGE_RANGE)) then  -- v3.93: engaged out to ENGAGE_RANGE
				-- Packet-based cant-see backup: incoming chunk 0x017 may set this flag.
				-- face_combat() now handles consistent facing; this is belt-and-suspenders.
				if cant_see_flag then
					cant_see_flag = false
					facing_emergency()
				end
				if not hs_hold_active() then heal_party() end   -- v4.41: HOT-SWITCH-HOLD
				-- Priority order: re-pull -> PullNext -> combat chain -> face_combat
				-- Re-pull (mob wandered out of range)
				-- v2.86: Skip projectile re-pull for 'dia' method. Mage jobs fight at range
				-- intentionally; firing /ma dia every tick while mob is outside melee range
				-- blocks run_combat_chain() for 2+ seconds each loop and spams recast errors.
				-- Provoke (if WAR sub is available) still fires; otherwise do nothing and let
				-- the mob stay engaged naturally.

				-- v3.93: all pull / re-pull decisions while engaged live in engaged_pull_logic()
				if not hs_hold_active() and closer_target_check(pull_dist) then coroutine.sleep(0.3) end  -- v4.24: closer mob in our fight (v4.41: not during HOT-SWITCH-HOLD)
				engaged_pull_logic(pull_command, pull_dist, pull_wait, cfg.pull and cfg.pull.method)
				
				-- PullNext_OnLowHP: highest priority once SC lockout clears
				-- Low-HP next-mob: ST-style pull
				-- 1. Store current mob ID
				-- 2. SetTarget next mob and pull it
				-- 3. Immediately SetTarget back to current mob to finish it
				-- low_hp_pull_done prevents re-pulling every tick once already done
				if pull_next_on_low_hp and autoattack_type == 'pull' and not hs_hold_active() then  -- v4.41
					-- v2.73: Fetch cur BEFORE cooldown check so the death-reset at the bottom
					-- always fires when cur.hpp reaches 0, even when cooldown is active.
					-- Previously cur was fetched inside the else-branch; when the cooldown
					-- fired, cur was nil at the reset check and low_hp_pull_done stayed true
					-- permanently, silently blocking all future PullNext pulls.
					local cur = windower.ffxi.get_mob_by_target('t')
					-- v2.45: Global cooldown prevents cascade pulls. When mob1 dies and auto-target
					-- switches to mob2 (already damaged by trusts), mob2.hpp may already be
					-- <= LowHPPrcnt, firing another pull immediately and pulling mob3, mob4, etc.
					-- Suppress all PullNext pulls for PULL_NEXT_COOLDOWN seconds after the last one.
					local time_since_pull_next = os.clock() - last_pull_next_time
					if last_pull_next_time > 0 and time_since_pull_next < PULL_NEXT_COOLDOWN then
						if not low_hp_skip_logged then
							debug_msg('PullNext cooldown: ' .. string.format('%.1f', PULL_NEXT_COOLDOWN - time_since_pull_next) .. 's remaining after last pull.')
							low_hp_skip_logged = true
						end
					else
					low_hp_skip_logged = false  -- v3.22: cooldown expired, allow next scan/pull to log
					if cur and cur.hpp and cur.hpp > 0 and cur.hpp <= low_hp_prcnt and not low_hp_pull_done then
						lhp_note(cur.id, 'scan', 'Low HP: ' .. (cur.name or '?') .. ' at or under ' .. low_hp_prcnt .. '% - looking for the next mob.')  -- v4.76: once per mob
						local next_all = windower.ffxi.get_mob_array()
						local next_mob = nil
						local next_d   = pull_dist + 1
						local my_id2   = player and player.id or 0
						-- v2.79: Build trust-aware party ID set with mob_index fallback for reliability.
						-- Primary: member.mob.id. Fallback: get_mob_by_index(member.mob_index).id.
						-- Also include player's own ID explicitly. Mobs claimed by other parties
						-- (not in party_ids) are excluded as "pink" and never pulled.
						local party_ids = {}
						local pdata = windower.ffxi.get_party()
						if pdata then
							for key, member in pairs(pdata) do
								if type(member) == 'table' and key:match('^p[0-5]$') then
									local eid = member.mob and member.mob.id
									if not eid and member.mob_index and member.mob_index > 0 then
										local pm = windower.ffxi.get_mob_by_index(member.mob_index)
										eid = pm and pm.id
									end
									if eid then party_ids[eid] = true end
								end
							end
						end
						if my_id2 > 0 then party_ids[my_id2] = true end
						if next_all then
							-- v2.79: Two-pass scan: prefer mobs already in our fight (trust/player-claimed,
							-- partially damaged) over fresh unclaimed mobs. Within each group pick closest.
							-- Prevents PullNext jumping past a nearby trust-hit mob to a distant fresh spawn.
							local next_eng = nil
							local next_eng_d = pull_dist + 1
							local next_new = nil
							local next_new_d = pull_dist + 1
							for _, mob in pairs(next_all) do
								if mob and mob.spawn_type == 16
									and mob.hpp and mob.hpp > 0
									and mob.valid_target
									and mob.distance
									and mob.id ~= cur.id
									and is_mob_whitelisted(mob.name)
            and not is_mob_name_blacklisted(mob.name, mob.id)
									and not is_cant_target_blocked(mob.id)
									and (mob.claim_id == 0 or party_ids[mob.claim_id]) then
									local d = mob.distance:sqrt()
									if d <= pull_dist then
										if mob.claim_id ~= 0 then  -- already in our fight
											if d < next_eng_d then next_eng_d = d; next_eng = mob end
										else                        -- fresh / unclaimed
											if d < next_new_d then next_new_d = d; next_new = mob end
										end
									end
								end
							end
							next_mob = next_eng or next_new
							next_d   = next_eng and next_eng_d or next_new_d
						end
						if not next_mob then   -- v4.76
							lhp_note(cur.id, 'none', 'Low HP pull: no free mob within ' .. string.format('%.1f', pull_dist) .. 'y to pull next.')
						end
						if next_mob then
						-- v2.71: SC lockout no longer blocks PullNext_OnLowHP.
						-- Previously ws_sc_locked gated the pull until the chain closed, but
						-- the intent is to pre-pull the next mob as early as possible so it
						-- walks into melee range by the time the current mob dies. Firing
						-- during an active SC is fine -- Provoke on the next mob does not
						-- interrupt the chain on the current mob.
						do
							-- Count mobs currently in melee range of the PLAYER (excluding current target).
							-- Only pull a 2nd mob if cur is the ONLY mob in melee range (mobs_in_melee == 0).
							-- Raised from 6y to 10y so flying/moving mobs (e.g. Apex Bats) that drift
							-- slightly out of tight melee range are still counted and suppress new pulls.
							-- v2.89: Exclude purple mobs (claimed by other parties) and non-whitelisted
							-- mobs from the count. Nearby players fighting their own mobs were triggering
							-- the cap and silently blocking all PullNext pulls.
							local PLAYER_MELEE_RADIUS = 10.0
							-- v4.76: only mobs in OUR fight count (claimed by the party, targeting
							-- or hitting one of us). Idle unclaimed mobs nearby used to count: on
							-- 11-18 the next bat was within 10y at 146 of 157 kills, so PullNext
							-- never fired.
							local _hs_ids, _hs_idx = hs_party_sets(windower.ffxi.get_player())
							local mobs_in_melee = 0
							if next_all then
								for _, mob in pairs(next_all) do
									if mob and mob.spawn_type == 16
										and mob.hpp and mob.hpp > 0
										and mob.valid_target
										and mob.distance
										and mob.id ~= cur.id
										and is_mob_whitelisted(mob.name)
             and not is_mob_name_blacklisted(mob.name, mob.id)
										and (mob.claim_id == 0 or party_ids[mob.claim_id])
										and hs_is_hot(mob, _hs_ids, _hs_idx) then  -- v4.76
										local mob_d = mob.distance:sqrt()
										if mob_d <= PLAYER_MELEE_RADIUS then
											mobs_in_melee = mobs_in_melee + 1
										end
									end
								end
							end
							-- PullNextMax = total mobs allowed in fight (including current target).
							-- mobs_in_melee counts OTHER mobs, so cap is (PullNextMax - 1).
							-- e.g. PullNextMax=6: pull freely until 5 others + current = 6 total.
							--      PullNextMax=2: only pull when current is the sole mob (original behavior).
							local pull_next_cap = math.max(0, pull_next_max - 1)
							if mobs_in_melee >= pull_next_cap then
								lhp_note(cur.id, 'cap', 'Low HP pull skipped: ' .. mobs_in_melee .. ' other mob(s) already fighting us (cap ' .. pull_next_cap .. ' from PullNextMax=' .. pull_next_max .. ').')  -- v4.76
								-- Don't set low_hp_pull_done - re-evaluate next tick
							else
								local next_melee_range = 3.0 + (next_mob.model_size or 2.0)
								-- v4.76: skip only a mob that is already fighting us; an idle mob in
								-- melee range gets pulled too (Locus Dire Bats don't aggro on their own)
								if next_d <= next_melee_range and hs_is_hot(next_mob, _hs_ids, _hs_idx) then
									-- Already in melee range - will aggro naturally, no pull needed
									lhp_note(cur.id, 'melee', 'Low HP pull skipped: ' .. (next_mob.name or '?') .. ' (' .. string.format('%.1f', next_d) .. 'y) is already fighting us.')  -- v4.76
									low_hp_pull_done = true
								elseif full_party_hold() then
									-- v4.54: party not full -- no second mob (checked again next tick)
								else
								-- v4.76: Provoke the next mob by ID and stay on the current one (no
								-- cursor switch / switch back -- that never worked while engaged)
								if not next_mob.id or next_mob.id <= 0 then
									debug_msg('Low HP pull: next_mob has invalid ID, skipping.')
								else
								if next_d <= PROVOKE_PULL_RANGE and provoke_pull_ready() and aa_ws_ago() < JA_AFTER_WS_GAP then
									-- v4.77: a JA inside our WS animation is dropped by the server --
									-- 11-18: 129 of 129 pull Provokes sent <3s after our WS failed,
									-- 160 of 166 sent >=4s after it worked. Wait, try next tick.
									lhp_note(cur.id, 'wsgap', 'Low HP pull: waiting for our WS animation before Provoking ' .. (next_mob.name or '?') .. '.')
								elseif next_d <= PROVOKE_PULL_RANGE and provoke_pull_ready() then
									info_msg('Next mob: ' .. (next_mob.name or '?') .. ' (' .. string.format('%.1f', next_d) ..
										'y) -- Provoke, staying on ' .. (cur.name or '?') .. ' (' .. tostring(cur.hpp) .. '%).')
									if provoke_by_id(next_mob, 'pull next') then
										last_pull_next_mob_id   = next_mob.id
										last_pull_next_mob_time = os.clock()
									end
								else
									lhp_note(cur.id, 'noprov', 'Low HP pull: Provoke not ready or ' .. (next_mob.name or '?') .. ' out of range (' ..
										string.format('%.1f', next_d) .. 'y) -- it gets the after-kill Provoke.')
								end
									-- v3.22: do NOT set low_hp_pull_done = true here.
								-- PULL_NEXT_COOLDOWN paces successive pulls; mobs_in_melee >= pull_next_cap
								-- stops them at PullNextMax. Setting done=true here blocked all further
								-- pulls until the current mob died, making PullNextMax > 2 ineffective.
								last_pull_next_time = os.clock()  -- v2.45: start cooldown to prevent cascade pulls
								low_hp_skip_logged = false  -- v3.22: allow next pull-scan to log after cooldown
								end  -- closes: if not next_mob.id or next_mob.id <= 0
								skip_combat_this_tick = false  -- target is now confirmed back on cur; resume combat immediately
							end
						end  -- closes if mobs_in_melee >= 1
						end  -- closes do block
						end  -- closes if next_mob then
					end  -- closes: if cur and cur.hpp...
					end  -- closes: cooldown else branch
					-- Reset flag once current mob is dead
					if cur and (not cur.hpp or cur.hpp <= 0) then
						low_hp_pull_done = false
						low_hp_skip_logged = false
					end
				end

				-- Combat chain: WS / JA / rings / magic
				-- safe_call('use_magic_burst',   use_magic_burst)
				-- safe_call('use_job_abilities', use_job_abilities)
				-- safe_call('use_weapon_skill',  use_weapon_skill)
				-- safe_call('use_rings',         use_rings)
				-- safe_call('use_item_food',     use_item_food)
				-- safe_call('use_magic',         use_magic)
				-- safe_call('use_weakness_magic',use_weakness_magic) 
				
				-- Sprinkle last_operation updates throughout the key functions:
				-- last_operation = 'use_magic_burst'
				-- debug_msg('TRACE: calling use_magic_burst')
				-- Run each combat function, stopping the chain if target dies between calls
				local function target_alive()
					local t = windower.ffxi.get_mob_by_target('t')
					return t and t.hpp and t.hpp > 0
				end
				local combat_suppressed = skip_combat_this_tick
				skip_combat_this_tick = false  -- always reset each tick
				local function run_combat_chain()
					-- When ws_sc_locked is true a WS with LockOut=1 has fired and we are
					-- waiting for the closing WS (LockOut=0) to complete the skillchain.
					-- Only use_weapon_skill runs during this window; everything else is
					-- skipped so nothing delays the next WS in the chain.
					-- v4.32: Dread Spikes mode first (gear; Dispel > nukes > /ra; no WS)
					if ds_tick() then return end
					if ws_sc_locked then
						use_weapon_skill()
						return
					end
					-- v3.93: use_provoke_for_hate() removed here; engaged_pull_logic() handles
					-- Provoke when the mob is out of melee range.
					if not target_alive() then return end
					use_magic_burst()
					if not target_alive() then return end
					pet_logic(true)  -- v3.94: summon / send pet in
					if not target_alive() then return end
					-- v4.70: group skillchain (aa_config.lua -> group_skillchain) plans the
					-- party's weapon skills; false = not active, job_config ws_list runs
					local _gsc = gsc_tick()
					if _gsc == 'fired' then return end
					if not target_alive() then return end
					if _gsc ~= 'hold' then use_job_abilities() end
					if not target_alive() then return end
					if not _gsc then use_weapon_skill() end
					if not target_alive() then return end
					if _gsc ~= 'hold' then use_rings() end
					if not target_alive() then return end
					use_item_food()
					if not target_alive() then return end
					use_magic()
					if not target_alive() then return end
					use_weakness_magic()
				end
				if hs_hold_active() then
					-- v4.41: HOT-SWITCH-HOLD -- no WS / JA / magic until our first melee round
				elseif combat_suppressed then
					debug_msg('Combat suppressed this tick (ST swap in progress).')
				else
					run_combat_chain()
				end
				-- v2.67: face_combat() runs AFTER run_combat_chain() so last_ws_time
				-- and last_ability_time are already updated when the face guard checks
				-- them. Previously it ran before the chain: face fired, then a WS or JA
				-- fired on the same tick -> invalid arg every time.
				face_combat()

            elseif os.clock() < hot_switch_until then
                coroutine.sleep(0.1)  -- v4.20: hot switch in flight -- don't sheathe
            else
                -- v3.09: In ASSIST mode, don't force /attack off — the game will
                -- disengage naturally when the mob dies. Forcing it here caused a
                -- loop: /attack off → status stays 1 → is_target_valid false → repeat.
                -- v4.42: not at a corpse / inside the kill quiet window (corpse_hold_check)
                if autoattack_type ~= 'assist' and not corpse_hold_check('disengage') then
                    cmd('input /attack off')
                    coroutine.sleep(0.3)
                    cmd('input /targetoff')
                end
                -- v3.03: Face the nearest mob already targeting us so we're turned
                -- toward the next threat the instant the current mob dies.
                do
                    local _fp = windower.ffxi.get_player()
                    local _fmobs = windower.ffxi.get_mob_array()
                    if _fp and _fmobs then
                        local _fidx = _fp.index
                        local _fnext, _fdist = nil, 999
                        for _, _fm in pairs(_fmobs) do
                            if _fm and _fm.spawn_type == 16
                               and _fm.hpp and _fm.hpp > 0
                               and _fm.target_index == _fidx
                               and not is_cant_target_blocked(_fm.id)  -- v3.83
                               and _fm.distance then
                                local _fd = _fm.distance:sqrt()
                                if _fd < _fdist then _fdist = _fd; _fnext = _fm end
                            end
                        end
                        if _fnext then
                            debug_msg('v3.03: Facing next mob: ' .. (_fnext.name or '?') .. ' (' .. string.format('%.1f', _fdist) .. 'y)')
                            -- v4.19: turn straight at it. The old set_target -> face -> /targetoff
                            -- was always skipped here (TARGET-SKIP: quiet window after kill).
                            face_mob_direct(_fnext)
                        end
                    end
                end
                ws_index = 1
                current_ws_use_count = 0
                ws_sc_locked = false  -- v2.80: clear SC lock when fight ends so it never bleeds into next mob
                low_hp_pull_done = false  -- reset for next fight
                low_hp_skip_logged = false
                item_mob_use_count = {}
                local now_prune = os.time()
                for k, v in pairs(ring_locks) do
                    if v <= now_prune then ring_locks[k] = nil end
                end
                -- v3.00: Prune expired cant-see blacklist entries (prevents unbounded growth)
                -- v3.98: moved into prune_blacklists(); also clears stale hit counters.
                prune_blacklists()
                coroutine.sleep((FAST_RETARGET and os.clock() < fast_kill_until) and 0.1 or 0.5)  -- v4.19
            end
        end
        
        aa_loop_nap()  -- v4.19: was coroutine.sleep(1)
    end
end



function is_target_valid(pull_dist)
    local player = windower.ffxi.get_player()
    if not (player and player.status == 1) then 
		-- debug_msg('No Player, or Player status not 1.')
		return false 
	end

    -- Using 't' is often more reliable than player.target_index for active combat
    local target = windower.ffxi.get_mob_by_target('t')        
    
    if target and target.spawn_type == 16 then
        --local dist = target.distance:sqrt() --Fix per Claude: "target.distance is a userdata vector in Windower's API. If it's unexpectedly nil (e.g., the mob just died or desynced), calling :sqrt() on it will error. You already guard against this in use_magic() (lines 811–815), but the same guard is missing in the main loop and is_target_valid. Wrap these like:"
		local dist = target.distance and target.distance:sqrt() or 999
        
        -- Check 1: Is the mob dead?
        if not target.hpp or target.hpp <= 0 then
            -- debug_msg('is_target_valid: Target Dead.')
            return false
        end

        -- Check 2: Distance logic
        -- We use pull_dist + 5 as a 'grace buffer' so you don't disengage 
        -- just because the mob moved slightly out of pulling range.
        if dist > (pull_dist + 5) then
            -- debug_msg('is_target_valid: Target out of range ('..string.format("%.1f", dist)..'y).')
            return false
        end

        -- Check 3: Systematic Melee Check (Optional Debug)
        local melee_range = 3.0 + (target.model_size or 2.0)
        if dist > melee_range then
            -- Note: We still return TRUE here because you might be running 
            -- toward the mob or waiting for it to come to you.
            -- debug_msg('Target out of melee range, but still valid.')
        end

        return true
    end

    -- debug_msg('is_target_valid: No valid monster targeted.')
    return false
end



-- Call this when the script loads
windower.register_event('load', function()
    update_job_configs()
    local _info      = windower.ffxi.get_info()
    local _zone_id   = _info and _info.zone or 0
    local _zone_name = res and res.zones and res.zones[_zone_id] and res.zones[_zone_id].english or ('Zone ' .. _zone_id)
    info_msg('AutoAttack v' .. _addon.version .. ' loaded — Zone: ' .. _zone_name .. ' (ID ' .. _zone_id .. ')' ..
              ' — target mode: ' .. tostring(settings.target_mode))
end)

--[[
v3.13 - ADD re-pull limit: after REPULL_LIMIT (3) re-pulls with mob still
       outside melee range, blacklist mob for 10s and disengage so scan
       finds next closest mob instead of looping indefinitely
v3.11 - FIX ASSIST facing: /target <bt> + //facing f every FACE_COMBAT_RATE
       seconds, unconditional at top of status==1 block
v3.10 - FIX ASSIST facing: move //facing block to TOP of status==1 (superseded)
v3.09 - FIX ASSIST mode: re-acquire <bt> before is_target_valid() when <t>
       is cleared; don't force /attack off in ASSIST else branch (caused loop
       blocking all combat and //facing in ASSIST mode)
v3.08 - FIX ASSIST facing: add dedicated //facing f loop in status==1 without
       JA lockout (face_combat() was blocked by frequent ability use)
v3.07 - FIX cant-target blacklist duration: 15s -> 10s
v3.06 - FIX cursor on blacklisted mobs: /targetoff immediately in final gate
       else branch and after spin /targetbnpc lands on filtered mob
v3.05 - FIX submerged/untargetable mobs: add mob.valid_target check to all
       scan paths so underwater mobs (Al'Taieu etc.) are skipped rather than
       attempted and blacklisted; they re-enter the scan when they surface
v3.04 - ADD user mob_blacklist: permanent name-based pull exclusion; rename
       automated cant_see_blacklist -> cant_target_ids to avoid confusion
v3.03 - PULL: face next mob attacking player immediately when current mob dies
v3.02 - FIX cant-see unblacklist: also unblacklist when mob's target_index ==
       player.index (mob is aggro'd on us, must be interactable)
v3.01 - FIX cant-see blacklist: reduce duration 30s -> 15s
v3.00 - STABILITY: pcall on chunk+action, nil guards, zone/login/logout resets,
       cant_see pruning, leader-change debounce in call_trusts
       SPEED: /attack on before pull cmd; settle 0.3->0.1s; 3.5->1.0s post-engage
v2.99 - FIX ASSIST mode: //facing f + 0.3s before /attack on at engage
v2.98 - FIX purple mob pull: hoist pull_party_ids before aggro scan; add claim_id +
       is_purple_excluded filter to aggro, melee-cap, proximity, spin scans and final gate
v2.97 - FIX pull range: re-check mob distance right before pull command fires;
       abort + /targetoff + re-scan if mob moved out of range during face/sleep delays
v2.96 - FIX stale target ID: proximity scan now detects when same mob is selected
       3x in 12s without engaging and blacklists it for 10s; clears on engage
v2.95 - FIX purple escape missing: claim_id in Windower lags ~1-2s behind
        the game's actual claim state. Added "already claimed" detection in
        the 0x017 packet handler — fires the instant the game sends the msg,
        immediately does /attack off + /targetoff and sets purple_limbo_until.
        The main loop purple_from_packet flag suppresses combat that same tick.
v2.94 - FIX purple-mob escape spam: added purple_limbo_until timer. When no
        replacement mob is found after disengaging a purple mob, the addon now
        holds /attack off for 15s instead of re-firing the escape every 2-3s
        while the purple mob keeps auto-retargeting the player (confirmed by log
        showing 8 escape cycles on Azi Dahaka over 47s).
v2.94 - Cant-see blacklist: if "Unable to see" fires 3+ times on the same mob
        within 8s (wall-clipped, geometry issue, or stuck mob), that mob ID is
        blacklisted for 10s and skipped by all scan paths. Debug msg fires on
        blacklist. Elevation (mob.z) filter was also added but removed — mob.z
        is unreliable in get_mob_array() for this use case.
v2.93 - Added purple_escape_exclusions list (just after job_config).
        Mobs on the list skip the purple-escape disengage check so shared
        open-world content (Domain Invasion, NMs, etc.) can still be fought
        even when another group's claim_id appears on the mob.
v2.92 - FIX Provoke re-pull: recast check used (nil or -1) ~= 0, so when
        Windower omits a ready ability from the recast table (nil = ready),
        Provoke was incorrectly skipped and /ra fired instead. Fixed in both
        try_provoke_pull and use_provoke_for_hate. Also added max-range guard
        (PROVOKE_PULL_RANGE) to use_provoke_for_hate so Provoke isn't wasted
        when the mob is beyond 17.8y.
v2.91 - FIX purple-mob escape: after /attack off + /targetoff, FFXI keeps
        status==1 indefinitely so the loop spun with no valid target. Now
        immediately scans for a whitelisted unclaimed replacement mob and
        switches to it. Falls back to waiting if none is in range.
v2.90 - Purple-mob escape: if current target's claim_id belongs to another
        party, fire /attack off + /targetoff and re-enter the pull scan.
v2.89 - FIX PullNext mobs_in_melee: excluded purple mobs (other parties) and
        non-whitelisted mobs from the nearby-mob cap count. They were silently
        blocking all low-HP 2nd pulls in busy camps.
v2.88 - FIX whitelist: added check to final target gate and melee cap scan;
        mobs entering via /targetbnpc fallback or proximity to player could
        bypass whitelist and get pulled. Now enforced at every target path.
v2.87 - Added mob_whitelist: only mobs whose name appears in the list will be
        pulled or engaged. Empty list = pull everything (original behavior).
        Whitelist is checked in all 4 scan paths: aggro, proximity, spin, PullNext.
v2.86 - FIX dia pull: skip projectile re-pull during combat for 'dia' method.
        Mage jobs fight at range; firing /ma dia every tick while mob was
        outside melee range blocked run_combat_chain() for 2+ seconds per
        loop and spammed recast errors. Provoke (WAR sub) still fires.
v2.85 - Raised PLAYER_MELEE_RADIUS from 6y to 10y in PullNext_OnLowHP melee cap
        check. Flying/moving mobs (e.g. Apex Bats) that drift slightly outside the
        old 6y radius were not being counted, allowing PullNext to chain-pull extra
        mobs and cause multi-bat pile-ups.
v2.84 - Added per-WS min_tp attribute to ws_list entries. When set, the WS will
        not fire until player TP reaches that threshold. Omitting min_tp retains
        the existing 1000 TP floor behavior. Fires a debug message when blocked.
v2.83 - (previous stable release)
v2.82 - Fix: use_weapon_skill() always returned false due to checking p_ws.hpp
        (nil on get_player() objects) instead of p_ws.vitals.hp. WSs never fired.
v2.81 - Added WS BLOCKED diagnostic messages at every exit point in use_weapon_skill().
v2.80 - Clear ws_sc_locked when fight ends so lock never bleeds into next mob.
v2.79 - Hoisted my_id/pull_party_ids scoping fixes; melee cap; two-pass scan.
v2.78 - Fixed ordering: declare current_ws before TP check.
v2.77 - Added player HP guard before WS fire.
v3.99 - Blacklist leak fix + pull-in timeout + closest-priority targeting.
        (1) mob_blacklist IDs (e.g. 17584150) were still getting the cursor. Two
            game-native targeting commands bypassed every blacklist check:
            '/target "<name>"' in the aggro path (targets ANY mob with that
            name -- the blacklisted Death Jacket over the cliff), and
            '/targetbnpc' when nothing was in pull range. Both removed; the aggro
            path now targets by ID with set_target(). set_target() itself also
            refuses mob_blacklist and temporarily blacklisted mobs (TARGET-SKIP).
            The final gate logs 'Cursor on blacklisted mob ...' if one slips in.
        (2) Pull-in timeout: a chosen mob within pull range has PULL_IN_TIMEOUT
            (10s) to reach melee range, take a swing, or be fighting a party
            member. The clock restarts while it is targeting the party and still
            walking closer. Otherwise PULL-TIMEOUT: blacklisted PULL_IN_BLACKLIST
            (10s, never lifted early), /attack off if engaged, /targetoff, and
            the next tick picks the closest mob again.
        (3) Priority scan picks the CLOSEST of: mobs targeting you or a party
            member/Trust, mobs your party already claimed, and any mob already
            in your melee range (was: first match in array order). Fresh mobs
            are still chosen nearest-first after that.
v3.98 - Long-run stability review (24-48h unattended runs). No combat logic changed.
        (1) Watchdog: a Lua runtime error kills the main-loop coroutine but left
            auto_attack = true, so the addon sat idle and //aa pull answered
            "Already running" until a reload. The loop now stamps a heartbeat
            each tick; a 'prerender' check (every 5s) restarts it after
            AA_WATCHDOG_STALL (120s) of silence, max 5 restarts per 30 min, then
            stops with a red message. //aa pull / assist also restart a dead loop.
        (2) Loop generation token: //aa stop then a quick //aa pull (or any
            restart) could leave the old loop sleeping inside coroutine.sleep()
            and wake up next to the new one -- two loops, doubled commands. The
            old loop now exits at its next check. The 30s "player unavailable"
            retry also exits early when stopped/superseded and no longer clears
            auto_attack for a newer loop.
        (3) Cached resource lookups (res_with): res.items:with() scanned ~28k
            items every combat tick per ring; spells / job abilities likewise per
            config entry. Now looked up once per name.
        (4) incoming chunk: returns early for packet IDs other than
            0x017/0x029/0x067/0x068 before allocating the pcall closure (was one
            closure per packet, hundreds per second of GC churn).
        (5) prune_blacklists(): between fights also drops stale cant-see hit
            counters (mobs that never reached CANT_SEE_LIMIT were never removed).
        (6) Nil guards: ws_list entry missing name / min_time / uses; aggro scan
            mob.hpp; heal_party player MP.
v3.97 - Provoke is reserved for PULLING mobs outside melee range.
        2026-10-10 log: 36 of 170 PROVOKE-PULLs fired on mobs at 1-2y. Cause:
        engaged_pull_logic() treated 4s with no melee round as "not in contact"
        and pulled (Provoke, or the provoke pull_command -> "Unable to use job
        ability"). DRG's ~5s delay plus Jump/High Jump gaps tripped it constantly.
        (1) Mob in melee range (3.0 + model_size): never Provoke / pull_command.
            No contact for MELEE_HIT_WAIT (4s) -> MELEE-CHECK: face the mob only.
        (2) No contact for MELEE_STALL_LIMIT (15s) in melee range -> MELEE-STALL:
            blacklist + disengage (unreachable / floating mob safety net).
        (3) The game's "<mob> is out of range." still allows a pull (Provoke OK):
            the mob is really out of reach.
        (4) Our JAs on the mob (action cat 6 / 14, e.g. Jump) now count as
            contact, except Provoke itself.
v3.96 - Crash hardening for built-in targeting + spin pull removed.
        2026-10-10 21:48:02: pol.exe crashed in FFXiMain.dll (0xc0000005, offset
        0x00076a75, first in weeks) ~2 min after v3.95 went live, the instant the
        Goblin Leecher died, a treasure casket spawned and the dead cursor cleared.
        (1) set_target() re-reads the mob by ID and skips it if it is dead,
            untargetable, not a monster (spawn_type 16) or beyond 50y.
        (2) New quiet window: TARGET_QUIET_WINDOW (1.0s) after any defeat message
            (0x029 msg 6/20/97/113/406/605/646), a treasure casket appearing
            ('incoming text') or a dead cursor, set_target() skips. Callers
            already retry next tick.
        (3) Every call logs TARGET-SET / TARGET-SKIP / TARGET-QUIET so the last
            targeting step before any future crash shows in the log.
            Whitelist cursor clears whitelist_cursor_id on a skip so it retries.
        (4) SET_TARGET_VIA_ADDON (default false): true sends 'lua c settarget'
            instead, the pre-v3.95 behaviour (load SetTarget for it).
        (5) Spin pull (//aa pull spin) removed: the spin loop, try_spin and the
            header/help/README entries. '//aa pull spin' now starts a normal pull.
v3.95 - Built-in targeting; the SetTarget addon is no longer required.
        New set_target(id) injects the same incoming 0x058 packet SetTarget sends.
        All 8 'lua c settarget <id>' calls replaced (proximity, melee cap,
        whitelist, spin, purple rescue, PullNext forward/back, final pull).
        Leaving SetTarget loaded is harmless. Header/README updated.
v3.94a - DRG: Spirit Surge is now an emergency 2-hour (hpp_below=35) instead of
         firing as an opener on the first mob (2026-10-10 log: it fired on trash at
         20:50:03 and 20:53:36; the addon reload resets its min_time timer).
v3.94 - Pet jobs: new DRG job_config (full) plus BST / SMN / PUP starter blocks.
        - New per-job `pet` block, run by new pet_logic(): re-summons the pet when
          it's gone (summon list tried in order: Call Wyvern / Call Beast, Bestial
          Loyalty / avatar spell via /ma / Activate, Deus Ex Automata), sends it at
          your target on engage or target switch (engage = 'Fight' / 'Assault' /
          'Deploy'), and calls it back when you're not engaged (retreat = 'Heel' /
          'Retreat' / 'Retrieve'). summon_idle, summon_block_buffs (DRG: no Call
          Wyvern during Spirit Surge), summon/engage/retreat_retry options.
          Runs between fights (status 0, after call_trusts) and in
          run_combat_chain() before use_job_abilities().
        - use_job_abilities(): pet commands, Ready moves and Blood Pacts now send
          with /pet (from the resource prefix) instead of /ja -- they never fired before.
        - New optional abilities fields: pet, pet_name, pet_hpp_below/above,
          pet_tp_min, pet_engaged, tp_max, hpp_above/below, mpp_above, max_recast
          (charge abilities), buff_stack (with buff_id), need_buff.
        - Pet TP / HP / target from the 0x067/0x068 pet status packets (pet_state).
        - New //aa pet command shows pet HP / TP / status / target.
        (1) Not engaged: once the target is within ENGAGE_RANGE (29.0y), /attack on
            ONLY (draw weapons) + wait_for_engage(). No Provoke or /ra at this stage.
            Main and spin paths. The v3.85 Provoke hold moved to stage 2.
        (2) Engaged: new engaged_pull_logic() (replaces the old re-pull block and the
            use_provoke_for_hate() call in run_combat_chain):
            - Mob in melee range (3.0 + model_size): no pull. Waits MELEE_HIT_WAIT
              (4s) for a swing; pulls only if none lands, or the game sends
              "<mob> is out of range." (msg 4/154, new 0x029 check).
            - Mob outside melee range: Provoke if within 17.8y and ready (confirmed);
              hold while Provoke is ready and the mob is 17.8y-pull_dist (6s max);
              else pull_command within pull_dist. Then waits PULL_APPROACH_WAIT (6s)
              for the mob to walk in before re-pulling.
            - Any melee round / WS on the mob (new melee_swing tracking in the action
              event) resets the re-pull counter. REPULL_LIMIT blacklist unchanged.
            is_target_valid() now uses max(pull_dist, ENGAGE_RANGE) (+5 grace) so a
            mob engaged at 29y isn't dropped (provoke method's pull_dist is 17.8).
            - Dia method: first pull only (v2.86 rule kept).
        (3) engage_at_melee_range() (v3.92) is no longer called.
v3.92 - Engage at max melee range. Pulls (Provoke / /ra / Dia) now fire while
        UNENGAGED -- Provoke landed 3/3 that way in v3.87. New
        engage_at_melee_range(): faces the mob every 1s while it approaches and
        sends /attack on the moment it is within melee range (3.0 + model_size),
        logging 'ATTACKING >>>> (melee edge Xy / Yy)'. Falls back to /attack on
        after APPROACH_WAIT_MAX (8s). Replaces the v3.24 5x1s facing loop in the
        main and spin pull paths. wait_for_engage() (v3.91) is no longer called
        by the pull paths.
v3.91 - v3.90 REVERTED: PROVOKE_PULL_RANGE back to 17.8 (and provoke pull_dist).
        The "out of range" lines were melee swings after /attack on, not Provoke.
        Real pattern in the 2026-10-10 log: Provoke-before-/attack-on (v3.87) 3/3
        landed; Provoke 0.5-0.7s after /attack on (v3.88/3.89) all dropped.
        New wait_for_engage(): after /attack on, poll until player.status == 1
        (engaged, max ENGAGE_WAIT_MAX 3.0s), then PULL_FOLLOWUP_DELAY (now a 0.2s
        settle), then Provoke -> pull_command fallback. Logs 'ENGAGED after Xs'.
v3.90 - (reverted in v3.91) PROVOKE-FAIL was a RANGE problem, not timing. The 2026-10-10 log shows
        Provoke landing at 4.9 / 6.9 / 7.6 / 8.0y, while every try at 9.5, 10.8,
        10.9, 12.7, 16.2, 17.3y got "The Death Jacket is out of range."
        PROVOKE_PULL_RANGE 17.8 -> 9.0 (also pull_dist for pull.method='provoke').
        Pull hold (v3.85) now waits for the mob to reach 9.0y before Provoking,
        else /ra after the 6s timeout. Hate re-grab uses the same limit.
v3.89 - PULL_FOLLOWUP_DELAY 0.5s -> 0.7s: Provoke at 0.5s after /attack on was still
        being dropped (PROVOKE-FAIL in game).
v3.88 - Pull order back to /attack on FIRST (v3.87's Provoke-first order made the
        engage land late). Main + spin pull paths: /attack on -> PULL_FOLLOWUP_DELAY
        (new tunable, default 0.5s; v3.86 used 0.15s) -> Provoke (confirmed via
        provoke_fire_confirmed) -> pull_command (/ra etc.) if Provoke isn't seen.
        Lower the delay for faster pulls; if PROVOKE-FAIL shows up often, raise it.
v3.87 - Provoke confirm-and-fallback (Shadowhammer: chat showed PROVOKE-PULL but
        Provoke never went off).
        (1) Pull paths (main + spin) now send Provoke BEFORE /attack on. It used to
            go 0.15s after /attack on, mid-engage, where the game silently drops JAs.
        (2) New provoke_fire_confirmed(): sends Provoke, then waits up to 2s
            (PROVOKE_CONFIRM_WAIT) for our own category-6 action packet with
            Provoke's ID. Logs 'PROVOKE-OK' or 'PROVOKE-FAIL'.
        (3) On a miss the 30s Provoke lock is cut to ~3s (PROVOKE_FAIL_RETRY) and
            the caller falls back: pull paths fire /attack on + pull_command (/ra,
            Dia...), PullNext fires pull_command, hate re-grab falls through to the
            normal re-pull. Previously a dropped Provoke meant no pull at all and
            Provoke locked for 30s.
        (4) try_provoke_pull() and use_provoke_for_hate() both use the new helper.
v3.86 - Mob ID blacklist.
        (1) mob_blacklist now accepts numeric mob IDs alongside names, e.g.
            17584150 blocks just that one mob while others with the same name
            are still pulled. Name entries still block every mob of that name.
        (2) is_mob_name_blacklisted(name, id) checks both; all 10 scan/target
            call sites now pass the mob's ID.
        (3) New //aa id: prints the current target's name, ID and index
            (flags [BLACKLISTED] if it already is).
v3.85 - Provoke-pull fix (Shadowhammer THF/WAR, 2026-10-10: only 8 of 22 pulls used
        Provoke). Nothing was disabled -- try_provoke_pull() only fires inside
        17.8y, but the /ra pull range is 24.9y, so the pull fired with /ra the
        moment a mob crossed 24.9y (you running toward it), before it could ever
        reach Provoke range. Every Death Jacket pulled at 23-24.7y got /ra
        ("out of range"), then re-pull /ra, then blacklisted.
        (1) New provoke_pull_ready() (WAR main/sub, recast ready, shared 30s lock);
            try_provoke_pull() now uses it.
        (2) New provoke_pull_hold(): in PULL mode, when Provoke is ready and the
            mob is inside pull_dist but beyond 17.8y, the pull is held (no
            /attack on, no /ra) and the cursor stays on the mob. Logs
            'PROVOKE-WAIT: ...'. Once the mob is within 17.8y Provoke pulls it.
        (3) Hold times out after provoke_hold_state.wait (6s) on the same mob,
            then the normal pull_command (/ra, Dia) fires. If Provoke is on
            recast there is no hold at all. pull.method = 'provoke' is unchanged.
        (4) Applied to the main pull path and the spin-scan pull path. Held ticks
            don't count toward the stale-pull blacklist (3 selections / 12s).
v3.84 - Built-in facing; the Facing addon is no longer required.
        Root cause of the 2026-10-09 death turned out to be the Facing addon not
        being loaded: every '//facing f' the script sent did nothing, so Shadowhammer
        stood facing away from the Death Jacket for 71 minutes.
        (1) New face(dir) helper (after cmd()) calls windower.ffxi.turn() directly,
            same math as Facing v0.3.1: 'f' = toward <st>/<t>, 'left'/'right' = 45
            degree step, n/ne/e/se/s/sw/w/nw (or full words) = compass heading.
        (2) All 17 cmd('input //facing f') + 1 send_command('input //facing f')
            calls, plus the fight_subcmd and spin left/right turns, now use face().
        (3) With cmd_mode = true each turn logs '[CMD] face <dir> (<radians>)'.
        (4) Header/README: Facing removed from requirements. Leaving Facing loaded
            is harmless (its on-screen angle display still works).
v3.83 - Unreachable-mob death fix (Shadowhammer THF died 2026-10-09 18:57, Crawlers'
        Nest: engaged on a Death Jacket 3y away for 71 min, 1,106 Evisceration
        attempts all "You cannot see", 0 damage dealt, no heals, slowly killed).
        (1) Cant-see detection now reads action-message packet 0x029 (msg 5 "Unable
            to see", 217/219 "You cannot see"). The old check only looked at chat
            packet 0x017, which never carries these, so the 3-strikes-in-8s blacklist
            and facing_emergency() had never fired. Logic moved to handle_cant_see();
            the 0x017 path still calls it.
        (2) Escalating unreachable blacklist: 10s -> 30s -> 120s -> 300s per repeat
            on the same mob ID (cant_see_strikes). From strike 2 the v3.02 "lift early
            if it targets you / moves into range" rule no longer applies.
        (3) Aggro scan and post-kill "facing next mob" now skip blacklisted mobs
            (they used to lock straight back onto an unreachable mob hitting you).
        (4) Stuck-engage watchdog (PULL mode): in melee range with no melee round,
            WS, ranged attack or offensive spell from you for STUCK_TIMEOUT (30s)
            -> blacklist (escalating) + /attack off + /targetoff. Paused while you
            are asleep, stunned, petrified or terrorized.
        (5) Low-HP stop: HP% <= LOW_HP_STOP_PCT (25) with no HP increase for
            LOW_HP_NO_HEAL_SECS (30s) -> AutoAttack stops, /attack off, red chat
            warning. Set LOW_HP_STOP = false to disable.
v3.82 - Public-release housekeeping (no gameplay logic changed):
        (1) Added the standard _addon block (name, author, version, commands).
            _addon.commands = {'autoattack','aa'} means //aa assist|pull|stop
            now work directly -- no more needing an "alias aa lua c autoattack"
            line in init.txt.
        (2) Added a proper file header (description, author, version,
            dependencies, command list, ToS note).
        (3) Command parsing now lowercases the command, so //aa ASSIST /
            //aa Pull work the same as lowercase.
        (4) //aa with no argument, or an unrecognized command, now prints a
            one-line usage reminder instead of doing nothing silently.
        (5) The load message and usage line now read the version from
            _addon.version instead of a hardcoded string, so they can't
            drift out of sync with the changelog again.
v3.81 - Code-quality audit fixes (no behavior change for WAR/RDM/NIN/THF/COR/DRK/WHM/BLM):
        (1) SAM trusts broken: duplicate 'trust_group' key in trusts table; second value
            'hastecap5' overwrote first 'mlt' — group doesn't exist, trusts never fired.
            Removed the duplicate line; effective group is now 'mlt'.
        (2) SAM hastecap group had duplicate Qultada; replaced with Ulmia.
        (3) "Kumhau " trailing space in purple_escape_exclusions: mob_name:lower() == "kumhau"
            never matched "kumhau " in the set — Kumhau would not be excluded from purple
            escape. Fixed to "Kumhau".
        (4) Four empty-string entries in purple_escape_exclusions removed (harmless but sloppy).
        (5) use_item_food(): local variable 'job_config' shadowed the module-level job_config
            table. Renamed to 'item_cfg' and switched to use current_config (already resolved).
        (6) File-scope skip_combat_this_tick comment updated to note it is shadowed by the
            per-tick local re-declaration inside status==1 block.
v3.80 - Step 3: blacklist dead-cursor mob immediately (5s) before /targetoff.
        Without blacklisting, stale API hpp caused the scan to re-select the same
        dead mob every tick; /targetoff fired but stale-pull never incremented
        (it lives inside the pull path, short-circuited by step 3's dead-cursor check).
        Blacklisting forces the scan to pick a different live mob next tick.
v3.79 - Revert step 3 and melee path to v3.53 approach (removes broken get_mob_by_id
        substitution added in v3.71). The substitution set target to a mob that wasn't
        the cursor target, causing every pull path check (t_check1, /attack on) to see
        a dead cursor. Step 3 is now a pure cursor read; if cursor is on a dead mob,
        /targetoff clears it immediately (fixes the old 40s corpse-cursor delay without
        the substitution hack). Melee path reverts to simple /attack on — step 3 only
        reaches melee branch when target.hpp > 0, meaning cursor IS on a live mob.
v3.78 - Fix melee /attack on skipping on live mobs due to stale get_mob_by_target.
        get_mob_by_id is a direct synchronous memory read and is always current;
        use it as the alive fallback if the cursor read is stale after settarget.
        Removed /targetoff from melee path (it was racing settarget and cancelling
        it); moved /targetoff to PULL ABORTED where mob is confirmed dead.
        Sleep extended to 1.0s to give settarget more time to resolve.
v3.77 - Fix dead-corpse re-selection loop and melee settarget queue backlog.
        (1) PULL ABORTED (target died before pull): immediately blacklist the mob for
        5s instead of waiting for 3 stale-pull retries. Prevents 3+ second dead-mob
        retry cycles when Windower's API shows stale hpp > 0 right after a kill.
        (2) Melee path: /targetoff first to flush queued settarget commands from
        previous failed pull cycles; then settarget(id) + 0.8s sleep (was 0.5s);
        if cursor still invalid but get_mob_by_id confirms mob alive, retry once.
v3.76 - Reverted melee-range attack path to v3.53 settarget-by-ID approach.
        Re-call lua c settarget pull_candidate.id, sleep 0.5s to let it resolve
        (settarget is async), verify target is alive, then /attack on. This mirrors
        the ranged pull path's t_check1 re-verify and was confirmed working in v3.53.
v3.75 - Replaced /target "name" (unreliable for mobs) with /targetoff + /targetbnpc
        in the melee-range attack path. /targetbnpc is game-native and always picks
        the nearest enemy. Verify the result is a live mob before /attack on fires.
v3.74 - Fixed melee-range /attack on not engaging: game cursor was still on the
        dead corpse (settarget is async, hasn't resolved). Added /target "name"
        + 0.5s sleep before /attack on in the melee path, matching the re-lock
        pattern already used in the ranged pull path (t_check1 after sleep(0.5)).
v3.73 - Fixed v3.71/v3.72 fallback: pull_candidate was declared inside the
        else/no-aggro Lua block so it went out of scope before step 3 ran —
        the fallback was always dead code (pull_candidate was nil at use site).
        Moved declaration to the same level as `local target = nil` so it
        survives into the get_mob_by_id fallback at step 3.
v3.72 - Fixed v3.71 fallback: `not target` never fired because get_mob_by_target
        returns the dead corpse (hpp=0), not nil. The fallback now also triggers
        when the cursor target is dead OR targets a different mob than pull_candidate.
v3.71 - Fixed 40+ second delay pulling non-aggro mobs within melee range.
        Root cause: proximity scan calls lua c settarget (async). The 0.5s
        sleep after was intended to let it resolve, but get_mob_by_target('t')
        still returned nil when settarget hadn't fully resolved, causing the
        final gate to fail silently every tick. Fix: melee cap and proximity
        scan now set pull_candidate to the selected mob. If get_mob_by_target
        returns nil, get_mob_by_id(pull_candidate.id) is used as fallback —
        the mob was already fully validated in the scan so this is safe.
v3.70 - Fixed melee cap triggering on non-aggro unclaimed mobs. The cap now
        only counts party-claimed mobs (pull_party_ids[claim_id]). Previously
        unclaimed mobs (claim_id==0) within 6y triggered the cap, causing an
        infinite settarget loop where target stayed nil each tick (settarget
        fires async, final gate runs same tick before it resolves). With the
        fix, unclaimed/non-aggro mobs fall through to the proximity scan and
        are pulled normally.
v3.69 - use_magic() now accepts a buff_only flag. When called outside battle
        (heal_buff_outside_battle=true), debuff and damage entries are skipped
        so they don't block heal/buff entries later in the list from firing.
        This fixes WHM Cura and similar heal-type spells being skipped when a
        debuff entry appeared earlier in the magic list.
v3.68 - Added heal_buff_outside_battle toggle. When true, heal_party() and
        use_magic() fire in the status==0 (out-of-combat) branch so mages
        keep the party healed and buffed between pulls.
v3.67 - Fixed domain_invasion trust override: 'dragon' → 'dragons' to match job_config group name.
v3.66 - Added 0.4s delay before /attack on in melee-range engagement path.
        The ranged pull path already had a 0.5s target-lock wait; melee path
        had none, causing /attack on to fire before settarget fully resolved.
v3.65 - Startup message now includes mob whitelist when active: shows mob names
        from mob_whitelist as "Hunting <name>, <name>..." when neither DI nor
        elemental_farming toggle is on but mob_whitelist_set is non-empty.
v3.64 - When domain_invasion.toggle == "true", call_trusts() overrides the
        job's default trust_group and uses 'dragon' group instead.
v3.63 - Startup message in PULL mode now appends farming context based on
        domain_invasion/elemental_farming toggles: "DI Farming", "Elemental
        Farming", or both. ASSIST mode unchanged.
v3.62 - Renamed master_config to job_config throughout (all 12 references).
v3.61 - Added master_pull_method top-level config. When type is non-empty,
        overrides cfg.pull.method, PullNext_OnLowHP, LowHPPrcnt, PullNextMax
        for all jobs. Set type='' to fall back to per-job job_config pull.
        Also fixed trailing comma syntax error on master_pull_method declaration.
v3.60 - Fixed bare [AoE]/[Other] key syntax in THF ws_list.
v3.59 - Fixed bare [Normal]/[Odin] key syntax in all remaining job ws_lists
        (THF, SAM, DRK, and others). All sub-table keys now use ["Normal"] etc.
v3.58 - Added ws_mode config {type, lockout}. ws_list for WAR now uses named
        sub-tables ["Normal"], ["AoE"], ["Odin"], ["Savage_Blade"]. use_weapon_skill()
        resolves active list from ws_mode.type (falls back to flat list for jobs
        not yet converted). ws_index resets when type changes. ws_mode.lockout=="false"
        disables SC chain locking entirely (ws_sc_locked stays false).
        Also fixed [AoE]/[Normal]/[Odin]/[Savage_Blade] key syntax (missing quotes).
v3.57 - Moved whitelist/blacklist set-building block to after job_config.
v3.56 - Added elemental_farming config block (same toggle/moblist pattern as
        domain_invasion). Both configs can be active simultaneously; their
        moblists are merged into mob_whitelist_set. Updated whitelist-building
        logic to use new field names (toggle/moblist) and handle both blocks.
v3.55 - Added domain_invasion config block. When di_toggle == "true", the
        di_moblist overrides mob_whitelist for all targeting/pull decisions.
        Set di_toggle = "false" to revert to normal mob_whitelist behavior.
        Also fixed missing comma in di_toggle line (Lua syntax).
v3.54 - Load event now prints current zone name and ID via debug_msg.
        Uses windower.ffxi.get_info().zone + res.zones[id].english.
v3.53 - Whitelist cursor: only settarget once per mob, not every tick.
        Previously settarget fired on the same out-of-range whitelist mob
        every loop tick (~1s), overriding any manual targeting the player
        did while running toward it. Added whitelist_cursor_id tracking:
        settarget only fires when the nearest whitelisted mob changes to a
        different ID. If it's the same mob as last tick, the call is skipped
        so the player can freely re-target while navigating.
        whitelist_cursor_id is reset to 0 when the proximity scan fires
        (mob entered pull range) so the cursor re-locks correctly the next
        time the player is between mobs.
v3.52 - Revert v3.51 three-zone whitelist approach. Restore v3.50 two-zone
        behavior: cursor only when dist > pull_dist; full pull + /attack when
        dist <= pull_dist. v3.51 intermediate /attack on at 30y removed.
v3.51 - Whitelist: three-zone approach for cursor / attack / pull.
        Previously cursor was placed on the out-of-range mob but no other
        action fired until pull_dist was reached. Now:
          >30y (WHITELIST_ATTACK_RANGE)  — cursor only; character does nothing
          ≤30y and >pull_dist            — /attack on so the character begins
                                           tracking and facing the mob, but the
                                           pull command is still withheld
          ≤pull_dist                     — pull fires as normal (face + /attack +
                                           pull command, existing behaviour)
        WHITELIST_ATTACK_RANGE is a local constant (30y) just above the
        whitelist "too far" block — easy to adjust without touching config.
v3.50 - Whitelist: cursor tracks closest whitelisted mob even when out of pull range.
        When the whitelist is active and no mob is within pull_dist, the script now
        scans the full mob array (any distance) for the closest valid whitelisted mob
        and places the cursor on it using settarget. No pull or /attack fires — the
        final gate's distance check prevents that. The player can see the target on
        their cursor and run toward it; pulling starts automatically once it enters
        pull_dist. Two code paths updated:
          1. "Nothing in pull range" fallback: instead of silently doing nothing,
             do a full-distance whitelist scan and settarget the nearest result.
          2. "Target too far" branch in final gate: when whitelist is active, don't
             /targetoff or start spinning — leave the cursor on the out-of-range mob
             and log its distance ("run toward it"). Non-whitelisted sessions still
             clear the cursor and spin as before.
v3.49 - Whitelist: cursor never lands on non-whitelisted mobs.
        Two targeting paths bypassed the whitelist check before placing the
        in-game cursor on a mob:
          1. Proximity-scan fallback (/targetbnpc when scan found nothing):
             When whitelist is active the scan already checked every mob in
             range; running /targetbnpc would only find non-whitelisted mobs
             that the final gate immediately clears — cursor still briefly
             visible. Fix: skip /targetbnpc entirely when mob_whitelist_set
             is non-empty. Whitelist-empty sessions are unaffected.
          2. Spin loop (/targetbnpc + 0.3-0.9s sleep then whitelist check):
             The cursor sat on a non-whitelisted mob for up to a second each
             spin step before being cleared. Fix: when whitelist is active,
             replace /targetbnpc in the spin with a get_mob_array() scan that
             applies all whitelist/blacklist/distance filters, then uses
             settarget on the closest valid mob directly — cursor never
             touches a non-whitelisted mob. /targetbnpc is still used during
             spin when whitelist is empty (no change for all-mob sessions).
v3.48 - Fix buff-spell spam and Shadowhammer missing Haste II.
        Root cause (from Shadowhammer's chat log analysis):
          The timer is set when /ma is SENT, not when the spell actually executes.
          When Savage Blade (or any WS) is in the action queue, the game delays the
          buff spell by 2-6s. By the time min_time=5 elapses, the spell hasn't even
          finished casting yet — 0x076 hasn't arrived, has_buff=false — so the
          resolution loop re-selects the same member and queues a second cast.
          This creates the double/triple Haste II spam on Mythrandiir seen in the
          log (casts 10-12s apart) and blocks Shadowhammer from ever being reached
          because Mythrandiir perpetually wins the p0→p5 slot scan.
        Fix: added post-cast buff verification after every buff_party/buff cast.
          After the normal cast sleep, sleep an additional 5s (covers WS anim lock
          + spell execution + 0x076 round-trip), then call get_member_buffs() on
          the target to confirm the buff actually landed.
          • Confirmed  → leave the timer; rotation continues normally.
          • Not found  → set timer for a 30s retry (instead of full buff_duration)
                        and log BUFF VERIFY: … NOT confirmed. The 30s back-off also
                        unblocks the p0→p5 scan so other members (Shadowhammer) get
                        their turn on the next cycle.
          • Data nil   → trust or untracked slot; can't verify — timer unchanged.
        The extra 5s sleep is added only when a buff spell actually fires, so it
        does not affect debuff, damage, or non-buff-verified spell paths.
v3.47 - Fix v3.46 regression: local player (Scracheebrat) receiving Haste II / Refresh III
        even when buff is already active.
        Root cause: dur_expired (a stale-0x076-data safety net) was also firing for the
        local player. But the local player's buff data comes from get_player().buffs which
        is ALWAYS accurate — the safety net must never apply to self. On a fresh session
        t_last=0 made dur_expired=true for every member including the local player, causing
        Section 4 to suppress skip_spell for self and cast over an already-active buff.
        Fix: Added is_self guard in all three dur_expired locations:
          1. Resolution loop — explicit targets list (is_self_t)
          2. Resolution loop — buff_party / buff_party_mages (is_self_m)
          3. Section 4 buff_id / buff_any check (is_self_s4)
        When effective_target or member.name matches player.name, dur_expired is forced
        false so the accurate local buff data always takes precedence.
v3.46 - Fix v3.45 regression: Haste II / Refresh III never casting after script reload.
        Root cause: v3.45 added dur_expired to the resolution loop (correctly selects
        a target when buff_duration has elapsed, even if buff data shows it active).
        But Section 4's buff_id check was unchanged — it still set skip_spell=true
        whenever the buff appeared active in the party data. Result: resolution loop
        selects p0 (dur_expired=true, t_last=0 on fresh session) → Section 4 blocks
        the cast (buff IS present) → p0 holds the slot every tick → no other member
        is ever checked → no buffs are ever cast.
        Fix: Section 4's buff_id check now also computes dur_expired_s4. If the timer
        has elapsed (or it's a fresh session with t_last=0), don't set skip_spell even
        when buff data shows the buff active. On reload this triggers one safety recast
        per member that already has the buff, then the rotation returns to normal.
        The buff_any list check received the same guard.
v3.45 - Three fixes for debuffs, cast timing, and Haste II not recasting on real PCs.
        Fix 1: Debuff timers now cleared on new mob.
          magic_last_used was not reset for debuff entries when a new mob was detected
          (magic_use_tracker was cleared, but not magic_last_used). This blocked all
          debuffs on subsequent mobs for the full min_time window (120-300s), causing
          only whichever debuff happened to have the oldest timer to fire.
          Fix: On new-mob detection, iterate current_config.magic and nil out
          magic_last_used keys for type='debuff' entries only. Buff timers are
          intentionally preserved (buffs persist across mobs).
        Fix 2: Cast timing formula corrected.
          Previous: (spell_data.cast_time or 0) / 60 + 2  <-- WRONG unit assumption
          cast_time in res.spells is in seconds, not 1/60s ticks. Dividing by 60
          reduced the sleep to ~2s (just the buffer), not enough for longer spells.
          New formula: actual_cast = base × (1 - fast_cast_pct/100); sleep = actual + 1.5s.
          Add magic.fast_cast_pct to RDM (50) and WHM (30) configs. Tune this value
          to match your character's total Fast Cast %. Raise if spells still overlap;
          lower if the loop feels slow. Per-spell override: entry.cast_time = N.
          Applied to all three spell functions: use_magic, use_magic_burst,
          use_weakness_magic.
        Fix 3: Stale buff data on real PC party members (Shadowhammer Haste II).
          Path A (live buff data available) only checked buff_id presence — never
          recasting if the buff appeared active. If the server's 0x076 wear-off packet
          was missed, Windower's party data kept showing the buff as active forever.
          Fix: In both buff resolution loops, add a buff_duration cap to Path A.
          Even if buff data shows the buff active, recast after buff_duration seconds.
          Example: Haste II buff_duration=300 → guaranteed recast every 5 minutes
          even if packet is missed. Works alongside the existing Path B (nil data).
v3.44 - Config-driven auto-cure via new `cure` block in job_config.
        heal_party() now reads current_config.cure instead of hardcoded spell IDs
        and thresholds. Each entry: {name='Cure IV', hpp_threshold=40, min_mp=88}.
        Spells are tried in listed order; first qualifying spell is cast.
        Added `cure` blocks to RDM (Cure IV @40%, Cure III @75%) and
        WHM (Cure V @30%, Cure IV @50%, Cure III @70%) configs.
        Removed temporary BUFF CHK debug_msg lines added in v3.43.
v3.43 - Fix: repeated buff casts when party member already has the buff.
        Root cause: get_party()[slot].buffs is nil for trust party members (server
        does not send 0x076 buff-sync packets for trusts). The resolution loop treated
        nil as "buff missing" and selected the trust every min_time (5s) forever.
        Fix: two-path buff evaluation in the resolution loop:
          A) buff data non-nil → check buff_id presence; use min_time as anti-spam
          B) buff data nil → use buff_duration (default 180s) as the recast gate;
             this is the full-duration fallback when we can't read actual buff state
        Added debug_msg('BUFF CHK: ...') lines in the resolution loop showing buff
        array length, has_buff result, and elapsed time. These help confirm whether
        buff data is actually being read. Once confirmed, they can be removed.
        New config field: buff_duration = N  (seconds). When buff data is unavailable,
        the script won't recast until N seconds have elapsed since the last cast.
        Default: 180. Example: {name='Haste II', type='buff_party', buff_id=33,
        min_time=5, buff_duration=180}
v3.42 - Fix: RDM casting Refresh III on themselves repeatedly.
        Root cause: the FFXI server does NOT send packet 0x076 (party buff update)
        for the local player's own party slot. So party[p0].buffs (or whichever slot
        the RDM occupies) is always nil. get_member_buffs() returned nil, the buff
        check saw "no Refresh on Scracheebrat", and re-cast every min_time (5s).
        Fix: in get_member_buffs(), when t_name matches player_data.name (the local
        character), return player_data.buffs from get_player() directly — this is
        always accurate for self-buffs. The party slot fallback still handles all
        other party members.
v3.41 - Fix three bugs introduced/found after v3.40 deploy:
        1. Config/Comment in magic table was NOT a Lua comment — it was a long
           string expression (positional element at index 1). ipairs() hit it first,
           saw nil .name, and broke immediately, silently skipping ALL spell entries.
           Fixed to correct (proper multi-line comment).
        2. Config: entries had target='buff_party_mages', type='buff' — type keyword
           was in the wrong field. Fixed to type='buff_party_mages', no target field.
        3. buff_party_mages: mp>0 check is not reliable — melees with Master Levels
           or MP gear have a small pool and would incorrectly receive Refresh/Regen.
           Now estimates max MP as floor(mp*100/mpp) when mpp>0. Members with
           estimated max MP below min_mp_pool (default 400) are skipped. 400 filters
           typical melee ML/gear MP (100-350) while including any mage-scale pool.
           Override per-entry: {name='Refresh III', type='buff_party_mages',
           buff_id=43, min_time=5, min_mp_pool=600}.
        4. buff_party / buff_party_mages: added only_names (whitelist) and skip_names
           (blacklist) table filters for explicit per-name control:
             only_names={'Scracheebrat','Joachim'} — buff ONLY these names
             skip_names={'Shadowhammer'}            — buff everyone EXCEPT these
v3.40 - Party buff rotation overhaul in use_magic():
        1. Per-target composite timer key (spell||target) so casting Haste II on
           Mythrandiir no longer blocks the timer for Shadowhammer/Vayne.
        2. Named-target buff check now uses get_party() data (via get_member_buffs()
           helper) instead of target_mob.buffs, which is always nil for other players
           in the Windower mob array. Buff state is now accurately checked.
        3. New 'targets' array on buff entries: list multiple names and the script
           auto-selects the first one who needs the buff each cycle.
        4. New type='buff_party': auto-iterate all party slots (p0-p5), buff the
           first member without the buff. Covers real players AND trusts (both appear
           in party slots and can benefit from Haste/Refresh/Regen).
        5. New type='buff_party_mages': same as buff_party but skips members with
           mp == 0 (non-MP jobs). Use for Refresh/Regen to avoid wasting it on pure
           melee jobs.
v3.39 - Remove DIAG messages (root cause confirmed: settarget addon was not loaded
        on Scracheebrat's client). spawn_type==16 gate kept as permanent safety net.
v3.38 - Add spawn_type==16 guard to final pull gate; DIAG messages for settarget
        failure diagnosis (trust/NPC targeted instead of monster).
v3.36 - Fix stale-pull false blacklist: moved stale_pull_count increment from
        proximity scan to AFTER the final claim_id gate passes. Trust-claimed
        mobs were failing the gate and cycling at ~1s/iter, hitting the 3-select
        limit before Dia ever fired. Now only genuine 'pull fired, no engage'
        situations count toward the blacklist threshold.
v3.35 - Dia pull_dist reduced 21.8 → 20.0. Log showed "out of range" at 21.9y;
        Dia's effective cap is ~20.7y and mob drift during face/sleep delays (~0.65s)
        caused borderline failures. 20.0 gives a reliable buffer.
v3.34 - Purple escape overhaul: rescue scan now runs from all three escape paths
        (packet, limbo, claim_id). Previously packet/limbo paths skipped the scan
        entirely, leaving Shadowhammer idle for the full 15s limbo even with mobs
        in range. Now rescue scan runs every tick during limbo; exits immediately
        when a replacement is found. Packet handler settle window reduced from 15s
        to 2s — main loop sets full 15s only after scan comes up empty. ASSIST
        mode skips rescue scan (follows leader target). /attack off settle sleep
        reduced from 1.0s to 0.5s in the claim_id branch.
v3.33 - Fix PULL command: toggle_auto_attack() was accidentally dropped from the
        pull branch when v3.32 added the debug_msg. Loop never started for //aa pull.
v3.32 - Startup debug messaging: command handler now prints job (main/sub) and
        subcmd when ASSIST or PULL command is received; toggle_auto_attack prints
        mode confirmation when the loop starts, and cleaner already-running msg.
v3.31 - DRK ws_list: scythe WSes only active (Catastrophe, Entropy, Quietus,
        Spiral Hell, Cross Reaper, Guillotine). GS/Sword commented out.
v3.30 - Add ['DRK'] job_config block (cloned from RDM). Full lv99 abilities:
        Blood Weapon (2hr/buff_id=51), Souleater (63), Last Resort (64),
        Diabolic Eye (346), Scarlet Delirium (479), Dark Seal (345),
        Nether Void (439), Weapon Bash (on-target stun). Full WS list for
        Great Sword (Resolution active) and Great Scythe (commented); pull
        method = 'dia' so DRK/WHM uses Dia to pull.
v3.29 - Revert get_spells() guard from v3.28. windower.ffxi.get_spells() proved
        unreliable in the tick loop and caused Dia to fall back to ranged_attack
        even for RDM who definitively has the spell. Removed the check entirely;
        if method='dia' is configured for a job without the spell the game will
        error naturally. Spin path ordering fix and DRK config addition retained.
v3.28 - Dia pull fixes: (1) Verify Dia (spell ID 23) is in the player's spell list
        before using dia method — jobs like DRK/WHM need the scroll learned; falls
        back to ranged_attack if not available. (2) Spin path now fires /attack on
        before the pull command (matching main pull path order). (3) Removed
        redundant pull_wait from spin path — the 5s facing loop handles timing.
v3.27 - use_item_food: check inventory stock via get_tool_count() before firing
        /item. If 0 in inventory, log and skip without burning the cooldown timer.
        Applies to Red Curry Bun, Silt Pouch, and any other item_food entry.
v3.26 - Pull-LOS blacklist: when PullNext fires //facing f then pulls a mob and
        the game responds "Unable to see" (geometry block, not "You cannot see"
        which is a facing issue), immediately blacklist that mob for 30s.
        Implemented via last_pull_next_mob_id stamp after facing + PULL_LOS_WINDOW
        (5s) check in incoming chunk handler. Existing CANT_SEE_LIMIT hit-counter
        path unchanged for normal combat situations.
v3.25 - ASSIST mode: face every 1s for 5s on initial engage (blocking loop after
        /attack on in status==0 path) and on new target mid-combat (burst window
        via assist_face_burst_until timestamp drops periodic rate from
        FACE_COMBAT_RATE to 1s for 5s without blocking the combat chain).
v3.24 - After /attack on, face mob every 1s for 5s (both main pull and spin/scan
        pull paths) while mob walks into melee range. Replaces flat sleep.
v3.23 - Reduce PULL_NEXT_COOLDOWN from 15s to 5s.
v3.22 - Fix PullNext multi-mob: remove low_hp_pull_done=true from successful pull
        path. PULL_NEXT_COOLDOWN (15s) paces pulls; mobs_in_melee >= PullNextMax-1
        stops at cap. Previously done=true blocked all re-pulls until current mob
        died, making PullNextMax > 2 useless. Reset low_hp_skip_logged on cooldown
        expiry so subsequent pull-scans log correctly.
v3.21 - PullNext_OnLowHP mob cap now driven by PullNextMax in pull config.
        PullNextMax = total mobs allowed in fight including current target.
        WAR defaults to 6; all other jobs defaulted to 2 (original behavior).
        Cap check: skip pull if (mobs_in_melee >= PullNextMax - 1).
v3.20 - Move check_ninja_tools() to after buff/distance checks in use_magic().
        Tool inventory is now only scanned when spell would actually be cast
        (buff not active, recast ready) — not on every tick.
v3.19 - restock_ninja_tool: skip toolbag unpack when sub-NIN (WAR/NIN etc).
        Universal toolbags only work with NIN as main job. Sub-NIN players
        must carry raw tools (e.g. Shihei) directly in main inventory.
v3.18 - Fix all toolbag names to match Windower res/items.lua 'en' field:
        Toolbag (Shihe)/(Shika)/(Ino)/(Cho) — mismatch blocked auto-unpack.
v3.17 - Add //aa dumpinv command and fix get_tool_count to use pairs() iteration.
v3.16 - Add debug logging to check_ninja_tools/restock_ninja_tool: logs tool name,
        count found, toolbag check, unpack attempt, and post-unpack count.
v3.15 - Correct Utsusemi tool mapping based on game log evidence: Ichi and Ni use
        Shihei; San uses Shikanofuda. v3.14 had Ichi/San swapped.
v3.14 - Fix ninja tool check for /NIN subjob: check_ninja_tools() now validates tools
        when sub_job == 'NIN', not only when main_job == 'NIN'. Ensures script skips
        Utsusemi casts when tools missing instead of letting game emit 'Lack tools'.
v2.76 - Last known-good version (2,632 WS fires logged 00:00-08:02).
v4.00 - EXP ring fix: 'Emperor band' (lowercase b) in the DRK and DRG ring_config
        never matched the resource name 'Emperor Band', so check_and_use_ring()
        silently returned false and the ring was never equipped/used. Fixed the
        spelling in both configs, and ring lookups now fall back to a
        case-insensitive match (cached) with a one-time RINGS debug message for
        any name that is miscapitalized or not found at all.
v4.01 - Stop blacklisting mobs that are fighting a Trust just outside your reach.
        2026-10-10 23:22 log: a Worker Crawler tanking Valaineral sat at 3.8y. The
        script counted 3.8y as melee (3.0 + model_size) but the game said "out of
        range", so it fired Provoke ("Unable to use job ability") 3x, hit the
        re-pull limit, then STUCK, then MELEE-STALL -- blacklisted 3 times while
        it was killing Valaineral.
        (1) Learned reach: "<mob> is out of range." at a distance we counted as
            melee shrinks that mob's melee range to (distance - 0.5)y (REACH log).
        (2) Step-in (APPROACH): a mob within APPROACH_MAX_DIST (10y) that is just
            out of reach or is fighting a Trust/party member gets a short walk
            toward it (windower.ffxi.run, <= 1.5s burst, then stop + face)
            instead of Provoke / re-pulls. APPROACH_ENABLED = false turns it off.
        (3) mob_fighting_trust(t): mob targeting a Trust/party member (not you)
            and within melee of them. Such a mob is exempt from the re-pull
            limit, the STUCK watchdog and MELEE-STALL. Mobs hitting YOU are not
            exempt, so the unreachable-cliff-mob protection (v3.83) still works.
        (4) Pull-in timeout longer: PULL_IN_TIMEOUT 10s -> 20s, and a timed-out
            mob is skipped for 30s (PULL_IN_BLACKLIST, was 10s) so the scan
            doesn't swing straight back to it.
v4.02 - Close mobs hitting you / a Trust get re-pulled with Provoke, never
        blacklisted. 2026-10-10 23:37 + 23:38 log: two Death Jackets tanked by
        Valaineral at 3.5y (game: "out of range"). Provoke was on cooldown, so
        RE-PULLING fired it into "Unable to use job ability" twice, hit the
        re-pull limit and blacklisted the mob; the second one was then also
        STUCK-blacklisted right after Provoke finally landed on it.
        (1) Hit tracking: the action event records who each mob last hit (melee,
            TP move, spell). mob_hit_victim(t) -> 'me' / 'party' if it hit you
            or a party member in the last MOB_HIT_WINDOW (10s). mob_fighting_trust()
            now also uses it (target_index missed these Jackets).
        (2) Close-fight re-pull: a mob within APPROACH_MAX_DIST (10y) that is
            hitting you or a Trust while you aren't hitting it -> Provoke
            (CLOSE-REPULL log). Provoke on cooldown -> wait for it, logged every
            5s with the seconds left. Also applies in melee range after
            MELEE_STALL_LIMIT (15s) with no contact. Without WAR main/sub the
            normal pull_command is used, with no re-pull limit.
        (3) Such a mob is exempt from the re-pull limit, MELEE-STALL and the
            STUCK watchdog. A mob that hits nobody (v3.83 cliff mob) is still
            blacklisted as before.
        (4) A Provoke pull_command on cooldown is no longer sent (PULL-WAIT log)
            and doesn't count as a re-pull attempt.
        (5) Pull-in timeout: a mob hitting you / a party member counts as pulled in.
v4.03 - Emperor Band added to every job's exp_rings. Only DRK and DRG listed it;
        every other job had exp_rings = {'Echad Ring'}, so once Echad's
        Dedication wore off (and Echad was on its 2h lockout) nothing else
        was tried. Now {'Echad Ring', 'Emperor Band'}: Echad is still used
        first, Emperor Band when no EXP/CP buff is up and Echad isn't ready.
        Commented-out templates (WAR, RDM, COR) updated the same way.
v4.04 - Rings use their own reuse timer. A traded-in Emperor Band with fresh
        charges was still held back by the 2h lock in settings.xml.
        (1) check_and_use_ring reads extdata next_use_time / charges_remaining.
            Timer in the future -> wait (logged once: 'RINGS: <ring> on reuse
            timer: Xh YYm left'). Timer passed + charges > 0 -> use it, and any
            leftover internal lock is cleared ('clearing stale lock').
        (2) After /item the ring is re-read: success only if its timer moved
            forward or a charge was used. The saved lock is set to the ring's
            real next-use time. A use that didn't go off is retried after
            RING_RETRY_SECS (120s) instead of locking the ring for 2 hours.
        (3) 0 charges is logged once per ring. The old 2h lock is only used
            if the item has no timer data.
v4.05 - Back to the 2h lock in settings.xml as the cooldown tracker (the
        extdata next_use_time from v4.04 isn't reliable). A replaced ring is
        detected from its charges instead:
        (1) settings.ring_charges[id] = charges left after our last use;
            settings.ring_max[id] = most charges ever seen. RING_MAX_CHARGES
            holds known max charges (Emperor Band = 3).
        (2) Lock still running, but the ring has more charges than we left it
            with, or is full (e.g. Emperor Band 3/3) -> 'RINGS: <ring>
            recharged' and the lock is cleared (set to 0 so a lock in the
            <global> section doesn't come back on reload).
        (3) Otherwise a locked ring logs once: 'RINGS: <ring> locked: Xh YYm
            left (c/max charges)'.
        (4) A use counts if a charge was spent or a new EXP/CP/Emporox buff
            appeared. A miss retries after RING_RETRY_SECS (120s); after
            RING_MAX_FAILS (3) misses in a row it's locked 2h as before.
v4.06 - CP rings (cp_rings) are only used when the main job is level 99.
        Below 99 they are skipped and the EXP rings are tried instead.
v4.07 - Crash test switch + ring command-error fix (2026-10-11).
        (1) //aa target native | packet (saved per character, default packet).
            native = no injected 0x058 packet: set_target() turns toward the
            mob and sends the game's own /targetbnpc until the cursor is on
            that mob ID (NATIVE_TARGET_TRIES 4, NATIVE_TARGET_WAIT 0.4s).
            Log lines TARGET-NATIVE-OK / TARGET-NATIVE-MISS. Lets us test
            whether the FFXiMain.dll crashes (10/10 21:48, 10/11 01:03, both
            seconds after a target-locked mob died) stop without injection.
            The load line now shows the target mode.
        (2) Rings: "...A command error occurred." right after our /item means
            the client refused it (no packet sent). The ring is now locked
            2h at once (saved), the default ring goes back on immediately,
            and the log says 'RINGS: game refused /item ...'. Before, it
            retried every 120s and the fail count reset on every //lua r,
            so Echad Ring was swapped in and out all night.
v4.08 - Emperor Band sat idle after its in-game reuse timer was up
        (2026-10-11 log: used 01:06, Dedication wore off 01:24, then
        'Emperor Band locked: 1h 42m left' -- the fixed 2h lock outlasted the
        ring's real reuse time).
        (1) A successful ring use no longer sets a 2h lock. The ring is held
            back by its buff (Dedication/Commitment/Emporox) instead; once
            the buff wears off it is tried right away.
        (2) If the game refuses the /item ("...A command error occurred."),
            or it fails RING_MAX_FAILS times, the ring waits
            RING_REFUSE_BACKOFF: 10m, 20m, 40m, 80m, then 2h max per
            refusal in a row. A successful use resets the backoff.
        (3) //aa rings shows each ring's wait; //aa rings reset clears all
            ring waits (saved) so they are tried on the next combat tick.
        (4) Log wording: 'RINGS: <ring> waiting: Xh YYm until next try'.
v4.09 - Emperor Band's reuse is 15 minutes. New RING_REUSE_SECS table
        (Emperor Band = 900s): after a use the ring waits exactly 15m
        ('RINGS: Emperor Band used. N charges left, next use in 15m.'), and
        if the game still refuses it the retry is RING_KNOWN_RETRY (120s)
        instead of the 10m-2h backoff, which now only applies to rings with
        no known reuse time (e.g. Echad Ring). Add other rings to
        RING_REUSE_SECS as their reuse times are confirmed.
v4.10 - v4.09 still honored the old 2h lock saved in settings.xml
        ('Emperor Band waiting: 1h 29m' with no Dedication up). A saved lock
        longer than a ring's RING_REUSE_SECS is now cleared automatically
        ('RINGS: <ring> had a Xm wait saved but its reuse is 15m -- clearing it.').
v4.11 - Crash hardening after the 3rd FFXiMain.dll crash (2026-10-11
        04:23:33, 0xc0000005 @ 0x00076a75 -- same offset as 10/10 21:48:02).
        Both of those crashes hit the same second as 'Dead cursor ...', i.e.
        the instant /targetoff was sent at a despawning corpse.
        (1) Dead cursor: blacklist as before, but /targetoff is deferred 3s
            and only sent if the cursor is still on that same dead ID
            ('TARGETOFF dead cursor ...' / 'TARGETOFF skipped ...'). Targeting
            is held for 3.5s. Logged once per corpse, not every tick.
        (2) Rings: /item waits until 5s after the last kill / casket / dead
            cursor ('RINGS: holding /item ...'). 01:03:15 crash was an /item
            3s after a kill.
        (3) HEARTBEAT line every 10 min: uptime, AA Lua memory, dead-cursor
            count, target mode.
v4.12 - Death fix (2026-10-11 06:06:49 Escha Zi'Tah, DRG/WAR). Provoked an
        Eschan Corse; it stopped at 7.0y casting Flood (casters hold at range).
        PULL-TIMEOUT blacklisted it at 20s, it then meleed us while we pulled
        an Eschan Sorcerer, LOW HP STOP fired at 25% and we stood there until
        Burst killed us. Trusts never engaged the ranged pulls.
        (1) Pull-in: a mob targeting YOU and claimed by your party is in our
            fight -- no pull-in timeout for PULL_IN_CLAIMED_MAX (60s) ('PULL-IN:
            ... no pull timeout'). It also counts as in_fight for the re-pull
            limit and step-in (APPROACH_ENABLED still governs movement).
        (2) A mob that hit you in the last MOB_HIT_WINDOW s is lifted off the
            temporary blacklists (cant-see / pull-in) and retargeted
            ('UNBLACKLIST: ... is hitting you'). 2+ unreachable strikes and
            mob_blacklist entries stay blocked.
        (3) No new pull while a mob is on you (hit you / targets you + claimed,
            within FRESH_HOLD_RANGE 25y), capped at FRESH_HOLD_MAX 45s per mob,
            or while HP < LOW_HP_NO_PULL_PCT (50%; 0 = off). 'HOLD: ...' log.
        (4) Low-HP stop never stops while a mob is on you: it warns and keeps
            fighting, and runs LOW_HP_EMERGENCY_CMD once (default '' = none).
            With nothing on you it stops as before.
        (5) Low-HP timer: the 30s starts when HP reaches LOW_HP_STOP_PCT (or at
            the last heal), not at the last HP rise -- at full HP nothing rises,
            so it fired 11s after the damage started.
        (6) 'PARTY:' debug line (each Trust's HP%, MP%, distance) whenever the
            low-HP logic warns or stops.
v4.13 - Emergency abilities (06:06 death follow-up). Spirit Surge
        (hpp_below=35) was ready but never fired: abilities only ran inside the
        combat chain (needs a live /t -- none 06:06:04-06:06:13, and nothing
        after LOW HP STOP), one per tick, and Jump at an out-of-range mob took
        the 06:06:16 tick. Both pet=true emergency entries (Spirit Surge,
        Restoring Breath) failed while non-pet ones fired.
        (1) emergency_abilities(): every main-loop tick, before the low-HP
            check, the first ready abilities entry with hpp_below (list order)
            fires, target or not ('EMERGENCY: HP n% -- using X').
        (2) A skipped emergency entry logs why every 10s ('EMERGENCY: ... X
            skipped: no live pet / recast 42s / recast unknown / ...').
        (3) get_live_pet(): falls back to your entity's pet_index when the
            <pet> target comes back empty.
        (4) Jumps (and any '<t>' entry with max_dist=N) only fire when the
            target is within melee reach + JUMP_REACH_PAD (1.5y).
        (5) DRG: Super Jump moved ahead of the TP-builder Jumps.
v4.14 - Opener gate: face before abilities. Jump / High Jump were firing on a
        fresh pull before we had faced or meleed the mob, so Trusts never
        engaged.
        (1) '<t>' job abilities (Jump, High Jump, Dragon Breaker, Smiting
            Breath, ...) now wait until we have landed a melee round (or WS)
            on the current mob. JAs no longer count as that first contact.
        (2) Until then, use_job_abilities() turns to the mob every
            OPENER_FACE_EVERY (2s) -- bypassing the 4s face JA lockout -- and
            fires no JA on the tick it turns ('OPENER: facing X ...').
        (3) OPENER_FALLBACK (12s): with no swing by then, '<t>' JAs are allowed
            anyway so a mob you can't swing at doesn't stall them for good.
        (4) Exempt: Provoke (pull tool) and hpp_below emergency entries (Super
            Jump) -- emergency_abilities() is unchanged. '<me>' buffs still
            fire as before (except on the tick we turn).
v4.15 - Ability range in job_config (max_dist). DRG '<t>' abilities now carry
        an explicit max_dist so they never fire at a mob out of reach.
        (1) max_dist on a '<t>' job ability is measured from the mob's EDGE
            (center distance minus model size), so the same number works on
            small and large mobs. Jumps without it still default to 4.5y
            (3.0 + JUMP_REACH_PAD) -- same reach as v4.13/v4.14.
        (2) DRG job_config: Jump, High Jump, Spirit Jump, Soul Jump, Super
            Jump and Dragon Breaker max_dist=4.5; Smiting Breath max_dist=10;
            commented Angon line max_dist=10.
        (3) New debug line when a range check holds an ability (every 10s per
            ability, RANGE_LOG_EVERY): 'RANGE: holding Jump -- 6.2y from the
            mob's edge, max_dist 4.5y.' Emergency skip reasons show the same.
        (4) Spell max_dist (magic section) is unchanged: still center distance.
v4.16 - DRG max_dist set to the published ability ranges (checked on BG-Wiki,
        FFXIclopedia and the Horizon wiki) instead of v4.15's 4.5y melee guess:
        Jump 9.5, Spirit Jump 9.5, High Jump 11.5, Soul Jump 11.5, Super Jump
        12.5, Dragon Breaker 12, Angon (commented) 10. Smiting Breath stays 10
        (no range published anywhere). Default for a Jump with no max_dist is
        unchanged (4.5y).
v4.17 - Backup pull. Mob targeted, weapons out, just outside melee range and
        the main pull can't fire (Provoke on recast / no /WAR, no ranged weapon
        or ammo for /ra, Dia on recast / no MP): the first ready entry of the
        new job_config[job].backup_pull list fires to tag it and pull it in.
        (1) backup_pull = { {name='Jump', max_dist=9.5}, ... }. name = JA, pet
            command, spell, or 'Ranged Attack' (/ra <t>). max_dist = yalms
            from the mob's edge. pet / hpp / tp fields work as in abilities.
        (2) Runs in engaged_pull_logic() right before the main pull (after
            Provoke / the Provoke hold) and in close_fight_repull() while it
            waits for Provoke. Never in melee range, never in ASSIST mode,
            never within PULL_APPROACH_WAIT (6s) of the last pull.
        (3) Checks: ability known + recast ready (+ amnesia), spell known +
            job level + recast + MP (+ silence, + ninja tools), /ra needs a
            bow/gun with ammo or a throwing weapon (animators / pet food don't
            count). Counts as a pull (ps.pulls / last_pull), not a re-pull.
        (4) Debug: 'BACKUP-PULL (engaged): X at 6.1y -- main pull not ready,
            using Jump.' / '... nothing ready for X -- Jump: not available /
            recast; ...' (every 5s, BACKUP_PULL_LOG_EVERY).
        (5) Lists: DRG Jump > Spirit Jump > Soul Jump > High Jump (Super Jump
            left out: wipes hate). SAM / COR Ranged Attack. RDM Dia II, Bio,
            Stone. BLM Bio, Stone. WHM Dia II, Banish. NIN Kurayami / Hojo /
            Jubaku: Ichi. DRK Bio, Stone, Drain. WAR / THF none (/ra is the
            pull). BST / SMN / PUP: pet already attacks on engage (commented
            examples). Spells max_dist 16, /ra 20.
v4.18 - Long-run review (multi-day ASSIST / PULL). No combat logic changed.
        (1) Zone-change reset never ran: the event was registered as
            'zone_change' (console: "Unknown event: zone_change" on every
            load). Now 'zone change' -- zoning stops the loop and clears
            blacklists, strikes, mob_hits, dead-cursor and target-quiet state.
        (2) Unreachable strikes (cant_see_strikes) never decayed. Escha mobs
            respawn with the same ID, so over days more mobs reached strike
            2+ (never unblacklisted, even while hitting you) and 4+ (300s
            skips). Strikes now expire after CANT_SEE_STRIKE_DECAY (900s) and
            are cleared when that mob is defeated.
        (3) mob_hits kept one entry per actor ever seen and allocated a new
            table on every melee/TP/spell action in range. Entries are now
            reused and pruned after MOB_HIT_WINDOW.
        (4) prune_blacklists() also runs every 60s from prerender -- ASSIST
            mode never reached the between-fight prune.
        (5) Native targeting (//aa target native) slept inside pcall; Lua 5.1
            can't yield there, so it gave up after the first /targetbnpc.
            Sleep moved outside pcall; busy flag self-expires after 5s.
        (6) Login: ring_locks re-pointed at the reloaded settings, per-session
            tables cleared, job config reloaded. New 'job change' handler.
            update_job_configs() returns if main_job isn't loaded yet.
        (7) Header comment version fixed (said 4.06).
v4.19 - Faster next-mob after a kill (PULL). Log 10/25: defeat -> next pull
        was ~5-6s (defeat 22:41:10, TARGET-SET :12, ENGAGED :14, PULLING :16).
        The 1.0s TARGET_QUIET_WINDOW (FFXiMain.dll crash guard, v3.96/v4.11)
        is unchanged -- no target packet is ever sent during it. The dead time
        around it is cut. FAST_RETARGET = false restores v4.18 timing.
        (1) Defeat packet for our target (cursor / last_target_id / last
            swing) opens a FAST_KILL_WINDOW (4s): the loop wakes right as the
            quiet window ends instead of on a flat 1s tick (aa_loop_nap()).
            Ends as soon as we're engaged on the next mob. 'FAST-RETARGET:'
        (2) WS 2s animation wait ends early when the WS killed the mob
            (nap_while_alive). Mob still alive = full 2s, as before.
        (3) "Wait for target lock" sleeps (priority target 0.5s, scan 0.5s,
            pre-pull 0.5s) now return the moment <t> is on that mob
            (wait_cursor, still max 0.5s).
        (4) After ENGAGED, the next tick runs 0.1s later (was 1s), so
            engaged_pull_logic() fires Provoke / the pull ~1s sooner. Still
            waits for status 1 + PULL_FOLLOWUP_DELAY first (v3.91 rule).
            Melee-range engages also wait_for_engage() now (no more double
            'ATTACKING >>>> (melee)').
        (5) v3.03 'Facing next mob' turns directly at the mob (no target
            packet). It used set_target(), which the quiet window always
            skipped, so it never actually turned you.
v4.20 - HOT SWITCH: next mob at the kill, weapons stay out (PULL mode).
        Re-checked the 3 FFXiMain.dll crashes: none had a target packet to a
        NEW live mob. 10/10 21:48:02 (v3.95) and 10/11 04:23:33 (v4.10, which
        logged every TARGET-SET -- none before it) both hit the instant
        /targetoff went out at a despawning corpse (same 0x00076a75 offset);
        10/11 01:03:15 was an /item 3s after a kill. And at 10/10 21:47:48 the
        game's own Auto-target switched to the Goblin Leecher at the kill with
        no problem. So the quiet window stays for corpse-side actions only.
        (1) Defeat packet for our target -> hot_switch_start(): nearest LIVE
            mob within 3.0 + model_size + HOT_SWITCH_EXTRA (1.0y), mobs in our
            fight first, fresh ones only if fresh_pull_hold() allows a pull.
        (2) 0x058 to the new mob (set_target(id, true) skips only the quiet
            window check) + outgoing 0x01A cat 0x0F 'Switch target'.
        (3) Main loop won't /attack off for up to 1.5s while it's in flight.
        (4) Log: 'HOT-SWITCH >>>> X (id, 2.8y, in our fight)', then
            'HOT-SWITCH-OK' or 'HOT-SWITCH-MISS' 0.8s later. A miss or no
            candidate falls back to the v4.19 fast re-target.
        (5) HOT_SWITCH = false turns it off. Skipped in //aa target native.
v4.21 - Hot switch reaches out to pull range. Log 10/25: 317 kills, 1 hot
        switch -- the next mob was almost never in melee reach (6.7-25.6y), so
        it fell back to sheathe + re-draw. Re-drawing right after the game
        sheathes hits "You must wait longer to perform that action." (23x)
        and ENGAGE-WAIT's 3s timeout (17x).
        (1) HOT_SWITCH_RANGE = 'pull' (default): any valid mob out to the
            current pull distance (Provoke 17.8 / ranged 24.9 / Dia 20). You
            stay engaged and engaged_pull_logic() Provokes / pulls it in.
            In-our-fight mobs still first, fresh ones only if fresh_pull_hold()
            allows. 'melee' = v4.20 reach.
        (2) Turns toward the new mob right after the switch (v4.20's one
            switch got "Unable to see" / "You cannot see" for ~3s).
        (3) aa_pull_dist global set by the main loop each tick.
v4.22 - move_in_range (new toggle at the top, default false; //aa move on|off).
        PULL mode: a target past the reach of both pull methods (beyond your
        pull distance) is run to until it is MOVE_STOP_MARGIN (1.5y) inside
        pull range; then Provoke / the main pull fires as usual.
        (1) move_toward_mob(): MOVE_BURST (2s) of running per tick, then
            stop + face + quick next tick, so trusts / heals / checks keep
            running. Stops on: in range, mob dead/gone, claimed by others,
            HP < LOW_HP_NO_PULL_PCT, //aa stop.
        (2) Terrain: position checked every 0.5s. < 0.5y moved = blocked
            (Z change = slope); 4s without getting 1y closer = no progress.
            New obstacle -> detour 50 deg to the side that worked last; stuck
            again within 2y -> same side, 80 / 110 / 140 deg (follows the
            edge); then back up 0.7s and try the other side. 8 stalls, 30s,
            or 3+ stalls with an 8y+ height gap -> MOVE-GIVEUP + strike
            blacklist (blacklist_unreachable), re-scan.
        (3) Status 0: nothing in pull range -> move_far_pick() targets the
            nearest valid mob out to MOVE_SCAN_DIST (45y). Beyond ENGAGE_RANGE
            it runs unengaged; inside it draws weapons and keeps running
            engaged (engaged_pull_logic, where PULL-WAIT used to idle).
        (4) Running in refreshes the pull-in timeout; a far pick is never
            counted as a stale pull.
        (5) Logs: MOVE / MOVE-SCAN / MOVE-STUCK / MOVE-BACKUP / MOVE-OK /
            MOVE-GIVEUP. 'unload' stops running.
        (6) Releases: built by tools/make_release.py, which forces
            move_in_range = false, comments out every mob_whitelist entry and
            sets master_pull_method type = ''.
v4.23 - master_pull_method: each field overrides on its own. Before, all
        four only applied when type was non-empty, so type = '' silently
        ignored PullNext_OnLowHP / LowHPPrcnt / PullNextMax (THF kept
        PullNext off). Now type overrides when non-empty, and the other three
        whenever they are not nil -- false counts, so PullNext_OnLowHP = false
        turns it off everywhere (the old 'x and false or job' idiom fell
        through to the job value). nil = job value.
        tools/make_release.py: releases ship master_pull_method as
        {type = '', PullNext_OnLowHP = nil, LowHPPrcnt = nil, PullNextMax = nil}
        so no override reaches other players.
v4.24 - Keep going for the closest mob in our fight (PULL).
        Log 10/25 23:33:20-53: a Limule was PULL-TIMEOUT blacklisted at 17.3y,
        walked in and hit Shadowhammer from 23:33:41 while he was held on a
        mob 25y away (PROVOKE-WAIT); at the kill, the hot switch found
        "nothing alive" although HOLD said that same mob was on him at 2.7y,
        then the quiet window + casket delayed it another 4s.
        (1) closer_target_check() every engaged tick, before
            engaged_pull_logic(): when we are not hitting the current target,
            switch (0x058 + 0x01A, no disengage) to a mob in our fight that is
            2y+ closer (hitting you / a Trust, claimed by us, or targeting one
            of you), or -- if the current one isn't pulled yet -- to a fresh
            mob 5y+ closer (if fresh_pull_hold allows). Within pull range,
            3s cooldown. 'CLOSER-SWITCH >>>> X (id, 2.7y, hitting you)'.
            CLOSER_SWITCH = false turns it off.
        (2) Hot switch counts a mob that is hitting you / a party member as
            'in our fight' (it only looked at claim + target index).
        (3) unblacklist_hitters() never worked: get_mob_array() is keyed by
            mob index, it looked mobs up by ID (no UNBLACKLIST line in any
            log). Now get_mob_by_id(). Also runs before the hot switch and the
            closer check, so a blacklisted mob that is hitting you is picked.
            NOTE: the v3.02 'Unblacklisting ... moved into range' block has
            the same index/ID lookup and is still dormant -- left alone on
            purpose (fixing it would lift most blacklists within pull range).
        (4) 'Target too far away' now skips that mob for 10s (10/25
            23:14:08-45: the same 31-39y cursor, /targetoff every tick, 37s).
        (5) Engaged switch code shared: engaged_switch(m).
        (6) Log 10/25 23:39:14-38: 24s unengaged with HOLD 'Gulch Limule
            (2.4y) is on you' every 6s. That mob (16961588) was Provoked by
            PullNext at 23:39:07, then 'Pull LOS: geometry-blocked ...
            blacklisted 30s'; it walked over and hit you, but the priority
            scan skips blacklisted mobs and unblacklist_hitters() was broken
            (3). It engaged at 23:39:38 when the 30s ran out. Now fixed, and
            unblacklist_hitters() uses the same 'on you' test as HOLD (hit
            you, or targets you + claimed by your party), so HOLD and the scan
            can no longer disagree. Repeat offenders (2+ strikes) stay out.
v4.25 - Debug levels: RELEASE (minimal) and DEV (deep + timing).
        debug_mode (true/false) is replaced by debug_level at the top:
        0 = off, 1 = RELEASE, 2 = DEV. //aa debug 0|1|2 (off|release|dev)
        and //aa debug file on|off change it for the session.
        (1) RELEASE (1): only high-level lines, '[AA] ...': loaded, mode
            start/stop, zone stop, PULLING / RE-PULLING / ATTACKING,
            HOT-SWITCH / CLOSER-SWITCH, Using WS, MB cast, EMERGENCY / LOW HP,
            trusts called, food, ring used / failed, purple escape, STUCK,
            MOVE-GIVEUP, PullNext 'Next mob', tool / ring / trust config
            problems and every handler error. 51 call sites moved to the
            new info_msg(); all other debug_msg() lines are DEV only.
        (2) DEV (2): every line, stamped '[DEBUG hh:mm:ss.mmm +d.ddd]' --
            wall clock to the ms (os.time() re-anchored to os.clock() at each
            second roll-over in prerender) and seconds since the previous
            line, so gaps / slow steps stand out.
        (3) DEV TIMING lines: 'loop pass #n took X.XXs -- last stage ...'
            when a main-loop pass runs past DEBUG_SLOW_TICK (3s). Stages:
            top, emergency, trusts, pet, heal-outside, assist-engage,
            pull-scan, engaged. 'client frame stall X.XXs' when prerender
            frames are DEBUG_FRAME_STALL (0.5s) apart (max one per 2s).
        (4) DEV file log: data/logs/aa_<date>.log, every line plus all [CMD]
            commands (even with cmd_mode off), flushed per line so a client
            crash keeps the last lines. DEBUG_LOG_FILE = false turns it off.
        (5) tools/make_release.py now also forces debug_level = 1,
            DEBUG_LOG_FILE = false, heal_buff_outside_battle = false,
            cmd_mode = false and ws_blocked_debug = false (on top of
            move_in_range = false, whitelist commented out and
            master_pull_method blank / nil).
v4.26 - move_in_range: scan out to 50y, and a stale run timer fix.
        Log 10/25 23:51-23:58 (THF/WAR, Abyssea - Tahrongi):
        (1) MOVE_SCAN_DIST 45 -> 50. 23:57:17-53 sat idle 36s after a kill
            until a Gully Clionid came inside 45y (first seen at 45.5y).
            50y is about as far as the client keeps mobs in the mob array.
        (2) 23:56:36 MOVE-GIVEUP 'still 36.3y away after 30s' fired 0.1s
            into a new run: the run on that mob at 23:55:45 was taken over
            by a proximity scan before MOVE-OK, so mv.id kept the old start
            time. A run now restarts its timers when the last burst on that
            mob ended 3s+ ago (mv.last).
        Stop point unchanged: 1.5y inside pull range, then pull as usual.
v4.27 - Provoke when it can land, /ra instead of waiting (PULL, engaged).
        Log 10/25: engaged 19.6-24y from idle Gully Clionids, PROVOKE-WAIT
        held the pull 6s every time (23:52:00, 23:55:49, 23:58:00); one sat
        at 17.8y for the full 6s. An idle mob never walks into Provoke range.
        (1) provoke_pull_hold() only holds while the mob is coming to you
            (claimed by you + targeting you, or hitting you / a Trust).
            Otherwise pull_command (/ra) fires now -- 'PROVOKE-SKIP' (once
            per mob). If pull_command can't fire (no ammo), the old hold stays.
        (2) Pull method 'provoke' with Provoke down (recast, 30s lock, no
            /WAR): /ra <t> right away if a ranged weapon is ready and the mob
            is within RA_PULL_RANGE (24.9y) -- 'PULL-RA' -- instead of
            PULL-WAIT 'Provoke ready in Xs'.
        Unchanged: Provoke in range and ready always goes first; after a
        pull, PULL_APPROACH_WAIT (6s) still lets the mob walk in.
v4.28 - move_to_target replaces move_in_range: how far in to run (PULL).
        'off' | 'pull' (v4.22 behaviour, stop 1.5y inside pull range) |
        'provoke' (Provoke ready + mob not coming: run to 16.3y and Provoke;
        else /ra from pull range) | 'melee' (run into melee reach, 3y + mob
        size - 0.5, Provoke on the way) | 'target' (run to MOVE_TARGET_STOP
        1.5y) | <number> (run to that many yalms, Provoke on the way).
        move_mode() normalises it (true = 'pull', false/nil = 'off').
        Engaged: the run-in modes go before the Provoke-hold / pull logic;
        if a run ends (arrived, gave up, HP low) the normal logic carries on.
        Unengaged scans (move_far_pick, beyond weapon-draw range) run for any
        mode except 'off', and stop at pull range; the engaged logic takes it
        from there. //aa move off|pull|provoke|melee|target|<yalms>.
        tools/make_release.py: releases ship move_to_target = 'off'.
v4.29 - Settings moved out to aa_config.lua (+ aa_config_defaults.lua).
        Moved: domain_invasion, elemental_farming, mob_whitelist,
        mob_blacklist, master_pull_method, ws_mode, heal_buff_outside_battle,
        move_to_target and the whole job_config table. They are still the
        same locals here (move_to_target still a global), loaded by
        aa_load_config() through loadfile() -- not require(), because
        Windower's own 'config' library is require('config').
        (1) aa_config.lua missing -> copied from aa_config_defaults.lua.
        (2) A top-level setting missing from aa_config.lua -> taken from the
            defaults file (chat note says which).
        (3) aa_config.lua has an error -> chat message, defaults used whole.
        aa_config_defaults.lua: whitelist empty, DI / elemental off, standard
        blacklist, master_pull_method blank/nil, every job PullNext_OnLowHP =
        false, ws_mode Normal + lockout "true", heal_buff_outside_battle =
        false, move_to_target = 'off'.
        tools/make_release.py: ships aa_config_defaults.lua (checked against
        the release-safe rules) and never aa_config.lua, so an update can't
        overwrite a user's settings.
v4.30 - Target packet miss -> /targetbnpc fallback for that one mob.
        Log 11/08 02:11:30-02:13:24 (WAR/DNC, King Ranperre's Tomb): 73
        TARGET-SETs in a row, cursor never moved, incl. a Locus Dire Bat at
        0.4-0.9y for 2 minutes; v4.28 had 23 misses at 01:55:50, and 10-22
        before a pull was common. The injected 0x058 just wasn't taking.
        set_target() (packet mode, not the hot switch) now counts packets to
        the same mob that didn't put the cursor on it. After
        PACKET_MISS_LIMIT (3) misses, the next try is native_target() --
        turn toward it + /targetbnpc, up to 4 tries, TARGET-NATIVE-OK/MISS
        -- logged 'TARGET-FALLBACK' (L1). Then straight back to packets
        (exact mob ID). Cursor on the mob, or a different mob, resets the
        count. /targetbnpc can land on a neighbour; the final gate still
        checks whitelist / blacklist / claim before any pull.
        HEARTBEAT shows 'tgt fallbacks N'. PACKET_MISS_LIMIT = 0 turns it off.
v4.31 - ws_mode.type = "Off" (any case) turns weapon skills off for every
        job. Before, "Off" (no such sub-list) fell back to the whole ws_list
        table: no WS on jobs that only use named lists, but a job with a
        flat list would still WS. use_weapon_skill() now returns right away
        on "Off" and keeps ws_sc_locked false so abilities aren't held.
        aa_config.lua / aa_config_defaults.lua: a short primer above each
        setting (values + how it is used) and a job_config section guide.
v4.32 - Dread Spikes mode. The game never sends a mob's buffs, so Dread
        Spikes (status 173) is tracked per mob ID: "gains the effect of
        Dread Spikes" (spell / TP move) or anyone's melee hit showing
        "spikes drain N HP" (msg 132) marks it up; wear-off / dispel
        messages (action and 0x029), the mob's death, clear_hits landed melee
        hits in a row with no drain, or max_duration (180s, the spell's
        duration) since it was last seen mark it down; a mob with no news
        for forget_after (60 min) is dropped. While your target has it:
        the job's dread_spikes.gear goes on (//gs disable on those slots),
        no weapon skills, then Dispel / Magic Finale / Dark Shot > nukes >
        /ra, with melee_rounds of melee left between nukes / shots so the
        drain messages keep the record current. When it's down, you
        disengage, or you switch to a clean mob: after_gear (or the gear
        worn before) goes back on and //gs enable. New aa_config.lua
        dread_spikes block and a dread_spikes block in each job_config.
        //aa ds lists the tracked mobs, //aa ds clear empties the list.
v4.33 - //aa ws off turns weapon skills off, //aa ws on turns them back on,
        //aa ws shows which it is. Session only: it isn't saved, and a
        reload (or game restart) brings weapon skills back. While off,
        use_weapon_skill() returns right away and ws_sc_locked stays false,
        so abilities aren't held back for a skillchain. ws_mode in
        aa_config.lua is not changed.
v4.34 - Death fix (2026-11-13 04:02, WAR, Locus Dire Bats). A bat stopped
        at 3.8y -- counted as melee range, but none of our swings landed
        while it hit us for 80s. AA only re-faced it and re-Provoked (each
        Provoke restarted the 15s stall clock), a Trust was missing, and we
        died. Auto stayed on and nothing was logged until the 60-minute
        auto-homepoint zoned us at 05:02.
        (1) STEP-IN: a mob hitting YOU (or claimed on you) with no swing of
            ours landing for STEP_IN_HIT_WAIT (8s, from engage / last swing,
            not last Provoke) gets a short step in -- 1.5y closer, never
            nearer than 1.5y. Works even with APPROACH_ENABLED = false;
            STEP_IN_WHEN_HIT = false turns it off. Log: 'STEP-IN: ...'.
        (2) Your own death: a defeat message aimed at you (msg 97 etc.) or
            status dead logs 'YOU WERE DEFEATED by <mob>', prints a red chat
            line and turns auto off (and stops running / Dread Spikes gear).
        (3) Trusts: a Trust still not in the party after TRUST_MAX_FAILS (3)
            calls in a row is skipped for TRUST_FAIL_SKIP (10 min) --
            'TRUSTS: X still not in the party after 3 calls'. Seeing it in
            the party resets the count; zoning clears it all.
v4.35 - Death fix #2 (2026-11-13 20:04, WAR, Locus Dire Bats). Hot switch
        missed, re-target picked bat 17555862, /attack on, a casket popped,
        two "Unable to see". STEP-IN moved us to 1.2y, then 2 minutes with
        zero melee rounds: only 2 WSs (TP from being hit), 3 Provokes, the
        bat never died and killed us. Step-in can't fix this -- range was
        fine; our swings weren't going to that mob.
        RE-ENGAGE: engaged, in melee range, and no melee ROUND on the target
        for REENGAGE_WAIT (15s) -- weapon skills, JAs and Provoke don't count
        (they kept resetting the old checks) -- sends /attack off, re-targets
        the mob, /attack on, and faces it. Repeats every 15s while it lasts.
        Log line names the battle target (<bt>, same / DIFFERENT) and where
        the last melee round went, to pin down the cause next time.
        REENGAGE_WHEN_STUCK = false turns it off. New melee_round tracker
        (action category 1 only).
v4.36 - Dread Spikes gear fixes (from the 2026-11-15 00:04 Disdained One
        log: detection, /ra, no-WS and the clean-hit clear all worked, but
        the weapon never swapped).
        * Slot aliases: weapon = main, ranged = range, lear / rear / lring /
          rring. "weapon" was ignored as an unknown slot.
        * 'empty' takes the item out of a slot (gear or after_gear), e.g.
          sub = 'empty'. Sent as the 0x050 equip packet with item index 0,
          like GearSwap. '' or nil still means "leave that slot alone".
        * Gear goes on in slot order, main first. pairs() order was random,
          so a grip could be sent before its two-handed weapon and refused.
        * The snapshot now also covers sub when main is swapped and ammo when
          range is swapped, and records empty slots as 'empty'.
        * after_gear is laid over the snapshot: slots it names use its items,
          every other swapped slot goes back to what was worn before. Before,
          a non-empty after_gear replaced the snapshot, so range kept the
          Snakeeye +1.
        * After the mode ends, the restore is checked and re-sent every 3s
          (up to 5 tries) until everything is back on.
v4.37 - STEP-IN goes back to your spot; Provoke in melee range until you hit.
        * STEP-BACK: the spot you stood on is saved right before a STEP-IN
          (the v4.34 emergency move). As soon as a melee round lands on that
          mob you run back to that exact spot (within STEP_IN_RETURN_TOL,
          0.35y) and face it again. Also goes back if the mob dies or you
          switch to another target. Once per mob (STEP_IN_RETURN_MAX); a
          second STEP-IN on the same mob keeps the first spot. No hit within
          STEP_IN_RETURN_WAIT (60s) -> the spot is forgotten. Blocked on the
          way back -> stops where it is. STEP_IN_RETURN = false turns it off.
          Log: 'STEP-HOME: spot saved ...' / 'STEP-BACK: ...'.
        * MELEE-PROVOKE: engaged (PULL mode, WAR main/sub), the mob in melee
          range and no melee round / WS on it in MELEE_HIT_WAIT (4s) -- or
          none yet since engaging -- Provoke fires every time it is ready
          (v3.97 never Provoked in melee range). It does not reset the
          STEP-IN, RE-ENGAGE or stall timers. MELEE_PROVOKE_NO_HIT = false
          turns it off. Log: 'MELEE-PROVOKE: ...'.
v4.38 - Provoke first, STEP-IN only on trouble.
        * MELEE-PROVOKE fires right away: engaged, mob in melee range and you
          aren't hitting it (none since engage, or no swing in 4s) -> Provoke
          as soon as it's ready. Now checked before RE-ENGAGE, and also when
          the game says "out of range" at melee distance.
        * STEP-IN no longer runs on the 8s STEP_IN_HIT_WAIT timer (removed).
          It needs TROUBLE: STEP_IN_MOB_HITS (4) attack rounds from the mob on
          you (hit or miss) with no melee round of yours landing on it, or a
          fresh (3s) "out of range" / "Unable to see" / "You cannot see" /
          "unable to reach" message about it. Then Provoke goes first; the
          step in only happens STEP_IN_AFTER_PROVOKE (3s) after a confirmed
          Provoke on that mob if you still aren't hitting. Provoke on recast
          -> waits up to STEP_IN_PROVOKE_MAXWAIT (8s) from the trouble, then
          steps in anyway. No /WAR -> steps in right away.
        * After a step, it needs fresh trouble (4 more rounds / a new message)
          before stepping again. A melee round landing clears the trouble.
        * STEP-BACK (v4.37) unchanged: back to the saved spot once engaged.
        * Log: 'TROUBLE: ...', 'MELEE-PROVOKE: ...', 'STEP-IN: ...'.

v4.39 - Provoke before giving up on a pull.
        Log 11/15 02:29:57: MELEE-PROVOKE on the last bat left Provoke on
        recast; the next bat (4.6y) got /ra x3, every one "can't see"; Provoke
        came back at 02:30:12 but was never tried, and PULL-TIMEOUT (20s)
        blacklisted the bat, /attack off, re-targeted it 70s later.
        * Pull-in timeout and re-pull limit now check Provoke first
          (giveup_provoke_first): mob in Provoke range, never Provoked since
          it was picked -> Provoke ready: fire it (lands = fresh 20s window);
          Provoke back within PULL_GIVEUP_PROVOKE_WAIT (8s): hold the give-up
          and wait for it. No /WAR / out of range / already tried -> old
          behavior. Holds never last more than ~11s.
        * /ra re-pull after "Unable to see" / "You cannot see" on the target
          (ra_cant_see, RA_CANT_SEE_WINDOW 10s): if Provoke is back within
          RA_CANT_SEE_PROVOKE_WAIT (8s), wait for it instead of re-pulling.
        * Log: 'GIVEUP-PROVOKE: ...', 'GIVEUP-HOLD: ...', 'PULL-WAIT: ... can't see'.

v4.40 - Provoke on hot-switch; otherwise Provoke is saved for pulls.
        * HOT-SWITCH -> Provoke the new mob right away (HOT_SWITCH_PROVOKE,
          default true): next loop tick, Provoke ready, mob within 17.8y,
          in melee range or not. Tried for HOT_SWITCH_PROVOKE_WINDOW (6s)
          after the switch. Log: 'HOT-SWITCH-PROVOKE: ...'.
        * MELEE_PROVOKE_NO_HIT now false: no more Provoke on a mob already in
          melee range that you aren't hitting -- that kept Provoke on recast
          when the next mob needed pulling (11/15 02:29 bat log). Provoke is
          used for: pulls, re-pulls, close-fight re-pulls, Provoke-before-
          give-up (v4.39), hot-switch, and any Provoke entry you put in your
          job's `abilities`.
        * STEP-IN with MELEE-PROVOKE off: steps in as soon as there is
          trouble (no 8s wait for a Provoke). A Provoke that just landed on
          the mob (hot-switch / pull) still gets STEP_IN_AFTER_PROVOKE (3s).

v4.41 - HOT-SWITCH-HOLD: nothing else until the first melee round.
        * After a hot-switch (and its Provoke) the puller does no other
          actions -- no WS, JAs, magic, rings/food, pet, heals, PullNext,
          closer-switch or backup pull -- until one of its melee rounds lands
          on the new mob, so Trusts and the party engage it. The pull logic
          (hot-switch Provoke, facing, re-pull, step-in) still runs.
        * Released by: first melee round on it, target changed / died,
          HOT_SWITCH_HOLD_MAX (15s) with no round, or your HP below
          HOT_SWITCH_HOLD_HPP (40%). HOT_SWITCH_HOLD = false turns it off.
        * Log: 'HOT-SWITCH-HOLD: ...' (start + 'released after Xs -- why').

v4.42 - Dead-mob guards for ASSIST (and two PULL leftovers).
        Other characters crashing in ASSIST after hours/days. Audit: ASSIST
        never got the v3.96-v4.11 crash guards (quiet window after a kill /
        casket, deferred /targetoff on a corpse) -- it sent /target <bt>
        unchecked ~1/s idle, every 1-3s engaged, and the instant <t> died.
        * assist_target_bt(): /target <bt> only when <bt> is a live,
          targetable mob, no quiet window is open, and the cursor isn't
          already on it. Used for ASSIST idle, engaged facing refresh and
          cursor-lost re-acquire. Log: 'ASSIST-BT-SKIP (...)' once per reason.
        * ASSIST /attack on: re-checks the mob is still alive and on the
          cursor after the 0.3s face (assist_engage_ok, 'ASSIST-ENGAGE-SKIP').
        * PULL: engaged with no valid target (our mob just died, hot switch
          found nothing) no longer sends /attack off + /targetoff at the
          corpse; held up to DEAD_CURSOR_TARGETOFF_DELAY (3s) while the game
          disengages on its own (corpse_hold_check, 'CORPSE-HOLD (...)').
        * PULL: 'PULL ABORTED: target died before pull fired' /targetoff is
          now deferred 3s and only sent if still on that corpse
          (deferred_targetoff), like the v4.11 dead cursor.
        * item_food: same RING_KILL_HOLD (5s) as rings -- no /item right
          after a kill / casket / dead cursor.
        * DEAD_MOB_GUARD = false turns all of this off (v4.41 behaviour).

v4.43 - Stability: ring wait cap, stale-loop guard, auto-run stop.
        Full review of v4.42: no undefined names, every distance guarded,
        0 Lua errors and flat memory (22-38 MB) in 17 logs / 22h sessions.
        * Ring /item kill hold capped at RING_HOLD_MAX (20s). Any nearby
          defeat restarts the 5s hold, so in a busy camp it could wait
          forever with no watchdog heartbeat -> watchdog restart -> two
          loops at once. Now: skip, default ring back on, retry the ring in
          RING_HOLD_RETRY (60s). Heartbeat kept alive while it waits.
        * STALE-LOOP guard: main_logic_loop registers its coroutine; a loop
          superseded by a watchdog restart (or stop + start) can no longer
          send commands, target packets, unequip packets or run. Every
          windower.send_command now goes through cmd() (logged at level 2).
          Log: 'STALE-LOOP: dropped ...'.
        * start_main_loop() stops auto-run first: a loop that died mid-move
          (Lua error) no longer leaves the character running through the
          watchdog restart.

v4.44 - PARTY COMMANDS (new file aa_party.lua).
        Friends (party.friends in aa_config.lua, name + nickname) control
        AutoAttack with "/tell <you> aa <command>" or "/p aa <command>".
        Only friends are obeyed; party chat only from friends in the party.
        * aa invite me|<name> [sync <name>] [leader <name>] [fight]:
          same-zone check (AA-to-AA "aa~q", party zone for members) ->
          not leader: "send this to <leader>" -> invitee in a Trust-only
          party drops it (refused while fighting) -> finish the mobs
          fighting the party (no new pulls, finish_timeout) -> /retr all ->
          /pcmd add -> Level Sync (0x077 packet, no text command exists) ->
          /pcmd leader + "aa~lead" so the new leader calls Trusts at once
          and fights -> else trust_wait (120s) after the drop, call Trusts,
          "/p aa fight" if it was fighting or "fight" was sent.
        * aa fight: leader waits for members to stack (stack_wait), pulls;
          members run onto the leader (party_range, 1y), assist its pulls,
          follow it between fights. aa stop (remote) finishes the fight first.
        * aa stack | follow | unfollow | cancel | disband | leave | leader |
          sync | unsync | trusts [group] | retr | rest | mount | dismount |
          pass | status | ping | help, pass-through pull/assist/ws/move/ds.
        * Invites from friends are accepted automatically (auto_accept).
        * call_trusts(): max_trusts now counts Trusts only, capped so the
          party (players + Trusts) never goes over 6.

v4.45 - Party commands: retrust, lot, new defaults.
        * aa retrust (leader): finish the mobs fighting the party (no new
          pulls), stop, /retr all, wait trust_wait from the drop, call
          Trusts until full, then back to the mode it was in.
        * aa lot: lot on every item in the treasure pool (pass = pass all).
        * party.stack_wait default 15s -> 5s, finish_timeout 180s -> 300s
          (both in aa_config.lua).

v4.46 - Trusts after an invite (2026-11-16 22:16 log).
        "aa invite me ... leader shadow fight": Mythrandiir joined 22:16:33,
        Trusts were called 4s later. The game blocks Trust magic for 120s
        after a player joins, so all 12 calls failed, every Trust went on
        the 10-minute skip list, and the fight started with no Trusts.
        The trust wait counted from the Trust drop -- and with no Trusts
        out (dropped in the 22:13 invite) there was no wait at all.
        * The wait now counts from the join (party.trust_wait, 120s).
        * Any player joining (AA's invite or a typed one) starts the window;
          becoming leader by a hand-off clears it (new leader isn't held).
        * call_trusts() skips calling inside the window (log: 'TRUSTS: a
          player joined the party -- no Trusts for Ns more.').
        * aa fight (leader): waits out the window, calls Trusts, then pulls.
        * Party Trust calls clear the old 10-minute skip list first.

v4.47 - aa stack / aa fight stack on the exact X/Y.
        Members ran until they were within party_range (1y) of the friend.
        Now they run onto the friend's exact X/Y and stop within
        party.stack_precision (0.3y): checked every frame, the last yalm in
        one-frame steps so they don't run past it, done once it holds for 3
        frames. aa fight stacks a member that is more than stack_precision
        away (was: more than 1y).

v4.48 - aa stack always stacks on the party leader.
        Was: on the sender (or a named friend). Now every member runs onto
        the leader's exact X/Y no matter who sends it; a name after "stack"
        is ignored, the leader stays put, and a character with no party
        (or a leader in another zone) replies instead of moving.

v4.49 - Trust waits report every 10s at debug level 1.
        * Invite / retrust wait and aa fight's wait: 'TRUSTS: Ns left before
          calling Trusts (...)' every 10s, then 'TRUSTS: wait over -- calling
          Trusts.'
        * call_trusts() hold line ('TRUSTS: a player joined the party -- no
          Trusts for Ns more.') moved from level 2 to level 1 (it comes every
          10s with the Trust check).
        (The v4.49 aa_party.lua copy didn't reach the addon folder; it ships
        with v4.50.)

v4.50 - FAST ASSIST for aa fight members.
        Members in aa fight waited for ASSIST mode to see the mob as the
        party's <bt>, then /target <bt>, a flat 1s wait, face, 0.3s, attack
        -- once per loop pass: a long lag after every leader pull.
        * aa_party.lua: the moment the leader acts on a mob (Provoke, /ra,
          melee, WS, spell, JA) or a mob acts on anyone in the party (you, a
          player or a Trust; unclaimed or party-claimed), an idle member
          targets it, faces and /attack on ('FAST-ASSIST >>>> <mob> (leader
          on it)'). Same mob at most once per 3s; only in aa fight (ASSIST,
          not engaged).
        * ASSIST idle: after /target <bt> it goes on as soon as the cursor is
          on <bt> (max 1s) instead of always sleeping 1s (assist_wait_cursor).

v4.51 - aa sneak | aa invis | aa sneak invis (aa_party.lua).
        "/p aa sneak invis" (or /tell): every character that doesn't have
        the buff puts it up -- its own spell (main or sub, MP and recast
        checked), else Spectral Jig (DNC main/sub 25+, gives both), else
        Silent Oil / Prism Powder -- Sneak always before Invisible. Then it
        answers in the same channel (/p or /t): 'Shadowhammer: Sneak 4:05,
        Invisible 4:50' (time left from the 0x063 buff packet), or 'NO
        Invisible (no Invisible spell, Spectral Jig or Prism Powder)'.
        Refused while fighting / mounted / resting.

v4.52 - aa warp | aa 299 (aa_party.lua).
        /p: every character stops AA / following (dismounts if mounted).
        Characters that can cast Warp II say "[AA] <name>: I can Warp II."
        in /p; after warp_claim_wait (3s) the first by name Warp IIs every
        other player in the zone (within 20y, waits for recast, one retry),
        then warps itself (Warp, else Warp II on itself, else its ring).
        The others wait for it (warp_wait 90s), then use their ring. No
        Warp II mage: each character /equip ring1 "Warp Ring", gs disable
        ring1, waits warp_ring_delay (11s, as the EXP rings), /item it;
        gs enable ring1 after zoning (or if it doesn't go off).
        /tell or typed: just that character (Warp spell, else ring).
        Refused while fighting.

v4.53 - aa warp: Warp Ring on the RIGHT ring, old ring put back.
        Remembers the item in the right ring slot, /equip ring2 "Warp Ring"
        + gs disable ring2, uses it after warp_ring_delay. After the warp
        (zone loaded + 3s) the old ring goes back on ring2, then gs enable
        ring2. If the ring doesn't go off, the old ring goes back at once.
v4.54 - Full party rule + ghost slot fix (Mark, 2026-11-17: Trust calls
        failed on timing and a mob got pulled anyway).
        * PULL mode never pulls a NEW mob while the party is short of
          Trusts (job max_trusts, zone limit, 6 per party). Mobs already
          fighting you / the party (hitting, claimed by or targeting one of
          you) are still fought. Covers the idle scan, an idle mob in melee
          range, the final pull gate (cursor kept, no /targetoff), the
          engaged pull of the current target, hot switch to a fresh mob and
          PullNext. 'PULL HOLD: party not full (n/m Trusts, x/6 in party)'
          every 10s at level 1.
        * Ghost slot: a disconnected player can hold a slot the party list
          doesn't show. When the game says the maximum Trusts are out while
          the party reads under 6/6 (or 3+ Trust calls fail for 60s with
          none joining, not silenced / mounted), the idle leader sends
          /retr all, waits for the Trusts to leave, clears the skip list and
          calls them again. Never while a mob is on the party. If it happens
          again within 10 min in the same zone it stops retrying and says so.
          Every chat line with 'alter ego' is logged (TRUST TEXT, level 2)
          so the exact game wording can be checked.
        * party.full_party_pull = true (aa_config.lua). //aa fullparty
          [on|off|fix]: show / turn off for the session / force the fix.
v4.55 - Ghost slot text fix (Mark, 2026-11-17 02:45 log: the fix worked --
        "You have called forth your maximum number of alter egos." -> /retr
        all -> all 5 Trusts back -- but the log was flooded).
        * AutoAttack's own [DEBUG]/[AA]/[CMD] lines come back through
          'incoming text'. The TRUST TEXT line held "alter egos" + "maximum"
          so it matched itself ~49 times (until the chat line was cut), and
          the PULL HOLD debug line "until the party is full" set it off at
          02:22 (could have caused a /retr all nobody needed). Own lines are
          now skipped.
        * "party is full" only counts within 10s (FP_TEXT_SECS) of our own
          Trust call.
v4.56 - Hot-switch Provoke waits for the WS animation (Mark, 2026-11-17:
        "the first provoke after a hot-switch is failing").
        * Logs 11-15..11-17: the failures were not the switch -- they were
          the kill WS. When a /ws kills the mob, the hot-switch Provoke went
          out ~1.5-3.0s after the /ws, still inside its animation, and the
          game dropped it (1,728 of 1,782 failed). Sent 3.25s+ after the
          /ws: 0 of ~600 failed. Melee kills / recent JAs were fine.
        * HOT-SWITCH-PROVOKE now waits until HOT_SWITCH_PROVOKE_WS_GAP
          (3.5s) after the last /ws, then fires. HOT-SWITCH-HOLD keeps
          everything else quiet meanwhile; the Provoke window is stretched
          so the wait can't expire it. Log (debug level 2):
          'HOT-SWITCH-PROVOKE: waiting X.Xs for the WS animation ...'.

v4.57 - aa disband actually disbands (Mark, 2026-11-17: "aa disband sent to
        Scracheebrat did drop trusts, but didn't disband party").
        * aa_party.lua: with Trusts out, /pcmd breakup only released the
          Trusts and the players stayed in the party. Disband / leave now
          sends /retr all first, waits for the Trusts to go (up to 5s),
          then /pcmd breakup (leader) or /pcmd leave.
        * It checks the party really emptied and tries again (3 tries,
          4s apart). If it still can't, it says so in the reply instead
          of claiming it disbanded. Log (debug level 2): 'DISBAND: ...'.
v4.58 - aa disband clears a party of 1 (Mark, 2026-11-17: "scracheebrat is
        still a leader of a party of 1, with no trusts or no other players").
        * aa_party.lua: with no players and no Trusts, disband used to say
          "not in a party" and do nothing, but the game can leave you as
          leader of a party of just yourself (e.g. after /retr all), which
          blocks invites. Disband now spots that (p0.is_leader or a party
          leader id still set) and sends /pcmd breakup, then /pcmd leave,
          up to 3 tries, checking each time. Also runs right after the
          Trusts are dropped. Log (debug level 2): 'DISBAND: party of 1 ...'.
v4.59 - Per-character log files (Mark, 2026-11-17: "I need these logs to be
        character/player specific for each file / day, because I login to
        different characters on different PCs").
        * Debug log files (debug level 2 + DEBUG_LOG_FILE) are now
          data/logs/aa_<Character>_<YYYY-MM-DD>.log, e.g.
          aa_Shadowhammer_2026-11-17.log -- one file per character per day.
        * Login / logout close the current file, so a character switch on the
          same PC starts that character's file. The date is checked on every
          line, so a session running past midnight rolls over to the next
          day's file. Before a character is loaded (title screen) lines go to
          aa_NoChar_<date>.log. The 'log opened' header names the character.
        * Old aa_<date>.log files are left as they are.
v4.60 - aa reload (Mark, 2026-11-17: "is there an aa command to have player
        reload autoattack?").
        * aa_party.lua: aa reload (or aa rl) runs //lua r autoattack.
          /tell <name> aa reload -> that character; /p aa reload -> every
          AA in the party; aa reload all (typed or by /tell) -> says
          "/p aa reload" so the whole party reloads, this one too.
        * Before reloading it saves who asked to data/reload_notify.txt; the
          reloaded AA reads it (within 2 min), deletes it and answers in
          the same channel: "[AA] <name>: reloaded -- AutoAttack v4.60", so
          you can see each PC is on the new build.
        * The reload stops AutoAttack (and any follow / invite in progress);
          send aa fight / pull / assist again afterwards.
        * Friends-list rules as for every other command.
v4.61 - Memory: 22-36 MB -> a few MB (Mark, 2026-11-18: "AA is running 25mb
        to 35MB ... what tables or data is causing this large footprint").
        Logs showed no leak (25h session flat at 22-36 MB). The cost was:
        (1) res.items, the game's full item list (~23,500 items, ~20 MB),
        loaded on the first item lookup and kept for good; (2) garbage from
        get_items() with no argument, which builds every bag each call.
        * res.items is now a small proxy (aa_item / aa_item_named): only the
          items looked up are kept. On a miss the full list is loaded, the
          entry kept, and the list released 10s (ITEMS_KEEP_SECS) after its
          last use. Everything that reads res.items -- this file,
          aa_party.lua and Windower's extdata lib (ring charges) -- goes
          through it. Before release, everything in the inventory is cached.
        * Tool counts compare item IDs (the tool's ID looked up once by
          name) instead of looking up the name of every inventory slot.
        * get_items() for one bag only: tools = inventory, rings = inventory
          + wardrobes, equipped range / ammo / Dread Spikes gear = equipment.
        * collectgarbage setpause 150 (was 200): garbage collected sooner,
          lower peaks.
        * HEARTBEAT line adds 'item list loads N'; debug level 2 logs
          'ITEMS: full item list loaded (why) in Xs' / '... released -- AA
          lua now N KB'.
v4.62 - aa update (Mark, 2026-11-18: "'aa update' would download, tell
        sender its downloaded, then reload, then tell sender its reloaded
        and version number"; aa reload still just reloads the files on disk).
        * aa_party.lua: aa update [all|force]. Reads manifest.txt from
          https://raw.githubusercontent.com/thrydwolfvalefor/autoattack/main/
          (party.update_url in aa_config.lua overrides it; never taken from
          chat), downloads the files it lists -- only autoattack.lua,
          aa_party.lua, aa_config_defaults.lua, README.md are allowed --
          and checks each one: byte size from the manifest, .lua files must
          load, autoattack.lua must carry the manifest's version. Then the
          current files go to backups/ (*_v<old>_pre-update_<date>), the new
          ones are written (old ones put back if a write fails), it replies
          "downloaded v<new> -- reloading...", reloads, and the reloaded AA
          replies "updated and reloaded -- AutoAttack v<new> (was v<old>)".
        * /tell -> that character, /p -> every AA in the party, aa update all
          -> "/p aa update" (whole party, sender too). Same or older version
          on GitHub -> "already on v..." / no downgrade unless "force".
          Refused while fighting or while an invite / retrust is running.
        * aa_config.lua dev = {debug_level, debug_log_file, cmd_mode,
          ws_blocked_debug} overrides the values at the top of this file,
          so an update (release copy: debug_level 1, log file off) keeps
          your own debug settings.
        * tools/make_release.py writes manifest.txt (version + file sizes)
          into realeases/autoattack/ and forces dev = {} in the defaults.
v4.63 - Updates never wipe a player's settings (Mark, 2026-11-18: "how are
        we handling aa_config so that players that get an update from github
        are not getting their own configs wiped out?").
        * aa update never touches aa_config.lua (only the four listed files),
          and releases ship only aa_config_defaults.lua (v4.62).
        * NEW: settings missing from aa_config.lua are filled from the
          defaults at every level, not just the top. Only adds what is
          missing, never changes a value. Never adds list items (numbered
          abilities / magic / food / cure entries), lists (trust groups,
          ws_list modes, mob lists, friends) or whole jobs under
          job_config -- the player's own lists and jobs stay as written.
        * One chat line instead of one per setting: "[AA] aa_config.lua: N
          new settings using defaults -- //aa config new to see them".
          //aa config new lists each one with its default value.
        * Rule from now on: settings are not renamed or removed in a way
          that breaks an older aa_config.lua; a renamed setting keeps
          accepting the old name for a while, and the changelog says so.
v4.64 - aa update fix (Mark, 2026-11-18 00:43: "update failed -- attempt to
        yield across metamethod/C-call boundary" on every PC).
        * aa_party.lua: do_update() runs inside pcall, and paused 0.2s
          (coroutine.sleep) between file downloads. Windower's Lua 5.1 can't
          yield inside pcall, so the update stopped after the first file --
          before anything was written (no files were changed). The pause is
          gone; nothing in do_update yields now.
        * PCs on v4.62 / v4.63 have the broken updater, so they need this
          version copied over by hand once; aa update works from v4.64 on.
v4.65 - Safe start + rollback, aa update check / aa version, richer ping,
        README "Installation & updates" (Mark, 2026-11-18: first release
        delivered by aa update).
        * SAFE START: the whole addon now runs inside AA_MAIN() under
          xpcall. If it fails to start within 10 min of an aa update
          (reload_notify.txt names the old version), the files that update
          backed up (backups/*_v<old>_pre-update_<stamp>) are copied back,
          the sender is told "v<new> failed to start (<error>) -- rolled back
          to v<old>, reloading.", and it reloads on the old version. Same if
          aa_party.lua fails to load after an update. Any other start
          failure is reported as before.
        * aa rollback [all]: back to the newest version an aa update backed
          up (not the one running). Refused while fighting. Reply "rolled
          back to v<old> -- reloading...".
        * aa update check / aa version: reads GitHub's manifest and replies
          "v4.65 (GitHub: v4.65) -- up to date" / '-- "aa update" to
          install' -- installs nothing.
        * aa ping: "<name> v<ver> | WAR99/SAM | PULL | 4.1 MB".
        * README: "Installation & updates" section (first install, aa
          update vs aa reload, config safety, GitHub cache, failed update,
          rollback).
v4.66 - Ring swap fix (Mark, 2026-11-18: pol.exe crash 00:57:34 on
        Mythrandiir, ntdll 0xc0000374, log ends on two ring /equip 3ms apart).
        * Echad / Trizek / Endorsement Ring were used at 23:29-23:31 but got no
          reuse lock (only Emperor Band had a known reuse), so they were
          swapped in every few minutes for their whole 2h recast (68 ring
          /equip in 70 min, 0 uses). Rings not in RING_REUSE_SECS now use
          recast_delay from res/items.lua (these three = 7200s): after a use
          the lock is saved and survives reloads ('used. ..., next use in 120m').
        * A ring with a long reuse (> RING_SHORT_REUSE 1800s) that fails or is
          refused uses the 10m-2h backoff, capped at its reuse. Short-reuse
          rings (Emperor Band) keep the 120s retry.
        * Buff-only confirmed use saves the real charge count (was charges-1,
          which read as 'charges went up' next time and cleared the lock).
        * New ring_equip(): at least RING_EQUIP_GAP (2s) between ring /equip
          commands. The default-ring restore goes out at once; the next
          ring's /equip waits ('RINGS: 2.0s gap before /equip ...').
        * extdata next_use_time is still NOT used (unreliable, see v4.05).
v4.67 - Party commands run on the sender too (Mark, 2026-11-18: "most aa
        commands should include the person sending the command ... including
        'aa version' they should run for each party member").
        * aa_party.lua: your own party line only ran on you when it was typed
          as "/p aa ..." / "/party aa ...". Typed with the chat box already in
          party mode, or sent from a macro, it ran on everyone but you. Now
          the party echo of your own line (incoming text mode 5) runs it too;
          the /p hook stays as a fallback and P.self_ran (3s) keeps it to one
          run. Lines AA said itself (P.said) are still skipped.
        * Unchanged exception: "aa follow <your own name>" does nothing on
          you -- everyone else follows you.
        * Tells still act only on the character you tell; add "all" (aa
          update all / aa reload all / aa rollback all) to do the party.
v4.68 - Sender's own reply was lost (Mark, 2026-11-18 02:01: Mythrandiir
        sent "/p aa version"; Shadow and Scrach answered, Myth did not).
        Myth's log shows it ran and sent "/p [AA] Mythrandiir: v4.67 ..."
        0.57s after its own line; the game dropped it (the reload reply 4s
        after its line showed). aa_party.lua: every party line from AA
        (replies, aa ... relays, "I can Warp II.") goes out at least
        PARTY_GAP (2s) after this character's last party line, typed or
        AA's -- scheduled, not slept (safe inside aa update's pcall).
v5.53 - Group skillchain: learned turn lengths -- fewer chain steps wiped by a
        second WS (Mark, 2026-11-24: "How is the DMG and GSC doing for the
        group today?").
        Review 00:00-12:45, Shadow THF (Evisceration / Rudra's Storm) + Myth
        SAM GK + Scrach RDM sword, all v5.52, Locus Dire Bats, King Ranperre's
        Tomb: 731 kills, 62-72 kills/h (median 59s apart), 22-25k EP/h, SC
        ~7M/h + WS ~7M/h + MB ~1M/h, 0 errors. Myth ENGAGE-LAG ~5s (was 18-22s
        before v5.47). Main chain Kasha > Evisceration = Gravitation > Fudo =
        Darkness (26.5k) > Rudra's Storm = Darkness end (19.3k).
        Loss found: 454 of 3949 live steps (11.5%) were wiped by another
        player's WS landing 0-3s after the step (Myth on Shadow 234, Shadow
        on Myth 113, Scrach/Myth 74, Scrach/Shadow 33); 311 of them were a
        level-3 Darkness / Light. The next player's turn opened 1.5s after the
        first one's, but Myth's WS lands 1-3s after his turn opens and his
        "readying" shows only ~0.5s before it lands.
        * Each AA learns, per teammate, how long after their turn opens their
          WS lands (last 40 skillchain steps they closed) and gives them
          p80 - 0.5s (handoff_wait .. handoff_max 3.0) before the next turn.
          Used for continuer and opener turns. group_skillchain.handoff_learn
          = false turns it off (back to fixed handoff_wait / opener_wait).
        * A teammate who came under half the times we waited on them (Scrach
          189 of 968) keeps the plain handoff_wait -- a longer turn would only
          slow the chain.
        * Late guard: when I become ready after a teammate ranked after me got
          their turn (and has 1000+ TP), I give them their full turn first
          ("GSC: late for my turn -- <name>'s turn is open").
        * Debug "GSC-STOMP: <who> <WS> landed N.Ns after <SC> (step N) -- that
          step was lost." and //aa gsc shows each teammate's learned turn, my
          send-to-land time and the count of lost steps.
        * The "<a> >> <ws> = <sc> (step N)" line also shows my turn number.
v5.52 - aa fight members get onto the next mob faster (Mark, 2026-11-23: "please
        review logs and see if ws/gsc/ EP per hour is working well").
        Review 22:33-22:49, Shadow THF (leader, v5.49) + Myth SAM GK (v5.48) +
        Scrach RDM sword (v5.05), King Ranperre's Tomb, synced ML45: 64 kills/h,
        22.1k EP/h, 111 WS / 10 min, 60% closed a skillchain (Darkness 35 x
        19.4k), 0 deaths / errors. GSC fine. The time sink is at the kill:
        Myth was still engaged on the corpse when Shadow hot-switched, idle 4s
        later and on the next bat 5-7s after Shadow (ENGAGE-LAG 5.0-6.9s every
        mob; 10.1s average over the day); 4 ENGAGE-STUCK today all "f4/2/2/2"
        = cursor on the bat, /attack on twice, still idle, then /assist put the
        cursor on another bat. Shadow's hot-switch hold waits for the party, so
        his first WS came 6-8s after the kill too.
        * aa_party.lua corpse_switch(): watched for 1.2-2.8s like the leader's
          v5.00 hot switch -- dropped out of attack with the cursor on the new
          mob -> /attack on at once; still engaged on the corpse after 0.35s ->
          switch again; idle with the cursor elsewhere -> fast assist may go
          at once (its 1.5-3s same-mob wait is cleared). Log FAST-SWITCH-OK /
          FAST-SWITCH-MISS (debug). party.switch_verify = false turns it off.
        * fast_engage(): /attack on with the cursor on the mob, still idle
          1.2s later -> outgoing 0x01A category 0x02 (Engage), max 2 per mob,
          before the /assist fallback. party.engage_packet = false turns it
          off. ENGAGE-STUCK counts it: f<calls>/<skips>/<atk>/<assist>/<pk>.
        * Tested: Lua 5.1 compile; mock harness (dropped out -> /attack on;
          switch ignored -> sent twice; /attack on ignored -> packet engages;
          cursor lost -> hand-over with the same-mob wait cleared).
v5.51 - aa trade rems: no 255-a-chapter cap any more (Mark, 2026-11-23: "rems
        tales traded over 255 are not lost") -- like Shami, Monisette refuses
        what doesn't fit; the rest stays with you and is reported FULL.
v5.50 - aa trade seals = aa trade crests: both trade every seal AND crest
        (Mark, 2026-11-23: "aa trade seals and aa trade crests (with trade
        both seals and crests)"); beastmen's + Kindred's seals and Kindred's /
        High / Sacred Kindred's crests in one go.
        * Mark: "Shami will not accept past 9999, and extra traded will not be
          lost" -> v5.49's 1-item first trade and the 9999-minus-stored cap
          are gone; what Shami refuses stays with you and is reported FULL
          (a refused mixed trade is still retried one kind at a time).
          Monisette keeps the 255-a-chapter-a-run cap (her behaviour unknown).
v5.49 - aa trade: seals / crests to Shami, Rem's Tales to Monisette (Mark,
        2026-11-23: "let's add a new feature 'aa trade [type]'. For this
        round is focused on trading items to store at stuff npcs").
        * nav.lua: "aa trade seals" (beastmen's + Kindred's seals) / "aa trade
          crests" (Kindred's, High and Sacred Kindred's crests) pulls them out
          of the satchel / sack / case into the inventory, walks to Shami
          (Port Jeuno H-8, <= 50y; Shemo next to him works too) and trades 8
          stacks at a time until none are left. "aa trade rem" / "rems" /
          "rem's": Rem's Tale Ch.1-10 to Monisette (Port Jeuno I-8).
        * Full: a kind he won't take (9999 seals / crests, 255 Rem's Tales
          each) stays with you and AA says so (a refused mixed trade is
          retried one kind at a time to find the full one). Seals / crests:
          the aa nav style list opens -- what Shami holds (read from his and
          Shemo's own words: "When taken together...", "Shami's holding a
          total of...", "That brings your total balance...") + exchanges at
          Shemo, who swaps STORED seals / crests 3 for 1; the suggestion
          (gold, highlighted) is 3000 of the full kind for 1000 of the kind
          you have least of. 2 for 1 during a campaign: AA reads the rate
          from Shemo ("(Maximum: N)" on his number line, "for N of yours",
          his "I'll be takin' N" offer) and then lists 2000 -> 1000.
          "aa trade rate 2|3|auto" sets it by hand.
        * Clicking an exchange: AA walks to Shemo, opens his menu and says
          what to pick and the number to enter (his offer and balances are
          drawn by the game from the menu itself, so with the menu hidden AA
          couldn't check them before the yes); it reads the result, updates
          the counts and keeps the menu answers for a later version.
        * aa trade list | swap <from> <to> [n] (bs, ks, kc, hkc, skc) | stop
          via aa stop. Per character: data/trade_<name>.lua.
v5.48 - Myth's ~19s idle engages: native /assist fallback + ENGAGE-STUCK report
        (Mark, 2026-11-23: "review the fights/gsc/ws of shadow and myth since
        the update ... If changes are needed, document, explain, build, and
        publish").
        * Review 21:07-21:47 (both v5.47, THF + SAM, Locus Dire Bats): 37 kills
          (54-60/h), 58-59% of WS closed a skillchain, Darkness 33-36 / 10 min
          at 17-22k, Fragmentation 1-2 / 10 min (v5.46: 2-3).
          Myth engaged 30 of 36 bats in 1.8-6.7s, but 5 in 18.5-19.9s, idle
          1.8-7.2y from the bat, all after 21:35 -- with 0 target give-ups,
          so v5.47's 20s block was not the cause. Myth's median went 4.1 ->
          3.8 -> 6.9 -> 9.1s over the four 10-min reports.
        * aa_party.lua fast_engage(): after the target packet misses the
          leader's mob once (or /attack on went out twice and we're still
          idle), the next try sends the game's own "/assist <leader>" and
          waits up to 1.2s for the cursor, then faces + /attack on. Off with
          party.assist_fallback = false.
        * ENGAGE-STUCK (members, aa fight): idle 6s (STUCK_SECS) while the
          leader is engaged on its mob -> one local line with everything fast
          assist saw (calls / skips / /attack on / /assist, last reason, lead
          watch state, cursor, <bt>, quiet window, block, main-loop age, the
          game's answer to /attack on), one "aa~g e stuck ..." line to the
          leader (PARTY-EVENT in the leader's log; max one / 15s), and an
          /assist try right away.
        * aa_mob_blocked(id) (autoattack.lua): seconds left on a mob's block.
v5.47 - Myth's 20s engage gaps; GSC look-ahead checks TP (Mark, 2026-11-23:
        "now that I have Rudra's Storm on shadow, please see how myth and I are
        working together" -> "yes please").
        * aa fight members: the leader's mob is never blocked. 11-23 (Shadow
          THF + Myth SAM, Locus Dire Bats): Myth took 18.6-22.7s to engage 10
          of 16 bats, each time idle 1.6-4y from it -- the 20s
          TARGET_GIVEUP_SECS block (target packets + /targetbnpc missed it in
          the pack) also stopped fast assist. aa_block_mob() now skips the
          leader's mob (aa_lead_mob_is() in aa_party.lua: the mob the leader is
          on / acted on in the last LEAD_MOB_KEEP s) and set_target() lifts an
          existing block on it ("TARGET-GIVEUP not done" / "TARGET-UNBLOCK").
        * PARTY-STATS: members send their target give-ups (" t<all>/<leader's
          mob>"); the leader's line reads "target give-ups N (leader's mob M)".
          Older AAs ignore the token.
        * GSC: gsc_follow() (what can follow a step) uses the same TP projection
          as gsc_continuers (v5.04): a teammate under 1000 TP only counts when
          their TP gain gets them there by about a window from now. 11-23: 5
          Shark Bites closed Gravitation as Fragmentation (avg 7k) while
          Rudra's Storm makes Darkness (avg 21.8k), betting on Myth's Light.
v5.46 - aa nav from inside your Mog House: out the door first (Mark,
        2026-11-23: "when in mog house or mog garden, and using 'aa nav', lets be
        dynamic and assume we need to exit. For mog house, it will be the option
        on the door for 'area you entered from' and then ... assume you can find
        a HP/book nearby ... For mog garden, always exit to East Adoulin").
        * nav.lua route(): in your Mog House (not Mog Garden) the only option is
          "out of your Mog House (area you entered from), then a Home Point /
          Survival Guide close by -> <place>"; outside, the carry-on (zone change
          or the Mog House flag going off) works out the rest from where you
          stand. Into the same zone with an NPC: AA looks for it.
        * The door: a menu that opens in the Mog House from anything but the
          Moogle is the door's; your choice there + leaving is learned
          (nav_learned "mhdoor:<zone>" / "mhdoor": menu, option, where you
          stood). Next time AA walks to that spot and answers the door menu.
        * Mog Garden unchanged: always out to Eastern Adoulin (v5.37/v5.38).
v5.45 - aa buy (Mark, 2026-11-23: "lets add an 'aa buy [item or partial item
        name] [qty]' ... most handy for the curio vendor moogle, and green thumb
        moogle, where there are many sub menus of items ... focus this 1st
        version on just stuff that those moogles sell").
        * nav.lua (with the menu code nav already has): every shop list
          (0x03C) that arrives after you pick a menu at a Curio Vendor Moogle or
          Green Thumb Moogle is remembered with the menu steps that opened it
          (data/shops_<name>.lua: item -> slot, price, steps).
        * aa buy scan: at a Curio Vendor Moogle, AA opens menus 1-12 one at a
          time (the menu and the shop window are caught, never drawn) and
          remembers what each holds. Not done at the Green Thumb Moogle (its menu
          also leaves the garden) -- open its shop menus once by hand.
        * aa buy <text> [qty]: picks the item (exact name, or the only match;
          else lists them), checks gil and free slots, walks to the moogle within
          50y, talks to it, opens the menu, buys (0x083, a stack at a time, each
          confirmed by 0x03F), closes the menu, says what it bought. aa buy list
          [text] shows what AA knows. Typed, tell or party (aa_party.lua: "buy").
        * Not yet seen in game: the exact menu option numbers; if scan finds
          nothing, opening each menu once by hand teaches AA the same thing.
v5.44 - aa nav: Warp Ring before Instant Warp, Walk of Echoes by its conflux
        (Mark, 2026-11-23: "please favor Warp Ring before Instant Warp scroll.
        Also, in Walk of Echoes, favor Conflux instead of warp").
        * nav.lua: an Instant Warp row listed above a Warp Ring row (it's
          faster) moves to just after the last Warp Ring row. With the ring on
          its reuse timer / not owned, Instant Warp is used as before.
        * PREFER_EXIT = Walk of Echoes: the Veridical Conflux -> Xarcabard [S]
          ways (then its Home Point, or "then on from there") are worked out even
          when a ring would do, and listed first; rings / Instant Warp after.
        * Examples (test_v544): WoE -> Port San d'Oria: conflux, then Home Point
          (39s) x3, Warp Ring, Instant Warp; PsoXja -> Port San d'Oria: Warp Ring,
          Instant Warp; Ru'Lude far from its Home Points: Home Points, Warp Ring,
          Instant Warp.
v5.43 - aa nav side-steps the post outside the Eastern Adoulin Mog House / Mog
        Garden spawn (Mark, 2026-11-23: "side stepping to the right a little as
        they are walking forward for the 1st 5 yalms would make it smoother").
        nav.lua START_NUDGES: a walk that starts within 6y of (-56,-136) in
        Eastern Adoulin (where the Green Thumb Moogle puts you) bears 35 deg
        right of its goal until it is 5y from where it started, then goes
        straight. More spots can be added to START_NUDGES.
v5.42 - v5.41 fix: home warps still came out on top when nav.via added its way
        (Mark's screenshot, Ru'Lude by Home Point #1 -> "mog garden": Instant
        Warp -> Eastern Adoulin first). The via block (v5.37) re-sorted the list
        after v5.41 had moved them down; that step now runs after it. Same case
        now: Home Point -> Eastern Adoulin #2 then Cunegonde, Survival Guide,
        Home Point #1, then Instant Warp and Warp Ring.
v5.41 - aa nav: Warp Ring / Instant Warp / Warp not on top where a Home Point
        or Survival Guide is (Mark, 2026-11-23: "make sure that Instant Warp or
        Warp Ring or Warp option are not the top option, when there are HPs or
        Books that a player can access in that zone"). nav.lua route(): with a
        Home Point / Survival Guide in this zone the order is usable ways, then
        those home warps, then locked ways. Zones with neither (Walk of Echoes)
        keep them on top when fastest. E.g. Ru'Lude Gardens 216y from the Home
        Point -> Port San d'Oria: Home Point first, Instant Warp 4th.
v5.40 - aa nav list: [X] close lights up (Mark, 2026-11-23: "lets make sure
        'close [x]' is highlighted when cursor is at the top row"). nav.lua: the
        title line's "[X] close" is its own button in the craft GUI's red button
        style (170,20,20, white text); with the mouse on the top line it turns
        lighter (+50) with yellow text. Clicking the top line still closes.
v5.39 - aa nav counts the walk from where a Survival Guide lands (Mark,
        2026-11-23: "'aa nav delivery crate' should take the user to a HP if
        close enough, instead of book > hp > rulude gardens ... wouldn't it be
        simpler to go from Eastern Adoulin HP, to rulude gardens HP#1").
        * Survival Guides (and other warps) have no landing spot in the warp
          data, so the walk from them to an NPC counted 0 and they beat Home
          Points that land much closer. nav.lua land_spot(): the warp data's
          spot, else where that warp stands (nav_zones spots / seen in game).
        * Eastern Adoulin (HP #2) -> Delivery Crate (Ru'Lude -12,120): now
          "Home Point -> Ru'Lude Gardens #1 (+121y walk)" (41s) first; the Survival
          Guide (+197y) is 4th. In Ru'Lude at HP #1 it just walks.
v5.38 - Out of Mog Garden also by the Mog Dinghy to Eastern Adoulin (Mark,
        2026-11-23: "It looks like eastern adoulin is the bottom option from
        Dinghy"). nav.lua: Mog Dinghy (Mog Garden) -> Eastern Adoulin added (and
        allowed to be learned); with garden_exit = 'Eastern Adoulin' the closer
        of the Green Thumb Moogle and the Dinghy is used. First time at the
        Dinghy: pick Eastern Adoulin (bottom option); AA remembers it.
v5.37 - Mog Garden always through Eastern Adoulin, for everyone (Mark,
        2026-11-23: "when exiting the mog garden, lets always choose 'exit to
        east adoulin' ... when going to mog garden, go to eastern adouline HP 2,
        or the book, and then talk to Cunegonde. Make that the default in 'aa
        nav' for all users").
        * nav.lua: Cunegonde (Eastern Adoulin -56,-130) -> Mog Garden (menu
          learned the first time).
        * nav.via['Mog Garden'] = {default = 'Eastern Adoulin / Cunegonde'} (no
          per-character entries; "<zone> / <NPC>" is new). With a preference only
          that way in is used: other ways in (Mog Dinghy, Mog Houses, Dangueubert)
          are left out; warps that land you somewhere first stay (the trip
          carries on). Your way is added even when another way is right where
          you stand (Port San d'Oria -> Home Point to Eastern Adoulin #2, then
          Cunegonde).
        * nav.garden_exit = 'Eastern Adoulin': out of Mog Garden only by the
          Green Thumb Moogle ('' = the Mog Dinghy too).
v5.36 - Shadowhammer goes into Mog Garden through Eastern Adoulin (Mark,
        2026-11-23: "since eastern adoulin has HP and book close by, I will use
        that now on for my mog garden entrance"). nav.via['Mog Garden']
        Shadowhammer = 'Eastern Adoulin' (was Port San d'Oria) in nav.lua's
        defaults and aa_config_defaults.lua.
v5.35 - aa nav out of Mog Garden by its own ways (Mark, 2026-11-23: "'aa nav'
        when player is in mog garden should first be to exit mog garden via
        dinghy or green thumb moogle, not warping out").
        * nav.lua: NO_WARP_OUT = Mog Garden: no ring / Instant Warp / Warp spell
          options from there (v5.32 "Warp Ring home" included).
        * Mog Dinghy in Mog Garden (-17,-24) -> Port San d'Oria / Port Bastok /
          Port Windurst as ways out (menu learned the first time; only those
          three are learned). With the Green Thumb Moogle -> Eastern Adoulin,
          the fastest of them wins (e.g. Ru'Lude: Green Thumb -> Eastern Adoulin,
          then Home Point; Port San d'Oria: the Dinghy).
v5.34 - aa nav walks around things in the way (Mark, 2026-11-23: "there is a
        BOX obstruction in the way to getting to Dangeuebert, so we need to walk
        wide to the right instead of straight to the NPC").
        * nav.lua: walking to a warp NPC, not 1y closer in 1.5s = stuck: turn
          right 70 deg for 2s, 90 deg 3s, 90 deg 5s, then left (70/90/90 deg,
          3/5/8s); then "walk there and AA warps (and remembers the way)".
        * A walk that needed a way around -- by AA or by you -- is saved as a
          path (points every 4y, data/nav_learned.lua "path:<zone>:<NPC>") and
          followed point by point next time (from the point nearest to you).
        * Test (box between Western Adoulin HP #2 and Dangueubert): first walk
          14s with two right turns, path learned; second walk 9.5s, no stops.
v5.33 - aa nav: Mog Garden ways + per-character preference, ring cooldowns
        (Mark, 2026-11-23: "When in walk of echos, and asked 'aa nav mog garden',
        first I would expect to use warp ring ... vertical conflux back to
        Xarcabard (S) would be the option if warp ring is on cool down ... my
        preferred mog garden is Port Sandaria, using the Dingy ... we probably
        need a config for this, or show all the options").
        * nav.lua: Mog Dinghy (Port San d'Oria / Bastok / Windurst) and the Mog
          House Moogle (towns, Jeuno, Whitegate, Adoulin) -> Mog Garden; menus
          learned the first time, a moogle's choice is tried in every town.
        * nav.via (aa_config nav block): per character the zone to go through,
          e.g. Mog Garden: Shadowhammer Port San d'Oria, Mythrandiir Eastern
          Adoulin, Scracheebrat Southern San d'Oria. Those ways come first,
          marked [your way]; the rest stay in the list.
        * Warp Ring home is also offered toward places without a Home Point
          (Walk of Echoes -> "Warp Ring -> Port San d'Oria, then talk to Mog
          Dinghy").
        * Ring / Instant Warp reuse: every use is noted (action packet, also
          aa warp and by hand; kept in data/nav_<name>.lua "used") and the item
          is left out until its recast (600s) is over. A ring that didn't go off
          is marked used and nav tries the next way (Walk of Echoes: conflux).
        * Warp NPC spots AA has seen are used when the warp data has none
          (Xarcabard [S] Home Point #1): 11-23 17:30 nav arrived in Xarcabard
          [S] before the Home Point had loaded and went back to Walk of Echoes.
          Exits back to the zone you just left aren't offered for 3 minutes.
        * The Walk of Echoes / Xarcabard [S] Veridical Conflux menu no longer
          overwrites the Abyssea unlocks (Shadowhammer's abyssea unlocks were
          cleared once; the next real Abyssea conflux reads them again).
v5.32 - aa nav: Walk of Echoes via Xarcabard [S], Warp Ring home from a zone
        with no warp (Mark, 2026-11-23: "go to xarcabard (S), go to the
        veridical conflux nearby, buy a kupofried medallion for 1000gil, then
        use the veridical conflux to enter Walk of Echoes"; "if I am in some
        zone without a book or warp ... use the warp ring to take me back to a
        HP").
        * nav.lua: Veridical Conflux Xarcabard [S] (239,-248) -> Walk of Echoes
          and back (Walk of Echoes (-420,-38) -> Xarcabard [S]) as zone-moving
          NPCs; menus learned the first time.
        * Key item to buy (NEED_KI: Kupofried's medallion, id 1599, 1000 gil):
          without it AA replays the learned buy choice, waits for the key item,
          talks again and goes in; a buy-and-enter menu of several steps is
          learned as one sequence (seq). Short on gil: it says so and stops.
          First time: "buy ..., then pick Walk of Echoes; AA remembers both."
        * Menus of several steps (update choices, then the final one) are now
          recorded and replayed (data/nav_learned.lua seq = "menu,opt,unk,auto;...").
        * A Veridical Conflux outside Abyssea is no longer taken for an Abyssea
          warp (devices and learning).
        * No warp NPC in your zone: Warp Ring / Instant Warp / Warp / Warp II to
          your Home Point, then the Home Point there (when it has a Home Point
          to the destination), e.g. "Warp Ring -> Ru'Lude Gardens, then Home
          Point -> Southern San d'Oria".
v5.31 - aa nav in-zone warp to the NPC, aa stop stops everything, craft-style
        nav rows (Mark, 2026-11-23: "interact with the yellow escha warp point
        and go to point #8, as that is the portal / point where emperox is";
        "'aa stop' should stop all aa loops and actions, such as nav, follow,
        fighting, etc."; "make the row highlights on the GUI for nav look like
        it does in CRAFT GUI").
        * nav.lua: arriving in the NPC's zone, AA checks for an in-zone warp
          that lands closer (Eschan Portal #8 is ~11y from Emporox) and uses it
          when that beats walking; when an in-zone warp is done ("at ...") it
          finds the NPC. Also when you start in Reisenjima.
        * aa_party.lua stop_everything(): typed //aa stop and tell / party
          "aa stop" now stop at once: aa nav, follow and aa fight (following,
          stacking, fight spot), a running sequence (not aa update), a warp
          ring waiting (ring put back), and the fight. Tell / party used to
          finish the current fight first. The "aa stop" nav sends itself before
          a warp (aa_nav_guarded) still stops only the fight.
        * nav list: each clickable line is its own box (24,24,36, text
          225,225,225); under the mouse +50 and white text -- the craft GUI's
          list style. Replaces the v5.25 blue bar and >> <<.
v5.30 - aa nav: Escha / Abyssea entrances reached by ring or warp first (Mark,
        2026-11-23: "'aa nav empor' is telling me to go to Wooden Shutter instead
        of equiping and using my Dim Ring").
        * Emporox stands in Reisenjima, which no zone line reaches -- only the
          Dimensional Portal at a crag. nav.lua only used an entrance when it
          was in the zone you stood in, so from N. Sandy nothing matched and the
          last-resort "leave by the nearest way out" (v5.23) picked the Wooden
          Shutter to Carpenters' Landing.
        * route(): when nothing gets you straight there, it now also looks for
          Escha / Abyssea entrances that lead to the zone (built-in list +
          learned ones) and offers every way to the entrance's zone, e.g.
          "Dim. Ring (Dem) -> Konschtat Highlands, then talk to Dimensional
          Portal". On landing AA carries on by itself and uses the portal.
        * Entrance spots (ENTER_SPOTS): crag Dimensional Portals and Cavernous
          Maws in La Theine / Konschtat / Tahrongi, so AA can head for the
          portal before it has loaded (La Theine's portal spot is estimated; a
          portal AA has seen in game, data/nav_npcs_seen.lua, wins).
v5.29 - Plain PULL roams; only aa fight has a fight spot (Mark, 2026-11-23:
        "when in PULL mode and not 'aa fight' I don't want the script to be
        moving me back to a starting point.. I want to float around and move
        to different rooms / floors").
        * v4.81 saved a fight spot (ANCHOR) on every //aa pull that had none,
          so the puller ran back to where pull was typed between mobs and
          mid-fight. Removed: //aa pull, "aa pull" by tell / party chat no
          longer save one. aa fight still saves the leader's spot and returns
          to it, as before.
        * A //aa pull after aa fight still ends fight mode and clears the spot
          (unchanged, aa_party.lua leave_fight_mode).
        * STEP-BACK (v4.37: back to where you stood a moment before an
          emergency step-in) is unchanged -- it's a few yalms, not a start spot.
v5.28 - Group skillchain for Shadow THF + Myth SAM (Mark, 2026-11-23: "I
        already have Shark Bite. Is there an issue where it was not detected?
        Any changes needed to AA to work better for Shadow THF myth SAM?").
        Review 02:36-09:44 (bats; 322 kills, ~52/hr): Myth's Shoha / Kasha
        closed Compression 668 times for 2.3k (35% of his WS) in a Transfixion /
        Compression loop with Evisceration; Darkness / Light average 20.5k.
        * Shark Bite was never used: group_skillchain.pools['Dagger'] didn't list
          it (GSC only uses pool WS the character knows). Added (built-in,
          aa_config.lua, aa_config_defaults.lua).
        * Skillchain damage learned per level for each closer (key "WS#1",
          "#2", "#3", "#E" = Light on Light), used before the one all-level
          figure. Evisceration's single figure (43k Light-equivalent, from 13k
          Transfixions / 0.25) priced its Darkness at 43k; real 20.6k.
        * New group_skillchain.min_sc (default 5.0k): a level-1 skillchain
          predicted under it is skipped -- the player saves TP for Fudo
          (Darkness) / Kasha (Light) on the next opener. Not at tp_cap.
          Debug: "GSC: <name> skips <WS> (Compression, ~2.5k) -- saving TP".
        * Per-level figures are learned on each PC (not sent in sync lines).
        All four AAs need v5.28 (each AA picks its own player's WS).
v5.27 - Level Sync off didn't work (Mark, 2026-11-23 09:03: "sync didn't work").
        09:01 log: v5.26 sent "Level Sync off" with the leader's own name; the
        game never answered (no "will be deactivated in 30 seconds") and AA gave
        up after 45s. The party menu sends it with the designee's name.
        aa_party.lua:
        * The designee is read from the party list packet (0x0DD Flags bit
          0x100, LevelSyncFlg) and kept in P.sync_who (also after a reload).
        * "Off" goes out with the designee's name; if unknown, each player's
          name in turn (then our own), 3s apart, until the game's 30s notice.
        * If the game ignores every try, AA says so and points to the party menu.
        * aa unsync uses the same and replies with the result.
v5.26 - aa sync when a Level Sync is already on (Mark, 2026-11-23: "aa sync
        shadow" kept failing). Myth's sync from 02:32 was still on, so the game
        answered "Level Sync could not be activated ... a status which prevents
        synchronization" while AA still said "Level Sync set to Shadowhammer".
        aa_party.lua (aa sync and aa invite ... sync <n>):
        * Same designee already synced -> "Level Sync is already on <n>."
        * Another sync on -> AA sends Level Sync off, waits for it to end (the
          game takes 30s), then syncs to the new designee.
        * The game's own answer decides the reply: "set" only after "Level Sync
          activated / master level restricted"; a refusal with no sync visible
          tries "off" once, then reports a blocking status (Level Restriction).
        * aa unsync notes the game takes 30s to end it.
v5.25 - aa nav list: stronger row highlight (Mark, 2026-11-23: "I need a better
        highlight for the rows.. the dingy yellow is hard to see"). The bar under
        the mouse is now a strong blue (alpha 190) and the line's text turns
        bright white with ">>" in front and "<<" at the end. Colour:
        nav.gui.highlight = {alpha, red, green, blue}.
v5.24 - aa nav: out of Mog Garden always to Eastern Adoulin (Mark, 2026-11-23:
        "when you choose the option 'return from whence you came' to exit mog
        garden, you will go back to whatever zone you came from ... it might be
        best to always exit the mog garden (when aa nav does it) by going to
        eastern adoulin, as there is a HP and Book and Waypoint close by").
        * Mog Garden's way out is now the Green Thumb Moogle -> Eastern Adoulin
          (the Mog Dinghy is no longer offered). The first time its menu shows:
          pick Eastern Adoulin (not "return from whence you came"); AA remembers
          that choice and answers it itself from then on.
        * From the Green Thumb Moogle only Eastern / Western Adoulin are ever
          learned -- "return from whence you came" changes with where you came
          in, so it is never kept as a route.
        * Destinations too far to plan in one go from there: "talk to Green Thumb
          Moogle -> Eastern Adoulin, then on from there" -- the trip carries on
          from Eastern Adoulin's Home Point / Survival Guide / Waypoint.
v5.23 - aa nav: out of Mog Garden (Mark, 2026-11-23: "when in mog garden, it tells
        me 'no known route' to king ranperre tomb. We can exit the mog garden via
        the dinghy or via the Green Thumb Moogle, and then continue from there").
        * A zone with no warp, no zone line and no known route out (Mog
          Garden) offers its ways out: "talk to Green Thumb Moogle (here) -> out
          of Mog Garden, then on from there [you pick]" and the Mog Dinghy. AA
          walks you to it and talks to it; you pick where to go; AA learns that
          choice (v5.22) and the trip carries on from wherever you land.
        * After that the learned way out is a normal route: "talk to Green Thumb
          Moogle -> Southern San d'Oria, then ...". Learned routes now also keep
          where they put you, so the next warp is picked by walking distance.
v5.22 - aa nav learns every route you use by hand (Mark, 2026-11-23: "lets learn
        all the routes... from Mog House, from Mog Dinghy, and from Adoulin
        west and east" -- after "why ... only the western adoulin garden, and
        not the mog garden from Port Sandoria?").
        * Any menu choice at any NPC or object that is followed by a zone change
          within 30s is remembered as a route (data/nav_learned.lua: NPC, its
          spot, the menu choice, and whether it was inside your Mog House) and
          used from then on like the routes from the server data -- the Mog House
          moogle into Mog Garden, the Mog Dinghy, the Adoulin NPCs, anything the
          data misses. Home Points / Survival Guides / Waypoints etc. are left
          out (nav already drives those).
        * Mog House routes: from outside, the step is "go into your Mog House"
          (nav lands you at that city's Mog House Home Point); once you are in,
          AA carries on and talks to the moogle for you. Entering / leaving the
          Mog House counts as a step even when the game doesn't zone.
        * //aa nav routes lists what was learned; //aa nav forget <name> drops a
          wrong one (a quest cutscene that moved you, say).
v5.21 - aa nav list: [X] close (Mark, 2026-11-23: "yes, add X"). The title line
        ends in "[X] close"; clicking the title line closes the list (it is
        highlighted like the other lines). A new //aa nav search still just
        replaces the list; //aa nav close works as before.
v5.20 - aa nav list pages (Mark, 2026-11-23: "when there are more items that can
        show in the default GUI, we need to make a way to see the others below
        by scrolling, or by clicking next page"). More than nav.max_rows (14)
        results: the list shows a page at a time with a bottom line
        "<< prev  page 1 of 3 (9 found)  next >>". Mouse wheel over the list
        (up = previous, down = next), click the left / right half of that line,
        or //aa nav next | prev. Line numbers stay the same across pages, so
        //aa nav 17 still picks result 17.
v5.19 - aa nav: aa stop stops it; your own "/p aa nav" opens the list; row
        highlight as a bar (Mark, 2026-11-23: "aa stop is not stopping the
        navigation. Also, when doing 'aa nav garden' it should popup a GUI with
        all the options, and then let you select. It didn't list mog garden at
        all, but tried to take me straight to RuAun gardens" and "lets focus on
        highlighting the background for the row").
        * aa stop (typed, /p or /tell) now also stops aa nav: walking to a warp,
          waiting for one, a warp in progress, a trip with more legs, looking for
          an NPC ("nav stopped."). The "aa stop" nav sends itself to stop the
          fight loop before travelling doesn't count.
        * "/p aa nav garden": the one who typed it gets the list (Ru'Aun
          Gardens, Ru'Lude Gardens, The Garden of Ru'Hmet, Mog Garden -- via
          Western Adoulin and Dangueubert -- ...) and picks; the pick goes to
          the party as "aa nav #<code>" so everyone goes to the same place.
          The others go on a name by themselves only when it is clear (one
          match or an exact name, "/p aa nav mog garden"); otherwise they wait
          for the pick ("12 matches -- waiting for Shadowhammer to pick one").
          Typed //aa nav is unchanged (list, pick for yourself; right-click =
          party).
        * The highlighted line now gets a coloured bar behind it (gold,
          see-through; nav.gui.highlight = {alpha, red, green, blue}) plus the
          ">" in front, instead of yellow text.
v5.18 - aa nav: NPCs found by what they are (Mark, 2026-11-23: "Funtrox is a
        Gobbie mystery box NPC, so I should be able to search mystery and find
        the gobbie mystery box NPCs").
        * nav_npcs.lua now has what each NPC is / does, for 2,863 of the 8,986
          NPCs: the comment at the top of its script in the Topaz server
          project ("Gobbie Mystery Box", "Tenshodo Merchant", "Chocobo
          Renter", "Starts and Finishes Quest: ...").
        * aa nav matches the name OR that text: "aa nav mystery" lists every
          Gobbie Mystery Box NPC (Funtrox, Specilox, Mystrix ...), "aa nav
          tenshodo" the Tenshodo merchants. The list shows it in brackets:
          "Funtrox [Gobbie Mystery Box] (Windurst Woods)". NPCs seen in game
          get the same text by name.
v5.17 - aa nav list: the line under the mouse is highlighted (Mark, 2026-11-23:
        "I can't really see what item I am selecting in the GUI that opens..
        can we highlight the row that is hovered over?"). The line under the
        mouse turns bright yellow with a ">" in front; moving off the list
        clears it. Click as before.
v5.16 - aa nav: walking the last bit keeps the goal (Mark, 2026-11-23: "I
        selected curator moogle at chateau, and it got me into the chateau,
        but then didn't continue to guide me or try to target the curator
        moogle inside"). From Lower Jeuno it warped to N. San d'Oria #2, and
        the next step was walking into the Chateau -- a "walk" step ended the
        trip, so nothing was waiting when you walked in.
        * A walking step keeps the trip going: AA tells you where the way into
          the next zone is (distance, direction, X / Y, every 5s) and carries
          on after the zone change -- in the Chateau it then guides you to the
          Curator Moogle and puts the cursor on it.
v5.15 - aa nav: more ways to target an NPC; progress on your own screen; 5s
        updates (Mark, 2026-11-23: "still it is unable to target ghebi. Also,
        when doing the command we should not do updates to the process to the
        Party Chat ... Also ... once in the right zone, there should be updates
        more often ... lets do 5s").
        * Targeting tries, in turn: the target packet, /target "<full name>",
          /target <first name>, turn + /targetnpc -- each logged at level 2
          ("NAV: target Ghebi Damomohe (25y) by name: cursor on ...") so the
          log shows which one the game takes. It keeps trying every 2s while
          the NPC is within seek_range (no more giving up after 3 rounds), and
          a cursor you put on it yourself counts too.
        * "/p aa nav ...": every AA's progress (going / walking / arrived /
          where the NPC is) is shown in that player's own chat window only --
          nothing goes to party chat any more. A /tell is still answered by tell.
        * Where the NPC is: every 5s (nav.seek_every) instead of 15s.
v5.14 - aa nav: NPC targeting checked (Mark, 2026-11-23: "aa is telling me that
        ghebi is targetted, but I am not seeing that"). v5.12 sent the
        injected target packet (0x058) and said "targeted" without looking;
        on NPCs that packet often doesn't move the cursor (the same miss
        v4.30 found on mobs).
        * Now: target packet, then turn toward the NPC + /targetnpc, taking
          turns, up to 6 tries 0.6s apart, and only "targeted" once the cursor
          really is on it. Otherwise "could not put the cursor on <name> -- it
          is Ny <dir> of you (trying again)" -- 3 rounds, 8s apart.
v5.13 - aa nav: warps that haven't loaded yet after zoning (Mark, 2026-11-22:
        "when I ran into range of HP#2 it didn't interact and warp me to the
        next zone"). After Faurie, the trip carried on 8s after zoning, but
        the Home Points of Northern San d'Oria weren't loaded yet (AA saw the
        zone's NPCs 12s in), so nav found no warp and told you to walk to
        Southern San d'Oria instead; walking up to HP #2 then did nothing.
        * Warps not loaded yet count from where the data says they stand
          (Home Point / Waypoint spots from the warp data, Survival Guide /
          Unity / Proto-Waypoint spots from the NPC data). AA walks toward the
          spot (50y rule), picks the NPC up the moment it shows, and warps.
        * The same for zone-moving NPCs not seen yet (Faurie ...): their spot
          comes from the NPC data instead of "can't see".
        * Standing on the spot before the NPC shows: AA waits there (arm_timeout).
v5.12 - aa nav: trips with legs, finding NPCs (Mark, 2026-11-22: "I am getting
        'no known way to ghebi damonohe' ... unable to get me out of the
        Chateau ... doesn't know that chateau goes to North Sandy, and then to
        HP which can take me over to the Lower Jeuno" and "if nav is run on an
        NPC/Object ... look for it and then put the cursor on them ... If the
        NPC is in the zone and too far away to target, advise them what the POS
        is and which direction to walk").
        * Two-leg routes: with no warp in your zone (Chateau), nav leaves by an
          NPC (Faurie) or on foot into a zone next door, then uses a warp
          there -- the one nearest to where you arrive. "talk to Faurie (here)
          -> Northern San d'Oria, then Home Point -> Lower Jeuno #2". Warp NPC
          spots the warp data lacks (Survival Guides, Unity, Proto-Waypoints)
          come from the NPC data (nav_zones.lua "spots").
        * A trip carries on by itself after each zone change (up to 3 legs,
          8s after zoning): "carrying on to ...". aa nav cancel stops it.
        * NPCs / objects: once you are in its zone (or already were), AA says
          how far, which way (north-east ...) and its X / Y, every 15s, and
          puts the cursor on it as soon as it is within nav.seek_range (40y):
          "Ghebi Damomohe is targeted -- 30y north of you". Gives up after
          nav.seek_timeout (600s) or when you leave the zone.
        * Party lines for NPCs carry the name (#n<zone>:<x>:<y>:<name>), so
          every AA finds it at the end.
        * Search: nothing found for the name as typed -> every word's first 4
          letters ("ghebi damonohe" finds Ghebi Damomohe).
v5.11 - aa nav: NPCs that move you to another zone (Mark, 2026-11-22: "can
        'nav' include movement NPCs that you use to get into / out of zones
        such as those like Faurie who is in Chateau D'oraguille, who you need
        to interact with to get out of the zone?" -- "yes please").
        * New file nav_transports.lua: 120 zone-moving NPCs (exit NPCs, gates,
          Postern, Runic Seals, Cermet Doors, Afdeen, Kaduru-Haiduru, Shihu-
          Danhu ...) read from the Topaz server project's NPC scripts (the
          event that ends in "send to zone X"): NPC, its spot, where it puts
          you, its menu and choice. tools/nav/mine_transports.py rebuilds it.
        * aa nav uses them: "talk to Faurie (here) -> Northern San d'Oria". AA
          walks you to the NPC (the 50y rule), talks to it and answers its menu
          itself. It also routes through them: Bastok -> Abdhaljs Isle =
          Home Point -> Upper Jeuno #3, then talk to Afdeen. No "walk" line
          where an NPC is the only way out (Chateau).
        * 26 NPCs whose script only looks at the menu and the choice are
          answered automatically, and only when the menu number matches the
          script's. The rest (key items, quests, several places on one choice)
          show their menu the first time ("[1st time: you pick]"): you pick,
          AA remembers it in data/nav_learned.lua and answers it from then on.
          Choices you make by hand at any of these NPCs are learned the same
          way when a zone change follows within 30s.
v5.10 - aa nav: warp inside your own zone toward the way on (Mark, 2026-11-22:
        "I am using 'aa nav chat' and currently in North Sandoria HP#1, and its
        not taking me to HP #2 which is right next to chateau").
        * Going to a zone with no warp (Chateau d'Oraguille) from the zone
          next to it, the Home Points / Waypoints of the zone you are in were
          never looked at -- only "walk" was offered. Now they are: from N.
          San d'Oria HP #1, aa nav chat = Home Point -> Northern San d'Oria
          #2, then walk in (~16s against ~44s walking).
        * With a known way into the next zone, the walk to it is counted from
          the real distance (from you, or from where the warp lands) plus 5s,
          instead of a flat 90s per zone; only zones after that are guessed.
          Standing by the gate, walking still wins.
v5.09 - aa nav walks you to a warp NPC that is close (Mark, 2026-11-22: "if
        the player is within 50 yalms of the hp/book/waypoint, its okay to
        walk them there so they are in range to use it").
        * The chosen warp NPC is farther than device_range (6y) but within
          nav.walk_range (50y): AA runs straight at it, stops 4y from it and
          warps. Farther than that: as before, the list says how far, you walk
          and AA warps once you are in reach.
        * The walk stops (and leaves the rest to you) when it isn't 1y closer
          after 5s (stuck on a wall), when you fight / rest / mount, on aa nav
          cancel, on a new aa nav and on zoning; arm_timeout (120s) still caps it.
        * Version numbers: every change gets its own version from here on
          (Mark: "we need to update version numbers with each change") --
          v5.07 and v5.08 below were first shipped inside v5.06.
v5.08 - aa nav: the warp that lands closest to the way on (Mark, 2026-11-22:
        "why would going to chateau take me to north sandoria #1 instead of
        #2 that is right next to chateau").
        * A zone without a warp
          is reached through the zone next to it, and every Home Point there
          counted the same, so #1 won by name. nav_zones.lua now also knows
          where each zone's way into the next zone is (from the zone-line
          data: where you arrive coming the other way; the Chateau gate added
          by hand), and the warp that lands closest to it wins -- Chateau ->
          Northern San d'Oria #2, then walk in.
v5.07 - aa nav: zones with no route listed, NPC search (Mark, 2026-11-22,
        first try from Dynamis - Tavnazia: "not finding a match for 'curator
        moogle' nor 'chateau d'oraguille'").
        * A zone that matches is always listed, also with no route
          from where you are ("no warp or walking route known from here").
          Chateau d'Oraguille <-> Northern San d'Oria and Heavens Tower <->
          Windurst Walls added to the zone links. New NPCs section: about 9,000
          NPCs with zone and spot (nav_npcs.lua, from the Topaz server project,
          read only while searching) plus every NPC AA sees in game, kept with
          its spot in data/nav_npcs_seen.lua (checked every minute) -- so newer
          NPCs (Curator Moogle ...) show up once you have been near one. The
          best warp for an NPC is the one that lands closest to it ("+Ny walk").
v5.06 - aa nav: travel anywhere the fastest way (Mark, 2026-11-22: "aa nav tar
        would search for all locations name %tar% and then popup a menu with
        the fastest warp/book/adouline warp crown method to get there").
        New files nav.lua (search, list, warps), nav_maps.lua (warp data from
        SuperWarp by Akaden, BSD licence; SuperWarp itself isn't needed) and
        nav_zones.lua (which zones connect).
        * //aa nav <text>: every zone and place (Auction House, Mog House,
          Adoulin districts ...) with <text> in its name, each with its
          fastest way from where you stand, in a list on screen. Left-click a
          line (or //aa nav <n>) to go; right-click (or //aa nav p<n>) sends
          "/p aa nav ..." so every AA in the party goes there its own fastest
          way. //aa nav party <text> and "/p aa nav <text>" do the same.
        * Ways: Home Points, Survival Guides (gil first, tabs only when under
          200 gil), Waypoints, Proto-Waypoints (always last), Unity, Escha /
          Reisenjima, Abyssea, Runic Portals, Campaign, Voidwatch, Warp Ring,
          Dim. Rings, Tavnazian Ring, Instant Warp, Warp / Teleport / Recall.
          Fastest first (walk to the warp + menu + zoning + ~90s per zone still
          to walk); cost doesn't count.
        * A zone with no warp: the nearest zone that has one, plus how many
          zones to walk. Warp too far away: the list shows how far; walk there
          and AA warps once you are within 6y (aa nav cancel stops it).
        * The warp itself: AA talks to the NPC and answers its menu with
          packets (SuperWarp's packet steps), so the menu never shows. It
          stops AA first, dismounts, and answers the sender: going / arrived /
          why not.
        * Rings go on the RIGHT ring like aa warp (aa_nav_ring in
          aa_party.lua: equip ring2, gs disable ring2, warp_ring_delay, use,
          old ring back after the zone).
        * Unlocks: read from the first warp menu of each kind you open (by
          hand or by nav) -- one Home Point gives every Home Point -- and kept
          in data/nav_<name>.lua. Unknown = treated as unlocked; a locked warp
          is cancelled cleanly. Where Warp Ring / Warp take you is learned
          the first time (aa warp counts too). //aa nav unlocks shows it.
        * aa update: nav files are listed as "nav=" in manifest.txt (v5.05 and
          older skip those lines). If they're missing after an update, AA
          downloads them once at load.
        * Settings: nav = {...} in aa_config.lua (defaults in
          aa_config_defaults.lua): list position, rows, run speed, zone /
          hop seconds, use_tabs, hide_locked ...
v5.05 - aa fight: no following; leader changes (Mark, 2026-11-22: "we dont
        want constant auto-follow on the leader, just an 'aa stack' once a
        fight. Shadow change leader to myth, then left the party, and all the
        players are still following shadow").
        * aa fight members no longer follow the leader between fights. They
          stack on the leader when aa fight starts, once after each kill
          (stack_after_kill), and when they drift mid-fight (stack_watch /
          stack_on_oor, unchanged). aa follow still follows.
        * Leader changed: members switch to the new leader (assist + stacking)
          after it holds 2s. The new leader stops stacking on anyone and keeps
          assisting ("aa fight" makes it pull). Leader left with no new leader
          / party gone: fight mode ends, everyone stays where they are.
        * aa follow stops when the followed player leaves the party.
v5.04 - Group skillchain: don't wait for a teammate who can't make it (Mark,
        2026-11-22, Vayne back as DRK: "see how the damage is doing ... If
        changes are needed, please build and publish").
        * A teammate keeps a continuer place from 500 TP (block_tp) because
          their TP is seen late. With Vayne on a great sword (slow TP), Shadow
          held for "Vayne continues Upheaval with Spinning Slash / Power Slash"
          141 times in 95 min; Vayne made the WS 33 times, someone else went
          after a median 5s 101 times, nobody 7 times.
        * AA now tracks each player's TP gain per second from the party list.
          A teammate under 1000 TP keeps their place only when that rate gets
          them to 1000 before the chain window closes (minus ws_lead). No rate
          yet (just joined) -> the old rule. group_skillchain.tp_project =
          false turns it off. Debug line: "GSC: <name> at <tp> TP (+N TP/s)
          won't reach 1000 before the window closes -- not waiting for them."
        * Fix: a group_skillchain or party setting set to false was read as
          "not set" and got its default (true) -- e.g. nuke_hold = false,
          burst = false, stack_after_kill = false, stack_on_oor = false,
          auto_accept = false had no effect. No current config file sets any
          of these to false, so nothing changes until one does.
v5.03 - Engage timing fix (Mark, 2026-11-21: "fix for joining-timing, yes";
        no change to stacking -- full stack, equidistant from mobs coming from
        any direction).
        * The leader's ENGAGE-LAG / ENGAGE summary now times each member from
          the leader picking the mob to that member's FIRST action on it
          (melee round, WS, spell, JA, casting), recorded the moment the
          action arrives. v5.00-5.02 used the member's latest action at
          whatever moment the main loop checked, so a late check showed
          18-20s for members who had been swinging for most of that time
          (v5.02 log: "19s" bats where Myth landed 12-17 melee rounds).
        * The "where were they" snapshot (debug 2) is only taken 3-6s in and
          says how many seconds in it was taken.
v5.02 - Stack after every kill; members follow the leader's target; Level
        Sync notice (Mark, 2026-11-21: "when in 'aa fight', do a stack after
        every kill, because players are sometimes getting separated").
        * aa fight members run onto the leader's exact spot after every kill
          of the mob they were fighting when they are more than
          stack_kill_min (0.5y) away and within stack_kill_max (30y). From
          the v5.01 log: Myth stood 1-2y off the stack 71% of the time (the
          re-stack only fired past 2y), his melee was "out of range" at a
          median 4.2y, and he landed 0 melee rounds on 29 of 155 bats.
        * Melee "out of range" while engaged and more than 0.5y from the
          leader -> stack now (stack_on_oor, at most every 5s).
        * Members follow the leader's target as soon as it changes (the
          leader's own target, read every 0.25s), not only when the leader
          acts on it -- the v5.01 log had members idle 3s in, 0-4y from the
          bat, on 108 bats (4-18s to engage).
        * Fast assist on the leader's mob ignores the post-kill quiet window
          (the mob is alive), retries after 1.5s instead of 3s, and can't get
          stuck "busy".
        * Level Sync wearing off is announced (L1): on 11-21 Vayne leaving
          ended the sync and EP per kill fell ~27% (about 470 -> 340).
v5.01 - More detail in the debug log (level 2 only) (Mark, 2026-11-21:
        "More detail in the logs is fine, for debug level 2 only"; no
        movement changes; hot-switch hold unchanged).
        * ENGAGE-LAG lines: how each member got on the mob (swing / WS /
          spell / JA / engaged), and for a slow member (over 5s) where they
          were 3s in: idle / engaged on another mob / engaged on it, and how
          far from the mob.
        * MELEE-ROUNDS line per mob: melee rounds (hits and misses) each
          player put on it while it was the leader's target, and how long --
          shows lost swings without the others' melee in the chat log.
        * Members' "out of range" counts split into melee / WS with the
          median distance, in the PARTY-STATS lines ("m" token on the hidden
          stats line; older AAs ignore it).
v5.00 - Faster party engage, hot-switch, targeting, magic bursts, learning
        (Mark, 2026-11-21, after the v4.99 report: "lets build all that").
        * Members (aa fight, ASSIST): fast assist ignored the leader's Provoke
          when it came while they were still engaged on the dead mob, and the
          leader's hot-switch hold then sent nothing for 6-8s -> members took
          5-9s (median) to join each bat. Now they remember the leader's mob:
          still engaged on a corpse -> switch to it at once (FAST-SWITCH),
          idle -> attack it (checked every 0.25s for 20s).
        * Hot-switch hold also releases (after 1s) once every party player in
          range is engaged on the mob or has acted on it (Mark OK'd it).
          Solo with Trusts: unchanged.
        * Engage timing: the leader counts a member's first action on the mob
          (melee, WS, spell, JA) or engaging it, whichever is first; members'
          slow reasons say "last mob" (still on the dead one) and "idle"
          instead of "other".
        * Hot switch: watched every 0.1s. Cursor on the new mob but dropped
          out of attack -> /attack on at once; still on the corpse after
          0.35s -> the switch is sent again (391 of 605 were "misses" on
          11-21, most of them the first kind).
        * Purple mob: skipped for 60s; the rescue only attacks once the cursor
          is really on the new mob. A mob that target packets and the
          /targetbnpc fallback both missed is skipped for 20s (11-21 10:53:
          19s spent retargeting one bat).
        * Magic bursts: every element the skillchain carries (Light = fire /
          lightning / wind / light, Fusion = fire / light ...), a 7s window
          (was 3s), the strongest ready spell (weakness element first on a
          tie). group_skillchain.burst = true turns bursting on for filler
          jobs while GSC is active (Scrach's mb_enabled stays false in his own
          file); group_skillchain.nuke_hold = true holds weakness nukes while
          a chain step is live on the mob so they land as bursts.
        * Learning: the TP each player had at the WS is tracked; a low sample
          is only thrown out against samples at similar TP (tp_band 500,
          band_min 5) -- low-TP Upheavals are real.
v4.99 - Party stats, events and report over party chat (Mark, 2026-11-21:
        "we won't be able to consistently get the actual physical log files
        from the other computers ... use party chat to send updates from the
        other clients over to shadowhammer and vice versa").
        * Every AA sends a hidden "aa~g s" line every 10 minutes: its own
          engage time after the party leader picks a mob, with why when it
          took over 5s (other mob, casting, mob coming, far, dead, AA off),
          WS landed / missed / interrupted, out of range and can't see
          messages, deaths, errors and learned samples not yet in the master.
        * "aa~g e" right away for a death, an error ("... error: " /
          "... failed: " lines) or a watchdog restart -- shown and logged on
          every other AA as "PARTY-EVENT <name>: ...".
        * The leader (PULL mode) writes a PARTY REPORT every 10 minutes from
          what its own client sees -- kills per hour, every player's WS (count
          x average), skillchains by type, how many WS closed one, magic
          bursts -- plus each member's stats line. //aa report (or
          //aa gsc report, /p aa gsc report) asks everyone now and prints it.
        * The leader's ENGAGE-LAG lines say how far the mob was when picked;
          the 10-minute summary counts slow mobs that were still 6y+ away
          (the overnight slow ones looked like bats still flying in).
        * Knowledge sync carries the per-mob-type figures too ("@Mob_Name"
          then 93W12:16.20 / 94S9:27.70); v4.98 AAs ignore those tokens.
v4.98 - Group skillchain learning, step 1 (Mark, 2026-11-21: "review AA/GSC/WS
        efficiency ... better ways to update dmg data / knowledge?").
        * Vayne's Weapon Bash (DRK job ability) arrives as a category 3 action
          with Ruinator's ID, so AA read it as a Ruinator WS: overnight 146 GSC
          lines planned chains on it ("Ruinator >> Upheaval = Fusion", "Myth
          continues Ruinator -- holding") and 131 samples of "Ruinator 0.24k"
          were learned. Only WS messages (185, 187, 188, 189, 197, 224-226,
          238) now count as a WS; the Ruinator junk is dropped.
        * Learning file format 2: counts learned on this PC since the master,
          and the master (aa_knowledge.lua) lists the counts it already holds
          ("used"). Before, the file with more samples won and the other's news
          was lost. Old files convert themselves at load.
        * learn_window 60 (replaces learn_cap 200): the newest 60 samples count,
          so a gear change shows within a night.
        * Per mob type: this player's figure for the mob is blended with their
          all-mob figure x the mob type's toughness (all players' samples on
          it), mob_k 5 -- a new mob type is right after a kill or two.
        * A sample under 25% (odd_ratio) of a settled average (odd_min 20
          samples) is skipped unless 3 (odd_repeat) come in a row.
v4.97 - Engage timing from the leader (Mark, 2026-11-21: "why is it taking so
        long for other party members to engage sometimes? ... add the log from
        Shadow, because I don't have the boxes for the others"). In PULL mode
        the leader times, for every new mob, how long each party player (not
        Trusts, same zone) takes to be engaged on that same mob: one
        "ENGAGE-LAG: <mob> -- Mythrandiir 3.2s, Vayne never" line per mob
        (log file) and an "ENGAGE (last 10 min ...)" summary in chat every 10
        minutes: median, slowest 10%, and how many mobs they never engaged.
v4.96 - A player at the TP cap opens first (Mark, 2026-11-21: "are there
        any other changes needed to improve efficiency? is the GSC tracking and
        usage plans working?"). Tracking and plans work (profiles, knowledge,
        Myth continued 40 of 61 times he was expected), but Vayne (DRK, Cross
        Reaper only -- it can't continue the party's Light / Fusion) always
        ranked below Shadow's and Myth's openers: he sat at 3000 TP, used 22 WS
        in 30 minutes (Shadow 151, Myth 125), and 19 of them landed on top of
        someone else's chain. Openers at group_skillchain.tp_cap (2900) or more
        now go first (log: "(opener, TP capped)"); the others wait their turn.
v4.95 - Party buffs (Haste II) reach everyone (Mark, 2026-11-21: "review the
        code for Scrach to cast Haste II on the party? I am not getting it
        consistently").
        * buff_party picked the first member whose timer said "due" even if
          that member couldn't be cast on (another zone, not in view, out of
          range, dead). The cast was skipped, the timer never moved, and the
          same member was picked again every tick: Mythrandiir in another zone
          blocked Haste II for everyone after him (Shadow's wore off at
          02:50:59 and wasn't recast for 8+ minutes; Scrach still hasted
          himself at 02:54). Those members are now skipped (buff_member_ok).
        * Party members' buffs are read from packet 0x076 (PARTY_BUFFS). get_party()
          has no .buffs, so remote members ran on buff_duration alone (300s,
          while Haste II lasted ~256s on Shadow) and a cast that didn't land
          was never noticed. Now: recast when it wears off; BUFF VERIFY sees a
          miss and retries in 30s. No 0x076 data -> the old timer.
v4.94 - Group skillchain after a reload mid-fight; POSITION (Mark, 2026-11-21,
        bats with Vayne, Scrach and Shadow: "Is there any changes that need to
        be made based on how GSC is working / sharing data").
        * The profile (job, weapon, WS) went out only while idle, so after a
          reload mid-fight it took 2 minutes (02:47:51 -> 02:49:52). Until then
          Vayne had no profile and was planned from the default Scythe list:
          Shadow held 5 times for Entropy / Insurgency / Ruinator, and Vayne
          only has Cross Reaper. The first profile after a load now goes out
          right away, engaged or not (others answer with theirs). Mid-fight
          weapon swaps still don't trigger one.
        * POSITION: a party member in another zone (Mythrandiir) no longer
          counts as "not in view -- NOT STACKED".
v4.93 - aa update previous / aa update <version> / aa update list (Mark,
        2026-11-21: "'aa update previous' can be used to select the previous
        version if the current one is having issues, or 'aa update 4.12'").
        * Every release is also on GitHub as a branch named vX.YY (from
          v4.69; v4.83 / v4.84 are left out -- they crash). "previous" = the
          newest one older than yours; "4.88" / "v4.88" = that one; "list"
          shows what's there. Typed, the whole party goes to the same
          version; "me" = only you. A chosen version may be older (no
          "force" needed); the plain "aa update" still goes to the newest.
v4.92 - Group skillchain learning per mob type; no-show list kept; caster
        closers from 1000 TP (Mark, 2026-11-21, after a Sortie hour: "Different
        mobs have different defenses, so tracking dmg per mob might be
        preferred ... Please make the suggested changes as well").
        * Learned WS and skillchain damage is also kept per mob type (wsm /
          scm, "Upheaval@Locus Dire Bat"). The plan uses the mob type's own
          numbers once there are learn_min samples, else the all-mob average.
          Per-mob numbers stay on each PC (not synced); make_release merges
          them into the master like the rest.
        * "<player> passed on <WS> 3x" is saved (data/aa_noshow_<Char>.lua)
          and kept 6h or until that player uses the WS again -- a reload no
          longer forgets it.
        * A filler (Scrach) counts as a continuer only from 1000 TP as you see
          it (was 500): in Sortie he was expected 21 times and went twice.
v4.91 - Teammates' group skillchain lines hidden (Mark, 2026-11-20 23:55: Myth's
        and Scrach's "aa~g p ..." showed in Shadow's party chat; his own were
        hidden). A teammate's aa~g party line is now dropped as a packet
        (0x017) and handled there, so the game never prints it.
v4.90 - Dynamic group skillchain (Mark, 2026-11-20: "any of our 4 friends may
        have different jobs and weapons ... scan the players in the party for
        jobs, weapons, weaponskills, and then determine a plan for most damage").
        * Skillchain properties now come from Windower's res.weapon_skills, so
          every weapon works (Shadow on THF with daggers, etc.); GSC_WS only
          overrides.
        * Profiles: each AA sends its job, level, weapon and WS in a hidden
          party line (aa~g p) on aa fight, a join, after zoning, on aa gsc ?,
          and on a job / main-hand change while idle (mid-fight swaps and
          Dread Spikes ignored). Lines are 1.5s apart by party slot. A
          teammate's profile beats the job_weapons / pools guesses; without
          one, the WS we see them use are added to their list.
        * Learning: every AA learns each player's WS damage, the skillchain
          damage of each closing WS (Light-equivalent) and magic bursts, into
          data/aa_learned_<Character>.lua (never shipped). aa_knowledge.lua
          is the master (shipped, read only). Per entry more samples wins.
          The plan uses learned damage before the built-in tables, and each
          skillchain step adds the fillers' MB damage x mb_weight.
        * Sync: on aa fight / a join every AA posts a digest (aa~g d); whoever
          knows most about a player sends those entries (aa~g k).
        * make_release.py merges every data/aa_learned_*.lua on MarksPC into
          aa_knowledge.lua and ships it; aa update downloads it ("extra=" in
          manifest.txt, so v4.89 still updates to v4.90).
        * //aa gsc k (learned), sync, save; //aa gsc ? re-sends profiles.
v4.89 - v4.88's EP chain logic taken out again (Mark, 2026-11-20: "I don't
        want that logic in the job_config abilities ... unless it really
        helped"). It didn't: 15h on v4.88, the burst fired on chain kill #20
        every time (12 times), but the 12 chains with it peaked at #23.8 on
        average, the 38 without at #23.8 too; median peak #24 and 381 EP per
        kill, the same as v4.85. A 45s burst speeds up one kill; the chain
        breaks around #24. ep_chain_min and the chain tracking are gone;
        Mighty Strikes / Brazen Rush / Meikyo Shisui are used when ready.
v4.88 - Burst for the high EP chain (Mark, 2026-11-19: "yes, lets build
        those updates").
        * EP / EXP chain tracking: the kill line ("Master chain #N!" ...
          "gains X exemplar points") gives the chain number (EP-CHAIN debug
          line). On 11-19 the chain reset at #23-25 every time, even with
          37s between kills, while EP rises from 317 (#0) to 450 (#23).
        * abilities take ep_chain_min = N: used only when the kill we're on
          would be chain #N or higher. No chain seen for 3 minutes (outside
          EP areas) -> used as normal.
        * Config: WAR Mighty Strikes (buff 44) and Brazen Rush, SAM Meikyo
          Shisui (buff 54), all with ep_chain_min = 20.
v4.87 - Longer wait for Shadow's Full Break (Mark, 2026-11-19: "let's do a
        slightly longer wait so shadow can open with full break, since it is
        the best sc we have"). At the start of a mob, while a teammate still
        owes their once-per-mob WS (Full Break) and is at block_tp (500) or
        more, everyone else holds their opener for up to pre_wait (6s,
        group_skillchain.pre_wait) instead of opener_wait (2s). The 2s ran out
        just as Shadow went -- 32 opener collisions in 308 kills on v4.85.
        Below 500 TP nobody waits on him. (v4.86 was tried and not released.)
v4.85 - Hotfix (Mark, 2026-11-19 11:27).
        * "autoattack.lua:1434: attempt to index local 'ids' (a nil value)",
          over and over: v4.83's new mob_in_our_fight(m, ids, idx) replaced
          v4.01's mob_in_our_fight(t) of the same name, which the main loop's
          closer-switch still calls with one argument. The new one is now
          mob_is_ours; v4.01's is back.
        * aa update mid-fight: v4.82 dropped the "fighting" check at the start
          but a second one after the download still said "a fight started --
          nothing changed" (10:58 twice). Removed; the reload resumes the fight.
v4.84 - Review of 9h overnight on v4.82 (Mark, 2026-11-19).
        * Full Break once per mob never really ran: the "done" marks were
          kept by mob ID until 400 of them, and the bats respawn with the
          same 8 IDs -- 9 Full Breaks in 9 hours (50 in 3h on v4.76, same
          bug). Marks now expire after 120s (GSC_PRE_FORGET).
        * A filler (Scrach) continuing a chain waits one handoff_wait after
          the window opens, like a self-continuation. Two closers on one
          resonance within 3s broke 133 of 980 pair-made Lights; 64 of those
          had Savage Blade in them.
v4.83 - No more sitting on a fresh bat while another one is fighting us
        (Mark, 2026-11-19: "Shadow just got stuck on a bat that was like 7
        yalms away, not aggroed to us, while another bat was already
        fighting us from behind").
        * 00:00:53 PullNext Provoked a bat at 8.3y; the current bat died
          0.7s later and HOT-SWITCH chose an unaggroed bat at 4.6y ("fresh")
          -- the Provoked one wasn't shown as claimed yet. Shadow then sat in
          PULL-WAIT on the fresh bat (Provoke on recast).
        * A mob we Provoked in the last 20s (PROVOKED_HOT_SECS) now counts as
          in our fight, so HOT-SWITCH takes it first.
        * Engaged on a mob that isn't fighting us while another one is: switch
          to the one that is (RETARGET >>>> line), checked every 2s.
v4.82 - aa update while fighting (Mark, 2026-11-18). It used to answer
        "fighting -- send aa update again after the fight". Now it updates
        right away, and the reloaded AA carries on: before the reload it
        saves the mode (PULL / ASSIST), the leader's fight spot and aa fight
        following to data/resume_state.txt; after it (same zone, within 2
        minutes) they come back and "aa pull" / "aa assist" restarts
        ("RESUME: carrying on in PULL mode..."). aa reload resumes the same
        way. The downloads still take a second or two, so expect a short
        pause mid-fight.
v4.81 - Puller walks back again (Mark, 2026-11-18: "Shadowhammer is still
        moving up to a bat sometimes, and then NOT moving back... even after
        that fight ends").
        * STEP-BACK allowed one return per mob ID, kept forever. The bats
          respawn with the same 8 IDs, so after the first return on each ID
          every later step-in saved no spot ("EMERGENCY STEP-IN" with no
          "STEP-HOME: spot saved") and never came back. The limit now
          forgets an ID 30s after its return (STEP_IN_RETURN_FORGET).
        * PULL mode always has a fight spot: where //aa pull started (aa
          fight still sets it first). After the 23:44 reload Shadow ran plain
          PULL with no spot, so nothing brought him back once a step-in
          stuck. Typed //aa pull still means "stay where you are" -- that is
          now the spot.
v4.80 - No "a player joined" on zoning (Mark, 2026-11-18). The join watch
        counted players: while you zone the party list reloads (Trusts look
        like players for a moment, members drop out and come back), so every
        zone said "a player joined -- no Trusts for 120s" and held Trusts for
        2 minutes. Now a join is a player name that wasn't in the party in
        the last 2 minutes, and nothing counts for 15s after a zone. The line
        names who joined.
v4.79 - aa update / aa version (Mark, 2026-11-18: "aa update should have all
        party players update even when they are not in the same zone";
        "aa version" said v4.77 was newest after v4.78 was out).
        * GitHub's raw file server keeps main/ files for 5 minutes. Update and
          version now ask the GitHub API for the newest commit and read the
          files from that commit, so a release shows up at once (falls back
          to main/ if the API doesn't answer).
        * //aa update and //aa version typed on any character go to the whole
          party through party chat -- every member, any zone. "aa update me"
          / "aa version me" = only that character. aa reload / aa rollback
          stay per character ("all" for the party).
v4.78 - Staying stacked (Mark, 2026-11-18: "shadow and myth and scrach are
        not standing together anymore... make sure shadow is going back to
        starting points if he ever moves").
        * Leader: while engaged, ANCHOR only went back when the mob could
          still be hit from the fight spot. With hot switching there's never
          a gap between mobs, so Shadow went back 13 times in 3 hours and sat
          1-3y off the spot. Now he also goes back when the mob is in our
          fight (it follows him).
        * Leader: no run back inside our own WS animation (can't move then:
          9 "blocked on the way back" stops), and the blocked check waits 1s.
        * Leader: a POSITION line every minute -- distance from the spot and
          each player's distance from the leader; in chat with
          "NOT STACKED" when anyone is more than 4y away or not in view.
        * Members: //aa stack / aa stack while fighting now stacks (it used
          to answer "is fighting -- not stacking").
        * Members: more than restack_max (10y) away while fighting -- the
          re-stack waited for "between fights", which never comes with hot
          switching. After restack_far_secs (20s) they re-stack anyway
          (the mob follows them). restack_far_secs = 0 turns that off.
v4.77 - Pull-next Provoke timing, damage model refit (Mark, 2026-11-18
        evening review of 227 kills on v4.76).
        * PullNext Provoke waits until JA_AFTER_WS_GAP (4s) after our own WS.
          v4.76 sent 318 pull Provokes: every one sent under 3s after our WS
          was dropped (129 of 129, "no Provoke seen"), 160 of 166 sent 4s+
          after it landed. The low-HP check usually fires right after the WS
          that put the mob under the threshold, so it now waits a tick or two.
        * Damage model refit (GSC_POWER / GSC_SCPOWER / GSC_MULT['end']):
          Light closed by Upheaval 28.4k, Ukko's Fury 27.3k, Shoha 20.6k, Fudo
          16.7k, Kasha 14.7k, Savage Blade 11.9k (was 31.9k -- Scrach's Light
          was overrated, so Myth's Shoha now closes Upheaval when he has TP);
          Light-on-Light 'end' 1.25 -> 1.4 (Ukko 36.8k, Fudo 26.2k).
        * Checked, unchanged: Light-on-Light still ends the chain (1 of 30
          continued), Light from a pair continues ~90% and its closer averages
          29-40k; the chain tracker and opener-after-end are right.
        * Plan look-ahead counts a later step only for players already at
          500 TP (block_tp); it used to count everyone, so a WS was scored
          with a follow-up from a player at 0 TP.
v4.76 - PullNext_OnLowHP fixed (Mark, 2026-11-18: "I see lots of messaging,
        but I never see the provoke until after the current bat dies").
        * The PullNextMax cap counted every mob within 10y -- idle,
          unclaimed ones too. At Locus Dire Bats the next bat was within 10y
          at 146 of 157 kills, so the pull was skipped every time (7 pulls in
          4h, all at 10-16y). Now only mobs in our fight count (hs_is_hot:
          claimed by the party, targeting or hitting one of us).
        * A mob already in melee range was skipped as "will aggro
          naturally" -- these bats don't. Now only a mob already fighting us
          is skipped; an idle one in reach is Provoked.
        * Logging: the scan line printed every tick and its flag hid every
          skip reason. Now one line per mob and reason (lhp_note), plus
          "no free mob within Ny to pull next".
        * GSC log: one chat line per skillchain step when it lands --
          "GSC: step 3 Light -- Tachi: Shoha (Mythrandiir)". The "X >> Y =
          Z (step N)" line for your own chain WS goes to the log file only
          at debug 2 (still in chat at debug 1, where the landing line
          isn't shown).
        * PullNext Provokes the next mob by ID (provoke_by_id: outgoing 0x01A,
          category 0x09) and stays on the current mob. The old ST pull moved
          the cursor, but while engaged <t> never followed: "target lock
          failed" 2 of 3 tries on 11-18, ~5s of /targetoff + /attack on and
          no Provoke. Provoke not ready / out of range -> one log line, the
          after-kill Provoke takes it.
v4.75 - Stacking watch, fight anchor, emergency-only step in (Mark,
        2026-11-18: DPS down after the ASUS restart -- the characters weren't
        stacked. Myth: 67 "out of range" in 30 min vs 8 in 53 min before;
        his melee 25k -> 18k/min. aa fight skipped stacking because Myth was
        engaged, and following only runs between fights.)
        * aa_party: party members in aa fight check their distance to the
          leader; engaged and more than party_range + restack_slack (2y) for
          restack_delay (2s) but within restack_max (10y) -> re-stack now,
          mid-fight, then face the mob. Farther: logged once, stacked
          between fights. aa fight also stacks a member who is already
          fighting (within restack_max).
        * Leader: aa fight saves the spot (ANCHOR); in PULL mode the leader
          runs back whenever more than ANCHOR_TOL (1y) away -- between mobs
          always, engaged only if the mob can still be hit from the spot.
          Cleared by stop / zoning.
        * STEP_IN_EMERGENCY: on trouble the leader Provokes, then shoots
          (if a ranged weapon is ready); it steps in only when the mob keeps
          hitting it with none of its rounds landing, or nothing fixed it
          in 12s. "Out of range" alone never steps in.
        * Only with aa fight: aa assist / aa pull on their own (typed, by
          tell or party chat) end fight mode -- no following, re-stacking or
          fight spot; the player stays where they are.
v4.74 - Fix: "autoattack.lua:768 attempt to call method 'with' (a nil
        value)" (Mark, 2026-11-18, ASUS on v4.73). res_with() called :with on
        a resource table that couldn't be searched -- the slim item proxy
        returns an empty table when the full item list fails to load.
        * Items by name (rings, food) go through aa_item_named().
        * Any other table without :with: one "RES: ... could not be
          searched" line, nil, tried again later.
        * Item list load failure ("not enough memory" on the ASUS after a
          long session -- the game client, not AA, which used ~4 MB):
          next load try after ITEMS_RETRY_SECS (120s); misses aren't cached
          while it is down (a ring isn't lost for the session), and the
          proxy's table methods return nil instead of erroring.
v4.73 - Group skillchain: fewer same-second collisions, per-player WS lists
        (Mark, 2026-11-18 v4.72 review: EP/h ~30.0k, SC dmg/kill 123k, steps
        3 x141 / 4 x34 -- best so far; but 56 same-second WS, mostly two
        players opening at once after a chain ended).
        * block_tp (500): a teammate who would open or continue better than
          you keeps their turn from 500 TP (was soon_tp 750) -- you see
          their TP late, so both thought they were first.
        * group_skillchain.players = {Name = {'WS', ...}}: that player's WS
          list for the plan instead of pools[weapon] (others can't see what
          a teammate has learned; your own list is always read from the game).
v4.72 - Group skillchain: Light-on-Light ends a chain, damage model, timing
        (Mark, 2026-11-18: v4.71 EP/h and DPS a little under v4.70).
        * Light made from two Light-property WS (Ukko's Fury / Fudo, either
          order) was continued 1 time in 156; Light made from Fusion +
          Fragmentation 70-82%. That Light now ends the chain (plan and
          tracker), so nobody spends a WS on it -- the next opener goes.
        * Plan value = the WS's damage + the skillchain damage it closes,
          from the logs (GSC_POWER, GSC_SCPOWER, GSC_MULT; config power /
          sc_power override). Light by closer: Savage Blade 32k, Upheaval
          25k, Ukko's Fury 25k, Shoha 16k, Fudo 16k, Kasha 15k -- so Shoha /
          Kasha open and Upheaval / Savage Blade / Ukko's Fury close.
        * window_open 2.5 -> 3.2 (WS lands ~4s after the last one: 2s gaps
          never chained, 3s about half, 4-9s reliably), ws_lead 1.0 -> 1.2.
        * Continuing your own WS always waits one handoff_wait; fillers
          (Scrach) open only after two opener turns -- 8 of v4.71's 24
          same-second collisions were Savage Blade on top of a melee WS.
v4.71 - Group skillchain tuning from the first v4.70 hour (Mark, 2026-11-18:
        kill cycle 68s -> 46s, EP/h ~19.7k -> ~32k, no refused JAs; but
        chains stopped at 2-3 steps and players collided).
        * Skillchain window from 10h of logs: SCs formed 2-10s after the
          previous WS at every step, no shrinking. window_open 3.0 -> 2.5,
          window_close 8 -> 10, window_step 1 -> 0, window_min 5 -> 8,
          max_steps 5 -> 8. v4.70 gave up on live chains after ~5-6s and
          opened a new one over them.
        * Collisions (two WS in the same second, the second wasted): a
          teammate within soon_tp of 1000 keeps their opener turn; whoever
          made the last WS continues only after everyone else.
        * No-show learning: a teammate we waited on who uses something else
          noshow_max (3) times loses that WS from our plan this session
          (others held 1.5s each time for a Requiescat Scrach never used).
        * bank_hpp (10): no new chain on a mob at or under 10% HP unless you
          have 2000+ TP -- the TP opens the next mob instead.
v4.70 - Group skillchains, JA timing, Berserk/Defender, rings, facing (Mark,
        2026-11-18 log review: ~20k EP/h, 65s kill cycle, chain broke at ~#21).
        * GROUP SKILLCHAIN (aa_config.lua -> group_skillchain, //aa gsc): with
          another player in the party, every AA plans the party's WS from the
          party list, jobs (0x0DD/0x0DF), TP and the chain it sees on the mob;
          job_config ws_list is paused. Best continuer goes first (level, melee
          before fillers, stronger closer), next best after handoff_wait;
          openers ranked by the 2-4 step chain they lead to; once_per_mob
          (Great Axe: Full Break) opens each new mob; fillers (RDM ...) burst
          first and only WS when no melee is close to 1000 TP or a chain needs
          them. Collision guard: no WS while a party WS is readying.
        * ws_list entries take once_per_mob = true (WAR Normal: Full Break once
          per mob, then Upheaval > Ukko's Fury > Upheaval).
        * No JA within JA_AFTER_WS_GAP (4s) of our own WS: all 193 of Myth's
          "Unable to use job ability" were 3.0-3.9s after his WS. A refused JA
          gets its min_time back (up to 3 times in 60s) instead of waiting
          its whole recast.
        * Berserk / Aggressor stack: their buff_any no longer skips each other
          (JA_STACKS). Defender yields to Berserk (JA_YIELD / yield_to): held
          while Berserk is up or ready within 30s. Shadow had Defender up
          87 of 169 min and Berserk 31.
        * Rings: one ring /item per pass, RING_PASS_GAP (60s) after a try that
          doesn't go off (3 rings back to back held the loop ~54s); CP rings
          skipped while EP comes in and no CP does, or job points are capped.
        * Facing: turn before /attack on, before every WS, and again 0.4s and
          1.0s after a hot switch; HOT-SWITCH-PROVOKE turns before Provoke.
v4.69 - Pass-through commands now answer the sender (Mark, 2026-11-18:
        "/t scracheebrat aa ws off" gave no reply). aa pull | assist |
        ws | move | ds by /tell or /p:
        * ws / move / ds run right away and every [AutoAttack] line they
          print is sent back ("Scracheebrat: Weapon skills OFF (until aa
          ws on or the addon is reloaded)."), at most 5 lines.
        * pull / assist: "switched to PULL mode (was ASSIST)", "already in
          PULL mode", "started PULL mode" or "couldn't start PULL mode".
        * Tells answer the sender; /p answers in party, except on the
          character that sent the /p line (it sees it in its own log).
        * The addon command handler is now the global aa_addon_command
          (still registered as the addon command).
]]


-- v2.64: Detect 'Unable to see' / 'You cannot see' game messages.
-- Uses 'incoming chunk' packet 0x017. FFXI packets contain color/formatting
-- escape bytes (\x1e, \x1f, etc.) interspersed in the text, so we strip all
-- non-printable bytes before matching. We also scan the whole packet (not
-- just from byte 5) to handle variable header sizes.
-- On match: set cant_see_flag (for main loop re-face) AND call
-- facing_emergency() which bypasses all rate/lockout guards immediately.
-- v3.83: Shared cant-see handler, called from the 0x017 (chat) and 0x029
-- (action message) paths of the incoming chunk handler below.
-- is_facing_msg = true for "You cannot see" (217/219), false for "Unable to see" (5).
local function handle_cant_see(is_facing_msg)
    -- v2.74: guard get_player() nil (returns nil during zone transitions)
    local p = windower.ffxi.get_player()
    if auto_attack and p and p.status == 1 then
        cant_see_flag = true
        if PSTAT then PSTAT.cant = PSTAT.cant + 1 end   -- v4.99
        local _mt = windower.ffxi.get_mob_by_target('t')   -- v4.38: STEP-IN trouble
        if _mt and _mt.id then
            melee_msg.id = _mt.id; melee_msg.time = os.clock()
            melee_msg.kind = is_facing_msg and 'You cannot see' or 'Unable to see'
            ra_cant_see.id = _mt.id; ra_cant_see.time = os.clock()   -- v4.39
        end
        facing_emergency()
        -- v2.94: Count cant-see hits per mob. After CANT_SEE_LIMIT hits
        -- within CANT_SEE_WINDOW seconds, blacklist this mob so the next
        -- scan skips it. Handles wall-clipped mobs and geometry issues.
        local t = windower.ffxi.get_mob_by_target('t')
        if t and t.id then
            local now = os.clock()
            -- v3.26: Pull-LOS fast-path.
            -- "Unable to see" (NOT "You cannot see") within PULL_LOS_WINDOW of a
            -- confirmed PullNext pull = geometry/wall block, not a facing issue.
            -- Script already fired //facing f before the pull, so if we still
            -- can't see the mob it's behind a wall. Blacklist 30s immediately,
            -- no hit-counter needed.
            if not is_facing_msg
               and last_pull_next_mob_id == t.id
               and (now - last_pull_next_mob_time) <= PULL_LOS_WINDOW then
                cant_target_ids[t.id] = now + PULL_LOS_BLACKLIST_DUR
                cant_target_counts[t.id] = nil
                debug_msg('Pull LOS: ' .. (t.name or '?') .. ' is geometry-blocked after confirmed pull — blacklisted 30s')
                last_pull_next_mob_id = nil
            else
                -- Normal combat cant-see: accumulate hits; blacklist after CANT_SEE_LIMIT
                local rec = cant_target_counts[t.id]
                if not rec or (now - rec.first_time) > CANT_SEE_WINDOW then
                    cant_target_counts[t.id] = {count=1, first_time=now}
                else
                    rec.count = rec.count + 1
                    if rec.count >= CANT_SEE_LIMIT then
                        local _dur, _n = blacklist_unreachable(t.id)  -- v3.83: escalating 10/30/120/300s
                        debug_msg('Cant-see blacklist: ' .. (t.name or '?') .. ' (ID ' .. t.id .. ') unreachable - strike ' ..
                                  _n .. ', skipping for ' .. _dur .. 's')
                        -- Disengage and clear target so next tick scans for a replacement
                        cmd('input /attack off')
                        cmd('input /targetoff')
                    end
                end
            end
        end
    end
end

windower.register_event('incoming chunk', function(id, data)
    if id == 0x076 then party_buffs_parse(data) end   -- v4.95: party members' buffs
    if not data then return end
    -- v3.98: only 4 packet IDs matter; return before creating the pcall closure
    -- (this handler runs for every incoming packet -- hundreds per second).
    if id == 0x0DD or id == 0x0DF then pcall(gsc_job_packet, id, data); return end  -- v4.70: party jobs
    if id ~= 0x017 and id ~= 0x029 and id ~= 0x067 and id ~= 0x068 then return end
    local _ok, _err = pcall(function()
    if id == 0x017 then
        local clean = data:gsub('[%z\x01-\x1f\x7f-\xff]', ' '):lower()
        -- v2.95: 'already claimed' fires when the game knows a mob is purple
        -- BEFORE Windower's claim_id field updates (can lag 1-2s). Respond
        -- immediately: disengage and set limbo so the main loop skips combat.
        if clean:find('already claimed') then
            local p = windower.ffxi.get_player()
            if auto_attack and p and p.status == 1 then
                local t = windower.ffxi.get_mob_by_target('t')
                -- v2.98: Skip escape for excluded mobs (e.g. Quetzalcoatl's Sibilus).
                -- The main loop escape block already checks is_purple_excluded, but the
                -- packet handler fired first and disengaged before the loop ran.
                if t and is_purple_excluded(t.name) then
                    debug_msg('Purple (packet): ' .. (t.name or '?') .. ' is excluded - ignoring already-claimed message.')
                else
                    info_msg('Purple (packet): ' .. (t and t.name or '?') .. ' already claimed. Disengaging immediately.')
                    purple_from_packet = true
                    -- v3.34: Only set a short 2s settle window here, NOT the full 15s.
                    -- The main loop rescue scan will extend to 15s if no replacement found.
                    -- Pre-setting 15s limbo in the packet handler blocked the rescue scan
                    -- from running, leaving Shadowhammer idle for the full duration.
                    purple_limbo_until = os.clock() + 2
                    cmd('input /attack off')
                    cmd('input /targetoff')
                end
            end
        end
        if clean:find('unable to see') or clean:find('you cannot see') then
            handle_cant_see(clean:find('you cannot see') ~= nil)
        end
        -- v4.38: "unable to reach" -> STEP-IN trouble (Provoke first)
        if clean:find('unable to reach') or clean:find('cannot reach') then
            local _pr = windower.ffxi.get_player()
            local _mt = windower.ffxi.get_mob_by_target('t')
            if auto_attack and _pr and _pr.status == 1 and _mt and _mt.id then
                melee_msg.id = _mt.id; melee_msg.time = os.clock(); melee_msg.kind = 'unable to reach'
            end
        end
    end
    -- v3.83: "Unable to see" (msg 5) and "You cannot see" (msgs 217/219) arrive as
    -- action-message packets (0x029), NOT chat (0x017). Before v3.83 the cant-see
    -- counter/blacklist never fired once (0 hits in 290 Shadowhammer logs).
    -- 0x029 layout: 0x04 actor ID (u32), 0x08 target ID (u32), 0x18 message ID (u16).
    if id == 0x029 and #data >= 0x1A then
        local _msg = (data:byte(0x19) + data:byte(0x1A) * 256) % 0x8000
        -- v3.96: a defeat message means an entity is about to despawn (and a
        -- casket may spawn). Hold set_target() for TARGET_QUIET_WINDOW.
        if _msg == 6 or _msg == 20 or _msg == 97 or _msg == 113 or _msg == 406
           or _msg == 605 or _msg == 646 then
            target_quiet('defeat (msg ' .. _msg .. ')')
            -- v4.18: the mob died -- its respawn starts with no unreachable strikes
            local _dt = data:byte(9) + data:byte(10) * 256 + data:byte(11) * 65536 + data:byte(12) * 16777216
            cant_see_strikes[_dt] = nil; cant_see_strike_time[_dt] = nil
            aa_kill_seen(_dt)  -- v4.19
            if pstat_kill then pcall(pstat_kill, _dt) end   -- v4.99: party report
            if aa_party_on_kill then pcall(aa_party_on_kill, _dt) end   -- v5.02: aa fight members re-stack
            if mob_hits then mob_hits[_dt] = nil end
            if ds_mobs then ds_mobs[_dt] = nil end  -- v4.32
            -- v4.34: was it us? (msg 97 = "<you> were defeated by <mob>")
            local _me_dd = windower.ffxi.get_player()
            if _me_dd and _dt == _me_dd.id then
                aa_on_defeated('msg ' .. _msg,
                    data:byte(5) + data:byte(6) * 256 + data:byte(7) * 65536 + data:byte(8) * 16777216)
            end
        end
        -- v4.32: Dread Spikes wore off / was removed (param 1 at 0x0C = status ID)
        if DS_LOSE_MSGS[_msg] and #data >= 0x10 and (data:byte(13) + data:byte(14) * 256) == DS_BUFF_ID then
            ds_on_msg(data:byte(9) + data:byte(10) * 256 + data:byte(11) * 65536 + data:byte(12) * 16777216, _msg, DS_BUFF_ID)
        end
        -- v3.93: "<mob> is out of range." (msg 4 / 154) for us -> engaged_pull_logic()
        if _msg == 4 or _msg == 154 then
            local _a4 = data:byte(5) + data:byte(6) * 256 + data:byte(7) * 65536 + data:byte(8) * 16777216
            local _t4 = data:byte(9) + data:byte(10) * 256 + data:byte(11) * 65536 + data:byte(12) * 16777216
            local _me4 = windower.ffxi.get_player()
            if _me4 and _a4 == _me4.id then
                oor_msg.id = _t4
                oor_msg.time = os.clock()
                if PSTAT then PSTAT.oor = PSTAT.oor + 1 end   -- v4.99
                if aa_party_on_oor and os.clock() - (last_ws_time or 0) >= 2 then pcall(aa_party_on_oor, _t4) end   -- v5.02: melee out of range -> re-stack
                -- v5.01: melee (auto-attack) or a WS / ability we just sent, and how far the mob was
                if PSTAT and PSTAT.oorm then
                    if os.clock() - (last_ws_time or 0) < 2 then PSTAT.oorw = PSTAT.oorw + 1 else PSTAT.oorm = PSTAT.oorm + 1 end
                    local _m4 = windower.ffxi.get_mob_by_id(_t4)
                    if _m4 and _m4.distance and #PSTAT.oord < 60 then PSTAT.oord[#PSTAT.oord + 1] = math.sqrt(_m4.distance) end
                end
            end
        end
        if _msg == 5 or _msg == 217 or _msg == 219 then
            local _actor = data:byte(5) + data:byte(6) * 256 + data:byte(7) * 65536 + data:byte(8) * 16777216
            local _tgt   = data:byte(9) + data:byte(10) * 256 + data:byte(11) * 65536 + data:byte(12) * 16777216
            local _me = windower.ffxi.get_player()
            if _me and (_actor == _me.id or _tgt == _me.id) then
                handle_cant_see(_msg ~= 5)
            end
        end
    end
    -- v3.94: pet status. 0x068 (and 0x067 type 4) carry our pet's HP%, TP and
    -- target. Owner index is at 0x06 in 0x068 and 0x0C in 0x067; TP at 0x10.
    if (id == 0x068 or id == 0x067) and #data >= 0x18 and data:byte(5) % 64 == 4 then
        local _me_p = windower.ffxi.get_player()
        local _own = (id == 0x068) and (data:byte(7) + data:byte(8) * 256)
                                    or (data:byte(0x0D) + data:byte(0x0E) * 256)
        if _me_p and _me_p.index and _own == _me_p.index then
            pet_state.hpp  = data:byte(0x0F)
            pet_state.tp   = data:byte(0x11) + data:byte(0x12) * 256
            if id == 0x068 then
                pet_state.target_id = data:byte(0x15) + data:byte(0x16) * 256 + data:byte(0x17) * 65536 + data:byte(0x18) * 16777216
            end
            pet_state.time = os.clock()
        end
    end
    end)
    if not _ok then info_msg('Chunk handler error: ' .. tostring(_err)) end
end)



-- v3.96: a treasure casket spawning also changes the entity table; hold
-- set_target() for TARGET_QUIET_WINDOW.
windower.register_event('incoming text', function(original)
    if original and original:find('concealing a treasure chest', 1, true) then
        target_quiet('treasure casket appeared')
    end
    -- v4.54: "maximum Trusts" while the party list isn't full = ghost slot
    -- v4.55: our own [DEBUG]/[AA]/[CMD] lines come back through this event too
    -- -- skip them (a TRUST TEXT line re-matched itself ~49 times, and the
    -- PULL HOLD debug line "until the party is full" set it off). "party is
    -- full" only counts within FP_TEXT_SECS of our own Trust call.
    local _clean = original and original:gsub('[%c\128-\255]', '')
    if _clean and not aa_own_line(_clean) then
        local _l = _clean:lower()
        if _l:find('alter ego', 1, true) or _l:find('party is full', 1, true) then
            debug_msg('TRUST TEXT: "' .. _clean .. '"')
            if (_l:find('alter ego', 1, true) and (_l:find('maximum', 1, true) or _l:find('max ', 1, true)
                or _l:find('limit', 1, true) or _l:find('too many', 1, true)))
               or (_l:find('party is full', 1, true) and os.clock() - fp.cast_at <= FP_TEXT_SECS) then
                local _full, _n, _w, _t = full_party_state()
                if not _full and _t < 6 then
                    fp.ghost = true; fp.ghost_line = _clean
                    info_msg('TRUSTS: game says max Trusts but the party shows ' .. _t .. '/6 (' .. _n .. '/' .. _w ..
                             ' Trusts) -- ghost slot fix next idle tick.')
                end
            end
        end
    end
    -- v4.70: refused JA -> retry; EP / CP coming in (CP rings)
    if original and original:find('Unable to use job ability', 1, true) then ja_failed_text() end
    if _clean and not aa_own_line(_clean) then
        if _clean:find('exemplar points', 1, true) then RING_EP_SEEN = os.clock() end
        if _clean:find('capacity points', 1, true) then RING_CP_SEEN = os.clock() end
    end
    -- v4.07: client refused our ring /item
    if original and ring_item_pending_until > os.clock()
       and original:find('A command error occurred', 1, true) then
        ring_cmd_error = true
    end
end)

-- v4.44: bridge for aa_party.lua (party commands by /tell and party chat).
-- Globals on purpose (main chunk is at the local limit).
function aa_running()       return auto_attack == true end
function aa_get_mode()      return autoattack_type end
function aa_set_mode(m)     autoattack_type = m; fight_subcmd = nil end
function aa_get_config()    return current_config end
function aa_send(str)       cmd(str) end
function aa_dbg(msg)        debug_msg(msg) end
function aa_trust_recheck() last_trust_check_time = 0 end
function aa_trust_reset() trust_fails = {}; trust_skip = {}; trust_pending = {} end  -- v4.46
function aa_load_party()
    local chunk, err = loadfile(windower.addon_path .. 'aa_party.lua')
    if not chunk then
        windower.add_to_chat(167, '[AA] aa_party.lua not loaded (party commands off): ' .. tostring(err))
        if aa_start_failed then aa_start_failed('aa_party.lua: ' .. tostring(err)) end   -- v4.65
        return nil
    end
    local ok, mod = pcall(chunk)
    if not ok then
        windower.add_to_chat(167, '[AA] aa_party.lua error (party commands off): ' .. tostring(mod))
        if aa_start_failed then aa_start_failed('aa_party.lua: ' .. tostring(mod)) end   -- v4.65
        return nil
    end
    return mod
end
AA_PARTY_MOD = aa_load_party()

-- v5.06: aa nav (nav.lua + nav_maps.lua + nav_zones.lua). A problem here only
-- turns aa nav off -- it never stops AutoAttack or rolls it back. Missing
-- files (updated from v5.05 or older, which doesn't fetch them) are
-- downloaded once from the release on GitHub, then nav loads.
function aa_load_nav(fetched)
    local f = windower.addon_path .. 'nav.lua'
    if not windower.file_exists(f) or not windower.file_exists(windower.addon_path .. 'nav_maps.lua') then
        if not fetched and aa_nav_fetch then
            windower.add_to_chat(207, '[AA] aa nav files missing -- getting them from GitHub.')
            coroutine.schedule(function()
                local okf, got = pcall(aa_nav_fetch)
                if okf and got then AA_NAV_MOD = aa_load_nav(true) end
            end, 5)
        else
            windower.add_to_chat(167, '[AA] aa nav is off: nav.lua / nav_maps.lua not found.')
        end
        return nil
    end
    local chunk, err = loadfile(f)
    if not chunk then
        windower.add_to_chat(167, '[AA] nav.lua not loaded (aa nav off): ' .. tostring(err))
        return nil
    end
    local ok, mod = pcall(chunk)
    if not ok then
        windower.add_to_chat(167, '[AA] nav.lua error (aa nav off): ' .. tostring(mod))
        return nil
    end
    return mod
end
AA_NAV_MOD = aa_load_nav()

-- Call this when commands are received (e.g. "//aa assist" or "//aa pull")
-- v4.69: a named global so aa_party.lua can run ws / move / ds directly and
-- send the sender what it printed (registered as the addon command below).
function aa_addon_command(command, ...)
    local args = {...}
    local subcmd = args[1] -- This will be 'ne', 'nw', 'east', etc., or nil
    command = command and command:lower() or 'help'
    -- v4.44: party commands (invite, fight, follow, ...) live in aa_party.lua
    if aa_party_command and aa_party_command(command, args) then return end

    if command == 'start' or command == 'assist' then
        autoattack_type = 'assist'
        fight_subcmd = subcmd
        update_job_configs()
        local _p = windower.ffxi.get_player()
        local _job = _p and (_p.main_job .. '/' .. (_p.sub_job or '?')) or '?'
        info_msg('ASSIST command received — starting ASSIST mode. Job: ' .. _job .. (subcmd and (', subcmd: ' .. subcmd) or ''))
        toggle_auto_attack()
    elseif command == 'pull' then
        autoattack_type = 'pull'
        if subcmd and subcmd:lower() == 'spin' then
            -- v3.96: spin pull removed
            windower.add_to_chat(8, '[AutoAttack] "spin" was removed in v3.96 -- starting a normal pull.')
            subcmd = nil
        end
        fight_subcmd = subcmd
        update_job_configs()
        local _p = windower.ffxi.get_player()
        local _job = _p and (_p.main_job .. '/' .. (_p.sub_job or '?')) or '?'
        info_msg('PULL command received — starting PULL mode. Job: ' .. _job .. (subcmd and (', subcmd: ' .. subcmd) or ''))
        -- v5.29: no fight spot for a plain //aa pull (v4.81 saved one here, so
        -- the puller kept running back to where pull was typed). Only aa fight
        -- sets AA_ANCHOR (aa_party.lua, before it starts PULL); plain PULL
        -- roams -- other rooms, other floors. STEP-BACK after an emergency
        -- step-in is separate (step_home) and still works.
        toggle_auto_attack()
    elseif command == 'stop' then
        -- debug_msg('Stop command received')
        auto_attack = false
        aa_clear_anchor('stopped')   -- v4.75
        fight_subcmd = nil
        initial_direction = nil
        if mv.active then windower.ffxi.run(false); mv.active = false end  -- v4.22
        ds_leave('stopped')  -- v4.32
        cmd('input /attack off')
    elseif command == 'move' then
        -- v4.28: //aa move [off|pull|provoke|melee|target|<yalms>] (this session only)
        --        no argument = show; 'on' = pull (old move_in_range)
        local _m = subcmd and subcmd:lower()
        local _ok = {off = 'off', pull = 'pull', on = 'pull', provoke = 'provoke', melee = 'melee', target = 'target'}
        if _m and _ok[_m] then move_to_target = _ok[_m]
        elseif _m and tonumber(_m) and tonumber(_m) > 0 then move_to_target = tonumber(_m)
        elseif _m then
            windower.add_to_chat(8, '[AutoAttack] move: use off | pull | provoke | melee | target | <yalms>')
        end
        if move_mode() == 'off' and mv.active then windower.ffxi.run(false); mv.active = false end
        local _mm = move_mode()
        windower.add_to_chat(8, '[AutoAttack] move_to_target: ' .. (_mm == 'custom'
            and (tostring(move_to_target) .. 'y') or _mm))
    elseif command == 'debug' then
        -- v4.25: //aa debug [0|1|2|off|release|dev] | //aa debug file [on|off]
        local _m = subcmd and subcmd:lower()
        local _lv = {['0'] = 0, off = 0, ['1'] = 1, release = 1, rel = 1, min = 1,
                     ['2'] = 2, dev = 2, deep = 2}
        if _m == 'file' then
            local _f = args[2] and args[2]:lower()
            if _f == 'on' then DEBUG_LOG_FILE = true
            elseif _f == 'off' then DEBUG_LOG_FILE = false
            else DEBUG_LOG_FILE = not DEBUG_LOG_FILE end
            if not DEBUG_LOG_FILE then aa_log_close() end
            aa_dbg_file_failed = false
        elseif _m and _lv[_m] then
            debug_level = _lv[_m]
            if debug_level < 2 then aa_log_close() end
            aa_dbg_last = 0
        elseif _m then
            windower.add_to_chat(8, '[AutoAttack] debug: use 0|1|2 (off|release|dev) or file on|off')
        end
        local _names = {[0] = 'OFF', [1] = 'RELEASE (minimal)', [2] = 'DEV (deep + timing)'}
        windower.add_to_chat(8, '[AutoAttack] debug_level ' .. tostring(debug_level) .. ' = ' ..
            tostring(_names[debug_level] or '?') .. ' | file log ' .. (DEBUG_LOG_FILE and 'ON' or 'OFF') ..
            ((debug_level >= 2 and DEBUG_LOG_FILE) and (' -> data/logs/aa_' .. os.date('%Y-%m-%d') .. '.log') or ''))
    elseif command == 'target' then
        -- v4.07: //aa target [packet|native] -- how set_target() puts the cursor on a mob
        local _m = subcmd and subcmd:lower()
        if _m == 'packet' or _m == 'native' then
            settings.target_mode = _m
            config.save(settings)
        elseif _m then
            windower.add_to_chat(8, '[AutoAttack] Usage: //aa target packet | native')
        end
        windower.add_to_chat(8, '[AutoAttack] Target mode: ' .. tostring(settings.target_mode) ..
            ((settings.target_mode == 'native') and ' (no injected packets -- uses /targetbnpc)'
                                                  or ' (injected 0x058 target lock)'))
    elseif command == 'config' then
        -- v4.63: //aa config new -- settings aa_config.lua doesn't have (defaults in use)
        local list = AA_CFG_NEW or {}
        if #list == 0 then
            windower.add_to_chat(207, '[AA] ' .. AA_CONFIG_FILE .. ' has every setting -- nothing new.')
        else
            windower.add_to_chat(207, '[AA] ' .. #list .. ' setting(s) not in ' .. AA_CONFIG_FILE ..
                ' -- these defaults are in use (copy a line into ' .. AA_CONFIG_FILE .. ' to change it):')
            for _, e in ipairs(list) do
                windower.add_to_chat(207, '[AA]   ' .. e.path .. ' = ' .. aa_cfg_fmt(e.value))
            end
        end
    elseif command == 'rings' then
        -- v4.08: //aa rings [reset] -- show ring waits; reset clears them all
        local _now = os.time()
        local _reset = subcmd and subcmd:lower() == 'reset'
        for id, t in pairs(ring_locks) do
            local it = aa_item(tonumber(id))   -- v4.61
            local nm = it and it.en or tostring(id)
            local left = (tonumber(t) or 0) - _now
            if _reset then
                ring_locks[id] = 0
            elseif left > 0 then
                windower.add_to_chat(8, string.format('[AutoAttack] %s: next try in %dh %02dm', nm,
                    math.floor(left / 3600), math.floor((left % 3600) / 60)))
            end
        end
        if _reset then
            settings.locks = ring_locks
            config.save(settings)
            ring_retry_at, ring_fail_count, ring_refuse_level, ring_warned = {}, {}, {}, {}
            windower.add_to_chat(8, '[AutoAttack] Ring waits cleared -- rings will be tried on the next combat tick.')
        else
            windower.add_to_chat(8, '[AutoAttack] //aa rings reset -- clear all ring waits')
        end
    elseif command == 'dumpinv' then
        dump_inventory()
    elseif command == 'id' then
        -- v3.86: show the current target's mob ID (for mob_blacklist entries)
        local _t = windower.ffxi.get_mob_by_target('t')
        if _t and _t.id then
            windower.add_to_chat(8, string.format('[AutoAttack] %s  ID: %d  (index %d / 0x%03X)%s',
                tostring(_t.name), _t.id, _t.index or 0, _t.index or 0,
                is_mob_name_blacklisted(_t.name, _t.id) and '  [BLACKLISTED]' or ''))
        else
            windower.add_to_chat(8, '[AutoAttack] No target.')
        end
    elseif command == 'pet' then
        -- v3.94: pet diagnostics
        local _pt = windower.ffxi.get_mob_by_target('pet')
        if _pt then
            windower.add_to_chat(8, string.format('[AutoAttack] Pet: %s  HP %d%%  TP %d  status %s  target %d%s',
                tostring(_pt.name), _pt.hpp or 0, pet_state.tp or 0, tostring(_pt.status),
                pet_state.target_id or 0, (_pt.status == 1) and '  [ENGAGED]' or ''))
        else
            windower.add_to_chat(8, '[AutoAttack] No pet out.')
        end
        local _pc = current_config and current_config.pet
        windower.add_to_chat(8, '[AutoAttack] pet block: ' .. (_pc and ((_pc.enabled == false) and 'disabled' or 'enabled') or 'none for this job'))
    elseif command == 'ds' or command == 'dreadspikes' then
        -- v4.32: //aa ds [clear]
        ds_command(subcmd and subcmd:lower())
    elseif command == 'fullparty' or command == 'fp' then
        -- v4.54: //aa fullparty [on|off|fix] -- no argument shows it
        local _m = subcmd and subcmd:lower()
        if _m == 'off' then FULL_PARTY_PULL = false
        elseif _m == 'on' then FULL_PARTY_PULL = true; fp.stuck_zone = nil
        elseif _m == 'fix' then fp.ghost = true; fp.fix_at = -1e9; fp.stuck_zone = nil; last_trust_check_time = 0
        elseif _m then windower.add_to_chat(8, '[AutoAttack] Usage: //aa fullparty [on|off|fix]') end
        local _f, _n, _w, _t = full_party_state()
        windower.add_to_chat(8, string.format('[AutoAttack] Full party rule %s -- %d/%d Trusts, %d/6 in party%s.%s',
            FULL_PARTY_PULL and 'ON' or 'OFF (this session)', _n, _w, _t, _f and '' or ' (NOT full)',
            _m == 'fix' and ' Ghost slot fix (/retr all + call Trusts) on the next idle tick.' or ''))
    elseif command == 'gsc' then
        gsc_command(subcmd)   -- v4.70: //aa gsc [on|off|auto]
    elseif command == 'report' then
        pstat_report()        -- v4.99: party report now
    elseif command == 'ws' then
        -- v4.33: //aa ws [off|on] -- no argument shows the current state
        local _m = subcmd and subcmd:lower()
        if _m == 'off' or _m == 'disable' or _m == '0' then
            ws_cmd_off = true
            ws_sc_locked = false
            windower.add_to_chat(8, '[AutoAttack] Weapon skills OFF (until //aa ws on or the addon is reloaded).')
        elseif _m == 'on' or _m == 'enable' or _m == '1' then
            ws_cmd_off = false
            windower.add_to_chat(8, '[AutoAttack] Weapon skills ON (ws_mode: ' .. tostring(ws_mode and ws_mode.type) .. ').')
        elseif _m == nil then
            windower.add_to_chat(8, '[AutoAttack] Weapon skills are ' .. (ws_cmd_off and 'OFF (//aa ws off)' or 'ON') ..
                ' -- ws_mode: ' .. tostring(ws_mode and ws_mode.type) .. '. Use //aa ws off | on.')
        else
            windower.add_to_chat(8, '[AutoAttack] Usage: //aa ws [off|on]')
        end
    else
        -- 'help', unrecognized commands, or //aa with no argument all land here.
        if command ~= 'help' then
            windower.add_to_chat(8, '[AutoAttack] Unknown command: ' .. tostring(command))
        end
        windower.add_to_chat(8, '[AutoAttack] v' .. _addon.version .. ' -- //aa assist | pull [n|s|e|w|...] | stop | move [off|pull|provoke|melee|target|n] | debug [0|1|2] | target [packet|native] | rings [reset] | ds [clear] | ws [off|on] | gsc [on|off|auto|?|k|sync|report] | report | fullparty [on|off|fix] | dumpinv | id | pet')
        windower.add_to_chat(8, '[AutoAttack] party: //aa invite me|<name> [sync <n>] [leader <n>] [fight] | fight | stop | stack | follow [n] | unfollow | cancel | disband | leave | leader <n> | sync <n> | unsync | trusts [grp] | retr | retrust | rest | mount [n] | dismount | pass | lot | sneak | invis | warp | nav <name> | status | ping | party')
    end
end
windower.register_event('addon command', aa_addon_command)   -- v4.69



-- v4.34: backup death check -- status 2 / 3 = dead (missed packet, DoT, etc.)
windower.register_event('status change', function(new_status, old_status)
    if new_status == 2 or new_status == 3 then aa_on_defeated('status ' .. new_status) end
end)

-- v3.00: Reset volatile state on zone/login/logout to prevent stale data crashes
-- v4.18: the event is 'zone change' (with a space). 'zone_change' was never
-- registered (console: "Unknown event: zone_change"), so none of this ran.
windower.register_event('zone change', function(new_id, old_id)
    PARTY_BUFFS = {}   -- v4.95
    if auto_attack then
        info_msg('Zone change detected: stopping auto-attack.')
        auto_attack = false
    end
    purple_limbo_until = 0; purple_from_packet = false; cant_see_flag = false
    stale_pull_id = 0; stale_pull_count = 0; stale_pull_time = 0
    last_target_id = 0; cant_target_ids = {}; cant_target_counts = {}
    last_pull_next_mob_id = nil; last_pull_next_mob_time = 0
    cant_see_strikes = {}; stuck_watch_id = 0; stuck_watch_start = 0  -- v3.83
    pet_state.tp = 0; pet_state.target_id = 0  -- v3.94
    cant_see_strike_time = {}; mob_hits = {}                  -- v4.18
    dead_cursor_pending_id = nil; native_target_busy = false  -- v4.18
    target_quiet_until = 0                                    -- v4.18
    ds_leave('zoned'); ds_mobs = {}                           -- v4.32 (mob IDs are per zone)
    trust_fails = {}; trust_skip = {}; trust_pending = {}     -- v4.34
end)
windower.register_event('login', function()
    aa_log_char = nil; aa_log_close(); aa_dbg_file_key = nil   -- v4.59: new character -> its own log file
    auto_attack = false; purple_limbo_until = 0; purple_from_packet = false
    cant_see_flag = false; last_target_id = 0
    last_pull_next_mob_id = nil; last_pull_next_mob_time = 0
    -- v4.18: config.lua reloads settings on login (this character's section);
    -- re-point ring_locks at it and load this character's job config.
    if settings and settings.locks then ring_locks = settings.locks end
    cant_target_ids = {}; cant_target_counts = {}; cant_see_strikes = {}
    cant_see_strike_time = {}; mob_hits = {}
    dead_cursor_pending_id = nil; native_target_busy = false
    update_job_configs()
end)
windower.register_event('logout', function()
    auto_attack = false
    pcall(gsc_k_save)   -- v4.90
    aa_log_char = nil; aa_log_close(); aa_dbg_file_key = nil   -- v4.59: next lines go to the next character's file
    dead_cursor_pending_id = nil; native_target_busy = false  -- v4.18
end)
-- v4.18: job change -> reload this job's config (was only done on //aa pull|assist)
windower.register_event('job change', function()
    update_job_configs()
    GSC.learned = nil   -- v4.90: the new job's WS list for the next profile
end)

-- v3.98: Main-loop watchdog. Checked every 5s. If auto_attack is on but the
-- loop's heartbeat (aa_loop_beat) is older than AA_WATCHDOG_STALL, the loop
-- coroutine died -- most likely a Lua runtime error (Windower prints it to the
-- console). Restart it, at most 5 times per 30 minutes, then stop for good so a
-- repeating error can't spin forever.
-- v4.11: HEARTBEAT every 10 min into the chat log, so the minutes before a
-- crash show session length, AA's Lua memory and the kill / dead-cursor
-- counts (memory-growth vs. per-kill-event clues).
HEARTBEAT_SECS   = 600
aa_hb_next       = os.clock() + 60
aa_hb_start      = os.clock()
aa_prune_next    = os.clock() + 60   -- v4.18
aa_frame_last, aa_stall_next = 0, 0   -- v4.25
windower.register_event('prerender', function()
    local now = os.clock()
    -- v4.25: keep the ms wall clock anchored (see aa_wall_clock)
    local _sec = os.time()
    if _sec ~= aa_wc_sec then
        if aa_wc_sec ~= 0 then aa_wc_wall, aa_wc_clock = _sec, now end
        aa_wc_sec = _sec
    end
    -- v4.25: DEV frame-stall check (client froze / hitched between frames)
    if (debug_level or 0) >= 2 then
        local _gap = now - aa_frame_last
        if aa_frame_last > 0 and _gap > DEBUG_FRAME_STALL and now >= aa_stall_next then
            aa_stall_next = now + 2
            debug_msg(string.format('TIMING: client frame stall %.2fs (loop stage \'%s\').', _gap, tostring(aa_tick_stage)))
        end
        aa_frame_last = now
    end
    if now >= aa_hb_next then
        aa_hb_next = now + HEARTBEAT_SECS
        pcall(function()
            local up = now - aa_hb_start
            debug_msg(string.format('HEARTBEAT up %dh%02dm | AA lua %.0f KB | item list loads %d | dead cursors %d | tgt fallbacks %d | mode %s | auto %s',
                math.floor(up / 3600), math.floor((up % 3600) / 60), collectgarbage('count'), aa_items_loads or 0,
                dead_cursor_count or 0, pkt_fallbacks or 0, tostring(settings and settings.target_mode), tostring(auto_attack)))
        end)
    end
    -- v4.18: prune blacklists / mob_hits every 60s from here too. The main
    -- loop only prunes between fights in PULL mode; ASSIST idles in status 0.
    if now >= aa_prune_next then
        aa_prune_next = now + 60
        pcall(prune_blacklists)
    end
    -- v4.61: drop the full item list once it hasn't been used for a while
    if aa_items_loaded_at and (now - aa_items_loaded_at) >= ITEMS_KEEP_SECS then
        pcall(aa_items_release)
    end
    if now < aa_wd_next then return end
    aa_wd_next = now + 5
    if not auto_attack then return end
    local stalled = now - (aa_loop_beat or 0)
    if stalled < AA_WATCHDOG_STALL then return end
    local recent = {}
    for _, t in ipairs(aa_wd_restarts) do
        if (now - t) < 1800 then recent[#recent + 1] = t end
    end
    aa_wd_restarts = recent
    if #recent >= 5 then
        auto_attack = false
        windower.add_to_chat(167, '[AutoAttack] WATCHDOG: main loop died 5 times in 30 min -- stopping. ' ..
            'Check the Windower console for the Lua error.')
        return
    end
    recent[#recent + 1] = now
    windower.add_to_chat(167, string.format('[AutoAttack] WATCHDOG: main loop silent for %ds ' ..
        '(likely a Lua error -- see Windower console). Restarting (%d in last 30 min).',
        math.floor(stalled), #recent))
    if pstat_event then pcall(pstat_event, 'watchdog', 'main loop restarted after ' .. math.floor(stalled) .. 's silent') end   -- v4.99
    start_main_loop()
end)

windower.register_event('action', function(action)
    local _ok2, _err2 = pcall(function()
    if not action or not action.targets then return end

    -- v3.83: stuck watchdog -- remember when we last melee'd / WS'd / shot / cast
    -- on something other than ourselves (cat 1 melee, 2 ranged, 3 WS, 4 spell).
    local _cat = action.category
    ds_on_action(action)  -- v4.32: Dread Spikes tracking
    gsc_on_action(action) -- v4.70: group skillchain
    pcall(pstat_on_action, action)   -- v4.99: party report

    -- v3.87: Provoke confirmation for provoke_fire_confirmed()
    if _cat == 6 and provoke_pending.active and provoke_pending.ja_id
       and action.param == provoke_pending.ja_id then
        local _me_p = windower.ffxi.get_player()
        if _me_p and action.actor_id == _me_p.id then
            provoke_pending.confirmed = true
        end
    end

    -- v3.93: remember our last melee round / WS and on which mob (engaged_pull_logic)
    -- v3.97: also count our JAs on the mob (cat 6 / 14, e.g. Jump, High Jump) as
    -- contact -- they replace a melee round. Provoke excluded (it's used at range).
    local _prov_ja = (_cat == 6 and provoke_pending.ja_id and action.param == provoke_pending.ja_id)
    if _cat == 1 or _cat == 3 or _cat == 14 or (_cat == 6 and not _prov_ja) then
        local _me_s = windower.ffxi.get_player()
        local _t_s = action.targets[1]
        if _me_s and action.actor_id == _me_s.id and _t_s and _t_s.id and _t_s.id ~= _me_s.id then
            melee_swing.id = _t_s.id
            melee_swing.time = os.clock()
        end
    end

    -- v4.35: melee rounds only (WS / JAs don't count) -- RE-ENGAGE check
    if _cat == 1 then
        local _me_r = windower.ffxi.get_player()
        local _t_r = action.targets[1]
        if _me_r and action.actor_id == _me_r.id and _t_r and _t_r.id and _t_r.id ~= _me_r.id then
            melee_round.id = _t_r.id
            melee_round.time = os.clock()
            if mob_hits[_t_r.id] then mob_hits[_t_r.id].mn = 0 end   -- v4.38
        end
    end

    -- v4.14: opener gate -- only a real melee round (cat 1) or WS (cat 3) counts
    if _cat == 1 or _cat == 3 then
        local _me_o = windower.ffxi.get_player()
        local _t_o = action.targets[1]
        if _me_o and action.actor_id == _me_o.id and _t_o and _t_o.id and _t_o.id ~= _me_o.id then
            melee_contact.id = _t_o.id
            melee_contact.time = os.clock()
        end
    end

    -- v4.02: remember who each actor last hit (melee / TP move / spell) for
    -- mob_hit_victim(): a mob hitting you or a Trust is in our fight.
    if _cat == 1 or _cat == 11 or _cat == 4 then
        local _th = action.targets[1]
        if _th and _th.id and action.actor_id and action.actor_id ~= _th.id then
            local _h = mob_hits[action.actor_id]   -- v4.18: reuse the entry (no table per action)
            if _h then _h.t = os.clock(); _h.tid = _th.id
            else _h = {t = os.clock(), tid = _th.id, mn = 0}; mob_hits[action.actor_id] = _h end
            -- v4.38: count the mob's attack rounds on us (reset by our melee round on it)
            if _cat == 1 then
                local _me_h = windower.ffxi.get_player()
                if _me_h and _th.id == _me_h.id then _h.mn = (_h.mn or 0) + 1 end
            end
        end
    end

    if _cat == 1 or _cat == 2 or _cat == 3 or _cat == 4 then
        local _me_a = windower.ffxi.get_player()
        if _me_a and action.actor_id == _me_a.id then
            local _t1 = action.targets[1]
            if _cat ~= 4 or (_t1 and _t1.id and _t1.id ~= _me_a.id) then
                last_offense_time = os.clock()
            end
        end
    end

    for _, target in pairs(action.targets) do
        if target and target.actions then
            for _, act in pairs(target.actions) do
                -- v5.00: the skillchain by name (any WS message), for the burst elements
                if act and act.has_add_effect and GSC_SC_MSG and GSC_SC_MSG[act.add_effect_message] then
                    MB_SC = {name = GSC_SC_MSG[act.add_effect_message], t = os.clock(), mob = target.id}
                end
                if act and act.message == 185 and act.has_add_effect then
                    local sc_id = act.add_effect_animation
                    if sc_id then
                        local element = sc_id_to_element[sc_id]
                        -- debug_msg('SC: sc_id=' .. tostring(sc_id) .. ' -> element=' .. tostring(element))
                        if element then
                            skillchain_element = element
                            skillchain_time = os.clock()
                            -- debug_msg('SC detected! element=' .. element .. ' MB window open (' .. SC_WINDOW .. 's)')
                        else
                            debug_msg('SC: Unknown sc_id=' .. tostring(sc_id) .. ' - add to sc_id_to_element table')
                        end
                    end
                end
            end
        end
    end
    end)
    if not _ok2 then info_msg('Action handler error: ' .. tostring(_err2)) end
end)

end  -- AA_MAIN (v4.65)

-- v4.65: start AutoAttack; on failure right after an aa update, roll back
do
    local ok, err = xpcall(AA_MAIN, function(e)
        return (debug and debug.traceback) and debug.traceback(tostring(e), 2) or tostring(e)
    end)
    if not ok and not aa_start_failed(err) then error(err, 0) end
end
