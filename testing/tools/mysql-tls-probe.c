/*
 * css34_mysql_tls_probe: TLS through the MariaDB Connector/C and OpenSSL
 * archives that builder/run/linux.sh links into dbi.mysql.ext (same static
 * libraries, same link group, same build image). Never released.
 *
 *   css34_mysql_tls_probe tls|plain|wrong-ca
 *
 * Environment: MYSQL_TLS_HOST, MYSQL_TLS_PORT (3306), MYSQL_TLS_USER,
 * MYSQL_TLS_PASS, MYSQL_TLS_CA (the server's CA), MYSQL_TLS_WRONG_CA.
 *
 *   tls       verified TLS (CA + host name) must connect; the client and the
 *             server must both report the session encrypted, and the TLS
 *             library must be the OpenSSL whose headers the build used
 *   plain     SourceMod's options (no TLS requested, peer verification off)
 *             must be refused by a REQUIRE SSL account (1045)
 *   wrong-ca  verification against another CA must fail (2026)
 *
 * Exit status 0 means the expectation of the mode held.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <mysql.h>
#include <errmsg.h>
#include <mysqld_error.h>
#include <openssl/opensslv.h>

static const char *env(const char *name, const char *fallback)
{
	const char *value = getenv(name);
	if (value && *value)
		return value;
	if (fallback)
		return fallback;
	fprintf(stderr, "css34_mysql_tls_probe: FAIL: %s is not set\n", name);
	exit(2);
}

static MYSQL *open_connection(int tls, const char *ca)
{
	MYSQL *mysql = mysql_init(NULL);
	unsigned int timeout = 20;
	my_bool verify = tls ? 1 : 0;

	if (!mysql)
	{
		fprintf(stderr, "css34_mysql_tls_probe: FAIL: mysql_init\n");
		exit(2);
	}
	mysql_options(mysql, MYSQL_OPT_CONNECT_TIMEOUT, &timeout);
	mysql_options(mysql, MYSQL_OPT_READ_TIMEOUT, &timeout);
	mysql_options(mysql, MYSQL_OPT_WRITE_TIMEOUT, &timeout);
	/* What SourceMod's MyDriver.cpp sets; TLS modes then turn it back on. */
	mysql_options(mysql, MYSQL_OPT_SSL_VERIFY_SERVER_CERT, &verify);
	if (tls)
	{
		my_bool enforce = 1;
		mysql_options(mysql, MYSQL_OPT_SSL_CA, ca);
		mysql_options(mysql, MYSQL_OPT_SSL_ENFORCE, &enforce);
	}
	return mysql;
}

static int connect_to(MYSQL *mysql)
{
	return mysql_real_connect(mysql, env("MYSQL_TLS_HOST", NULL), env("MYSQL_TLS_USER", NULL),
		env("MYSQL_TLS_PASS", NULL), NULL, (unsigned int)atoi(env("MYSQL_TLS_PORT", "3306")),
		NULL, 0) != NULL;
}

/* The server's view of this session: Ssl_cipher and Ssl_version. */
static int server_status(MYSQL *mysql, char *cipher, char *version, size_t size)
{
	MYSQL_RES *res;
	MYSQL_ROW row;

	cipher[0] = version[0] = '\0';
	if (mysql_query(mysql, "SHOW SESSION STATUS WHERE Variable_name IN ('Ssl_cipher', 'Ssl_version')")
		|| !(res = mysql_store_result(mysql)))
	{
		fprintf(stderr, "css34_mysql_tls_probe: FAIL: session status: %s\n", mysql_error(mysql));
		return 0;
	}
	while ((row = mysql_fetch_row(res)))
	{
		if (row[0] && row[1] && !strcmp(row[0], "Ssl_cipher"))
			snprintf(cipher, size, "%s", row[1]);
		else if (row[0] && row[1] && !strcmp(row[0], "Ssl_version"))
			snprintf(version, size, "%s", row[1]);
	}
	mysql_free_result(res);
	return 1;
}

