function gadget:GetInfo()
  return { name = "AIRTS quit", desc = "Echo winners, quit after GameOver",
           author = "airts", date = "2026", license = "GNU GPL, v2 or later",
           layer = 1000, enabled = true }
end

if gadgetHandler:IsSyncedCode() then return false end   -- unsynced half only

local modOpts  = Spring.GetModOptions() or {}
-- quit no earlier than this frame, so a run can prove it reached a given frame
local minFrame = tonumber(modOpts.airts_quit_minframe or "") or 0
local quitAt   = nil
local quitDone = false

function gadget:GameOver(winners)
  local ids = {}
  for i = 1, #winners do ids[#ids + 1] = tostring(winners[i]) end
  local f = Spring.GetGameFrame()
  Spring.Echo("AIRTS_GAMEOVER winners=" .. table.concat(ids, ",") .. " frame=" .. f)
  quitAt = math.max(f + 30, minFrame)
end

function gadget:GameFrame(n)
  if quitAt and n >= quitAt and not quitDone then
    quitDone = true
    Spring.Echo("AIRTS_QUIT frame=" .. n)
    Spring.Quit()
  end
end
