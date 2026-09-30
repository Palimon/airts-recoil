-- AIRTS fork feature tests (airts/scripts/feature-tests.sh, start script airts/fixtures/feature-tests.txt).
-- Active only with the modoption airts_test = "features"; each check prints one AIRTS_TEST line with
-- PASS, FAIL or SKIP (flag absent, as on stock Recoil), then AIRTS_TEST_DONE and the game ends.
function gadget:GetInfo()
  return { name = "AIRTS feature tests", desc = "Checks for the fork's Lua-visible engine patches",
           author = "airts", date = "2026", license = "GNU GPL, v2 or later",
           layer = 10, enabled = true }
end

if not gadgetHandler:IsSyncedCode() then return false end

local modOpts = Spring.GetModOptions() or {}
local fs = (Engine and Engine.FeatureSupport) or {}

local SETUP = 30      -- units are created
local START = 32      -- tempo, speed multipliers and orders are set
local MEASURE = 152   -- 120 frames later, everything is measured
local FINISH = 170

local probe
local U = {}          -- name -> unitID
local P = {}          -- name -> {x, z} at START
local results = { pass = 0, fail = 0, skip = 0 }

local function report(name, ok, detail)
  local tag = (ok == nil) and "SKIP" or (ok and "PASS" or "FAIL")
  if ok == nil then results.skip = results.skip + 1
  elseif ok then results.pass = results.pass + 1
  else results.fail = results.fail + 1 end
  Spring.Echo(string.format("AIRTS_TEST %s %s %s", tag, name, detail or ""))
end

local function spawn(name, x, z)
  local u = Spring.CreateUnit(probe, x, Spring.GetGroundHeight(x, z), z, 0, 0)
  U[name] = u
  return u
end

local function dist(name)
  local x, _, z = Spring.GetUnitPosition(U[name])
  local dx, dz = x - P[name][1], z - P[name][2]
  return math.sqrt(dx * dx + dz * dz)
end

local function turretRotY(u)
  local turret = Spring.GetUnitPieceMap(u).turret
  local _, ry = Spring.UnitScript.CallAsUnit(u, Spring.UnitScript.GetPieceRotation, turret)
  return ry
end

local function spinTurret(u)
  local turret = Spring.GetUnitPieceMap(u).turret
  Spring.UnitScript.CallAsUnit(u, Spring.UnitScript.Spin, turret, 2, math.rad(30))
end

function gadget:Initialize()
  if modOpts.airts_test ~= "features" then
    gadgetHandler:RemoveGadget()
    return
  end
  probe = UnitDefNames.probe.id
  Spring.Echo(string.format("AIRTS_TEST_START airtsUnitTempo=%s airtsUnitSpeedMult=%s",
    tostring(fs.airtsUnitTempo), tostring(fs.airtsUnitSpeedMult)))
end

local rot0 = {}

