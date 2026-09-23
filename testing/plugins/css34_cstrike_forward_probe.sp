/**
 * css34 cstrike forward probe.
 *
 * Registers every cstrike.ext detour-backed forward so the extension installs
 * its HandleCommand_Buy_Internal / GetWeaponPrice / TerminateRound /
 * CSWeaponDrop hooks, counts how often each fires and logs the counters on
 * every round_end. On Metamod 2.0 KHook lines these hooks run on KHook instead
 * of CDetour/SourceHook.
 *
 * css34_cs_probe_mode is a bit mask; 0 (default) is passive and every forward
 * returns Plugin_Continue.
 *   1 = block "flashbang" buys (Plugin_Handled)
 *   2 = halve weapon prices (Plugin_Changed)
 *   4 = shorten the round end delay (Plugin_Changed)
 */
#include <sourcemod>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "css34 cstrike forward probe",
	author = "sourcemod-css34",
	description = "Counts cstrike.ext detour forwards (buy, price, terminate, drop)",
	version = "1.0.0",
	url = "https://github.com/fmu1337/sourcemod-css34"
};

ConVar g_Mode;
int g_Buy;
int g_Price;
int g_Terminate;
int g_Drop;
int g_Blocked;
int g_Rounds;

public void OnPluginStart()
{
	g_Mode = CreateConVar("css34_cs_probe_mode", "0", "Bit mask: 1 block flashbang buys, 2 halve prices, 4 shorten round end delay; 0 = passive");
	HookEvent("round_end", Event_RoundEnd);
}

public Action CS_OnBuyCommand(int client, const char[] weapon)
{
	g_Buy++;
	if ((g_Mode.IntValue & 1) && StrEqual(weapon, "flashbang"))
	{
		g_Blocked++;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action CS_OnGetWeaponPrice(int client, const char[] weapon, int &price)
{
	g_Price++;
	if ((g_Mode.IntValue & 2) && price > 1)
	{
		price /= 2;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action CS_OnTerminateRound(float &delay, CSRoundEndReason &reason)
{
	g_Terminate++;
	if (g_Mode.IntValue & 4)
	{
		delay = 2.0;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action CS_OnCSWeaponDrop(int client, int weaponIndex, bool donated)
{
	g_Drop++;
	return Plugin_Continue;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_Rounds++;
	LogMessage("[css34_cs_probe] round=%d mode=%d buy=%d price=%d terminate=%d drop=%d blocked=%d",
		g_Rounds, g_Mode.IntValue, g_Buy, g_Price, g_Terminate, g_Drop, g_Blocked);
}
