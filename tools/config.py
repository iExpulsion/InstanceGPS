"""Hand-maintained knowledge the databases don't carry: wings, boss prerequisites,
teleporters. Boss names are DungeonEncounter.dbc names."""

LINK_RADIUS = 20.0      # max hop between two spawn points (yards)
HOP_PENALTY = 40.0      # longer hops cost more (they may cut through walls)
BRIDGE_PENALTY = 3.0    # cost multiplier for forced links between disconnected areas
TELEPORT_COST = 15.0
SIMPLIFY_EPS = 2.5      # waypoint simplification tolerance (yards)

SKIP_MAPS = set()

# Maps with separate wings: each wing is its own route.
WINGS = {
    189: [  # Scarlet Monastery
        {'name': 'Graveyard', 'entrance': 45, 'bosses': ['Interrogator Vishas', 'Bloodmage Thalnos']},
        {'name': 'Library', 'entrance': 614, 'bosses': ['Houndmaster Loksey', 'Arcanist Doan']},
        {'name': 'Armory', 'entrance': 612, 'bosses': ['Herod']},
        {'name': 'Cathedral', 'entrance': 610, 'bosses': ['High Inquisitor Fairbanks', 'High Inquisitor Whitemane']},
    ],
    429: [  # Dire Maul
        {'name': 'East', 'entrance': 3183, 'bosses': ['Zevrim Thornhoof', 'Hydrospawn', 'Lethtendris', 'Alzzin the Wildshaper']},
        {'name': 'West', 'entrance': 3186, 'bosses': ['Tendris Warpwood', 'Illyanna Ravenoak', 'Magister Kalendris',
                                                      "Immol'thar", 'Prince Tortheldrin']},
        {'name': 'North', 'entrance': 3189, 'bosses': ["Guard Mol'dar", 'Stomper Kreeg', 'Guard Fengus', "Guard Slip'kik",
                                                       'Captain Kromcrush', "Cho'Rush the Observer", 'King Gordok']},
    ],
    229: [  # Blackrock Spire
        {'name': 'Lower', 'entrance': 1468, 'bosses': ['Highlord Omokk', "Shadow Hunter Vosh'gajin", 'War Master Voone',
                                                       'Mother Smolderweb', 'Urok Doomhowl', 'Quartermaster Zigris',
                                                       'Halycon', 'Gizrul the Slavener', 'Overlord Wyrmthalak']},
        {'name': 'Upper', 'entrance': 1468, 'bosses': ['Pyroguard Emberseer', 'Solakar Flamewreath',
                                                       'Warchief Rend Blackhand', 'The Beast', 'General Drakkisath']},
    ],
}

# Maps where the player may come in through different entrances: one full route per entrance.
MULTI_ENTRANCE = {329, 349}
ENTRANCE_NAMES = {2216: 'Main Gate', 2214: 'Service Entrance',
                  3133: 'Orange (Foulspore)', 3134: 'Purple (Wicked Grotto)'}
ENTRANCE_OVERRIDE = {}
EXIT_IS_ENTRANCE = set()

# Event instances: bosses come strictly in encounter order.
LINEAR = {649, 650, 595, 534, 560, 269, 608, 632, 658, 668, 580, 469, 575, 616}