function gadget:GameFrame(n)
  if n == SETUP then
    -- a row per check, well away from both start positions
    spawn("anim_t1", 1000, 1600); spawn("anim_t0", 1100, 1600)
    spawn("move_t1", 1000, 1800); spawn("move_t05", 1000, 1900); spawn("move_t0", 1000, 2000)
    spawn("mc_t1", 1000, 2100); spawn("mc_t05", 1000, 2200)
    spawn("reload_t1", 1000, 2300); spawn("reload_t05", 1000, 2400)
    spawn("mc_m1", 1000, 2500); spawn("mc_m0", 1000, 2600); spawn("mc_m3", 1000, 2700)
    spawn("move_m1", 1000, 2800); spawn("move_m0", 1000, 2900); spawn("move_m3", 1000, 3000)
    for _, name in ipairs({ "anim_t1", "anim_t0" }) do spinTurret(U[name]) end
  end

  if n == START then
    for name, u in pairs(U) do
      local x, _, z = Spring.GetUnitPosition(u)
      P[name] = { x, z }
      Spring.GiveOrderToUnit(u, CMD.FIRE_STATE, { 0 }, 0)
    end
    if fs.airtsUnitTempo then
      Spring.SetUnitTempo(U.anim_t0, 0)
      Spring.SetUnitTempo(U.move_t05, 0.5)
      Spring.SetUnitTempo(U.move_t0, 0)
      Spring.SetUnitTempo(U.mc_t05, 0.5)
      Spring.SetUnitTempo(U.reload_t05, 0.5)
    end
    if fs.airtsUnitSpeedMult then
      Spring.SetUnitSpeedMult(U.mc_m0, 0)
      Spring.SetUnitSpeedMult(U.mc_m3, 3)
      Spring.SetUnitSpeedMult(U.move_m0, 0)
      Spring.SetUnitSpeedMult(U.move_m3, 3)
    end
    rot0.anim_t1 = turretRotY(U.anim_t1)
    rot0.anim_t0 = turretRotY(U.anim_t0)
    for _, name in ipairs({ "move_t1", "move_t05", "move_t0", "move_m1", "move_m0", "move_m3" }) do
      Spring.GiveOrderToUnit(U[name], CMD.MOVE, { P[name][1] + 2000, 0, P[name][2] }, 0)
    end
    for _, name in ipairs({ "mc_t1", "mc_t05", "mc_m1", "mc_m0", "mc_m3" }) do
      local u = U[name]
      Spring.MoveCtrl.Enable(u)
      Spring.MoveCtrl.SetTrackGround(u, true)
      Spring.MoveCtrl.SetGravity(u, 0)
      Spring.MoveCtrl.SetVelocity(u, 1, 0, 0)
    end
    for _, name in ipairs({ "reload_t1", "reload_t05" }) do
      Spring.SetUnitWeaponState(U[name], 1, { reloadState = n + 600 })
    end
  end

  if n == MEASURE then
    local T = fs.airtsUnitTempo and true or nil
    local M = fs.airtsUnitSpeedMult and true or nil

    -- tempo 0 freezes script animation; tempo 1 keeps it running
    local d1 = math.abs(turretRotY(U.anim_t1) - rot0.anim_t1)
    local d0 = math.abs(turretRotY(U.anim_t0) - rot0.anim_t0)
    report("tempo0_animation_frozen", T and (d0 == 0 and d1 > 0.1), string.format("turn_t1=%.4f turn_t0=%.4f", d1, d0))

    -- tempo 0.5 moves about half as far as tempo 1 under the same order; tempo 0 not at all
    local m1, m05, m0 = dist("move_t1"), dist("move_t05"), dist("move_t0")
    report("tempo_ground_move", T and (m0 == 0 and m1 > 50 and m05 / m1 > 0.35 and m05 / m1 < 0.65),
      string.format("d_t1=%.2f d_t05=%.2f d_t0=%.4f ratio=%.3f", m1, m05, m0, m05 / math.max(m1, 1e-6)))

    -- MoveCtrl motion at tempo 0.5 covers half the distance
    local c1, c05 = dist("mc_t1"), dist("mc_t05")
    report("tempo_movectrl", T and (math.abs(c05 / c1 - 0.5) < 0.02),
      string.format("d_t1=%.2f d_t05=%.2f ratio=%.4f", c1, c05, c05 / math.max(c1, 1e-6)))

    -- a reload in progress at tempo 0.5 ends 60 frames later after 120 frames
    local r1 = Spring.GetUnitWeaponState(U.reload_t1, 1, "reloadState")
    local r05 = Spring.GetUnitWeaponState(U.reload_t05, 1, "reloadState")
    report("tempo_reload", T and (r05 - r1 >= 59 and r05 - r1 <= 61),
      string.format("reload_t1=%d reload_t05=%d shift=%d", r1, r05, r05 - r1))

    -- speed multiplier under MoveCtrl: 0 holds the unit exactly, 3 triples the distance
    local k1, k0, k3 = dist("mc_m1"), dist("mc_m0"), dist("mc_m3")
    report("speedmult_movectrl", M and (k0 == 0 and math.abs(k3 / k1 - 3) < 0.02),
      string.format("d_m1=%.2f d_m0=%.4f d_m3=%.2f ratio=%.4f", k1, k0, k3, k3 / math.max(k1, 1e-6)))

    -- speed multiplier on a ground order: 0 does not move, 3 goes further than 1
    local g1, g0, g3 = dist("move_m1"), dist("move_m0"), dist("move_m3")
    report("speedmult_ground_move", M and (g0 < 0.01 and g3 > 1.5 * g1),
      string.format("d_m1=%.2f d_m0=%.4f d_m3=%.2f ratio=%.3f", g1, g0, g3, g3 / math.max(g1, 1e-6)))
  end

  if n == FINISH then
    Spring.Echo(string.format("AIRTS_TEST_DONE pass=%d fail=%d skip=%d", results.pass, results.fail, results.skip))
    for _, u in ipairs(Spring.GetTeamUnits(1) or {}) do Spring.DestroyUnit(u, false, true) end
  end
end
