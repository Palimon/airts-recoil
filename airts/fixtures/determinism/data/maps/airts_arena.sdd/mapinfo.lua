return {
  name            = "AIRTS Arena",
  version         = "",
  description     = "Flat generated arena (make_map.py)",
  modtype         = 3,
  mapfile         = "maps/airts_arena.smf",
  depend          = { "Map Helper v1" },
  maxmetal        = 0.02,
  extractorradius = 500,
  teams = {
    [0] = { startpos = { x = 600,  z = 600  } },
    [1] = { startpos = { x = 3500, z = 3500 } },
  },
  terraintypes = {
    [0] = { name = "Default", hardness = 1.0, receivetracks = true,
            movespeeds = { tank = 1.0, kbot = 1.0, hover = 1.0, ship = 1.0 } },
  },
}
