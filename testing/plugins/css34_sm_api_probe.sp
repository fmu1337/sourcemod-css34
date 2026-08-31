#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#undef REQUIRE_PLUGIN
#include <regex>
#define REQUIRE_PLUGIN

#define PLUGIN_TAG "[css34_sm_probe]"
#define PROBE_RETRY_MAX 8
#define PROBE_RETRY_DELAY 1.5

new Handle:g_CvarAuto;
new Handle:g_CvarVerbose;
new g_RoundRuns;
new g_TotalOk;
new g_TotalFail;
new g_OnTakeDamageHits;
new bool:g_Hooked[MAXPLAYERS + 1];
new bool:g_PlayerHurtSeen;

public Plugin:myinfo =
{
    name = "CSS34 SourceMod API Probe",
    author = "sourcemod-css34 CI",
    description = "Exercise core SM / SDKTools / SDKHooks / CSTrike APIs for css34 matrix CI",
    version = "1.0",
    url = "https://github.com/fmu1337/sourcemod-css34"
};

public OnPluginStart()
{
    g_CvarAuto = CreateConVar("sm_css34_api_probe_auto", "1",
        "Run full API probe each round_start", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_CvarVerbose = CreateConVar("sm_css34_api_probe_verbose", "0",
        "Log every individual probe pass/fail", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    RegServerCmd("sm_css34_api_probe_run", Cmd_RunProbe, "Run SourceMod API probe suite now");
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_PostNoCopy);
}

public OnConfigsExecuted()
{
    AddServerTag("css34-api-probe");
}

public Action:Cmd_RunProbe(client, args)
{
    RunFullProbeSuite(FindProbeBot());
    return Plugin_Handled;
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (GetConVarInt(g_CvarAuto) < 1)
    {
        return;
    }

    CreateTimer(PROBE_RETRY_DELAY, Timer_RunProbe, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
  new victim = GetClientOfUserId(GetEventInt(event, "userid"));
  new dmg = GetEventInt(event, "dmg_health");
  if (victim > 0 && dmg > 0)
  {
    g_PlayerHurtSeen = true;
  }
}

public Action:Timer_RunProbe(Handle:timer, any:retry)
{
    new bot = FindProbeBot();
    if (bot < 1 && retry < PROBE_RETRY_MAX)
    {
        CreateTimer(PROBE_RETRY_DELAY, Timer_RunProbe, retry + 1, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }

    g_RoundRuns++;
    RunFullProbeSuite(bot);
    return Plugin_Stop;
}

FindProbeBot()
{
    for (new client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && IsFakeClient(client))
        {
            return client;
        }
    }
    return 0;
}

ProbeResult(bool:pass, const String:category[], const String:name[])
{
    if (pass)
    {
        g_TotalOk++;
    }
    else
    {
        g_TotalFail++;
    }

    if (GetConVarInt(g_CvarVerbose) > 0 || !pass)
    {
        LogMessage("%s cat=%s probe=%s ok=%d", PLUGIN_TAG, category, name, pass ? 1 : 0);
    }
}

ProbeSection(const String:category[])
{
    LogMessage("%s section_begin cat=%s", PLUGIN_TAG, category);
}

RunFullProbeSuite(bot)
{
    new startOk = g_TotalOk;
    new startFail = g_TotalFail;

    ProbeSection("core");
    RunCoreProbes();

    ProbeSection("halflife");
    RunHalflifeProbes();

    ProbeSection("clients");
    RunClientProbes(bot);

    ProbeSection("entity");
    RunEntityProbes(bot);

    ProbeSection("sdktools");
    RunSdkToolsProbes(bot);

    ProbeSection("cstrike");
    RunCStrikeProbes();

    ProbeSection("adt");
    RunAdtProbes();

    ProbeSection("convars");
    RunConVarProbes();

    ProbeSection("events");
    RunEventProbes();

    ProbeSection("regex");
    RunRegexProbes();

    ProbeSection("sdkhooks");
    RunSdkHooksProbes(bot);

    new roundOk = g_TotalOk - startOk;
    new roundFail = g_TotalFail - startFail;
    LogMessage("%s summary round=%d ok=%d fail=%d total_ok=%d total_fail=%d otd_hits=%d player_hurt=%d",
        PLUGIN_TAG, g_RoundRuns, roundOk, roundFail, g_TotalOk, g_TotalFail,
        g_OnTakeDamageHits, g_PlayerHurtSeen ? 1 : 0);
}

RunCoreProbes()
{
    ProbeResult(GetTime() > 0, "core", "GetTime");
    ProbeResult(GetSysTickCount() > 0, "core", "GetSysTickCount");

    new EngineVersion:eng = GetEngineVersion();
    ProbeResult(eng == Engine_CSS || eng == Engine_SourceSDK2006, "core", "GetEngineVersion");

    ProbeResult(LibraryExists("sdktools"), "core", "LibraryExists_sdktools");
    ProbeResult(LibraryExists("sdkhooks"), "core", "LibraryExists_sdkhooks");
    ProbeResult(LibraryExists("cstrike"), "core", "LibraryExists_cstrike");

    new Handle:iter = GetPluginIterator();
    ProbeResult(iter != INVALID_HANDLE, "core", "GetPluginIterator");
    if (iter != INVALID_HANDLE)
    {
        CloseHandle(iter);
    }

    ProbeResult(LibraryExists("regex"), "core", "LibraryExists_regex");

    new Handle:gd = LoadGameConfigFile("sdkhooks.games");
    ProbeResult(gd != INVALID_HANDLE, "core", "LoadGameConfigFile_sdkhooks");
    if (gd != INVALID_HANDLE)
    {
        new offset = GameConfGetOffset(gd, "OnTakeDamage");
        ProbeResult(offset > 0, "core", "GameConfGetOffset_OnTakeDamage");
        CloseHandle(gd);
    }
}

RunHalflifeProbes()
{
    new String:folder[PLATFORM_MAX_PATH];
    GetGameFolderName(folder, sizeof(folder));
    ProbeResult(folder[0] == 'c', "halflife", "GetGameFolderName");

    new String:map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));
    ProbeResult(map[0] != '\0', "halflife", "GetCurrentMap");

    ProbeResult(GetGameTime() >= 0.0, "halflife", "GetGameTime");
    ProbeResult(GetGameTickCount() >= 0, "halflife", "GetGameTickCount");
    ProbeResult(GetTickInterval() > 0.0, "halflife", "GetTickInterval");
    ProbeResult(IsDedicatedServer(), "halflife", "IsDedicatedServer");
    ProbeResult(IsMapValid("de_dust2"), "halflife", "IsMapValid");

    new String:display[PLATFORM_MAX_PATH];
    GetMapDisplayName("de_dust2", display, sizeof(display));
    ProbeResult(display[0] != '\0', "halflife", "GetMapDisplayName");

    new r1 = GetRandomInt(1, 100);
    new r2 = GetRandomInt(1, 100);
    ProbeResult(r1 >= 1 && r1 <= 100, "halflife", "GetRandomInt");
    SetRandomSeed(12345);
    ProbeResult(GetRandomInt(1, 100) == GetRandomInt(1, 100), "halflife", "SetRandomSeed");
}

