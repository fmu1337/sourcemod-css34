#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>

#define PLUGIN_TAG "[css34_botplay]"
#define MAP_COUNT 3
#define PROBE_RETRY_MAX 8
#define PROBE_RETRY_DELAY 1.5

new Handle:g_CvarRotateEvery;
new g_MapIndex;
new g_RoundCount;
new g_ProbeOk;
new g_ProbeFail;
new bool:g_ClientHooked[MAXPLAYERS + 1];

new const String:g_Maps[MAP_COUNT][] =
{
    "de_dust2",
    "de_inferno",
    "de_nuke"
};

public Plugin:myinfo =
{
    name = "CSS34 Botplay Stress",
    author = "sourcemod-css34 CI",
    description = "Map rotation + sdkhooks/sdktools ABI probe for botplay",
    version = "1.1",
    url = "https://github.com/fmu1337/sourcemod-css34"
};

public OnPluginStart()
{
    g_CvarRotateEvery = CreateConVar("sm_css34_botplay_rotate_every", "3",
        "Change map after this many completed rounds", FCVAR_NOTIFY, true, 1.0, true, 50.0);

    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

    SyncMapIndexToCurrent();
}

SyncMapIndexToCurrent()
{
    new String:current[PLATFORM_MAX_PATH];
    GetCurrentMap(current, sizeof(current));

    g_MapIndex = 0;
    for (new i = 0; i < MAP_COUNT; i++)
    {
        if (StrEqual(current, g_Maps[i], false))
        {
            g_MapIndex = i;
            return;
        }
    }
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    CreateTimer(PROBE_RETRY_DELAY, Timer_RunAbiProbe, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_RunAbiProbe(Handle:timer, any:retry)
{
    new bots = CountBotsInGame();
    if (bots < 1 && retry < PROBE_RETRY_MAX)
    {
        CreateTimer(PROBE_RETRY_DELAY, Timer_RunAbiProbe, retry + 1, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }

    RunAbiProbe(bots);
    LogMessage("%s probe round=%d ok=%d fail=%d bots=%d map=%s",
        PLUGIN_TAG, g_RoundCount + 1, g_ProbeOk, g_ProbeFail, bots, g_Maps[g_MapIndex]);
    return Plugin_Stop;
}

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
    g_RoundCount++;

    new rotateEvery = GetConVarInt(g_CvarRotateEvery);
    if (rotateEvery < 1)
    {
        rotateEvery = 3;
    }

    if (g_RoundCount % rotateEvery != 0)
    {
        return;
    }

    g_MapIndex = (g_MapIndex + 1) % MAP_COUNT;
    LogMessage("%s map_rotate round=%d -> %s", PLUGIN_TAG, g_RoundCount, g_Maps[g_MapIndex]);
    CreateTimer(2.0, Timer_ChangeMap, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_ChangeMap(Handle:timer)
{
    ForceChangeLevel(g_Maps[g_MapIndex], "");
    return Plugin_Stop;
}

CountBotsInGame()
{
    new bots = 0;
    for (new client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && IsFakeClient(client))
        {
            bots++;
        }
    }
    return bots;
}

ProbePass(bool:pass)
{
    if (pass)
    {
        g_ProbeOk++;
    }
    else
    {
        g_ProbeFail++;
    }
}

ProbeEntityClass(const String:classname[])
{
    new ent = FindEntityByClassname(-1, classname);
    ProbePass(ent != -1 && IsValidEntity(ent));
}

RunAbiProbe(bots)
{
    g_ProbeOk = 0;
    g_ProbeFail = 0;

    ProbeEntityClass("worldspawn");
    ProbeEntityClass("info_player_terrorist");
    ProbeEntityClass("info_player_counterterrorist");

    if (bots < 1)
    {
        ProbePass(false);
        LogMessage("%s abi_probe ok=%d fail=%d (no bots yet)", PLUGIN_TAG, g_ProbeOk, g_ProbeFail);
        return;
    }

    for (new client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsFakeClient(client))
        {
            continue;
        }

        ProbeClient(client);
    }

    LogMessage("%s abi_probe ok=%d fail=%d", PLUGIN_TAG, g_ProbeOk, g_ProbeFail);
}

ProbeClient(client)
{
    AttachClientHooksOnce(client);

    new team = GetClientTeam(client);
    ProbePass(team == 2 || team == 3);

    if (!IsPlayerAlive(client))
    {
        return;
    }

    ProbePass(GetClientHealth(client) > 0);

    new weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    ProbePass(weapon == -1 || IsValidEntity(weapon));

    new String:model[PLATFORM_MAX_PATH];
    GetClientModel(client, model, sizeof(model));
    ProbePass(model[0] != '\0');

    new Float:origin[3];
    GetClientAbsOrigin(client, origin);
    ProbePass(origin[0] != 0.0 || origin[1] != 0.0 || origin[2] != 0.0);
}

AttachClientHooksOnce(client)
{
    if (client < 1 || client > MaxClients || g_ClientHooked[client])
    {
        return;
    }

    SDKHook(client, SDKHook_PreThink, Probe_PreThink);
    g_ClientHooked[client] = true;
    ProbePass(true);
}

public Action:Probe_PreThink(client)
{
    return Plugin_Continue;
}
