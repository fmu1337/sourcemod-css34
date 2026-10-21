/**
 * css34 probes for upstream SourceMod behaviour that botplay must keep.
 *
 * Sound (#2586, SM 1.13.0.7475): a NormalSHook that returns Plugin_Changed
 * must not stop the next hook, and the next hook must see the edits.
 * 1.12-dev through 7257 does not have this fix; the plugin still logs both
 * counters and check-upstream-probe.sh enforces the chain only on builds
 * that contain it.
 *
 * Entity outputs (#2589, SM 1.12.0.7257 / SM 1.13.0.7477): a
 * HookSingleEntityOutput on an entity that is then destroyed must not run
 * for a new logic_relay after a map change.
 *
 * Userid lookup (#2577, SM 1.12.0.7256 / SM 1.13.0.7476): GetClientOfUserId
 * rejects negative ids and ids above USHRT_MAX, and still resolves a live
 * client's userid. The write-side guard is the same bounds check inside
 * OnClientConnect; a plugin cannot forge an engine userid, so the probe
 * covers the lookup a plugin actually calls.
 */
#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PROBE_TAG "[css34_upstream_probe]"
#define PROBE_SAMPLE "buttons/button17.wav"
#define PROBE_MARK 137
#define PROBE_PITCH 173

int g_SoundFirst;
int g_SoundSecond;
int g_SoundSaw;
int g_SoundBad;

int g_OutputHits;
int g_OutputFresh;
int g_OutputStale;
int g_OutputMiss;
int g_OutputMaps;
bool g_OutputArmed;

int g_UserOk;
int g_UserBad;
int g_Rounds;

public Plugin myinfo =
{
	name = "css34 upstream probe",
	author = "sourcemod-css34",
	description = "Sound Plugin_Changed, entity output cleanup, userid lookup",
	version = "1.0.0",
	url = "https://github.com/fmu1337/sourcemod-css34"
};

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	AddNormalSoundHook(Sound_First);
	AddNormalSoundHook(Sound_Second);
}

public void OnMapStart()
{
	// Own non-weapon sample: no dependency on bots firing or weapon precaches.
	if (!PrecacheSound(PROBE_SAMPLE, true))
	{
		SetFailState("Could not precache upstream sound probe");
	}
	CreateTimer(1.5, Timer_OutputProbe, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(2.0, Timer_SoundProbe, 0, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(2.0, Timer_ClientProbes, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ClientProbes(Handle timer, int retry)
{
	int client = FindInGameClient();
	if (client == -1 && retry < 8)
	{
		CreateTimer(1.5, Timer_ClientProbes, retry + 1, TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Stop;
	}
	if (client != -1)
	{
		ProbeUserId(client);
	}
	return Plugin_Stop;
}

public Action Timer_OutputProbe(Handle timer)
{
	int ent = CreateEntityByName("logic_relay");
	if (ent == -1 || !DispatchSpawn(ent))
	{
		g_OutputMiss++;
		LogError("%s logic_relay spawn failed ent=%d", PROBE_TAG, ent);
		return Plugin_Stop;
	}

	int before = g_OutputHits;
	FireEntityOutput(ent, "OnTrigger", ent, 0.0);
	if (g_OutputArmed)
	{
		g_OutputMaps++;
		if (g_OutputHits != before)
		{
			g_OutputStale++;
		}
	}

	HookSingleEntityOutput(ent, "OnTrigger", OnRelayTrigger);
	g_OutputArmed = true;
	before = g_OutputHits;
	FireEntityOutput(ent, "OnTrigger", ent, 0.0);
	if (g_OutputHits == before)
	{
		g_OutputMiss++;
	}
	else
	{
		g_OutputFresh++;
	}

	AcceptEntityInput(ent, "Kill");
	return Plugin_Stop;
}

public Action OnRelayTrigger(const char[] output, int caller, int activator, float delay)
{
	if (StrEqual(output, "OnTrigger"))
	{
		g_OutputHits++;
	}
	return Plugin_Continue;
}

void ProbeUserId(int client)
{
	if (GetClientOfUserId(-1) != 0)
	{
		g_UserBad++;
	}
	if (GetClientOfUserId(0) != 0)
	{
		g_UserBad++;
	}
	// USHRT_MAX + 1. The lookup table is that wide; this must not crash.
	if (GetClientOfUserId(65536) != 0)
	{
		g_UserBad++;
	}
	int userid = GetClientUserId(client);
	if (userid <= 0 || GetClientOfUserId(userid) != client)
	{
		g_UserBad++;
	}
	else
	{
		g_UserOk++;
	}
	int edge = GetClientOfUserId(65535);
	if (edge != 0 && (edge < 1 || edge > MaxClients || !IsClientInGame(edge) || GetClientUserId(edge) != 65535))
	{
		g_UserBad++;
	}
}

public Action Timer_SoundProbe(Handle timer)
{
	// Broadcast after every round_start, including after map changes. Pitch
	// identifies our emit without relying on synchronous hook delivery.
	EmitSoundToAll(PROBE_SAMPLE, SOUND_FROM_WORLD, SNDCHAN_STATIC,
		SNDLEVEL_NORMAL, SND_NOFLAGS, 0.8, PROBE_MARK);
	return Plugin_Stop;
}

bool IsProbeSample(const char[] sample, int pitch)
{
	return StrEqual(sample, PROBE_SAMPLE) && (pitch == PROBE_MARK || pitch == PROBE_PITCH);
}

public Action Sound_First(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
	int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
	char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (!IsProbeSample(sample, pitch) || pitch != PROBE_MARK)
	{
		return Plugin_Continue;
	}
	g_SoundFirst++;
	pitch = PROBE_PITCH;
	return Plugin_Changed;
}

public Action Sound_Second(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
	int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
	char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (!IsProbeSample(sample, pitch))
	{
		return Plugin_Continue;
	}
	g_SoundSecond++;
	if (pitch == PROBE_PITCH)
	{
		g_SoundSaw++;
	}
	else
	{
		g_SoundBad++;
	}
	return Plugin_Continue;
}

int FindInGameClient()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			return client;
		}
	}
	return -1;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_Rounds++;
	LogMessage("%s round=%d sound_first=%d sound_second=%d sound_saw=%d sound_bad=%d output_fresh=%d output_stale=%d output_miss=%d output_maps=%d userid_ok=%d userid_bad=%d",
		PROBE_TAG, g_Rounds,
		g_SoundFirst, g_SoundSecond, g_SoundSaw, g_SoundBad,
		g_OutputFresh, g_OutputStale, g_OutputMiss, g_OutputMaps,
		g_UserOk, g_UserBad);
}
