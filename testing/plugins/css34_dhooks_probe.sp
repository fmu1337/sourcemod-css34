/**
 * css34 DHooks probe.
 *
 * When dhooks.ext is available, installs:
 *  - a virtual hook on CCSPlayer::OnTakeDamage (offset from sdkhooks.games)
 *    on every client;
 *  - a dynamic detour on CCSPlayer::RoundRespawn (sm-cstrike.games signature;
 *    cstrike.ext does not detour it, so no two detours share a prologue);
 *  - a POST virtual hook on CBasePlayer::EyePosition that checks the Vector
 *    return value (returned through a hidden pointer on x86) and overrides it
 *    with the same value;
 *  - a PRE virtual hook on CCSPlayer::PlayStepSound that reads its float
 *    stack parameter and re-calls the function with the parameter set to the
 *    same value (MRES_ChangedHandled);
 *  - a POST detour on CWeaponCSBase::GetMaxSpeed that checks the float
 *    return value (x87 ST(0) on x86) and overrides it with itself.
 * The last three use css34_dhooks_probe.games (testing/plugins/gamedata).
 * Logs the hit counters on every round_end. Lines that do not ship DHooks
 * (css34 SM 1.11, SourceMod builds without dhooks.ext) log available=0.
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
	description = "Exercises DHooks virtual hooks and dynamic detours on CS:S v34",
	version = "1.1.0",
	url = "https://github.com/fmu1337/sourcemod-css34"
};

bool g_Available;
bool g_Setup;
Handle g_OnTakeDamage;
Handle g_RoundRespawn;
Handle g_EyePosition;
Handle g_PlayStepSound;
Handle g_MaxSpeed;
int g_VHookHits;
int g_DetourHits;
int g_EyeHits;
int g_EyeBad;
int g_StepHits;
int g_StepBad;
int g_SpeedHits;
int g_SpeedBad;
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
	GameData probe = new GameData("css34_dhooks_probe.games");
	if (sdkhooks == null || cstrike == null || probe == null)
	{
		LogError("[css34_dhooks_probe] setup failed: gamedata missing");
		delete sdkhooks;
		delete cstrike;
		delete probe;
		return;
	}

	int offset = sdkhooks.GetOffset("OnTakeDamage");
	if (offset != -1)
	{
		g_OnTakeDamage = DHookCreate(offset, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity, VHook_OnTakeDamage);
		DHookAddParam(g_OnTakeDamage, HookParamType_ObjectPtr);
	}

	offset = probe.GetOffset("EyePosition");
	if (offset != -1)
	{
		g_EyePosition = DHookCreate(offset, HookType_Entity, ReturnType_Vector, ThisPointer_CBaseEntity, VHook_EyePosition);
	}

	offset = probe.GetOffset("PlayStepSound");
	if (offset != -1)
	{
		g_PlayStepSound = DHookCreate(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, VHook_PlayStepSound);
		DHookAddParam(g_PlayStepSound, HookParamType_VectorPtr);
		DHookAddParam(g_PlayStepSound, HookParamType_ObjectPtr);
		DHookAddParam(g_PlayStepSound, HookParamType_Float);
		DHookAddParam(g_PlayStepSound, HookParamType_Bool);
	}

	g_RoundRespawn = CreateProbeDetour(cstrike, "RoundRespawn", CallConv_THISCALL, ReturnType_Void, ThisPointer_CBaseEntity, false, Detour_RoundRespawn);
	g_MaxSpeed = CreateProbeDetour(probe, "CWeaponCSBase::GetMaxSpeed", CallConv_THISCALL, ReturnType_Float, ThisPointer_Ignore, true, Detour_MaxSpeed);

	delete sdkhooks;
	delete cstrike;
	delete probe;
	g_Setup = (g_OnTakeDamage != null && g_RoundRespawn != null && g_EyePosition != null
		&& g_PlayStepSound != null && g_MaxSpeed != null);
	if (!g_Setup)
	{
		LogError("[css34_dhooks_probe] setup failed: otd=%d respawn=%d eye=%d step=%d speed=%d",
			g_OnTakeDamage != null, g_RoundRespawn != null, g_EyePosition != null,
			g_PlayStepSound != null, g_MaxSpeed != null);
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			OnClientPutInServer(client);
		}
	}
}

Handle CreateProbeDetour(GameData conf, const char[] name, CallingConvention callConv, ReturnType returnType, ThisPointerType thisType, bool post, DHookCallback callback)
{
	Handle detour = DHookCreateDetour(Address_Null, callConv, returnType, thisType);
	if (detour == null || !DHookSetFromConf(detour, conf, SDKConf_Signature, name))
	{
		LogError("[css34_dhooks_probe] setup failed: %s signature not found", name);
		delete detour;
		return null;
	}
	if (!DHookEnableDetour(detour, post, callback))
	{
		LogError("[css34_dhooks_probe] setup failed: %s detour not enabled", name);
		delete detour;
		return null;
	}
	return detour;
}

public void OnClientPutInServer(int client)
{
	if (g_OnTakeDamage != null)
	{
		DHookEntity(g_OnTakeDamage, false, client);
	}
	if (g_EyePosition != null)
	{
		DHookEntity(g_EyePosition, true, client);
	}
	if (g_PlayStepSound != null)
	{
		DHookEntity(g_PlayStepSound, false, client);
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

// Eye position is the origin plus the (standing or ducked) view offset
public MRESReturn VHook_EyePosition(int pThis, DHookReturn hReturn)
{
	float eye[3], origin[3];
	DHookGetReturnVector(hReturn, eye);
	GetEntPropVector(pThis, Prop_Data, "m_vecAbsOrigin", origin);
	g_EyeHits++;
	float dz = eye[2] - origin[2];
	if (FloatAbs(eye[0] - origin[0]) > 1.0 || FloatAbs(eye[1] - origin[1]) > 1.0 || dz < 0.0 || dz > 80.0)
	{
		if (g_EyeBad++ < 5)
		{
			LogError("[css34_dhooks_probe] EyePosition %.1f %.1f %.1f vs origin %.1f %.1f %.1f",
				eye[0], eye[1], eye[2], origin[0], origin[1], origin[2]);
		}
	}
	DHookSetReturnVector(hReturn, eye);
	return MRES_Override;
}

public MRESReturn VHook_PlayStepSound(int pThis, DHookParam hParams)
{
	float volume = DHookGetParam(hParams, 3);
	g_StepHits++;
	if (volume < 0.0 || volume > 2.0)
	{
		if (g_StepBad++ < 5)
		{
			LogError("[css34_dhooks_probe] PlayStepSound volume %f", volume);
		}
		return MRES_Ignored;
	}
	DHookSetParam(hParams, 3, volume);
	return MRES_ChangedHandled;
}

// CS:S weapon speeds are 150..260 units/s
public MRESReturn Detour_MaxSpeed(DHookReturn hReturn)
{
	float speed = DHookGetReturn(hReturn);
	g_SpeedHits++;
	if (speed < 100.0 || speed > 400.0)
	{
		if (g_SpeedBad++ < 5)
		{
			LogError("[css34_dhooks_probe] CWeaponCSBase::GetMaxSpeed %f", speed);
		}
		return MRES_Ignored;
	}
	DHookSetReturn(hReturn, speed);
	return MRES_Override;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_Rounds++;
	LogMessage("[css34_dhooks_probe] round=%d available=%d setup=%d vhook=%d detour=%d eye=%d eye_bad=%d step=%d step_bad=%d speed=%d speed_bad=%d",
		g_Rounds, g_Available, g_Setup, g_VHookHits, g_DetourHits,
		g_EyeHits, g_EyeBad, g_StepHits, g_StepBad, g_SpeedHits, g_SpeedBad);
}
