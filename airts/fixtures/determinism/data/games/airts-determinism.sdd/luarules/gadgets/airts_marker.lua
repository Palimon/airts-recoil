function gadget:GetInfo()
  return { name = "AIRTS marker", desc = "Frame markers and metalmap probe",
           author = "airts", date = "2026", license = "GNU GPL, v2 or later",
           layer = 0, enabled = true }
end

if not gadgetHandler:IsSyncedCode() then return false end

local function metalAtWorld(x, z)
  return Spring.GetMetalAmount(math.floor(x / 16), math.floor(z / 16))
end

function gadget:Initialize()
  Spring.Echo("[airts_marker] init game=" .. tostring(Game.gameName) .. " " .. tostring(Game.gameVersion)
    .. " map=" .. tostring(Game.mapName))
end

function gadget:GameFrame(n)
  if n % 500 == 0 then
    Spring.Echo("[airts_marker] frame " .. n .. " game=" .. tostring(Game.gameName))
  end
  if n == 10 then
    local sx, sz = Spring.GetMetalMapSize()
    -- patch centre (start 0 + (250,0)) = world (850,600) = metal square (53,37)
    -- empty spot world (1200,1200) = square (75,75)
    -- asymmetric probe squares: (mx=200,mz=20) and its transpose (20,200)
    Spring.Echo(string.format(
      "[airts_marker] metal probe size=%dx%d patch(850,600)=%.4f empty(1200,1200)=%.4f sq(200,20)=%.4f sq(20,200)=%.4f centre(2048,2048)=%.4f",
      sx, sz, metalAtWorld(850, 600), metalAtWorld(1200, 1200),
      Spring.GetMetalAmount(200, 20), Spring.GetMetalAmount(20, 200), metalAtWorld(2048, 2048)))
  end
end