RunClientProbes(bot)
{
    ProbeResult(GetMaxClients() >= 1, "clients", "GetMaxClients");
    ProbeResult(GetClientCount() >= 0, "clients", "GetClientCount");

    if (bot < 1)
    {
        ProbeResult(false, "clients", "bot_present");
        return;
    }

    ProbeResult(IsClientInGame(bot), "clients", "IsClientInGame");
    ProbeResult(IsFakeClient(bot), "clients", "IsFakeClient");

    new String:cname[MAX_NAME_LENGTH];
    GetClientName(bot, cname, sizeof(cname));
    ProbeResult(cname[0] != '\0', "clients", "GetClientName");

    new team = GetClientTeam(bot);
    ProbeResult(team == 2 || team == 3, "clients", "GetClientTeam");

    new userid = GetClientUserId(bot);
    ProbeResult(GetClientOfUserId(userid) == bot, "clients", "GetClientOfUserId");

    new serial = GetClientSerial(bot);
    ProbeResult(GetClientFromSerial(serial) == bot, "clients", "GetClientSerial");

    if (IsPlayerAlive(bot))
    {
        ProbeResult(GetClientHealth(bot) > 0, "clients", "GetClientHealth");
        ProbeResult(GetClientArmor(bot) >= 0, "clients", "GetClientArmor");

        new String:model[PLATFORM_MAX_PATH];
        GetClientModel(bot, model, sizeof(model));
        ProbeResult(model[0] != '\0', "clients", "GetClientModel");

        new Float:origin[3];
        GetClientAbsOrigin(bot, origin);
        ProbeResult(origin[2] != 0.0, "clients", "GetClientAbsOrigin");

        new String:weapon[64];
        GetClientWeapon(bot, weapon, sizeof(weapon));
        ProbeResult(weapon[0] != '\0', "clients", "GetClientWeapon");
    }
}

