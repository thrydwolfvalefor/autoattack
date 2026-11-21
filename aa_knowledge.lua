-- AutoAttack group skillchain knowledge (master) v4.94 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "4.94",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 26, a = 7.338, t = 1795248233},
    ["Tachi: Kasha"] = {n = 32, a = 8.094, t = 1795248371},
    ["Tachi: Shoha"] = {n = 21, a = 8.378, t = 1795248356},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 20, a = 6.968, t = 1795254591},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 27, a = 2.932, t = 1795254598},
    ["Ukko's Fury"] = {n = 41, a = 14.019, t = 1795254574},
    ["Upheaval"] = {n = 52, a = 15.588, t = 1795254586},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 11, a = 10.258, t = 1795254574},
    ["Ruinator"] = {n = 3, a = 0.243, t = 1795254491},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 9, a = 12.727, t = 1795248097},
    ["Tachi: Kasha"] = {n = 19, a = 12.812, t = 1795248204},
    ["Tachi: Shoha"] = {n = 15, a = 13.993, t = 1795248356},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 14, a = 8.409, t = 1795254511},
  },
  ["Shadowhammer"] = {
    ["Ukko's Fury"] = {n = 29, a = 26.370, t = 1795254565},
    ["Upheaval"] = {n = 23, a = 24.199, t = 1795254553},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 21, a = 6.121, t = 1795254566},
  },
},
wsm = {
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 4, a = 5.285, t = 1795254591},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 9, a = 3.163, t = 1795254545},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 14, a = 14.442, t = 1795254574},
    ["Upheaval@Locus Dire Bat"] = {n = 21, a = 17.462, t = 1795254586},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 11, a = 10.258, t = 1795254574},
    ["Ruinator@Locus Dire Bat"] = {n = 3, a = 0.243, t = 1795254491},
  },
},
scm = {
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 3, a = 9.370, t = 1795254511},
  },
  ["Shadowhammer"] = {
    ["Ukko's Fury@Locus Dire Bat"] = {n = 11, a = 29.508, t = 1795254565},
    ["Upheaval@Locus Dire Bat"] = {n = 16, a = 27.949, t = 1795254553},
  },
},
}
