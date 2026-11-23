-- AutoAttack group skillchain knowledge (master) v5.05 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua +41725 new
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- wsm / scm = the same per mob type ("WS@mob").
-- used = {character, kind, player, key, samples}: what of each learning file this
-- master already holds (v4.98) -- only samples past it count as new.
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "5.05",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 12236, a = 8.539, t = 1795406249},
    ["Tachi: Kasha"] = {n = 12468, a = 8.100, t = 1795406215},
    ["Tachi: Shoha"] = {n = 9578, a = 8.382, t = 1795406223},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 3660, a = 7.722, t = 1795406244},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 8943, a = 3.100, t = 1795406206},
    ["Ukko's Fury"] = {n = 18025, a = 13.571, t = 1795406187},
    ["Upheaval"] = {n = 16740, a = 17.153, t = 1795406238},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 2730, a = 11.480, t = 0},
    ["Freezebite"] = {n = 12, a = 2.110, t = 0},
    ["Frostbite"] = {n = 12, a = 1.540, t = 0},
    ["Herculean Slash"] = {n = 594, a = 2.313, t = 1795406021},
    ["Power Slash"] = {n = 255, a = 3.415, t = 1795404986},
    ["Shockwave"] = {n = 4, a = 1.340, t = 0},
    ["Sickle Moon"] = {n = 3, a = 3.810, t = 0},
    ["Spinning Slash"] = {n = 2835, a = 7.603, t = 1795406223},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 7393, a = 17.715, t = 1795406249},
    ["Tachi: Kasha"] = {n = 7951, a = 16.513, t = 1795406215},
    ["Tachi: Shoha"] = {n = 6470, a = 17.919, t = 1795406144},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 2577, a = 13.621, t = 1795406244},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 64, a = 5.972, t = 1795396225},
    ["Ukko's Fury"] = {n = 14889, a = 27.604, t = 1795406187},
    ["Upheaval"] = {n = 9431, a = 28.141, t = 1795406229},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 810, a = 19.630, t = 0},
    ["Herculean Slash"] = {n = 152, a = 8.766, t = 1795405353},
    ["Power Slash"] = {n = 56, a = 11.059, t = 1795397422},
    ["Shockwave"] = {n = 4, a = 3.820, t = 0},
    ["Spinning Slash"] = {n = 1479, a = 16.102, t = 1795406223},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 14173, a = 6.971, t = 1795406136},
  },
  ["Vayne"] = {
    ["MB"] = {n = 2, a = 0.005, t = 1795381145},
  },
},
wsm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 11032, a = 8.539, t = 1795406249},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 11258, a = 8.100, t = 1795406215},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 8629, a = 8.382, t = 1795406223},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 3644, a = 7.722, t = 1795406244},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 8925, a = 3.100, t = 1795406206},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 17992, a = 13.571, t = 1795406187},
    ["Upheaval@Locus Dire Bat"] = {n = 16696, a = 17.153, t = 1795406238},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 2730, a = 11.480, t = 0},
    ["Freezebite@Locus Dire Bat"] = {n = 12, a = 2.110, t = 0},
    ["Frostbite@Locus Dire Bat"] = {n = 12, a = 1.540, t = 0},
    ["Herculean Slash@Knotted Root"] = {n = 3, a = 1.100, t = 0},
    ["Herculean Slash@Locus Dire Bat"] = {n = 591, a = 2.313, t = 1795406021},
    ["Power Slash@Locus Dire Bat"] = {n = 255, a = 3.416, t = 1795404986},
    ["Shockwave@Locus Dire Bat"] = {n = 4, a = 1.340, t = 0},
    ["Sickle Moon@Lightfoot Lapinion"] = {n = 3, a = 3.810, t = 0},
    ["Spinning Slash@Knotted Root"] = {n = 3, a = 3.780, t = 0},
    ["Spinning Slash@Lightfoot Lapinion"] = {n = 6, a = 8.060, t = 0},
    ["Spinning Slash@Locus Dire Bat"] = {n = 2826, a = 7.603, t = 1795406223},
  },
},
scm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 6667, a = 17.715, t = 1795406249},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 7194, a = 16.513, t = 1795406215},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 5830, a = 17.919, t = 1795406144},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 2566, a = 13.621, t = 1795406244},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 64, a = 5.972, t = 1795396225},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 14868, a = 27.604, t = 1795406187},
    ["Upheaval@Locus Dire Bat"] = {n = 9418, a = 28.141, t = 1795406229},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 810, a = 19.630, t = 0},
    ["Herculean Slash@Locus Dire Bat"] = {n = 152, a = 8.766, t = 1795405353},
    ["Power Slash@Locus Dire Bat"] = {n = 56, a = 11.059, t = 1795397422},
    ["Shockwave@Locus Dire Bat"] = {n = 4, a = 3.820, t = 0},
    ["Spinning Slash@Locus Dire Bat"] = {n = 1479, a = 16.102, t = 1795406223},
  },
},
used = {
  {"Shadowhammer", "mb", "Scracheebrat", "MB", 3422},
  {"Shadowhammer", "mb", "Vayne", "MB", 2},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Fudo", 1861},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Kasha", 1974},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Shoha", 1478},
  {"Shadowhammer", "sc", "Scracheebrat", "Savage Blade", 659},
  {"Shadowhammer", "sc", "Shadowhammer", "Full Break", 18},
  {"Shadowhammer", "sc", "Shadowhammer", "Ukko's Fury", 3852},
  {"Shadowhammer", "sc", "Shadowhammer", "Upheaval", 2302},
  {"Shadowhammer", "sc", "Vayne", "Cross Reaper", 86},
  {"Shadowhammer", "sc", "Vayne", "Herculean Slash", 75},
  {"Shadowhammer", "sc", "Vayne", "Power Slash", 16},
  {"Shadowhammer", "sc", "Vayne", "Shockwave", 1},
  {"Shadowhammer", "sc", "Vayne", "Spinning Slash", 655},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 1861},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 1974},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 1478},
  {"Shadowhammer", "scm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 659},
  {"Shadowhammer", "scm", "Shadowhammer", "Full Break@Locus Dire Bat", 18},
  {"Shadowhammer", "scm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 3852},
  {"Shadowhammer", "scm", "Shadowhammer", "Upheaval@Locus Dire Bat", 2302},
  {"Shadowhammer", "scm", "Vayne", "Cross Reaper@Locus Dire Bat", 86},
  {"Shadowhammer", "scm", "Vayne", "Herculean Slash@Locus Dire Bat", 75},
  {"Shadowhammer", "scm", "Vayne", "Power Slash@Locus Dire Bat", 16},
  {"Shadowhammer", "scm", "Vayne", "Shockwave@Locus Dire Bat", 1},
  {"Shadowhammer", "scm", "Vayne", "Spinning Slash@Locus Dire Bat", 655},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Fudo", 3195},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Kasha", 3243},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Shoha", 2088},
  {"Shadowhammer", "ws", "Scracheebrat", "Savage Blade", 938},
  {"Shadowhammer", "ws", "Shadowhammer", "Full Break", 2292},
  {"Shadowhammer", "ws", "Shadowhammer", "Ukko's Fury", 4550},
  {"Shadowhammer", "ws", "Shadowhammer", "Upheaval", 4258},
  {"Shadowhammer", "ws", "Vayne", "Cross Reaper", 279},
  {"Shadowhammer", "ws", "Vayne", "Freezebite", 3},
  {"Shadowhammer", "ws", "Vayne", "Frostbite", 3},
  {"Shadowhammer", "ws", "Vayne", "Herculean Slash", 318},
  {"Shadowhammer", "ws", "Vayne", "Power Slash", 81},
  {"Shadowhammer", "ws", "Vayne", "Shockwave", 1},
  {"Shadowhammer", "ws", "Vayne", "Spinning Slash", 1176},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 3195},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 3243},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 2089},
  {"Shadowhammer", "wsm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 938},
  {"Shadowhammer", "wsm", "Shadowhammer", "Full Break@Locus Dire Bat", 2292},
  {"Shadowhammer", "wsm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 4550},
  {"Shadowhammer", "wsm", "Shadowhammer", "Upheaval@Locus Dire Bat", 4258},
  {"Shadowhammer", "wsm", "Vayne", "Cross Reaper@Locus Dire Bat", 279},
  {"Shadowhammer", "wsm", "Vayne", "Freezebite@Locus Dire Bat", 3},
  {"Shadowhammer", "wsm", "Vayne", "Frostbite@Locus Dire Bat", 3},
  {"Shadowhammer", "wsm", "Vayne", "Herculean Slash@Locus Dire Bat", 318},
  {"Shadowhammer", "wsm", "Vayne", "Power Slash@Locus Dire Bat", 81},
  {"Shadowhammer", "wsm", "Vayne", "Shockwave@Locus Dire Bat", 1},
  {"Shadowhammer", "wsm", "Vayne", "Spinning Slash@Locus Dire Bat", 1176},
},
}
