-- AutoAttack group skillchain knowledge (master) v5.02 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua +5088 new
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- wsm / scm = the same per mob type ("WS@mob").
-- used = {character, kind, player, key, samples}: what of each learning file this
-- master already holds (v4.98) -- only samples past it count as new.
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "5.02",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 945, a = 9.804, t = 1795302553},
    ["Tachi: Kasha"] = {n = 1126, a = 9.853, t = 1795302571},
    ["Tachi: Shoha"] = {n = 1138, a = 9.826, t = 1795302530},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 269, a = 8.214, t = 1795302453},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 975, a = 3.205, t = 1795302567},
    ["Ukko's Fury"] = {n = 1830, a = 14.756, t = 1795302576},
    ["Upheaval"] = {n = 1728, a = 18.652, t = 1795302535},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 778, a = 11.482, t = 1795293414},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 668, a = 21.131, t = 1795302553},
    ["Tachi: Kasha"] = {n = 805, a = 20.865, t = 1795302571},
    ["Tachi: Shoha"] = {n = 717, a = 22.425, t = 1795302427},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 180, a = 14.701, t = 1795302453},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 5, a = 6.039, t = 1795295460},
    ["Ukko's Fury"] = {n = 1399, a = 31.619, t = 1795302548},
    ["Upheaval"] = {n = 1155, a = 35.605, t = 1795302535},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 206, a = 19.442, t = 1795293374},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 1362, a = 7.780, t = 1795302574},
  },
},
wsm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 919, a = 9.804, t = 1795302553},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 1094, a = 9.853, t = 1795302571},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 1117, a = 9.826, t = 1795302530},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 253, a = 8.214, t = 1795302453},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 958, a = 3.205, t = 1795302567},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 1803, a = 14.756, t = 1795302576},
    ["Upheaval@Locus Dire Bat"] = {n = 1697, a = 18.652, t = 1795302535},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 778, a = 11.482, t = 1795293414},
  },
},
scm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 659, a = 21.131, t = 1795302553},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 786, a = 20.865, t = 1795302571},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 702, a = 22.425, t = 1795302427},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 169, a = 14.703, t = 1795302453},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 5, a = 6.039, t = 1795295460},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 1381, a = 31.619, t = 1795302548},
    ["Upheaval@Locus Dire Bat"] = {n = 1148, a = 35.605, t = 1795302535},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 206, a = 19.442, t = 1795293374},
  },
},
used = {
  {"Shadowhammer", "mb", "Scracheebrat", "MB", 752},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Fudo", 318},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Kasha", 352},
  {"Shadowhammer", "sc", "Mythrandiir", "Tachi: Shoha", 325},
  {"Shadowhammer", "sc", "Scracheebrat", "Savage Blade", 120},
  {"Shadowhammer", "sc", "Shadowhammer", "Full Break", 1},
  {"Shadowhammer", "sc", "Shadowhammer", "Ukko's Fury", 668},
  {"Shadowhammer", "sc", "Shadowhammer", "Upheaval", 487},
  {"Shadowhammer", "sc", "Vayne", "Cross Reaper", 86},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 318},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 352},
  {"Shadowhammer", "scm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 325},
  {"Shadowhammer", "scm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 120},
  {"Shadowhammer", "scm", "Shadowhammer", "Full Break@Locus Dire Bat", 1},
  {"Shadowhammer", "scm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 668},
  {"Shadowhammer", "scm", "Shadowhammer", "Upheaval@Locus Dire Bat", 487},
  {"Shadowhammer", "scm", "Vayne", "Cross Reaper@Locus Dire Bat", 86},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Fudo", 457},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Kasha", 530},
  {"Shadowhammer", "ws", "Mythrandiir", "Tachi: Shoha", 499},
  {"Shadowhammer", "ws", "Scracheebrat", "Savage Blade", 179},
  {"Shadowhammer", "ws", "Shadowhammer", "Full Break", 441},
  {"Shadowhammer", "ws", "Shadowhammer", "Ukko's Fury", 868},
  {"Shadowhammer", "ws", "Shadowhammer", "Upheaval", 796},
  {"Shadowhammer", "ws", "Vayne", "Cross Reaper", 279},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Fudo@Locus Dire Bat", 457},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Kasha@Locus Dire Bat", 530},
  {"Shadowhammer", "wsm", "Mythrandiir", "Tachi: Shoha@Locus Dire Bat", 500},
  {"Shadowhammer", "wsm", "Scracheebrat", "Savage Blade@Locus Dire Bat", 179},
  {"Shadowhammer", "wsm", "Shadowhammer", "Full Break@Locus Dire Bat", 441},
  {"Shadowhammer", "wsm", "Shadowhammer", "Ukko's Fury@Locus Dire Bat", 868},
  {"Shadowhammer", "wsm", "Shadowhammer", "Upheaval@Locus Dire Bat", 796},
  {"Shadowhammer", "wsm", "Vayne", "Cross Reaper@Locus Dire Bat", 279},
},
}