# Instances whose final encounter is locked until the others are done (door, event, shield...):
# the route keeps it last. Everywhere else the order is free (plus PRECEDENCE / LINEAR).
LAST_BOSS_GATED = {
    329,  # Stratholme: Baron Rivendare (ziggurats + slaughterhouse)
    289,  # Scholomance: Darkmaster Gandling (the six room bosses)
    109,  # Sunken Temple: Shade of Eranikus
    230,  # Blackrock Depths: Emperor Dagran Thaurissan
    229,  # Blackrock Spire: General Drakkisath (upper) / Wyrmthalak (lower)
    70,   # Uldaman: Archaedas
    33,   # Shadowfang Keep: Archmage Arugal
    576,  # The Nexus: Keristrasza (prison)
    599,  # Halls of Stone: Sjonnir
    578,  # The Oculus: Ley-Guardian Eregos
    574,  # Utgarde Keep: Ingvar
    557,  # Mana-Tombs: Nexus-Prince Shaffar
    552,  # The Arcatraz: Harbinger Skyriss
    585,  # Magisters' Terrace: Kael'thas
    542,  # The Blood Furnace: Keli'dan
    554,  # The Mechanar: Pathaleon
    545,  # The Steamvault: Warlord Kalithresh
    568,  # Zul'Aman: Zul'jin
    548,  # Serpentshrine Cavern: Lady Vashj
    550,  # Tempest Keep: Kael'thas
    564,  # Black Temple: Illidan
    531,  # Ahn'Qiraj Temple: C'Thun
    724,  # The Ruby Sanctum: Halion
}

