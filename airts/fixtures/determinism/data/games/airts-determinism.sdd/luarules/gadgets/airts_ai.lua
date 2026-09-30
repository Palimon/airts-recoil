local AI_NAME = "AirtsAI"

function gadget:GetInfo()
  return { name = "AIRTS AI placeholder", desc = "Logs which teams run " .. AI_NAME,
           author = "airts", date = "2026", license = "GNU GPL, v2 or later",
           layer = -100, enabled = true }
end

if not gadgetHandler:IsSyncedCode() then return false end

function gadget:Initialize()
  local mine = {}
  for _, teamID in ipairs(Spring.GetTeamList()) do
    local ai = Spring.GetTeamLuaAI(teamID)
    Spring.Echo("[airts_ai] team " .. teamID .. " luaai=" .. tostring(ai))
    if ai == AI_NAME then mine[#mine + 1] = tostring(teamID) end
  end
  Spring.Echo("[airts_ai] " .. AI_NAME .. " controls teams: " .. table.concat(mine, ","))
end
