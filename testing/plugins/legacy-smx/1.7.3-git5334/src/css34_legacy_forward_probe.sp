/**
 * css34 forward probe for plugins built by old compilers.
 *
 * Production servers keep .smx files built by spcomp 1.7 - 1.11. Upstream
 * SourceMod changes forward argument checking (alliedmodders/sourcemod#2593,
 * #2594), so botplay runs this plugin three times: built by spcomp 1.7.3 and
 * 1.11 (prebuilt in testing/plugins/legacy-smx/) and by the package's own
 * spcomp (compile-botplay-plugins.sh). Each copy
 *
 *  - creates a global forward with mixed parameter types and calls it every
 *    round, twice in a row (a stale error state fails the second call); every
 *    copy listens to it, so each call crosses compiler versions;
 *  - creates a private forward, adds its own callback and calls it;
 *  - calls one of its own functions through Call_StartFunction.
 *
 * Only correctly typed arguments are pushed: an old plugin that worked on
 * SM 1.11 could not push a wrong type (1.11 threw at Call_Push*).
 *
 * Log line, checked by check-legacy-plugins.sh:
 *   [css34_legacy_fwd] compiler=<SOURCEMOD_VERSION of the includes> round=N
 *     ok=N fail=N listeners=N bad_args=N
 *
 * Copies built with includes before 1.13 also call a private forward declared
 * (Param_Cell, Param_VarArgs), three cells per call. SourceMod 1.13 dropped
 * varargs forwards (ICallable rewrite) and #2594 reuses their value (5<<1) for
 * Param_Int64, so this is informational only (check-legacy-plugins.sh
 * enforces it with LEGACY_FWD_REQUIRE_VARARGS=1):
 *   [css34_legacy_fwd] compiler=... varargs calls=N runs=N errors=N last_error=N
 *
 * Keep the syntax buildable by spcomp 1.7.3 (no methodmap forwards, no
 * GlobalForward/PrivateForward types).
 */
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define PROBE_TAG "[css34_legacy_fwd]"
#define PROBE_CELL 1337
#define PROBE_FLOAT 13.5
#define PROBE_STR "css34-legacy"
#define PROBE_ANY 77

Handle g_Global = null;
Handle g_Private = null;
Handle g_VarArgs = null;
int g_VarCalls;
int g_VarRuns;
int g_VarErrors;
int g_VarLastError;
int g_Round;
int g_Ok;
int g_Fail;
int g_Listeners;
int g_BadArgs;
char g_Compiler[32];

public Plugin myinfo =
{
	name = "css34 legacy forward probe",
	author = "sourcemod-css34",
	description = "Global/private forwards with mixed parameter types",
	version = "1.0.0",
	url = "https://github.com/fmu1337/sourcemod-css34"
};

public void OnPluginStart()
{
	Format(g_Compiler, sizeof(g_Compiler), "%s", SOURCEMOD_VERSION);
	g_Global = CreateGlobalForward("Css34Legacy_OnMixed", ET_Hook,
		Param_Cell, Param_Float, Param_String, Param_Array,
		Param_CellByRef, Param_FloatByRef, Param_Any);
	g_Private = CreateForward(ET_Single,
		Param_Cell, Param_Float, Param_String, Param_FloatByRef, Param_Any);
	AddToForward(g_Private, null, Css34Legacy_Private);
#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR < 13
	g_VarArgs = CreateForward(ET_Ignore, Param_Cell, view_as<ParamType>(5<<1));
	AddToForward(g_VarArgs, null, Css34Legacy_VarArgs);
#endif
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	LogMessage("%s compiler=%s loaded", PROBE_TAG, g_Compiler);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_Round++;
	Check(RunGlobal(), "global");
	Check(RunGlobal(), "global-again");
	Check(RunPrivate(), "private");
	Check(RunFunction(), "function");
	LogMessage("%s compiler=%s round=%d ok=%d fail=%d listeners=%d bad_args=%d",
		PROBE_TAG, g_Compiler, g_Round, g_Ok, g_Fail, g_Listeners, g_BadArgs);
	if (g_VarArgs != null) {
		for (int i = 0; i < 2; i++) {
			RunVarArgs();
		}
		LogMessage("%s compiler=%s varargs calls=%d runs=%d errors=%d last_error=%d",
			PROBE_TAG, g_Compiler, g_VarCalls, g_VarRuns, g_VarErrors, g_VarLastError);
	}
}