# (a, b): a must be killed before b.
PRECEDENCE = {
    # Dire Maul West: the usual way through - the outer bosses (clearing pylons on the way), then
    # Immol'thar's prison, then Prince Tortheldrin's Athenaeum past it
    429: [(b, "Immol'thar") for b in ('Tendris Warpwood', 'Illyanna Ravenoak', 'Magister Kalendris')]
         + [("Immol'thar", 'Prince Tortheldrin')],
    # Zul'Farrak: Ukorz is behind the end door Weegli blows up once the pyramid event is over
    # (Nekrum and Sezz'ziz come with its last wave); Velratha and Gahz'rilla don't gate him
    209: [("Shadowpriest Sezz'ziz", 'Nekrum Gutchewer'), ('Nekrum Gutchewer', 'Chief Ukorz Sandscalp'),
          ("Shadowpriest Sezz'ziz", 'Chief Ukorz Sandscalp')]
        # Ukorz before the pools (Velratha, Gahz'rilla): no walking back from the pools to the end door
        + [('Chief Ukorz Sandscalp', b) for b in ('Hydromancer Velratha', "Ghaz'rilla")],
    # Gundrak: Gal'darah's way opens once the three altars are used (their bosses dead); heroic
    # Eck's door opens when Moorabi dies (instance_gundrak.cpp)
    604: [(b, "Gal'darah") for b in ("Slad'ran", 'Drakkari Colossus', 'Moorabi')] + [('Moorabi', 'Eck the Ferocious')],
    # The Obsidian Sanctum: a drake left alive joins Sartharion (hard mode); clear them first
    615: [(d, 'Sartharion') for d in ('Tenebron', 'Shadron', 'Vesperon')],
    43: [(b, 'Mutanus the Devourer') for b in ('Lord Cobrahn', 'Lady Anacondra', 'Lord Pythas', 'Lord Serpentis')]
        # Anacondra on the way in, then the Pit of Fangs (Cobrahn, then the ledge drop), and Kresh
        # in the river on the way back across to the east side
        + [('Lady Anacondra', 'Lord Cobrahn'), ('Lord Cobrahn', 'Kresh')]
        + [('Kresh', b) for b in ('Lord Pythas', 'Skum', 'Lord Serpentis', 'Verdan the Everliving')],
    48: [('Twilight Lord Kelris', "Aku'mai")],
    389: [('Bazzalan', 'Jergosh the Invoker')],   # Ragefire Chasm: drop off Bazzalan's ledge to Jergosh
    533: [  # Naxxramas
        ("Anub'Rekhan", 'Grand Widow Faerlina'), ('Grand Widow Faerlina', 'Maexxna'),
        ('Noth the Plaguebringer', 'Heigan the Unclean'), ('Heigan the Unclean', 'Loatheb'),
        ('Instructor Razuvious', 'Gothik the Harvester'), ('Gothik the Harvester', 'The Four Horsemen'),
        ('Patchwerk', 'Grobbulus'), ('Grobbulus', 'Gluth'), ('Gluth', 'Thaddius'),
        ('Maexxna', 'Sapphiron'), ('Loatheb', 'Sapphiron'), ('The Four Horsemen', 'Sapphiron'), ('Thaddius', 'Sapphiron'),
        ('Sapphiron', "Kel'Thuzad"),
    ],
    603: [  # Ulduar
        ('Flame Leviathan', 'Ignis the Furnace Master'), ('Flame Leviathan', 'Razorscale'),
        ('Flame Leviathan', 'XT-002 Deconstructor'), ('XT-002 Deconstructor', 'The Iron Council'),
        ('The Iron Council', 'Kologarn'), ('Kologarn', 'Auriaya'),
        ('Kologarn', 'Hodir'), ('Kologarn', 'Thorim'), ('Kologarn', 'Freya'), ('Kologarn', 'Mimiron'),
        ('Hodir', 'General Vezax'), ('Thorim', 'General Vezax'), ('Freya', 'General Vezax'), ('Mimiron', 'General Vezax'),
        ('General Vezax', 'Yogg-Saron'),
        ('Hodir', 'Algalon the Observer'), ('Thorim', 'Algalon the Observer'),
        ('Freya', 'Algalon the Observer'), ('Mimiron', 'Algalon the Observer'),
    ],
    631: [  # Icecrown Citadel
        ('Lord Marrowgar', 'Lady Deathwhisper'), ('Lady Deathwhisper', 'Icecrown Gunship Battle'),
        ('Icecrown Gunship Battle', 'Deathbringer Saurfang'),
        ('Deathbringer Saurfang', 'Festergut'), ('Deathbringer Saurfang', 'Rotface'),
        ('Festergut', 'Professor Putricide'), ('Rotface', 'Professor Putricide'),
        ('Deathbringer Saurfang', 'Blood Council'), ('Blood Council', "Queen Lana'thel"),
        ('Deathbringer Saurfang', 'Valithria Dreamwalker'), ('Valithria Dreamwalker', 'Sindragosa'),
    ],
    409: [(b, 'Majordomo Executus') for b in ('Lucifron', 'Magmadar', 'Gehennas', 'Garr', 'Baron Geddon',
                                              'Shazzrah', 'Sulfuron Harbinger', 'Golemagg the Incinerator')],
    532: [('Attumen the Huntsman', 'Moroes'), ('Moroes', 'Maiden of the Virtue'), ('Maiden of the Virtue', 'Opera Event'),
          ('Opera Event', 'The Curator'), ('The Curator', 'Terestian Illhoof'), ('The Curator', 'Shade of Aran'),
          ('The Curator', 'Netherspite'), ('The Curator', 'Chess Event'), ('Chess Event', 'Prince Malchezaar'),
          ('Moroes', 'Nightbane')],   # the Master's Terrace opens up past Moroes
    531: [('The Prophet Skeram', b) for b in ('Silithid Royalty', 'Battleguard Sartura', 'Fankriss the Unyielding',
                                               'Viscidus', 'Princess Huhuran', 'Twin Emperors', 'Ouro')] +
         [('Battleguard Sartura', 'Fankriss the Unyielding'), ('Fankriss the Unyielding', 'Princess Huhuran'),
          ('Princess Huhuran', 'Twin Emperors'), ('Twin Emperors', 'Ouro')],
    565: [('High King Maulgar', 'Gruul the Dragonkiller')],
    548: [],
    564: [("High Warlord Naj'entus", 'Supremus')],
}

