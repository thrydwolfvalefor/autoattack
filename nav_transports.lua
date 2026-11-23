-- nav_transports.lua -- AutoAttack "aa nav": NPCs that move you to another zone (v5.11)
-- From the Topaz server project's NPC scripts (scripts/zones/*/npcs: onEventFinish -> setPos).
-- {name, zone, x, y, to zone, landing x, landing y, menu (csid), option, auto}
-- auto = the script picks the warp by menu + option only; otherwise AA opens the menu,
-- you pick, and AA remembers your choice (data/nav_learned.lua).
return {
    {"Stone Door", 9, -380, 330, 22, -15, -120, 2, 1, false},  -- PsoXja/_i99
    {"Stone Door", 9, 342, -50, 111, 260, -20, 26, 1, false},  -- PsoXja/_090
    {"Tarnotik", 11, 161, -56, 13, -116, -620, 32, nil, false},  -- Oldton_Movalpolos/Tarnotik
    {"Sleakachiq", 12, 163, 137, 13, -94, -584, 28, 2, false},  -- Newton_Movalpolos/Sleakachiq
    {"Sleakachiq", 12, 163, 137, 106, 448, 730, 28, 1, false},  -- Newton_Movalpolos/Sleakachiq
    {"Cermet Gate", 14, -216, 280, 16, 92, 80, 150, 1, false},  -- Hall_of_Transference/_0e0
    {"Cermet Gate", 14, -216, -280, 18, 186, -52, 150, 1, false},  -- Hall_of_Transference/_0e1
    {"Cermet Gate", 14, 280, -16, 20, -93, 171, 150, 1, false},  -- Hall_of_Transference/_0e2
    {"Large Apparatus", 14, -236, 290, 16, 92, 80, 160, nil, false},  -- Hall_of_Transference/_0e3
    {"Large Apparatus", 14, -236, -270, 18, 186, -52, 160, nil, false},  -- Hall_of_Transference/_0e5
    {"Large Apparatus", 14, 270, -36, 20, -93, 171, 160, nil, false},  -- Hall_of_Transference/_0e7
    {"Radiant Aureole", 17, 0, 360, 102, 340, -60, 14, 1, true},  -- Spire_of_Holla/Radiant_Aureole
    {"Radiant Aureole", 19, 0, -360, 108, 140, 220, 14, 1, true},  -- Spire_of_Dem/Radiant_Aureole
    {"Radiant Aureole", 21, 0, -360, 117, 180, 260, 14, 1, true},  -- Spire_of_Mea/Radiant_Aureole
    {"Radiant Aureole", 23, 0, -360, 9, -380, 334, 15, 1, true},  -- Spire_of_Vahzl/Radiant_Aureole
    {"Dilapidated Gate", 25, -260, 280, 29, 729, 410, 8, 1, false},  -- Misareaux_Coast/_0p2
    {"Iron Gate", 25, 56, 740, 28, -220, 80, 9, 1, false},  -- Misareaux_Coast/_0p8
    {"Spatial Displacement", 25, -544, 358, 29, 730, 407, 551, 2, false},  -- Misareaux_Coast/Spatial_Displacement
    {"Spatial Displacement", 25, -544, 358, 30, 733, -507, 8, nil, false},  -- Misareaux_Coast/Spatial_Displacement
    {"Sewer Entrance", 26, 28, 46, 27, 260, -284, 502, 1, false},  -- Tavnazian_Safehold/_0q1
    {"Spatial Displacement", 29, 735, -704, 25, -539, 359, 10, 1, false},  -- Riverne-Site_B01/Spatial_Displacement
    {"Spatial Displacement", 29, 735, -704, 31, 13, -540, 33, 1, false},  -- Riverne-Site_B01/Spatial_Displacement
    {"Spatial Displacement", 30, 655, 583, 25, -539, 359, 10, 1, false},  -- Riverne-Site_A01/Spatial_Displacement
    {"Spatial Displacement", 30, 655, 583, 31, 13, -540, 35, 1, false},  -- Riverne-Site_A01/Spatial_Displacement
    {"Spatial Displacement", 31, 19, -540, 25, -539, 359, 7, 1, false},  -- Monarch_Linn/Spatial_Displacement
    {"Spatial Displacement", 31, 19, -540, 29, -534, 504, 10, 1, false},  -- Monarch_Linn/Spatial_Displacement
    {"Spatial Displacement", 31, 19, -540, 30, -509, -388, 11, 1, false},  -- Monarch_Linn/Spatial_Displacement
    {"Auroral Updraft", 33, -32, -619, 32, 612, 773, 150, 1, false},  -- AlTaieu/Auroral_Updraft
    {"Crystalline Field", 33, 0, -460, 34, -20, -355, 100, 1, false},  -- AlTaieu/_0x0
    {"Gate of the Gods", 34, -20, -280, 35, -420, 248, 52, 1, false},  -- Grand_Palace_of_HuXzoi/_iya
    {"Particle Gate", 35, 420, 440, 34, -20, -355, 112, 1, false},  -- The_Garden_of_RuHmet/_0zs
    {"Pursuivant", 44, 516, 545, 244, 0, 23, 3, 1, true},  -- Abdhaljs_Isle-Purgonorgo/Pursuivant
    {"Shihu-Danhu", 48, 63, -51, 105, 382, -106, 103, 1, false},  -- Al_Zahbi/Shihu-Danhu
    {"Shihu-Danhu", 48, 63, -51, 110, 214, 420, 103, 1, false},  -- Al_Zahbi/Shihu-Danhu
    {"Shihu-Danhu", 48, 63, -51, 120, -327, 438, 103, 1, false},  -- Al_Zahbi/Shihu-Danhu
    {"Shihu-Danhu", 48, 63, -51, 126, 167, -213, 103, 1, false},  -- Al_Zahbi/Shihu-Danhu
    {"Shihu-Danhu", 48, 63, -51, 243, -1, -53, 103, 1, false},  -- Al_Zahbi/Shihu-Danhu
    {"Gate: The Pit", 50, 80, -108, 71, -600, 40, 133, 1, true},  -- Aht_Urhgan_Whitegate/_1e9
    {"Ironbound Gate", 50, -43, 56, 51, 690, 220, 131, 1, false},  -- Aht_Urhgan_Whitegate/Ironbound_Gate
    {"Ironbound Gate", 50, -43, 56, 52, 570, 140, 130, 1, false},  -- Aht_Urhgan_Whitegate/Ironbound_Gate
    {"Kaduru-Haiduru", 50, -71, -71, 243, 0, -6, nil, nil, false},  -- Aht_Urhgan_Whitegate/Kaduru-Haiduru
    {"Postern", 51, 693, 220, 50, -37, -56, 502, 1, true},  -- Wajaom_Woodlands/_1f0
    {"Kamih Mapokhalam", 52, 20, 598, 72, 325, -620, 121, nil, false},  -- Bhaflau_Thickets/Kamih_Mapokhalam
    {"Postern", 52, 574, 140, 50, -37, 56, 502, 1, true},  -- Bhaflau_Thickets/_1g0
    {"Runic Seal", 52, -180, -834, 66, 0, 0, 505, 4, false},  -- Bhaflau_Thickets/_1g2
    {"Cutter", 54, -465, -394, 60, 0, 0, nil, 4, false},  -- Arrapago_Reef/Cutter
    {"Runic Seal", 54, 37, 620, 55, 0, 0, nil, 4, false},  -- Arrapago_Reef/_jic
    {"Rune of Release", 55, 412, 54, 54, 0, 0, 102, nil, false},  -- Ilrusi_Atoll/Rune_of_Release
    {"Rune of Release", 56, -60, 415, 79, 0, 0, 102, nil, false},  -- Periqia/Rune_of_Release
    {"Runic Seal", 61, 704, 384, 63, 0, 0, nil, 4, false},  -- Mount_Zhayolm/_1p3
    {"Rune of Release", 63, 410, 301, 61, 0, 0, 102, nil, false},  -- Lebros_Cavern/Rune_of_Release
    {"Rune of Release", 66, -55, -103, 52, 0, 0, 102, nil, false},  -- Mamool_Ja_Training_Grounds/Rune_of_Release
    {"Rune of Release", 69, 476, 40, 79, 0, 0, 102, nil, false},  -- Leujaoam_Sanctum/Rune_of_Release
    {"Gate: The Pit", 71, -604, 40, 50, 80, -105, 51, 1, true},  -- The_Colosseum/_1e9
    {"Gilded Gateway", 72, -580, -160, 74, 0, 0, nil, 4, false},  -- Alzadaal_Undersea_Ruins/_20u
    {"Gilded Gateway", 72, 580, 440, 76, 0, 0, nil, 4, false},  -- Alzadaal_Undersea_Ruins/_20t
    {"Runic Seal", 72, 124, 20, 77, 0, 0, nil, nil, false},  -- Alzadaal_Undersea_Ruins/_20m
    {"Kwadaaf", 79, -639, -260, 72, -235, 220, 223, nil, false},  -- Caedarva_Mire/Kwadaaf
    {"Nasheefa", 79, -441, -740, 72, -220, 475, 183, nil, false},  -- Caedarva_Mire/Nasheefa
    {"Nuimahn", 79, -380, -281, 72, -515, 740, 203, nil, false},  -- Caedarva_Mire/Nuimahn
    {"Runic Seal", 79, -354, -20, 56, 0, 0, nil, 4, false},  -- Caedarva_Mire/_273
    {"Runic Seal", 79, 487, -500, 69, 0, 0, 140, 4, false},  -- Caedarva_Mire/_272
    {"Tyamah", 79, 321, -700, 72, -20, 835, 163, nil, false},  -- Caedarva_Mire/Tyamah
    {"Alfred", 80, 95, -59, 81, 94, 266, 200, 1, false},  -- Southern_San_dOria_[S]/Alfred
    {"Eauvague, T.K.", 80, 105, -53, 81, 94, 266, 200, 1, true},  -- Southern_San_dOria_[S]/Eauvague_TK
    {"Red Canyon", 87, -229, 95, 88, 380, 147, 200, 1, true},  -- Bastok_Markets_[S]/Red_Canyon
    {"Ajen-Myoojen", 94, -45, 239, 95, 320, -46, 200, 1, true},  -- Windurst_Waters_[S]/Ajen-Myoojen
    {"Iron Portcullis", 97, 737, -40, 99, -239, -20, 104, 1, true},  -- Meriphataud_Mountains_[S]/Iron_Portcullis
    {"Shattered Telepoint", 102, 340, -60, 14, -267, 280, 202, 0, false},  -- La_Theine_Plateau/Shattered_Telepoint
    {"Shattered Telepoint", 102, 340, -60, 16, 92, 80, 201, nil, false},  -- La_Theine_Plateau/Shattered_Telepoint
    {"Cavernous Maw", 104, 246, 6, 217, -351, 700, 47, 1, false},  -- Jugner_Forest/Cavernous_Maw_2
    {"Cavernous Maw", 106, -78, 600, 254, -555, -760, 908, 1, false},  -- North_Gustaberg/Cavernous_Maw_2
    {"Shattered Telepoint", 108, 140, 220, 14, -267, -280, 913, 0, false},  -- Konschtat_Highlands/Shattered_Telepoint
    {"Shattered Telepoint", 108, 140, 220, 18, 186, -52, 912, nil, false},  -- Konschtat_Highlands/Shattered_Telepoint
    {"Iron Grate", 111, 241, -20, 9, 396, -20, nil, 1, false},  -- Beaucedine_Glacier/Iron_Grate
    {"Shattered Telepoint", 117, 180, 260, 14, 280, -67, 913, 0, false},  -- Tahrongi_Canyon/Shattered_Telepoint
    {"Shattered Telepoint", 117, 180, 260, 20, -93, 171, 912, nil, false},  -- Tahrongi_Canyon/Shattered_Telepoint
    {"Dock Lever", 143, 130, 16, 172, -73, 60, 14, nil, false},  -- Palborough_Mines/_3z2
    {"Cermet Door", 158, 320, 20, 184, 524, 20, 2, 1, true},  -- Upper_Delkfutts_Tower/_4e1
    {"Transporter", 169, 183, -60, 242, 0, -22, 71, 1, true},  -- Toraimarai_Canal/Transporter
    {"Shimmering Circle", 180, -588, -626, 130, 291, -401, 12, 1, true},  -- LaLoff_Amphitheater/qm0_1
    {"Cermet Door", 184, 520, 20, 158, 313, 20, 20, 1, true},  -- Lower_Delkfutts_Tower/Cermet_Door
    {"Wooden Shutter", 231, -125, 193, 2, -480, 669, 5, 1, true},  -- Northern_San_dOria/Wooden_Shutter
    {"Faurie", 233, 1, -15, 231, 0, 100, 506, 0, true},  -- Chateau_dOraguille/Faurie
    {"Tonana", 238, -2, 99, 241, 109, -134, 571, 1, true},  -- Windurst_Waters/Tonana
    {"Komulili", 239, 67, -44, 240, -112, 92, 338, 1, true},  -- Windurst_Walls/Komulili
    {"Machu-Kuchu", 240, -112, 101, 239, 66, -50, 338, 1, true},  -- Port_Windurst/Machu-Kuchu
    {"Pattsu-Yabittsu", 241, 106, -137, 238, -2, 103, 411, 1, true},  -- Windurst_Woods/Pattsu-Yabittsu
    {"Door:Vestal Chamber", 242, 0, 40, 239, 0, 130, 407, nil, false},  -- Heavens_Tower/_6q2
    {"Maat", 243, 11, 119, 139, -511, -211, 64, 1, false},  -- RuLude_Gardens/Maat
    {"Maat", 243, 11, 119, 144, -350, -260, 64, 1, false},  -- RuLude_Gardens/Maat
    {"Maat", 243, 11, 119, 146, 299, 354, 64, 1, false},  -- RuLude_Gardens/Maat
    {"Maat", 243, 11, 119, 168, -220, 4, 64, 1, false},  -- RuLude_Gardens/Maat
    {"Maat", 243, 11, 119, 206, -225, 20, 64, 1, false},  -- RuLude_Gardens/Maat
    {"Nomad Moogle", 243, 10, 122, 139, -511, -211, 10045, 14, false},  -- RuLude_Gardens/Nomad_Moogle
    {"Nomad Moogle", 243, 10, 122, 144, -350, -260, 10045, 19, false},  -- RuLude_Gardens/Nomad_Moogle
    {"Nomad Moogle", 243, 10, 122, 146, 299, 354, 10045, 20, false},  -- RuLude_Gardens/Nomad_Moogle
    {"Nomad Moogle", 243, 10, 122, 206, -225, 20, 10045, 21, false},  -- RuLude_Gardens/Nomad_Moogle
    {"Pherimociel", 243, -32, 68, 51, 0, 0, 10098, nil, false},  -- RuLude_Gardens/Pherimociel
    {"Afdeen", 244, 1, 22, 44, 0, 0, 179, 1, true},  -- Upper_Jeuno/Afdeen
    {"Mapitoto", 244, -54, 86, 105, 475, -159, nil, 1, false},  -- Upper_Jeuno/Mapitoto
    {"Domenic", 245, 33, -15, 139, 0, 0, 10115, 2, false},  -- Lower_Jeuno/Domenic
    {"Domenic", 245, 33, -15, 144, 0, 0, 10115, 3, false},  -- Lower_Jeuno/Domenic
    {"Domenic", 245, 33, -15, 146, 0, 0, 10115, 4, false},  -- Lower_Jeuno/Domenic
    {"Domenic", 245, 33, -15, 206, 0, 0, 10115, 5, false},  -- Lower_Jeuno/Domenic
    {"Horst", 246, -54, -10, 102, -562, 640, 339, 260, false},  -- Port_Jeuno/Horst
    {"Horst", 246, -54, -10, 103, 362, -119, 339, 276, false},  -- Port_Jeuno/Horst
    {"Horst", 246, -54, -10, 104, 241, 11, 339, 272, false},  -- Port_Jeuno/Horst
    {"Horst", 246, -54, -10, 106, -71, 601, 339, 292, false},  -- Port_Jeuno/Horst
    {"Horst", 246, -54, -10, 107, 337, -675, 339, 284, false},  -- Port_Jeuno/Horst
    {"Horst", 246, -54, -10, 108, 91, -582, 339, 264, false},  -- Port_Jeuno/Horst
    {"Horst", 246, -54, -10, 112, 269, -75, 339, 288, false},  -- Port_Jeuno/Horst
    {"Horst", 246, -54, -10, 117, -28, -680, 339, 268, false},  -- Port_Jeuno/Horst
    {"Horst", 246, -54, -10, 118, -338, 47, 339, 280, false},  -- Port_Jeuno/Horst
    {"Pacomart", 248, -14, -31, 252, 0, 0, 179, 1, false},  -- Selbina/Pacomart
    {"Tonasav", 249, -18, 28, 252, 0, 0, 371, 1, false},  -- Mhaura/Tonasav
    {"Dangueubert", 256, 5, -137, 280, 0, 0, 546, 1, false},  -- Western_Adoulin/Dangueubert
    {"Pagnelle", 256, -8, -100, 258, 0, 0, 5032, nil, false},  -- Western_Adoulin/Pagnelle
    {"Liseran Door: Entrance", 267, -287, 60, 274, -40, -20, 34, 1, true},  -- Kamihr_Drifts/Liseran_Door_Entrance
    {"Liseran Door: Exit", 274, -35, -20, 267, -280, 60, 28, 1, true},  -- Outer_RaKaznar/Liseran_Door_Exit
}
