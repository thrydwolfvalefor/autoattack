-- AutoAttack group skillchain knowledge (master) v4.98 -- built by make_release.py
-- from: aa_knowledge.lua, aa_learned_Shadowhammer.lua (old format)
-- [kind][player][weapon skill] = {n = samples, a = average (thousands), t = last update}
-- ws = WS damage; sc = skillchain damage when this WS closes it, as Light-equivalent
-- (Light 1.0, level 2 0.55, level 1 0.25, Light on Light 1.4); mb = magic bursts
-- wsm / scm = the same per mob type ("WS@mob").
-- used = {character, kind, player, key, samples}: what of each learning file this
-- master already holds (v4.98) -- only samples past it count as new.
-- Shipped by every release; aa update replaces it. Your own learning is in
-- data/aa_learned_<Character>.lua and is never replaced.
return {
version = "4.98",
ws = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 488, a = 8.642, t = 1795279879},
    ["Tachi: Kasha"] = {n = 596, a = 9.235, t = 1795279948},
    ["Tachi: Shoha"] = {n = 639, a = 9.219, t = 1795279978},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 90, a = 8.625, t = 1795279897},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 534, a = 2.834, t = 1795279918},
    ["Ukko's Fury"] = {n = 962, a = 13.647, t = 1795279932},
    ["Upheaval"] = {n = 932, a = 16.971, t = 1795279955},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 499, a = 12.401, t = 1795279950},
  },
},
sc = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo"] = {n = 350, a = 18.346, t = 1795279879},
    ["Tachi: Kasha"] = {n = 453, a = 17.761, t = 1795279948},
    ["Tachi: Shoha"] = {n = 392, a = 23.291, t = 1795279853},
  },
  ["Scracheebrat"] = {
    ["Savage Blade"] = {n = 60, a = 15.248, t = 1795279238},
  },
  ["Shadowhammer"] = {
    ["Full Break"] = {n = 4, a = 5.748, t = 1795279918},
    ["Ukko's Fury"] = {n = 731, a = 28.273, t = 1795279932},
    ["Upheaval"] = {n = 668, a = 29.407, t = 1795279941},
  },
  ["Vayne"] = {
    ["Cross Reaper"] = {n = 120, a = 20.417, t = 1795279809},
  },
},
mb = {
  ["Scracheebrat"] = {
    ["MB"] = {n = 610, a = 6.489, t = 1795279893},
  },
},
wsm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 462, a = 8.682, t = 1795279879},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 564, a = 9.255, t = 1795279948},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 617, a = 9.214, t = 1795279935},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 74, a = 8.892, t = 1795279897},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 517, a = 2.836, t = 1795279918},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 935, a = 13.647, t = 1795279932},
    ["Upheaval@Locus Dire Bat"] = {n = 901, a = 16.978, t = 1795279955},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 499, a = 12.401, t = 1795279950},
  },
},
scm = {
  ["Mythrandiir"] = {
    ["Tachi: Fudo@Locus Dire Bat"] = {n = 341, a = 18.472, t = 1795279879},
    ["Tachi: Kasha@Locus Dire Bat"] = {n = 434, a = 17.885, t = 1795279948},
    ["Tachi: Shoha@Locus Dire Bat"] = {n = 377, a = 23.535, t = 1795279853},
  },
  ["Scracheebrat"] = {
    ["Savage Blade@Locus Dire Bat"] = {n = 49, a = 16.843, t = 1795279238},
  },
  ["Shadowhammer"] = {
    ["Full Break@Locus Dire Bat"] = {n = 4, a = 5.748, t = 1795279918},
    ["Ukko's Fury@Locus Dire Bat"] = {n = 713, a = 28.298, t = 1795279932},
    ["Upheaval@Locus Dire Bat"] = {n = 661, a = 29.446, t = 1795279941},
  },
  ["Vayne"] = {
    ["Cross Reaper@Locus Dire Bat"] = {n = 120, a = 20.417, t = 1795279809},
  },
},
used = {
},
}