TELEPORTS = {
    603: {'clique': ['Ulduar Teleporter']},
    631: {'clique': ['Scourge Transporter'],
          # the Frozen Throne pad is a Scourge Transporter too, but only leads to the Lich King
          'not_in_network': [(4356.93, 2769.41, 355.955)],
          'oneway': [((4356.93, 2769.41, 355.955), (529.302, -2124.49, 840.857),
                      ['Professor Putricide', "Queen Lana'thel", 'Sindragosa'], 'Step on the Frozen Throne platform'),
                     # Frostwing Halls: Valithria's exit door (west, opens when she's done) leads to an
                     # elevator (Doodad_icecrown_elevator01, 4051.8, 2484.5) down to Sindragosa's gauntlet hall
                     ((4051.8, 2484.5, 366.0), (4051.8, 2484.5, 211.0), ['Valithria Dreamwalker'],
                      "Leave through Valithria's west door and take the elevator down to Sindragosa's gauntlet"),
                     # after the gunship battle your ship drops you at Deathbringer's Rise (TaxiPath
                     # 1814 / 1818 end next to the Deathbringer's Rise transporter)
                     ((-437.3, 2436.5, 191.5), (-549.073, 2211.29, 539.223), ['Icecrown Gunship Battle'],
                      "Ride the Skybreaker to Deathbringer's Rise"),
                     ((-437.5, 1956.3, 210.5), (-549.073, 2211.29, 539.223), ['Icecrown Gunship Battle'],
                      "Ride Orgrim's Hammer to Deathbringer's Rise")]},
    533: {'oneway': [
        # wing-end portals back to the hub (open once the wing's last boss is dead), and the
        # hub orb up to Sapphiron (open once all four wings are done)
        ((2909.0, -4025.02, 273.475), (3005.51, -3434.64, 304.195), ['Loatheb'], 'Take the portal back to the entrance'),
        ((3465.16, -3940.45, 308.788), (3005.51, -3434.64, 304.195), ['Maexxna'], 'Take the portal back to the entrance'),
        ((2493.02, -2921.78, 241.193), (3005.51, -3434.64, 304.195), ['The Four Horsemen'], 'Take the portal back to the entrance'),
        ((3539.02, -2936.82, 302.476), (3005.51, -3434.64, 304.195), ['Thaddius'], 'Take the portal back to the entrance'),
        ((2997.5, -3437.73, 304.189), (3498.3, -5349.49, 144.968),
         ['Loatheb', 'Maexxna', 'The Four Horsemen', 'Thaddius'], 'Click the Orb of Naxxramas'),
    ]},
}

# Set by server modules (servers/<name>/server.py, see overlay.py); AzerothCore itself has none.
REMOVE_INSTANCES = set()
REMOVE_BOSSES = {}
EXTRA_BOSSES = {}

# Manual boss positions {(map, name): (x, y, z)} that override everything else.
POSITIONS = {
    # Rend starts on the balcony above Blackrock Stadium and rides down on Gyth once the waves are
    # done; the fight is on the arena floor (areatrigger 2026 at_blackrock_stadium, which starts it)
    (229, 'Warchief Rend Blackhand'): (153.8, -419.8, 110.5),
}

# Doors that stay shut until bosses die: {map: [((x, y, z), radius, [bosses])]}. Routes don't walk
# through them before then (navmesh polygons within `radius` yards of the door are closed).
DOORS = {
    # Blackrock Spire: the stadium's exit portcullis (GO 175186, DoorData PASSAGE on Rend)
    229: [((93.0, -435.6, 111.0), 6.0, ['Warchief Rend Blackhand'])],
}

# Floors the navmesh lacks because they're game objects: {map: [((x, y), radius, z)]}, added as a
# flat round floor joined to the navmesh along its rim (navmesh.add_floor).
ADD_FLOORS = {
    # Trial of the Crusader: the Argent Coliseum's arena floor (GO 195527, broken for Anub'arak);
    # without it the routes went round the outside of the arena
    649: [((563.7, 139.6), 62.0, 394.0)],
}

# Bosses fought in a different place per faction: {(map, name): {'Alliance': pos, 'Horde': pos}}.
# Instances with any of these get one route per faction.
FACTION_POSITIONS = {
    # Icecrown Gunship Battle: board your own ship from the Rampart of Skulls. The points are the
    # rampart edge nearest to where each ship docks (first stop of TaxiPath 1814 / 1818).
    (631, 'Icecrown Gunship Battle'): {'Alliance': (-437.3, 2436.5, 191.5),   # The Skybreaker
                                       'Horde': (-437.5, 1956.3, 210.5)},     # Orgrim's Hammer
}

