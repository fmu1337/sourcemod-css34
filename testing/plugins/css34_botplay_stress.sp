#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>

#define PLUGIN_TAG "[css34_botplay]"
#define MAP_COUNT 3

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
    version = "1.0",
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
    CreateTimer(1.0, Timer_RunAbiProbe, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_RunAbiProbe(Handle:timer)
{
    RunAbiProbe();
    LogMessage("%s probe round=%d ok=%d fail=%d map=%s",
        PLUGIN_TAG, g_RoundCount + 1, g_ProbeOk, g_ProbeFail, g_Maps[g_MapIndex]);
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

RunAbiProbe()
{
    g_ProbeOk = 0;
    g_ProbeFail = 0;

    new ent = FindEntityByClassname(-1, "worldspawn");
    if (ent != -1 && IsValidEntity(ent))
    {
        g_ProbeOk++;
    }
    else
    {
        g_ProbeFail++;
    }

    ent = FindEntityByClassname(-1, "info_player_start");
    if (ent != -1 && IsValidEntity(ent))
    {
        g_ProbeOk++;
    }
    else
    {
        g_ProbeFail++;
    }

    for (new client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }

        AttachClientHooksOnce(client);

        new team = GetClientTeam(client);
        new health = GetClientHealth(client);
        new alive = IsPlayerAlive(client);

        if (team >= 0 && health >= 0)
        {
            g_ProbeOk++;
        }
        else
        {
            g_ProbeFail++;
        }

        if (alive)
        {
            new weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
            if (weapon == -1 || IsValidEntity(weapon))
            {
                g_ProbeOk++;
            }
            else
            {
                g_ProbeFail++;
            }
        }

        new String:model[PLATFORM_MAX_PATH];
        if (GetEntPropString(client, Prop_Data, "m_ModelName", model, sizeof(model)) >= 0)
        {
            g_ProbeOk++;
        }
        else
        {
            g_ProbeFail++;
        }
    }

    LogMessage("%s abi_probe ok=%d fail=%d", PLUGIN_TAG, g_ProbeOk, g_ProbeFail);
}

AttachClientHooksOnce(client)
{
    if (client < 1 || client > MaxClients || g_ClientHooked[client])
    {
        return;
    }

    SDKHook(client, SDKHook_PreThink, Probe_PreThink);
    g_ClientHooked[client] = true;
    g_ProbeOk++;
}

public Action:Probe_PreThink(client)
{
    return Plugin_Continue;
}
