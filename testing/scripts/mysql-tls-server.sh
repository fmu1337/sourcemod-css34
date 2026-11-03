#!/usr/bin/env bash
# MariaDB and MySQL servers for testing/scripts/mysql-tls-test.sh (T4.5), on the
# CI host.
#
#   mysql-tls-server.sh start DIR   write a throwaway CA, one server certificate
#                                   for css34-mariadb and css34-mysql (DNS names
#                                   only, no IP address) and an unrelated CA to
#                                   DIR ({ca,server,server-key,wrong-ca}.pem), then
#                                   run containers css34-mariadb and css34-mysql
#                                   with TLS, and css34-mysql-notls with TLS
#                                   turned off, on network css34-db
#   mysql-tls-server.sh stop        remove them and the network (logs are
#                                   printed first)
#
# Accounts on both: css34_tls (REQUIRE SSL) and css34_plain. MariaDB uses
# mysql_native_password; MySQL uses caching_sha2_password, its default and the
# only one MySQL 8.4 / HeatWave enable. Images "mariadb:11.8" and "mysql:8.4"
# from builder/lines.json (pinned by digest).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
name=css34-mariadb
mysql_name=css34-mysql
notls_name=css34-mysql-notls
network=css34-db
image_name="mariadb:11.8"
mysql_image_name="mysql:8.4"

docker_cmd() { if docker info >/dev/null 2>&1; then docker "$@"; else sudo docker "$@"; fi; }
die() { echo "FAIL: $*" >&2; exit 1; }

image_ref() { # [image name]
  python3 - "$root/builder/lines.json" "${1:-$image_name}" <<'PY'
import json, sys
images = json.load(open(sys.argv[1]))["images"]
print("{}@{}".format(sys.argv[2], images[sys.argv[2]]))
PY
}