RunEntityProbes(bot)
{
    ProbeResult(GetMaxEntities() > 0, "entity", "GetMaxEntities");
    ProbeResult(GetEntityCount() > 0, "entity", "GetEntityCount");

    new ent = FindEntityByClassname(-1, "worldspawn");
    ProbeResult(ent != -1 && IsValidEntity(ent), "entity", "worldspawn");

    new String:cls[64];
    if (ent != -1)
    {
        GetEntityClassname(ent, cls, sizeof(cls));
        ProbeResult(StrEqual(cls, "worldspawn", false), "entity", "GetEntityClassname");
    }

    if (bot > 0 && IsClientInGame(bot) && IsPlayerAlive(bot))
    {
        ProbeResult(HasEntProp(bot, Prop_Send, "m_iHealth"), "entity", "HasEntProp_health");
        ProbeResult(GetEntProp(bot, Prop_Send, "m_iHealth") > 0, "entity", "GetEntProp_health");
        ProbeResult(HasEntProp(bot, Prop_Send, "m_ArmorValue"), "entity", "HasEntProp_armor");
        ProbeResult(GetEntityAddress(bot) != 0, "entity", "GetEntityAddress");

        new weapon = GetEntPropEnt(bot, Prop_Send, "m_hActiveWeapon");
        ProbeResult(weapon == -1 || IsValidEntity(weapon), "entity", "GetEntPropEnt_weapon");
    }
}

RunSdkToolsProbes(bot)
{
    ProbeResult(GetTeamCount() >= 2, "sdktools", "GetTeamCount");

    new String:tname[32];
    GetTeamName(2, tname, sizeof(tname));
    ProbeResult(tname[0] != '\0', "sdktools", "GetTeamName");

    ProbeResult(GetTeamScore(2) >= 0, "sdktools", "GetTeamScore");
    ProbeResult(GetTeamClientCount(2) >= 0, "sdktools", "GetTeamClientCount");

    if (bot < 1 || !IsClientInGame(bot) || !IsPlayerAlive(bot))
    {
        ProbeResult(false, "sdktools", "bot_alive_for_trace");
        return;
    }

    new Float:eye[3];
    GetClientEyePosition(bot, eye);
    ProbeResult(eye[2] > 0.0, "sdktools", "GetClientEyePosition");

    new Float:angles[3];
    GetClientEyeAngles(bot, angles);
    ProbeResult(angles[0] != 0.0 || angles[1] != 0.0, "sdktools", "GetClientEyeAngles");

    new Float:dir[3];
    GetAngleVectors(angles, dir, NULL_VECTOR, NULL_VECTOR);

    new target = GetClientAimTarget(bot, true);
    ProbeResult(target == -1 || IsValidEntity(target), "sdktools", "GetClientAimTarget");

    new Handle:trace = TR_TraceRayFilterEx(eye, dir, MASK_SOLID, RayType_Infinite, TraceFilter_NoPlayers);
    ProbeResult(trace != INVALID_HANDLE, "sdktools", "TR_TraceRayFilterEx");
    if (trace != INVALID_HANDLE)
    {
        ProbeResult(TR_DidHit(trace), "sdktools", "TR_DidHit");
        new Float:endpos[3];
        TR_GetEndPosition(endpos, trace);
        ProbeResult(endpos[0] != 0.0 || endpos[1] != 0.0, "sdktools", "TR_GetEndPosition");
        CloseHandle(trace);
    }

    new slot = GetPlayerWeaponSlot(bot, 0);
    ProbeResult(slot == -1 || IsValidEntity(slot), "sdktools", "GetPlayerWeaponSlot");
}

public bool:TraceFilter_NoPlayers(entity, contentsMask)
{
    return entity > MaxClients;
}

RunCStrikeProbes()
{
    new scoreT = CS_GetTeamScore(CS_TEAM_T);
    new scoreCT = CS_GetTeamScore(CS_TEAM_CT);
    ProbeResult(scoreT >= 0 && scoreCT >= 0, "cstrike", "CS_GetTeamScore");

    new bot = FindProbeBot();
    if (bot > 0)
    {
        new mvp = CS_GetMVPCount(bot);
        ProbeResult(mvp >= 0, "cstrike", "CS_GetMVPCount");
    }

    ProbeResult(CS_IsValidWeaponID(CSWeapon_AK47), "cstrike", "CS_IsValidWeaponID");
    ProbeResult(CS_AliasToWeaponID("ak47") == CSWeapon_AK47, "cstrike", "CS_AliasToWeaponID");

    new String:alias[32];
    CS_WeaponIDToAlias(CSWeapon_AK47, alias, sizeof(alias));
    ProbeResult(alias[0] != '\0', "cstrike", "CS_WeaponIDToAlias");

    new String:translated[32];
    CS_GetTranslatedWeaponAlias("ak47", translated, sizeof(translated));
    ProbeResult(translated[0] != '\0', "cstrike", "CS_GetTranslatedWeaponAlias");
}

