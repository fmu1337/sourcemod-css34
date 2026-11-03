/**
 * css34_mysql_probe: dbi.mysql.ext connects on request (mysql-tls-test.sh).
 * The script runs these server commands over RCON and reads one result line per
 * label from the SourceMod log; the plugin does nothing until they run. Kept out
 * of testing/plugins/*.sp, so the botplay suites do not load it.
 *
 *   css34_mysql_probe <label> <databases.cfg entry>          SQL_Connect
 *   css34_mysql_probe_persistent <label> <databases.cfg entry>
 *                                                            persistent SQL_Connect, kept open
 *   css34_mysql_probe_async <label> <databases.cfg entry>    Database.Connect (worker thread)
 *   css34_mysql_probe_custom <label> <host> <user> <pass> <ssl_mode> [ssl_ca]
 *                                                            SQL_ConnectCustom
 *
 * Result: "[css34_mysql_probe] <label> ok driver=... result=css34-42 server=...
 * charset=... ssl_version='...' ssl_cipher='...'" (the server's view of the
 * session: empty TLS fields without TLS), or "<label> FAIL <what>: <error>".
 */
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "css34_mysql_probe",
	author = "css34",
	description = "dbi.mysql.ext connect + TLS probe (mysql-tls-test.sh)",
	version = "2.0",
	url = "https://github.com/fmu1337/sourcemod-css34"
};

char g_AsyncLabel[64];
ArrayList g_Persistent;

public void OnPluginStart()
{
	RegServerCmd("css34_mysql_probe", Command_Probe, "<label> <databases.cfg entry>: SQL_Connect, query, log");
	RegServerCmd("css34_mysql_probe_persistent", Command_ProbePersistent,
		"<label> <databases.cfg entry>: persistent SQL_Connect, query, log, keep it open");
	RegServerCmd("css34_mysql_probe_async", Command_ProbeAsync, "<label> <databases.cfg entry>: Database.Connect, query, log");
	RegServerCmd("css34_mysql_probe_custom", Command_ProbeCustom,
		"<label> <host> <user> <pass> <ssl_mode> [ssl_ca]: SQL_ConnectCustom, query, log");
}

static void Report(const char[] label, const char[] format, any ...)
{
	char buffer[768];
	VFormat(buffer, sizeof(buffer), format, 3);
	LogMessage("[css34_mysql_probe] %s %s", label, buffer);
	PrintToServer("[css34_mysql_probe] %s %s", label, buffer);
}

static void Describe(const char[] label, Database db)
{
	char ident[16], error[256];
	db.Driver.GetIdentifier(ident, sizeof(ident));

	DBResultSet rs = SQL_Query(db, "SELECT CONCAT('css34-', 6 * 7), VERSION(), @@character_set_client");
	if (rs == null)
	{
		SQL_GetError(db, error, sizeof(error));
		Report(label, "FAIL query: %s", error);
		return;
	}
	char result[32], version[64], charset[32];
	if (!rs.FetchRow())
	{
		Report(label, "FAIL query returned no row");
		delete rs;
		return;
	}
	rs.FetchString(0, result, sizeof(result));
	rs.FetchString(1, version, sizeof(version));
	rs.FetchString(2, charset, sizeof(charset));
	delete rs;

	// SHOW works on MariaDB and MySQL 8 alike (MySQL has no
	// information_schema.SESSION_STATUS).
	rs = SQL_Query(db, "SHOW SESSION STATUS WHERE Variable_name IN ('Ssl_version', 'Ssl_cipher')");
	if (rs == null)
	{
		SQL_GetError(db, error, sizeof(error));
		Report(label, "FAIL session status: %s", error);
		return;
	}
	char name[32], value[128], tlsVersion[32], cipher[128];
	while (rs.FetchRow())
	{
		rs.FetchString(0, name, sizeof(name));
		rs.FetchString(1, value, sizeof(value));
		if (StrEqual(name, "Ssl_version", false))
			strcopy(tlsVersion, sizeof(tlsVersion), value);
		else if (StrEqual(name, "Ssl_cipher", false))
			strcopy(cipher, sizeof(cipher), value);
	}
	delete rs;
	Report(label, "ok driver=%s result=%s server=%s charset=%s ssl_version='%s' ssl_cipher='%s'",
		ident, result, version, charset, tlsVersion, cipher);
}

