-- AutoAttack group skillchain knowledge (master) v4.92 -- built by make_release.py
-- from: aa_learned_Shadowhammer.lua
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "4.92",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 26, a = 7.338, t = 1795248233},
    ["Tachi: Kasha"] = {n = 32, a = 8.094, t = 1795248371},
    ["Tachi: Shoha"] = {n = 21, a = 8.378, t = 1795248356},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 16, a = 7.388, t = 1795248408},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 17, a = 2.779, t = 1795248308},
    ["Ukko's Fury"] = {n = 27, a = 13.799, t = 1795248337},
    ["Upheaval"] = {n = 31, a = 14.317, t = 1795248352},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 9, a = 12.727, t = 1795248097},
    ["Tachi: Kasha"] = {n = 19, a = 12.812, t = 1795248204},
    ["Tachi: Shoha"] = {n = 15, a = 13.993, t = 1795248356},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 11, a = 8.147, t = 1795248240},
  },
  ["Shadowhammer"] = {
    ["Ukko's Fury"] = {n = 18, a = 24.452, t = 1795248244},
    ["Upheaval"] = {n = 7, a = 15.627, t = 1795248314},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 5, a = 0.075, t = 1795247545},
  },
},
wsm = {
},
scm = {
},
}
