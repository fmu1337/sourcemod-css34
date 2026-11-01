/**
 * css34_legacy_probe: a PLAPI 11 Metamod plugin built against MM 1.10
 * core-legacy (SourceHook v4), i.e. an "old" plugin for MM 1.12.
 *
 * It is compiled with the MM 1.10 build (apply-mmsource-oldbridge.sh adds it
 * to core-legacy/AMBuilder) and is never shipped. testing/scripts/
 * legacy-bridge-test.sh installs it on a server running metamod.2.ep1 and
 * checks that the nested legacy core loads it and that its SourceHook v4
 * hook on IServerGameDLL::LevelInit fires.
 *
 * Events go to <mod>/addons/metamod/css34_legacy_probe.log, one per line:
 *   load api=<n> late=<0|1>, all_loaded, level_init map=<name>, unload
 */

#include <stdio.h>
#include <string.h>
#include "ISmmPlugin.h"

class LegacyProbe : public ISmmPlugin
{
public:
	bool Load(PluginId id, ISmmAPI *ismm, char *error, size_t maxlen, bool late);
	bool Unload(char *error, size_t maxlen);
	void AllPluginsLoaded();
	bool Pause(char *error, size_t maxlen) { return true; }
	bool Unpause(char *error, size_t maxlen) { return true; }
	const char *GetAuthor() { return "sourcemod-css34"; }
	const char *GetName() { return "CSS34 Legacy Probe"; }
	const char *GetDescription() { return "PLAPI 11 test plugin for the MM 1.12 legacy bridge"; }
	const char *GetURL() { return "https://github.com/fmu1337/sourcemod-css34"; }
	const char *GetLicense() { return "GPLv3"; }
	const char *GetVersion() { return "1.0"; }
	const char *GetDate() { return __DATE__; }
	const char *GetLogTag() { return "CSS34LP"; }
};

LegacyProbe g_LegacyProbe;
PLUGIN_EXPOSE(LegacyProbe, g_LegacyProbe);

SH_DECL_HOOK6(IServerGameDLL, LevelInit, SH_NOATTRIB, 0, bool, char const *, char const *, char const *, char const *, bool, bool);

static IServerGameDLL *g_pServer = NULL;
static char g_LogPath[512];

static void ProbeLog(const char *fmt, const char *arg)
{
	FILE *fp = fopen(g_LogPath, "a");
	if (!fp)
	{
		return;
	}
	fprintf(fp, fmt, arg);
	fputc('\n', fp);
	fclose(fp);
}

static bool Hook_LevelInit(char const *map, char const *entities, char const *old_level,
	char const *landmark, bool load_game, bool background)
{
	ProbeLog("level_init map=%s", map ? map : "");
	RETURN_META_VALUE(MRES_IGNORED, true);
}

bool LegacyProbe::Load(PluginId id, ISmmAPI *ismm, char *error, size_t maxlen, bool late)
{
	PLUGIN_SAVEVARS();

	ismm->PathFormat(g_LogPath, sizeof(g_LogPath), "%s/addons/metamod/css34_legacy_probe.log", ismm->GetBaseDir());

	CreateInterfaceFn server = ismm->serverFactory(false);
	char iface[] = "ServerGameDLL000";
	for (int i = 3; i <= 9 && !g_pServer; i++)
	{
		iface[15] = (char)('0' + i);
		g_pServer = (IServerGameDLL *)server(iface, NULL);
	}
	if (!g_pServer)
	{
		snprintf(error, maxlen, "IServerGameDLL not found");
		return false;
	}

	SH_ADD_HOOK_STATICFUNC(IServerGameDLL, LevelInit, g_pServer, Hook_LevelInit, true);

	char line[64];
	snprintf(line, sizeof(line), "%d late=%d", GetApiVersion(), late ? 1 : 0);
	ProbeLog("load api=%s", line);
	ismm->ConPrintf("[CSS34LP] loaded in the legacy core (PLAPI %d)\n", GetApiVersion());
	return true;
}

void LegacyProbe::AllPluginsLoaded()
{
	ProbeLog("all_loaded%s", "");
}

bool LegacyProbe::Unload(char *error, size_t maxlen)
{
	if (g_pServer)
	{
		SH_REMOVE_HOOK_STATICFUNC(IServerGameDLL, LevelInit, g_pServer, Hook_LevelInit, true);
	}
	ProbeLog("unload%s", "");
	return true;
}
