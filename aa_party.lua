--[[
    aa_party.lua -- AutoAttack party commands (v4.44, v4.45: retrust / lot, v4.46: Trust join window,
    v4.47: aa stack goes to the exact X/Y, v4.48: aa stack always on the leader,
    v4.49: Trust waits report every 10s, v4.50: fast assist for aa fight members,
    v4.51: aa sneak / invis, v4.52: aa warp / aa 299, v4.53: Warp Ring on the right ring,
    old ring put back, v4.57: aa disband drops Trusts first, then breaks up,
    v4.58: aa disband clears a leftover party of 1,
    v4.60: aa reload [all], v4.61: slim item lookups (aa_item / aa_item_named),
    v4.62: aa update [all|force] -- newest release from GitHub, then reload,
    v4.64: aa update fix -- no yield inside pcall,
    v4.65: aa update check | aa version | aa rollback [all] | richer ping,
    v4.67: your own party line runs on your own character too, however it
    was typed (/p, party chat mode, macro) -- caught from the party echo,
    v4.68: party lines go out at least 2s apart -- a reply right after your
    own line was dropped by the game,
    v4.69: pull / assist / ws / move / ds answer the sender,
    v4.70: aa gsc [on|off|auto] -- group skillchain switch, answers the sender,
    v4.90: aa gsc ? -- every AA re-sends its profile; aa~g lines are hidden,
    v5.52: aa fight member's corpse switch is verified; engage packet when /attack on didn't take,
    v5.56: aa leader <name> sync <name> (either order): sync first, then the leader is passed,
    v5.57: waiting for a fight to end (invite / retrust): 3 min, sender gets mob HP% every 30s,
    v4.75: stacking watch -- aa fight members re-stack on the leader mid-fight
    (within restack_max), the leader keeps its aa fight spot),
    v5.06: aa nav <zone or place> -- fastest warp there (nav.lua); /p aa nav = every AA
    in the party, each its own fastest way; aa_nav_ring = rings on ring2 like aa warp)

    Loaded by autoattack.lua. Lets your friends (party.friends in
    aa_config.lua) control this character's AutoAttack with /tell or party
    chat. Every command starts with "aa":

        /tell Shadowhammer aa invite me sync shadow leader myth fight
        /p aa fight

    Only names in party.friends are obeyed. Party-chat commands are only
    obeyed from friends who are in your party. Replies always start with
    "[AA]", and AA-to-AA messages with "aa~", so one AA never sets off
    another by accident.

    Commands (by /tell, by /p, or typed here as //aa <command>):
      invite me|<name> [sync <name>] [leader <name>] [fight]
      fight | stop | stack | follow [name] | unfollow | cancel
      disband | leave | leader <name> | sync <name> | unsync
      trusts [group] | retr | retrust | rest | mount [name] | dismount | pass | lot
      status | ping | help | version | reload [all] | update [all|force|check] | rollback [all]
      pull [dir] | assist | ws on|off | move <mode> | ds [clear] | gsc [on|off|auto]   (answer the sender)
      nav <zone or place> | nav cancel   (v5.06: each AA warps there its own fastest way)
      //aa party   (typed only) -- friends, settings and what the party code is doing

    See README.md "Party commands" for the details.
]]

local packets = require('packets')
local res     = require('resources')

local P = {gen = 0, busy = nil, step = 'idle', replies = {},
           follow = nil, follow_fight = false, stack = nil, running = false,
           said = {}, invite_from = nil, move_next = 0,
           last_join = nil, watch_next = 0, watch_players = nil, watch_lead = nil,
           leader_id = nil, engaging = false, fast_last = {}}
AA_PARTY = P

-- ---------------------------------------------------------------------------
-- settings
-- ---------------------------------------------------------------------------
local D = {
    enabled        = true,
    friends        = {},
    party_range    = 1,      -- yalms: "on top of each other" (aa fight / aa stack)
    stack_precision = 0.3,   -- yalms: aa stack / aa fight stop this close to the exact X/Y
    follow_range   = 1,      -- yalms: how close aa follow keeps you
    stack_watch    = true,   -- v4.75: aa fight members re-stack on the leader when they drift
    restack_slack  = 1.0,    -- v4.75: yalms past party_range before a re-stack
    restack_max    = 10,
    switch_verify  = true,   -- v5.52: aa fight member's switch off a corpse is watched (/attack on if the game drops you)
    engage_packet  = true,   -- v5.52: /attack on that didn't take -> engage packet once
    assist_fallback = true,  -- v5.48: fast assist uses the game's /assist <leader> when the target packet misses     -- v4.75: farthest a member re-stacks while fighting (farther: between fights)
    restack_delay  = 2,      -- v4.75: s off the stack before re-stacking
    restack_far_secs = 20,   -- v4.78: farther than restack_max this long while fighting: re-stack anyway (0 = never)
    stack_after_kill = true, -- v5.02: aa fight members stack on the leader after every kill
    stack_kill_min = 0.5,    -- v5.02: yalms off the leader before the after-kill stack runs
    stack_kill_max = 30,     -- v5.02: farthest a member runs for the after-kill stack
    stack_on_oor   = true,   -- v5.02: melee out of range while engaged -> stack on the leader
    stack_timeout  = 30,     -- s a member runs toward the leader before giving up
    stack_wait     = 5,      -- s the leader waits for members to stack before the first pull
    trust_wait     = 120,    -- s after dropping trusts before the inviting leader calls them again
    finish_timeout = 180,    -- s to finish the mobs fighting the party before an invite / retrust is cancelled (v5.57: 300 -> 180)
    finish_progress = 30,    -- v5.57: s between "still fighting: <mob> at N% HP" replies to the sender
    reply_timeout  = 8,      -- s to wait for another character's AA to answer
    auto_accept    = true,   -- accept party invites from friends
    mount          = 'Raptor',
    warp_ring      = 'Warp Ring',  -- aa warp without a Warp II mage
    warp_ring_delay = 11,    -- s between equipping the Warp Ring and using it
    warp_claim_wait = 3,     -- s for the party's Warp II mages to speak up
    warp_wait      = 90,     -- s to wait for the mage's Warp II before using the ring
    retr_command   = '/retr all',
}
local function opt(k)
    local c = AA_CFG and AA_CFG.party
    local v = nil
    if type(c) == 'table' then v = c[k] end   -- v5.04: 'x and c[k] or nil' turned false into nil
    if v == nil then return D[k] end
    return v
end

-- friends: [lowercase name or nick] = proper name
local function friend_map()
    local map = {}
    for _, f in ipairs(opt('friends') or {}) do
        local name = type(f) == 'table' and f.name or f
        if type(name) == 'string' and name ~= '' then
            map[name:lower()] = name
            if type(f) == 'table' and type(f.nick) == 'string' and f.nick ~= '' then
                map[f.nick:lower()] = name
            end
        end
    end
    return map
end

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------
local function me() return windower.ffxi.get_player() end
local function my_name() local p = me(); return p and p.name or '' end
local function zone_id() local i = windower.ffxi.get_info(); return i and i.zone or 0 end
local function say(msg) info_msg('PARTY: ' .. msg) end
local function dbg(msg) if aa_dbg then aa_dbg('PARTY: ' .. msg) end end
local function send(str) if aa_send then aa_send(str) else windower.send_command(str) end end

local function is_friend(name)
    return name and friend_map()[name:lower()] ~= nil
end

-- 'me' -> sender; friend name or nickname -> proper name; your own name too.
local function resolve(word, sender)
    if not word then return nil end
    word = word:lower()
    if word == 'me' then return sender end
    local own = my_name()
    if own ~= '' and word == own:lower() then return own end
    return friend_map()[word]
end

-- A party member is a Trust when its entity is an NPC (entity IDs of
-- players are below 0x01000000). Members out of range have no mob: players.
local function is_trust(m)
    local mob = m and m.mob
    return mob ~= nil and (mob.is_npc == true or (mob.id or 0) >= 0x1000000)
end

local function members()
    local list, party = {}, windower.ffxi.get_party()
    if not party then return list, nil end
    for i = 0, 5 do
        local m = party['p' .. i]
        if m and m.name then
            list[#list + 1] = {key = 'p' .. i, name = m.name, id = m.id or (m.mob and m.mob.id),
                               zone = m.zone, mob = m.mob, trust = is_trust(m)}
        end
    end
    return list, party
end
local function member(name)
    if not name then return nil end
    for _, m in ipairs(members()) do
        if m.name:lower() == name:lower() then return m end
    end
    return nil
end
local function players()    -- real players in the party (you included)
    local n = 0
    for _, m in ipairs(members()) do if not m.trust then n = n + 1 end end
    return math.max(n, 1)
end
local function trust_count()
    local n = 0
    for _, m in ipairs(members()) do if m.trust then n = n + 1 end end
    return n
end
local function has_players() return players() > 1 end
local function leader_name()
    local list, party = members()
    if not party or not has_players() then return my_name() end
    local lid = party.party1_leader
    for _, m in ipairs(list) do
        if lid and m.id == lid then return m.name end
    end
    if party.p0 and party.p0.is_leader then return my_name() end
    return nil
end
local function i_lead()
    if not has_players() then return true end
    return leader_name() == my_name()
end
local function engaged() local p = me(); return p and p.status == 1 end

local function my_mob()
    local p = me()
    return p and p.id and windower.ffxi.get_mob_by_id(p.id) or nil
end
local function dist_to_name(name)
    local a, b = my_mob(), name and windower.ffxi.get_mob_by_name(name)
    if not a or not b or not a.x or not b.x then return nil, b end
    local dx, dy = b.x - a.x, b.y - a.y
    return math.sqrt(dx * dx + dy * dy), b
end

-- A mob is fighting the party: claimed by you / a member / Trust, targeting
-- one of you, or has hit one of you (hs_is_hot in autoattack.lua). Mobs that
-- are only nearby don't count.
local function party_fighting()
    local p = me()
    if not p then return false end
    if p.status == 1 then return true end
    local mobs = windower.ffxi.get_mob_array()
    if not mobs or not hs_party_sets or not hs_is_hot then return false end
    local ids, idx = hs_party_sets(p)
    for _, m in pairs(mobs) do
        if type(m) == 'table' and m.spawn_type == 16 and m.hpp and m.hpp > 0 and m.valid_target
           and hs_is_hot(m, ids, idx) then
            return true, m
        end
    end
    return false
end

-- trusts to aim for: the job's max_trusts, the zone limit, and 6 per party
local function trusts_wanted()
    local cfg = aa_get_config and aa_get_config()
    local tc = cfg and cfg.trusts
    if not tc or not tc.enabled then return 0 end
    local n = tc.max_trusts or 5
    if get_max_trusts then n = math.min(n, get_max_trusts()) end
    return math.max(0, math.min(n, 6 - players()))
end

-- ---------------------------------------------------------------------------
-- talking
-- ---------------------------------------------------------------------------
local function tell(name, text) send('input /tell ' .. name .. ' ' .. text) end