# Optional z bands to pick a floor where floor rectangles overlap: map -> [(zmin, zmax, floor)]
FLOOR_Z = {}

USE_MAP_TEXTURES = True
LONG_RADIUS = 70.0      # longest hop allowed when the map texture shows open floor
LONG_NEIGHBOURS = 10    # long-hop candidates per point
LONG_PENALTY = 1.15
WALL_TOLERANCE = 4.0    # yards of non-floor pixels a hop may cross (map art noise)
MAX_ALL_GROUP = 8

# Bosses that turn friendly instead of dying: seeing them friendly marks the kill.
FRIENDLY_ON_DEFEAT = {'Hodir', 'Thorim', 'Freya', 'Mimiron', 'Algalon the Observer', 'Argent Champion',
                      'Grand Champions'}
BRIDGE_MASK_PENALTY = 1.3
MASK_MIN_ON_FLOOR = 0.6

# AzerothCore navmesh (mmaps, copied from the client-data Docker volume). The spawn graph is the fallback.
import os as _os
USE_NAVMESH = True
MMAPS_DIR = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), '..', 'mmaps')
NAV_SIMPLIFY_EPS = 1.5

# Teleporter destinations that only open once bosses are dead (from the AzerothCore gossip
# scripts/conditions): map -> [((x, y, z) of the destination teleporter, [boss names])].
# A teleport edge into a locked destination is not used until those bosses are down.
TELEPORT_UNLOCK = {
    631: [  # icecrown_citadel_teleport.cpp
        ((-503.593, 2211.47, 62.7621), ['Lord Marrowgar']),                 # Oratory of the Damned
        ((-615.146, 2211.47, 199.909), ['Lady Deathwhisper']),              # Rampart of Skulls
        ((-549.073, 2211.29, 539.223), ['Icecrown Gunship Battle']),        # Deathbringer's Rise
        ((4199.35, 2769.42, 350.977), ['Deathbringer Saurfang']),           # Upper Spire
        # Sindragosa's Lair: offered once Valithria AND the frostwing gauntlet are done
        # (icecrown_citadel_teleport.cpp); the gauntlet isn't a boss here, and on a first clear you
        # walk it to reach her, so the route never takes this teleport before she's dead
        ((4356.58, 2565.75, 220.402), ['Valithria Dreamwalker', 'Sindragosa']),
        ((4356.93, 2769.41, 355.955), ['Deathbringer Saurfang']),           # Frozen Throne pad (Upper Spire)
    ],
    603: [  # conditions for gossip menu 10389
        ((553.233, -12.3247, 409.679), ['Flame Leviathan']),                # Colossal Forge
        ((926.292, -11.4635, 418.595), ['XT-002 Deconstructor']),           # Scrapyard
        ((1498.05, -24.3509, 420.966), ['XT-002 Deconstructor']),           # Antechamber
        ((1859.65, -24.9121, 448.811), ['Kologarn']),                       # Shattered Walkway
        ((2086.26, -23.9948, 421.316), ['Auriaya']),                        # Conservatory of Life
        ((2518.16, 2569.03, 412.299), ['Auriaya']),                         # Spark of Imagination
        ((1854.82, -11.5608, 334.175), ['General Vezax']),                  # Prison of Yogg-Saron
    ],
}

# Assign map levels from WMO groups + DungeonMapChunk.dbc (the client's method); texture/rectangle guess as fallback.
USE_WMO_FLOORS = True

# Blizzard's map data is used wherever it exists. Classic/TBC instances have no Blizzard map
# on 3.3.5; the WoW Dungeon Maps (WDM) patch adds them (Project Reforged bundles the same maps).
# True: include those maps for those instances (they only take effect for players who have the
# patch). False: Blizzard data only.
DUNGEON_MAP_PATCH = True