public Action Command_Probe(int args)
{
	char label[64], conf[64], error[256];
	if (args != 2)
	{
		Report("-", "FAIL usage: css34_mysql_probe <label> <databases.cfg entry>");
		return Plugin_Handled;
	}
	GetCmdArg(1, label, sizeof(label));
	GetCmdArg(2, conf, sizeof(conf));

	Database db = SQL_Connect(conf, false, error, sizeof(error));
	if (db == null)
	{
		Report(label, "FAIL connect %s: %s", conf, error);
		return Plugin_Handled;
	}
	Describe(label, db);
	delete db;
	return Plugin_Handled;
}

public Action Command_ProbePersistent(int args)
{
	char label[64], conf[64], error[256];
	if (args != 2)
	{
		Report("-", "FAIL usage: css34_mysql_probe_persistent <label> <databases.cfg entry>");
		return Plugin_Handled;
	}
	GetCmdArg(1, label, sizeof(label));
	GetCmdArg(2, conf, sizeof(conf));

	Database db = SQL_Connect(conf, true, error, sizeof(error));
	if (db == null)
	{
		Report(label, "FAIL connect %s: %s", conf, error);
		return Plugin_Handled;
	}
	Describe(label, db);
	// Open until the plugin unloads, so a later persistent connect can match it.
	if (g_Persistent == null)
		g_Persistent = new ArrayList();
	g_Persistent.Push(db);
	return Plugin_Handled;
}

public Action Command_ProbeAsync(int args)
{
	char conf[64];
	if (args != 2)
	{
		Report("-", "FAIL usage: css34_mysql_probe_async <label> <databases.cfg entry>");
		return Plugin_Handled;
	}
	GetCmdArg(1, g_AsyncLabel, sizeof(g_AsyncLabel));
	GetCmdArg(2, conf, sizeof(conf));
	Database.Connect(OnAsyncConnected, conf);
	return Plugin_Handled;
}

public void OnAsyncConnected(Database db, const char[] error, any data)
{
	if (db == null)
	{
		Report(g_AsyncLabel, "FAIL connect (threaded): %s", error);
		return;
	}
	Describe(g_AsyncLabel, db);
	delete db;
}

public Action Command_ProbeCustom(int args)
{
	char label[64], host[128], user[64], pass[64], mode[32], ca[256], error[256];
	if (args < 5 || args > 6)
	{
		Report("-", "FAIL usage: css34_mysql_probe_custom <label> <host> <user> <pass> <ssl_mode> [ssl_ca]");
		return Plugin_Handled;
	}
	GetCmdArg(1, label, sizeof(label));
	GetCmdArg(2, host, sizeof(host));
	GetCmdArg(3, user, sizeof(user));
	GetCmdArg(4, pass, sizeof(pass));
	GetCmdArg(5, mode, sizeof(mode));

	KeyValues kv = new KeyValues("css34_mysql_probe");
	kv.SetString("driver", "mysql");
	kv.SetString("host", host);
	kv.SetString("database", "");
	kv.SetString("user", user);
	kv.SetString("pass", pass);
	kv.SetString("ssl_mode", mode);
	if (args == 6)
	{
		GetCmdArg(6, ca, sizeof(ca));
		kv.SetString("ssl_ca", ca);
	}
	Database db = SQL_ConnectCustom(kv, error, sizeof(error), false);
	delete kv;
	if (db == null)
	{
		Report(label, "FAIL connect (custom): %s", error);
		return Plugin_Handled;
	}
	Describe(label, db);
	delete db;
	return Plugin_Handled;
}
