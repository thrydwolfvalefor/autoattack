-- AutoAttack group skillchain knowledge (master) v5.01 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua +5141 new
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- wsm / scm = the same per mob type ("WS@mob").
-- used = {character, kind, player, key, samples}: what of each learning file this
-- master already holds (v4.98) -- only samples past it count as new.
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "5.01",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 746, a = 8.832, t = 1795294095},
    ["Tachi: Kasha"] = {n = 916, a = 9.289, t = 1795294085},
    ["Tachi: Shoha"] = {n = 986, a = 9.029, t = 1795294102},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 171, a = 8.265, t = 1795294047},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 804, a = 2.984, t = 1795294118},
    ["Ukko's Fury"] = {n = 1472, a = 14.518, t = 1795294107},
    ["Upheaval"] = {n = 1441, a = 16.877, t = 1795294098},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 778, a = 11.482, t = 1795293414},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 536, a = 18.816, t = 1795294095},
    ["Tachi: Kasha"] = {n = 682, a = 19.345, t = 1795294085},
    ["Tachi: Shoha"] = {n = 593, a = 22.833, t = 1795294102},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 110, a = 16.421, t = 1795294047},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 4, a = 5.748, t = 1795279918},
    ["Ukko's Fury"] = {n = 1093, a = 30.937, t = 1795294107},
    ["Upheaval"] = {n = 1020, a = 29.747, t = 1795294041},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 206, a = 19.442, t = 1795293374},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 1007, a = 7.942, t = 1795294105},
  },
},
wsm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 720, a = 8.833, t = 1795294095},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 884, a = 9.289, t = 1795294085},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 965, a = 9.029, t = 1795294102},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 155, a = 8.268, t = 1795294047},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 786, a = 2.958, t = 1795294080},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 1445, a = 14.518, t = 1795294107},
    ["Upheaval@Locus Dire Bat"] = {n = 1410, a = 16.877, t = 1795294098},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 778, a = 11.482, t = 1795293414},
  },
},
scm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 527, a = 18.818, t = 1795294095},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 663, a = 19.347, t = 1795294085},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 578, a = 22.837, t = 1795294102},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 99, a = 16.984, t = 1795294047},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 4, a = 5.748, t = 1795279918},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 1075, a = 30.937, t = 1795294107},
    ["Upheaval@Locus Dire Bat"] = {n = 1013, a = 29.747, t = 1795294041},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 206, a = 19.442, t = 1795293374},
  },
},
used = {
  {"Shadowhammer", "mb", "Scracheebrat", "MB", 397},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Fudo", 186},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Kasha", 229},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Shoha", 201},
  {"Shadowhammer", "sc", "Scracheebrat", "Savage Blade", 50},
  {"Shadowhammer", "sc", "Shadowhammer", "Ukko's Fury", 362},
  {"Shadowhammer", "sc", "Shadowhammer", "Upheaval", 352},
  {"Shadowhammer", "sc", "Vayne", "Cross Reaper", 86},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 186},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 229},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 201},
  {"Shadowhammer", "scm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 50},
  {"Shadowhammer", "scm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 362},
  {"Shadowhammer", "scm", "Shadowhammer", "Upheaval@Locus Dire Bat", 352},
  {"Shadowhammer", "scm", "Vayne", "Cross Reaper@Locus Dire Bat", 86},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Fudo", 258},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Kasha", 320},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Shoha", 347},
  {"Shadowhammer", "ws", "Scracheebrat", "Savage Blade", 81},
  {"Shadowhammer", "ws", "Shadowhammer", "Full Break", 270},
  {"Shadowhammer", "ws", "Shadowhammer", "Ukko's Fury", 510},
  {"Shadowhammer", "ws", "Shadowhammer", "Upheaval", 509},
  {"Shadowhammer", "ws", "Vayne", "Cross Reaper", 279},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 258},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 320},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 348},
  {"Shadowhammer", "wsm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 81},
  {"Shadowhammer", "wsm", "Shadowhammer", "Full Break@Locus Dire Bat", 269},
  {"Shadowhammer", "wsm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 510},
  {"Shadowhammer", "wsm", "Shadowhammer", "Upheaval@Locus Dire Bat", 509},
  {"Shadowhammer", "wsm", "Vayne", "Cross Reaper@Locus Dire Bat", 279},
},
}