# Raid wings: once the route enters a wing it finishes it before moving to another.
WING_GROUPS = {
    533: [["Anub'Rekhan", 'Grand Widow Faerlina', 'Maexxna'],
          ['Noth the Plaguebringer', 'Heigan the Unclean', 'Loatheb'],
          ['Instructor Razuvious', 'Gothik the Harvester', 'The Four Horsemen'],
          ['Patchwerk', 'Grobbulus', 'Gluth', 'Thaddius']],
}

# Trial of the Crusader: every phase starts at Barrett Ramsey (34816, npc_announcer_toc10), who
# stands on the arena floor
_BARRETT = (559.2, 90.6, 395.3)
_READY = 'Talk to Barrett Ramsey: "We are ready!" '

# Passages missing from the navmesh, walked in a straight line: map -> [(from, to, oneway)], or
# (from, to, oneway, hint, cost) with the arrow hint at its start and its cost in yards.
# Points are navmesh edge points found next to each gap.
WALK_LINKS = {
    43: [
        # Wailing Caverns: from the edge of Verdan's ledge on the Crag, jump into the deep pool below
        # (riverbed -106, banks around -87) and swim back toward the entrance
        ((-47.5, 39.2, -33.0), (-47.7, 39.1, -105.8), True, 'Jump down into the water'),
        # past Lord Cobrahn, the Pit of Fangs ledge drops ~13 yd (no fall damage) to the way back to the river
        ((-96.5, 440.3, -76.8), (-94.7, 444.5, -89.6), True, 'Drop down the ledge'),
    ],
    389: [
        # Ragefire Chasm: the ledge past Bazzalan drops straight down toward Jergosh
        ((-379.0, 160.2, 9.2), (-380.9, 162.6, -16.5), True, 'Drop down the ledge'),
    ],
    631: [
        # the hole in the middle of Queen Lana'thel's room drops you into the Crimson Hall below
        ((4620.7, 2760.6, 400.7), (4618.7, 2762.7, 361.2), True, 'Jump down the hole in the floor'),
    ],
    533: [
        # Grobbulus -> slime pipe -> Gluth: the pipe leaves the south-west corner of Grobbulus' room (a level tunnel)
        # and comes out in Gluth's room (ends located from an in-game map screenshot)
        ((3173.0, -3267.0, 319.2), (3254.2, -3188.4, 298.0), True, 'Go through the slime pipe'),
        # Gluth -> Thaddius: the corridor is on the navmesh up to the step up into Thaddius' room
        # (11 yd higher), which isn't; hop only that step
        ((3498.7, -2940.5, 292.8), (3503.5, -2934.0, 304.0), True),
    ],
    649: [
        # Trial of the Crusader: Barrett breaks the arena floor for Anub'arak and everyone falls into
        # the chamber below. A fall takes no walking, so it costs next to nothing (the 5th value).
        (_BARRETT, (559.2, 90.6, 141.7), True, None, 5.0),
    ],
}

# Encounter names the client's DungeonEncounter.dbc misspells
BOSS_RENAME = {
    'Overlrod Tyrannus': 'Scourgelord Tyrannus',      # Pit of Saron
    'Salram the Fleshcrafter': 'Salramm the Fleshcrafter',   # Culling of Stratholme
    'Ramnstein the Gorger': 'Ramstein the Gorger',            # Stratholme
}

# Hard-mode variants of a route (the addon's "Hard-mode routes" option swaps them in): only the
# listed bosses are walked to; the others join those fights.
HARD_MODES = {
    615: {'name': 'Hard mode', 'bosses': ['Sartharion']},   # Obsidian Sanctum: Sartharion with all drakes up
}

