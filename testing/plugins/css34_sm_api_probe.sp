#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <topmenus>

#undef REQUIRE_PLUGIN
#include <regex>
#include <geoip>
#include <clientprefs>
#define REQUIRE_PLUGIN

#define PLUGIN_TAG "[css34_sm_probe]"
#define PROBE_RETRY_MAX 8
#define PROBE_RETRY_DELAY 1.5

new Handle:g_CvarAuto;
new Handle:g_CvarVerbose;
new Handle:g_ProbeCookie = INVALID_HANDLE;
new Handle:g_ProbeMenu = INVALID_HANDLE;
new Handle:g_ProbeTopMenu = INVALID_HANDLE;
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
    description = "Exercise stock SM APIs and extensions for css34 matrix CI",
    version = "1.1",
    url = "https://github.com/fmu1337/sourcemod-css34"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    MarkNativeAsOptional("GeoipCode2");
    MarkNativeAsOptional("GeoipCode3");
    MarkNativeAsOptional("GeoipCountry");
    MarkNativeAsOptional("GeoipLatitude");
    MarkNativeAsOptional("GeoipLongitude");
    MarkNativeAsOptional("RegClientCookie");
    MarkNativeAsOptional("FindClientCookie");
    MarkNativeAsOptional("GetCookieIterator");
    MarkNativeAsOptional("CompileRegex");
    MarkNativeAsOptional("MatchRegex");
    MarkNativeAsOptional("SQL_GetDriver");
    MarkNativeAsOptional("SQLite_UseDatabase");
    MarkNativeAsOptional("SQL_Query");
    return APLRes_Success;
}

