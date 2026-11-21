-- AutoAttack group skillchain knowledge (master) v5.00 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua +2136 new
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- wsm / scm = the same per mob type ("WS@mob").
-- used = {character, kind, player, key, samples}: what of each learning file this
-- master already holds (v4.98) -- only samples past it count as new.
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "5.00",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 588, a = 8.393, t = 1795285707},
    ["Tachi: Kasha"] = {n = 718, a = 8.786, t = 1795285695},
    ["Tachi: Shoha"] = {n = 794, a = 9.246, t = 1795285727},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 108, a = 8.624, t = 1795285727},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 649, a = 2.866, t = 1795285677},
    ["Ukko's Fury"] = {n = 1165, a = 13.221, t = 1795285702},
    ["Upheaval"] = {n = 1130, a = 16.137, t = 1795285721},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 606, a = 12.485, t = 1795285732},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 419, a = 17.590, t = 1795285707},
    ["Tachi: Kasha"] = {n = 533, a = 18.245, t = 1795285623},
    ["Tachi: Shoha"] = {n = 489, a = 23.541, t = 1795285658},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 74, a = 15.342, t = 1795285727},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 4, a = 5.748, t = 1795279918},
    ["Ukko's Fury"] = {n = 873, a = 27.766, t = 1795285702},
    ["Upheaval"] = {n = 821, a = 30.217, t = 1795285712},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 153, a = 20.445, t = 1795285534},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 734, a = 6.358, t = 1795285712},
  },
},
wsm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 562, a = 8.398, t = 1795285707},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 686, a = 8.790, t = 1795285695},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 773, a = 9.245, t = 1795285727},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 92, a = 8.838, t = 1795285727},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 632, a = 2.866, t = 1795285677},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 1138, a = 13.221, t = 1795285702},
    ["Upheaval@Locus Dire Bat"] = {n = 1099, a = 16.137, t = 1795285721},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 605, a = 12.569, t = 1795285707},
  },
},
scm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 410, a = 17.630, t = 1795285707},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 514, a = 18.281, t = 1795285623},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 474, a = 23.568, t = 1795285658},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 63, a = 16.715, t = 1795285727},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 4, a = 5.748, t = 1795279918},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 855, a = 27.769, t = 1795285702},
    ["Upheaval@Locus Dire Bat"] = {n = 814, a = 30.221, t = 1795285712},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 153, a = 20.445, t = 1795285534},
  },
},
used = {
  {"Shadowhammer", "mb", "Scracheebrat", "MB", 124},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Fudo", 69},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Kasha", 80},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Shoha", 97},
  {"Shadowhammer", "sc", "Scracheebrat", "Savage Blade", 14},
  {"Shadowhammer", "sc", "Shadowhammer", "Ukko's Fury", 142},
  {"Shadowhammer", "sc", "Shadowhammer", "Upheaval", 153},
  {"Shadowhammer", "sc", "Vayne", "Cross Reaper", 33},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 69},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 80},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 97},
  {"Shadowhammer", "scm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 14},
  {"Shadowhammer", "scm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 142},
  {"Shadowhammer", "scm", "Shadowhammer", "Upheaval@Locus Dire Bat", 153},
  {"Shadowhammer", "scm", "Vayne", "Cross Reaper@Locus Dire Bat", 33},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Fudo", 100},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Kasha", 122},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Shoha", 155},
  {"Shadowhammer", "ws", "Scracheebrat", "Savage Blade", 18},
  {"Shadowhammer", "ws", "Shadowhammer", "Full Break", 115},
  {"Shadowhammer", "ws", "Shadowhammer", "Ukko's Fury", 203},
  {"Shadowhammer", "ws", "Shadowhammer", "Upheaval", 198},
  {"Shadowhammer", "ws", "Vayne", "Cross Reaper", 107},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 100},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 122},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 156},
  {"Shadowhammer", "wsm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 18},
  {"Shadowhammer", "wsm", "Shadowhammer", "Full Break@Locus Dire Bat", 115},
  {"Shadowhammer", "wsm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 203},
  {"Shadowhammer", "wsm", "Shadowhammer", "Upheaval@Locus Dire Bat", 198},
  {"Shadowhammer", "wsm", "Vayne", "Cross Reaper@Locus Dire Bat", 106},
},
}