# Places the route has to pass on the way to a boss, in order: [((x, y, z), arrow hint or None)],
# or ((x, y, z), hint, lead) to show the hint for `lead` yards on the way there too.
# For an escort or event that makes the boss appear, or a way the navmesh gets wrong.
BOSS_VIA = {
    649: {
        'Northrend Beasts': [(_BARRETT, _READY + 'Gormok the Impaler comes in first.', 60)],
        'Lord Jaraxxus': [(_BARRETT, _READY + 'to bring in Lord Jaraxxus.', 60)],
        'Faction Champions': [(_BARRETT, _READY + 'to start the Faction Champions.', 60)],
        "Val'kyr Twins": [(_BARRETT, _READY + "to bring in the Twin Val'kyr.", 60)],
        "Anub'arak": [(_BARRETT, _READY + "(or wait about a minute): the floor breaks and drops you to Anub'arak.", 60)],
    },
    209: {
        # the pyramid event starts at the troll cages on top of the pyramid (zulfarrak.cpp, go_troll_cage)
        "Shadowpriest Sezz'ziz": [((1886.0, 1296.0, 48.2),
                                   "Open a troll cage on top of the pyramid to free Sergeant Bly's crew, then hold "
                                   "the stairs with them through three waves; Nekrum and Sezz'ziz come with the last")],
        # Weegli waits at the foot of the pyramid after the waves, then blows up the end door
        'Chief Ukorz Sandscalp': [((1877.5, 1199.6, 8.9),
                                   'Ask Weegli Blastfuse "Will you blow up that door now?" to open the way to Ukorz'),
                                  ((1857.1, 1145.7, 15.2), None)],
        "Ghaz'rilla": [((1650.9, 1171.9, 10.9),
                        "Strike the Gong of Zul'Farrak with the Mallet of Zul'Farrak to summon Gahz'rilla")],
    },
    43: {
        'Mutanus the Devourer': [((-134.97, 125.40, -78.09),
                                  'With the four Fanglords dead, tell the Disciple of Naralex "Let the event begin!" '
                                  'and protect him; Mutanus appears at the end')],
        # Pythas -> Skum: down the west side of the rock; the navmesh's shorter way along the east
        # side can't be walked (way traced on an in-game map screenshot, 2026-10-01)
        'Skum': [((2.0, -233.7, -73.8), None), ((-63.5, -213.3, -65.6), None), ((-129.1, -187.3, -67.6), None)],
    },
    229: {
        # in through the stadium's entry door (GO 164726); walking in starts the event
        'Warchief Rend Blackhand': [((108.0, -420.3, 111.0),
                                     'Walk into the stadium to start the event: fight off the waves of Blackhand '
                                     'troops, then Rend rides down on Gyth. The exit gate opens when Rend dies.')],
    },
}

# Escorts: after the boss's via points, the route follows this NPC's escort path (its rows in
# the world DB's `waypoints` table) instead of the navmesh, since that's the way the NPC walks.
ESCORTS = {
    43: {'Mutanus the Devourer': 3678},   # Disciple of Naralex: entrance -> Naralex's chamber
}

# Gossip option to pick at multi-destination teleporters: map -> [((x, y, z) of the destination, text)]
TELEPORT_NAMES = {
    631: [((-17.0711, 2211.47, 30.0546), "Teleport to Light's Hammer."),
          ((-503.593, 2211.47, 62.7621), "Teleport to the Oratory of the Damned."),
          ((-615.146, 2211.47, 199.909), "Teleport to the Rampart of Skulls."),
          ((-549.073, 2211.29, 539.223), "Teleport to the Deathbringer's Rise."),
          ((4199.35, 2769.42, 350.977), "Teleport to the Upper Spire."),
          ((4356.58, 2565.75, 220.402), "Teleport to Sindragosa's Lair.")],
    603: [((-706.122, -92.6024, 429.876), "Teleport to the Expedition Base Camp."),
          ((131.248, -35.3802, 409.804), "Teleport to the Formation Grounds."),
          ((553.233, -12.3247, 409.679), "Teleport to the Colossal Forge."),
          ((926.292, -11.4635, 418.595), "Teleport to the Scrapyard."),
          ((1498.05, -24.3509, 420.966), "Teleport to the Antechamber of Ulduar."),
          ((1859.65, -24.9121, 448.811), "Teleport to the Shattered Walkway."),
          ((2086.26, -23.9948, 421.316), "Teleport to the Conservatory of Life."),
          ((2518.16, 2569.03, 412.299), "Teleport to the Spark of Imagination."),
          ((1854.82, -11.5608, 334.175), "Teleport to the Prison of Yogg-Saron.")],
}

