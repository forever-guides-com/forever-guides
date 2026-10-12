-- Dungeon map tiles and boss portraits as FileDataIDs (generated, do not edit).
-- Data of the Forever Guides database, client build 1.60.1.70291 (enUS), retrieved 2026-10-07.
-- Whether a file exists in the Forever client is only known in game.
-- maps[instance].floors[n].fid holds the 12 tiles in grid order (4 columns by 3 rows).
-- Minimap maps (Ruins of Lordaeron, Dalaran, ...): grid = { x, y, cols, rows, fid, world } is the crop of the
-- tiles World/Minimaps/<MapID>/map<x>_<y>.blp, floors[1] = { fid, cols, rows } the same tiles as the one floor,
-- tiles every tile of the map, soon = true while the crop is open (data stand 2026-10-09).
-- loading[instance] = { fid, src }: the loading screen of the instance map and the LoadingScreens column it
-- came from (wide169, wide, narrow or main). Not confirmed in the Forever client, only loadScreens is.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.DungeonAssets = {
  ejDefault = 521744,
  loadScreens = {
    Dalaran = 7963775,
    EasternKingdom = 7963776,
    Excavation = 7963777,
    Kalimdor = 7963779,
    OldIronforge = 7963781,
    RuinsofLordaeron = 7963782,
    ZephrasIsle = 7950679,
  },
  loading = {
    ["Blackfathom Deeps"] = { fid = 131823, src = "narrow" },
    ["Blackrock Depths"] = { fid = 131824, src = "narrow" },
    ["City of Dalaran"] = { fid = 7963775, src = "main" },
    ["Dire Maul - East"] = { fid = 131835, src = "narrow" },
    ["Dire Maul - North"] = { fid = 131835, src = "narrow" },
    ["Dire Maul - West"] = { fid = 131835, src = "narrow" },
    ["Excavation Site: Wetlands"] = { fid = 7963777, src = "main" },
    ["Gnomeregan"] = { fid = 131841, src = "narrow" },
    ["Hall of Thanes"] = { fid = 7963781, src = "main" },
    ["Lower Blackrock Spire"] = { fid = 131825, src = "narrow" },
    ["Maraudon"] = { fid = 131850, src = "narrow" },
    ["Onyxia's Lair"] = { fid = 131863, src = "narrow" },
    ["Ragefire Chasm"] = { fid = 131862, src = "narrow" },
    ["Razorfen Downs"] = { fid = 131864, src = "narrow" },
    ["Razorfen Kraul"] = { fid = 131865, src = "narrow" },
    ["Ruins of Lordaeron"] = { fid = 7963782, src = "main" },
    ["Scarlet Monastery"] = { fid = 131852, src = "narrow" },
    ["Scholomance"] = { fid = 131868, src = "narrow" },
    ["Shadowfang Keep"] = { fid = 131869, src = "narrow" },
    ["Stormwind Stockade"] = { fid = 131870, src = "narrow" },
    ["Stratholme"] = { fid = 131871, src = "narrow" },
    ["Sunken Temple"] = { fid = 131872, src = "narrow" },
    ["The Deadmines"] = { fid = 131833, src = "narrow" },
    ["Uldaman"] = { fid = 131876, src = "narrow" },
    ["Upper Blackrock Spire"] = { fid = 131825, src = "narrow" },
    ["Wailing Caverns"] = { fid = 131882, src = "narrow" },
    ["Zul'Farrak"] = { fid = 131885, src = "narrow" },
  },
  maps = {
    ["Blackfathom Deeps"] = {
      folder = "BlackFathomDeeps",
      floors = {
        { fid = { 447578, 447582, 447583, 447584, 447585, 447586, 447587, 447588, 447589, 447579, 447580, 447581 } },
        { fid = { 447590, 447594, 447595, 447596, 447597, 447598, 447599, 447600, 447601, 447591, 447592, 447593 } },
        { fid = { 447602, 447606, 447607, 447608, 447609, 447610, 447611, 447612, 447613, 447603, 447604, 447605 } },
      },
    },
    ["Blackrock Depths"] = {
      folder = "BlackrockDepths",
      alt = {
        { folder = "BlackrockDepths_Anniv", floors = {
            { fid = { 6125540, 6125544, 6125545, 6125546, 6125547, 6125548, 6125549, 6125550, 6125551, 6125541, 6125542, 6125543 } },
            { fid = { 6125552, 6125556, 6125557, 6125558, 6125559, 6125560, 6125561, 6125562, 6125563, 6125553, 6125554, 6125555 } },
          } },
      },
      floors = {
        { fid = { 447638, 447642, 447643, 447644, 447645, 447646, 447647, 447648, 447649, 447639, 447640, 447641 } },
        { fid = { 447650, 447654, 447655, 447656, 447657, 447658, 447659, 447660, 447661, 447651, 447652, 447653 } },
      },
    },
    ["City of Dalaran"] = {
      grid = {
        x = 31, y = 31, cols = 1, rows = 2,
        fid = { 6982328, 6982441 },
        world = { x0 = 533.33, y0 = 533.33, x1 = -533.33, y1 = 0 },
      },
      floors = {
        { fid = { 6982328, 6982441 }, cols = 1, rows = 2 },
      },
      tiles = { 6982320, 6982324, 6982330, 6982437, 6982443, 6982318, 6982326, 6982332, 6982439, 6982445, 6982316, 6982322, 6982328, 6982441, 6982447, 6982389, 6982391, 6982395, 6982489, 6982485, 6982393, 6982397, 6982399, 6982487, 6982491 },
      lo = 7963775,
    },
    ["Dire Maul - East"] = {
      folder = "DireMaul",
      note = "shared by the three wings, the floor to wing assignment is not in the file names",
      floors = {
        { fid = { 449508, 449512, 449513, 449514, 449515, 449516, 449517, 449518, 449519, 449509, 449510, 449511 } },
        { fid = { 449520, 449524, 449525, 449526, 449527, 449528, 449529, 449530, 449531, 449521, 449522, 449523 } },
        { fid = { 449532, 449536, 449537, 449538, 449539, 449540, 449541, 449542, 449543, 449533, 449534, 449535 } },
        { fid = { 449544, 449548, 449549, 449550, 449551, 449552, 449553, 449554, 449555, 449545, 449546, 449547 } },
        { fid = { 449556, 449560, 449561, 449562, 449563, 449564, 449565, 449566, 449567, 449557, 449558, 449559 } },
        { fid = { 449568, 449572, 449573, 449574, 449575, 449576, 449577, 449578, 449579, 449569, 449570, 449571 } },
      },
    },
    ["Dire Maul - North"] = {
      folder = "DireMaul",
      note = "shared by the three wings, the floor to wing assignment is not in the file names",
      floors = {
        { fid = { 449508, 449512, 449513, 449514, 449515, 449516, 449517, 449518, 449519, 449509, 449510, 449511 } },
        { fid = { 449520, 449524, 449525, 449526, 449527, 449528, 449529, 449530, 449531, 449521, 449522, 449523 } },
        { fid = { 449532, 449536, 449537, 449538, 449539, 449540, 449541, 449542, 449543, 449533, 449534, 449535 } },
        { fid = { 449544, 449548, 449549, 449550, 449551, 449552, 449553, 449554, 449555, 449545, 449546, 449547 } },
        { fid = { 449556, 449560, 449561, 449562, 449563, 449564, 449565, 449566, 449567, 449557, 449558, 449559 } },
        { fid = { 449568, 449572, 449573, 449574, 449575, 449576, 449577, 449578, 449579, 449569, 449570, 449571 } },
      },
    },
    ["Dire Maul - West"] = {
      folder = "DireMaul",
      note = "shared by the three wings, the floor to wing assignment is not in the file names",
      floors = {
        { fid = { 449508, 449512, 449513, 449514, 449515, 449516, 449517, 449518, 449519, 449509, 449510, 449511 } },
        { fid = { 449520, 449524, 449525, 449526, 449527, 449528, 449529, 449530, 449531, 449521, 449522, 449523 } },
        { fid = { 449532, 449536, 449537, 449538, 449539, 449540, 449541, 449542, 449543, 449533, 449534, 449535 } },
        { fid = { 449544, 449548, 449549, 449550, 449551, 449552, 449553, 449554, 449555, 449545, 449546, 449547 } },
        { fid = { 449556, 449560, 449561, 449562, 449563, 449564, 449565, 449566, 449567, 449557, 449558, 449559 } },
        { fid = { 449568, 449572, 449573, 449574, 449575, 449576, 449577, 449578, 449579, 449569, 449570, 449571 } },
      },
    },
    ["Excavation Site: Wetlands"] = {
      tiles = { 7473414, 7473416, 7473418, 7473432, 7473434, 7473448, 7287260, 7287266, 7287272, 7473503, 7473454, 7287262, 7287268, 7287274, 7473509, 7473456, 7287264, 7287270, 7287276, 7473511, 7473458, 7473476, 7473482, 7473484, 7473486, 7474475, 7474479, 7474483, 7474511, 7474515, 7474519, 7474547, 7474477, 7474481, 7474485, 7474513, 7474517, 7474521, 7474549 },
      soon = true,
      lo = 7963777,
    },
    ["Gnomeregan"] = {
      folder = "Gnomeregan",
      floors = {
        { fid = { 449580, 449584, 449585, 449586, 449587, 449588, 449589, 449590, 449627, 449581, 449582, 449583 } },
        { fid = { 449628, 449632, 449633, 449634, 449635, 449636, 449637, 449638, 449639, 449629, 449630, 449631 } },
        { fid = { 449640, 449644, 449645, 449646, 449647, 449648, 449649, 449650, 449651, 449641, 449642, 449643 } },
        { fid = { 449652, 449656, 449657, 449658, 449659, 449660, 449661, 449662, 449663, 449653, 449654, 449655 } },
      },
    },
    ["Hall of Thanes"] = {
      tiles = { 7725792, 7725846, 7725900, 7725954, 7726008, 7726062, 7726116, 7726170, 7726224, 7725798, 7725852, 7725906, 7725960, 7726014, 7726068, 7726122, 7726176, 7726230, 7725804, 7725858, 7725912, 7725966, 7726020, 7726074, 7726128, 7726182, 7726236, 7725810, 7725864, 7725918, 7725972, 7726026, 7726080, 7726134, 7726188, 7726242, 7725816, 7725870, 7725924, 7725978, 7726032, 7726086, 7726140, 7726194, 7726248, 7725822, 7725876, 7725930, 7725984, 7726038, 7726092, 7726146, 7726200, 7726254, 7725828, 7725882, 7725936, 7725990, 7726044, 7726098, 7726152, 7726206, 7726260, 7725834, 7725888, 7725942, 7725996, 7726050, 7726104, 7726158, 7726212, 7726266, 7725840, 7725894, 7725948, 7726002, 7726056, 7726110, 7726164, 7726218, 7726272 },
      soon = true,
    },
    ["Hyjal Summit"] = {
      folder = "Hyjal_Camelot",
      alt = {
        { folder = "CoTMountHyjal", floors = {
            { fid = { 515283, 515287, 515288, 515289, 515290, 515291, 515292, 515293, 515294, 515284, 515285, 515286 } },
          } },
      },
      floors = {
        { fid = { 7139245, 7139249, 7139250, 7139251, 7139252, 7139253, 7139254, 7139255, 7139256, 7139246, 7139247, 7139248 } },
      },
    },
    ["Lower Blackrock Spire"] = {
      folder = "BlackrockSpire",
      note = "folder holds seven floors, the split between Lower and Upper Blackrock Spire is not in the file names",
      floors = {
        { fid = { 447662, 447666, 447667, 447668, 447669, 447670, 447671, 447672, 447673, 447663, 447664, 447665 } },
        { fid = { 447674, 447678, 447679, 447680, 447681, 447682, 447683, 447684, 447685, 447675, 447676, 447677 } },
        { fid = { 447686, 447690, 447691, 447692, 447693, 447694, 447695, 447696, 447697, 447687, 447688, 447689 } },
        { fid = { 447698, 447702, 447703, 447704, 447705, 447706, 447707, 447708, 447709, 447699, 447700, 447701 } },
        { fid = { 447710, 447714, 447715, 447716, 447717, 447718, 447719, 447720, 447721, 447711, 447712, 447713 } },
        { fid = { 447722, 447726, 447727, 447728, 447729, 447730, 447731, 447732, 447733, 447723, 447724, 447725 } },
        { fid = { 447734, 447738, 447739, 447740, 447741, 447742, 447743, 447744, 447745, 447735, 447736, 447737 } },
      },
    },
    ["Maraudon"] = {
      folder = "Maraudon",
      floors = {
        { fid = { 449676, 449680, 449681, 449682, 449683, 449684, 449685, 449686, 449687, 449677, 449678, 449679 } },
        { fid = { 449688, 449692, 449693, 449694, 449695, 449696, 449697, 449698, 449699, 449689, 449690, 449691 } },
      },
    },
    ["Onyxia's Lair"] = {
      folder = "OnyxiasLair",
      floors = {
        { fid = { 448070, 448074, 448075, 448076, 448077, 448078, 448079, 448080, 448081, 448071, 448072, 448073 } },
      },
    },
    ["Ragefire Chasm"] = {
      folder = "Ragefire",
      floors = {
        { fid = { 449736, 449740, 449741, 449742, 449743, 449744, 449745, 449746, 449747, 449737, 449738, 449739 } },
      },
    },
    ["Razorfen Downs"] = {
      folder = "RazorfenDowns",
      floors = {
        { fid = { 448094, 448098, 448099, 448100, 448101, 448102, 448103, 448104, 448105, 448095, 448096, 448097 } },
      },
    },
    ["Razorfen Kraul"] = {
      folder = "RazorfenKraul",
      floors = {
        { fid = { 448106, 448110, 448111, 448112, 448113, 448114, 448115, 448116, 448117, 448107, 448108, 448109 } },
      },
    },
    ["Ruins of Lordaeron"] = {
      grid = {
        x = 31, y = 28, cols = 1, rows = 2,
        fid = { 7255736, 7255754 },
        world = { x0 = 2133.33, y0 = 533.33, x1 = 1066.67, y1 = 0 },
      },
      floors = {
        { fid = { 7255736, 7255754 }, cols = 1, rows = 2 },
      },
      tiles = { 7255712, 7255730, 7255748, 7255718, 7255736, 7255754, 7255724, 7255742, 7255760 },
      lo = 7963782,
    },
    ["Scarlet Monastery"] = {
      folder = "ScarletMonastery",
      alt = {
        { folder = "ScarletMonasteryOld", floors = {
            { fid = { 5333983, 5333984, 5333985, 5333986, 5333987, 5333988, 5333989, 5333990, 5333991, 5333992, 5333993, 5333994 } },
            { fid = { 5333996, 5333997, 5333998, 5333999, 5334000, 5334001, 5334002, 5334003, 5334004, 5334005, 5334006, 5334007 } },
            { fid = { 5334009, 5334010, 5334011, 5334012, 5334013, 5334014, 5334015, 5334016, 5334017, 5334018, 5334019, 5334020 } },
            { fid = { 5334037, 5334038, 5334040, 5334041, 5334043, 5334044, 5334046, 5334047, 5334049, 5334050, 5334052, 5334053 } },
          } },
      },
      floors = {
        { fid = { 449760, 449764, 449765, 449766, 449767, 449768, 449769, 449770, 449771, 449761, 449762, 449763 } },
        { fid = { 449772, 449776, 449777, 449778, 449779, 449780, 449781, 449782, 449783, 449773, 449774, 449775 } },
        { fid = { 449784, 449788, 449789, 449790, 449791, 449792, 449793, 449794, 449795, 449785, 449786, 449787 } },
        { fid = { 449796, 449800, 449801, 449802, 449803, 449804, 449805, 449806, 449807, 449797, 449798, 449799 } },
      },
    },
    ["Scholomance"] = {
      folder = "Scholomance",
      alt = {
        { folder = "ScholomanceOLD", floors = {
            { fid = { 5332424, 5332428, 5332429, 5332430, 5332431, 5332432, 5332433, 5332434, 5332435, 5332425, 5332426, 5332427 } },
            { fid = { 5332436, 5332440, 5332441, 5332442, 5332443, 5332444, 5332445, 5332446, 5332447, 5332437, 5332438, 5332439 } },
            { fid = { 5332448, 5332452, 5332453, 5332454, 5332455, 5332456, 5332457, 5332458, 5332459, 5332449, 5332450, 5332451 } },
            { fid = { 5332460, 5332464, 5332465, 5332466, 5332467, 5332468, 5332469, 5332470, 5332471, 5332461, 5332462, 5332463 } },
          } },
      },
      floors = {
        { fid = { 448178, 448182, 448183, 448184, 448185, 448186, 448187, 448188, 448189, 448179, 448180, 448181 } },
        { fid = { 448190, 448194, 448195, 448196, 448197, 448198, 448199, 448200, 448201, 448191, 448192, 448193 } },
        { fid = { 448202, 448206, 448207, 448208, 448209, 448210, 448211, 448212, 448213, 448203, 448204, 448205 } },
        { fid = { 448214, 448218, 448219, 448220, 448221, 448222, 448223, 448224, 448225, 448215, 448216, 448217 } },
      },
    },
    ["Shadowfang Keep"] = {
      folder = "ShadowfangKeep",
      floors = {
        { fid = { 448226, 448230, 448231, 448232, 448233, 448234, 448235, 448236, 448237, 448227, 448228, 448229 } },
        { fid = { 448238, 448242, 448243, 448244, 448245, 448246, 448247, 448248, 448249, 448239, 448240, 448241 } },
        { fid = { 448250, 448254, 448255, 448256, 448257, 448258, 448259, 448260, 448261, 448251, 448252, 448253 } },
        { fid = { 448262, 448266, 448267, 448268, 448269, 448270, 448271, 448272, 448273, 448263, 448264, 448265 } },
        { fid = { 448274, 448278, 448279, 448280, 448281, 448282, 448283, 448284, 448285, 448275, 448276, 448277 } },
        { fid = { 448286, 448290, 448291, 448292, 448293, 448294, 448295, 448296, 448297, 448287, 448288, 448289 } },
        { fid = { 448298, 448302, 448303, 448304, 448305, 448306, 448307, 448308, 448309, 448299, 448300, 448301 } },
      },
    },
    ["Stormwind Stockade"] = {
      folder = "TheStockade",
      floors = {
        { fid = { 455959, 455963, 455964, 455965, 455966, 455967, 455968, 455969, 455970, 455960, 455961, 455962 } },
      },
    },
    ["Stratholme"] = {
      folder = "Stratholme",
      floors = {
        { fid = { 448322, 448326, 448327, 448328, 448329, 448330, 448331, 448332, 448333, 448323, 448324, 448325 } },
        { fid = { 448334, 448338, 448339, 448340, 448341, 448342, 448343, 448344, 448345, 448335, 448336, 448337 } },
      },
    },
    ["Sunken Temple"] = {
      folder = "TheTempleofAtalhakkar",
      floors = {
        { fid = { 452514, 452518, 452519, 452520, 452521, 452522, 452523, 452524, 452525, 452515, 452516, 452517 } },
      },
    },
    ["The Deadmines"] = {
      folder = "TheDeadmines",
      floors = {
        { fid = { 449591, 449595, 449596, 449597, 449598, 449599, 449600, 449601, 449602, 449592, 449593, 449594 } },
        { fid = { 449603, 449607, 449608, 449609, 449610, 449611, 449612, 449613, 449614, 449604, 449605, 449606 } },
      },
    },
    ["Uldaman"] = {
      folder = "Uldaman",
      alt = {
        { folder = "Uldaman_Upres", floors = {
            { fid = { 4504949, 4504953, 4504954, 4504955, 4504956, 4504957, 4504958, 4504959, 4504960, 4504950, 4504951, 4504952 } },
            { fid = { 4504961, 4504965, 4504966, 4504967, 4504968, 4504969, 4504970, 4504971, 4504972, 4504962, 4504963, 4504964 } },
          } },
      },
      floors = {
        { fid = { 448430, 448434, 448435, 448436, 448437, 448438, 448439, 448440, 448441, 448431, 448432, 448433 } },
        { fid = { 448442, 448446, 448447, 448448, 448449, 448450, 448451, 448452, 448453, 448443, 448444, 448445 } },
      },
    },
    ["Upper Blackrock Spire"] = {
      folder = "UpperBlackrockSpire",
      floors = {
        { fid = { 1027018, 1027022, 1027023, 1027024, 1027025, 1027026, 1027027, 1027028, 1027029, 1027019, 1027020, 1027021 } },
        { fid = { 1027030, 1027034, 1027035, 1027036, 1027037, 1027038, 1027039, 1027040, 1027041, 1027031, 1027032, 1027033 } },
        { fid = { 1027042, 1027046, 1027047, 1027048, 1027049, 1027050, 1027051, 1027052, 1027053, 1027043, 1027044, 1027045 } },
      },
    },
    ["Wailing Caverns"] = {
      folder = "WailingCaverns",
      floors = {
        { fid = { 448454, 448458, 448459, 448460, 448461, 448462, 448463, 448464, 448465, 448455, 448456, 448457 } },
      },
    },
    ["Zul'Farrak"] = {
      folder = "ZulFarrak",
      floors = {
        { fid = { 449820, 449824, 449825, 449826, 449827, 449828, 449829, 449830, 449831, 449821, 449822, 449823 } },
      },
    },
  },
  portraits = {
    ["Blackfathom Deeps"] = {
      ["Aku'mai"] = 607532,
      ["Baron Aquanis"] = 607552,
      ["Gelihast"] = 607609,
      ["Ghamoo-ra"] = 1064179,
      ["Lady Sarevess"] = 607682,
      ["Lorgus Jett"] = 607701,
      ["Old Serra'kis"] = 607733,
      ["Twilight Lord Kelris"] = 607800,
    },
    ["Blackrock Depths"] = {
      ["Ambassador Flamelash"] = 607535,
      ["Bael'Gar"] = 607549,
      ["Emperor Dagran Thaurissan"] = 607595,
      ["Fineous Darkvire"] = 607602,
      ["General Angerforge"] = 607610,
      ["Golem Lord Argelmach"] = 607618,
      ["High Interrogator Gerstahn"] = 607644,
      ["Houndmaster Grebmar"] = 607647,
      ["Hurley Blackbreath"] = 607650,
      ["Lord Incendius"] = 607694,
      ["Lord Roccor"] = 607697,
      ["Magmus"] = 607705,
      ["Phalanx"] = 607740,
      ["Plugger Spazzring"] = 607741,
      ["Princess Moira Bronzebeard"] = 607746,
      ["Pyromancer Loregrain"] = 607749,
      ["Ribbly Screwspigot"] = 607758,
      ["Warder Stilgiss"] = 607814,
    },
    ["City of Dalaran"] = {
      ["Mana Devourer"] = 1536492,
    },
    ["Dire Maul - East"] = {
      ["Alzzin the Wildshaper"] = 607533,
      ["Hydrospawn"] = 607653,
      ["Lethtendris"] = 607686,
      ["Zevrim Thornhoof"] = 607824,
    },
    ["Dire Maul - North"] = {
      ["Captain Kromcrush"] = 607560,
      ["Cho'Rush the Observer"] = 607565,
      ["Guard Fengus"] = 607629,
      ["Guard Mol'dar"] = 607630,
      ["Guard Slip'kik"] = 607631,
      ["King Gordok"] = 607673,
      ["Stomper Kreeg"] = 607777,
    },
    ["Dire Maul - West"] = {
      ["Illyanna Ravenoak"] = 607656,
      ["Immol'thar"] = 607657,
      ["Magister Kalendris"] = 607703,
      ["Prince Tortheldrin"] = 607745,
      ["Tendris Warpwood"] = 607785,
    },
    ["Gnomeregan"] = {
      ["Crowd Pummeler 9-60"] = 607572,
      ["Electrocutioner 6000"] = 607594,
      ["Grubbis"] = 607628,
      ["Mekgineer Thermaplugg"] = 607714,
      ["Viscous Fallout"] = 607808,
    },
    ["Lower Blackrock Spire"] = {
      ["Gizrul the Slavener"] = 607615,
      ["Halycon"] = 607634,
      ["Highlord Omokk"] = 607645,
      ["Mother Smolderweb"] = 607719,
      ["Overlord Wyrmthalak"] = 607737,
      ["Quartermaster Zigris"] = 607751,
      ["Shadow Hunter Vosh'gajin"] = 607769,
      ["Urok Doomhowl"] = 607801,
      ["War Master Voone"] = 607810,
    },
    ["Maraudon"] = {
      ["Celebras the Cursed"] = 607562,
      ["Landslide"] = 607684,
      ["Lord Vyletongue"] = 607699,
      ["Noxxion"] = 607728,
      ["Princess Theradras"] = 607747,
      ["Razorlash"] = 607756,
      ["Rotgrip"] = 607761,
      ["Tinkerer Gizlock"] = 607796,
    },
    ["Onyxia's Lair"] = {
      ["Onyxia"] = 1379025,
    },
    ["Ragefire Chasm"] = {
      ["Bazzalan"] = 607554,
      ["Jergosh the Invoker"] = 607668,
      ["Oggleflint"] = 607730,
      ["Taragaman the Hungerer"] = 607781,
    },
    ["Razorfen Downs"] = {
      ["Amnennar the Coldbringer"] = 607537,
      ["Glutton"] = 607617,
      ["Mordresh Fire Eye"] = 607718,
      ["Tuten'kash"] = 607799,
    },
    ["Razorfen Kraul"] = {
      ["Agathelos the Raging"] = 607530,
      ["Aggem Thorncurse"] = 607531,
      ["Charlga Razorflank"] = 607563,
      ["Death Speaker Jargba"] = 607584,
      ["Overlord Ramtusk"] = 607736,
      ["Roogug"] = 607760,
    },
    ["Scarlet Monastery"] = {
      ["Arcanist Doan"] = 607545,
      ["Bloodmage Thalnos"] = 607557,
      ["Herod"] = 607640,
      ["High Inquisitor Fairbanks"] = 607642,
      ["High Inquisitor Whitemane"] = 607643,
      ["Houndmaster Loksey"] = 607648,
      ["Interrogator Vishas"] = 607662,
      ["Scarlet Commander Mograine"] = 607764,
    },
    ["Scholomance"] = {
      ["Darkmaster Gandling"] = 607582,
      ["Doctor Theolen Krastinov"] = 607586,
      ["Instructor Malicia"] = 607661,
      ["Jandice Barov"] = 607666,
      ["Kirtonos the Herald"] = 607675,
      ["Kormok"] = 1134504,
      ["Lady Illucia Barov"] = 607681,
      ["Lord Alexei Barov"] = 607691,
      ["Lorekeeper Polkelt"] = 607700,
      ["Marduk Blackpool"] = 607709,
      ["Ras Frostwhisper"] = 607754,
      ["Rattlegore"] = 607755,
      ["The Ravenian"] = 607791,
      ["Vectus"] = 607804,
    },
    ["Shadowfang Keep"] = {
      ["Baron Silverlaine"] = 522206,
      ["Commander Springvale"] = 522213,
    },
    ["Stratholme"] = {
      ["Balnazzar"] = 607551,
      ["Baroness Anastari"] = 607553,
      ["Hearthsinger Forresten"] = 607637,
      ["Magistrate Barthilas"] = 607704,
      ["Maleki the Pallid"] = 607707,
      ["Nerub'enkan"] = 607724,
      ["Postmaster Malown"] = 5875510,
      ["Ramstein the Gorger"] = 607752,
      ["The Unforgiven"] = 607792,
      ["Timmy the Cruel"] = 607795,
    },
    ["Sunken Temple"] = {
      ["Avatar of Hakkar"] = 607548,
      ["Dreamscythe"] = 608311,
      ["Jammal'an the Prophet"] = 607665,
      ["Shade of Eranikus"] = 607768,
    },
    ["The Deadmines"] = {
      ["Captain Greenskin"] = 5875505,
      ["Cookie"] = 5875506,
      ["Edwin VanCleef"] = 5875507,
      ["Gilnid"] = 5875508,
      ["Mr. Smite"] = 5875509,
      ["Rhahk'Zor"] = 5875511,
      ["Sneed"] = 5875512,
    },
    ["Uldaman"] = {
      ["Ancient Stone Keeper"] = 607538,
      ["Archaedas"] = 607546,
      ["Baelog"] = 607550,
      ["Eric \"The Swift\""] = 607598,
      ["Galgann Firehammer"] = 607606,
      ["Grimlok"] = 607626,
      ["Ironaya"] = 607664,
      ["Obsidian Sentinel"] = 607729,
      ["Olaf"] = 607732,
      ["Revelosh"] = 607757,
    },
    ["Upper Blackrock Spire"] = {
      ["General Drakkisath"] = 607612,
      ["Pyroguard Emberseer"] = 607748,
      ["The Beast"] = 607786,
      ["Warchief Rend Blackhand"] = 607813,
    },
    ["Wailing Caverns"] = {
      ["Kresh"] = 607676,
      ["Lady Anacondra"] = 607680,
      ["Lord Cobrahn"] = 607693,
      ["Lord Pythas"] = 607696,
      ["Lord Serpentis"] = 607698,
      ["Mutanus the Devourer"] = 607721,
      ["Skum"] = 607775,
      ["Verdan the Everliving"] = 607805,
    },
    ["Zul'Farrak"] = {
      ["Antu'sul"] = 607541,
      ["Chief Ukorz Sandscalp"] = 607564,
      ["Gahz'rilla"] = 607604,
      ["Hydromancer Velratha"] = 607652,
      ["Nekrum Gutchewer"] = 607723,
      ["Shadowpriest Sezz'ziz"] = 607770,
      ["Theka the Martyr"] = 607793,
      ["Witch Doctor Zum'rah"] = 607819,
    },
  },
}