make_certs() {
  local dir="$1"
  mkdir -p "$dir"
  (
    cd "$dir"
    rm -f ./*.pem ./*.csr ./*.srl
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 2 -subj "/CN=css34 probe CA" \
      -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
      -keyout ca-key.pem -out ca.pem 2>/dev/null
    openssl req -newkey rsa:2048 -nodes -sha256 -subj "/CN=${name}" \
      -keyout server-key.pem -out server.csr 2>/dev/null
    # No IP address: verify_identity by address must fail, verify_ca must not.
    printf '%s\n' "subjectAltName=DNS:${name},DNS:${mysql_name}" "basicConstraints=critical,CA:FALSE" \
      "keyUsage=critical,digitalSignature,keyEncipherment" "extendedKeyUsage=serverAuth" >server.ext
    openssl x509 -req -sha256 -days 2 -in server.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
      -extfile server.ext -out server.pem 2>/dev/null
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 2 -subj "/CN=css34 unrelated CA" \
      -addext "basicConstraints=critical,CA:TRUE" -keyout wrong-ca-key.pem -out wrong-ca.pem 2>/dev/null
    openssl verify -CAfile ca.pem server.pem >/dev/null
    # Throwaway test keys; the server runs as another uid inside the container.
    chmod 0644 ./*.pem
  )
}

wait_ready() { # container, readiness command...
  local container="$1" deadline=$((SECONDS + 180))
  shift
  until docker_cmd exec "$container" "$@" >/dev/null 2>&1; do
    if [[ "$(docker_cmd inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" != true ]]; then
      docker_cmd logs "$container" 2>&1 | tail -n 40
      die "${container} exited during startup"
    fi
    (( SECONDS < deadline )) || { docker_cmd logs "$container" 2>&1 | tail -n 40; die "${container} did not become ready"; }
    sleep 2
  done
}

start() {
  local dir="${1:?certificate directory required}"
  local image mysql_image init mysql_init
  image="$(image_ref)"
  mysql_image="$(image_ref "$mysql_image_name")"
  make_certs "$dir"
  dir="$(cd "$dir" && pwd)"
  init="$dir/init.sql"
  mysql_init="$dir/init-mysql.sql"
  cat >"$init" <<'SQL'
CREATE USER 'css34_tls'@'%' IDENTIFIED VIA mysql_native_password USING PASSWORD('css34-tls-probe') REQUIRE SSL;
CREATE USER 'css34_plain'@'%' IDENTIFIED VIA mysql_native_password USING PASSWORD('css34-plain-probe');
SQL
  cat >"$mysql_init" <<'SQL'
CREATE USER 'css34_tls'@'%' IDENTIFIED WITH caching_sha2_password BY 'css34-tls-probe' REQUIRE SSL;
CREATE USER 'css34_plain'@'%' IDENTIFIED WITH caching_sha2_password BY 'css34-plain-probe';
SQL
  chmod 0644 "$init" "$mysql_init"
  docker_cmd rm -f "$name" "$mysql_name" "$notls_name" >/dev/null 2>&1 || true
  docker_cmd network inspect "$network" >/dev/null 2>&1 || docker_cmd network create "$network" >/dev/null
  echo "==> Starting ${name} (${image}) and ${mysql_name} (${mysql_image}) with TLS on network ${network}"
  docker_cmd run -d --name "$name" --network "$network" \
    -e MARIADB_RANDOM_ROOT_PASSWORD=1 \
    -v "$dir:/certs:ro" \
    -v "$init:/docker-entrypoint-initdb.d/css34.sql:ro" \
    "$image" \
    --ssl-ca=/certs/ca.pem --ssl-cert=/certs/server.pem --ssl-key=/certs/server-key.pem >/dev/null
  docker_cmd run -d --name "$mysql_name" --network "$network" \
    -e MYSQL_RANDOM_ROOT_PASSWORD=yes \
    -v "$dir:/certs:ro" \
    -v "$mysql_init:/docker-entrypoint-initdb.d/css34.sql:ro" \
    "$mysql_image" \
    --ssl-ca=/certs/ca.pem --ssl-cert=/certs/server.pem --ssl-key=/certs/server-key.pem \
    --tls-version=TLSv1.2,TLSv1.3 >/dev/null
  # A server that offers no TLS: required and the verify modes must refuse it.
  docker_cmd run -d --name "$notls_name" --network "$network" \
    -e MYSQL_RANDOM_ROOT_PASSWORD=yes \
    -v "$mysql_init:/docker-entrypoint-initdb.d/css34.sql:ro" \
    "$mysql_image" \
    --tls-version= >/dev/null
  wait_ready "$name" healthcheck.sh --connect --innodb_initialized
  docker_cmd exec "$name" mariadb --version
  echo "==> ${name} is ready"
  # TCP (the image's init server listens on no port), as an account init.sql made.
  wait_ready "$mysql_name" mysql --protocol=TCP -h127.0.0.1 -ucss34_plain -pcss34-plain-probe -e 'SELECT 1'
  docker_cmd exec "$mysql_name" mysqld --version
  echo "==> ${mysql_name} is ready"
  wait_ready "$notls_name" mysql --protocol=TCP -h127.0.0.1 -ucss34_plain -pcss34-plain-probe --ssl-mode=DISABLED \
    --get-server-public-key -e 'SELECT 1'
  if docker_cmd exec "$notls_name" mysql --protocol=TCP -h127.0.0.1 -ucss34_plain -pcss34-plain-probe \
      --ssl-mode=REQUIRED -e 'SELECT 1' >/dev/null 2>&1; then
    die "${notls_name} accepts TLS"
  fi
  echo "==> ${notls_name} is ready (no TLS)"
}

stop() {
  local container
  for container in "$name" "$mysql_name" "$notls_name"; do
    if docker_cmd inspect "$container" >/dev/null 2>&1; then
      echo "==== ${container} log (tail) ===="
      docker_cmd logs "$container" 2>&1 | tail -n 30 || true
      docker_cmd rm -f "$container" >/dev/null 2>&1 || true
    fi
  done
  docker_cmd network rm "$network" >/dev/null 2>&1 || true
}

case "${1:-}" in
  start) start "${2:-}" ;;
  stop) stop ;;
  *) echo "usage: $0 start DIR | stop" >&2; exit 2 ;;
esac
