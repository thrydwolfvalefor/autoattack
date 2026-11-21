-- AutoAttack group skillchain knowledge (master) v4.99 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua +1200 new
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- wsm / scm = the same per mob type ("WS@mob").
-- used = {character, kind, player, key, samples}: what of each learning file this
-- master already holds (v4.98) -- only samples past it count as new.
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "4.99",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 520, a = 8.790, t = 1795282023},
    ["Tachi: Kasha"] = {n = 639, a = 8.948, t = 1795281980},
    ["Tachi: Shoha"] = {n = 690, a = 9.405, t = 1795282014},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 96, a = 8.627, t = 1795281648},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 576, a = 2.846, t = 1795282043},
    ["Ukko's Fury"] = {n = 1039, a = 13.857, t = 1795281985},
    ["Upheaval"] = {n = 1007, a = 16.675, t = 1795282051},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 537, a = 12.375, t = 1795282027},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 372, a = 18.184, t = 1795282023},
    ["Tachi: Kasha"] = {n = 484, a = 17.446, t = 1795281980},
    ["Tachi: Shoha"] = {n = 429, a = 24.215, t = 1795282014},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 65, a = 15.234, t = 1795281029},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 4, a = 5.748, t = 1795279918},
    ["Ukko's Fury"] = {n = 782, a = 28.733, t = 1795281985},
    ["Upheaval"] = {n = 725, a = 29.569, t = 1795282032},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 131, a = 20.306, t = 1795281912},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 654, a = 6.341, t = 1795282024},
  },
},
wsm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 494, a = 8.822, t = 1795282023},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 607, a = 8.963, t = 1795281980},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 669, a = 9.403, t = 1795282014},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 80, a = 8.887, t = 1795281648},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 559, a = 2.847, t = 1795282043},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 1012, a = 13.856, t = 1795281985},
    ["Upheaval@Locus Dire Bat"] = {n = 975, a = 16.652, t = 1795282032},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 537, a = 12.375, t = 1795282027},
  },
},
scm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 363, a = 18.297, t = 1795282023},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 465, a = 17.553, t = 1795281980},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 414, a = 24.405, t = 1795282014},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 54, a = 16.810, t = 1795281029},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 4, a = 5.748, t = 1795279918},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 764, a = 28.750, t = 1795281985},
    ["Upheaval@Locus Dire Bat"] = {n = 718, a = 29.591, t = 1795282032},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 131, a = 20.306, t = 1795281912},
  },
},
used = {
  {"Shadowhammer", "mb", "Scracheebrat", "MB", 44},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Fudo", 22},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Kasha", 31},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Shoha", 37},
  {"Shadowhammer", "sc", "Scracheebrat", "Savage Blade", 5},
  {"Shadowhammer", "sc", "Shadowhammer", "Ukko's Fury", 51},
  {"Shadowhammer", "sc", "Shadowhammer", "Upheaval", 57},
  {"Shadowhammer", "sc", "Vayne", "Cross Reaper", 11},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 22},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 31},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 37},
  {"Shadowhammer", "scm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 5},
  {"Shadowhammer", "scm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 51},
  {"Shadowhammer", "scm", "Shadowhammer", "Upheaval@Locus Dire Bat", 57},
  {"Shadowhammer", "scm", "Vayne", "Cross Reaper@Locus Dire Bat", 11},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Fudo", 32},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Kasha", 43},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Shoha", 51},
  {"Shadowhammer", "ws", "Scracheebrat", "Savage Blade", 6},
  {"Shadowhammer", "ws", "Shadowhammer", "Full Break", 42},
  {"Shadowhammer", "ws", "Shadowhammer", "Ukko's Fury", 77},
  {"Shadowhammer", "ws", "Shadowhammer", "Upheaval", 75},
  {"Shadowhammer", "ws", "Vayne", "Cross Reaper", 38},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 32},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 43},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 52},
  {"Shadowhammer", "wsm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 6},
  {"Shadowhammer", "wsm", "Shadowhammer", "Full Break@Locus Dire Bat", 42},
  {"Shadowhammer", "wsm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 77},
  {"Shadowhammer", "wsm", "Shadowhammer", "Upheaval@Locus Dire Bat", 74},
  {"Shadowhammer", "wsm", "Vayne", "Cross Reaper@Locus Dire Bat", 38},
},
}
