/**
 * css34: PLAPI 7-12 plugins run in the nested legacy core (css34_old_plugins.cpp).
 */
#ifndef _INCLUDE_CSS34_OLD_PLUGINS_H_
#define _INCLUDE_CSS34_OLD_PLUGINS_H_

#include <stddef.h>
#include "metamod_plugins.h"

/* MM 1.4 (PLAPI 7) to MM 1.10 (PLAPI 11/12); 13 is the experimental 1.6 API. */
#define CSS34_OLD_PLAPI_MIN 7
#define CSS34_OLD_PLAPI_MAX 12

bool css34_IsOldPluginApi(int api);
void css34_LoadOldPlugin(CPluginManager::CPlugin *pl, int api, char *error, size_t maxlen, bool late);

#endif
