/**
 * css34: run PLAPI 7-11 Metamod plugins (built for MM 1.4-1.10) next to the
 * modern core.
 *
 * Upstream MM 1.12 refuses such a plugin ("Older Metamod version required,
 * probably 1.4.x"). Here the modern core loads metamod.1.ep1 (the MM 1.10
 * legacy core, SourceHook v4) from its own bin directory on first use and
 * lets it host the plugin. The modern plugin list keeps a proxy for each old
 * plugin, so "meta list", "meta unload", "meta pause" and server shutdown
 * work as for any other plugin. Without metamod.1.ep1 the plugin fails with
 * the upstream message, as before.
 *
 * Forced unloads pass through to the legacy core, a proxy is freed with its
 * plugin, a plugin's EnableVSPListener() reaches the modern core's VSP
 * listener (OnVSPListening and GetVSPInfo() work), and the legacy core shuts
 * down (plugins unloaded, SourceHook v4 hooks removed) when Metamod does.
 *
 * The css34_old_* functions are exported by builder/patches/mm-oldbridge/
 * css34_nested.cpp in the legacy core (bridge ABI version 2).
 */

#include <stdio.h>
#include <string.h>
#include "metamod_oslink.h"
#include "metamod.h"
#include "metamod_plugins.h"
#include "metamod_util.h"
#include "css34_old_plugins.h"

#if defined _WIN32
#define CSS34_OLD_CORE "metamod.1.ep1.dll"
#else
#define CSS34_OLD_CORE "metamod.1.ep1.so"
#endif
#define CSS34_OLD_BRIDGE_API 2

using namespace SourceMM;

namespace
{
	typedef int (*old_api_t)();
	typedef int (*old_init_t)(void *, void *, char *, size_t);
	typedef void (*old_all_loaded_t)();
	typedef int (*old_load_t)(const char *, int, char *, size_t);
	typedef int (*old_unload_t)(int, int, char *, size_t);
	typedef int (*old_pause_t)(int, int, char *, size_t);
	typedef int (*old_running_t)(int, char *, size_t);
	typedef const char *(*old_info_t)(int, int);
	typedef void (*old_vsp_request_t)();
	typedef void (*old_set_vsp_request_t)(old_vsp_request_t);
	typedef void (*old_vsp_t)(void *, int);
	typedef void (*old_shutdown_t)();

	struct OldCore
	{
		HINSTANCE lib;
		bool tried;
		bool ready;
		char failure[256];
		old_init_t init;
		old_all_loaded_t all_loaded;
		old_load_t load;
		old_unload_t unload;
		old_pause_t pause;
		old_running_t running;
		old_info_t info;
		old_set_vsp_request_t set_vsp_request;
		old_vsp_t vsp;
		old_shutdown_t shutdown;
	} g_OldCore;

	/* A legacy plugin called EnableVSPListener(): pass on the modern core's
	 * VSP callbacks now, or start its listener; NotifyVSPListening forwards
	 * them once it listens. */
	void OldVspRequest()
	{
		int version = 0;
		IServerPluginCallbacks *callbacks = g_Metamod.GetVSPInfo(&version);
		if (callbacks)
		{
			g_OldCore.vsp(callbacks, version);
		}
		else
		{
			g_Metamod.EnableVSPListener();
		}
	}

	template <typename T>
	bool Resolve(T &fn, const char *name)
	{
		fn = (T)dlsym(g_OldCore.lib, name);
		return fn != NULL;
	}

