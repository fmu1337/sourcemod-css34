/**
 * css34: nested legacy core (metamod.1.ep1 from MM 1.10 core-legacy).
 *
 * metamod.2.ep1 (MM 1.12) loads this library on demand and hands it every
 * plugin that reports PLAPI 7-11. The legacy core then runs next to the
 * modern one in the same process:
 *   - it starts like the VSP bridge does (AlternatelyLoadMetamod with the
 *     engine and server factories), hooking IServerGameDLL with SourceHook v4;
 *   - it does not read metaplugins.ini or the VDF directory, does not register
 *     its own meta / metamod_version / mm_* commands and does not hook the
 *     client "meta" command: the modern core owns all of those;
 *   - plugins are loaded, listed, paused and unloaded through the C functions
 *     below; the modern core shows each one as a proxy in "meta list";
 *   - EnableVSPListener() asks the modern core, which hands its VSP callbacks
 *     over with css34_old_vsp (OnVSPListening, GetVSPInfo);
 *   - css34_old_shutdown unloads its plugins and removes its SourceHook v4
 *     hooks when the modern core shuts down.
 *
 * The functions are this project's own ABI (version CSS34_OLD_BRIDGE_API);
 * both sides are built from this repository.
 */

#include <string.h>
#include "sourcemm.h"
#include "CPlugin.h"
#include "CSmmAPI.h"
#include "util.h"

#define CSS34_OLD_BRIDGE_API 2

using namespace SourceMM;

bool g_bCss34Nested = false;
static bool g_bCss34NestedAllLoaded = false;
static bool g_bCss34NestedDown = false;
typedef void (*css34_vsp_request_t)();
static css34_vsp_request_t g_Css34VspRequest = NULL;

/* CSmmAPI::EnableVSPListener in nested mode (apply-mmsource-oldbridge.sh). */
void css34_nested_request_vsp()
{
	if (g_Css34VspRequest && !g_bCss34NestedDown)
	{
		g_Css34VspRequest();
	}
}

static void css34_copy_error(char *error, size_t maxlen, const char *msg)
{
	if (error && maxlen)
	{
		UTIL_Format(error, maxlen, "%s", msg);
	}
}

SMM_API int css34_old_api()
{
	return CSS34_OLD_BRIDGE_API;
}

SMM_API int css34_old_init(void *engine_factory, void *server_factory, char *error, size_t maxlen)
{
	if (g_bCss34Nested)
	{
		return 1;
	}
	if (g_GameDll.loaded || g_bIsBridgedAsVsp)
	{
		css34_copy_error(error, maxlen, "the legacy core already runs as the game DLL or VSP");
		return 0;
	}
	if (!engine_factory || !server_factory)
	{
		css34_copy_error(error, maxlen, "no engine or server factory for the legacy core");
		return 0;
	}

	g_bCss34Nested = true;
	if (!AlternatelyLoadMetamod((CreateInterfaceFn)engine_factory, (CreateInterfaceFn)server_factory))
	{
		g_bCss34Nested = false;
		css34_copy_error(error, maxlen, "the legacy core failed to start");
		return 0;
	}
	return 1;
}

SMM_API void css34_old_all_loaded()
{
	if (!g_bCss34Nested || g_bCss34NestedAllLoaded)
	{
		return;
	}
	g_bCss34NestedAllLoaded = true;
	g_PluginMngr.SetAllLoaded();
}

/* Returns the legacy plugin id (>= Pl_MinId) or -1 with error set. */
SMM_API int css34_old_load(const char *file, int late, char *error, size_t maxlen)
{
	if (!g_bCss34Nested || g_bCss34NestedDown)
	{
		css34_copy_error(error, maxlen, "the legacy core is not running");
		return -1;
	}
	if (late)
	{
		css34_old_all_loaded();
	}

	char msg[256];
	msg[0] = '\0';
	bool already = false;
	PluginId id = g_PluginMngr.Load(file, Pl_Console, already, msg, sizeof(msg));
	CPluginManager::CPlugin *pl = (id >= Pl_MinId) ? g_PluginMngr.FindById(id) : NULL;
	if (!pl || pl->m_Status != Pl_Running || !pl->m_API)
	{
		if (!msg[0])
		{
			UTIL_Format(msg, sizeof(msg), "legacy core could not load %s", file);
		}
		if (pl && !already)
		{
			char ignored[128];
			g_PluginMngr.Unload(id, true, ignored, sizeof(ignored));
		}
		css34_copy_error(error, maxlen, msg);
		return -1;
	}
	return id;
}

SMM_API int css34_old_unload(int id, int force, char *error, size_t maxlen)
{
	if (error && maxlen)
	{
		error[0] = '\0';
	}
	return g_PluginMngr.Unload(id, force != 0, error, maxlen) ? 1 : 0;
}

SMM_API int css34_old_pause(int id, int pause, char *error, size_t maxlen)
{
	if (error && maxlen)
	{
		error[0] = '\0';
	}
	bool ok = pause ? g_PluginMngr.Pause(id, error, maxlen) : g_PluginMngr.Unpause(id, error, maxlen);
	return ok ? 1 : 0;
}

SMM_API int css34_old_running(int id, char *error, size_t maxlen)
{
	CPluginManager::CPlugin *pl = g_PluginMngr.FindById(id);
	if (!pl || !pl->m_API || pl->m_Status != Pl_Running)
	{
		css34_copy_error(error, maxlen, "legacy plugin is not running");
		return 0;
	}
	return pl->m_API->QueryRunning(error, maxlen) ? 1 : 0;
}

/* 0 name, 1 author, 2 description, 3 url, 4 license, 5 version, 6 date, 7 log tag */
SMM_API const char *css34_old_info(int id, int field)
{
	CPluginManager::CPlugin *pl = g_PluginMngr.FindById(id);
	if (!pl || !pl->m_API)
	{
		return "";
	}
	ISmmPlugin *api = pl->m_API;
	const char *value = NULL;
	switch (field)
	{
	case 0: value = api->GetName(); break;
	case 1: value = api->GetAuthor(); break;
	case 2: value = api->GetDescription(); break;
	case 3: value = api->GetURL(); break;
	case 4: value = api->GetLicense(); break;
	case 5: value = api->GetVersion(); break;
	case 6: value = api->GetDate(); break;
	case 7: value = api->GetLogTag(); break;
	}
	return value ? value : "";
}

SMM_API int css34_old_count()
{
	return (int)g_PluginMngr.GetPluginCount();
}

SMM_API void css34_old_set_vsp_request(css34_vsp_request_t fn)
{
	g_Css34VspRequest = fn;
}

/* The modern core's VSP callbacks: what a vsp_bridge load would have set. */
SMM_API void css34_old_vsp(void *callbacks, int version)
{
	if (!g_bCss34Nested || g_bCss34NestedDown || !callbacks)
	{
		return;
	}
	g_pRealVspCallbacks = (IServerPluginCallbacks *)callbacks;
	g_vsp_version = (unsigned int)version;
	g_PluginMngr.SetVSPAsLoaded();
}

/* Metamod shuts down: unload every legacy plugin and remove the SourceHook v4
 * hooks. The legacy core registered no cvars of its own (the modern core owns
 * them), so this is UnloadMetamod without the shutting-down cvar unlink. */
SMM_API void css34_old_shutdown()
{
	if (!g_bCss34Nested || g_bCss34NestedDown)
	{
		return;
	}
	g_bCss34NestedDown = true;
	UnloadMetamod(false);
}
