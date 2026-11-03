/**
 * css34 gamedata library probe.
 *
 * Resolves one "library" "engine" / "server" symbol each through
 * css34_gamedata_probe.games (testing/plugins/gamedata) and logs
 *   [css34_gamedata_probe] engine_sv=1 engine_cmd=1 engine_dlgen=1 server_maxspeed=1
 * (1 = non-null address). botplay-test.sh requires every field to be 1.
 * Also logs the GAMEBIN / EXECUTABLE_PATH lines of the engine's "path"
 * command: SM 1.12+ looks for engine_i486.so in those directories.
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
}

public void OnConfigsExecuted()
{
	char output[8192];
	ServerCommandEx(output, sizeof(output), "path");

	char lines[64][256];
	int count = ExplodeString(output, "\n", lines, sizeof(lines), sizeof(lines[]));
	int logged = 0;
	for (int i = 0; i < count; i++)
	{
		if (StrContains(lines[i], "GAMEBIN") != -1 || StrContains(lines[i], "EXECUTABLE_PATH") != -1)
		{
			TrimString(lines[i]);
			LogMessage("[css34_gamedata_probe] path: %s", lines[i]);
			logged++;
		}
	}
	if (logged == 0)
	{
		LogMessage("[css34_gamedata_probe] path: no GAMEBIN / EXECUTABLE_PATH lines (%d bytes)", strlen(output));
	}
}

int HasAddress(GameData conf, const char[] name)
{
	return conf.GetAddress(name) != Address_Null ? 1 : 0;
}