RunAdtProbes()
{
    new Handle:arr = CreateArray(1);
    ProbeResult(arr != INVALID_HANDLE, "adt", "CreateArray");
    if (arr != INVALID_HANDLE)
    {
        PushArrayCell(arr, 42);
        ProbeResult(GetArrayCell(arr, 0) == 42, "adt", "PushArrayCell");
        ClearArray(arr);
        CloseHandle(arr);
    }

    new Handle:trie = CreateTrie();
    ProbeResult(trie != INVALID_HANDLE, "adt", "CreateTrie");
    if (trie != INVALID_HANDLE)
    {
        SetTrieValue(trie, "key", 7);
        new val;
        ProbeResult(GetTrieValue(trie, "key", val) && val == 7, "adt", "TrieValue");
        CloseHandle(trie);
    }

    new Handle:pack = CreateDataPack();
    ProbeResult(pack != INVALID_HANDLE, "adt", "CreateDataPack");
    if (pack != INVALID_HANDLE)
    {
        WritePackCell(pack, 99);
        ResetPack(pack);
        ProbeResult(ReadPackCell(pack) == 99, "adt", "DataPack");
        CloseHandle(pack);
    }

    new String:path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/css34_probe");
    ProbeResult(path[0] != '\0', "adt", "BuildPath");

    new String:testfile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, testfile, sizeof(testfile), "data/css34_probe/probe.txt");
    new Handle:f = OpenFile(testfile, "w");
    ProbeResult(f != INVALID_HANDLE, "adt", "OpenFile");
    if (f != INVALID_HANDLE)
    {
        WriteFileLine(f, "css34");
        CloseHandle(f);
        ProbeResult(FileExists(testfile), "adt", "FileExists");
        DeleteFile(testfile);
    }
}

RunConVarProbes()
{
    new Handle:cv = FindConVar("bot_quota");
    ProbeResult(cv != INVALID_HANDLE, "convars", "FindConVar");
    if (cv != INVALID_HANDLE)
    {
        ProbeResult(GetConVarInt(cv) >= 0, "convars", "GetConVarInt");
    }

    new Handle:own = FindConVar("sm_css34_api_probe_auto");
    ProbeResult(own != INVALID_HANDLE, "convars", "plugin_cvar");
}

RunEventProbes()
{
    ProbeResult(g_PlayerHurtSeen, "events", "player_hurt_seen");
}

RunRegexProbes()
{
    if (!LibraryExists("regex"))
    {
        ProbeResult(true, "regex", "skipped_no_ext");
        return;
    }

    new Regex:re = CompileRegex("css34", 0, "", 0);
    ProbeResult(re != INVALID_HANDLE, "regex", "CompileRegex");
    if (re != INVALID_HANDLE)
    {
        ProbeResult(MatchRegex(re, "test css34 probe"), "regex", "MatchRegex");
        CloseHandle(re);
    }
}

RunSdkHooksProbes(bot)
{
    if (bot < 1 || !IsClientInGame(bot))
    {
        ProbeResult(false, "sdkhooks", "bot_present");
        return;
    }

    AttachHooksOnce(bot);
    ProbeResult(g_Hooked[bot], "sdkhooks", "SDKHook_attached");
}

AttachHooksOnce(client)
{
    if (client < 1 || client > MaxClients || g_Hooked[client])
    {
        return;
    }

    SDKHook(client, SDKHook_PreThink, Hook_PreThink);
    SDKHook(client, SDKHook_PostThink, Hook_PostThink);
    SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
    SDKHook(client, SDKHook_WeaponSwitch, Hook_WeaponSwitch);
    g_Hooked[client] = true;
}

public Action:Hook_PreThink(client)
{
    return Plugin_Continue;
}

public Action:Hook_PostThink(client)
{
    return Plugin_Continue;
}

public Action:Hook_WeaponSwitch(client, weapon)
{
    return Plugin_Continue;
}

public Action:Hook_OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
    if (victim >= 1 && victim <= MaxClients && IsClientInGame(victim))
    {
        g_OnTakeDamageHits++;
        if ((g_OnTakeDamageHits % 50) == 1)
        {
            LogMessage("%s on_take_damage victim=%d attacker=%d dmg=%.1f hits=%d",
                PLUGIN_TAG, victim, attacker, damage, g_OnTakeDamageHits);
        }
    }
    return Plugin_Continue;
}