	bool StartOldCore()
	{
		if (g_OldCore.tried)
		{
			return g_OldCore.ready;
		}
		g_OldCore.tried = true;

		char path[PATH_SIZE];
		if (!GetFileOfAddress((void *)&StartOldCore, path, sizeof(path)))
		{
			UTIL_Format(g_OldCore.failure, sizeof(g_OldCore.failure), "cannot locate the Metamod bin directory");
			return false;
		}
		for (size_t i = strlen(path); i-- > 0; )
		{
			if (_IsPathSepChar(path[i]))
			{
				path[i + 1] = '\0';
				break;
			}
		}
		strncat(path, CSS34_OLD_CORE, sizeof(path) - strlen(path) - 1);

		FILE *fp = fopen(path, "rb");
		if (!fp)
		{
			UTIL_Format(g_OldCore.failure, sizeof(g_OldCore.failure), "%s is not installed", CSS34_OLD_CORE);
			return false;
		}
		fclose(fp);

		g_OldCore.lib = dlmount(path);
		if (!g_OldCore.lib)
		{
			UTIL_Format(g_OldCore.failure, sizeof(g_OldCore.failure), "cannot load %s: %s", CSS34_OLD_CORE, dlerror());
			return false;
		}

		old_api_t api = NULL;
		if (!Resolve(api, "css34_old_api") || api() != CSS34_OLD_BRIDGE_API
			|| !Resolve(g_OldCore.init, "css34_old_init")
			|| !Resolve(g_OldCore.all_loaded, "css34_old_all_loaded")
			|| !Resolve(g_OldCore.load, "css34_old_load")
			|| !Resolve(g_OldCore.unload, "css34_old_unload")
			|| !Resolve(g_OldCore.pause, "css34_old_pause")
			|| !Resolve(g_OldCore.running, "css34_old_running")
			|| !Resolve(g_OldCore.info, "css34_old_info")
			|| !Resolve(g_OldCore.set_vsp_request, "css34_old_set_vsp_request")
			|| !Resolve(g_OldCore.vsp, "css34_old_vsp")
			|| !Resolve(g_OldCore.shutdown, "css34_old_shutdown"))
		{
			UTIL_Format(g_OldCore.failure, sizeof(g_OldCore.failure),
				"%s has no css34 bridge (bridge API %d required)", CSS34_OLD_CORE, CSS34_OLD_BRIDGE_API);
			return false;
		}

		char error[256];
		error[0] = '\0';
		if (!g_OldCore.init((void *)g_Metamod.GetEngineFactory(false), (void *)g_Metamod.GetServerFactory(false),
				error, sizeof(error)))
		{
			UTIL_Format(g_OldCore.failure, sizeof(g_OldCore.failure), "%s: %s", CSS34_OLD_CORE, error);
			return false;
		}

		g_OldCore.set_vsp_request(&OldVspRequest);
		int version = 0;
		IServerPluginCallbacks *callbacks = g_Metamod.GetVSPInfo(&version);
		if (callbacks)
		{
			g_OldCore.vsp(callbacks, version);
		}

		g_OldCore.ready = true;
		g_Metamod.ConPrintf("[META] Started %s for PLAPI 7-11 plugins\n", CSS34_OLD_CORE);
		return true;
	}

	/* Set by css34_UnloadPlugin for the Unload() call it makes. */
	bool g_UnloadForce = false;

	class OldPluginProxy;
	OldPluginProxy *g_Proxies = NULL;

