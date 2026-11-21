-- AutoAttack group skillchain knowledge (master) v4.97 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "4.97",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 74, a = 8.107, t = 1795257664},
    ["Tachi: Kasha"] = {n = 86, a = 8.484, t = 1795257656},
    ["Tachi: Shoha"] = {n = 73, a = 7.847, t = 1795257672},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 34, a = 7.453, t = 1795257490},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 80, a = 2.806, t = 1795257692},
    ["Ukko's Fury"] = {n = 137, a = 13.476, t = 1795257676},
    ["Upheaval"] = {n = 147, a = 15.818, t = 1795257704},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 61, a = 10.413, t = 1795257686},
    ["Ruinator"] = {n = 19, a = 0.243, t = 1795257706},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 48, a = 18.080, t = 1795257664},
    ["Tachi: Kasha"] = {n = 71, a = 16.215, t = 1795257656},
    ["Tachi: Shoha"] = {n = 45, a = 17.469, t = 1795257672},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 23, a = 10.920, t = 1795257256},
  },
  ["Shadowhammer"] = {
    ["Ukko's Fury"] = {n = 101, a = 27.118, t = 1795257676},
    ["Upheaval"] = {n = 80, a = 26.211, t = 1795257650},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 4, a = 22.000, t = 1795257479},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 92, a = 6.764, t = 1795257680},
  },
},
wsm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 48, a = 8.525, t = 1795257664},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 54, a = 8.715, t = 1795257656},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 52, a = 7.633, t = 1795257672},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 18, a = 7.510, t = 1795257490},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 63, a = 2.813, t = 1795257692},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 110, a = 13.397, t = 1795257676},
    ["Upheaval@Locus Dire Bat"] = {n = 116, a = 16.218, t = 1795257704},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 61, a = 10.413, t = 1795257686},
    ["Ruinator@Locus Dire Bat"] = {n = 19, a = 0.243, t = 1795257706},
  },
},
scm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 39, a = 19.315, t = 1795257664},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 52, a = 17.459, t = 1795257656},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 30, a = 19.206, t = 1795257672},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 12, a = 13.462, t = 1795257256},
  },
  ["Shadowhammer"] = {
    ["Ukko's Fury@Locus Dire Bat"] = {n = 83, a = 27.696, t = 1795257676},
    ["Upheaval@Locus Dire Bat"] = {n = 73, a = 27.227, t = 1795257650},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 4, a = 22.000, t = 1795257479},
  },
},
}
