/**
 * css34_socket_probe: smoke test of the third-party Socket extension
 * (builder/third-party/socket.sh) with its legacy natives.
 *
 * The server command css34_socket_probe [host] [port] sends an A2S_INFO query
 * ("\xFF\xFF\xFF\xFFTSource Engine Query\0") over UDP to this server (127.0.0.1 and
 * hostport by default) through SocketCreate / SocketSetArg / SocketConnect /
 * SocketSend and waits for the reply in the receive callback. A challenge reply
 * (0x41) is answered once with the challenge appended, as newer engines expect.
 * Results go to addons/sourcemod/logs/css34_socket_probe.log, one line each:
 *   PASS reply type 0x49 bytes=<n> port=<port> hostname_match=<0|1> name=<server name>
 *   FAIL <reason>
 * read by testing/scripts/socket-ext-test.sh. Kept out of testing/plugins/*.sp,
 * which the botplay suites compile for every line (only SOCKET_LINES have socket.inc).
 */
#include <sourcemod>
#include <socket>

#pragma semicolon 1
#pragma newdecls required

#define PROBE_TIMEOUT 10.0

public Plugin myinfo = {
	name = "CSS34 Socket Probe",
	author = "sourcemod-css34",
	description = "A2S_INFO over the Socket extension (legacy natives)",
	version = "1.0.0",
	url = "https://github.com/fmu1337/sourcemod-css34"
};

char g_LogPath[PLATFORM_MAX_PATH];
Socket g_Socket = null;
Handle g_Timeout = null;
bool g_ChallengeSent = false;

public void OnPluginStart()
{
	BuildPath(Path_SM, g_LogPath, sizeof(g_LogPath), "logs/css34_socket_probe.log");
	RegServerCmd("css34_socket_probe", Command_Probe, "A2S_INFO to this server over socket.ext");
}

void Result(const char[] format, any ...)
{
	char line[512];
	VFormat(line, sizeof(line), format, 2);
	PrintToServer("css34_socket_probe: %s", line);
	File f = OpenFile(g_LogPath, "a");
	if (f != null)
	{
		f.WriteLine("%s", line);
		delete f;
	}
}

void Finish()
{
	if (g_Timeout != null)
	{
		KillTimer(g_Timeout);
		g_Timeout = null;
	}
	if (g_Socket != null)
	{
		CloseHandle(g_Socket);
		g_Socket = null;
	}
}

public Action Command_Probe(int args)
{
	char host[64] = "127.0.0.1";
	int port = FindConVar("hostport").IntValue;
	if (args >= 1)
	{
		GetCmdArg(1, host, sizeof(host));
	}
	if (args >= 2)
	{
		char buf[16];
		GetCmdArg(2, buf, sizeof(buf));
		port = StringToInt(buf);
	}
	Finish();
	g_ChallengeSent = false;
	g_Socket = SocketCreate(SOCKET_UDP, OnSocketError);
	if (g_Socket == null)
	{
		Result("FAIL SocketCreate returned null");
		return Plugin_Handled;
	}
	SocketSetArg(g_Socket, port);
	SocketConnect(g_Socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, host, port);
	g_Timeout = CreateTimer(PROBE_TIMEOUT, Timer_Timeout);
	PrintToServer("css34_socket_probe: A2S_INFO to %s:%d", host, port);
	return Plugin_Handled;
}

// "\xFF\xFF\xFF\xFFTSource Engine Query\0" (25 bytes), plus a 4-byte challenge.
int BuildQuery(char[] query, int maxlen, const char[] challenge, int challengeLen)
{
	for (int i = 0; i < 4; i++)
	{
		query[i] = 0xFF;
	}
	int len = 4 + strcopy(query[4], maxlen - 4, "TSource Engine Query") + 1;
	for (int i = 0; i < challengeLen; i++)
	{
		query[len + i] = challenge[i];
	}
	return len + challengeLen;
}

public void OnSocketConnected(Socket socket, any port)
{
	char query[64];
	int len = BuildQuery(query, sizeof(query), "", 0);
	SocketSend(socket, query, len);
}

public void OnSocketReceive(Socket socket, const char[] data, const int size, any port)
{
	if (size < 5)
	{
		Result("FAIL short reply bytes=%d", size);
		Finish();
		return;
	}
	int type = data[4] & 0xFF;
	if (type == 0x41 && size >= 9 && !g_ChallengeSent)
	{
		char challenge[4];
		for (int i = 0; i < 4; i++)
		{
			challenge[i] = data[5 + i];
		}
		char query[64];
		int len = BuildQuery(query, sizeof(query), challenge, 4);
		g_ChallengeSent = true;
		SocketSend(socket, query, len);
		return;
	}
	if (type != 0x49)
	{
		Result("FAIL reply type 0x%02X bytes=%d", type, size);
		Finish();
		return;
	}
	// 0x49, protocol byte, then the server name.
	char name[128];
	strcopy(name, sizeof(name), data[6]);
	char hostname[128];
	FindConVar("hostname").GetString(hostname, sizeof(hostname));
	Result("PASS reply type 0x49 bytes=%d port=%d hostname_match=%d name=%s",
		size, port, StrEqual(name, hostname) ? 1 : 0, name);
	Finish();
}

public void OnSocketDisconnected(Socket socket, any port)
{
	Result("FAIL disconnected before a reply");
	Finish();
}

public void OnSocketError(Socket socket, const int errorType, const int errorNum, any port)
{
	Result("FAIL socket error type=%d errno=%d", errorType, errorNum);
	Finish();
}

public Action Timer_Timeout(Handle timer)
{
	g_Timeout = null;
	Result("FAIL no reply within %.0f s", PROBE_TIMEOUT);
	Finish();
	return Plugin_Stop;
}
