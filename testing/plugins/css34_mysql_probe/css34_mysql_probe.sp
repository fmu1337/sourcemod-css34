/**
 * css34_mysql_probe: one synchronous dbi.mysql.ext round trip on request.
 * testing/scripts/mysql-tls-test.sh runs "css34_mysql_probe <databases.cfg entry>"
 * over RCON and reads the result line from the SourceMod log. The plugin does
 * nothing until that server command runs. Kept out of testing/plugins/*.sp, so the
 * botplay suites do not load it.
 */
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "css34_mysql_probe",
	author = "css34",
	description = "dbi.mysql.ext connect + query probe (mysql-tls-test.sh)",
	version = "1.0",
	url = "https://github.com/fmu1337/sourcemod-css34"
};

public void OnPluginStart()
{
	RegServerCmd("css34_mysql_probe", Command_Probe, "<databases.cfg entry>: connect, query, log the result");
}

static void Report(const char[] format, any ...)
{
	char buffer[512];
	VFormat(buffer, sizeof(buffer), format, 2);
	LogMessage("[css34_mysql_probe] %s", buffer);
	PrintToServer("[css34_mysql_probe] %s", buffer);
}

public Action Command_Probe(int args)
{
	char conf[64], error[256];
	if (args != 1)
	{
		Report("FAIL usage: css34_mysql_probe <databases.cfg entry>");
		return Plugin_Handled;
	}
	GetCmdArg(1, conf, sizeof(conf));

	Database db = SQL_Connect(conf, false, error, sizeof(error));
	if (db == null)
	{
		Report("FAIL connect %s: %s", conf, error);
		return Plugin_Handled;
	}

	char ident[16];
	db.Driver.GetIdentifier(ident, sizeof(ident));
	// Ssl_cipher is the server's view of this session ("" without TLS).
	DBResultSet rs = SQL_Query(db,
		"SELECT CONCAT('css34-', 6 * 7), VERSION(), "
		... "(SELECT VARIABLE_VALUE FROM information_schema.SESSION_STATUS WHERE VARIABLE_NAME = 'Ssl_cipher')");
	if (rs == null)
	{
		SQL_GetError(db, error, sizeof(error));
		Report("FAIL query: %s", error);
		delete db;
		return Plugin_Handled;
	}

	char result[32], version[64], cipher[128];
	if (!rs.FetchRow())
	{
		Report("FAIL query returned no row");
	}
	else
	{
		rs.FetchString(0, result, sizeof(result));
		rs.FetchString(1, version, sizeof(version));
		rs.FetchString(2, cipher, sizeof(cipher));
		Report("ok driver=%s result=%s server=%s ssl_cipher='%s'", ident, result, version, cipher);
	}
	delete rs;
	delete db;
	return Plugin_Handled;
}