static int probe_tls(void)
{
	MYSQL *mysql = open_connection(1, env("MYSQL_TLS_CA", NULL));
	const char *client_cipher, *client_version = NULL, *library = NULL;
	char server_cipher[128], server_version[64];
	int ok = 1;

	if (!connect_to(mysql))
	{
		fprintf(stderr, "css34_mysql_tls_probe: FAIL: verified TLS connect: [%u] %s\n",
			mysql_errno(mysql), mysql_error(mysql));
		mysql_close(mysql);
		return 1;
	}
	client_cipher = mysql_get_ssl_cipher(mysql);
	mariadb_get_infov(mysql, MARIADB_CONNECTION_TLS_VERSION, &client_version);
	mariadb_get_infov(mysql, MARIADB_TLS_LIBRARY, &library);
	if (!server_status(mysql, server_cipher, server_version, sizeof(server_cipher)))
		ok = 0;
	printf("css34_mysql_tls_probe: server=%s client_cipher=%s client_version=%s"
		" server_cipher=%s server_version=%s library=%s built_with=%s\n",
		mysql_get_server_info(mysql), client_cipher ? client_cipher : "(none)",
		client_version ? client_version : "(none)", server_cipher, server_version,
		library ? library : "(none)", OPENSSL_VERSION_TEXT);
	if (!client_cipher || !client_version || !server_cipher[0] || !server_version[0])
	{
		fprintf(stderr, "css34_mysql_tls_probe: FAIL: the session is not encrypted\n");
		ok = 0;
	}
	else if (strcmp(client_cipher, server_cipher) || strcmp(client_version, server_version))
	{
		fprintf(stderr, "css34_mysql_tls_probe: FAIL: client and server disagree on the TLS session\n");
		ok = 0;
	}
	if (!library || strcmp(library, OPENSSL_VERSION_TEXT))
	{
		fprintf(stderr, "css34_mysql_tls_probe: FAIL: TLS library is not %s\n", OPENSSL_VERSION_TEXT);
		ok = 0;
	}
	mysql_close(mysql);
	if (ok)
		printf("css34_mysql_tls_probe: OK: verified TLS session\n");
	return ok ? 0 : 1;
}

static int probe_refused(int tls, const char *ca, unsigned int expect, const char *what)
{
	MYSQL *mysql = open_connection(tls, ca);
	unsigned int err;

	if (connect_to(mysql))
	{
		fprintf(stderr, "css34_mysql_tls_probe: FAIL: %s connected\n", what);
		mysql_close(mysql);
		return 1;
	}
	err = mysql_errno(mysql);
	printf("css34_mysql_tls_probe: %s refused: [%u] %s\n", what, err, mysql_error(mysql));
	mysql_close(mysql);
	if (err != expect)
	{
		fprintf(stderr, "css34_mysql_tls_probe: FAIL: %s: expected error %u\n", what, expect);
		return 1;
	}
	printf("css34_mysql_tls_probe: OK: %s refused\n", what);
	return 0;
}

int main(int argc, char **argv)
{
	int rc;

	if (argc != 2)
	{
		fprintf(stderr, "usage: css34_mysql_tls_probe tls|plain|wrong-ca\n");
		return 2;
	}
	if (mysql_library_init(0, NULL, NULL))
	{
		fprintf(stderr, "css34_mysql_tls_probe: FAIL: mysql_library_init\n");
		return 2;
	}
	if (!strcmp(argv[1], "tls"))
		rc = probe_tls();
	else if (!strcmp(argv[1], "plain"))
		rc = probe_refused(0, NULL, ER_ACCESS_DENIED_ERROR, "plaintext login of a REQUIRE SSL account");
	else if (!strcmp(argv[1], "wrong-ca"))
		rc = probe_refused(1, env("MYSQL_TLS_WRONG_CA", NULL), CR_SSL_CONNECTION_ERROR,
			"TLS against another CA");
	else
	{
		fprintf(stderr, "css34_mysql_tls_probe: unknown mode %s\n", argv[1]);
		rc = 2;
	}
	mysql_library_end();
	return rc;
}