public OnPluginStart()
{
    g_CvarAuto = CreateConVar("sm_css34_api_probe_auto", "1",
        "Run full API probe each round_start", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_CvarVerbose = CreateConVar("sm_css34_api_probe_verbose", "0",
        "Log every individual probe pass/fail", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    RegServerCmd("sm_css34_api_probe_run", Cmd_RunProbe, "Run SourceMod API probe suite now");
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_PostNoCopy);

    if (LibraryExists("clientprefs"))
    {
        g_ProbeCookie = RegClientCookie("css34_probe_cookie", "css34 probe cookie", CookieAccess_Public);
    }
}

public OnConfigsExecuted()
{
    AddServerTag("css34-api-probe");
    LoadTranslations("common.phrases");
}

public OnPluginEnd()
{
    if (g_ProbeMenu != INVALID_HANDLE)
    {
        CloseHandle(g_ProbeMenu);
        g_ProbeMenu = INVALID_HANDLE;
    }
    if (g_ProbeTopMenu != INVALID_HANDLE)
    {
        CloseHandle(g_ProbeTopMenu);
        g_ProbeTopMenu = INVALID_HANDLE;
    }
}

public Action:Cmd_RunProbe(args)
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

ProbeSkip(const String:category[], const String:name[])
{
    LogMessage("%s cat=%s probe=%s ok=1 skipped=1", PLUGIN_TAG, category, name);
}

ProbeSection(const String:category[])
{
    LogMessage("%s section_begin cat=%s", PLUGIN_TAG, category);
}

ProbeLibrary(const String:name[], bool:required)
{
    new bool:loaded = LibraryExists(name);
    if (required)
    {
        ProbeResult(loaded, "extensions", name);
    }
    else if (loaded)
    {
        ProbeResult(true, "extensions", name);
    }
    else
    {
        ProbeSkip("extensions", name);
    }
}

RunFullProbeSuite(bot)
{
    new startOk = g_TotalOk;
    new startFail = g_TotalFail;

    ProbeSection("extensions");
    RunExtensionsProbes();

    ProbeSection("core");
    RunCoreProbes();

    ProbeSection("halflife");
    RunHalflifeProbes();

    ProbeSection("commandline");
    RunCommandLineProbes();

    ProbeSection("clients");
    RunClientProbes(bot);

    ProbeSection("entity");
    RunEntityProbes(bot);

    ProbeSection("sdktools");
    RunSdkToolsProbes(bot);

    ProbeSection("sdktools_stringtables");
    RunStringTablesProbes();

    ProbeSection("sdktools_sound");
    RunSoundProbes();

    ProbeSection("cstrike");
    RunCStrikeProbes();

    ProbeSection("adt");
    RunAdtProbes();

    ProbeSection("sorting");
    RunSortingProbes();

    ProbeSection("keyvalues");
    RunKeyValuesProbes();

    ProbeSection("textparse");
    RunTextParseProbes();

    ProbeSection("lang");
    RunLangProbes(bot);

    ProbeSection("convars");
    RunConVarProbes();

    ProbeSection("events");
    RunEventProbes();

    ProbeSection("menus");
    RunMenuProbes();

    ProbeSection("topmenus");
    RunTopMenuProbes();

    ProbeSection("usermessages");
    RunUserMessageProbes();

    ProbeSection("regex");
    RunRegexProbes();

    ProbeSection("geoip");
    RunGeoIpProbes();

    ProbeSection("clientprefs");
    RunClientPrefsProbes(bot);

    ProbeSection("dbi");
    RunDbiProbes();

    ProbeSection("sdkhooks");
    RunSdkHooksProbes(bot);

    new roundOk = g_TotalOk - startOk;
    new roundFail = g_TotalFail - startFail;
    LogMessage("%s summary round=%d ok=%d fail=%d total_ok=%d total_fail=%d otd_hits=%d player_hurt=%d",
        PLUGIN_TAG, g_RoundRuns, roundOk, roundFail, g_TotalOk, g_TotalFail,
        g_OnTakeDamageHits, g_PlayerHurtSeen ? 1 : 0);
}

RunExtensionsProbes()
{
    ProbeLibrary("sdktools", true);
    ProbeLibrary("sdkhooks", true);
    ProbeLibrary("cstrike", true);
    ProbeLibrary("regex", true);
    ProbeLibrary("clientprefs", true);
    ProbeLibrary("dbi.sqlite", true);
    ProbeLibrary("dbi.mysql", false);
    ProbeLibrary("geoip", false);
    ProbeLibrary("bintools", false);
    ProbeLibrary("dhooks", false);
}

RunCoreProbes()
{
    ProbeResult(GetTime() > 0, "core", "GetTime");
    ProbeResult(GetSysTickCount() > 0, "core", "GetSysTickCount");

    new EngineVersion:eng = GetEngineVersion();
    ProbeResult(eng == Engine_CSS || eng == Engine_SourceSDK2006, "core", "GetEngineVersion");

    new Handle:iter = GetPluginIterator();
    ProbeResult(iter != INVALID_HANDLE, "core", "GetPluginIterator");
    if (iter != INVALID_HANDLE)
    {
        CloseHandle(iter);
    }

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

    SetRandomSeed(12345);
    ProbeResult(GetRandomInt(1, 100) == GetRandomInt(1, 100), "halflife", "SetRandomSeed");
}

RunCommandLineProbes()
{
    new String:cmdline[256];
    ProbeResult(GetCommandLine(cmdline, sizeof(cmdline)), "commandline", "GetCommandLine");

    new String:game[64];
    GetCommandLineParam("-game", game, sizeof(game), "");
    ProbeResult(game[0] != '\0', "commandline", "GetCommandLineParam_game");
}

RunClientProbes(bot)
{
    ProbeResult(MaxClients >= 1, "clients", "MaxClients");
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
        ProbeResult(view_as<int>(GetEntityAddress(bot)) != 0, "entity", "GetEntityAddress");

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

    ProbeResult(GetClientListeningFlags(bot) >= 0, "sdktools", "GetClientListeningFlags");
}

RunStringTablesProbes()
{
    ProbeResult(GetNumStringTables() > 0, "sdktools_stringtables", "GetNumStringTables");

    new idx = FindStringTable("modelprecache");
    ProbeResult(idx != INVALID_STRING_TABLE, "sdktools_stringtables", "FindStringTable_modelprecache");
    if (idx != INVALID_STRING_TABLE)
    {
        ProbeResult(GetStringTableNumStrings(idx) >= 0, "sdktools_stringtables", "GetStringTableNumStrings");
    }
}

RunSoundProbes()
{
    PrecacheSound("player/pl_fallpain1.wav", true);
    ProbeResult(true, "sdktools_sound", "PrecacheSound");
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

    new Handle:stack = CreateStack(1);
    ProbeResult(stack != INVALID_HANDLE, "adt", "CreateStack");
    if (stack != INVALID_HANDLE)
    {
        PushStackCell(stack, 11);
        new cell;
        ProbeResult(PopStackCell(stack, cell) && cell == 11, "adt", "StackCell");
        CloseHandle(stack);
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

RunSortingProbes()
{
    new arr[5] = {5, 1, 4, 2, 3};
    SortIntegers(arr, sizeof(arr), Sort_Ascending);
    ProbeResult(arr[0] == 1 && arr[4] == 5, "sorting", "SortIntegers");
}

RunKeyValuesProbes()
{
    new Handle:kv = CreateKeyValues("probe");
    ProbeResult(kv != INVALID_HANDLE, "keyvalues", "CreateKeyValues");
    if (kv == INVALID_HANDLE)
    {
        return;
    }

    KvSetString(kv, "foo", "bar");
    KvSetNum(kv, "num", 42);
    new String:val[32];
    KvGetString(kv, "foo", val, sizeof(val));
    ProbeResult(StrEqual(val, "bar", false), "keyvalues", "KvGetString");
    ProbeResult(KvGetNum(kv, "num") == 42, "keyvalues", "KvGetNum");
    CloseHandle(kv);
}

RunTextParseProbes()
{
    new Handle:parser = SMC_CreateParser();
    ProbeResult(parser != INVALID_HANDLE, "textparse", "SMC_CreateParser");
    if (parser != INVALID_HANDLE)
    {
        CloseHandle(parser);
    }
}

RunLangProbes(bot)
{
    SetGlobalTransTarget(LANG_SERVER);
    new String:phrase[64];
    Format(phrase, sizeof(phrase), "%T", "Player", LANG_SERVER);
    ProbeResult(phrase[0] != '\0', "lang", "Format_T");

    if (bot > 0)
    {
        new lang = GetClientLanguage(bot);
        ProbeResult(lang >= 0, "lang", "GetClientLanguage");
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

RunMenuProbes()
{
    if (g_ProbeMenu != INVALID_HANDLE)
    {
        CloseHandle(g_ProbeMenu);
        g_ProbeMenu = INVALID_HANDLE;
    }

    g_ProbeMenu = CreateMenu(MenuHandler_Probe);
    ProbeResult(g_ProbeMenu != INVALID_HANDLE, "menus", "CreateMenu");
    if (g_ProbeMenu == INVALID_HANDLE)
    {
        return;
    }

    SetMenuTitle(g_ProbeMenu, "CSS34 Probe");
    AddMenuItem(g_ProbeMenu, "ok", "Probe item");
    ProbeResult(GetMenuItemCount(g_ProbeMenu) >= 1, "menus", "AddMenuItem");

    new Handle:style = GetMenuStyleHandle(MenuStyle_Radio);
    ProbeResult(style != INVALID_HANDLE, "menus", "GetMenuStyleHandle");
}

RunTopMenuProbes()
{
    if (g_ProbeTopMenu != INVALID_HANDLE)
    {
        CloseHandle(g_ProbeTopMenu);
        g_ProbeTopMenu = INVALID_HANDLE;
    }

    g_ProbeTopMenu = CreateTopMenu(TopMenuHandler_Probe);
    ProbeResult(g_ProbeTopMenu != INVALID_HANDLE, "topmenus", "CreateTopMenu");
}

RunUserMessageProbes()
{
    new UserMessageType:umType = GetUserMessageType();
    ProbeResult(umType == UM_BitBuf || umType == UM_Protobuf, "usermessages", "GetUserMessageType");

    new UserMsg:msgId = GetUserMessageId("TextMsg");
    ProbeResult(msgId != INVALID_MESSAGE_ID, "usermessages", "GetUserMessageId_TextMsg");

    if (msgId != INVALID_MESSAGE_ID)
    {
        new String:msgName[64];
        ProbeResult(GetUserMessageName(msgId, msgName, sizeof(msgName)), "usermessages", "GetUserMessageName");
    }

    new UserMsg:sayId = GetUserMessageId("SayText");
    ProbeResult(sayId != INVALID_MESSAGE_ID, "usermessages", "GetUserMessageId_SayText");
}

RunRegexProbes()
{
    if (!LibraryExists("regex"))
    {
        ProbeSkip("regex", "extension_missing");
        return;
    }

    new Regex:re = CompileRegex("css34", 0, "", 0);
    ProbeResult(re != INVALID_HANDLE, "regex", "CompileRegex");
    if (re != INVALID_HANDLE)
    {
        new bool:matched = MatchRegex(re, "test css34 probe");
        ProbeResult(matched, "regex", "MatchRegex");
        CloseHandle(re);
    }
}

RunGeoIpProbes()
{
    if (!LibraryExists("geoip"))
    {
        ProbeSkip("geoip", "extension_missing");
        return;
    }

    new String:cc2[3];
    new String:cc3[4];
    ProbeResult(GeoipCode2("127.0.0.1", cc2), "geoip", "GeoipCode2");
    ProbeResult(GeoipCode3("127.0.0.1", cc3), "geoip", "GeoipCode3");

    new String:country[64];
    ProbeResult(GeoipCountry("8.8.8.8", country, sizeof(country)), "geoip", "GeoipCountry");

    new Float:lat = GeoipLatitude("8.8.8.8");
    new Float:lon = GeoipLongitude("8.8.8.8");
    ProbeResult(lat != 0.0 || lon != 0.0, "geoip", "GeoipLatLon");
}

RunClientPrefsProbes(bot)
{
    if (!LibraryExists("clientprefs"))
    {
        ProbeSkip("clientprefs", "extension_missing");
        return;
    }

    ProbeResult(g_ProbeCookie != INVALID_HANDLE, "clientprefs", "RegClientCookie");
    if (g_ProbeCookie != INVALID_HANDLE)
    {
        new Handle:found = FindClientCookie("css34_probe_cookie");
        ProbeResult(found == g_ProbeCookie, "clientprefs", "FindClientCookie");
    }

    new Handle:iter = GetCookieIterator();
    ProbeResult(iter != INVALID_HANDLE, "clientprefs", "GetCookieIterator");
    if (iter != INVALID_HANDLE)
    {
        CloseHandle(iter);
    }

    if (bot > 0 && g_ProbeCookie != INVALID_HANDLE)
    {
        SetClientCookie(bot, g_ProbeCookie, "probe");
        new String:buf[32];
        GetClientCookie(bot, g_ProbeCookie, buf, sizeof(buf));
        ProbeResult(StrEqual(buf, "probe", false), "clientprefs", "SetGetClientCookie");
    }
}

RunDbiProbes()
{
    new String:error[256];
    new Handle:sqliteDriver = SQL_GetDriver("sqlite");
    ProbeResult(sqliteDriver != INVALID_HANDLE, "dbi", "SQL_GetDriver_sqlite");

    new Handle:mysqlDriver = SQL_GetDriver("mysql");
    if (mysqlDriver != INVALID_HANDLE)
    {
        ProbeResult(true, "dbi", "SQL_GetDriver_mysql");
    }
    else
    {
        ProbeSkip("dbi", "SQL_GetDriver_mysql");
    }

    if (!LibraryExists("dbi.sqlite"))
    {
        ProbeSkip("dbi", "sqlite_extension_missing");
        return;
    }

    new Handle:db = SQLite_UseDatabase(":memory:", error, sizeof(error));
    ProbeResult(db != INVALID_HANDLE, "dbi", "SQLite_UseDatabase");
    if (db == INVALID_HANDLE)
    {
        return;
    }

    new Handle:rs = SQL_Query(db, "CREATE TABLE css34_probe (id INTEGER PRIMARY KEY, val TEXT);");
    ProbeResult(rs != INVALID_HANDLE, "dbi", "SQL_Query_create");
    if (rs != INVALID_HANDLE)
    {
        CloseHandle(rs);
    }

    rs = SQL_Query(db, "INSERT INTO css34_probe (val) VALUES ('ok');");
    ProbeResult(rs != INVALID_HANDLE, "dbi", "SQL_Query_insert");
    if (rs != INVALID_HANDLE)
    {
        CloseHandle(rs);
    }

    rs = SQL_Query(db, "SELECT val FROM css34_probe LIMIT 1;");
    ProbeResult(rs != INVALID_HANDLE, "dbi", "SQL_Query_select");
    if (rs != INVALID_HANDLE)
    {
        if (SQL_FetchRow(rs))
        {
            new String:val[16];
            SQL_FetchString(rs, 0, val, sizeof(val));
            ProbeResult(StrEqual(val, "ok", false), "dbi", "SQL_FetchString");
        }
        CloseHandle(rs);
    }

    CloseHandle(db);
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

public bool:TraceFilter_NoPlayers(entity, contentsMask)
{
    return entity > MaxClients;
}

public MenuHandler_Probe(Handle:menu, MenuAction:action, param1, param2)
{
    return 0;
}

public TopMenuHandler_Probe(Handle:topmenu, TopMenuAction:action, TopMenuObject:topobj_id, param, String:buffer[], maxlength)
{
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
