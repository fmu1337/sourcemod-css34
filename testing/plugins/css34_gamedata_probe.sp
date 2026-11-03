/**
 * css34 gamedata library probe.
 *
 * Resolves one "library" "engine" / "server" symbol each through
 * css34_gamedata_probe.games (testing/plugins/gamedata) and logs
 *   [css34_gamedata_probe] engine_sv=1 engine_cmd=1 engine_dlgen=1 server_maxspeed=1
 * (1 = non-null address). botplay-test.sh requires every field to be 1.
 * For diagnosis it also logs the mapped engine_*.so modules and the
 * GAMEBIN / EXECUTABLE_PATH lines of the engine's "path" command: SM 1.12+
 * looks for engine_i486.so in those directories.
 */
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "css34 gamedata probe",
	author = "sourcemod-css34",
	description = "Checks engine and server gamedata symbol lookups on CS:S v34",
	version = "1.0.0",
	url = "https://github.com/fmu1337/sourcemod-css34"
};

public void OnPluginStart()
{
	GameData conf = new GameData("css34_gamedata_probe.games");
	if (conf == null)
	{
		LogError("[css34_gamedata_probe] gamedata css34_gamedata_probe.games missing");
		return;
	}

	LogMessage("[css34_gamedata_probe] engine_sv=%d engine_cmd=%d engine_dlgen=%d server_maxspeed=%d",
		HasAddress(conf, "engine_sv"), HasAddress(conf, "engine_cmd"),
		HasAddress(conf, "engine_dlgen"), HasAddress(conf, "server_maxspeed"));
	delete conf;

	LogMappedEngines();
}

public void OnConfigsExecuted()
{
	char output[8192];
	ServerCommandEx(output, sizeof(output), "path");

	char line[256];
	int pos = 0;
	int len = strlen(output);
	int logged = 0;
	while (pos < len)
	{
		int next = SplitString(output[pos], "\n", line, sizeof(line));
		if (next == -1)
		{
			strcopy(line, sizeof(line), output[pos]);
			pos = len;
		}
		else
		{
			pos += next;
		}
		if (StrContains(line, "GAMEBIN") != -1 || StrContains(line, "EXECUTABLE_PATH") != -1)
		{
			TrimString(line);
			LogMessage("[css34_gamedata_probe] path: %s", line);
			logged++;
		}
	}
	if (logged == 0)
	{
		LogMessage("[css34_gamedata_probe] path: no GAMEBIN / EXECUTABLE_PATH lines (%d bytes)", len);
	}
}

// One line per engine_*.so mapping in /proc/self/maps (path only, deduplicated)
void LogMappedEngines()
{
	File maps = OpenFile("/proc/self/maps", "r");
	if (maps == null)
	{
		LogMessage("[css34_gamedata_probe] maps: /proc/self/maps not readable");
		return;
	}

	char line[512], last[512];
	while (maps.ReadLine(line, sizeof(line)))
	{
		int slash = FindCharInString(line, '/');
		if (slash == -1 || StrContains(line[slash], "engine_") == -1)
		{
			continue;
		}
		TrimString(line[slash]);
		if (!StrEqual(line[slash], last))
		{
			strcopy(last, sizeof(last), line[slash]);
			LogMessage("[css34_gamedata_probe] maps: %s", last);
		}
	}
	delete maps;
}

int HasAddress(GameData conf, const char[] name)
{
	return conf.GetAddress(name) != Address_Null ? 1 : 0;
}
