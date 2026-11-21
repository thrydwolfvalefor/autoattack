# AutoAttack for Windower 4 (Final Fantasy XI)

AutoAttack is a Windower 4 Lua addon that runs your character's fight loop for you: it can assist your party's target or pull mobs on its own, then keeps your weapon skills, job abilities, spells, healing, food and EXP/CP rings going while you fight.

Current version: **4.98** (see the changelog block at the bottom of `autoattack.lua`).

> **Read this first.** Automating gameplay may be against the game's Terms of Service. You use this addon at your own risk. The authors are not responsible for warnings, suspensions or lost items.

---

## Contents

1. [Requirements](#requirements)
2. [Installation & updates](#installation--updates)
3. [Quick start](#quick-start)
4. [Commands](#commands)
5. [Party commands](#party-commands) (v4.44)
6. [Modes: ASSIST and PULL](#modes-assist-and-pull)
7. [What the loop does each tick](#what-the-loop-does-each-tick)
8. [Configuration](#configuration)
9. [Job configuration reference](#job-configuration-reference)
10. [Safety systems](#safety-systems)
11. [Debugging](#debugging)
12. [Settings file](#settings-file)
13. [Known limitations](#known-limitations)
14. [Troubleshooting](#troubleshooting)

---

## Requirements

| Requirement | Notes |
|---|---|
| Windower 4 | The addon uses the standard `resources`, `extdata` and `config` libraries that ship with Windower. |
| GearSwap (optional) | Not required. The ring logic assumes GearSwap, if you use it, restores your normal left ring afterwards. |

No other addons are needed. Targeting (since v3.95) and facing (since v3.84) are built in, so SetTarget and Facing are no longer required; leaving them loaded does no harm. To load AutoAttack automatically, add it to your `init.txt` or `scripts/init.txt`, for example:

```
lua load autoattack
alias aa lua c autoattack
```

---

## Installation & updates

### First install

1. Copy the `autoattack` folder into `Windower4\addons\`. The addon file must be `Windower4\addons\autoattack\autoattack.lua`. (The newest release is at https://github.com/thrydwolfvalefor/autoattack: **Code -> Download ZIP**.)
2. In game, run `//lua load autoattack`. The first time, it creates `aa_config.lua` from `aa_config_defaults.lua` and says so in chat.
3. Add the `alias aa lua c autoattack` line above to your Windower `init.txt` if you want to type `//aa`. Otherwise use the long form, `//lua c autoattack <command>`.
4. Open `aa_config.lua` in a text editor and review your settings (see [Configuration](#configuration)). Reload with `//lua r autoattack` after any change. The shipped job tables contain example trusts, spells, ability lists and ring names; change them to match your character before your first run.

### Updating (v4.64 or later)

| Command | What it does |
|---|---|
| `aa update check` / `aa version` | Replies with your version and the newest on GitHub, e.g. `v4.65 (GitHub: v4.66) -- "aa update" to install`. Installs nothing. |
| `aa update` | Downloads the newest release, checks it, backs up your current files to `backups\`, installs it and reloads. Replies `downloaded v<new> -- reloading...`, then `updated and reloaded -- AutoAttack v<new> (was v<old>)`. |
| `aa reload` | Only reloads the files already on the PC (after you edit `aa_config.lua`, for example). Downloads nothing. |
| `aa rollback` | Goes back to the version before the last `aa update` (v4.65+). |

* By `/tell` a command acts on that character; in party chat (`/p aa update`) on every AutoAttack in the party; add `all` (`aa update all`) to do the whole party from a `/tell` or your own `//aa`.
* **Your settings are safe.** `aa update` only replaces `autoattack.lua`, `aa_party.lua`, `aa_config_defaults.lua` and `README.md`. Your `aa_config.lua`, `data\` folder and logs are never touched. New settings use their defaults until you add them yourself: `//aa config new` lists them.
* **Just published?** GitHub can serve the old files for about 5 minutes after a new release. The update checks every file and stops with `try again in a few minutes` if it gets an old one -- nothing is changed.
* **If an update fails** (`update failed -- ...`), nothing was changed. If the new version installs but fails to start, AutoAttack puts the previous version back by itself (v4.65+) and says `v<new> failed to start (...) -- rolled back to v<old>`. Send the error to whoever maintains the release.
* Updates are refused while you're fighting.

---

## Quick start

**Follow a party leader and fight what they fight**

```
//aa assist
```

**Hunt on your own**

```
//aa pull
```

**Stop**

```
//aa stop
```

Only one loop may run at a time. Sending `assist` or `pull` while it is already running prints "Already running ... ignoring start command". Send `stop` first if you want to change modes.

---

## Commands

Commands are entered as `//aa <command>` (with the alias) or `//lua c autoattack <command>`.

| Command | What it does |
|---|---|
| `assist` (alias: `start`) | Starts ASSIST mode. Uses `/target <bt>` to take your party's battle target, faces it and attacks. Never pulls and never uses Provoke. |
| `pull` | Starts PULL mode. Scans for mobs, pulls them with your configured pull method, and fights. Also joins fights that trusts or party members start. |
| `stop` | Stops the loop and sends `/attack off`. |
| `move [off\|pull\|provoke\|melee\|target\|<yalms>]` | Sets `move_to_target` for this session (no argument = show it). See **move_to_target** below (v4.28). |
| `debug [0\|1\|2]` | Sets the debug level for this session: `0`/`off`, `1`/`release` (minimal), `2`/`dev` (everything, with timing). `debug file [on\|off]` turns the level-2 log file on or off. No argument shows the current setting. See [Debugging](#debugging) (v4.25). |
| `target [packet\|native]` | Shows or sets how the script puts the cursor on a mob (saved per character). `packet` (default) injects the 0x058 target-lock packet. `native` injects nothing: it turns toward the mob and sends the game's own `/targetbnpc` until the cursor is on that mob (`TARGET-NATIVE-OK` / `TARGET-NATIVE-MISS` in the log). Added in v4.07 to test the FFXiMain.dll crashes. In `packet` mode, if 3 packets in a row miss the same mob, the next try uses `/targetbnpc` for that mob once (`TARGET-FALLBACK` in the log), then goes back to packets (v4.30, `PACKET_MISS_LIMIT`, 0 = off). |
| `rings [reset]` | Shows how long each EXP/CP/Emporox ring waits before its next try. `reset` clears every ring wait so they are tried on the next combat tick (v4.08). Rings are no longer locked 2h after a use: the buff check holds them until Dedication/Commitment wears off, and a game refusal waits 10m, 20m, 40m, 80m, then 2h. Rings in `RING_REUSE_SECS` (Emperor Band = 15m, v4.09) wait exactly their reuse time and retry a refusal after 2m. |
| `ds [clear]` | Lists the mobs Dread Spikes tracking knows about (up or down, when it was last seen, clean hits, last news). `clear` turns Dread Spikes mode off and empties the list (v4.32). See [Dread Spikes mode](#dread-spikes-mode). |
| `ws [off\|on]` | Turns weapon skills off or back on for this session (no argument = show it). Not saved: reloading the addon turns them back on. While off, no WS fires on any job and abilities aren't held for a skillchain. `ws_mode` in aa_config.lua is untouched (v4.33). |
| `fullparty [on\|off\|fix]` | Full party rule (v4.54). No argument shows it and the Trust count. `off` lets PULL pull with a short party for this session, `on` turns it back on, `fix` forces the ghost-slot fix (`/retr all`, then call Trusts) on the next idle tick. See **Full party rule** under [Safety systems](#safety-systems). |
| `dumpinv` | Prints every item in your main inventory to the chat log. Use it when an item name in your config is not being recognised. |
| `pet` | Shows your pet's name, HP%, TP, status and target, and whether the job has a `pet` block. |

### Optional argument for `assist` and `pull`

Anything typed after the command is stored as the fight sub-command. Today it only has an effect in **PULL** mode:

| Argument | Effect |
|---|---|
| `n`, `s`, `e`, `w`, `ne`, `nw`, `se`, `sw`, `north`, `south`, `east`, `west`, `left`, `right`, `f` | Turns to that direction each time the pull scan finds no aggro, so the character stays pointed in that direction. |

Example: `//aa pull ne`

`spin` was removed in v3.96; `//aa pull spin` now just starts a normal pull.

Unknown commands are ignored silently.

### Things that stop the loop automatically

* Zoning (`zone change`; fixed in v4.18 -- before that the handler never fired). Start it again after you arrive.
* Logging out.
* Being defeated (v4.34). The log shows `YOU WERE DEFEATED by <mob>` and a red line is printed in chat.
* Player data unavailable for about 30 seconds in a row.

Changing job while the loop is idle is fine. The job table is re-read every time you send `assist` or `pull`.

---

## Party commands

*(v4.44, in `aa_party.lua` next to `autoattack.lua`.)* Your friends can control your AutoAttack with a `/tell` or in party chat. Every command starts with `aa`:

```
/tell Shadowhammer aa invite me sync shadow leader myth fight
/p aa fight
```

* Only characters in `party.friends` (aa_config.lua) are obeyed. Each friend has a `name` and a short `nick` that can be used in commands (`aa invite scrach`).
* Party-chat commands are only obeyed from friends who are in your party. `/tell` commands work from any friend.
* A party-chat command runs on **every** AutoAttack in the party, the sender included (`/p aa version` gets a reply from each of you), however you typed it: `/p aa ...`, the chat box in party mode, or a macro (v4.67). The one exception is `aa follow <your name>`: everyone else follows you and you stay put.
* Every friend runs AutoAttack too: the invite asks the other character's AutoAttack which zone they are in.
* Replies start with `[AA]`; AutoAttack-to-AutoAttack messages start with `aa~`. Neither is ever taken as a command.
* Every command can also be typed on your own character as `//aa <command>`. `//aa party` shows your friends, the party settings and what the party code is doing.

| Command | What it does |
|---|---|
| `invite me\|<name> [sync <name>] [leader <name>] [fight]` | Invites the sender (`me`) or a named friend. The sender and the invitee must be in your zone (any distance). If you're not the party leader you reply "send this to <leader>". If the invitee is in a Trust-only party, their AutoAttack drops it (unless they are fighting: then they tell the requester they can't). Then: finish the mobs fighting the party (no new pulls; mobs that aren't fighting you don't count), drop Trusts (`/retr all`), invite, Level Sync to `sync`, hand the leader to `leader`. A new leader calls Trusts right away and, with `fight` (or if you were fighting), starts the fight. If you stay leader: wait `trust_wait` (120s) from the Trust drop, call Trusts, then `/p aa fight` if you were fighting or `fight` was sent. In party chat only the leader acts on it. |
| `fight` | The party leader (or a solo character) waits up to `stack_wait` (5s) for party members to stack on it, then pulls. A party member runs onto the leader's exact X/Y (within `stack_precision`, 0.3y, v4.47), then assists the leader's pulls and follows the leader between fights. `/p aa fight` starts everyone. |
| `stop` | Finishes the current fight (no new pulls), then stops. (Typed `//aa stop` still stops at once.) |
| `stack` | Every party member runs onto the **party leader's** exact X/Y and stops directly on top, within `stack_precision` (0.3y), whoever sends it (v4.48; a name after it is ignored). The leader stays put. |
| `follow [name]` / `unfollow` | Follows the named friend (default: the party leader, or the sender) at `follow_range`, or stops following. Paused while you're engaged. |
| `cancel` | Stops an invite (or Trust call) that is running. |
| `disband` | The leader drops its Trusts first, then breaks the party up (checks it emptied, retries up to 3 times); a member leaves; a Trust-only party drops its Trusts; a leftover party of just yourself is broken up so you can take an invite. Refused while fighting. |
| `leave` | Leaves the party. Refused while fighting. |
| `leader <name>` | Passes the party leader (leader only). |
| `sync <name>` / `unsync` | Level Sync to a party member, or off (leader only). |
| `trusts [group]` | Calls Trusts until the party is full; `group` picks the job's trust group for this session (leader only). |
| `retr` | Drops all Trusts (leader only). |
| `retrust` | Drops the Trusts and calls them again (leader only, v4.45). Like an invite: finishes the mobs fighting the party first (no new pulls), stops, `/retr all`, waits `trust_wait` from the drop, calls Trusts until the party is full, then goes back to PULL / ASSIST if it was running. Cancelled if still fighting after `finish_timeout`. |
| `rest` | Stops AutoAttack and following, `/heal`s until HP and MP are full, then stands up. |
| `mount [name]` / `dismount` | Stops AutoAttack and mounts (`party.mount`, default Raptor) / dismounts. |
| `sneak` / `invis` / `sneak invis` | Every character that doesn't already have the buff puts it up: its own Sneak / Invisible spell (main or sub job, MP and recast checked), else Spectral Jig (DNC main or sub, level 25+, gives both), else Silent Oil / Prism Powder. Sneak always goes first. Then it answers in the same channel it was asked in (`/p` or `/t`) with the time left, e.g. `[AA] Shadowhammer: Sneak 4:05, Invisible 4:50`, or what it couldn't do. Refused while fighting, mounted or resting (v4.51). |
| `warp` (or `299`) | **In party chat:** everyone stops AutoAttack and following. If anyone in the party can cast Warp II (they say `[AA] <name>: I can Warp II.`), that mage casts Warp II on every other player in the zone, then warps itself; the others wait up to `warp_wait` (90s), then use their ring. With no Warp II mage, every character equips its Warp Ring on the **right ring** (ring2), waits `warp_ring_delay` (11s) and uses it; the ring that was there goes back on after the warp, or right away if the Warp Ring doesn't go off (v4.53). **By /tell or typed:** just that character (its own Warp spell, else the ring). Refused while fighting (v4.52). |
| `pass` | Passes every item in the treasure pool. |
| `lot` | Lots on every item in the treasure pool (v4.45). |
| `status` | Replies with job, AutoAttack mode, HP/MP/TP, leader, and what the party code is doing. |
| `ping` | Replies with name, version, job, mode and memory, e.g. `Scracheebrat v4.65 \| WAR99/SAM \| PULL \| 4.1 MB` (v4.65). |
| `version` (or `update check`) | Replies with this version and the newest on GitHub; installs nothing (v4.65). |
| `rollback [all]` | Goes back to the version before the last `aa update` (v4.65). Refused while fighting. |
| `help` | Replies with the command list. |
| `reload [all]` (or `rl`) | Reloads AutoAttack (`//lua r autoattack`) (v4.60). By `/tell`: just that character. In party chat: every AutoAttack in the party. `reload all` (typed or by `/tell`): says `/p aa reload`, so the whole party reloads, including the sender. After the reload each one answers in the same channel with `[AA] <name>: reloaded -- AutoAttack v<version>`. The reload stops AutoAttack, so send `fight` / `pull` / `assist` again afterwards. |
| `update [all\|force]` | Downloads the newest release from GitHub (`thrydwolfvalefor/autoattack`, or `party.update_url` in aa_config.lua), checks every file, backs the current files up to `backups\`, installs the new ones, replies `downloaded v<new> -- reloading...`, reloads, then replies `updated and reloaded -- AutoAttack v<new> (was v<old>)` (v4.62). Only `autoattack.lua`, `aa_party.lua`, `aa_config_defaults.lua` and `README.md` are replaced; your `aa_config.lua`, `data\` and logs are never touched. By `/tell`: that character; in party chat: every AutoAttack in the party; `update all`: the whole party. Already current: `already on v...`. `force` re-installs or allows an older version. Refused while fighting. `reload` only reloads the files already on the PC. Needs v4.64 or later (the v4.62 / v4.63 updater was broken). |
| `pull [dir]`, `assist`, `ws on\|off`, `move <mode>`, `ds [clear]`, `gsc on\|off\|auto\|?` | Same as the `//aa` command. `pull` / `assist` switch the running mode if AutoAttack is already on. Each one answers the sender (v4.69): `ws` / `move` / `ds` send back what the command printed (e.g. `[AA] Scracheebrat: Weapon skills OFF (until aa ws on or the addon is reloaded).`, at most 5 lines); `pull` / `assist` say `switched to PULL mode (was ASSIST)`, `already in PULL mode`, `started PULL mode` or `couldn't start PULL mode`. A `/tell` is answered by tell; a party-chat command is answered in party by everyone except the character that sent it. `ws off` / `move` last until `ws on` / another `move` or a reload. |

**Settings** (`party = {...}` in aa_config.lua): `enabled`, `friends`, `party_range` (1), `stack_precision` (0.3), `follow_range` (1), `stack_timeout` (30s), `stack_wait` (5s), `trust_wait` (120s), `finish_timeout` (300s: an invite or retrust is cancelled if the party is still fighting after this), `reply_timeout` (8s), `auto_accept` (true: invites from friends are accepted), `mount` ('Raptor'), `warp_ring` ('Warp Ring'), `warp_ring_delay` (11s), `warp_claim_wait` (3s), `warp_wait` (90s), `retr_command` ('/retr all').

**Fast assist (v4.50):** a member in `aa fight` doesn't wait for ASSIST mode to find the party's battle target. The moment the leader acts on a mob (Provoke, ranged pull, melee, WS, spell, JA), or a mob acts on anyone in the party (players or Trusts), the idle member targets it and attacks at once (`FAST-ASSIST >>>> <mob>` in the log).

**Level Sync** has no text command in FFXI (it's in the party menu), so AutoAttack sends the party menu's own Level Sync request (packet 0x077).

**Trusts with other players:** `max_trusts` counts Trusts only, and AutoAttack never fills the party past 6 (2 players = at most 4 Trusts).

**No Trusts for 120s after a player joins** (game rule). From v4.46 AutoAttack counts `trust_wait` from the moment a player joins the party (its own invite or one you typed), doesn't call Trusts until then (`TRUSTS: a player joined the party -- no Trusts for Ns more.` in the log), and `aa fight` waits it out and calls Trusts before the first pull. A character that is handed the leader isn't held by the window.

---

## Modes: ASSIST and PULL

### ASSIST

* Targets your party's battle target (`<bt>`), turns to face it, and uses `/attack on`.
* Keeps facing every 3 seconds during the fight, and every second for 5 seconds after a new target.
* Will not use Provoke, even if it is in the ability list.
* Does not scan for mobs and does not rescue you from a purple (other-party-claimed) mob.
* (v4.42) Only sends `/target <bt>` when the battle target is a live, targetable mob, the cursor isn't already on it, and no kill / treasure-casket quiet window is open. It never targets a dying or despawning mob, and it checks again that the mob is still alive right before `/attack on`. Skips are logged once per reason as `ASSIST-BT-SKIP (...)` / `ASSIST-ENGAGE-SKIP` at debug level 2.

### PULL

1. Looks for priority mobs: any mob targeting you or one of your trusts or party members, any mob your party has already claimed, and any mob already inside your melee range. The closest of these is targeted.
2. If none, picks the nearest allowed mob within pull range. Mobs that are already part of your fight are preferred over fresh ones. If nothing is in range, it waits (no game-side `/targetbnpc`, which ignores the blacklist).
3. Turns to face it, sends `/attack on`, and fires the pull.
4. Watches the mob while it walks in, re-facing every second for the first 5 seconds.
5. Fights it using the combat chain below.

**Pull methods** (`pull.method`, or `master_pull_method.type` to override every job):

| Method | Command sent | Pull range |
|---|---|---|
| `ranged_attack` | `/ra <t>` | 24.9 yalms |
| `provoke` | `/ja provoke <t>` | 17.8 yalms |
| `dia` | `/ma dia <t>` | 20.0 yalms |

If you are WAR main or sub and Provoke is ready and the mob is within 17.8 yalms, Provoke is used as the pull instead of your configured method. If Provoke is ready but the mob is farther than 17.8 yalms (still inside your pull range), the pull is held for up to 6 seconds (`provoke_hold_state.wait`) so the mob can come into Provoke range; after that your configured method fires. If Provoke is on recast, the configured method fires right away. Your pull method is never used on a mob that is already in melee range (3 yalms + the mob's size). Since v4.40 Provoke is saved for pulling: it is used for pulls, re-pulls, and right after a hot-switch (the new mob is Provoked as soon as you switch to it, if Provoke is ready and the mob is within 17.8 yalms; `HOT_SWITCH_PROVOKE`, `HOT-SWITCH-PROVOKE` in the log). If your weapon skill killed the last mob, that Provoke waits until 3.5 seconds after the weapon skill (`HOT_SWITCH_PROVOKE_WS_GAP`), because the game drops a Provoke sent during the weapon skill's animation (v4.56). A Provoke entry in your job's `abilities` still fires as configured. (v4.41) After a hot-switch the puller also does nothing else (no weapon skills, job abilities, magic, rings or food, pet commands, heals, PullNext, closer-target switch or backup pull) until one of its own melee rounds lands on the new mob, so Trusts and party members engage it (`HOT_SWITCH_HOLD`, `HOT-SWITCH-HOLD` in the log). The hold ends early if the target changes or dies, after 15 seconds with no melee round (`HOT_SWITCH_HOLD_MAX`), or if your HP drops below 40% (`HOT_SWITCH_HOLD_HPP`). The v4.37/v4.38 melee-range Provoke (`MELEE_PROVOKE_NO_HIT`, Provoke on a mob in melee range you are not hitting) is now off by default; set it to `true` in autoattack.lua to bring it back. If you have not hit it for 4 seconds the script also re-faces it, and after 15 seconds with no contact (`MELEE_STALL_LIMIT`) it treats the mob as unreachable, blacklists it and disengages. The one exception is when the game itself says the mob is out of range.

**PullNext_OnLowHP.** When enabled for a job, once your current target is below `LowHPPrcnt` percent HP the script pulls a second mob and switches back to the first one. `PullNextMax` is the total number of mobs allowed in the fight, including the current one. There is a 5 second cooldown between these pulls.

---

## What the loop does each tick

The loop wakes about once a second. Right after your target dies (v4.19, `FAST_RETARGET = true`) it ticks faster for up to 4 seconds: it wakes the moment the 1-second post-kill targeting quiet window ends, scans and targets the next mob, and runs the pull 0.1s after you engage instead of a second later. The WS animation wait also ends early when the WS was the killing blow. The quiet window itself is never shortened (it guards against the client crash seen when targeting while a corpse/casket despawns). Set `FAST_RETARGET = false` near the top of the targeting section of `autoattack.lua` to go back to the v4.18 timing.

**Hot switch (v4.20, PULL mode).** When your target dies while you're engaged, the addon immediately switches to the nearest *live* mob within melee reach (3.0 + mob size + `HOT_SWITCH_EXTRA`, default 1.0y) without disengaging, so your weapon stays out. Mobs already in your fight (on you, on a party member, or claimed by your party) are preferred; a fresh mob is used only when a new pull would be allowed (HP not below `LOW_HP_NO_PULL_PCT`, nothing else on you). It moves the cursor to the new mob and sends the game's own *Switch target* action. Nothing is sent at the corpse. If no mob is close enough, or the switch doesn't take (`HOT-SWITCH-MISS` in the log), the normal re-target runs. Set `HOT_SWITCH = false` to turn it off. It is skipped in `//aa target native`.
Since v4.21 the reach is your pull distance (`HOT_SWITCH_RANGE = 'pull'`, the default): Provoke 17.8y, ranged 24.9y, Dia 20y. You stay engaged on the farther mob and the engaged pull (Provoke / ranged / Dia) brings it in, instead of sheathing and drawing again (which often hits "You must wait longer"). `HOT_SWITCH_RANGE = 'melee'` limits it to mobs within melee reach.

**Closer switch (v4.24, PULL mode).** While engaged, if you are not hitting your current target (it's still out at range, or held for Provoke), the addon switches without disengaging to a closer mob that is in your fight: hitting you or a Trust, claimed by your party, or targeting one of you, and at least 2y closer. If the current target hasn't been pulled yet, it also switches to a fresh mob at least 5y closer (when a new pull is allowed). Both must be within pull range; there is a 3s cooldown between switches. After the kill the hot switch picks the next closest. Log: `CLOSER-SWITCH >>>>`. Set `CLOSER_SWITCH = false` to turn it off.

**move_to_target (v4.28, PULL mode, `'off'` by default; replaces v4.22's `move_in_range`).** Set it in `aa_config.lua`, or `//aa move <value>` for this session:

| Value | What happens |
|---|---|
| `'off'` | Never runs. Pulls only mobs already in pull range. |
| `'pull'` | Runs until the mob is 1.5y inside pull range (/ra 24.9y, Provoke 17.8y, Dia 20y), then pulls. |
| `'provoke'` | Like `'pull'`, but when Provoke is ready and the mob isn't already coming, keeps running to 16.3y and Provokes. With Provoke down (or no /WAR) it pulls with /ra from pull range. |
| `'melee'` | Runs into melee reach (3y + the mob's size) and starts swinging. Provokes on the way if it is ready and in range. |
| `'target'` | Runs right up to the mob (`MOVE_TARGET_STOP`, 1.5y), then swings. |
| a number, e.g. `12` | Runs until the mob is that many yalms away, Provokes on the way, then the normal pull / melee logic. |

How the running works (all modes except `'off'`): when your target is beyond the reach of both pull methods (past your pull distance), the addon runs toward it until it is 1.5y inside pull range, then pulls as usual. When nothing is in pull range at all it targets the nearest valid mob out to `MOVE_SCAN_DIST` (50y, about the farthest the game client tracks mobs). It runs in 2-second bursts so trusts, heals and safety checks keep working. Terrain handling: it checks your X/Y/Z every 0.5s; if you barely moved (rock, wall, slope) or stopped getting closer, it detours left or right (50° first, wider on the same obstacle, preferring the side that worked last), backs up and tries the other side if that fails, and gives up after 8 stalls, 30 seconds, or a large height gap (cliff) -- the mob is then blacklisted like other unreachable mobs. It stops if the mob dies or is claimed by someone else, your HP drops below `LOW_HP_NO_PULL_PCT`, or you `//aa stop`. Log lines: `MOVE`, `MOVE-SCAN`, `MOVE-STUCK`, `MOVE-BACKUP`, `MOVE-OK`, `MOVE-GIVEUP`.

**Releases** are built with `python tools/make_release.py`, which always ships `move_to_target = 'off'`, the mob whitelist commented out, and `master_pull_method` with `type = ''` and the other fields `nil` (no overrides).

**Not engaged (status 0)**
1. Calls trusts (at most every 10 seconds, see [Trusts](#trusts)).
2. If `heal_buff_outside_battle` is true, heals the party and casts buff-type magic between fights.
3. ASSIST: takes `<bt>` and engages. PULL: runs the scan and pull described above.

**Engaged (status 1)**
1. ASSIST facing and target refresh.
2. Purple-mob check (PULL mode).
3. Party healing (`cure` list).
4. PULL mode: re-pull or Provoke if the mob is out of melee range.
5. PullNext_OnLowHP if enabled.
6. The combat chain, in this order: Provoke for hate (PULL only), magic burst, job abilities, weapon skill, rings, food, magic, weakness magic.
7. Facing (every 3 seconds).

While a skillchain lockout is active (see [Skillchain lockout](#skillchain-lockout)) the chain runs only weapon skills.

---

## Configuration

### Config files (v4.29)

The settings you change most live in their own file, so you never have to dig through `autoattack.lua`:

| File | What it is |
|---|---|
| `aa_config.lua` | **Your settings.** `mob_whitelist`, `mob_blacklist`, `domain_invasion`, `elemental_farming`, `master_pull_method`, `ws_mode`, `heal_buff_outside_battle`, `move_to_target`, and the whole `job_config` table (trusts, pull, abilities, magic, weapon skills, rings, food for every job). Edit this one. |
| `aa_knowledge.lua` | **Shipped group skillchain knowledge** (v4.90): learned WS, skillchain and magic burst damage for the group, merged from everyone's learning when a release is built. Read only; `aa update` replaces it. |
| `data/aa_learned_<Character>.lua` | **This character's learning** (v4.90). Written by AutoAttack as it plays (and from what teammates send); never shipped and never replaced by `aa update`. |
| `aa_config_defaults.lua` | **Shipped safe defaults.** Don't edit it. Whitelist empty, Domain Invasion / elemental farming off, standard blacklist, no `master_pull_method` overrides, every job's `PullNext_OnLowHP = false`, `ws_mode` `"Normal"` with lockout `"true"`, `heal_buff_outside_battle = false`, `move_to_target = 'off'`. |

* If `aa_config.lua` is missing, AutoAttack copies the defaults file to `aa_config.lua` on load. To start over, delete `aa_config.lua` and reload.
* If a setting is missing from `aa_config.lua`, the default is used and chat says which one.
* If `aa_config.lua` has a typo / Lua error, chat shows the error and the whole defaults file is used until you fix it.
* Releases ship only `aa_config_defaults.lua`, so updating AutoAttack never overwrites your `aa_config.lua`.
* After editing, reload: `//lua r autoattack`.

Debug options (`debug_level`, `DEBUG_LOG_FILE`, `cmd_mode`, ...) and the advanced tuning values stay in `autoattack.lua`.

Booleans in the first few blocks of `aa_config.lua` are written as the **strings** `"true"` / `"false"`.

### Mob filters

```lua
local domain_invasion    = {toggle = "false", moblist = { ... }}
local elemental_farming  = {toggle = "false", moblist = { ... }}
local mob_whitelist      = { "Death Jacket" }
local mob_blacklist      = { "Om'xzomit", ... }
```

* If `domain_invasion.toggle` or `elemental_farming.toggle` is `"true"`, their `moblist` entries **replace** `mob_whitelist`. Both may be on at once and their lists are merged.
* Otherwise `mob_whitelist` is used.
* **An empty whitelist means "pull anything".**
* Names are matched case-insensitively and must match the in-game name exactly.
* `mob_blacklist` is never pulled or engaged, whatever the whitelist says.
* When `domain_invasion.toggle` is `"true"`, trusts use each job's `dragons` list instead of the job's normal trust group.
* `purple_escape_exclusions` (further down the file) lists mobs that should not trigger the "claimed by another party" disengage, such as Domain Invasion mobs and open-world NMs that several parties fight at once.

### Global options

| Variable | Default | Meaning |
|---|---|---|
| `master_pull_method` | `{type = '', PullNext_OnLowHP = nil, LowHPPrcnt = nil, PullNextMax = nil}` | Overrides every job's `pull` table field by field (v4.23). `type` (`'ranged_attack'`, `'provoke'` or `'dia'`) overrides the pull method when not empty; `PullNext_OnLowHP`, `LowHPPrcnt` and `PullNextMax` each override when not `nil` (`false` counts as a value). Leave a field `nil` (or `type = ''`) to use the job's own setting. |
| `ws_mode.type` | `"Normal"` | Which weapon-skill sub-list to use: `"Normal"`, `"AoE"`, `"Odin"`, `"Savage_Blade"`, etc. Only sub-lists that exist in the job's `ws_list` can be chosen. `"Off"` turns weapon skills off for every job (v4.31). |
| `dread_spikes` | `{enabled = true, max_duration = 180, clear_hits = 4, forget_after = 3600, melee_rounds = 1, melee_wait = 8, cast_range = 20, lock_gearswap = true}` | Dread Spikes tracking and mode (v4.32). See [Dread Spikes mode](#dread-spikes-mode). |
| `ws_mode.lockout` | `"true"` | Set to `"false"` to disable the skillchain lockout everywhere. |
| `heal_buff_outside_battle` | `false` | Heal and buff between fights (for mage and support jobs). |
| `debug_level` | `1` | `0` = off, `1` = RELEASE (minimal, high-level `[AA]` lines), `2` = DEV (every decision, ms timestamps, TIMING lines, file log). `//aa debug 0\|1\|2` changes it in game. |
| `DEBUG_LOG_FILE` | `false` | At level 2, also writes every line (and every `[CMD]`) to `data\logs\aa_<Character>_<date>.log`. |
| `DEBUG_SLOW_TICK` / `DEBUG_FRAME_STALL` | `3.0` / `0.5` | Level 2 thresholds (seconds) for the TIMING lines. |
| `cmd_mode` | `false` | Prints a `[CMD]` line for every command the script sends. Useful when the game reports "Invalid argument". |
| `ws_blocked_debug` | `false` | Prints "WS BLOCKED: needs X TP" messages. |

### Trusts

Under `job_config[JOB].trusts`:

```lua
trusts = {
    trust_group = 'mlt',   -- which list below to use
    enabled = true,
    max_trusts = 5,        -- lower this if you have fewer trusts unlocked
    mlt = {
        {cast='Koru-Moru',    mob='Koru-Moru'},
        {cast='Shantotto II', mob='Shantotto'},
    },
}
```

* `cast` is the exact spell name you cast (for example `Apururu (UC)`).
* `mob` is the name that appears in your party list once the trust is summoned (for example `Apururu`). It is used to tell whether the trust is already out.
* Trusts are only called when you are the party leader, or when there are no other players in the party, and never while engaged.
* Zone limits are applied automatically: 0 trusts in towns and most instanced areas, 3 in Limbo and Dynamis. Otherwise `max_trusts` applies.
* If a trust still isn't in the party after 3 calls in a row (`TRUST_MAX_FAILS`), it is skipped for 10 minutes (`TRUST_FAIL_SKIP`) so the loop doesn't keep re-casting it (v4.34). Zoning resets this.
* Every trust in the list must be one you have unlocked. The script does not check whether you own the spell.

---

## Job configuration reference

Jobs currently configured: **WAR, THF, SAM, RDM, BLM, WHM, NIN, DRK, COR, DRG**, plus starter blocks for **BST, SMN, PUP** (edit their pets, Ready moves, pacts and maneuvers before use). Each entry under `job_config` (in `aa_config.lua`) can contain the sections below. To add a job, copy an existing entry, rename the key to the three-letter job code, and edit the lists.

> If you play a job that has no entry, the script currently falls back to the **WAR** table and prints "No config found for XXX. Defaulting to WAR". Add an entry for your job before using the addon on it.

### `pull`

```lua
pull = {method = 'ranged_attack', PullNext_OnLowHP = false, LowHPPrcnt = 10, PullNextMax = 2}
```

### `backup_pull`

A backup for when the main pull can't fire right now. Example: you've targeted a mob and drawn your weapons, it is standing just outside melee range, and Provoke is on recast. The first ready entry fires at the mob to tag it and pull it in.

```lua
backup_pull = {
    {name='Jump',      max_dist=9.5},
    {name='High Jump', max_dist=11.5},
},
```

| Field | Meaning |
|---|---|
| `name` | A job ability, pet command or spell, or `'Ranged Attack'` for `/ra <t>`. |
| `max_dist` | Only when you are within this many yalms of the mob's edge (its distance minus its size). Default 4.5. |
| `pet`, `hpp_above`, ... | Same as in `abilities`. |

The main pull counts as "not ready" when Provoke is on recast or you have no /WAR (`provoke`), when you have no bow, gun or throwing weapon with ammo (`ranged_attack`), or when Dia is on recast or you're short on MP (`dia`). A backup pull never fires in melee range, in ASSIST mode, or within 6 seconds of the last pull (`PULL_APPROACH_WAIT`). It skips anything you can't use yet: ability not learned or on recast, spell below your job level or out of MP, silenced, amnesia, or no ninja tools. The log shows `BACKUP-PULL (engaged): X at 6.1y -- main pull not ready, using Jump.`, and every 5 seconds it lists why nothing fired.

Default lists: DRG Jump, Spirit Jump, Soul Jump, High Jump (Super Jump is left out because it wipes your hate). SAM and COR use Ranged Attack. RDM uses Dia II, Bio, Stone. BLM uses Bio, Stone. WHM uses Dia II, Banish. NIN uses Kurayami: Ichi, Hojo: Ichi, Jubaku: Ichi. DRK uses Bio, Stone, Drain. WAR and THF have none, because `/ra` is already their pull. BST, SMN and PUP have commented examples only, because the pet already attacks when you engage.

### `abilities`

A list of job abilities, tried **in order**. The first one whose conditions are met fires; the loop then waits for the animation.

```lua
{name='Berserk', target='<me>', tp=0, min_time=250, buff_any={56,58,64}}
```

| Field | Meaning |
|---|---|
| `name` | Exact ability name. |
| `target` | `'<me>'`, `'<t>'`, or a player name. |
| `tp` | Minimum TP needed before it is used (for example Haste Samba at 350). |
| `min_time` | Minimum seconds between uses. |
| `uses_per_mob` | Maximum uses per target. The counter resets on every new target. |
| `buff_id` | Skip while this buff is active. |
| `buff_any` | Skip while **any** buff in the list is active. |
| `mp_threshold`, `hp_threshold` | Only for `Convert`: use it when MP% is at or below `mp_threshold` and HP% is at or above `hp_threshold`. Afterwards it casts Cure IV on you. |
| `tp_max` | Only when your TP is at or below this (for example Jumps at 999, so they never sit on a weapon skill). |
| `hpp_above`, `hpp_below`, `mpp_above` | Only when your HP% / MP% is within these limits. |
| `max_recast` | For charge abilities (Ready, Maneuvers): usable while the recast timer is this many seconds or less, instead of only at 0. |
| `buff_stack` | With `buff_id`: skip only once this many copies of the buff are up (PUP maneuvers). |
| `need_buff` | Only usable **while** this buff is up (for example Cooldown while Overloaded). |
| `max_dist` | For abilities aimed at the mob (`target='<t>'`): only fire when you are within this many yalms of the mob's edge (its distance minus its size, so big mobs work too). The DRG config uses the published ranges: Jump and Spirit Jump 9.5, High Jump and Soul Jump 11.5, Super Jump 12.5, Dragon Breaker 12, Angon 10 (Smiting Breath 10 is a guess; no range is published). Jumps without it default to 4.5. When it holds an ability the log says `RANGE: holding Jump -- 6.2y from the mob's edge, max_dist 4.5y.` |
| `pet` | `true`: only when your pet is out. `false`: only when no pet is out. |
| `pet_name` | Only when your pet's name contains this text (keeps Blood Pacts on the right avatar). |
| `pet_hpp_below`, `pet_hpp_above` | Pet HP% limits (Spirit Link, Reward, Repair). |
| `pet_tp_min` | Only when your pet has at least this much TP. |
| `pet_engaged` | `true`: only while the pet is fighting. `false`: only while it is idle. |

Abilities are skipped while you have Amnesia. Provoke entries are ignored in ASSIST mode.

Abilities aimed at the mob (`target='<t>'`, such as Jump or Dragon Breaker) wait until you have faced the mob and landed your first melee round on it, so your Trusts engage first. Until then the loop turns you toward the mob every 2 seconds. After 12 seconds with no swing they are allowed anyway. Provoke and emergency (`hpp_below`) entries are not held back.

Pet commands, Ready moves and Blood Pacts go in `abilities` like any other ability. They are sent with `/pet` automatically.

### `pet`

Used by pet jobs (DRG, BST, SMN, PUP). Each tick the addon re-summons a missing pet, sends it at your target when you engage or switch targets, and can call it back when you are not engaged.

```lua
pet = {enabled = true,
    summon = {'Call Beast', 'Bestial Loyalty'}, -- tried in order; spells (avatars) are cast with /ma
    summon_idle = true,          -- also summon between fights, not only while engaged
    summon_block_buffs = {126},  -- don't summon while any of these buffs are up
    engage = 'Fight',            -- 'Fight' (BST), 'Assault' (SMN), 'Deploy' (PUP), nil for a wyvern
    retreat = 'Heel',            -- 'Heel' / 'Retreat' / 'Retrieve' when you're not engaged; nil to leave it
}
```

Optional timers: `summon_retry` (default 6 seconds), `engage_retry` and `retreat_retry` (default 4 seconds). Pet TP comes from the game's pet status packet, so `pet_tp_min` and `//aa pet` work without other addons.


### `magic`

A list of spells, tried in order. Set `enabled = false` to turn the whole list off. `fast_cast_pct` is your Fast Cast total and is used to estimate how long to wait after each cast.

| Field | Meaning |
|---|---|
| `name` | Exact spell name. |
| `type` | `'buff'`, `'buff_party'`, `'buff_party_mages'`, `'debuff'`, `'damage'` or `'heal'`. |
| `target` | `'<me>'`, `'<t>'` or a player name. Not needed for the party types. |
| `buff_id`, `buff_any` | Buff IDs that show the spell is already active. |
| `min_time` | Minimum seconds between casts on the same target. |
| `uses_per_mob` | Maximum casts per target. |
| `max_dist` | Maximum distance, default 21. Checked for debuffs and nukes. |
| `buff_duration` | For party buffs. Recast after this many seconds even if the buff still looks active. This covers missed wear-off packets and trusts, whose buffs cannot be read. |
| `targets` | With `type='buff'`: a list of names; the first one missing the buff is chosen. |
| `only_names`, `skip_names` | With `buff_party` types: whitelist or blacklist of names. |
| `min_mp_pool` | With `buff_party_mages`: estimated max-MP threshold, default 400. |
| `cast_time` | Overrides the computed wait after casting. |

Behaviour worth knowing:

* Damage spells are skipped when MP is under 30%.
* Debuff and damage spells turn you toward the target first.
* Magic stops while you are Silenced.
* Ninjutsu checks your tool supply. On NIN main it will unpack a universal toolbag; on /NIN you must carry the raw tools.
* After a party buff the script waits about 5 seconds and checks the buff landed. If not, it retries in about 30 seconds.

### `cure`

```lua
cure = {enabled = true,
    {name='Cure IV',  hpp_threshold=30, min_mp=88},
    {name='Cure III', hpp_threshold=50, min_mp=46},
}
```

Spells are tried in order. The first one whose MP requirement is met and whose recast is ready is cast on the lowest-HP party member, if that member is under `hpp_threshold`. With `heal_buff_outside_battle` on, the threshold between fights is 100%.

### `weakness_spells`

Casts an element the target is weak to, and (if `mb_enabled = true`) tries to magic burst a skillchain.

```lua
weakness_spells = {enabled = true, mb_enabled = false,
    ice = { {name='Blizzard IV', min_time=10, uses_per_mob=999}, ... },
    fire = { ... }, lightning = { ... }, earth = { ... },
    wind = { ... }, water = { ... }, light = { ... }, dark = { ... },
}
```

The target's weakness comes from the `mob_weaknesses` table near the top of the file, which matches on **part of the mob name**. Edit that table for the mobs you fight. A 6 second lockout applies between weakness casts.

### `ws_list`

Weapon skills are grouped into named lists. `ws_mode.type` chooses which one is active.

```lua
ws_list = {enabled = true,
    ["Normal"] = {
        {name='Full Break',   uses=1, min_time=3, SA=0, LockOut=1, min_tp=1000},
        {name='Upheaval',     uses=1, min_time=3, SA=0, LockOut=1, min_tp=1000},
        {name="Ukko's Fury",  uses=1, min_time=3, SA=0, LockOut=1, min_tp=1000},
        {name='Upheaval',     uses=1, min_time=3, SA=0, LockOut=0, min_tp=1000},
    },
}
```

| Field | Meaning |
|---|---|
| `name` | Exact weapon-skill name. |
| `uses` | How many times to use it before moving to the next entry. Required. |
| `min_time` | Seconds that must pass since the **previous** weapon skill. Required. |
| `min_tp` | Minimum TP for this entry (never below 1000). |
| `SA` | `1` = use Sneak Attack first when it is ready. |
| `LockOut` | `1` = starts a skillchain lockout. `0` = this is the closing skill; it ends the lockout. Leave out to change nothing. |

The list is walked in order and wraps back to the first entry. The position resets on every new target and when a fight ends.

### Stacking watch and fight anchor (v4.75)

* `aa fight` on the leader saves its spot. In PULL mode the leader runs back to it whenever it is more than 1 yalm away: between mobs always, while engaged only if the mob can still be hit from the spot.
* Party members in `aa fight` watch their distance to the leader. Engaged and more than `party_range` + `restack_slack` (2 yalms) away for `restack_delay` (2 s), but within `restack_max` (10 yalms): they re-stack right away, mid-fight, and face the mob again. Farther than that: logged once, stacked between fights. `aa fight` also stacks a member who is already fighting. `stack_watch = false` turns it off.
* All of the above is `aa fight` only. `aa assist` / `aa pull` on their own (typed, by tell or party chat) end fight mode: no following, re-stacking or fight spot -- the player stays where they are.
* v4.78: the leader goes back to the fight spot mid-fight too (the mob follows), and logs a POSITION line every minute ("NOT STACKED" in chat when a player is more than 4y off). Members more than `restack_max` away re-stack after `restack_far_secs` (20s); `aa stack` works while fighting.
* Stepping in to a mob is an emergency only (`STEP_IN_EMERGENCY`): on trouble the leader Provokes, then shoots (if a ranged weapon is ready); it steps in only when the mob keeps hitting it with none of its rounds landing, or nothing fixed it in 12 s. "Out of range" alone never makes it step in.

### Group skillchain (v4.70)

When another player is in the party (`group_skillchain.min_players`, default 2 with you), every AutoAttack plans the party's weapon skills together and the job's `ws_list` is paused. It runs again as soon as you are the only player left. No messages pass between characters: each AutoAttack works out the same plan from the party list, each player's job (party packets), TP, `group_skillchain` in `aa_config.lua`, and the weapon skills it sees land on the mob (players' and Trusts').

* **Continuing a chain.** After a WS lands, whoever adds the most goes first: the skillchain level, the stronger closing WS (`power`), and what can still follow it. Melee come before fillers. If that player doesn't go, the next best gets a turn `handoff_wait` seconds later. Nobody breaks a live chain that someone else can still continue.
* **Opening.** With no live chain, the ready player whose opener leads to the best 2-4 step chain (counting players who are ready or nearly ready, `soon_tp`) opens; the next best opens `opener_wait` seconds later if they don't.
* **Once per mob.** `once_per_mob = {['Great Axe'] = 'Full Break'}`: a player who still owes that WS on the current mob opens with it, then the chain carries on (Full Break > Kasha = Fusion > Ukko's Fury = Light > Fudo = Light).
* **Fillers** (`filler_jobs`, default RDM BLM WHM SCH GEO BRD SMN, or `fillers = {'Name'}`): magic burst first; use TP to continue a chain only when no melee can, otherwise only while the melee are under `filler_wait_tp` (or the filler is near 3000 TP).
* **Weapons.** Yours is read from your main hand; other players' from `job_weapons[job]`, or `weapons[name]` until their job is known. `pools[weapon]` lists the WS each player brings (yours only the ones you have learned).
* **Collision guard.** No WS while another party member's WS is readying. Teammates see each other's TP a moment late, so a teammate within `soon_tp` of 1000 keeps their opener turn, and whoever made the last WS continues only after everyone else (v4.71).
* **Window** (from logs): skillchains formed 4-10 s after the previous WS at every step (2 s never, 3 s about half), so the next WS is sent 3.2 s after the last one lands (`window_open`) and up to `window_close` 10 minus `ws_lead` 1.2; no shrink per step (v4.72).
* **Light on Light ends the chain** (v4.72): a Light made from two Light-property WS (e.g. Ukko's Fury and Fudo) can't be continued, so the next opener goes instead. A Light made from Fusion + Fragmentation can take one more Light WS.
* **Damage model** (v4.72): each WS is worth its own damage plus the skillchain damage it closes (`power` / `sc_power`, built in from logs: Light closed by Savage Blade 32k, Upheaval 25k, Ukko's Fury 25k, Shoha 16k).
* **Turn order** (v4.73): a teammate placed ahead of you keeps the turn from `block_tp` (500 TP), because you see their TP a moment late.
* **Per-player lists** (v4.73): `players = {Scracheebrat = {'Savage Blade'}}` gives a teammate's exact WS list instead of `pools[weapon]`. Your own list is always read from the game. Since v4.90 a teammate's profile (below) is used when they send one; this list overrides only when you set it.
* **No-shows** (v4.71): a teammate who passes on a planned WS `noshow_max` times (3) stops being planned for it this session.
* **TP bank** (v4.71): no new chain on a mob at or under `bank_hpp` % HP (10) unless you have 2000+ TP; that TP opens the next mob.
* `//aa gsc` shows what it sees (players, jobs, weapons, TP, pools, last chain). `//aa gsc on|off` overrides `enabled` for this session; `//aa gsc auto` goes back to the config. Also by tell or party chat: `aa gsc off`.
* Only with `ws_mode.type = "Normal"`; AoE / Odin / other modes still use `ws_list`.

### Dynamic group skillchain (v4.90)

Any job, any weapon: if Shadow comes as THF with daggers, everyone's AutoAttack plans his Rudra's Storm / Evisceration / Exenterator.

* **Skillchain properties** come from Windower's own weapon skill list, so every weapon skill works. The built-in table only corrects it.
* **Profiles.** Each AutoAttack sends its job, level, weapon and the weapon skills it will use in a hidden party line (`aa~g p ...`, never shown in the chat window; since v4.91 teammates' lines are dropped before the game prints them):
  * on `aa fight`, when a player joins, after zoning, and on `aa gsc ?`;
  * when your job or main-hand weapon changes while you're idle, after it stays that way `weapon_hold` seconds (3). Swaps mid-fight (Abyssea red-procs) and Dread Spikes weapons are ignored.
  * Lines go out 1.5 seconds apart by party slot, so four players never post at once.
  * A teammate's profile comes before the `job_weapons` / `pools` guesses. Without one, the weapon skills you see them use are added to their list.
* **Learning.** Every AutoAttack learns, for every player in the party (Vayne included): each WS's damage, the skillchain damage each closing WS makes (as Light-equivalent) and magic burst damage. It's saved to `data/aa_learned_<Character>.lua` every 2 minutes, on zoning, logout and unload.
  * `aa_knowledge.lua` is the master. At load both are read. Since v4.98 the learning file keeps what was learned on this PC since the master, and the master lists what it already holds, so nothing is counted twice and nothing is lost. Older files convert themselves.
  * The newest `learn_window` (60) samples make each figure, so gear changes show quickly.
  * Per mob type: the player's figure for that mob is blended with their all-mob figure x how hard the party hits that mob type (`mob_k` 5). A new mob type is right after a kill or two.
  * A sample under 25% of a settled average (20+ samples) is skipped unless 3 come in a row (`odd_ratio`, `odd_min`, `odd_repeat`).
  * Only real weapon skills count: DRK Weapon Bash (which arrives with Ruinator's ID) is ignored since v4.98.
  * The plan uses learned damage first (that player's, then the party's, after `learn_min` samples), then the built-in figures. Each skillchain also counts the fillers' learned magic burst x `mb_weight`.
* **Sharing.** On `aa fight` and when a player joins, every AutoAttack posts a short digest (`aa~g d`). Whoever knows the most about a player sends those entries (`aa~g k`), and the others take any entry with more samples than theirs.
* **Master file.** When a release is built on MarksPC, `make_release.py` adds the new samples of every `data/aa_learned_*.lua` (and the entries teammates sent) to `aa_knowledge.lua`, records what it took, and ships it; `aa update` downloads it (`extra=` in `manifest.txt`).
* `//aa gsc` marks players whose profile it has with `(profile)`. `//aa gsc k` lists what is learned for the party, `//aa gsc sync` compares now, `//aa gsc save` writes the learning file, `//aa gsc ?` (or `/p aa gsc ?`) re-sends profiles.
* Settings in `group_skillchain`: `announce`, `learn`, `sync` (all true), `learn_min` 3, `learn_window` 60, `mob_k` 5, `odd_min` 20, `odd_ratio` 0.25, `odd_repeat` 3, `pool_max` 6, `weapon_hold` 3, `mb_weight` 0.5, `sync_min` 5.

### `ring_config`

```lua
ring_config = {enabled = true,
    default_ring = 'Chirich Ring',
    exp_rings = {'Echad Ring'},
    cp_rings = {'Trizek Ring', 'Endorsement Ring'},
    emporox_ring = "Emporox's Ring",
}
```

If you have no EXP/CP/Emporox buff, the script equips a ring in slot ring1, uses it, then equips `default_ring` back. Exp and CP rings are locked for 2 hours after use; the lock is stored in the settings file. Rings are looked up in your inventory and wardrobes. **Equipping and using a ring takes about 18 seconds, during which the loop does nothing else.** The `/item` waits until 5 seconds have passed with no kill nearby (`RING_KILL_HOLD`). (v4.43) If kills keep coming for 20 seconds (`RING_HOLD_MAX`), the ring is skipped, `default_ring` goes back on, and that ring is tried again 60 seconds later (`RING_HOLD_RETRY`). Set `enabled = false` (or leave a list out) if you do not want this.

**v4.70 notes**

* `ws_list` entries take `once_per_mob = true` (fires once on each mob, then the list carries on without it).
* `abilities` entries take `yield_to = {'Berserk'}` (and `yield_secs`, default 30): the JA is held while that JA is up or ready within `yield_secs`. Built in for Defender (Defender and Berserk cancel each other). Berserk and Aggressor stack, so their `buff_any` no longer skip each other.
* No job ability within 4 seconds of your own WS, and a JA the game refuses ("Unable to use job ability") is tried again after the gap instead of waiting its whole recast.
* Rings: one ring per pass and 60 seconds before the next ring after one that didn't go off. CP rings are skipped while exemplar points come in and capacity points don't, or when job points are capped.

### `item_food`

```lua
item_food = {enabled = true,
    {name='Red Curry Bun', target='<me>', min_time=30, uses_per_mob=1, buff_id=251},
}
```

Uses an item when its `min_time` has passed, you do not have its `buff_id`, you are not moving, and you actually have the item. `min_time` is required.

### `dread_spikes`

```lua
dread_spikes = {enabled = true,
    gear       = {main = 'Item Name', sub = 'empty', range = 'Item Name'},
    after_gear = {},       -- {} = put back what was worn before
    dispel     = 'auto',   -- 'auto' | {'Dispel'} | {}
    nukes      = 'auto',   -- 'auto' | {'Thunder IV', 'Thunder III'} | {}
    ranged     = true,
},
```

Used when the top-level `dread_spikes.enabled` is `true` and your target has Dread Spikes (v4.32).

| Field | Meaning |
|---|---|
| `enabled` | `false` turns the mode off for this job: no gear swap and weapon skills stay on. Tracking still runs. |
| `gear` | Worn while the target has Dread Spikes. Slots: `main sub range ammo head neck ear1 ear2 body hands ring1 ring2 back waist legs feet` (also `weapon` = `main`, `ranged` = `range`, v4.36). `'empty'` takes that slot's item off, e.g. `sub = 'empty'`. `''` leaves the slot alone. Gear goes on main first. Swapping `main`, `sub` or `range` costs your TP. `{}` = no swap. |
| `after_gear` | `{}` puts back exactly what was worn before: every swapped slot, plus `sub` when `main` was swapped and `ammo` when `range` was. Slots you list here use your items instead, and every other slot still goes back to what was worn before (v4.36). The restore is checked and re-sent every 3s, up to 5 tries. |
| `dispel` | `'auto'` tries Dispel, Magic Finale and Dark Shot, whichever this job (main or sub) can use. Or list your own. `{}` = none. Dispel goes first every time it is ready. |
| `nukes` | `'auto'` uses this job's `magic` entries with `type='damage'`. Or list spells strongest first. Cast when no dispel is ready. |
| `ranged` | `true` = `/ra` between melee rounds when a ranged weapon and ammo are ready. Ranged attacks don't trigger spikes. |

### Dread Spikes mode

The game never sends a mob's buffs to the client, so AutoAttack tracks Dread Spikes (status 173) per mob ID from the messages it can see:

- **Marked up:** the mob "gains the effect of Dread Spikes" (spell or TP move), or anyone's melee hit on it (yours, the party's, Trusts') shows "spikes drain N HP".
- **Marked down:** a wear-off or dispel message, the mob dies, `clear_hits` landed melee hits in a row with no drain, or `max_duration` seconds since it was last seen. The spell lasts 3:00 and ends early once it has drained its cap, so 180 is the most it can last after a cast or a drain.
- **Forgotten:** no news about the mob for `forget_after` seconds (60 minutes). Everything is cleared when you zone.

When the mob you are fighting has it:

1. The job's `gear` goes on. With `lock_gearswap = true`, `//gs disable` is sent for those slots so GearSwap can't swap them back.
2. No weapon skills, and the skillchain lockout is cleared.
3. Dispel (spell or JA) first, then nukes, then `/ra`. Nukes and shots wait for `melee_rounds` of your melee in between, so the drain messages keep the record current. If you aren't swinging, they wait `melee_wait` seconds at most.
4. When it's down, you switch to a clean mob, or you leave the fight, `after_gear` (or the gear worn before) goes back on and `//gs enable` is sent.

`//aa ds` shows the tracked mobs. At debug level 1 you see `DREAD SPIKES` lines only for your own target. Level 2 shows every mob.

---

## Safety systems

### Skillchain lockout

When a weapon skill with `LockOut=1` fires, all non-weapon-skill actions are held back so the next skill in the chain is not delayed. A `LockOut=0` skill ends the lockout. The lockout is also cleared when a new target is picked, when the fight ends, when you change job, and when you change `ws_mode.type`. Set `ws_mode.lockout = "false"` to switch it off.

### Purple (claimed) mob handling

* Mobs claimed by anyone outside your party are ignored when scanning.
* If your target becomes claimed by someone else, or the game says "already claimed", the script sends `/attack off` and `/targetoff`, then looks for a replacement. If none is in range it waits up to 15 seconds.
* Mobs in `purple_escape_exclusions` are exempt.
* ASSIST mode does not do the replacement scan.

### Unreachable mobs

* **Cant-see counter.** Three "Unable to see" / "You cannot see" messages on one mob within 8 seconds blacklists it and disengages. Repeat offenders are skipped for longer each time: 10s, 30s, 120s, then 300s.
* **Stuck watchdog (PULL mode).** If you are engaged with the mob in melee range but have not swung, weapon skilled, shot or cast at anything for 30 seconds (`STUCK_TIMEOUT`), the mob is blacklisted the same escalating way and you disengage. It pauses while you are asleep, stunned, petrified or terrorized.
* **Pull line-of-sight.** "Unable to see" within 5 seconds of a PullNext pull blacklists that mob for 30 seconds.
* **Stale pull.** The same mob chosen 3 times in 12 seconds without an engage is blacklisted for 10 seconds.
* **Pull-in timeout.** A mob chosen within pull range has 20 seconds (`PULL_IN_TIMEOUT`) to reach your melee range, take a swing from you, or be fighting a party member. The clock restarts while it is targeting your party and still walking closer. Otherwise it is blacklisted for 30 seconds (`PULL_IN_BLACKLIST`, never lifted early), you disengage, and the closest mob is picked again. A mob that is targeting you and is already claimed by your party (for example a Provoked caster that stops at casting range) is never timed out this way for up to 60 seconds (`PULL_IN_CLAIMED_MAX`). (v4.39) Before giving up on a mob in Provoke range, if you are WAR main or sub and Provoke has not been tried on it yet, Provoke fires first; if it lands the mob gets a fresh 20 seconds. If Provoke comes back within 8 seconds (`PULL_GIVEUP_PROVOKE_WAIT`) the script waits for it before giving up (`GIVEUP-PROVOKE` / `GIVEUP-HOLD` in the log).
* **Mobs on you come first.** A mob that hit you in the last 10 seconds is taken off any temporary blacklist and targeted again. No new mob is pulled while a mob is on you (it hit you, or it targets you and your party has claimed it, within 25 yalms), for at most 45 seconds per mob (`FRESH_HOLD_MAX`), and no new mob is pulled while your HP is below 50% (`LOW_HP_NO_PULL_PCT`, 0 turns it off).
* **Step-in (`APPROACH_ENABLED`).** If the game says a mob is out of range while it looks close, or a Trust is tanking it a few yalms away (within 10 yalms, `APPROACH_MAX_DIST`), you walk toward it in a short burst instead of re-pulling, and that mob's melee range is shrunk to what the game actually allows. Mobs fighting a Trust or party member are never blacklisted by the re-pull limit, the stuck watchdog or the melee stall check.
* **Step-in when hit (v4.34, reworked v4.38, `STEP_IN_WHEN_HIT`).** If a mob in melee range is giving you trouble, Provoke goes first and a short step in (1.5 yalms closer, never nearer than 1.5 yalms) only follows if that didn't fix it. Trouble means the mob has attacked you 4 times (`STEP_IN_MOB_HITS`, hits or misses) without one of your melee rounds landing on it, or the game just said "out of range", "Unable to see", "You cannot see" or "unable to reach" about it (`TROUBLE` in the log). The step in happens 3 seconds (`STEP_IN_AFTER_PROVOKE`) after a Provoke lands on that mob if you still aren't hitting. If Provoke is on recast it waits up to 8 seconds (`STEP_IN_PROVOKE_MAXWAIT`), then steps in anyway; with no /WAR it steps in right away. (v4.40) With `MELEE_PROVOKE_NO_HIT` off (the default) it no longer waits for a Provoke: it steps in as soon as there is trouble, except for 3 seconds after a Provoke that just landed on that mob. After a step it needs fresh trouble before stepping again (`STEP-IN` in the log). This works even with `APPROACH_ENABLED = false`. Set `STEP_IN_WHEN_HIT = false` to turn it off.
* **Step back after a step-in (v4.37, `STEP_IN_RETURN`).** Right before a step-in, AutoAttack saves the spot you are standing on. As soon as a melee round lands on that mob you run back to that exact spot (within 0.35 yalms, `STEP_IN_RETURN_TOL`) and face the mob again; mobs follow you, so the fight carries on at your old spot. It also goes back if the mob dies or you switch targets. This happens once per mob (`STEP_IN_RETURN_MAX`); if you still can't hit it after going back, the next step-in keeps you there. If nothing lands within 60 seconds (`STEP_IN_RETURN_WAIT`) the spot is forgotten. Log: `STEP-HOME` / `STEP-BACK`. Set `STEP_IN_RETURN = false` to turn it off.
* **Re-engage when no melee rounds (v4.35, `REENGAGE_WHEN_STUCK`).** If you're engaged with the mob in melee range but haven't landed a melee round on it for 15 seconds (`REENGAGE_WAIT`; weapon skills, job abilities and Provoke don't count), AutoAttack sends `/attack off`, targets the mob again and sends `/attack on` (`RE-ENGAGE` in the log, which also shows your battle target and where your last melee round went). It repeats every 15 seconds while the problem lasts. Set `REENGAGE_WHEN_STUCK = false` to turn it off.
* **Close-fight re-pull (v4.02).** A mob within 10 yalms that is hitting you or a Trust while you aren't hitting it is re-pulled with Provoke (`CLOSE-REPULL` in the log). If Provoke is on cooldown the script waits for it instead of wasting the re-pull, and the mob is never blacklisted. A Provoke pull command on cooldown is no longer sent.
* **Re-pull limit.** After 3 re-pulls with the mob still out of melee range, it is blacklisted for 10 seconds and you disengage. (v4.39) The same Provoke-first check runs before the limit is hit. Also, if a ranged pull just got "Unable to see" / "You cannot see" and Provoke is back within 8 seconds (`RA_CANT_SEE_PROVOKE_WAIT`), the script waits for Provoke instead of sending another `/ra` that won't land.
* **Dead cursor.** If your cursor is on a corpse, it is cleared and that ID is skipped for 5 seconds.
* **Dead-mob guards (v4.42, `DEAD_MOB_GUARD`).** No command is sent at a corpse that may still be despawning (the cause of the FFXiMain.dll crashes). ASSIST's `/target <bt>` waits for a live battle target (see ASSIST above). In PULL, when your mob dies and nothing is hot-switched to, `/attack off` + `/targetoff` are held for up to 3 seconds while the game disengages on its own (`CORPSE-HOLD` in the log), and a pull aborted because the mob died clears the cursor 3 seconds later, only if it is still on that corpse. Food and other `item_food` items wait 5 seconds after a kill, like rings. Set `DEAD_MOB_GUARD = false` in autoattack.lua for the v4.41 behaviour.
* A first-time blacklist entry is lifted early if the mob starts targeting you or moves into range. From the second strike on it is not, and the aggro scan will not lock back onto a blacklisted mob. Strikes are forgotten after 15 minutes without a new one (`CANT_SEE_STRIKE_DECAY`) or when that mob dies (v4.18). All entries are cleared when you zone.

### Full party rule (v4.54)

In PULL mode no **new** mob is pulled while the party is short of Trusts -- the job's `max_trusts`, the zone limit and 6 per party all count (with 2 players and `max_trusts = 5`, full is 4 Trusts). Mobs already fighting you or the party (hitting, claimed by, or targeting you, a player or a Trust) are still fought. While it holds, AutoAttack keeps calling Trusts and prints `PULL HOLD: party not full (n/m Trusts, x/6 in party)` every 10 seconds. The cursor is left alone. It covers the idle scan, idle mobs in melee range, the engaged pull, hot switch and PullNext. ASSIST mode never pulls, so it is not affected. Turn it off with `full_party_pull = false` in the `party` block of aa_config.lua, or `//aa fullparty off` for the session.

**Ghost slot.** A disconnected player can leave a party slot the party list doesn't show: the party reads 4/6 or 5/6 but the game says the maximum Trusts are out. When that game line comes in (or 3+ Trust calls fail over 60 seconds with none joining, while you are not silenced or mounted), the idle leader sends `/retr all`, waits for the Trusts to leave, clears the Trust skip list and calls them again. This never happens while a mob is on the party. If it happens again within 10 minutes in the same zone, AutoAttack stops retrying and tells you to remove the disconnected member or use `//aa fullparty off`. `//aa fullparty fix` forces the fix. The game line is "You have called forth your maximum number of alter egos." ("The party is full" counts too, but only within 10 seconds of a Trust call). Every game chat line with "alter ego" is logged at debug level 2 (`TRUST TEXT`); AutoAttack's own `[DEBUG]` / `[AA]` lines are ignored, so they can't set it off (v4.55).

### Main-loop watchdog

If the main loop goes silent for 120 seconds (`AA_WATCHDOG_STALL`, normally a Lua error, shown in the Windower console), AutoAttack restarts it; after 5 restarts in 30 minutes it stops. (v4.43) A restart (or a stop + start) always turns auto-run off first, so a loop that died mid-move doesn't leave you running, and a replaced loop that is still waiting somewhere can no longer send anything: its commands, target packets and movement are dropped (`STALE-LOOP` in the log).

### Low-HP stop

If your HP is at or below 25% (`LOW_HP_STOP_PCT`) and nothing has healed you for 30 seconds (`LOW_HP_NO_HEAL_SECS`, counted from when your HP dropped that low), AutoAttack sends `/attack off`, prints a red warning in chat and stops. If a mob is still on you it does **not** stop (that would leave you standing there): it prints a red warning and keeps fighting. Set `LOW_HP_EMERGENCY_CMD` to a Windower command (for example `'input /ja "Super Jump" <t>'`) to run it once when your HP drops that low with a mob on you. Each warning also logs a `PARTY:` line with every Trust's HP, MP and distance. Set `LOW_HP_STOP = false` to turn this off.

**Emergency abilities.** Every `abilities` entry with `hpp_below` (Spirit Surge, Restoring Breath, Super Jump, ...) is checked at the start of every loop cycle, even with no target, and the first ready one fires (`EMERGENCY: HP n% -- using X`). If one is skipped while your HP is under its limit, the log says why every 10 seconds (no live pet, recast, out of reach, ...). Abilities aimed at the mob respect their `max_dist` (yalms from the mob's edge); Jumps without one use 4.5 yalms (3.0 + `JUMP_REACH_PAD`).

### Facing

Facing is built in (since v3.84); the separate Facing addon is not needed. The script turns you toward your target every 3 seconds during a fight, before spells and pulls, and immediately after an "Unable to see" / "You cannot see" message. It uses the same math as the Facing addon and turns you toward `<st>` if a sub-target cursor is open, otherwise `<t>`. With `cmd_mode = true` each turn is logged as `[CMD] face ...`.

---

## Debugging

AutoAttack has three debug levels (v4.25), set with `debug_level` at the top of the file or in game with `//aa debug`:

| Level | `//aa debug` | What you see |
|---|---|---|
| `0` | `0` / `off` | Nothing except command replies and warnings. |
| `1` | `1` / `release` | **Default.** Short `[AA] ...` lines for the important events only: loaded, mode start / stop, `PULLING` / `ATTACKING`, target switches, weapon skills, emergencies, trusts, food and ring use, setup problems and errors. |
| `2` | `2` / `dev` | Everything. Each line is stamped `[DEBUG 23:33:41.512 +0.084]` (time to the millisecond and seconds since the previous line). Adds `TIMING:` lines when a pass of the main loop takes longer than `DEBUG_SLOW_TICK` (naming the step it was on) or the game freezes between frames for longer than `DEBUG_FRAME_STALL`. With `DEBUG_LOG_FILE = true` (or `//aa debug file on`) every line and every command the script sends is also written to `data\logs\aa_<Character>_<date>.log`, saved line by line so it survives a client crash. |

* If something goes wrong, run `//aa debug dev`, reproduce it and send the log file with your report.
* If the game shows "Invalid argument" in the console, set `cmd_mode = true` (or use level 2 with the file log), reproduce it, and look at the `[CMD]` line just above the error.
* If an item or tool is not recognised, run `//aa dumpinv` and compare the name to your config.
* Level 2 is very verbose; go back to `//aa debug 1` for normal play.

**Updates and your settings (v4.63).** `aa update` only replaces `autoattack.lua`, `aa_party.lua`, `aa_config_defaults.lua` and `README.md`; your `aa_config.lua` is never touched. When a new version adds a setting your `aa_config.lua` doesn't have, the default is used (at any level, e.g. a new `party` option or a new field in a job's `pull` block) and one line tells you: `[AA] aa_config.lua: N new settings using defaults -- //aa config new to see them`. `//aa config new` lists them with their default values; copy a line into your `aa_config.lua` to change it. Your own lists (abilities, magic, food, trust groups, WS lists, mob lists, friends) and jobs are never added to or changed.

**Dev settings (v4.62).** `dev = {debug_level = 2, debug_log_file = true}` in aa_config.lua overrides the debug values at the top of autoattack.lua (also `cmd_mode`, `ws_blocked_debug`), so `aa update` never resets them. Leave it `{}` to use the file's values.

**Memory (v4.61).** AutoAttack no longer keeps Windower's full item list (about 20 MB) loaded. It keeps only the items it has looked up. When it needs one it hasn't seen, it loads the list for a moment and releases it 10 seconds later (`ITEMS_KEEP_SECS`). At level 2 the `HEARTBEAT` line (every 10 minutes) shows `AA lua <KB>` and `item list loads <n>`, and each load / release is logged as `ITEMS: ...`.

---

## Settings file

`addons\autoattack\data\settings.xml` is written by the addon. It stores, per character, the time each food or pouch was last used and the ring lock timers. It is safe to delete; it will be recreated.

---

## Known limitations

* **Turning side effect.** The built-in facing uses the same `windower.ffxi.turn()` call as the Facing addon, whose documentation warns that overusing it can desync your character from the camera (invisible character, frozen camera) until you zone or log out. AutoAttack turns often.
* **Configuration is done in the Lua file.** There are no in-game commands to change the whitelist or weapon-skill mode (`//aa debug` changes the debug level for the session only).
* **It does not check what you know.** Spells, trusts and abilities that you have not learned, or that your sub job cannot use, are still attempted and the game will report an error.
* **Party members from your alliance** are treated as "another party" for claim checks.
* **Job changes.** Re-send `assist` or `pull` after changing jobs.
* **One character.** The loop is per client. Run it on each client separately.

---

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Nothing happens after `//aa pull` | You changed zones (zoning stops the loop), or no mob passes your filters. Send `//aa pull` again and check the `[DEBUG]` lines. |
| "Already running" message | The loop is already active. Send `//aa stop` first. |
| Trusts never appear | The `cast` or `mob` name in the trust list is wrong, or you have not unlocked that trust. Check `[DEBUG] TRUSTS:` lines. |
| A weapon skill never fires | It needs at least 1000 TP, `min_time` must have passed since the last weapon skill, and if a lockout is active only weapon skills run. Turn on `ws_blocked_debug`. |
| Pulls only target one kind of mob | A whitelist is active. Empty `mob_whitelist` and set both farming toggles to `"false"` to pull anything. |
| Character keeps running at a far-away mob | With a whitelist active, the script leaves the cursor on an out-of-range whitelisted mob so you can run to it. It will not pull until it is in range. |
| Spells fail with "Unable to cast" or "Unknown spell" | The spell is not available on your current main/sub job or is not learned. Remove it from `magic`. |
| Game crashes (FFXiMain.dll access violation) | Check the last `TARGET-SET` / `TARGET-SKIP` / `TARGET-QUIET` lines in the log before the crash. If crashes keep happening right after kills, raise `TARGET_QUIET_WINDOW` (default 1.0s), or set `SET_TARGET_VIA_ADDON = true` and load SetTarget to go back to the pre-v3.95 targeting. To rule the injected packet out entirely, run `//aa target native` (v4.07) and play a normal session. |
| Ring log says `game refused /item ... (command error)` | The game itself rejected the `/item` (still on its reuse timer, or level too low). The ring is locked for 2h and the default ring goes back on. Clear the lock in `data/settings.xml` if you know the ring is ready. |

---

## Credits

Written by Mark Williams. Depends on the Windower 4 project. The built-in targeting is based on Windower's SetTarget addon, and the built-in facing on the Facing addon (Zero Serenity, Rubenator, Nattack).