	class OldPluginProxy : public ISmmPlugin
	{
	public:
		explicit OldPluginProxy(int id) : m_Id(id), m_Next(g_Proxies)
		{
			g_Proxies = this;
		}
		virtual ~OldPluginProxy()
		{
			for (OldPluginProxy **p = &g_Proxies; *p; p = &(*p)->m_Next)
			{
				if (*p == this)
				{
					*p = m_Next;
					break;
				}
			}
		}
		static OldPluginProxy *Find(ISmmPlugin *api)
		{
			for (OldPluginProxy *p = g_Proxies; p; p = p->m_Next)
			{
				if (p == api)
				{
					return p;
				}
			}
			return NULL;
		}
		virtual int GetApiVersion()
		{
			return METAMOD_PLAPI_VERSION;
		}
		virtual bool Load(PluginId, ISmmAPI *, char *, size_t, bool)
		{
			return true;
		}
		virtual void AllPluginsLoaded()
		{
			g_OldCore.all_loaded();
		}
		virtual bool QueryRunning(char *error, size_t maxlen)
		{
			return g_OldCore.running(m_Id, error, maxlen) != 0;
		}
		virtual bool Unload(char *error, size_t maxlen)
		{
			return g_OldCore.unload(m_Id, g_UnloadForce ? 1 : 0, error, maxlen) != 0;
		}
		virtual bool Pause(char *error, size_t maxlen)
		{
			return g_OldCore.pause(m_Id, 1, error, maxlen) != 0;
		}
		virtual bool Unpause(char *error, size_t maxlen)
		{
			return g_OldCore.pause(m_Id, 0, error, maxlen) != 0;
		}
		virtual const char *GetName() { return g_OldCore.info(m_Id, 0); }
		virtual const char *GetAuthor() { return g_OldCore.info(m_Id, 1); }
		virtual const char *GetDescription() { return g_OldCore.info(m_Id, 2); }
		virtual const char *GetURL() { return g_OldCore.info(m_Id, 3); }
		virtual const char *GetLicense() { return g_OldCore.info(m_Id, 4); }
		virtual const char *GetVersion() { return g_OldCore.info(m_Id, 5); }
		virtual const char *GetDate() { return g_OldCore.info(m_Id, 6); }
		virtual const char *GetLogTag() { return g_OldCore.info(m_Id, 7); }
	private:
		int m_Id;
		OldPluginProxy *m_Next;
	};
}

bool css34_UnloadPlugin(CPluginManager::CPlugin *pl, bool force, char *error, size_t maxlen)
{
	g_UnloadForce = force;
	bool ok = pl->m_API->Unload(error, maxlen);
	g_UnloadForce = false;
	return ok;
}

void css34_ReleaseOldPlugin(CPluginManager::CPlugin *pl)
{
	OldPluginProxy *proxy = OldPluginProxy::Find(pl->m_API);
	if (proxy)
	{
		pl->m_API = NULL;
		delete proxy;
	}
}

void css34_OldVspListening(IServerPluginCallbacks *callbacks, int version)
{
	if (g_OldCore.ready && callbacks)
	{
		g_OldCore.vsp(callbacks, version);
	}
}

void css34_ShutdownOldCore()
{
	if (g_OldCore.ready)
	{
		g_OldCore.ready = false;
		g_OldCore.shutdown();
	}
}

bool css34_IsOldPluginApi(int api)
{
	return api >= CSS34_OLD_PLAPI_MIN && api <= CSS34_OLD_PLAPI_MAX;
}

void css34_LoadOldPlugin(CPluginManager::CPlugin *pl, int api, char *error, size_t maxlen, bool late)
{
	if (!StartOldCore())
	{
		if (error)
		{
			UTIL_Format(error, maxlen, "Older Metamod version required, probably 1.4.x (%d < %d); %s",
				api, PLAPI_MIN_VERSION, g_OldCore.failure);
		}
		pl->m_Status = Pl_Error;
		return;
	}

	char msg[256];
	msg[0] = '\0';
	int old_id = g_OldCore.load(pl->m_File.c_str(), late ? 1 : 0, msg, sizeof(msg));
	if (old_id < 0)
	{
		if (error)
		{
			UTIL_Format(error, maxlen, "%s", msg[0] ? msg : "legacy core refused the plugin");
		}
		pl->m_Status = Pl_Refused;
		return;
	}

	/* The proxy stands in for the old plugin; m_Lib stays open so unload works as usual. */
	pl->m_API = new OldPluginProxy(old_id);
	pl->m_Status = Pl_Running;
	g_Metamod.ConPrintf("[META] Old plugin \"%s\" (PLAPI %d) runs in %s as legacy id %d\n",
		pl->m_File.c_str(), api, CSS34_OLD_CORE, old_id);
}