-- v4.68: party chat lines from this character go out at least PARTY_GAP s
-- apart. Mythrandiir's own "aa version" (02:01:12) ran and its reply was sent
-- 0.57s later, but never showed in party chat: the game drops a second party
-- line sent that fast. P.party_last = when our last party line went out (or
-- is scheduled to); a later line is scheduled after the gap -- never a
-- coroutine.sleep here (reply runs inside do_update's pcall, see v4.64).
local PARTY_GAP = 2
P.party_last = P.party_last or -99
local function party_say(line)
    local now = os.clock()
    local wait = P.party_last + PARTY_GAP - now
    if wait > 0 then
        P.party_last = now + wait
        dbg(string.format('party line held %.1fs: %s', wait, line))
        coroutine.schedule(function() send('input /p ' .. line) end, wait)
    else
        P.party_last = now
        send('input /p ' .. line)
    end
end
function aa_party_say(line) party_say(line) end   -- v4.90: autoattack.lua's GSC lines
local function party_sent_now()   -- a party line of ours just went out (typed or macro)
    P.party_last = math.max(P.party_last, os.clock())
end

-- ctx = {src = 'tell' | 'party' | 'local', sender = name}
local function reply(ctx, text)
    text = '[AA] ' .. text
    if ctx.src == 'tell' and ctx.sender then
        tell(ctx.sender, text)
    elseif ctx.src == 'party' then
        P.said[text:lower()] = os.clock()
        party_say(text)   -- v4.68
    else
        windower.add_to_chat(207, text)
    end
    dbg('reply (' .. ctx.src .. '): ' .. text)
end

local handle_command  -- forward

-- Say an "aa ..." command in party chat, and run it here too (your own party
-- line may not come back to you as a chat message).
local function party_command(text)
    P.said[text:lower()] = os.clock()
    party_say(text)   -- v4.68
    local me_name = my_name()
    coroutine.schedule(function()
        handle_command({src = 'party', sender = me_name, self = true}, text)
    end, 0.5)
end

function aa_party_run(text) party_command(text) end   -- v5.06: nav.lua's party lines

-- ---------------------------------------------------------------------------
-- running a sequence (one at a time; aa cancel stops it)
-- ---------------------------------------------------------------------------
local function begin(ctx, name)
    if P.busy then
        reply(ctx, my_name() .. ' is busy: ' .. P.busy .. ' (' .. P.step .. '). Send "aa cancel" to stop it.')
        return nil
    end
    P.gen = P.gen + 1
    P.busy, P.step = name, 'starting'
    say('START ' .. name)
    return P.gen
end
local function alive(g) return g == P.gen end
local function done(g, ctx, text)
    if not alive(g) then return end
    P.busy, P.step = nil, 'idle'
    if text then reply(ctx, text) end
end
local function fail(g, ctx, text)
    if not alive(g) then return end
    say('STOPPED ' .. tostring(P.busy) .. ': ' .. text)
    P.busy, P.step = nil, 'idle'
    reply(ctx, text)
end
local function sleep(g, s)
    coroutine.sleep(s)
    return alive(g)
end

-- AA-to-AA question: tell "aa~<verb> <n> <args>", wait for "aa~r <n> <answer>"
local function ask(g, name, verb, args)
    local n = tostring(math.random(1000, 9999))
    P.replies[n] = nil
    tell(name, 'aa~' .. verb .. ' ' .. n .. (args and (' ' .. args) or ''))
    local t0 = os.clock()
    while os.clock() - t0 < opt('reply_timeout') do
        coroutine.sleep(0.5)
        if not alive(g) then return nil end
        if P.replies[n] then
            local a = P.replies[n]; P.replies[n] = nil
            return a
        end
    end
    return nil
end

-- where is <name>? {zone, p (0 no party | 1 Trusts only | 2 with players), e, l}
local function where(g, name)
    if name == my_name() then
        return {zone = zone_id(), p = has_players() and 2 or (trust_count() > 0 and 1 or 0),
                e = engaged() and 1 or 0, l = i_lead() and 1 or 0, mine = true}
    end
    local m = member(name)
    if m and m.zone then return {zone = m.zone, mine = true} end
    local a = ask(g, name, 'q')
    if not a then return nil end
    local t = {}
    for k, v in a:gmatch('(%a)(%d+)') do t[k] = tonumber(v) end
    t.zone = t.z
    return t.zone and t or nil
end

-- ---------------------------------------------------------------------------
-- moving: aa stack (run onto someone) and aa follow (stay with someone)
-- ---------------------------------------------------------------------------
local function run_stop()
    if P.running then windower.ffxi.run(false); P.running = false end
end

local function move_tick()
    local now = os.clock()
    -- v4.47: stacking checks every frame (it has to stop on an exact spot)
    if not P.stack then
        if now < P.move_next then return end
        P.move_next = now + 0.05
    end
    local name, range
    if P.stack then
        if now > P.stack.deadline then
            run_stop(); P.stack.result = false; P.stack = nil
            return
        end
        name, range = P.stack.name, opt('stack_precision')
    elseif P.follow and not P.follow_fight then   -- v5.05: aa follow only; aa fight doesn't follow
        name, range = P.follow, opt('follow_range')
    else
        run_stop()
        return
    end
    local p = me()
    -- engaged: the main loop does the moving (v4.75: except a re-stack on the
    -- leader). Dead / resting: don't move.
    if not p or (p.status == 1 and not (P.stack and P.stack.engaged_ok)) or p.status == 2
       or p.status == 3 or p.status == 33 or (mv and mv.active) then
        run_stop()
        return
    end
    local d, t = dist_to_name(name)
    if not d then run_stop(); return end
    local start_at = P.stack and range or (range + 0.5)   -- follow: a little slack so it doesn't stutter
    if d <= range or (not P.running and d <= start_at) then
        run_stop()
        if P.stack then
            -- v4.47: on the spot -- done once it holds for a few frames
            P.stack.hold = (P.stack.hold or 0) + 1
            if P.stack.hold >= 3 then
                if P.stack.engaged_ok and face_mob_direct then   -- v4.75: back on the mob
                    local tm = windower.ffxi.get_mob_by_target('t')
                    if tm and tm.hpp and tm.hpp > 0 then face_mob_direct(tm) end
                end
                P.stack.result = true; P.stack = nil
            end
        end
    else
        if P.stack then P.stack.hold = 0 end
        local a = my_mob()
        if a then
            -- v4.47: the last yalm in short steps (run one frame, check, run
            -- again) so it stops on the X/Y instead of running past it
            if P.stack and d < 1.0 and P.running then
                run_stop()
            else
                windower.ffxi.run(t.x - a.x, t.y - a.y)
                P.running = true
            end
        end
    end
end

-- run onto <name>'s exact X/Y (within stack_precision); true when there
local function stack_on(name, timeout, g, engaged_ok)
    P.stack = {name = name, deadline = os.clock() + (timeout or opt('stack_timeout')), engaged_ok = engaged_ok}
    local s = P.stack
    while s.result == nil do
        coroutine.sleep(0.2)
        if g and not alive(g) then
            if P.stack == s then P.stack = nil; run_stop() end
            return false
        end
    end
    return s.result
end

-- v4.75: STACKING WATCH (Mark, 2026-11-18: "we need to watch for this, and if
-- this happens, need to re-stack. Stacking while fighting is fine... as long
-- as they are already close (within 10 yalms)."). aa fight members only.
local function stack_watch()
    local now = os.clock()
    if now < (P.sw_next or 0) then return end
    P.sw_next = now + 0.5
    if not P.follow_fight or not P.follow or P.stack or opt('stack_watch') == false or not aa_running() then
        P.sw_since = nil
        return
    end
    local p = me()
    if not p or p.status ~= 1 then P.sw_since = nil; P.sw_far = nil; return end   -- not engaged: follow moves you
    if mv and mv.active then return end
    local d = dist_to_name(P.follow)
    if not d then return end
    if d <= opt('party_range') + opt('restack_slack') then P.sw_since = nil; P.sw_far = nil; return end
    if d > opt('restack_max') then
        if not P.sw_far then
            P.sw_far = now
            say(string.format('STACK: %.1fy from %s -- too far to re-stack mid-fight, stacking between fights.', d, P.follow))
        end
        -- v4.78: with hot switching "between fights" never comes -- after
        -- restack_far_secs go anyway (the mob follows you)
        local far = tonumber(opt('restack_far_secs')) or 0
        if far <= 0 or now - P.sw_far < far then return end
        P.sw_far = nil
        P.restacks = (P.restacks or 0) + 1
        say(string.format('STACK: still %.1fy from %s after %ds of fighting -- re-stacking now (%d this session).',
            d, P.follow, far, P.restacks))
        P.stack = {name = P.follow, deadline = now + opt('stack_timeout'), engaged_ok = true}
        return
    end
    P.sw_since = P.sw_since or now
    if now - P.sw_since < opt('restack_delay') then return end
    P.sw_since = nil
    P.restacks = (P.restacks or 0) + 1
    say(string.format('STACK: %.1fy from %s while fighting -- re-stacking (%d this session).', d, P.follow, P.restacks))
    P.stack = {name = P.follow, deadline = now + opt('stack_timeout'), engaged_ok = true}
end

-- ---------------------------------------------------------------------------
-- AutoAttack mode control
-- ---------------------------------------------------------------------------
local function start_mode(mode)
    if aa_running() then
        if aa_get_mode() ~= mode then
            aa_set_mode(mode)
            say('switched to ' .. mode:upper() .. ' mode.')
        end
    else
        send('aa ' .. mode)
    end
end

-- v5.57: the mob the party is fighting and its HP%, for the progress replies:
-- our own target when engaged, else the first mob on the party
local function fight_mob()
    local p = me()
    if p and p.status == 1 then
        local t = windower.ffxi.get_mob_by_target('t')
        if t and t.spawn_type == 16 and (t.hpp or 0) > 0 then return t end
    end
    local _, m = party_fighting()
    return m
end
local function mmss(s)
    s = math.max(0, math.floor(s + 0.5))
    return string.format('%d:%02d', math.floor(s / 60), s % 60)
end
-- no new pulls; wait until no mob is fighting the party (true) or timeout (false)
-- v5.57 (Mark, 11-25: "give it 3 minutes to finish fighting ... a response back
-- to the requestor ... that gives the current mob HP %, so that the sender can
-- tell there is progress being made"): with ctx, the sender gets a line at the
-- start and every finish_progress s: "<mob> at N% HP -- <what> when it's over;
-- gives up in m:ss".
local function finish_fights(g, timeout, ctx, what)
    if aa_running() and aa_get_mode() == 'pull' then aa_set_mode('assist') end
    local t0, quiet = os.clock(), 0
    local every = tonumber(opt('finish_progress')) or 30
    local next_at = t0
    while os.clock() - t0 < timeout do
        local fighting = party_fighting()
        if fighting then quiet = 0 else quiet = quiet + 1 end
        if quiet >= 3 then return true end
        local now = os.clock()
        if ctx and fighting and every > 0 and now >= next_at then
            local m = fight_mob()
            local mob = m and string.format('%s at %d%% HP', m.name or 'mob', m.hpp or 0) or 'a mob'
            local first = next_at == t0
            reply(ctx, string.format('%s %s -- %s when it\'s over; gives up in %s.',
                first and 'Finishing the current fight first (no new pulls):' or 'Still fighting:',
                mob, what or 'going on', mmss(timeout - (now - t0))))
            next_at = (first and now or next_at) + every
        end
        if not sleep(g, 1) then return false end
    end
    return false
end

-- call Trusts until the party is full (or nothing more can be called)
local function call_all_trusts(g)
    if trusts_wanted() == 0 then return end
    -- v4.46: calls that failed earlier (e.g. inside the 120s join window) must
    -- not keep these Trusts on the 10-minute skip list
    if aa_trust_reset then aa_trust_reset() end
    local t0, last, same = os.clock(), -1, 0
    while alive(g) and os.clock() - t0 < 120 do
        if engaged() then return end
        if trust_count() >= trusts_wanted() or #members() >= 6 then return end
        if aa_trust_recheck then aa_trust_recheck() end
        call_trusts()
        local n = trust_count()
        if n == last then
            same = same + 1
            if same >= 3 then return end
        else
            same = 0
        end
        last = n
        if not sleep(g, 2) then return end
    end
end

local function drop_trusts(g)
    if trust_count() == 0 then return true end
    send('input ' .. opt('retr_command'))
    local t0 = os.clock()
    while os.clock() - t0 < 15 do
        if trust_count() == 0 then return true end
        if not sleep(g, 0.5) then return false end
    end
    return trust_count() == 0
end

-- wait trust_wait from <since> (nil = no wait). v4.46: the game blocks Trust
-- magic for 120s after a player joins the party, so invites wait from the
-- join (they waited from the Trust drop, and not at all with no Trusts out).
local function latest(a, b)
    if not a then return b end
    if not b then return a end
    return math.max(a, b)
end
-- v4.49: a countdown line every 10s (debug level 1) while waiting
local TRUST_WAIT_REPORT = 10
local function trust_countdown(left, why)
    say(string.format('TRUSTS: %ds left before calling Trusts (%s).', math.ceil(left), why))
end

local function wait_trust_time(g, since)
    if not since then return true end
    local wait_s = opt('trust_wait') - (os.clock() - since)
    if wait_s <= 0 then return true end
    say('waiting ' .. math.floor(wait_s) .. 's before calling Trusts.')
    local t_end = os.clock() + wait_s
    local next_report = os.clock() + TRUST_WAIT_REPORT
    while os.clock() < t_end do
        local left = t_end - os.clock()
        P.step = 'waiting ' .. math.ceil(left) .. 's for Trusts'
        if os.clock() >= next_report then
            trust_countdown(left, 'game: none for 120s after a player joins')
            next_report = next_report + TRUST_WAIT_REPORT
        end
        if not sleep(g, 1) then return false end
    end
    say('TRUSTS: wait over -- calling Trusts.')
    return true
end

-- v4.46: seconds left in the 120s "no Trusts after a player joins" window
-- (0 = none). The window is the leader's; passing the leader clears it.
function aa_trust_hold()
    if not P.last_join then return 0 end
    local left = opt('trust_wait') - (os.clock() - P.last_join)
    if left <= 0 then P.last_join = nil; return 0 end
    return left
end

-- Level Sync has no text command: it is the party menu's 0x077 request
-- (Permissions 6 = sync to Target Name, 7 = Level Sync off).
local function level_sync(name, on)
    local ok, err = pcall(function()
        packets.inject(packets.new('outgoing', 0x077, {
            ['Target Name'] = name, ['Party Type'] = 0, ['Permissions'] = on and 6 or 7}))
    end)
    if not ok then say('Level Sync packet failed: ' .. tostring(err)) end
    return ok
end

-- v5.26: a new Level Sync while one is already on fails ("Level Sync could not
-- be activated. One or more party members are currently under the effect of a
-- status which prevents synchronization." -- 11-23 08:25, Myth's 02:32 sync
-- was still on; AA said "set" anyway). Now: same designee -> say so; another
-- designee -> turn the old sync off (the game takes 30s), wait, then sync.
-- The game's answer (activated / could not) decides what AA reports.
LEVEL_SYNC_BUFF = 269
local function sync_on()
    local p = me()
    for _, b in ipairs(p and p.buffs or {}) do if b == LEVEL_SYNC_BUFF then return true end end
    return false
end
windower.register_event('incoming text', function(original)
    if not original then return end
    if original:find('Level Sync activated', 1, true)
       or original:find('master level has been restricted', 1, true)
       or original:find('level has been restricted', 1, true) then
        P.sync_result, P.sync_ending = 'ok', nil
    elseif original:find('Level Sync could not be activated', 1, true) then
        P.sync_result = 'fail'
    elseif original:find('Level Sync will be deactivated', 1, true) then
        P.sync_ending = os.clock()
    elseif original:find('Level Sync effect wears off', 1, true) then
        P.sync_ending, P.sync_who = nil, nil
    end
end)

-- v5.27: retail ignores "Level Sync off" (0x077 ChangeKind 7) sent with the
-- leader's own name (11-23 09:01: no "will be deactivated" notice, 45s timeout).
-- The party menu sends it with the designee's name. The designee is flagged in
-- the party list packet 0x0DD: Flags (0x14, u16) bit 0x100 = LevelSyncFlg.
windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x0DD or not data or #data < 0x16 then return end
    local pid = data:byte(5) + data:byte(6) * 256 + data:byte(7) * 65536 + data:byte(8) * 16777216
    local flags = data:byte(0x15) + data:byte(0x16) * 256
    local name
    for _, m in ipairs(members()) do
        if m.id == pid then name = m.name; break end
    end
    if not name then
        local ok, p = pcall(packets.parse, 'incoming', data)
        name = ok and p and p['Name'] or nil
        if name == '' then name = nil end
    end
    if not name then return end
    if math.floor(flags / 256) % 2 == 1 then   -- bit 0x100
        if P.sync_who ~= name then dbg('Level Sync designee (0x0DD): ' .. name) end
        P.sync_who = name
    elseif P.sync_who and P.sync_who:lower() == name:lower() then
        P.sync_who = nil
    end
end)

-- send "Level Sync off" and watch for the game's 30s notice: designee's name
-- first, then each player (designee unknown), then our own name
local function sync_off_request(nap)
    local tried, names = {}, {}
    local function add(n) if n and n ~= '' and not tried[n:lower()] then tried[n:lower()] = true; names[#names + 1] = n end end
    add(P.sync_who)
    for _, m in ipairs(members()) do if not m.trust then add(m.name) end end
    add(my_name())
    for _, n in ipairs(names) do
        P.sync_ending = nil
        dbg('Level Sync off request with name ' .. n)
        level_sync(n, false)
        local t0 = os.clock()
        while not P.sync_ending and os.clock() - t0 < 3 do
            if not nap(0.5) then return nil end
        end
        if P.sync_ending then
            dbg('Level Sync off accepted (name ' .. n .. ')')
            return true
        end
    end
    return false
end

-- wait until the old sync is gone: our buff drops, or 32s after the game's
-- "will be deactivated in 30 seconds" (a member out of range never had the buff)
local function wait_sync_off(nap)
    local t0 = os.clock()
    while true do
        if os.clock() - t0 > 45 then return false end
        local ending = P.sync_ending
        if not sync_on() and (not ending or os.clock() - ending > 32) then
            if ending or os.clock() - t0 > 3 then return true end
        end
        if not nap(1) then return nil end
    end
end

-- nap(s) sleeps and returns false if the caller was cancelled
local function set_level_sync(ctx, who, nap)
    nap = nap or function(s) coroutine.sleep(s); return true end
    if P.sync_busy and os.clock() - P.sync_busy < 60 then
        reply(ctx, 'Level Sync change already in progress -- wait for it.')
        return false
    end
    P.sync_busy = os.clock()
    local function out(ok, text) P.sync_busy = nil; if text then reply(ctx, text) end; return ok end
    local was = P.sync_who
    if sync_on() and was and was:lower() == who:lower() then
        return out(true, 'Level Sync is already on ' .. who .. '.')
    end
    for attempt = 1, 2 do
        if sync_on() or P.sync_ending then
            if not P.sync_ending then
                say('Level Sync already on' .. (was and (' (' .. was .. ')') or '') .. ' -- turning it off first.')
                reply(ctx, 'Level Sync is already on' .. (was and (' ' .. was) or '') ..
                      ' -- turning it off, then syncing to ' .. who .. ' (about 30s).')
                local r = sync_off_request(nap)   -- v5.27
                if r == nil then return out(false) end
                if not r then
                    return out(false, 'The game ignored "Level Sync off" (tried ' ..
                               (was or 'every member') .. '). Remove it from the party menu, then aa sync ' .. who .. '.')
                end
            end
            local off = wait_sync_off(nap)
            if off == nil then return out(false) end
            if not off then return out(false, 'Old Level Sync did not end within 45s -- not syncing to ' .. who .. '.') end
            if not nap(1) then return out(false) end
        end
        if not member(who) then return out(false, who .. ' is not in the party -- no Level Sync.') end
        P.sync_result = nil
        level_sync(who, true)
        local t0 = os.clock()
        while not P.sync_result and os.clock() - t0 < 6 do
            if not nap(0.5) then return out(false) end
        end
        if P.sync_result == 'ok' or (P.sync_result == nil and sync_on()) then
            P.sync_who = who
            say('Level Sync set to ' .. who .. '.')
            return out(true, 'Level Sync set to ' .. who .. '.')
        end
        if P.sync_result ~= 'fail' then
            return out(false, 'No answer from the game on Level Sync to ' .. who .. '.')
        end
        if attempt == 1 then
            -- refused: an old sync we could not see (not on us) may still be on --
            -- send "off" once and watch for the game's 30s notice
            say('Level Sync to ' .. who .. ' refused -- trying "sync off" first.')
            local r = sync_off_request(nap)   -- v5.27
            if r == nil then return out(false) end
            if not r then break end
            reply(ctx, 'An old Level Sync was still on -- ending it, then syncing to ' .. who .. ' (about 30s).')
        end
    end
    return out(false, 'Level Sync to ' .. who .. ' could not be activated: a party member has a status ' ..
               'that blocks it (e.g. Level Restriction from capped content).')
end

-- ---------------------------------------------------------------------------
-- aa fight: the leader pulls, members assist the leader's pulls
-- ---------------------------------------------------------------------------
-- v4.75: ASSIST / PULL on their own mean "stay where you are" (Mark, 11-18:
-- "If the player runs ASSIST, then they want to stay where they are. but if
-- aa fight is ran, we want to stack and fight."). They end aa fight's
-- following, re-stacking and the leader's fight spot. aa fight itself starts
-- ASSIST / PULL, so commands within FIGHT_OWN_SECS of it don't count.
FIGHT_OWN_SECS = 3
local function leave_fight_mode(why)
    if os.clock() - (P.fight_at or -99) < FIGHT_OWN_SECS then return end
    local had = P.follow_fight or (AA_ANCHOR ~= nil)
    if P.follow_fight then P.follow, P.follow_fight = nil, false; P.stack = nil; run_stop() end
    if aa_clear_anchor then aa_clear_anchor(why) end
    if had then say('FIGHT mode off (' .. why .. ') -- staying where you are, no stacking.') end
end

local function do_fight(ctx)
    P.fight_at = os.clock()   -- v4.75: the ASSIST / PULL this starts keeps fight mode
    if gsc_on_fight then pcall(gsc_on_fight) end   -- v4.90: profiles + learned damage
    if i_lead() then
        P.follow, P.follow_fight = nil, false
        -- wait (stack_wait at most) for party members in this zone to stack on us
        local t0 = os.clock()
        while os.clock() - t0 < opt('stack_wait') do
            local all = true
            for _, m in ipairs(members()) do
                if not m.trust and m.name ~= my_name() and m.zone == zone_id() then
                    local d = dist_to_name(m.name)
                    if not d or d > opt('party_range') + 0.5 then all = false; break end
                end
            end
            if all then break end
            coroutine.sleep(0.5)
        end
        -- v4.46: Trusts first. Inside the join window wait it out, then call
        -- them -- never pull with an empty party because the calls failed.
        if trusts_wanted() > 0 and trust_count() < trusts_wanted() and not engaged() then
            local g = P.gen
            local left = aa_trust_hold()
            if left > 0 then
                say(string.format('FIGHT: waiting %ds (no Trusts for 120s after a player joins), then calling Trusts.', math.ceil(left)))
                local t_end = os.clock() + left
                local next_report = os.clock() + TRUST_WAIT_REPORT
                while os.clock() < t_end do
                    if os.clock() >= next_report then
                        trust_countdown(t_end - os.clock(), 'then pulling')
                        next_report = next_report + TRUST_WAIT_REPORT
                    end
                    coroutine.sleep(1)
                    if g ~= P.gen then return end
                end
                say('TRUSTS: wait over -- calling Trusts.')
            end
            call_all_trusts(g)
            if g ~= P.gen then return end
            say('FIGHT: ' .. trust_count() .. ' Trust(s) in the party.')
        end
        if aa_set_anchor then aa_set_anchor() end   -- v4.75: the leader keeps this spot
        say('FIGHT: leader -- pulling.')
        P.fight_at = os.clock()
        start_mode('pull')
        return
    end
    local L = leader_name()
    local lm = member(L)
    if not L or not lm then reply(ctx, my_name() .. ': no party leader found -- not fighting.'); return end
    if lm.zone and lm.zone ~= zone_id() then
        reply(ctx, my_name() .. ': ' .. L .. ' is not in my zone -- not fighting.'); return
    end
    if not engaged() then
        local d = dist_to_name(L)
        if not d then reply(ctx, my_name() .. ": can't see " .. L .. ' -- not fighting.'); return end
        if d > opt('stack_precision') then
            say('FIGHT: stacking on ' .. L .. ' (' .. string.format('%.1f', d) .. 'y).')
            if not stack_on(L) then
                reply(ctx, my_name() .. ': could not get on top of ' .. L .. ' -- not fighting.')
                return
            end
        end
    else
        -- v4.75: already fighting -- stack anyway when close (11-18: Myth stayed
        -- off the stack for 30 min because aa fight came while he was engaged)
        local d = dist_to_name(L)
        if d and d > opt('party_range') + 0.5 and d <= opt('restack_max') then
            say('FIGHT: fighting, but ' .. string.format('%.1f', d) .. 'y from ' .. L .. ' -- stacking now.')
            stack_on(L, nil, nil, true)
        elseif d and d > opt('restack_max') then
            say('FIGHT: ' .. string.format('%.1f', d) .. 'y from ' .. L .. ' -- stacking after this fight.')
        end
    end
    P.follow, P.follow_fight = L, true
    say('FIGHT: assisting ' .. L .. "'s pulls (stacking on " .. L .. ' after each kill, no following).')
    P.fight_at = os.clock()
    start_mode('assist')
end

-- v5.31: aa stop stops EVERYTHING right away (Mark, 2026-11-23: "'aa stop'
-- should stop all aa loops and actions, such as nav, follow, fighting, etc."):
-- aa nav, follow / aa fight (following, stacking, re-stacking, fight spot), a
-- running sequence (invite, retrust, sneak, mount ... -- not an aa update),
-- a warp ring waiting to go off (your ring goes back), and the fight itself
-- (autoattack.lua: loop off, /attack off). Returns what was stopped.
local function stop_everything(why)
    local what = {}
    if aa_nav_stop then
        local ok, r = pcall(aa_nav_stop)
        if ok and r then what[#what + 1] = 'nav' end
    end
    if P.follow then what[#what + 1] = (P.follow_fight and 'aa fight' or ('following ' .. P.follow)) end
    if P.stack then what[#what + 1] = 'stacking' end
    P.follow, P.follow_fight, P.stack = nil, false, nil
    run_stop()
    if aa_clear_anchor then aa_clear_anchor(why) end   -- v4.75
    if P.busy and P.busy ~= 'update' and not P.updating then
        what[#what + 1] = P.busy
        P.gen = P.gen + 1; P.busy, P.step = nil, 'idle'
    end
    if P.warp_ring_on or P.warping then
        what[#what + 1] = 'warp'
        P.warp_gen = (P.warp_gen or 0) + 1
        P.warping = false
        if P.warp_ring_on and aa_warp_restore then pcall(aa_warp_restore, false) end
    end
    if aa_running and aa_running() then what[#what + 1] = 'fighting' end
    return what
end
AA_STOP_EVERYTHING = stop_everything

-- aa stop (tell / party): stop everything now (v5.31; before: finish the fight first)
local function do_stop(ctx)
    local what = stop_everything('aa stop')
    send('aa stop')   -- autoattack.lua: loop off, /attack off, moving off
    local txt = my_name() .. ': stopped' .. (#what > 0 and (' (' .. table.concat(what, ', ') .. ')') or ' (nothing was running)') .. '.'
    say(txt)
    if ctx.src ~= 'party' or #what > 0 then reply(ctx, txt) end
end

-- ---------------------------------------------------------------------------
-- aa invite
-- ---------------------------------------------------------------------------
local function run_invite(g, ctx, inv, sync, lead, fight)
    local requester = ctx.sender or my_name()
    local myz = zone_id()

    -- 1. same zone (requester, and the invitee when it's someone else)
    P.step = 'zone check'
    local checked = {}
    for _, who in ipairs({requester, inv}) do
        if who ~= my_name() and not checked[who] then
            checked[who] = true
            local w = where(g, who)
            if not alive(g) then return end
            if not w then return fail(g, ctx, 'No answer from ' .. who .. "'s AutoAttack -- invite cancelled.") end
            if w.zone ~= myz then return fail(g, ctx, who .. ' is not in my zone -- invite cancelled.') end
            if who == inv then checked.inv = w end
        end
    end
    local wi = checked.inv or where(g, inv)
    local already = member(inv) ~= nil

    -- 2. the invitee's own party
    if not already and wi then
        if wi.p == 2 then
            return fail(g, ctx, inv .. ' is in a party with other players -- they need "aa disband" or "aa leave" first.')
        elseif wi.p == 1 then
            P.step = 'asking ' .. inv .. ' to drop their Trusts'
            local a = ask(g, inv, 'd', requester)
            if not alive(g) then return end
            if not a then return fail(g, ctx, 'No answer from ' .. inv .. "'s AutoAttack -- invite cancelled.") end
            if not a:find('^ok') then
                return fail(g, ctx, inv .. " can't leave their party right now (" .. a .. ') -- invite cancelled.')
            end
        end
    end

    -- 3. finish the current fight (no new pulls)
    local was_running = aa_running()
    local was_mode = aa_get_mode()
    if not already and (was_running or party_fighting()) then
        P.step = 'finishing the current fight'
        if not finish_fights(g, opt('finish_timeout'), ctx, 'inviting ' .. inv) then
            if alive(g) and was_running and aa_running() then aa_set_mode(was_mode) end
            return fail(g, ctx, 'Still fighting after ' .. opt('finish_timeout') .. 's -- invite cancelled.')
        end
        if aa_running() then send('aa stop') end
        P.follow_fight = false
        if not sleep(g, 1.5) then return end
    end

    -- 4. drop Trusts
    local dropped_at = nil
    if not already and trust_count() > 0 then
        P.step = 'dropping Trusts'
        if not drop_trusts(g) then
            if not alive(g) then return end
            return fail(g, ctx, 'Trusts did not leave -- invite cancelled.')
        end
        dropped_at = os.clock()
        if not sleep(g, 1) then return end
    end

    -- 5. invite
    if not already then
        P.step = 'inviting ' .. inv
        send('input /pcmd add ' .. inv)
        local t0 = os.clock()
        while not member(inv) do
            if os.clock() - t0 > 30 then return fail(g, ctx, inv .. ' did not join within 30s.') end
            if not sleep(g, 1) then return end
        end
        P.last_join = os.clock()
        say(inv .. ' joined.')
        if not sleep(g, 2) then return end
    end

    -- 6. Level Sync
    if sync then
        P.step = 'Level Sync to ' .. sync
        if member(sync) then
            set_level_sync(ctx, sync, function(t) return sleep(g, t) end)   -- v5.26
            if not alive(g) then return end
            if not sleep(g, 2) then return end
        else
            reply(ctx, sync .. ' is not in the party -- no Level Sync.')
        end
    end

    -- 7. hand off the leader
    local resume = fight or was_running
    if lead and lead ~= my_name() then
        P.step = 'passing leader to ' .. lead
        send('input /pcmd leader ' .. lead)
        local t0 = os.clock()
        while leader_name() ~= lead do
            if os.clock() - t0 > 10 then break end
            if not sleep(g, 1) then return end
        end
        if leader_name() == lead then
            -- the new leader calls Trusts right away (no wait) and starts the fight
            local a = ask(g, lead, 'lead', 'f' .. (resume and 1 or 0))
            if not alive(g) then return end
            if not a then reply(ctx, 'No answer from ' .. lead .. "'s AutoAttack -- they need to call Trusts / fight themselves.") end
            return done(g, ctx, 'Done: ' .. inv .. ' in the party, leader is ' .. lead .. '.')
        end
        reply(ctx, 'Could not pass leader to ' .. lead .. ' -- I stay leader.')
    end

    -- 8. we are still the leader: wait for Trusts, call them, fight again
    if trusts_wanted() > 0 then
        if not wait_trust_time(g, latest(dropped_at, P.last_join)) then return end
        P.step = 'calling Trusts'
        call_all_trusts(g)
        if not alive(g) then return end
    end
    done(g, ctx, 'Done: ' .. inv .. ' is in the party.' .. (resume and ' Fighting again.' or ''))
    if resume then party_command('aa fight') end
end

local function cmd_invite(ctx, w)
    if not w[2] then return reply(ctx, 'Use: aa invite me|<name> [sync <name>] [leader <name>] [fight]') end
    local inv = resolve(w[2], ctx.sender)
    if not inv then return reply(ctx, '"' .. w[2] .. '" is not on my friend list.') end
    if inv == my_name() then return reply(ctx, "I can't invite myself.") end
    local sync, lead, fight = nil, nil, false
    local i = 3
    while w[i] do
        if w[i] == 'sync' or w[i] == 'leader' or w[i] == 'lead' then
            local who = resolve(w[i + 1], ctx.sender)
            if not who then return reply(ctx, '"' .. tostring(w[i + 1]) .. '" after ' .. w[i] .. ' is not on my friend list.') end
            if w[i] == 'sync' then sync = who else lead = who end
            i = i + 2
        elseif w[i] == 'fight' then
            fight = true; i = i + 1
        else
            return reply(ctx, 'Unknown word "' .. w[i] .. '". Use: aa invite me|<name> [sync <name>] [leader <name>] [fight]')
        end
    end
    if has_players() and not i_lead() then
        if ctx.src == 'party' then return end  -- in party chat only the leader acts
        return reply(ctx, 'Not party leader -- send this to ' .. tostring(leader_name()) .. '.')
    end
    local g = begin(ctx, 'invite ' .. inv)
    if g then run_invite(g, ctx, inv, sync, lead, fight) end
end

-- ---------------------------------------------------------------------------
-- the other commands
-- ---------------------------------------------------------------------------
local function status_line()
    local p = me()
    if not p then return my_name() .. ': no player data.' end
    local v = p.vitals or {}
    local job = tostring(p.main_job) .. tostring(p.main_job_level or '') .. '/' .. tostring(p.sub_job or '-')
    local mode = aa_running() and aa_get_mode():upper() or 'OFF'
    local s = string.format('%s %s: %s | HP %d%% MP %d%% TP %d | %s',
        p.name, job, mode, v.hpp or 0, v.mpp or 0, v.tp or 0, i_lead() and 'leader' or ('leader ' .. tostring(leader_name())))
    if P.busy then s = s .. ' | ' .. P.busy .. ': ' .. P.step end
    if P.follow then s = s .. ' | following ' .. P.follow end
    return s
end

local HELP = {
    'aa invite me|<name> [sync <name>] [leader <name>] [fight]',
    'aa fight | stop | stack (on leader) | follow [name] | unfollow | cancel | status | ping',
    'aa disband | leave | leader <name> | sync <name> | unsync | trusts [grp] | retr | retrust',
    'aa rest | mount [name] | dismount | pass | lot | pull [dir] | assist | ws on|off',
    'aa sneak | invis | sneak invis  (spell, else Spectral Jig, else Silent Oil / Prism Powder)',
    'aa warp | aa 299  (party: a Warp II mage warps everyone, else each uses its Warp Ring)',
    'aa nav <zone or place>  (v5.06: each AA warps there its own fastest way) | aa nav cancel',
    'aa buy <item> [qty] | aa buy list [text] | aa buy scan  (v5.45: Curio Vendor / Green Thumb Moogle)',
    "aa trade seals | crests (every seal + crest, stored with Shami) | rems (Rem's Tales to Monisette) | trade list | trade swap <from> <to> [n] | trade rate 2|3|auto  (v5.49)",
    'aa reload  (/t: that character, /p: everyone) | aa reload all  (whole party)',
    'aa update [me|force]  (whole party, any zone; "me" = only you -- newest AutoAttack from GitHub, then reload)',
    'aa update previous | aa update 4.88 | aa update list  (go back to an older version on GitHub; [me] = only you)',
    'aa version [me]  (whole party compares with GitHub)  |  aa rollback [all]  (back to the version before the last update)',
}

local function cmd_follow(ctx, w)
    local who = w[2] and resolve(w[2], ctx.sender) or nil
    if w[2] and not who then return reply(ctx, '"' .. w[2] .. '" is not on my friend list.') end
    if not who then
        if has_players() and not i_lead() then who = leader_name()
        elseif ctx.sender and ctx.sender ~= my_name() then who = ctx.sender end
    end
    if not who or who == my_name() then
        if ctx.src == 'party' and ctx.self then return end
        return reply(ctx, my_name() .. ': follow whom? (aa follow <name>)')
    end
    P.follow, P.follow_fight = who, false
    say('following ' .. who .. '.')
    if ctx.src ~= 'party' then reply(ctx, my_name() .. ' is following ' .. who .. '.') end
end

-- v4.48: always stacks on the party leader (a name after "stack" is ignored);
-- the leader itself stays put.
local function cmd_stack(ctx, w)
    if not has_players() then
        if ctx.src ~= 'party' then reply(ctx, my_name() .. ' is not in a party -- no leader to stack on.') end
        return
    end
    local who = leader_name()
    if not who then return reply(ctx, my_name() .. ': no party leader found -- not stacking.') end
    if who == my_name() then return end   -- the leader is the spot
    local lm = member(who)
    if lm and lm.zone and lm.zone ~= zone_id() then
        return reply(ctx, my_name() .. ': ' .. who .. ' is not in my zone -- not stacking.')
    end
    -- v4.78: stacks while fighting too (asked for; the mob follows you)
    local fighting = engaged()
    local d = dist_to_name(who)
    if not d then return reply(ctx, my_name() .. ": can't see " .. who .. '.') end
    if fighting then say(string.format('fighting, %.1fy from %s -- stacking anyway.', d, who)) end
    if stack_on(who, nil, nil, fighting) then
        local d2 = dist_to_name(who)
        say(string.format('stacked on %s (%.2fy).', who, d2 or 0))
    else
        reply(ctx, my_name() .. ': could not get on top of ' .. who .. '.')
    end
end

-- v4.57: drop our own Trusts FIRST, then /pcmd breakup (or leave), then
-- check the party really emptied and try again if it didn't. Sent with
-- Trusts still out, /pcmd breakup only released the Trusts and the players
-- stayed in the party (Scracheebrat, 2026-11-17).
local function wait_until(cond, secs)
    local t0 = os.clock()
    while not cond() and os.clock() - t0 < secs do coroutine.sleep(0.5) end
    return cond()
end

-- v4.58: true while the game still shows us in a party (we are flagged as
-- leader / a party leader id is set) but nobody else is in it.
local function solo_party()
    if has_players() or trust_count() > 0 then return false end
    local party = windower.ffxi.get_party()
    if not party then return false end
    if party.p0 and party.p0.is_leader == true then return true end
    local lid = party.party1_leader
    return lid ~= nil and lid ~= 0
end

local function cmd_disband(ctx, leave_only)
    local what = leave_only and 'leave' or 'disband'
    if engaged() or party_fighting() then
        return reply(ctx, my_name() .. " is fighting -- can't " .. what .. ' right now.')
    end
    P.follow_fight = false
    if aa_running() then send('aa stop') end

    local dropped = false
    if i_lead() and trust_count() > 0 then
        dbg('DISBAND: releasing ' .. trust_count() .. ' Trust(s) before the ' .. what .. '.')
        send('input ' .. opt('retr_command'))
        dropped = true
        coroutine.sleep(1)
        if not wait_until(function() return trust_count() == 0 end, 5) then
            dbg('DISBAND: ' .. trust_count() .. ' Trust(s) still listed -- going ahead anyway.')
        end
        coroutine.sleep(1)
    end

    if not has_players() then
        -- v4.58: no players and no Trusts can still leave a "party of 1" with
        -- us as leader, which blocks invites. Break it up / leave it.
        if solo_party() then
            dbg('DISBAND: party of 1 still up -- clearing it.')
            for attempt = 1, 3 do
                local cmd = (attempt % 2 == 1) and 'input /pcmd breakup' or 'input /pcmd leave'
                dbg('DISBAND: party-of-1 attempt ' .. attempt .. ' -- ' .. cmd:sub(7) .. '.')
                send(cmd)
                if wait_until(function() return not solo_party() end, 3) then break end
            end
            if solo_party() then
                return reply(ctx, my_name() .. ' could not clear their party of 1 -- try /pcmd leave by hand.')
            end
            return reply(ctx, my_name() .. (dropped and ' dropped their Trusts and' or '')
                         .. ' disbanded their party of 1 -- ready for an invite.')
        end
        if dropped then
            return reply(ctx, my_name() .. ' dropped their Trusts -- ready for an invite.')
        end
        return reply(ctx, my_name() .. ' is not in a party -- ready for an invite.')
    end

    local breakup = false
    for attempt = 1, 3 do
        breakup = (not leave_only) and i_lead()
        dbg('DISBAND: attempt ' .. attempt .. ' -- ' .. (breakup and '/pcmd breakup' or '/pcmd leave') .. '.')
        send(breakup and 'input /pcmd breakup' or 'input /pcmd leave')
        if wait_until(function() return not has_players() end, 4) then break end
    end

    if has_players() then
        reply(ctx, my_name() .. ' could not ' .. what .. ' -- still in a party (leader: '
              .. tostring(leader_name()) .. ').')
    elseif breakup then
        reply(ctx, my_name() .. ' disbanded the party.')
    else
        reply(ctx, my_name() .. ' left the party.')
    end
end

local function need_lead(ctx)
    if i_lead() then return true end
    if ctx.src ~= 'party' then reply(ctx, my_name() .. ' is not party leader (' .. tostring(leader_name()) .. ' is).') end
    return false
end

local function cmd_rest(ctx)
    if engaged() or party_fighting() then return reply(ctx, my_name() .. " is fighting -- can't rest.") end
    P.follow, P.follow_fight = nil, false
    run_stop()
    if aa_running() then send('aa stop') end
    coroutine.sleep(1)
    send('input /heal on')
    say('resting until HP/MP are full.')
    local t0 = os.clock()
    coroutine.sleep(4)
    while os.clock() - t0 < 900 do
        local p = me()
        if not p or p.status ~= 33 then
            say('rest ended (no longer resting).')
            return
        end
        local v = p.vitals or {}
        if (v.hpp or 0) >= 100 and ((v.max_mp or 0) == 0 or (v.mpp or 0) >= 100) then
            send('input /heal off')
            say('HP/MP full -- stood up.')
            if ctx.src ~= 'party' then reply(ctx, my_name() .. ' is rested.') end
            return
        end
        coroutine.sleep(2)
    end
end

local function cmd_pool(ctx, lot)
    local items = windower.ffxi.get_items()
    local pool = items and items.treasure
    local n = 0
    if type(pool) == 'table' then
        for slot, it in pairs(pool) do
            if type(it) == 'table' and (it.item_id or 0) > 0 then
                if lot then windower.ffxi.lot_item(slot) else windower.ffxi.pass_item(slot) end
                n = n + 1
                coroutine.sleep(0.5)
            end
        end
    end
    say((lot and 'lotted on ' or 'passed ') .. n .. ' item(s) in the treasure pool.')
end

local function cmd_trusts(ctx, w)
    if has_players() and not need_lead(ctx) then return end
    local cfg = aa_get_config and aa_get_config()
    if not (cfg and cfg.trusts) then return reply(ctx, my_name() .. ': no trusts set up for this job.') end
    if w[2] then
        if type(cfg.trusts[w[2]]) ~= 'table' then
            return reply(ctx, my_name() .. ': no trust group "' .. w[2] .. '" for this job.')
        end
        cfg.trusts.trust_group = w[2]
        say('trust group set to ' .. w[2] .. ' (this session).')
    end
    if engaged() then return reply(ctx, my_name() .. " is fighting -- can't call Trusts now.") end
    local g = begin(ctx, 'calling Trusts')
    if not g then return end
    P.step = 'calling Trusts'
    call_all_trusts(g)
    done(g, ctx, nil)
    say(trust_count() .. ' Trust(s) in the party.')
end

-- aa retrust: finish the fight (no new pulls), drop the Trusts, wait
-- trust_wait, call them again, then go back to the mode it was in.
local function cmd_retrust(ctx)
    if has_players() and not need_lead(ctx) then return end
    if trusts_wanted() == 0 then return reply(ctx, my_name() .. ': no Trusts set up for this job.') end
    local g = begin(ctx, 'retrust')
    if not g then return end
    local was_running, was_mode = aa_running(), aa_get_mode()
    if was_running or party_fighting() then
        P.step = 'finishing the current fight'
        say('RETRUST: finishing the current fight first (no new pulls).')
        if not finish_fights(g, opt('finish_timeout'), ctx, 'redoing the Trusts') then
            if alive(g) and was_running and aa_running() then aa_set_mode(was_mode) end
            return fail(g, ctx, 'Still fighting after ' .. opt('finish_timeout') .. 's -- retrust cancelled.')
        end
        if aa_running() then send('aa stop') end
        if not sleep(g, 1.5) then return end
    end
    local dropped_at = nil
    if trust_count() > 0 then
        P.step = 'dropping Trusts'
        if not drop_trusts(g) then
            if not alive(g) then return end
            return fail(g, ctx, 'Trusts did not leave -- retrust cancelled.')
        end
        dropped_at = os.clock()
    end
    if not wait_trust_time(g, latest(dropped_at, P.last_join)) then return end
    P.step = 'calling Trusts'
    call_all_trusts(g)
    if not alive(g) then return end
    done(g, ctx, nil)
    say('RETRUST: ' .. trust_count() .. ' Trust(s) in the party' .. (was_running and (' -- back to ' .. was_mode:upper() .. '.') or '.'))
    if ctx.src ~= 'party' then reply(ctx, my_name() .. ': retrust done, ' .. trust_count() .. ' Trust(s).') end
    if was_running then start_mode(was_mode) end
end

-- ---------------------------------------------------------------------------
-- v4.51: aa sneak | aa invis | aa sneak invis
--   Each character that doesn't already have the buff puts it up -- its own
--   spell first (main or sub job), else Spectral Jig (DNC main/sub, gives
--   both), else the item (Silent Oil = Sneak, Prism Powder = Invisible) --
--   then says in the same channel (/p or /t) that it has it and for how long.
-- ---------------------------------------------------------------------------
local BUFF = {sneak = {id = 71, name = 'Sneak', spell = 'Sneak', item = 'Silent Oil'},
              invis = {id = 69, name = 'Invisible', spell = 'Invisible', item = 'Prism Powder'}}
local BUFF_PERIOD = 0x100000000 / 60   -- the buff clock wraps every ~2.27 years
P.buff_end = {}                        -- [buff id] = os.time() it wears off (from 0x063)

windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x063 or not data or #data < 0xC8 or data:byte(5) ~= 9 then return end
    local now, ends = os.time(), {}
    for i = 1, 32 do
        local b = data:byte(i * 2 + 7) + data:byte(i * 2 + 8) * 256
        if b == 69 or b == 71 then
            local o = i * 4 + 0x45
            local raw = data:byte(o) + data:byte(o + 1) * 256 + data:byte(o + 2) * 65536 + data:byte(o + 3) * 16777216
            local base = 1009810800 + raw / 60
            local k = math.ceil((now - base) / BUFF_PERIOD)
            ends[b] = base + k * BUFF_PERIOD
        end
    end
    P.buff_end = ends
end)

local function has_buff(bid)
    local p = me()
    for _, b in ipairs(p and p.buffs or {}) do if b == bid then return true end end
    return false
end
local function buff_left(bid)
    local e = P.buff_end[bid]
    if not e then return nil end
    local left = e - os.time()
    return left > 0 and left or nil
end
local function fmt_left(sec)
    if not sec then return '?' end
    sec = math.floor(sec)
    return string.format('%d:%02d', math.floor(sec / 60), sec % 60)
end

local function spell_ready(name)
    local sp = res.spells:with('en', name)
    local p = me()
    if not sp or not p then return false end
    local known = windower.ffxi.get_spells()
    if not known or not known[sp.id] then return false end
    local lv = sp.levels or {}
    local ok = (p.main_job_id and lv[p.main_job_id] and lv[p.main_job_id] <= (p.main_job_level or 0))
            or (p.sub_job_id and lv[p.sub_job_id] and lv[p.sub_job_id] <= (p.sub_job_level or 0))
    if not ok then return false end
    if (p.vitals and p.vitals.mp or 0) < (sp.mp_cost or 0) then return false end
    local rc = windower.ffxi.get_spell_recasts()
    return not (rc and (rc[sp.recast_id or sp.id] or 0) > 0)
end
local function jig_ready()
    local p = me()
    if not p then return false end
    local dnc = (p.main_job == 'DNC' and (p.main_job_level or 0) >= 25)
             or (p.sub_job == 'DNC' and (p.sub_job_level or 0) >= 25)
    if not dnc then return false end
    local ja = res.job_abilities:with('en', 'Spectral Jig')
    local rc = windower.ffxi.get_ability_recasts()
    return ja ~= nil and not (rc and (rc[ja.recast_id] or 0) > 0)
end
local function have_item(name)
    local it = aa_item_named(name)   -- v4.61
    local inv = it and windower.ffxi.get_items(0)
    if not inv then return false end
    for _, e in ipairs(inv) do
        if type(e) == 'table' and e.id == it.id and (e.count or 0) > 0 then return true end
    end
    return false
end

-- wait (max s) for the buff to show; true when it's on
local function wait_buff(bid, s)
    local t0 = os.clock()
    while os.clock() - t0 < s do
        if has_buff(bid) then return true end
        coroutine.sleep(0.25)
    end
    return has_buff(bid)
end

local function cmd_sneak(ctx, w)
    local want = {}
    for _, word in ipairs(w) do
        if word == 'sneak' then want[#want + 1] = 'sneak'
        elseif word == 'invis' or word == 'invisible' then want[#want + 1] = 'invis' end
    end
    -- always Sneak before Invisible (an action after Invisible would drop it)
    table.sort(want, function(a, b) return a == 'sneak' and b ~= 'sneak' end)
    if P.sneaking then return end
    local p = me()
    if not p then return end
    if p.status ~= 0 then
        return reply(ctx, my_name() .. ' is ' .. (p.status == 1 and 'fighting' or 'busy (mounted / resting?)') .. ' -- no ' ..
            table.concat((function() local t = {} for _, k in ipairs(want) do t[#t + 1] = BUFF[k].name end return t end)(), ' / ') .. '.')
    end
    P.sneaking = true
    local missing, why = {}, {}
    for _, k in ipairs(want) do if not has_buff(BUFF[k].id) then missing[#missing + 1] = k end end
    local jigged = false
    for _, k in ipairs(missing) do
        local b = BUFF[k]
        if not has_buff(b.id) then
            local how
            if spell_ready(b.spell) then
                how = 'spell'; send('input /ma "' .. b.spell .. '" <me>')
            elseif not jigged and jig_ready() then
                how = 'jig'; jigged = true; send('input /ja "Spectral Jig" <me>')
            elseif have_item(b.item) then
                how = 'item'; send('input /item "' .. b.item .. '" <me>')
            end
            if not how then
                why[k] = 'no ' .. b.spell .. ' spell, Spectral Jig or ' .. b.item
            elseif not wait_buff(b.id, how == 'spell' and 10 or 6) then
                why[k] = how == 'spell' and (b.spell .. ' did not land')
                      or how == 'jig' and 'Spectral Jig did not land'
                      or (b.item .. ' did not land')
            else
                dbg(b.name .. ' up (' .. how .. ').')
            end
            coroutine.sleep(how == 'spell' and 2.5 or 1.5)   -- let the next action through
        end
    end
    coroutine.sleep(1)   -- the buff packet (0x063) follows the buff
    local parts = {}
    for _, k in ipairs(want) do
        local b = BUFF[k]
        if has_buff(b.id) then
            parts[#parts + 1] = b.name .. ' ' .. fmt_left(buff_left(b.id))
        else
            parts[#parts + 1] = 'NO ' .. b.name .. (why[k] and (' (' .. why[k] .. ')') or '')
        end
    end
    P.sneaking = false
    reply(ctx, my_name() .. ': ' .. table.concat(parts, ', '))
end

-- ---------------------------------------------------------------------------
-- v4.52: aa warp | aa 299
--   Party (/p): every character stops AA and following. Characters that can
--   cast Warp II say "[AA] <name>: I can Warp II." in /p; after
--   warp_claim_wait the first of them (by name) Warp IIs every other player
--   in the zone, then warps itself (Warp, or Warp II on itself). The others
--   wait for it (warp_wait), then fall back to the ring. With no Warp II mage,
--   each character equips its Warp Ring on the RIGHT ring (ring2), waits
--   warp_ring_delay and uses it; the ring that was there goes back on after
--   the warp (v4.53). By /tell or typed: just this character (Warp spell, else ring).
-- ---------------------------------------------------------------------------
P.warp_gen, P.warp_mages = 0, {}
local WARP_BAGS = {0, 8, 10, 11, 12, 13, 14, 15, 16}   -- inventory + wardrobes

local function spell_usable(name)     -- known, level, MP (recast not checked)
    local sp = res.spells:with('en', name)
    local p = me()
    if not sp or not p then return false end
    local known = windower.ffxi.get_spells()
    if not known or not known[sp.id] then return false end
    local lv = sp.levels or {}
    return ((p.main_job_id and lv[p.main_job_id] and lv[p.main_job_id] <= (p.main_job_level or 0))
         or (p.sub_job_id and lv[p.sub_job_id] and lv[p.sub_job_id] <= (p.sub_job_level or 0))) and true or false
end
local function wait_spell(name, wg, max_s)
    local t0 = os.clock()
    while os.clock() - t0 < max_s do
        if P.warp_gen ~= wg then return false end
        if spell_ready(name) then return true end
        coroutine.sleep(1)
    end
    return spell_ready(name)
end
local function have_item_any(name)
    local it = aa_item_named(name)   -- v4.61
    if not it then return false end
    for _, bag in ipairs(WARP_BAGS) do
        local items = windower.ffxi.get_items(bag)
        if type(items) == 'table' then
            for _, e in ipairs(items) do
                if type(e) == 'table' and e.id == it.id then return true end
            end
        end
    end
    return false
end
local function wait_zoned(zone0, wg, max_s)
    local t0 = os.clock()
    while os.clock() - t0 < max_s do
        if P.warp_gen ~= wg or zone_id() ~= zone0 then return true end
        coroutine.sleep(0.5)
    end
    return zone_id() ~= zone0
end

-- v4.53: the item in the right ring slot now (nil = empty / unknown)
local function right_ring_name()
    local eq = windower.ffxi.get_items('equipment')   -- v4.61: equipment only
    if not eq or not eq.right_ring or eq.right_ring == 0 then return nil end
    local it = windower.ffxi.get_items(eq.right_ring_bag or 0, eq.right_ring)
    local r = it and it.id and it.id > 0 and aa_item(it.id)   -- v4.61
    return r and r.en or nil
end

-- v4.53: after the warp (zoned) or a failed ring: old ring back on, unlock ring2
function aa_warp_restore(wait_load)
    if not P.warp_ring_on then return end
    P.warp_ring_on = false
    local old = P.warp_old_ring
    P.warp_old_ring = nil
    coroutine.schedule(function()
        if wait_load then
            -- wait for the new zone to finish loading
            local t0 = os.clock()
            while os.clock() - t0 < 30 do
                local p, eq = me(), windower.ffxi.get_items('equipment')   -- v4.61
                if p and p.name and eq then break end
                coroutine.sleep(1)
            end
            coroutine.sleep(3)
        end
        if old and old ~= opt('warp_ring') then
            send('input /equip ring2 "' .. old .. '"')
            say('WARP: ' .. old .. ' back on the right ring.')
            coroutine.sleep(1)
        end
        send('gs enable ring2')
    end, wait_load and 2 or 0)
end

local function warp_ring(ctx, wg, zone0)
    local ring = opt('warp_ring')
    if not have_item_any(ring) then
        return reply(ctx, my_name() .. ': no ' .. ring .. ' -- not warping.')
    end
    P.warp_old_ring = right_ring_name()
    send('input /equip ring2 "' .. ring .. '"')
    send('gs disable ring2')
    P.warp_ring_on = true
    say(string.format('WARP: %s on the right ring (was %s) -- using it in %ds.', ring, tostring(P.warp_old_ring or 'empty'), opt('warp_ring_delay')))
    local t_end = os.clock() + opt('warp_ring_delay')
    while os.clock() < t_end do
        coroutine.sleep(0.5)
        if P.warp_gen ~= wg then return end
    end
    send('input /item "' .. ring .. '" <me>')
    if not wait_zoned(zone0, wg, 20) then
        aa_warp_restore(false)
        reply(ctx, my_name() .. ': ' .. ring .. ' did not go off (still on its reuse timer?).')
    end
end

-- v5.06: aa nav uses a warp ring (Warp Ring, Dim. Rings, Tavnazian Ring) the
-- aa warp way: on the RIGHT ring (ring2), gs disable ring2, warp_ring_delay,
-- /item; the old ring goes back after the zone (aa_warp_restore). note(text)
-- is told when the ring does not go off. Returns false, why when it can't start.
function aa_nav_ring(ring, note)
    if P.warp_ring_on or P.warping then return false, 'a warp ring is already being used.' end
    if not have_item_any(ring) then return false, 'no ' .. ring .. '.' end
    P.warp_gen = P.warp_gen + 1
    local wg, zone0 = P.warp_gen, zone_id()
    P.warp_old_ring = right_ring_name()
    send('input /equip ring2 "' .. ring .. '"')
    send('gs disable ring2')
    P.warp_ring_on = true
    say(string.format('NAV: %s on the right ring (was %s) -- using it in %ds.', ring, tostring(P.warp_old_ring or 'empty'), opt('warp_ring_delay')))
    coroutine.schedule(function()
        local t_end = os.clock() + opt('warp_ring_delay')
        while os.clock() < t_end do
            coroutine.sleep(0.5)
            if P.warp_gen ~= wg then return end
        end
        send('input /item "' .. ring .. '" <me>')
        if not wait_zoned(zone0, wg, 20) then
            aa_warp_restore(false)
            if note then note(ring .. ' did not go off (still on its reuse timer?).') end
        end
    end, 0)
    return true
end

local function warp_self_spell(wg, zone0)
    for _, sp in ipairs({'Warp', 'Warp II'}) do
        if spell_usable(sp) and wait_spell(sp, wg, 60) then
            send('input /ma "' .. sp .. '" <me>')
            if wait_zoned(zone0, wg, 15) then return true end
        end
    end
    return false
end

local function warp_party(ctx, wg, zone0)
    for _, m in ipairs(members()) do
        if P.warp_gen ~= wg then return end
        if not m.trust and m.name ~= my_name() and m.zone == zone0 then
            local d = dist_to_name(m.name)
            if not d or d > 20 then
                reply(ctx, my_name() .. ': ' .. m.name .. ' is out of Warp II range -- use your ring.')
            else
                local done = false
                for _ = 1, 2 do
                    if not wait_spell('Warp II', wg, 90) then break end
                    send('input /ma "Warp II" ' .. m.name)
                    local t0 = os.clock()
                    while os.clock() - t0 < 15 do
                        coroutine.sleep(0.5)
                        if P.warp_gen ~= wg then return end
                        local mm = member(m.name)
                        if not mm or mm.zone ~= zone0 then done = true; break end
                    end
                    if done then break end
                end
                say('WARP: ' .. m.name .. (done and ' warped.' or ' was NOT warped.'))
            end
        end
    end
    if P.warp_gen ~= wg then return end
    if not warp_self_spell(wg, zone0) and P.warp_gen == wg then
        say('WARP: could not warp myself by spell -- using the ring.')
        warp_ring(ctx, wg, zone0)
    end
end

local function cmd_warp(ctx)
    if P.warping then return end
    local p = me()
    if not p then return end
    if p.status ~= 0 and p.status ~= 85 and p.status ~= 5 then
        return reply(ctx, my_name() .. ' is ' .. (p.status == 1 and 'fighting' or 'busy') .. ' -- not warping.')
    end
    P.warping = true
    P.warp_mages = {}
    P.warp_gen = P.warp_gen + 1
    AA_NAV_EXPECT_HOME = os.clock()   -- v5.06: aa nav learns where Warp takes you
    local wg, zone0 = P.warp_gen, zone_id()
    P.follow, P.follow_fight, P.stack = nil, false, nil
    run_stop()
    if aa_running() then send('aa stop') end
    if p.status == 85 or p.status == 5 then send('input /dismount'); coroutine.sleep(1.5) end
    if ctx.src ~= 'party' or not has_players() then
        -- just me: my own Warp spell, else my ring
        if not ((spell_usable('Warp') or spell_usable('Warp II')) and warp_self_spell(wg, zone0)) and P.warp_gen == wg then
            warp_ring(ctx, wg, zone0)
        end
        if P.warp_gen == wg then P.warping = false end
        return
    end
    if spell_usable('Warp II') then
        P.warp_mages[my_name()] = true
        party_say('[AA] ' .. my_name() .. ': I can Warp II.')   -- v4.68
    end
    coroutine.sleep(opt('warp_claim_wait'))
    if P.warp_gen ~= wg then return end
    local names = {}
    for n in pairs(P.warp_mages) do
        if n == my_name() or member(n) then names[#names + 1] = n end
    end
    table.sort(names)
    local warper = names[1]
    if warper == my_name() then
        say('WARP: I have Warp II -- warping the party, then myself.')
        warp_party(ctx, wg, zone0)
    elseif warper then
        say('WARP: waiting for ' .. warper .. "'s Warp II.")
        if not wait_zoned(zone0, wg, opt('warp_wait')) and P.warp_gen == wg then
            say('WARP: no Warp II from ' .. warper .. ' -- using the ring.')
            warp_ring(ctx, wg, zone0)
        end
    else
        warp_ring(ctx, wg, zone0)
    end
    if P.warp_gen == wg then P.warping = false end
end

-- ---------------------------------------------------------------------------
-- AA-to-AA messages ("aa~<verb> <n> ...")
-- ---------------------------------------------------------------------------
local function handle_proto(sender, text)
    local verb, n, rest = text:match('^[Aa][Aa]~(%a+)%s+(%d+)%s*(.*)$')
    if not verb then return end
    verb = verb:lower()
    if verb == 'r' then
        P.replies[n] = rest
        return
    end
    coroutine.schedule(function()
        if verb == 'q' then
            local pstate = has_players() and 2 or (trust_count() > 0 and 1 or 0)
            tell(sender, string.format('aa~r %s z%d p%d e%d l%d', n, zone_id(), pstate,
                (engaged() or party_fighting()) and 1 or 0, i_lead() and 1 or 0))
        elseif verb == 'd' then
            -- getting ready for an invite: drop the Trust-only party, unless fighting
            local requester = (rest ~= '' and rest) or sender
            if engaged() or party_fighting() then
                if requester ~= sender then
                    tell(requester, '[AA] ' .. my_name() .. " is fighting -- can't join right now.")
                end
                tell(sender, 'aa~r ' .. n .. ' no fighting')
                return
            end
            if has_players() then tell(sender, 'aa~r ' .. n .. ' no players'); return end
            P.follow_fight = false
            if aa_running() then send('aa stop'); coroutine.sleep(1) end
            local g = P.gen
            drop_trusts(g)
            tell(sender, 'aa~r ' .. n .. ((trust_count() == 0) and ' ok' or ' no trusts'))
        elseif verb == 'lead' then
            -- we were just made leader by an invite: Trusts now (no wait), then fight
            tell(sender, 'aa~r ' .. n .. ' ok')
            local fight = rest:lower():find('f1') ~= nil
            local t0 = os.clock()
            while not i_lead() and os.clock() - t0 < 10 do coroutine.sleep(1) end
            if not i_lead() then say('asked to lead, but I am not the leader.'); return end
            P.last_join = nil  -- v4.46: a new leader isn't held by the join window
            say('I am the new leader' .. (fight and ' -- calling Trusts, then fighting.' or ' -- calling Trusts.'))
            if not aa_running() and not P.busy then
                P.gen = P.gen + 1
                local g = P.gen
                P.busy, P.step = 'new leader', 'calling Trusts'
                call_all_trusts(g)
                if alive(g) then P.busy, P.step = nil, 'idle' end
            end
            if fight then party_command('aa fight') end
        end
    end, 0)
end

-- ---------------------------------------------------------------------------
-- commands ("aa <command> ...")
-- ---------------------------------------------------------------------------
local PASS_THROUGH = {pull = true, assist = true, ws = true, move = true, ds = true, gsc = true}  -- v4.70: gsc

-- v4.69: pass-through commands answer the sender. ws / move / ds run here
-- right away (aa_addon_command in autoattack.lua) and the [AutoAttack] lines
-- they print go back to the sender; pull / assist say which mode we're in.
-- A /p line from this character isn't answered here (its own log shows it).
local function pass_through(ctx, c, w)
    local quiet = ctx.src == 'party' and ctx.self
    local args = {}
    for i = 2, #w do args[#args + 1] = w[i] end
    local function answer(lines)
        if quiet then return end
        local max, n = 5, 0
        for _, l in ipairs(lines) do
            n = n + 1
            if n > max then
                reply(ctx, my_name() .. ': (+' .. (#lines - max) .. ' more lines -- see my chat log)')
                break
            end
            if n > 1 and ctx.src == 'tell' then coroutine.sleep(1) end   -- party lines are spaced by party_say
            if #l > 110 then l = l:sub(1, 107) .. '...' end
            reply(ctx, my_name() .. ': ' .. l)
        end
    end
    if c == 'pull' or c == 'assist' then
        leave_fight_mode('aa ' .. c .. ' from ' .. tostring(ctx.sender))   -- v4.75
        local MODE = c:upper()
        if aa_running() then
            local was = tostring(aa_get_mode and aa_get_mode() or '?'):upper()
            aa_set_mode(c)
            say('switched to ' .. MODE .. ' mode (from ' .. tostring(ctx.sender) .. ').')
            return answer({(was == MODE) and ('already in ' .. MODE .. ' mode.')
                                          or ('switched to ' .. MODE .. ' mode (was ' .. was .. ').')})
        end
        send('aa ' .. table.concat(w, ' '))
        coroutine.sleep(1.5)
        if aa_running() then
            return answer({'started ' .. tostring(aa_get_mode and aa_get_mode() or c):upper() .. ' mode' ..
                ((#args > 0) and (' (' .. table.concat(args, ' ') .. ')') or '') .. '.'})
        end
        return answer({"couldn't start " .. MODE .. ' mode -- see my chat log.'})
    end
    if type(aa_addon_command) ~= 'function' then   -- older autoattack.lua
        send('aa ' .. table.concat(w, ' '))
        return answer({'ran "aa ' .. table.concat(w, ' ') .. '".'})
    end
    -- ws / move / ds: run it now and catch what it prints
    local got, real = {}, windower.add_to_chat
    windower.add_to_chat = function(mode, text, ...)
        got[#got + 1] = tostring(text)
        return real(mode, text, ...)
    end
    local ok, err = pcall(aa_addon_command, c, unpack(args))
    windower.add_to_chat = real
    local lines = {}
    for _, t in ipairs(got) do
        if not (t:find('^%[DEBUG') or t:find('^%[CMD%]')) then
            t = t:gsub('^%[AutoAttack%]%s*', ''):gsub('^%[AA%]%s*', ''):gsub('//aa ', 'aa '):gsub('^%s+', '')
            if t ~= '' then lines[#lines + 1] = t end
        end
    end
    if not ok then
        dbg('pass-through "' .. c .. '" error: ' .. tostring(err))
        lines = {'"aa ' .. table.concat(w, ' ') .. '" failed -- see my chat log.'}
        windower.add_to_chat(167, '[AA] "aa ' .. table.concat(w, ' ') .. '" failed: ' .. tostring(err))
    elseif #lines == 0 then
        lines = {'done: aa ' .. table.concat(w, ' ') .. '.'}
    end
    answer(lines)
end

-- ---------------------------------------------------------------------------
-- v4.60: aa reload [all] -- reloads AutoAttack (//lua r autoattack).
--   /tell aa reload   -> that character      /p aa reload -> every AA in the party
--   aa reload all     -> says "/p aa reload" (whole party, this one too)
-- A reload wipes the Lua state, so who asked (and how) is saved to
-- data/reload_notify.txt first; the reloaded AA reads it and answers with
-- its version in the same channel. AutoAttack is stopped by the reload.
-- ---------------------------------------------------------------------------
local RELOAD_FILE = windower.addon_path .. 'data/reload_notify.txt'
local function addon_folder()
    return windower.addon_path:match('([^/\\]+)[/\\]*$') or 'autoattack'
end
-- Save who asked (and the version before an update) for the reloaded AA,
-- stop everything, then //lua r autoattack.
-- v4.82: what was running, so the reloaded AA carries on (aa update mid-fight)
local RESUME_FILE = windower.addon_path .. 'data/resume_state.txt'
local function save_resume()
    os.remove(RESUME_FILE)
    if not (aa_running and aa_running()) then return end
    local f = io.open(RESUME_FILE, 'w')
    if not f then return end
    local A = AA_ANCHOR
    f:write(table.concat({
        tostring(os.time()), tostring(aa_get_mode and aa_get_mode() or ''), tostring(zone_id()),
        (P.follow_fight and P.follow) or '',
        A and string.format('%.3f', A.x) or '', A and string.format('%.3f', A.y) or '',
    }, '\t'), '\n')
    f:close()
end
-- after the reload: same zone, within 2 minutes -> fight spot, aa fight
-- following and the mode (pull / assist) come back
RESUME_MAX_AGE = 120
local function resume_after_reload()
    local f = io.open(RESUME_FILE, 'r')
    if not f then return end
    local line = f:read('*l') or ''
    f:close()
    os.remove(RESUME_FILE)
    local t, mode, z, lead, ax, ay = line:match('^(%d+)\t(%a*)\t(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)')
    t, z = tonumber(t), tonumber(z)
    if not t or os.time() - t > RESUME_MAX_AGE or (mode ~= 'pull' and mode ~= 'assist') then return end
    if z ~= zone_id() then say('RESUME: zoned since the reload -- not resuming.'); return end
    if tonumber(ax) and tonumber(ay) then AA_ANCHOR = {x = tonumber(ax), y = tonumber(ay), zone = z} end
    if lead ~= '' then P.follow, P.follow_fight = lead, true end
    P.fight_at = os.clock()   -- the "aa <mode>" below keeps fight mode (leave_fight_mode)
    say('RESUME: carrying on in ' .. mode:upper() .. ' mode after the reload' ..
        (AA_ANCHOR and ', fight spot kept' or '') .. (lead ~= '' and (', fight-following ' .. lead) or '') .. '.')
    send('aa ' .. mode)
end

local function reload_now(ctx, from_ver)
    save_resume()   -- v4.82
    local f = io.open(RELOAD_FILE, 'w')
    if f then
        f:write(ctx.src, '\t', ctx.sender or '', '\t', tostring(os.time()), '\t', from_ver or '', '\n')
        f:close()
    end
    P.gen = P.gen + 1
    P.busy, P.step, P.stack = nil, 'idle', nil
    P.follow, P.follow_fight = nil, false
    run_stop()
    coroutine.schedule(function() windower.send_command('lua r ' .. addon_folder()) end, 1.5)
end
local function cmd_reload(ctx, w)
    -- in party chat everyone already reloads: "all" there means the same thing
    if w[2] == 'all' and ctx.src ~= 'party' and has_players() then
        if ctx.src == 'tell' then reply(ctx, my_name() .. ': reloading the whole party.') end
        return party_command('aa reload')
    end
    if ctx.src ~= 'party' then reply(ctx, my_name() .. ': reloading AutoAttack v' .. tostring(_addon.version) .. '...') end
    say('reloading AutoAttack (from ' .. tostring(ctx.sender) .. ').')
    reload_now(ctx)
end

-- ---------------------------------------------------------------------------
-- v4.62: aa update [all|force] -- download the newest release from GitHub,
-- tell the sender it's downloaded, reload, then tell the sender the new
-- version (from the reloaded AA).
--   /tell aa update -> that character   /p aa update -> every AA in the party
--   aa update all   -> says "/p aa update" (whole party, this one too)
--   aa update force -> also re-installs the same version / allows a downgrade
-- The download address is fixed here (or party.update_url in aa_config.lua)
-- -- never taken from the chat message. Only the files below can be
-- replaced; aa_config.lua, data/ and logs are never touched. Every file is
-- checked (size from manifest.txt, .lua files must load, autoattack.lua must
-- carry the manifest's version) before anything is written; the old files go
-- to backups/ first and are put back if a write fails. Refused while fighting.
-- ---------------------------------------------------------------------------
local UPDATE_URL   = 'https://raw.githubusercontent.com/thrydwolfvalefor/autoattack/main/'
local UPDATE_FILES = {['autoattack.lua'] = true, ['aa_party.lua'] = true,
                      ['aa_config_defaults.lua'] = true, ['README.md'] = true,
                      ['aa_knowledge.lua'] = true,   -- v4.90
                      ['nav.lua'] = true, ['nav_maps.lua'] = true, ['nav_zones.lua'] = true,   -- v5.06
                      ['nav_npcs.lua'] = true, ['nav_transports.lua'] = true}   -- v5.11
local function ver_cmp(a, b)
    local pa, pb = {}, {}
    for n in tostring(a):gmatch('%d+') do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b):gmatch('%d+') do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end
local function http_get(url, extra)
    local ok_https, https = pcall(require, 'ssl.https')
    if not ok_https then return nil, 'Windower is missing ssl.https (LuaSec)' end
    local ltn12 = require('ltn12')
    https.TIMEOUT = 15
    local out = {}
    local hdr = {['User-Agent'] = 'AutoAttack/' .. tostring(_addon.version), ['Cache-Control'] = 'no-cache'}
    for k, v in pairs(extra or {}) do hdr[k] = v end
    local ok, r, code = pcall(https.request, {url = url, sink = ltn12.sink.table(out), headers = hdr})
    if not ok then return nil, tostring(r) end
    if not r then return nil, tostring(code) end
    if code ~= 200 then return nil, 'HTTP ' .. tostring(code) end
    return table.concat(out)
end
-- v4.79: raw.githubusercontent.com keeps .../main/ files for 5 minutes
-- (cache-control max-age=300; a ?query doesn't get past it), so right after a
-- release "aa version" said the old version was newest (Mark, 11-18 21:46).
-- For the default address, ask the GitHub API for the newest commit on main
-- and read the files from that commit (never stale). Falls back to main/.
local function update_base()
    local base = opt('update_url') or UPDATE_URL
    if base:sub(-1) ~= '/' then base = base .. '/' end
    local owner, repo, branch = base:match('^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/$')
    if not owner then return base end
    local sha = http_get('https://api.github.com/repos/' .. owner .. '/' .. repo .. '/commits/' .. branch,
                         {Accept = 'application/vnd.github.sha'})
    sha = sha and sha:match('^%s*(%x+)%s*$')
    if sha and #sha >= 7 then
        return 'https://raw.githubusercontent.com/' .. owner .. '/' .. repo .. '/' .. sha .. '/'
    end
    dbg('UPDATE: GitHub API gave no commit -- reading ' .. branch .. '/ (may be up to 5 min old).')
    return base
end

-- v4.93: older versions on GitHub. Every release is also published as a
-- branch named vX.YY (tags / GitHub releases named vX.YY count too), so
-- "aa update previous" or "aa update 4.88" can go back to one when the
-- newest has a problem (Mark, 2026-11-21). One API call each for branches
-- and tags; files are read from raw.githubusercontent.com/<owner>/<repo>/vX.YY/.
AA_UPD_MIN = '4.69'   -- oldest release kept on GitHub (v4.83 / v4.84 are left out: they crash)
function aa_upd_repo()
    local base = opt('update_url') or UPDATE_URL
    if base:sub(-1) ~= '/' then base = base .. '/' end
    return base:match('^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/')
end
-- list of versions, newest first, and version -> ref name
function aa_upd_versions()
    local o, r = aa_upd_repo()
    if not o then return nil, 'update_url is not a GitHub address -- no older versions to pick from.' end
    local list, refs = {}, {}
    for _, kind in ipairs({'branches', 'tags'}) do
        local body = http_get('https://api.github.com/repos/' .. o .. '/' .. r .. '/' .. kind .. '?per_page=100',
                              {Accept = 'application/vnd.github+json'})
        for ref in (body or ''):gmatch('"name"%s*:%s*"(v?%d+%.%d+[%.%d]*)"') do
            local v = ref:gsub('^v', '')
            if not refs[v] and ver_cmp(v, AA_UPD_MIN) >= 0 then refs[v] = ref; list[#list + 1] = v end
        end
    end
    if #list == 0 then return nil, 'found no versions on GitHub (or GitHub did not answer).' end
    table.sort(list, function(a, b) return ver_cmp(a, b) > 0 end)
    return list, refs
end
-- "previous" / "prev" / "back" / "4.88" / "v4.88" -> version, ref   (or nil, why)
function aa_upd_resolve(sel)
    local list, refs = aa_upd_versions()
    if not list then return nil, refs end
    local have = tostring(_addon.version)
    if sel == 'previous' or sel == 'prev' or sel == 'back' then
        for _, v in ipairs(list) do
            if ver_cmp(v, have) < 0 then return v, refs[v] end
        end
        return nil, 'no version older than v' .. have .. ' on GitHub.'
    end
    local want = tostring(sel):gsub('^v', '')
    if refs[want] then return want, refs[want] end
    local near = {}
    for i = 1, math.min(#list, 8) do near[#near + 1] = list[i] end
    return nil, 'v' .. want .. ' is not on GitHub. Newest: ' .. table.concat(near, ', ') .. ' ("aa update list").'
end

local function do_update(ctx, force, ref)
    local me_n = my_name()
    local function bad(text) reply(ctx, me_n .. ': update failed -- ' .. text); say('UPDATE failed: ' .. text) end
    local base = update_base()   -- v4.79
    if ref then   -- v4.93: a chosen version (aa update previous / aa update 4.88)
        local o, r = aa_upd_repo()
        base = 'https://raw.githubusercontent.com/' .. o .. '/' .. r .. '/' .. ref .. '/'
    end
    local man, e = http_get(base .. 'manifest.txt')
    if not man then return bad('manifest.txt: ' .. tostring(e)) end
    local ver = man:match('version%s*=%s*([%d%.]+)')
    local files = {}
    for name, size in man:gmatch('file%s*=%s*([%w_%.%-]+)%s+(%d+)') do
        if not UPDATE_FILES[name] then return bad('manifest lists "' .. name .. '" -- refused.') end
        files[#files + 1] = {name = name, size = tonumber(size)}
    end
    -- v4.90: "extra=" files (aa_knowledge.lua) -- v4.89 and older skip these lines
    for name, size in man:gmatch('extra%s*=%s*([%w_%.%-]+)%s+(%d+)') do
        if not UPDATE_FILES[name] then return bad('manifest lists "' .. name .. '" -- refused.') end
        files[#files + 1] = {name = name, size = tonumber(size)}
    end
    -- v5.06: "nav=" files (nav.lua, nav_maps.lua, nav_zones.lua) -- v5.05 and older skip these lines
    for name, size in man:gmatch('nav%s*=%s*([%w_%.%-]+)%s+(%d+)') do
        if not UPDATE_FILES[name] then return bad('manifest lists "' .. name .. '" -- refused.') end
        files[#files + 1] = {name = name, size = tonumber(size)}
    end
    if not ver or #files == 0 then return bad('manifest.txt has no version / files.') end
    local have = tostring(_addon.version)
    local c = ver_cmp(ver, have)
    if c == 0 and not force then return reply(ctx, me_n .. ': already on v' .. have .. '.') end
    if c < 0 and not force and not ref then   -- v4.93: a chosen version may be older
        return reply(ctx, me_n .. ': GitHub has v' .. ver .. ', older than v' .. have .. ' -- not downgrading ("aa update force" does it).')
    end
    say('UPDATE: downloading v' .. ver .. ' (have v' .. have .. ', ' .. #files .. ' files).')
    local got = {}
    for _, f in ipairs(files) do
        local body, e2 = http_get(base .. f.name)
        if not body then return bad(f.name .. ': ' .. tostring(e2)) end
        if f.size and #body ~= f.size then
            return bad(f.name .. ' is ' .. #body .. ' bytes, expected ' .. f.size .. ' (GitHub may still be serving the old copy -- try again in a few minutes).')
        end
        if f.name:match('%.lua$') then
            local chunk, perr = (loadstring or load)(body, '=' .. f.name)
            if not chunk then return bad(f.name .. ' does not load: ' .. tostring(perr)) end
        end
        if f.name == 'autoattack.lua' and not body:find("_addon%.version%s*=%s*'" .. ver:gsub('%.', '%%.') .. "'") then
            return bad('autoattack.lua is not v' .. ver .. ' (GitHub may still be serving the old copy -- try again in a few minutes).')
        end
        got[#got + 1] = {name = f.name, data = body}
        -- v4.64: no coroutine.sleep here -- do_update runs inside pcall, and
        -- Lua 5.1 can't yield inside pcall ('attempt to yield across
        -- metamethod/C-call boundary'). Nothing in do_update may yield.
    end
    -- v4.85: no "a fight started" refusal -- the reload resumes the fight (v4.82)
    -- back up the current files, then write the new ones
    local dir = windower.addon_path
    local old = {}
    for _, g in ipairs(got) do
        local fh = io.open(dir .. g.name, 'rb')
        if fh then old[g.name] = fh:read('*a'); fh:close() end
    end
    if windower.dir_exists and windower.create_dir and not windower.dir_exists(dir .. 'backups') then
        windower.create_dir(dir .. 'backups')
    end
    local stamp = os.date('%Y-%m-%d_%H%M')
    for n, data in pairs(old) do
        local stem, ext = n:match('^(.-)(%.[^.]+)$')
        local fh = io.open(dir .. 'backups/' .. stem .. '_v' .. have .. '_pre-update_' .. stamp .. ext, 'wb')
        if fh then fh:write(data); fh:close() end
    end
    for i, g in ipairs(got) do
        local fh = io.open(dir .. g.name, 'wb')
        local okw = fh and fh:write(g.data)
        if fh then fh:close() end
        if not okw then
            for k = 1, i do
                local o = old[got[k].name]
                local r = o and io.open(dir .. got[k].name, 'wb')
                if r then r:write(o); r:close() end
            end
            return bad('could not write ' .. g.name .. ' -- old files put back.')
        end
    end
    reply(ctx, me_n .. ': downloaded v' .. ver .. ' -- reloading...')
    say('UPDATE: v' .. have .. ' -> v' .. ver .. ' installed, reloading.')
    reload_now(ctx, have)
end
-- v5.06: nav.lua / nav_maps.lua / nav_zones.lua missing (an update from v5.05
-- or older only fetches "file=" lines): download the "nav=" files of the
-- release on GitHub, check each (size, loads), write them. true when all are there.
function aa_nav_fetch()
    local base = update_base()
    local man, e = http_get(base .. 'manifest.txt')
    if not man then say('NAV: could not read GitHub (' .. tostring(e) .. ').'); return false end
    local dir, n = windower.addon_path, 0
    for name, size in man:gmatch('nav%s*=%s*([%w_%.%-]+)%s+(%d+)') do
        if UPDATE_FILES[name] then
            local body, e2 = http_get(base .. name)
            if not body or #body ~= tonumber(size) then
                say('NAV: ' .. name .. ' did not download (' .. tostring(e2 or (#body .. ' bytes')) .. ').')
                return false
            end
            if not (loadstring or load)(body, '=' .. name) then say('NAV: ' .. name .. ' does not load.'); return false end
            local fh = io.open(dir .. name, 'wb')
            if not fh then say('NAV: could not write ' .. name .. '.'); return false end
            fh:write(body); fh:close()
            n = n + 1
        end
    end
    if n == 0 then say('NAV: the release on GitHub has no nav files.'); return false end
    say('NAV: downloaded ' .. n .. ' nav files.')
    return true
end

-- v4.65: aa update check / aa version -- compare with GitHub, install nothing
local function cmd_update_check(ctx)
    local me_n, have = my_name(), tostring(_addon.version)
    local base = update_base()   -- v4.79
    local man, e = http_get(base .. 'manifest.txt')
    if not man then return reply(ctx, me_n .. ': v' .. have .. ' -- could not read GitHub (' .. tostring(e) .. ').') end
    local ver = man:match('version%s*=%s*([%d%.]+)')
    if not ver then return reply(ctx, me_n .. ': v' .. have .. ' -- GitHub manifest has no version.') end
    local c = ver_cmp(ver, have)
    local st = (c == 0) and 'up to date' or (c > 0) and '"aa update" to install' or 'newer than GitHub'
    reply(ctx, string.format('%s: v%s (GitHub: v%s) -- %s', me_n, have, ver, st))
end

-- v4.65: aa rollback [all] -- back to the newest version an aa update backed up
local function cmd_rollback(ctx, w)
    if w[2] == 'all' and ctx.src ~= 'party' and has_players() then
        if ctx.src == 'tell' then reply(ctx, my_name() .. ': rolling back the whole party.') end
        return party_command('aa rollback')
    end
    local me_n, cur = my_name(), tostring(_addon.version)
    if engaged() or party_fighting() then
        return reply(ctx, me_n .. ': fighting -- send "aa rollback" again after the fight.')
    end
    if not (aa_rollback_find and aa_rollback_restore) then
        return reply(ctx, me_n .. ': rollback needs autoattack.lua v4.65 or later.')
    end
    local set = aa_rollback_find(cur)
    if not set then
        return reply(ctx, me_n .. ': no earlier version backed up by "aa update" -- nothing to roll back to.')
    end
    local ok, why = aa_rollback_restore(set)
    if not ok then return reply(ctx, me_n .. ': rollback failed -- ' .. tostring(why)) end
    reply(ctx, me_n .. ': rolled back to v' .. set.ver .. ' -- reloading...')
    say('ROLLBACK: v' .. cur .. ' -> v' .. set.ver .. ' (from ' .. tostring(ctx.sender) .. ').')
    reload_now(ctx, cur)
end

local function cmd_update(ctx, w)
    -- v4.79: typed //aa update (and update check) goes to the whole party, in
    -- any zone -- party chat reaches every member. "aa update me" = only you.
    local mine = w[2] == 'me' or w[3] == 'me'
    if w[2] == 'check' then
        if ctx.src == 'local' and not mine and has_players() then return party_command('aa version') end
        return cmd_update_check(ctx)
    end
    local force = w[2] == 'force' or w[3] == 'force' or w[4] == 'force'
    -- v4.93: aa update list | previous | <version>
    local sel = w[2]
    if sel == 'list' then
        local list, why = aa_upd_versions()
        if not list then return reply(ctx, my_name() .. ': ' .. tostring(why)) end
        local top = {}
        for i = 1, math.min(#list, 15) do top[#top + 1] = list[i] end
        return reply(ctx, my_name() .. ': v' .. tostring(_addon.version) .. ' -- on GitHub: ' .. table.concat(top, ', '))
    end
    local ref
    if sel == 'previous' or sel == 'prev' or sel == 'back' or (sel and sel:match('^v?%d+%.%d+[%.%d]*$')) then
        local ver, r = aa_upd_resolve(sel)
        if not ver then return reply(ctx, my_name() .. ': ' .. tostring(r)) end
        -- typed: the whole party goes to that exact version (not each one's own "previous")
        if not mine and ctx.src == 'local' and has_players() then
            return party_command('aa update ' .. ver .. (force and ' force' or ''))
        end
        ref = r
    elseif not mine and (w[2] == 'all' or ctx.src == 'local') and ctx.src ~= 'party' and has_players() then
        if ctx.src == 'tell' then reply(ctx, my_name() .. ': updating the whole party.') end
        return party_command('aa update' .. (force and ' force' or ''))
    end
    -- v4.82: no "fighting" refusal -- the reloaded AA resumes the fight (save_resume)
    if P.busy then return reply(ctx, my_name() .. ' is busy: ' .. P.busy .. ' -- "aa cancel" first, then "aa update".') end
    if P.updating then return end
    P.updating = true
    local ok, err = pcall(do_update, ctx, force, ref)
    P.updating = false
    if not ok then reply(ctx, my_name() .. ': update failed -- ' .. tostring(err)) end
end

handle_command = function(ctx, text)
    if opt('enabled') == false then return end
    local w, raw = {}, {}
    for word in text:gmatch('%S+') do raw[#raw + 1] = word; w[#w + 1] = word:lower() end
    if w[1] == 'aa' then table.remove(w, 1); table.remove(raw, 1) end
    local c = w[1]
    if not c then return end
    dbg('command from ' .. tostring(ctx.sender) .. ' (' .. ctx.src .. '): ' .. text)

    if c == 'invite' then cmd_invite(ctx, w)
    elseif c == 'fight' then do_fight(ctx)
    elseif c == 'stop' then do_stop(ctx)
    elseif c == 'stack' then cmd_stack(ctx, w)
    elseif c == 'follow' then cmd_follow(ctx, w)
    elseif c == 'unfollow' then
        P.follow, P.follow_fight = nil, false; run_stop()
        say('stopped following.')
    elseif c == 'cancel' then
        if P.busy then
            local what = P.busy
            P.gen = P.gen + 1; P.busy, P.step = nil, 'idle'
            P.stack = nil; run_stop()
            reply(ctx, my_name() .. ': cancelled ' .. what .. '.')
        elseif ctx.src ~= 'party' then
            reply(ctx, my_name() .. ': nothing to cancel.')
        end
    elseif c == 'disband' then cmd_disband(ctx, false)
    elseif c == 'leave' then cmd_disband(ctx, true)
    elseif c == 'leader' or c == 'lead' or c == 'sync' then
        -- v5.56: "aa leader <name> sync <name>" / "aa sync <name> leader <name>"
        -- (Mark, 11-24: "aa leader shadow sync shadow" only moved the leader --
        -- the sync words were ignored). Only the leader can set Level Sync, so
        -- the sync goes first, then the leader is passed.
        local use = 'Use: aa leader <name> [sync <name>] / aa sync <name> [leader <name>]'
        if not need_lead(ctx) then return end   -- only the leader parses / answers
        local lead, sync
        local i = 1
        while w[i] do
            local k = w[i]
            if k == 'leader' or k == 'lead' or k == 'sync' then
                local who = resolve(w[i + 1], ctx.sender)
                if not who then return reply(ctx, w[i + 1] and ('"' .. w[i + 1] .. '" after ' .. k .. ' is not on my friend list.') or use) end
                if k == 'sync' then sync = who else lead = who end
                i = i + 2
            else
                return reply(ctx, 'Unknown word "' .. k .. '". ' .. use)
            end
        end
        for _, who in ipairs({lead or false, sync or false}) do
            if who and not member(who) then return reply(ctx, who .. ' is not in the party.') end
        end
        local pass = lead and lead:lower() ~= my_name():lower()
        if lead and not pass and not sync then return reply(ctx, my_name() .. ' is already the party leader.') end
        if sync then
            coroutine.schedule(function()   -- v5.26
                local ok = set_level_sync(ctx, sync)
                if pass then
                    if not ok then reply(ctx, 'Level Sync not set -- still passing leader to ' .. lead .. '.') end
                    coroutine.sleep(1)
                    send('input /pcmd leader ' .. lead)
                end
            end, 0)
        elseif pass then
            send('input /pcmd leader ' .. lead)
        end
    elseif c == 'unsync' then
        if not need_lead(ctx) then return end
        coroutine.schedule(function()   -- v5.27: designee's name, see sync_off_request
            local r = sync_off_request(function(t) coroutine.sleep(t); return true end)
            if r then reply(ctx, 'Level Sync off -- the game ends it in 30s.')
            else reply(ctx, 'The game ignored "Level Sync off" -- remove it from the party menu.') end
        end, 0)
    elseif c == 'trusts' then cmd_trusts(ctx, w)
    elseif c == 'retr' then
        if has_players() and not need_lead(ctx) then return end
        send('input ' .. opt('retr_command'))
    elseif c == 'rest' then cmd_rest(ctx)
    elseif c == 'mount' then
        if engaged() then return reply(ctx, my_name() .. " is fighting -- can't mount.") end
        P.follow_fight = false
        if aa_running() then send('aa stop'); coroutine.sleep(1) end
        local name = raw[2] and table.concat(raw, ' ', 2) or opt('mount')
        if not name or name == '' then name = 'Raptor' end
        send('input /mount "' .. name .. '"')
    elseif c == 'dismount' then send('input /dismount')
    elseif c == 'sneak' or c == 'invis' or c == 'invisible' then cmd_sneak(ctx, w)
    elseif c == 'warp' or c == '299' then cmd_warp(ctx)
    elseif c == 'nav' then   -- v5.06: nav.lua
        local words = {}
        for i = 2, #raw do words[#words + 1] = raw[i] end
        if aa_nav_command then
            -- v5.15: nav progress from a party line goes to each player's own
            -- chat window, not to party chat (a /tell still answers by tell)
            aa_nav_command(ctx, words, function(t)
                if ctx.src == 'party' then windower.add_to_chat(207, '[AA] ' .. t) else reply(ctx, t) end
            end)
        else
            reply(ctx, my_name() .. ': aa nav is not loaded (nav.lua missing -- "aa update force").')
        end
    elseif c == 'buy' then   -- v5.45: nav.lua (Curio Vendor / Green Thumb Moogles)
        local words = {}
        for i = 2, #raw do words[#words + 1] = raw[i] end
        if aa_buy_command then
            aa_buy_command(ctx, words, function(t)
                if ctx.src == 'party' then windower.add_to_chat(207, '[AA] ' .. t) else reply(ctx, t) end
            end)
        else
            reply(ctx, my_name() .. ': aa buy is not loaded (nav.lua missing -- "aa update force").')
        end
    elseif c == 'trade' then   -- v5.49: nav.lua (seals / crests to Shami, Rem's Tales to Monisette)
        local words = {}
        for i = 2, #raw do words[#words + 1] = raw[i] end
        if aa_trade_command then
            aa_trade_command(ctx, words, function(t)
                if ctx.src == 'party' then windower.add_to_chat(207, '[AA] ' .. t) else reply(ctx, t) end
            end)
        else
            reply(ctx, my_name() .. ': aa trade is not loaded (nav.lua missing -- "aa update force").')
        end
    elseif c == 'pass' then cmd_pool(ctx, false)
    elseif c == 'lot' then cmd_pool(ctx, true)
    elseif c == 'retrust' then cmd_retrust(ctx)
    elseif c == 'status' then reply(ctx, status_line())
    elseif c == 'ping' then   -- v4.65: name, version, job, mode, memory
        local pl = me()
        local job = pl and ((pl.main_job or '?') .. tostring(pl.main_job_level or '') .. '/' .. (pl.sub_job or '-')) or '?'
        local mode = aa_running() and tostring(aa_get_mode and aa_get_mode() or 'on'):upper() or 'idle'
        reply(ctx, string.format('%s v%s | %s | %s | %.1f MB', my_name(), tostring(_addon.version), job, mode,
            collectgarbage('count') / 1024))
    elseif c == 'reload' or c == 'rl' then cmd_reload(ctx, w)   -- v4.60
    elseif c == 'update' then cmd_update(ctx, w)                 -- v4.62
    elseif c == 'version' then                                   -- v4.65
        -- v4.79: typed //aa version asks the whole party ("aa version me" = only you)
        if ctx.src == 'local' and w[2] ~= 'me' and has_players() then party_command('aa version')
        else cmd_update_check(ctx) end
    elseif c == 'rollback' then cmd_rollback(ctx, w)             -- v4.65
    elseif c == 'help' then
        if ctx.src ~= 'party' or not ctx.self then
            for _, line in ipairs(HELP) do reply(ctx, line); coroutine.sleep(1) end
        end
    elseif PASS_THROUGH[c] then
        pass_through(ctx, c, w)   -- v4.69: answers the sender
    elseif ctx.src ~= 'party' then
        reply(ctx, 'Unknown command "' .. c .. '". Send "aa help".')
    end
end

-- ---------------------------------------------------------------------------
-- //aa <party command> typed on this character (called from autoattack.lua)
-- ---------------------------------------------------------------------------
local LOCAL = {invite = true, fight = true, stack = true, follow = true, unfollow = true,
               cancel = true, disband = true, leave = true, leader = true, lead = true,
               sync = true, unsync = true, trusts = true, retr = true, rest = true,
               mount = true, dismount = true, pass = true, status = true, ping = true,
               lot = true, retrust = true, sneak = true, invis = true, invisible = true,
               warp = true, ['299'] = true, reload = true, rl = true, update = true, rollback = true, version = true,
               nav = true, buy = true, trade = true}   -- v5.06, v5.45, v5.49

function aa_party_command(command, args)
    -- v4.75: //aa assist / //aa pull typed (not started by aa fight): stay put
    if command == 'assist' or command == 'pull' or command == 'start' then
        leave_fight_mode('//aa ' .. command)
        return false
    end
    if command == 'stop' then
        -- typed //aa stop: autoattack.lua stops the fight; v5.31: everything
        -- else stops too. Not when aa nav sent it to stop the loop before a
        -- warp (aa_nav_guarded) -- then only the fight stops.
        if not (aa_nav_guarded and aa_nav_guarded()) then
            local what = stop_everything('//aa stop')
            if #what > 0 then say('STOP: ' .. table.concat(what, ', ') .. ' stopped.') end
        end
        return false
    end
    if command == 'party' then
        local names = {}
        for _, f in ipairs(opt('friends') or {}) do
            names[#names + 1] = type(f) == 'table' and (tostring(f.name) .. (f.nick and (' (' .. f.nick .. ')') or '')) or tostring(f)
        end
        windower.add_to_chat(207, '[AA] Party commands ' .. (opt('enabled') == false and 'OFF' or 'ON') ..
            ' | friends: ' .. (#names > 0 and table.concat(names, ', ') or 'none (set party.friends in aa_config.lua)'))
        windower.add_to_chat(207, string.format('[AA] party_range %sy | follow_range %sy | stack_wait %ss | trust_wait %ss | finish_timeout %ss | auto_accept %s | mount %s',
            tostring(opt('party_range')), tostring(opt('follow_range')), tostring(opt('stack_wait')), tostring(opt('trust_wait')),
            tostring(opt('finish_timeout')), tostring(opt('auto_accept')), tostring(opt('mount'))))
        windower.add_to_chat(207, '[AA] ' .. status_line())
        return true
    end
    if not LOCAL[command] then return false end
    local text = command .. ((args and #args > 0) and (' ' .. table.concat(args, ' ')) or '')
    local me_name = my_name()
    coroutine.schedule(function() handle_command({src = 'local', sender = me_name}, text) end, 0)
    return true
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
local function clean(s)
    return (s or ''):gsub('[%z\1-\31\127-\255]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
end

windower.register_event('chat message', function(message, sender, mode, gm)
    if mode ~= 3 and mode ~= 4 then return end          -- 3 = tell, 4 = party
    if not sender or sender == '' or sender == my_name() then return end
    local text = clean(message)
    local low = text:lower()
    -- v4.52: "[AA] <name>: I can Warp II." from a friend in the party during aa warp
    if mode == 4 and P.warping and low:find('^%[aa%] %S+: i can warp ii') then
        if is_friend(sender) and member(sender) then P.warp_mages[sender] = true end
        return
    end
    if not (low == 'aa' or low:find('^aa%s') or low:find('^aa~')) then return end
    if not is_friend(sender) then
        dbg('ignored "' .. text .. '" from ' .. sender .. ' (not on the friend list).')
        return
    end
    if low:find('^aa~') then
        -- v4.90: group skillchain profiles / learned damage from a party member
        if mode == 4 and low:find('^aa~g%s') then
            local _k = sender .. '|' .. text                  -- v4.91: taken from the packet already?
            if P.gsc_took and P.gsc_took[_k] and os.clock() - P.gsc_took[_k] < 5 then return end
            if member(sender) and gsc_proto then
                local ok, err = pcall(gsc_proto, sender, text)
                if not ok then dbg('aa~g from ' .. sender .. ' failed: ' .. tostring(err)) end
            end
            return
        end
        if mode == 3 then handle_proto(sender, text) end
        return
    end
    if mode == 4 and not member(sender) then return end
    local ctx = {src = (mode == 3) and 'tell' or 'party', sender = sender}
    coroutine.schedule(function() handle_command(ctx, text) end, 0)
end)

-- your own party "aa ..." lines: run them here too, so a party command acts
-- on every AutoAttack in the party, the sender included (v4.67).
-- v4.67: before, only an outgoing line starting with "/p" or "/party" was
-- caught; a line typed with the chat box already in party mode (no /p), or
-- sent by a macro, never ran on the sender. Now the party echo of your own
-- line (incoming text mode 5 = party, outgoing -- res/chat.lua) runs it too,
-- and the /p hook stays as a fallback. P.self_ran stops a double run.
-- "aa follow <your own name>" still does nothing on you (cmd_follow).
P.self_ran = P.self_ran or {}
local function run_own_party_line(body)
    body = (body or ''):lower():gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if not (body == 'aa' or body:find('^aa%s')) then return end
    local now = os.clock()
    local t = P.said[body]
    if t and now - t < 5 then return end                 -- AA said it (and ran it) already
    local r = P.self_ran[body]
    if r and now - r < 3 then return end                 -- echo + /p hook: run once
    P.self_ran[body] = now
    local me_name = my_name()
    dbg('own party line: ' .. body)
    coroutine.schedule(function()
        handle_command({src = 'party', sender = me_name, self = true}, body)
    end, 0.5)
end

windower.register_event('outgoing text', function(original, modified)
    local s = clean(modified or original):lower()
    if s:find('^/p%s') or s:find('^/party%s') then party_sent_now() end   -- v4.68
    local body = s:match('^/p%s+(aa.*)$') or s:match('^/party%s+(aa.*)$')
    if body then run_own_party_line(body) end
end)

-- v4.67: the party echo of your own line, e.g. "(Shadowhammer) aa version"
windower.register_event('incoming text', function(original, modified, mode)
    if mode ~= 5 then return end
    local s = clean(original)
    local who, body = s:match('^%(([%a]+)%)%s*(.*)$')
    if not who or who ~= my_name() or not body then return end
    party_sent_now()   -- v4.68: any own party line (typed in party mode / macro)
    if body:lower():find('^aa') then run_own_party_line(body) end
end)

windower.register_event('party invite', function(sender)
    if not opt('auto_accept') or not sender or not is_friend(sender) then return end
    if has_players() then return end
    say('invite from ' .. sender .. ' -- joining.')
    coroutine.schedule(function()
        if trust_count() > 0 then drop_trusts(P.gen); coroutine.sleep(1) end
        send('input /join')
    end, 1.5)
end)

windower.register_event('zone change', function()
    if P.busy then say('zoned -- cancelled ' .. P.busy .. '.') end
    P.gen = P.gen + 1
    P.busy, P.step, P.stack = nil, 'idle', nil
    P.follow_fight = false
    P.fast_last, P.engaging = {}, false  -- v4.50
    P.lead_mob = nil   -- v5.00
    -- v4.52: warped (or zoned) -- stop any warp in progress, free the ring slot
    P.warp_gen = (P.warp_gen or 0) + 1
    P.warping = false
    aa_warp_restore(true)   -- v4.53: old right ring back on after loading
    run_stop()
    P.zone_quiet = os.clock() + 15   -- v4.80: the party list reloads after a zone
    if gsc_on_zone then pcall(gsc_on_zone) end   -- v4.90
end)

-- v5.05: LEADER CHANGES (Mark, 2026-11-22: "Shadow change leader to myth, then
-- left the party, and all the players are still following shadow"). aa fight
-- members stack on whoever leads now; the new leader stops stacking on anyone;
-- with no leader / no party, fight mode ends. aa follow stops when the
-- followed player leaves. Acts after the change holds LEADER_CHANGE_SECS (the
-- party list reloads while zoning).
LEADER_CHANGE_SECS = 2
function leader_watch(L, now)
    if now < (P.zone_quiet or 0) then P.lc_since = nil; return end
    if P.follow_fight and P.follow then
        local lead = has_players() and L or nil
        local gone = not member(P.follow)
        if lead == P.follow and not gone then P.lc_since = nil; return end
        P.lc_since = P.lc_since or now
        if now - P.lc_since < LEADER_CHANGE_SECS then return end
        P.lc_since = nil
        local old = P.follow
        if lead and lead == my_name() then
            P.follow, P.follow_fight, P.stack, P.lead_mob = nil, false, nil, nil
            run_stop()
            say('FIGHT: ' .. old .. ' is no longer leading -- you lead now. Not stacking on anyone; send "aa fight" to start pulling.')
        elseif lead and member(lead) then
            P.follow, P.stack, P.lead_mob = lead, nil, nil
            run_stop()
            say('FIGHT: party leader is now ' .. lead .. ' (was ' .. old .. ') -- assisting and stacking on ' .. lead .. '.')
        else
            P.follow, P.follow_fight, P.stack, P.lead_mob = nil, false, nil, nil
            run_stop()
            say('FIGHT: ' .. old .. (gone and ' left the party' or ' is no longer leading') .. ' -- fight mode off, staying here.')
        end
        return
    end
    if P.follow and not P.follow_fight and not member(P.follow) then
        P.lc_since = P.lc_since or now
        if now - P.lc_since < LEADER_CHANGE_SECS then return end
        P.lc_since = nil
        say('FOLLOW: ' .. P.follow .. ' left the party -- not following.')
        P.follow, P.stack = nil, nil
        run_stop()
    end
end

-- v4.46: a player joining the party (any invite, typed or AA's) starts the
-- 120s Trust window; becoming leader by a hand-off clears it.
local function watch_party()
    local now = os.clock()
    if now < P.watch_next then return end
    P.watch_next = now + 1
    local n, lead = players(), i_lead()
    -- v4.80: a join is a player NAME not in the party in the last 2 minutes,
    -- and not within 15s of zoning. While you zone, the party list reloads
    -- (Trusts briefly look like players, members drop out and come back), and
    -- the old head count said "a player joined" on every zone (Mark, 11-18).
    P.seen = P.seen or {}
    local joined
    local list = members()
    if P.watch_players and n > P.watch_players and now >= (P.zone_quiet or 0) then
        local mine = my_name()
        for _, m in ipairs(list) do
            local t = P.seen[m.name]
            if not m.trust and m.name ~= mine and not (t and now - t < 120) then joined = m.name end
        end
    end
    for _, m in ipairs(list) do P.seen[m.name] = now end
    if joined then
        P.last_join = now
        dbg(joined .. ' joined the party -- no Trusts for ' .. opt('trust_wait') .. 's.')
        if gsc_on_join then pcall(gsc_on_join, joined) end   -- v4.90
    end
    if P.watch_lead == false and lead and has_players() then
        P.last_join = nil
        dbg('became party leader -- Trust window cleared.')
    end
    P.watch_players, P.watch_lead = n, lead
    -- v4.50: forget fast-assist mobs older than a minute
    for id, t in pairs(P.fast_last) do if now - t > 60 then P.fast_last[id] = nil end end
    -- v4.50: leader's entity ID for fast assist
    local L = leader_name()
    local lm = L and member(L)
    P.leader_id = lm and lm.id or nil
    pcall(leader_watch, L, now)   -- v5.05
end

-- ---------------------------------------------------------------------------
-- v4.50: FAST ASSIST. An aa fight member used to wait for ASSIST mode to see
-- the mob as the party's <bt>, then /target <bt>, wait 1s, face, wait, attack
-- -- once per loop pass. Now the moment the leader acts on a mob (Provoke,
-- /ra, melee, WS, spell) or a mob acts on anyone in the party, the member
-- targets that mob and attacks.
-- ---------------------------------------------------------------------------
-- v5.48: ENGAGE TRACE per leader's mob (what fast assist tried, and what the
-- game said). 11-23 21:35-21:47 (v5.47 both sides): Myth stood idle 18.5-19.9s
-- next to 5 of 11 bats with 0 target give-ups, so the v5.47 cause was not it;
-- Myth's own log isn't reachable, so the member now reports it (ENGAGE-STUCK).
local function fe_trace(mob_id)
    local f = P.fe
    if not f or f.id ~= mob_id then
        f = {id = mob_id, t0 = os.clock(), calls = 0, skips = 0, atk = 0, asst = 0, pk = 0, why = '-', msg = nil}
        P.fe = f
    end
    return f
end
local function fe_cursor_wait(mob_id, n)
    local t
    for _ = 1, n do
        coroutine.sleep(0.1)
        t = windower.ffxi.get_mob_by_target('t')
        if t and t.id == mob_id then return t end
    end
    return t
end
-- v5.52: engage by packet (outgoing 0x01A category 0x02 'Engage'), the packet the
-- client itself sends for /attack on. Used when /attack on with the cursor on
-- the leader's mob didn't take (11-23 ENGAGE-STUCK: "f4/2/2/2" -- cursor on the
-- bat, /attack on x2, still idle; the /assist fallback then put the cursor on
-- the wrong bat).
local function engage_packet(m)
    if not m or not m.id or not m.index or opt('engage_packet') == false then return false end
    if aa_stale_loop and aa_stale_loop() then return false end
    local ok = pcall(function()
        local packets = require('packets')
        packets.inject(packets.new('outgoing', 0x01A, {
            ['Target']       = m.id,
            ['Target Index'] = m.index,
            ['Category']     = 0x02,   -- Engage
            ['Param']        = 0,
        }))
    end)
    return ok
end
-- v5.52: wait up to secs for us to be engaged on mob_id (true) or not
local function wait_engaged(mob_id, secs)
    local t0 = os.clock()
    while os.clock() - t0 < secs do
        coroutine.sleep(0.1)
        local p, t = me(), windower.ffxi.get_mob_by_target('t')
        if p and p.status == 1 and t and t.id == mob_id then return true end
        if p and p.status ~= 0 and p.status ~= 1 then return false end
    end
    return false
end
local function fast_engage(mob_id, why, live)   -- v5.02: live = the leader's live mob
    -- v5.02: a fast engage that never finished doesn't block the next one
    if P.engaging and os.clock() - (P.engaging_at or 0) > 3 then P.engaging = false end
    if P.engaging or engaged() then return end
    local last = P.fast_last[mob_id]
    if last and os.clock() - last < (live and 1.5 or 3) then return end
    P.fast_last[mob_id] = os.clock()
    P.engaging, P.engaging_at = true, os.clock()
    coroutine.schedule(function()
        local f = fe_trace(mob_id)
        f.calls = f.calls + 1
        local m = windower.ffxi.get_mob_by_id(mob_id)
        if m and m.spawn_type == 16 and m.hpp and m.hpp > 0 and m.valid_target and not engaged() then
            local t = windower.ffxi.get_mob_by_target('t')
            if not t or t.id ~= mob_id then
                -- v5.48: the target packet already missed this mob, or /attack on
                -- went out twice and we're still idle: the game's own /assist
                -- <leader> (puts the cursor on the leader's target natively)
                local lead = P.follow
                if lead and opt('assist_fallback') ~= false and (f.skips >= 1 or f.atk >= 2) then
                    f.asst = f.asst + 1
                    send('input /assist ' .. lead)
                    t = fe_cursor_wait(mob_id, 12)
                    if not (t and t.id == mob_id) then
                        f.why = 'assist:' .. (t and t.id and ('on ' .. tostring(t.name)) or 'no cursor')
                    end
                elseif set_target then
                    -- v5.02: the leader's live mob skips the post-kill quiet window
                    if set_target(mob_id, live and true or nil) == false then f.why = 'set_target refused' end
                    t = fe_cursor_wait(mob_id, 8)
                end
            end
            m = windower.ffxi.get_mob_by_id(mob_id)
            if t and t.id == mob_id and m and m.hpp and m.hpp > 0 and not engaged() then
                if face then face('f') end
                coroutine.sleep(0.15)
                send('input /attack on')
                f.atk, f.atk_at = f.atk + 1, os.clock()
                say(string.format('FAST-ASSIST >>>> %s (%s%s).', tostring(m.name), why,
                    f.asst > 0 and ', via /assist' or ''))
                -- v5.52: still idle 1.2s after /attack on with the cursor on it ->
                -- engage packet once (before the /assist fallback moves the cursor)
                if not wait_engaged(mob_id, 1.2) then
                    local p2, t2 = me(), windower.ffxi.get_mob_by_target('t')
                    m = windower.ffxi.get_mob_by_id(mob_id)
                    if p2 and p2.status == 0 and t2 and t2.id == mob_id and m and (m.hpp or 0) > 0
                       and f.pk < 2 and engage_packet(m) then
                        f.pk = f.pk + 1
                        local took = wait_engaged(mob_id, 1.0)
                        say(string.format('FAST-ASSIST: /attack on didn\'t take in 1.2s -- engage packet sent (%s).',
                            took and 'engaged' or 'still idle'))
                    end
                end
            else
                f.skips = f.skips + 1
                if f.why == '-' then
                    f.why = (t and t.id) and ('cursor on ' .. tostring(t.name)) or 'no cursor'
                end
                dbg('FAST-ASSIST skipped ' .. tostring(mob_id) .. ' (' .. f.why .. ').')
            end
        elseif m and m.hpp and m.hpp > 0 and not m.valid_target then
            f.why = 'not valid_target'
        end
        P.engaging = false
    end, 0)
end

-- v5.00: FAST SWITCH. Still engaged on the mob that just died (the game takes a
-- moment to drop you) when the leader hits the next one: switch to it while
-- engaged, the way the leader's hot switch does, instead of waiting to go idle.
-- Never switches away from a live mob.
local function corpse_switch(mob_id, why)
    if P.engaging then return end
    local t = windower.ffxi.get_mob_by_target('t')
    if t and t.id == mob_id then return end
    if t and t.spawn_type == 16 and (t.hpp or 0) > 0 then return end   -- still fighting a live mob
    local now = os.clock()
    local last = P.fast_last[mob_id]
    if last and now - last < 2 then return end
    P.fast_last[mob_id] = now
    local m = windower.ffxi.get_mob_by_id(mob_id)
    if not m or m.spawn_type ~= 16 or not m.valid_target or not m.hpp or m.hpp <= 0 then return end
    if not (engaged_switch and engaged_switch(m)) then return end
    say(string.format('FAST-SWITCH >>>> %s (%s, off the last kill).', tostring(m.name), why))
    if opt('switch_verify') == false then return end
    -- v5.52: watch the switch go through, like the leader's hot switch (v5.00:
    -- most switches "missed" because the game dropped us out of attack with the
    -- cursor already on the new mob). 11-23 22:33-22:49: Myth engaged on the
    -- corpse at the kill, idle 4s later, on the next bat 5-7s after Shadow.
    -- Dropped out with the cursor on it -> /attack on at once; still engaged on
    -- the corpse after 0.35s -> switch once more; idle with the cursor
    -- elsewhere -> hand over to fast assist right away.
    P.engaging, P.engaging_at = true, os.clock()
    coroutine.schedule(function()
        local st = {t0 = os.clock()}
        -- one look, never yields (pcall in Lua 5.1 can't hold a sleep); true = finished
        local function step()
            local p, t = me(), windower.ffxi.get_mob_by_target('t')
            local mm = windower.ffxi.get_mob_by_id(mob_id)
            if not mm or (mm.hpp or 0) <= 0 then st.why = 'mob gone'; return true end
            if not p then st.why = 'no player'; return true end
            local el = os.clock() - st.t0
            -- on it: keep watching ~1.2s, the game's drop-out comes 0.5-1s after the switch
            if p.status == 1 and t and t.id == mob_id then st.seen = st.seen or el; return el >= 1.2 end
            if p.status == 0 and t and t.id == mob_id and not st.attacked then
                st.attacked = el
                send('input /attack on')
            elseif p.status == 0 and (not t or t.id ~= mob_id) and el >= 0.3 then
                st.why = 'idle, cursor ' .. (t and t.id and ('on ' .. tostring(t.name)) or 'off'); return true
            elseif p.status == 1 and (not t or t.id ~= mob_id) and not st.resent and el >= 0.35 then
                st.resent = true
                engaged_switch(mm)
            end
            return false
        end
        while true do
            coroutine.sleep(0.1)
            local okc, done = pcall(step)
            if not okc then st.why = 'error: ' .. tostring(done); break end
            if done then break end
            if os.clock() - st.t0 >= 1.6 + (st.attacked and 1.2 or 0) then st.why = st.why or 'timed out'; break end
        end
        do
            local p, t = me(), windower.ffxi.get_mob_by_target('t')
            st.ok = (p and p.status == 1 and t and t.id == mob_id) and true or false
        end
        local extra = (st.attacked and string.format(' (dropped out of attack -- /attack on after %.1fs)', st.attacked) or '') ..
                      (st.resent and ' (switch sent twice)' or '')
        if st.ok then
            dbg(string.format('FAST-SWITCH-OK: on %s (watched %.1fs)%s.', tostring(m.name), os.clock() - st.t0, extra))
        else
            dbg(string.format('FAST-SWITCH-MISS: %s%s -- fast assist takes over.', tostring(st.why or '?'), extra))
            P.fast_last[mob_id] = nil   -- fast assist may go at once
        end
        P.engaging = false
    end, 0)
end
-- v5.00: the leader's mob is ours to join for LEAD_MOB_KEEP s after the leader acts on it
LEAD_MOB_KEEP = 20
local function lead_mob_ok(m)
    if not m or m.spawn_type ~= 16 or not m.valid_target or not m.hpp or m.hpp <= 0 then return false end
    if not m.distance or m.distance > 625 then return false end   -- 25y
    if m.claim_id and m.claim_id ~= 0 then
        for _, x in ipairs(members()) do if x.id == m.claim_id then return true end end
        return false
    end
    return true
end
local function lead_mob_watch()
    local now = os.clock()
    if now < (P.lead_watch_at or 0) then return end
    P.lead_watch_at = now + 0.25
    if not P.follow_fight or not aa_running() or aa_get_mode() ~= 'assist' then
        P.lw_why = not P.follow_fight and 'not aa fight' or (not aa_running() and 'AA off' or 'mode ' .. tostring(aa_get_mode()))
        return
    end
    -- v5.02: the leader's own target (engaged), the moment it changes
    local lmem = P.follow and member(P.follow)
    local lmob = lmem and lmem.mob
    if lmob and lmob.status == 1 and (lmob.target_index or 0) > 0 then
        local tm = windower.ffxi.get_mob_by_index(lmob.target_index)
        if tm and tm.id and tm.id ~= P.lead_mob and lead_mob_ok(tm) then
            P.lead_mob, P.lead_mob_at = tm.id, now
        elseif tm and tm.id == P.lead_mob then
            P.lead_mob_at = now
        end
    end
    if not P.lead_mob or now - (P.lead_mob_at or 0) > LEAD_MOB_KEEP then
        P.lw_why = P.lead_mob and 'lead mob stale' or 'no lead mob'
        return
    end
    local p = me()
    if not p then return end
    local m = windower.ffxi.get_mob_by_id(P.lead_mob)
    if not lead_mob_ok(m) then
        P.lw_why = 'lead mob not ok (' .. (not m and 'gone' or (m.claim_id and m.claim_id ~= 0 and 'claim ' .. tostring(m.claim_id) or 'dist/hp')) .. ')'
        P.lead_mob = nil
        return
    end
    P.lw_why = 'ok'

    if p.status == 0 then fast_engage(P.lead_mob, "leader's mob", true)
    elseif p.status == 1 then corpse_switch(P.lead_mob, "leader's mob") end
end

-- v5.48: ENGAGE-STUCK. aa fight member, idle while the leader has been
-- engaged on its mob for STUCK_SECS: say what fast assist saw (local log +
-- one "aa~g e stuck ..." line to the leader, max one per mob / 15s) and
-- try the game's /assist <leader> right away.
STUCK_SECS = 6
local function stuck_watch()
    local now = os.clock()
    if now < (P.stuck_at or 0) then return end
    P.stuck_at = now + 0.5
    if not P.follow_fight or not P.follow or i_lead() then P.W = nil; return end
    if not aa_running() or aa_get_mode() ~= 'assist' then P.W = nil; return end
    local lm = member(P.follow)
    local lmob = lm and lm.mob
    if not lmob or lmob.status ~= 1 or (lmob.target_index or 0) == 0 then P.W = nil; return end
    local W = P.W
    if not W or W.idx ~= lmob.target_index then
        W = {idx = lmob.target_index, t0 = now, rep = false}
        P.W = W
    end
    local p = me()
    if not p or p.status == 1 or W.rep or now - W.t0 < STUCK_SECS then return end
    if p.vitals and p.vitals.hp == 0 then return end
    W.rep = true
    local mob = windower.ffxi.get_mob_by_index(W.idx)
    if not mob or not mob.id or (mob.hpp or 0) <= 0 then return end
    local f = (P.fe and P.fe.id == mob.id) and P.fe or nil
    local t = windower.ffxi.get_mob_by_target('t')
    local bt = windower.ffxi.get_mob_by_target('bt')
    local d = mob.distance and math.sqrt(mob.distance) or -1
    local blk = aa_mob_blocked and aa_mob_blocked(mob.id) or 0
    local q = math.max(0, (target_quiet_until or 0) - now)
    local beat = now - (aa_loop_beat or now)
    -- short form for the party line (110 chars max for the whole line)
    local short = string.format('%.0fs %.1fy f%d/%d/%d/%d/%d %s|%s|t%s bt%s q%.0f b%.0f L%.0f %s',
        now - W.t0, d, f and f.calls or 0, f and f.skips or 0, f and f.atk or 0, f and f.asst or 0, f and f.pk or 0,
        f and f.why or '-', tostring(P.lw_why or '-'),
        (t and t.id == mob.id) and '=' or (t and t.id and 'x' or '0'),
        (bt and bt.id == mob.id) and '=' or (bt and bt.id and 'x' or '0'),
        q, blk, beat, (f and f.msg) and f.msg:sub(1, 24) or '')
    say(string.format('ENGAGE-STUCK: idle %.0fs while %s fights %s (%.1fy, id %s) -- fast assist calls %d, skipped %d, ' ..
        '/attack on %d, /assist %d, engage packet %d, last: %s; lead watch: %s; cursor %s; <bt> %s; quiet %.1fs; blocked %.0fs; main loop %.1fs ago%s. Trying /assist %s.',
        now - W.t0, P.follow, tostring(mob.name), d, tostring(mob.id), f and f.calls or 0, f and f.skips or 0,
        f and f.atk or 0, f and f.asst or 0, f and f.pk or 0, f and f.why or '-', tostring(P.lw_why or '-'),
        t and (tostring(t.name) .. ' ' .. tostring(t.id)) or 'none', bt and (tostring(bt.name) .. ' ' .. tostring(bt.id)) or 'none',
        q, blk, beat, (f and f.msg) and ('; game said "' .. f.msg .. '"') or '', P.follow))
    if pstat_event then pcall(pstat_event, 'stuck', short) end
    -- force the native path now
    local ff = fe_trace(mob.id)
    if ff.skips < 1 then ff.skips = 1 end
    P.fast_last[mob.id] = nil
    P.engaging = false
    fast_engage(mob.id, 'stuck ' .. math.floor(now - W.t0) .. 's', true)
end
-- v5.48: what the game answered to our /attack on (3s after it)
windower.register_event('incoming text', function(original)
    local f = P.fe
    if not f or not f.atk_at or os.clock() - f.atk_at > 3 or type(original) ~= 'string' then return end
    local low = original:lower()
    if low:find('cannot attack', 1, true) or low:find('unable to', 1, true) or low:find('out of range', 1, true)
       or low:find('too far', 1, true) or low:find('cannot see', 1, true) or low:find('you cannot', 1, true) then
        f.msg = original:gsub('%c', ''):gsub('^%s+', ''):sub(1, 60)
    end
end)

-- v5.47: true when mob_id is the leader's mob this aa fight member is joining
-- (seen within LEAD_MOB_KEEP s). autoattack.lua never blocks it (aa_block_mob /
-- set_target): 11-23 a 20s target give-up on it kept Myth idle ~20s a bat.
function aa_lead_mob_is(mob_id)
    if not mob_id or not P.follow_fight or not P.lead_mob or P.lead_mob ~= mob_id then return false end
    if os.clock() - (P.lead_mob_at or 0) > LEAD_MOB_KEEP then return false end
    return (aa_running and aa_running() and aa_get_mode and aa_get_mode() == 'assist') and true or false
end

windower.register_event('action', function(act)
    if not P.follow_fight or not act or not act.actor_id or not act.targets then return end
    if not aa_running() or aa_get_mode() ~= 'assist' then return end
    local p = me()
    if not p or (p.status ~= 0 and p.status ~= 1) then return end
    local cat = act.category
    if cat == 7 or cat == 8 or cat == 9 or cat == 12 then return end  -- "begins" (no hit yet)
    local t1 = act.targets[1]
    local tid = t1 and t1.id
    if not tid then return end
    if P.leader_id and act.actor_id == P.leader_id then
        local m = windower.ffxi.get_mob_by_id(tid)
        if m and m.spawn_type == 16 and (m.hpp or 0) > 0 then
            P.lead_mob, P.lead_mob_at = tid, os.clock()   -- v5.00
            if p.status == 0 then fast_engage(tid, 'leader on it') else corpse_switch(tid, 'leader on it') end
        end
        return
    end
    -- a mob acting on someone in the party (you, a player or a Trust)
    local am = windower.ffxi.get_mob_by_id(act.actor_id)
    if am and am.spawn_type == 16 then
        for _, mb in ipairs(members()) do
            if mb.id == tid then
                if am.claim_id == 0 or (function()
                        for _, x in ipairs(members()) do if x.id == am.claim_id then return true end end
                        return false end)() then
                    if p.status == 0 then fast_engage(act.actor_id, 'on ' .. mb.name)
                    else corpse_switch(act.actor_id, 'on ' .. mb.name) end   -- v5.00
                end
                return
            end
        end
    end
end)

windower.register_event('prerender', function()
    watch_party()
    stack_watch()   -- v4.75
    lead_mob_watch()   -- v5.00
    stuck_watch()      -- v5.48
    if P.stack or P.follow or P.running then move_tick() end
    if gsc_watch then pcall(gsc_watch) end   -- v4.90: job / weapon change -> profile
end)

-- v5.02: STACK AFTER EVERY KILL (Mark, 2026-11-21: "when in 'aa fight', do a
-- stack after every kill, because players are sometimes getting seperated").
-- aa fight members only; the leader keeps its fight spot (anchor).
local function fight_stack(why, maxd)
    if not P.follow_fight or not P.follow or P.stack or not aa_running() then return false end
    if mv and mv.active then return false end
    if i_lead() then return false end
    local p = me()
    if not p or p.status == 2 or p.status == 3 or p.status == 33 then return false end
    local d = dist_to_name(P.follow)
    if not d or d <= opt('stack_kill_min') or d > (maxd or opt('stack_kill_max')) then return false end
    P.restacks = (P.restacks or 0) + 1
    say(string.format('STACK: %s -- %.1fy from %s, stacking (%d this session).', why, d, P.follow, P.restacks))
    P.stack = {name = P.follow, deadline = os.clock() + opt('stack_timeout'), engaged_ok = true}
    return true
end
function aa_party_on_kill(dead_id)
    if opt('stack_after_kill') == false or not P.follow_fight then return end
    local t = windower.ffxi.get_mob_by_target('t')
    if not ((t and t.id == dead_id) or P.lead_mob == dead_id) then return end   -- not our fight
    local g = P.gen
    coroutine.schedule(function()   -- after the fast switch / hot switch has gone out
        if P.gen == g then fight_stack('after the kill') end
    end, 0.6)
end
function aa_party_on_oor(mob_id)
    if opt('stack_on_oor') == false or not P.follow_fight or not engaged() then return end
    local now = os.clock()
    if now - (P.oor_stack_at or -100) < 5 then return end
    if fight_stack('melee out of range', opt('restack_max')) then P.oor_stack_at = now end
end
-- v5.02: Level Sync wore off (11-21: EP per kill fell ~27% when the designee left)
windower.register_event('incoming text', function(original)
    if not original or not original:find('Level Sync effect wears off', 1, true) then return end
    if not has_players() then return end
    info_msg('LEVEL SYNC is off -- EP per kill is lower without it (11-21: about 470 -> 340). ' ..
             'Party leader: "aa sync <name>" syncs to that member (pick the lowest master level).')
end)

windower.register_event('unload', function() run_stop() end)

-- v4.60: just reloaded by "aa reload"? Answer whoever asked (within 2 minutes).
do
    local f = io.open(RELOAD_FILE, 'r')
    if f then
        local line = f:read('*l') or ''
        f:close()
        os.remove(RELOAD_FILE)
        local src, sender, t, from = line:match('^(%a+)\t([^\t]*)\t(%d+)\t?([^\t]*)')
        t = tonumber(t)
        -- v4.65: keep it for autoattack.lua's safe start (rollback if the rest fails to load)
        if src then AA_RELOAD_NOTE = {src = src, sender = sender, t = t, from = from} end
        if src and t and os.time() - t <= 120 then
            coroutine.schedule(function()
                for _ = 1, 30 do
                    if my_name() ~= '' then break end
                    coroutine.sleep(1)
                end
                if my_name() == '' then return end
                resume_after_reload()   -- v4.82
                local ctx = {src = src, sender = (sender ~= '' and sender) or nil}
                local now_v = tostring(_addon.version)
                if from and from ~= '' and from ~= now_v then   -- v4.62: after aa update
                    reply(ctx, my_name() .. ': updated and reloaded -- AutoAttack v' .. now_v .. ' (was v' .. from .. ')')
                else
                    reply(ctx, my_name() .. ': reloaded -- AutoAttack v' .. now_v)
                end
            end, 2)
        end
    end
end

-- v4.91: a teammate's "aa~g" party line is dropped as a packet (0x017), so the
-- game never prints it. v4.90 hid them with 'incoming text', which worked for
-- your own lines but not for teammates' (Mark, 11-20 23:52: Myth's and
-- Scrach's "aa~g p ..." showed in Shadow's chat). The line is handled here.
P.gsc_took = P.gsc_took or {}
windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x017 or not data or #data < 0x18 or data:byte(5) ~= 4 then return end   -- 4 = party
    local msg = data:sub(0x18):match('^[^%z]*') or ''
    if not msg:lower():find('^aa~g%s') then return end
    local name = data:sub(9, 0x17):match('^[%w]+')
    if name and is_friend(name) and member(name) and gsc_proto then
        local text = clean(msg)
        local now = os.clock()
        for k, t in pairs(P.gsc_took) do if now - t > 10 then P.gsc_took[k] = nil end end
        P.gsc_took[name .. '|' .. text] = now
        coroutine.schedule(function()
            local ok, err = pcall(gsc_proto, name, text)
            if not ok then dbg('aa~g from ' .. name .. ' failed: ' .. tostring(err)) end
        end, 0)
    end
    return true   -- never shown
end)

-- v4.90: keep the group skillchain's party lines ("aa~g ...") out of the chat
-- window -- 13 = a party member's line, 5 = your own (res/chat.lua)
windower.register_event('incoming text', function(original, modified, mode)
    if mode ~= 13 and mode ~= 5 then return end
    local s = clean(original)
    if s:find('^%([%a]+%)%s*[Aa][Aa]~[Gg]%s') then return true end
end)

return P
