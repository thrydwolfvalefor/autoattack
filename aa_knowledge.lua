-- AutoAttack group skillchain knowledge (master) v5.04 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua +3976 new
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- wsm / scm = the same per mob type ("WS@mob").
-- used = {character, kind, player, key, samples}: what of each learning file this
-- master already holds (v4.98) -- only samples past it count as new.
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "5.04",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 3234, a = 8.670, t = 0},
    ["Tachi: Kasha"] = {n = 3439, a = 9.030, t = 0},
    ["Tachi: Shoha"] = {n = 3169, a = 8.770, t = 0},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 1314, a = 7.284, t = 1795338353},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 3155, a = 3.362, t = 1795338317},
    ["Ukko's Fury"] = {n = 6278, a = 14.317, t = 1795338376},
    ["Upheaval"] = {n = 5943, a = 17.982, t = 1795338361},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 1615, a = 11.480, t = 0},
    ["Freezebite"] = {n = 3, a = 2.106, t = 1795332703},
    ["Frostbite"] = {n = 3, a = 1.536, t = 1795332847},
    ["Herculean Slash"] = {n = 2, a = 1.778, t = 1795332421},
    ["Power Slash"] = {n = 46, a = 3.500, t = 1795338381},
    ["Shockwave"] = {n = 1, a = 1.339, t = 1795337819},
    ["Sickle Moon"] = {n = 1, a = 3.810, t = 0},
    ["Spinning Slash"] = {n = 83, a = 6.726, t = 1795338334},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 2082, a = 18.600, t = 0},
    ["Tachi: Kasha"] = {n = 2310, a = 18.640, t = 0},
    ["Tachi: Shoha"] = {n = 2041, a = 23.460, t = 0},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 920, a = 12.725, t = 1795338353},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 18, a = 6.370, t = 0},
    ["Ukko's Fury"] = {n = 5022, a = 26.381, t = 1795338367},
    ["Upheaval"] = {n = 3503, a = 29.690, t = 1795338282},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 465, a = 19.620, t = 0},
    ["Herculean Slash"] = {n = 1, a = 8.092, t = 1795332421},
    ["Power Slash"] = {n = 8, a = 10.129, t = 1795337905},
    ["Shockwave"] = {n = 1, a = 3.820, t = 1795337819},
    ["Spinning Slash"] = {n = 32, a = 12.233, t = 1795338334},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 5278, a = 7.759, t = 1795338343},
  },
},
wsm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 3208, a = 8.670, t = 0},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 3407, a = 9.030, t = 0},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 3151, a = 8.770, t = 0},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 1298, a = 7.284, t = 1795338353},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 3137, a = 3.362, t = 1795338317},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 6249, a = 14.317, t = 1795338376},
    ["Upheaval@Locus Dire Bat"] = {n = 5907, a = 17.982, t = 1795338361},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 1615, a = 11.480, t = 0},
    ["Freezebite@Locus Dire Bat"] = {n = 3, a = 2.106, t = 1795332703},
    ["Frostbite@Locus Dire Bat"] = {n = 3, a = 1.536, t = 1795332847},
    ["Herculean Slash@Knotted Root"] = {n = 1, a = 1.100, t = 0},
    ["Herculean Slash@Locus Dire Bat"] = {n = 1, a = 2.455, t = 1795332421},
    ["Power Slash@Locus Dire Bat"] = {n = 45, a = 3.539, t = 1795338302},
    ["Shockwave@Locus Dire Bat"] = {n = 1, a = 1.339, t = 1795337819},
    ["Sickle Moon@Lightfoot Lapinion"] = {n = 1, a = 3.810, t = 0},
    ["Spinning Slash@Knotted Root"] = {n = 1, a = 3.780, t = 0},
    ["Spinning Slash@Lightfoot Lapinion"] = {n = 2, a = 8.060, t = 0},
    ["Spinning Slash@Locus Dire Bat"] = {n = 80, a = 6.726, t = 1795338334},
  },
},
scm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 2073, a = 18.610, t = 0},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 2291, a = 18.640, t = 0},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 2026, a = 23.470, t = 0},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 909, a = 12.725, t = 1795338353},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 18, a = 6.370, t = 0},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 5003, a = 26.381, t = 1795338367},
    ["Upheaval@Locus Dire Bat"] = {n = 3494, a = 29.690, t = 1795338282},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 465, a = 19.620, t = 0},
    ["Herculean Slash@Locus Dire Bat"] = {n = 1, a = 8.092, t = 1795332421},
    ["Power Slash@Locus Dire Bat"] = {n = 8, a = 10.129, t = 1795337905},
    ["Shockwave@Locus Dire Bat"] = {n = 1, a = 3.820, t = 1795337819},
    ["Spinning Slash@Locus Dire Bat"] = {n = 32, a = 12.233, t = 1795338334},
  },
},
used = {
  {"Shadowhammer", "mb", "Scracheebrat", "MB", 2046},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Fudo", 682},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Kasha", 705},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Shoha", 627},
  {"Shadowhammer", "sc", "Scracheebrat", "Savage Blade", 419},
  {"Shadowhammer", "sc", "Shadowhammer", "Full Break", 7},
  {"Shadowhammer", "sc", "Shadowhammer", "Ukko's Fury", 1877},
  {"Shadowhammer", "sc", "Shadowhammer", "Upheaval", 1134},
  {"Shadowhammer", "sc", "Vayne", "Cross Reaper", 86},
  {"Shadowhammer", "sc", "Vayne", "Herculean Slash", 1},
  {"Shadowhammer", "sc", "Vayne", "Power Slash", 8},
  {"Shadowhammer", "sc", "Vayne", "Shockwave", 1},
  {"Shadowhammer", "sc", "Vayne", "Spinning Slash", 32},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 682},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 705},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 627},
  {"Shadowhammer", "scm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 419},
  {"Shadowhammer", "scm", "Shadowhammer", "Full Break@Locus Dire Bat", 7},
  {"Shadowhammer", "scm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 1877},
  {"Shadowhammer", "scm", "Shadowhammer", "Upheaval@Locus Dire Bat", 1134},
  {"Shadowhammer", "scm", "Vayne", "Cross Reaper@Locus Dire Bat", 86},
  {"Shadowhammer", "scm", "Vayne", "Herculean Slash@Locus Dire Bat", 1},
  {"Shadowhammer", "scm", "Vayne", "Power Slash@Locus Dire Bat", 8},
  {"Shadowhammer", "scm", "Vayne", "Shockwave@Locus Dire Bat", 1},
  {"Shadowhammer", "scm", "Vayne", "Spinning Slash@Locus Dire Bat", 32},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Fudo", 1119},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Kasha", 1108},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Shoha", 922},
  {"Shadowhammer", "ws", "Scracheebrat", "Savage Blade", 581},
  {"Shadowhammer", "ws", "Shadowhammer", "Full Break", 1092},
  {"Shadowhammer", "ws", "Shadowhammer", "Ukko's Fury", 2261},
  {"Shadowhammer", "ws", "Shadowhammer", "Upheaval", 2154},
  {"Shadowhammer", "ws", "Vayne", "Cross Reaper", 279},
  {"Shadowhammer", "ws", "Vayne", "Freezebite", 3},
  {"Shadowhammer", "ws", "Vayne", "Frostbite", 3},
  {"Shadowhammer", "ws", "Vayne", "Herculean Slash", 1},
  {"Shadowhammer", "ws", "Vayne", "Power Slash", 46},
  {"Shadowhammer", "ws", "Vayne", "Shockwave", 1},
  {"Shadowhammer", "ws", "Vayne", "Spinning Slash", 80},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 1119},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 1108},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 923},
  {"Shadowhammer", "wsm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 581},
  {"Shadowhammer", "wsm", "Shadowhammer", "Full Break@Locus Dire Bat", 1092},
  {"Shadowhammer", "wsm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 2261},
  {"Shadowhammer", "wsm", "Shadowhammer", "Upheaval@Locus Dire Bat", 2154},
  {"Shadowhammer", "wsm", "Vayne", "Cross Reaper@Locus Dire Bat", 279},
  {"Shadowhammer", "wsm", "Vayne", "Freezebite@Locus Dire Bat", 3},
  {"Shadowhammer", "wsm", "Vayne", "Frostbite@Locus Dire Bat", 3},
  {"Shadowhammer", "wsm", "Vayne", "Herculean Slash@Locus Dire Bat", 1},
  {"Shadowhammer", "wsm", "Vayne", "Power Slash@Locus Dire Bat", 45},
  {"Shadowhammer", "wsm", "Vayne", "Shockwave@Locus Dire Bat", 1},
  {"Shadowhammer", "wsm", "Vayne", "Spinning Slash@Locus Dire Bat", 80},
},
}
