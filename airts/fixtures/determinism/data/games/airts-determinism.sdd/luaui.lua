-- AIRTS LuaUI entry point. Idle unless the start script sets
-- [MODOPTIONS] airts_reload_to=<exact versioned game name>; then, from frame
-- 600, it rescans the data dirs every 30 frames and, once that archive is
-- visible, reloads the engine in-process into a game of that archive.

local target = (Spring.GetModOptions() or {}).airts_reload_to
local FIRST_FRAME = 600
local done = false

Spring.Echo("[airts_luaui] loaded game=" .. tostring(Game.gameName) .. " reload_to=" .. tostring(target))

local SCRIPT = [[
[GAME]
{
	Gametype=%s;
	MapName=AIRTS Arena;
	IsHost=1;
	OnlyLocal=1;
	MyPlayerName=host;
	StartPosType=3;
	FixedRNGSeed=123123;
	RecordDemo=0;
	[MODOPTIONS]
	{
		MinSpeed=20;
		MaxSpeed=20;
		airts_quit_minframe=1500;
	}
	[PLAYER0]
	{
		Name=host;
		Spectator=1;
		Team=0;
	}
	[AI0]
	{
		Name=ai_red;
		ShortName=AirtsAI;
		Team=0;
		Host=0;
	}
	[AI1]
	{
		Name=ai_blue;
		ShortName=AirtsAI;
		Team=1;
		Host=0;
	}
	[TEAM0]
	{
		TeamLeader=0;
		AllyTeam=0;
		Side=AIRTS;
		StartPosX=600;
		StartPosZ=600;
	}
	[TEAM1]
	{
		TeamLeader=0;
		AllyTeam=1;
		Side=AIRTS;
		StartPosX=3500;
		StartPosZ=3500;
	}
	[ALLYTEAM0]
	{
		NumAllies=0;
	}
	[ALLYTEAM1]
	{
		NumAllies=0;
	}
}
]]

function GameFrame(n)
  if done or not target or target == "" then return end
  if n < FIRST_FRAME or (n - FIRST_FRAME) % 30 ~= 0 then return end
  VFS.ScanAllDirs()
  local seen = VFS.HasArchive(target)
  Spring.Echo("[airts_luaui] frame " .. n .. " ScanAllDirs done, HasArchive(" .. target .. ")=" .. tostring(seen))
  if seen then
    done = true
    Spring.Echo("AIRTS_SEEN_B frame=" .. n .. " -> Spring.Reload")
    Spring.Reload(string.format(SCRIPT, target))
  end
end
