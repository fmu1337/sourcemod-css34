#!/usr/bin/env bash
# Emit configure.py database client path flag(s) for the checked-out SourceMod tree.
set -euo pipefail

db_configure_args() {
  local deps_dir="$1"
  local sourcemod_dir="$2"
  local mariadb_dir="$deps_dir/mariadb-connector-c-3.4.9-x86"

  if grep -q "'--mariadb-path'" "$sourcemod_dir/configure.py" 2>/dev/null \
    || grep -q 'mariadb-path' "$sourcemod_dir/configure.py" 2>/dev/null; then
    printf '%s\n' "--mariadb-path=$mariadb_dir"
  elif [ "${SOURCEMOD_MAJOR:-11}" -ge 13 ]; then
    # SM 1.13.7404 still names the flag --mysql-path but links MariaDB Connector/C.
    printf '%s\n' "--mysql-path=$mariadb_dir"
  else
    printf '%s\n' "--mysql-path=$deps_dir/mysql-5.5"
  fi
}
