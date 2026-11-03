#!/usr/bin/env python3
"""Host-side tests of sm13's MySQL ssl_mode / ssl_ca handling; require g++."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SERIES = ROOT / 'builder/patches/series'
CORE = SERIES / 'sm13-latest/sourcemod/0008-dbi-connect-options.patch'
MYSQL = SERIES / 'sm13-latest/sourcemod/0009-mysql-tls-options.patch'
# The values and default of fmu1337/sm-dbi-mysql (MysqlSslConfig.cpp), which
# servers already use in databases.cfg.
SM_DBI_MYSQL_MODES = ['disabled', 'preferred', 'required', 'verify_ca', 'verify_identity']


def section(patch, path):
    text = patch.read_text()
    header = 'diff --git a/' + path + ' b/' + path + '\n'
    if header not in text:
        raise AssertionError(path + ' not in ' + patch.name)
    return text.split(header, 1)[1].split('\ndiff --git ', 1)[0]


def new_file(patch, path):
    """A file the patch adds, as it is after the patch."""
    body = section(patch, path)
    if 'new file mode' not in body.split('\n@@ ', 1)[0]:
        raise AssertionError(path + ' is not a new file in ' + patch.name)
    body = body.split('\n@@ ', 1)[1].split('\n', 1)[1]
    return ''.join(line[1:] + '\n' for line in body.splitlines() if line.startswith('+'))


HARNESS = r'''
#include "MySslOptions.h"
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main(int argc, char **argv)
{
	const char *dir = argv[1]; /* contains ca.pem */
	char ca[1024], error[512];
	MySslSettings s;
	MySslMode m;

	/* Defaults and names */
	CHECK(MySsl_ParseMode(NULL, &m) && m == MySsl_Preferred);
	CHECK(MySsl_ParseMode("", &m) && m == MySsl_Preferred);
	CHECK(MySsl_ParseMode("disabled", &m) && m == MySsl_Disabled);
	CHECK(MySsl_ParseMode("preferred", &m) && m == MySsl_Preferred);
	CHECK(MySsl_ParseMode("required", &m) && m == MySsl_Required);
	CHECK(MySsl_ParseMode("verify_ca", &m) && m == MySsl_VerifyCA);
	CHECK(MySsl_ParseMode("verify_identity", &m) && m == MySsl_VerifyIdentity);
	CHECK(MySsl_ParseMode("VERIFY_IDENTITY", &m) && m == MySsl_VerifyIdentity);
	CHECK(MySsl_ParseMode("Required", &m) && m == MySsl_Required);
	for (int i = MySsl_Disabled; i <= MySsl_VerifyIdentity; i++)
		CHECK(MySsl_ParseMode(MySsl_ModeName((MySslMode)i), &m) && m == i);

	/* Unknown values never downgrade */
	const char *bad[] = {"verify_full", "true", "1", "on", " preferred", "preferred ", "verify-ca",
		"VERIFY_IDENTITY_X", "disable", "require"};
	for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++)
	{
		m = MySsl_VerifyIdentity;
		CHECK(!MySsl_ParseMode(bad[i], &m));
		error[0] = '\0';
		CHECK(!MySsl_Resolve(bad[i], "ca.pem", dir, &s, error, sizeof(error)));
		CHECK(strstr(error, "is not one of disabled, preferred, required, verify_ca, verify_identity"));
		CHECK(strstr(error, bad[i]));
	}

	/* No keys: preferred, no CA */
	CHECK(MySsl_Resolve(NULL, NULL, dir, &s, error, sizeof(error)));
	CHECK(s.mode == MySsl_Preferred && s.ca[0] == '\0');

	/* Only the verify modes read ssl_ca (as sm-dbi-mysql) */
	CHECK(MySsl_Resolve("required", "missing.pem", dir, &s, error, sizeof(error)));
	CHECK(s.mode == MySsl_Required && s.ca[0] == '\0');
	CHECK(MySsl_Resolve("disabled", "missing.pem", dir, &s, error, sizeof(error)));
	CHECK(s.mode == MySsl_Disabled && s.ca[0] == '\0');
	CHECK(MySsl_Resolve("preferred", "missing.pem", dir, &s, error, sizeof(error)));
	CHECK(s.mode == MySsl_Preferred && s.ca[0] == '\0');

	/* Verify modes need a readable CA */
	CHECK(!MySsl_Resolve("verify_ca", NULL, dir, &s, error, sizeof(error)));
	CHECK(strstr(error, "ssl_mode verify_ca needs ssl_ca"));
	CHECK(!MySsl_Resolve("verify_identity", "", dir, &s, error, sizeof(error)));
	CHECK(strstr(error, "ssl_mode verify_identity needs ssl_ca"));
	CHECK(!MySsl_Resolve("verify_identity", "missing.pem", dir, &s, error, sizeof(error)));
	CHECK(strstr(error, "cannot read ssl_ca") && strstr(error, "missing.pem"));

	/* Relative to addons/sourcemod/, absolute kept */
	CHECK(MySsl_Resolve("verify_ca", "ca.pem", dir, &s, error, sizeof(error)));
	snprintf(ca, sizeof(ca), "%s/ca.pem", dir);
	CHECK(s.mode == MySsl_VerifyCA && strcmp(s.ca, ca) == 0);
	CHECK(MySsl_Resolve("verify_identity", ca, "/nonexistent", &s, error, sizeof(error)));
	CHECK(s.mode == MySsl_VerifyIdentity && strcmp(s.ca, ca) == 0);

	/* An over-long path fails instead of truncating to another file */
	char longname[2048];
	memset(longname, 'a', sizeof(longname) - 1);
	longname[sizeof(longname) - 1] = '\0';
	CHECK(!MySsl_Resolve("verify_ca", longname, dir, &s, error, sizeof(error)));
	CHECK(strstr(error, "path too long"));

	printf("%s\n", failures ? "FAILED" : "PASSED");
	return failures ? 1 : 0;
}
'''


class SslOptions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_parser_and_resolver(self):
        for name in ('MySslOptions.h', 'MySslOptions.cpp'):
            (self.root / name).write_text(new_file(MYSQL, 'extensions/mysql/mysql/' + name))
        (self.root / 'harness.cpp').write_text(HARNESS)
        (self.root / 'sm').mkdir()
        (self.root / 'sm/ca.pem').write_text('-----BEGIN CERTIFICATE-----\n')
        binary = self.root / 'harness'
        subprocess.run(['g++', '-std=c++17', '-Wall', '-Werror', '-I', str(self.root),
                        str(self.root / 'MySslOptions.cpp'), str(self.root / 'harness.cpp'),
                        '-o', str(binary)], check=True)
        result = subprocess.run([str(binary), str(self.root / 'sm')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASSED', result.stdout)

    def test_modes_match_sm_dbi_mysql(self):
        source = new_file(MYSQL, 'extensions/mysql/mysql/MySslOptions.cpp')
        table = re.findall(r'\{"([a-z_]+)", MySsl_\w+\}', source)
        self.assertEqual(table, SM_DBI_MYSQL_MODES)
        driver = section(MYSQL, 'extensions/mysql/mysql/MyDriver.cpp')
        self.assertIn('"ssl_mode"', driver)
        self.assertIn('"ssl_ca"', driver)
        self.assertIn('MYSQL_SET_CHARSET_NAME, "utf8mb4"', driver)

    def test_dbi_abi_unchanged(self):
        # DatabaseInfo and the DBI interfaces stay as they are; the keys travel
        # through a separate, new interface.
        for patch in (SERIES / 'sm13-latest').rglob('*.patch'):
            text = patch.read_text()
            self.assertNotIn('b/public/IDBDriver.h', text, patch.name)
            self.assertNotIn('b/public/IShareSys.h', text, patch.name)
        header = new_file(CORE, 'public/IDBConnectOptions.h')
        self.assertIn('#define SMINTERFACE_DBCONNECTOPTIONS_NAME\t\t"IDBConnectOptions"', header)
        self.assertIn('class IDBConnectOptions : public SMInterface', header)
        # Every key of an entry and of SQL_ConnectCustom's KeyValues is kept.
        builder = section(CORE, 'core/logic/DatabaseConfBuilder.cpp')
        self.assertIn('+\t\tm_ParseCurrent->options.emplace_back(key, value);', builder)
        natives = section(CORE, 'core/logic/smn_database.cpp')
        self.assertIn('DBConnectOptionsScope scope(&info, &options);', natives)

    def test_sm12_has_no_tls_options(self):
        # SM 1.12's MySQL 5.6 client bundles yaSSL (TLS <= 1.1, no
        # caching_sha2_password): MySQL 8.4 / HeatWave need sm13.
        for patch in (SERIES / 'sm12-latest').rglob('*.patch'):
            text = patch.read_text()
            self.assertNotIn('ssl_mode', text, patch.name)
            self.assertNotIn('IDBConnectOptions', text, patch.name)


if __name__ == '__main__':
    unittest.main()
