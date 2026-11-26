/**
 * css34: PLAPI 7-11 plugins run in the nested legacy core (css34_old_plugins.cpp).
 */
#ifndef _INCLUDE_CSS34_OLD_PLUGINS_H_
#define _INCLUDE_CSS34_OLD_PLUGINS_H_

#include <stddef.h>
#include "metamod_plugins.h"

class IServerPluginCallbacks;

/* MM 1.4 (PLAPI 7) to MM 1.10 (PLAPI 11): the MM 1.10 legacy core's
 * PLAPI_VERSION is 11 and it refuses anything newer. */
#define CSS34_OLD_PLAPI_MIN 7
#define CSS34_OLD_PLAPI_MAX 11

bool css34_IsOldPluginApi(int api);
void css34_LoadOldPlugin(CPluginManager::CPlugin *pl, int api, char *error, size_t maxlen, bool late);
/* CPluginManager::_Unload: unload pl, passing force through to an old plugin. */
bool css34_UnloadPlugin(CPluginManager::CPlugin *pl, bool force, char *error, size_t maxlen);
/* CPluginManager::_Unload, once pl is gone from the list: free an old plugin's proxy. */
void css34_ReleaseOldPlugin(CPluginManager::CPlugin *pl);
/* MetamodSource::NotifyVSPListening: the legacy core's plugins listen too. */
void css34_OldVspListening(IServerPluginCallbacks *callbacks, int version);
/* mm_UnloadMetamod, after the modern plugins: shut the legacy core down. */
void css34_ShutdownOldCore();

#endif
