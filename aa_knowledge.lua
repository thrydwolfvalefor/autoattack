-- AutoAttack group skillchain knowledge (master) v4.96 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "4.96",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 65, a = 8.094, t = 1795257240},
    ["Tachi: Kasha"] = {n = 78, a = 8.450, t = 1795257250},
    ["Tachi: Shoha"] = {n = 62, a = 7.557, t = 1795257203},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 33, a = 7.253, t = 1795257256},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 70, a = 2.873, t = 1795257274},
    ["Ukko's Fury"] = {n = 125, a = 13.598, t = 1795257261},
    ["Upheaval"] = {n = 128, a = 15.769, t = 1795257250},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 52, a = 10.455, t = 1795257244},
    ["Ruinator"] = {n = 16, a = 0.243, t = 1795257121},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 40, a = 17.770, t = 1795257240},
    ["Tachi: Kasha"] = {n = 63, a = 16.090, t = 1795257250},
    ["Tachi: Shoha"] = {n = 38, a = 16.280, t = 1795257195},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 23, a = 10.920, t = 1795257256},
  },
  ["Shadowhammer"] = {
    ["Ukko's Fury"] = {n = 90, a = 27.322, t = 1795257261},
    ["Upheaval"] = {n = 67, a = 25.922, t = 1795257191},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 3, a = 23.985, t = 1795257109},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 80, a = 6.616, t = 1795257236},
  },
},
wsm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 39, a = 8.598, t = 1795257240},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 46, a = 8.697, t = 1795257250},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 41, a = 7.136, t = 1795257203},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 17, a = 7.126, t = 1795257256},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 52, a = 2.921, t = 1795257227},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 98, a = 13.543, t = 1795257261},
    ["Upheaval@Locus Dire Bat"] = {n = 97, a = 16.233, t = 1795257250},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 52, a = 10.455, t = 1795257244},
    ["Ruinator@Locus Dire Bat"] = {n = 16, a = 0.243, t = 1795257121},
  },
},
scm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 31, a = 19.234, t = 1795257240},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 44, a = 17.505, t = 1795257250},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 23, a = 17.771, t = 1795257195},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 12, a = 13.462, t = 1795257256},
  },
  ["Shadowhammer"] = {
    ["Ukko's Fury@Locus Dire Bat"] = {n = 72, a = 28.039, t = 1795257261},
    ["Upheaval@Locus Dire Bat"] = {n = 60, a = 27.124, t = 1795257191},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 3, a = 23.985, t = 1795257109},
  },
},
}
