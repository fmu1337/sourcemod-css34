/**
 * css34 DHooks probe.
 *
 * When dhooks.ext is available, installs:
 *  - a virtual hook on CCSPlayer::OnTakeDamage (offset from sdkhooks.games)
 *    on every client;
 *  - a dynamic detour on CCSPlayer::RoundRespawn (sm-cstrike.games signature;
 *    cstrike.ext does not detour it, so no two detours share a prologue).
 * Logs the hit counters on every round_end. Lines that do not ship DHooks
 * (css34 SM 1.11, the KHook SourceMod branch on x86) log available=0.
 */
#include <sourcemod>
#undef REQUIRE_EXTENSIONS
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "css34 DHooks probe",
	author = "sourcemod-css34",
	description = "Exercises a DHooks virtual hook and a dynamic detour on CS:S v34",
	version = "1.0.0",
	url = "https://github.com/fmu1337/sourcemod-css34"
};

bool g_Available;
bool g_Setup;
Handle g_OnTakeDamage;
Handle g_RoundRespawn;
int g_VHookHits;
int g_DetourHits;
int g_Rounds;

public void OnPluginStart()
{
	HookEvent("round_end", Event_RoundEnd);
}

public void OnAllPluginsLoaded()
{
	g_Available = LibraryExists("dhooks");
	if (!g_Available)
	{
		LogMessage("[css34_dhooks_probe] dhooks.ext not available on this line");
		return;
	}

	GameData sdkhooks = new GameData("sdkhooks.games");
	GameData cstrike = new GameData("sm-cstrike.games");
	if (sdkhooks == null || cstrike == null)
	{
		LogError("[css34_dhooks_probe] setup failed: gamedata missing");
		delete sdkhooks;
		delete cstrike;
		return;
	}

	int offset = sdkhooks.GetOffset("OnTakeDamage");
	if (offset != -1)
	{
		g_OnTakeDamage = DHookCreate(offset, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity, VHook_OnTakeDamage);
		DHookAddParam(g_OnTakeDamage, HookParamType_ObjectPtr);
	}

	g_RoundRespawn = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_CBaseEntity);
	if (g_RoundRespawn != null && DHookSetFromConf(g_RoundRespawn, cstrike, SDKConf_Signature, "RoundRespawn"))
	{
		if (!DHookEnableDetour(g_RoundRespawn, false, Detour_RoundRespawn))
		{
			LogError("[css34_dhooks_probe] setup failed: RoundRespawn detour not enabled");
		}
	}
	else
	{
		LogError("[css34_dhooks_probe] setup failed: RoundRespawn signature not found");
	}

	delete sdkhooks;
	delete cstrike;
	g_Setup = (g_OnTakeDamage != null && g_RoundRespawn != null);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			OnClientPutInServer(client);
		}
	}
}

public void OnClientPutInServer(int client)
{
	if (g_OnTakeDamage != null)
	{
		DHookEntity(g_OnTakeDamage, false, client);
	}
}

public MRESReturn VHook_OnTakeDamage(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	g_VHookHits++;
	return MRES_Ignored;
}

public MRESReturn Detour_RoundRespawn(int pThis)
{
	g_DetourHits++;
	return MRES_Ignored;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_Rounds++;
	LogMessage("[css34_dhooks_probe] round=%d available=%d setup=%d vhook=%d detour=%d",
		g_Rounds, g_Available, g_Setup, g_VHookHits, g_DetourHits);
}