void RunVarArgs()
{
	g_VarCalls++;
	Call_StartForward(g_VarArgs);
	Call_PushCell(PROBE_CELL);
	Call_PushCell(1);
	Call_PushCell(2);
	Call_PushCell(3);
	int code = Call_Finish();
	if (code != SP_ERROR_NONE) {
		g_VarErrors++;
		g_VarLastError = code;
	}
}

// Never touches the variadic arguments: a core that passes them by value
// instead of by reference would hand it invalid references.
public void Css34Legacy_VarArgs(int cell, any ...)
{
	if (cell == PROBE_CELL) {
		g_VarRuns++;
	}
}

void Check(bool ok, const char[] what)
{
	if (ok) {
		g_Ok++;
	} else {
		g_Fail++;
		LogError("%s compiler=%s FAIL %s round=%d", PROBE_TAG, g_Compiler, what, g_Round);
	}
}

bool RunGlobal()
{
	int arr[3] = {3, 4, 5};
	int cellRef = 0;
	float floatRef = 0.0;
	int result = 0;
	int count = GetForwardFunctionCount(g_Global);
	g_Listeners = count;

	Call_StartForward(g_Global);
	Call_PushCell(PROBE_CELL);
	Call_PushFloat(PROBE_FLOAT);
	Call_PushString(PROBE_STR);
	Call_PushArray(arr, sizeof(arr));
	Call_PushCellRef(cellRef);
	Call_PushFloatRef(floatRef);
	Call_PushCell(PROBE_ANY);
	int err = Call_Finish(result);
	if (err != SP_ERROR_NONE || cellRef != count || floatRef != 0.5 * float(count)) {
		LogError("%s compiler=%s global err=%d count=%d cellRef=%d floatRef=%.1f",
			PROBE_TAG, g_Compiler, err, count, cellRef, floatRef);
		return false;
	}
	return count > 0;
}

public Action Css34Legacy_OnMixed(int cell, float fl, const char[] str, const int[] arr,
	int &cellRef, float &floatRef, any anyv)
{
	if (cell != PROBE_CELL || fl != PROBE_FLOAT || !StrEqual(str, PROBE_STR)
		|| arr[0] != 3 || arr[1] != 4 || arr[2] != 5 || anyv != PROBE_ANY) {
		g_BadArgs++;
		LogError("%s compiler=%s bad global args cell=%d fl=%.2f str=%s arr=%d,%d,%d any=%d",
			PROBE_TAG, g_Compiler, cell, fl, str, arr[0], arr[1], arr[2], anyv);
	}
	cellRef += 1;
	floatRef += 0.5;
	return Plugin_Continue;
}

bool RunPrivate()
{
	float floatRef = 1.0;
	int result = 0;
	Call_StartForward(g_Private);
	Call_PushCell(PROBE_CELL);
	Call_PushFloat(PROBE_FLOAT);
	Call_PushString(PROBE_STR);
	Call_PushFloatRef(floatRef);
	Call_PushFloat(2.5);
	int err = Call_Finish(result);
	if (err != SP_ERROR_NONE || result != PROBE_CELL + 1 || floatRef != 3.0) {
		LogError("%s compiler=%s private err=%d result=%d floatRef=%.1f",
			PROBE_TAG, g_Compiler, err, result, floatRef);
		return false;
	}
	return true;
}

public int Css34Legacy_Private(int cell, float fl, const char[] str, float &floatRef, any anyv)
{
	if (fl != PROBE_FLOAT || !StrEqual(str, PROBE_STR) || view_as<float>(anyv) != 2.5) {
		g_BadArgs++;
		LogError("%s compiler=%s bad private args fl=%.2f str=%s any=%.2f",
			PROBE_TAG, g_Compiler, fl, str, view_as<float>(anyv));
	}
	floatRef *= 3.0;
	return cell + 1;
}

bool RunFunction()
{
	int cellRef = 10;
	int result = 0;
	Call_StartFunction(null, Css34Legacy_Direct);
	Call_PushCell(PROBE_CELL);
	Call_PushFloat(PROBE_FLOAT);
	Call_PushString(PROBE_STR);
	Call_PushCellRef(cellRef);
	int err = Call_Finish(result);
	if (err != SP_ERROR_NONE || result != 1 || cellRef != 11) {
		LogError("%s compiler=%s function err=%d result=%d cellRef=%d",
			PROBE_TAG, g_Compiler, err, result, cellRef);
		return false;
	}
	return true;
}

public int Css34Legacy_Direct(int cell, float fl, const char[] str, int &cellRef)
{
	if (cell != PROBE_CELL || fl != PROBE_FLOAT || !StrEqual(str, PROBE_STR)) {
		return 0;
	}
	cellRef++;
	return 1;
}