# Fights whose end the combat log doesn't show: the creature_text lines (entry, group) that
# mark the win. The build pulls the exact text; the addon matches monster yells/says/emotes.
KILL_YELLS = {
    (631, 'Icecrown Gunship Battle'): [(36948, 13), (36939, 12)],   # Muradin / Saurfang victory
    (631, 'Valithria Dreamwalker'): [(36789, 7)],                   # "I AM RENEWED!"
    (603, 'Hodir'): [(32845, 4)],
    (603, 'Thorim'): [(32865, 9)],
    (603, 'Freya'): [(32906, 3)],
    (603, 'Mimiron'): [(33350, 13)],
    (603, 'Algalon the Observer'): [(32871, 12)],
    (595, "Mal'ganis"): [(26533, 10)],
    (599, 'Tribunal of Ages'): [(28070, 29)],                       # Brann, end of the event
    # Tirion's "Well fought!" after the Grand Champions yield. Their credit spell (68572) has no
    # target either, so it can miss the combat log just like Faction Champions' below.
    (650, 'Grand Champions'): [(33628, 24)],
    (650, 'Argent Champion'): [(34928, 6), (35119, 6)],             # Paletress / Eadric defeated
    (650, 'The Black Knight'): [(35451, 7)],                        # "No! I must not fail... again..."
    # Tirion's "A shallow and tragic victory..." once the last champion dies. The credit spell
    # (68184) is cast by Tirion on himself, up in the stands, and doesn't always reach the
    # combat log; the yell is the same for both factions and every difficulty.
    (649, 'Faction Champions'): [(34996, 12)],
}

# Arrival radius (yards) for fights that don't happen at a fixed spot.
BOSS_RADIUS = {
    (631, 'Icecrown Gunship Battle'): 120,   # the fight is on the moving ships
}

# Keep paths this far (yards) from walls/corners, at most 45% of a passage's width.
WALL_MARGIN = 5.0

# Pull paths into the middle of corridors (tools/centre.py): walls closer than this many yards
# push the path away; walls on both sides of a narrower corridor balance out in its middle.
CENTRE_PATHS = True
CENTRE_CLEARANCE = 8.0
# ...then straighten it wherever a straight line stays on the ground and this far from walls
# (or nearly as far as the centred path, in narrower spots): straight corridors look straight
STRAIGHTEN_PATHS = True
STRAIGHT_CLEARANCE = 5.0

# Places to visit right after a boss dies, on the way to whichever boss comes next:
# {map: {boss: [((x, y, z), hint or None)]}} (e.g. an altar the boss's death makes usable).
BOSS_AFTER = {}

# Event hints researched from the AzerothCore scripts (tools/hints.json: per map, boss -> points
# with hint texts, plus the source each came from). Merged into BOSS_VIA; hand-made entries above win.
def _load_hints():
    import json, os
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hints.json')
    if not os.path.exists(p):
        return
    data = json.load(open(p, encoding='utf8'))
    for e in data.get('hints', []):
        # "boss": visited on the way to that boss; "after": right after that boss dies
        table, key = (BOSS_AFTER, e['after']) if e.get('after') else (BOSS_VIA, e['boss'])
        per_map = table.setdefault(e['map'], {})
        if key in per_map:
            continue
        per_map[key] = [((pt['x'], pt['y'], pt['z']), pt.get('hint')) for pt in e['points']]
        if e.get('any_order'):
            per_map[key].append(('any-order', None))   # see navroute: visit them in the shortest order
    for o in data.get('order', []):
        PRECEDENCE.setdefault(o['map'], [])
        if (o['before'], o['after']) not in PRECEDENCE[o['map']]:
            PRECEDENCE[o['map']].append((o['before'], o['after']))


_load_hints()
