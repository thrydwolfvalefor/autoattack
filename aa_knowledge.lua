-- AutoAttack group skillchain knowledge (master) v4.95 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "4.95",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 26, a = 7.338, t = 1795248233},
    ["Tachi: Kasha"] = {n = 32, a = 8.094, t = 1795248371},
    ["Tachi: Shoha"] = {n = 21, a = 8.378, t = 1795248356},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 28, a = 6.882, t = 1795255219},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 35, a = 2.900, t = 1795255235},
    ["Ukko's Fury"] = {n = 53, a = 14.025, t = 1795255224},
    ["Upheaval"] = {n = 75, a = 16.163, t = 1795255249},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 28, a = 8.564, t = 1795255238},
    ["Ruinator"] = {n = 7, a = 0.243, t = 1795255244},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 9, a = 12.727, t = 1795248097},
    ["Tachi: Kasha"] = {n = 19, a = 12.812, t = 1795248204},
    ["Tachi: Shoha"] = {n = 15, a = 13.993, t = 1795248356},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 20, a = 10.089, t = 1795255219},
  },
  ["Shadowhammer"] = {
    ["Ukko's Fury"] = {n = 39, a = 26.274, t = 1795255224},
    ["Upheaval"] = {n = 32, a = 25.572, t = 1795255211},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 33, a = 6.935, t = 1795255215},
  },
},
wsm = {
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 12, a = 6.207, t = 1795255219},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 18, a = 3.014, t = 1795255235},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 26, a = 14.259, t = 1795255224},
    ["Upheaval@Locus Dire Bat"] = {n = 43, a = 17.405, t = 1795255211},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 28, a = 8.564, t = 1795255238},
    ["Ruinator@Locus Dire Bat"] = {n = 7, a = 0.243, t = 1795255244},
  },
},
scm = {
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 9, a = 12.461, t = 1795255219},
  },
  ["Shadowhammer"] = {
    ["Ukko's Fury@Locus Dire Bat"] = {n = 21, a = 27.835, t = 1795255224},
    ["Upheaval@Locus Dire Bat"] = {n = 25, a = 28.358, t = 1795255211},
  },
},
}
