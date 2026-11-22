-- AutoAttack group skillchain knowledge (master) v5.03 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua +14963 new
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- wsm / scm = the same per mob type ("WS@mob").
-- used = {character, kind, player, key, samples}: what of each learning file this
-- master already holds (v4.98) -- only samples past it count as new.
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "5.03",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 1872, a = 9.480, t = 1795325775},
    ["Tachi: Kasha"] = {n = 2028, a = 9.096, t = 1795325769},
    ["Tachi: Shoha"] = {n = 1912, a = 9.476, t = 1795325762},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 614, a = 8.786, t = 1795329108},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 1746, a = 3.454, t = 1795329047},
    ["Ukko's Fury"] = {n = 3403, a = 16.726, t = 1795329133},
    ["Upheaval"] = {n = 3166, a = 21.960, t = 1795329124},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 1057, a = 11.480, t = 0},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 1223, a = 20.958, t = 1795325723},
    ["Tachi: Kasha"] = {n = 1390, a = 19.221, t = 1795325769},
    ["Tachi: Shoha"] = {n = 1222, a = 21.691, t = 1795325762},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 418, a = 15.376, t = 1795329108},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 11, a = 6.254, t = 1795324522},
    ["Ukko's Fury"] = {n = 2695, a = 32.562, t = 1795329113},
    ["Upheaval"] = {n = 1966, a = 34.841, t = 1795329056},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 292, a = 19.620, t = 0},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 2741, a = 8.677, t = 1795329072},
  },
},
wsm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 1846, a = 9.480, t = 1795325775},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 1996, a = 9.096, t = 1795325769},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 1892, a = 9.476, t = 1795325762},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 598, a = 8.786, t = 1795329108},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 1728, a = 3.454, t = 1795329047},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 3373, a = 16.796, t = 1795329113},
    ["Upheaval@Locus Dire Bat"] = {n = 3131, a = 21.960, t = 1795329124},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 1057, a = 11.480, t = 0},
  },
},
scm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 1214, a = 20.958, t = 1795325723},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 1371, a = 19.221, t = 1795325769},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 1207, a = 21.691, t = 1795325762},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 407, a = 15.376, t = 1795329108},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 11, a = 6.254, t = 1795324522},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 2676, a = 32.562, t = 1795329113},
    ["Upheaval@Locus Dire Bat"] = {n = 1957, a = 34.841, t = 1795329056},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 292, a = 19.620, t = 0},
  },
},
used = {
  {"Shadowhammer", "mb", "Scracheebrat", "MB", 1726},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Fudo", 682},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Kasha", 705},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Shoha", 627},
  {"Shadowhammer", "sc", "Scracheebrat", "Savage Blade", 307},
  {"Shadowhammer", "sc", "Shadowhammer", "Full Break", 7},
  {"Shadowhammer", "sc", "Shadowhammer", "Ukko's Fury", 1594},
  {"Shadowhammer", "sc", "Shadowhammer", "Upheaval", 943},
  {"Shadowhammer", "sc", "Vayne", "Cross Reaper", 86},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 682},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 705},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 627},
  {"Shadowhammer", "scm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 307},
  {"Shadowhammer", "scm", "Shadowhammer", "Full Break@Locus Dire Bat", 7},
  {"Shadowhammer", "scm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 1594},
  {"Shadowhammer", "scm", "Shadowhammer", "Upheaval@Locus Dire Bat", 943},
  {"Shadowhammer", "scm", "Vayne", "Cross Reaper@Locus Dire Bat", 86},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Fudo", 1119},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Kasha", 1108},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Shoha", 922},
  {"Shadowhammer", "ws", "Scracheebrat", "Savage Blade", 441},
  {"Shadowhammer", "ws", "Shadowhammer", "Full Break", 940},
  {"Shadowhammer", "ws", "Shadowhammer", "Ukko's Fury", 1923},
  {"Shadowhammer", "ws", "Shadowhammer", "Upheaval", 1718},
  {"Shadowhammer", "ws", "Vayne", "Cross Reaper", 279},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 1119},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 1108},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 923},
  {"Shadowhammer", "wsm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 441},
  {"Shadowhammer", "wsm", "Shadowhammer", "Full Break@Locus Dire Bat", 940},
  {"Shadowhammer", "wsm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 1922},
  {"Shadowhammer", "wsm", "Shadowhammer", "Upheaval@Locus Dire Bat", 1718},
  {"Shadowhammer", "wsm", "Vayne", "Cross Reaper@Locus Dire Bat", 279},
},
}
