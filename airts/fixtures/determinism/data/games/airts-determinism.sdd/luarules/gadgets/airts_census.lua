-- AIRTS determinism fixture: spawns two squads, drives them into each other and logs a hash of
-- the synced state every CENSUS_EVERY frames. Two runs of the same build must print the same
-- AIRTS_CENSUS lines and end on the same AIRTS_GAMEOVER frame (airts/scripts/determinism.sh).
function gadget:GetInfo()
  return { name = "AIRTS census", desc = "Determinism fixture: squads, fight orders, state hash",
           author = "airts", date = "2026", license = "GNU GPL, v2 or later",
           layer = 0, enabled = true }
end

if not gadgetHandler:IsSyncedCode() then return false end

local modOpts      = Spring.GetModOptions() or {}
local SQUAD        = tonumber(modOpts.airts_det_squad or "") or 12
local TIMEOUT      = tonumber(modOpts.airts_det_timeout or "") or 18000
local SPAWN_FRAME  = 30
local ORDER_EVERY  = 150
local CENSUS_EVERY = 300
local MOD          = 65521 -- keeps every intermediate below 2^24, exact in a float or a double

local probeDefID = UnitDefNames.probe.id
local gaia = Spring.GetGaiaTeamID()
local over = false

local function playingTeams()
  local out = {}
  for _, t in ipairs(Spring.GetTeamList()) do
    if t ~= gaia then out[#out + 1] = t end
  end
  return out
end

local function centroid(teamID)
  local units = Spring.GetTeamUnits(teamID) or {}
  if #units == 0 then return nil end
  local sx, sz = 0, 0
  for i = 1, #units do
    local x, _, z = Spring.GetUnitPosition(units[i])
    sx, sz = sx + x, sz + z
  end
  return sx / #units, sz / #units
end

local function census(n)
  local h, hp, counts = 1, 0, {}
  for _, t in ipairs(playingTeams()) do counts[#counts + 1] = Spring.GetTeamUnitCount(t) end
  local all = Spring.GetAllUnits()
  for i = 1, #all do
    local u = all[i]
    local x, y, z = Spring.GetUnitPosition(u)
    local health = Spring.GetUnitHealth(u) or 0
    hp = hp + health
    for _, v in ipairs({ u, math.floor(x * 8), math.floor(y * 8), math.floor(z * 8), math.floor(health * 8) }) do
      h = (h * 31 + (v % MOD)) % MOD
    end
  end
  Spring.Echo(string.format("AIRTS_CENSUS frame=%d units=%s hp=%d hash=%d",
    n, table.concat(counts, "/"), math.floor(hp), h))
end

function gadget:Initialize()
  -- every fork feature flag as game Lua sees it (all nil on stock Recoil), sorted by key
  local fs, keys, parts = Engine.FeatureSupport or {}, {}, {}
  for k in pairs(fs) do
    if type(k) == "string" and k:sub(1, 5) == "airts" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  for i = 1, #keys do parts[#parts + 1] = keys[i] .. "=" .. tostring(fs[keys[i]]) end
  Spring.Echo("AIRTS_FEATURES " .. table.concat(parts, " ") .. " version=" .. tostring(Engine.version))
end

function gadget:GameOver()
  over = true
end

function gadget:GameFrame(n)
  if n == SPAWN_FRAME then
    for _, t in ipairs(playingTeams()) do
      local x, _, z = Spring.GetTeamStartPosition(t)
      for _ = 1, SQUAD do
        local px, pz = x + math.random(-250, 250), z + math.random(-250, 250)
        Spring.CreateUnit(probeDefID, px, Spring.GetGroundHeight(px, pz), pz, 0, t)
      end
    end
  end
  if n > SPAWN_FRAME and n % ORDER_EVERY == 0 and not over then
    local teams = playingTeams()
    for i, t in ipairs(teams) do
      local enemy = teams[(i % #teams) + 1]
      local cx, cz = centroid(enemy)
      if cx then
        local units = Spring.GetTeamUnits(t) or {}
        for k = 1, #units do
          local tx, tz = cx + math.random(-120, 120), cz + math.random(-120, 120)
          Spring.GiveOrderToUnit(units[k], CMD.FIGHT, { tx, Spring.GetGroundHeight(tx, tz), tz }, 0)
        end
      end
    end
  end
  if n % CENSUS_EVERY == 0 then census(n) end
  if n == TIMEOUT and not over then
    Spring.Echo("AIRTS_TIMEOUT frame=" .. n)
    local units = Spring.GetTeamUnits(1) or {}
    for i = 1, #units do Spring.DestroyUnit(units[i], false, false) end
  end
end
