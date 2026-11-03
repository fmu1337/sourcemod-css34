#!/usr/bin/env bash
# MariaDB server for testing/scripts/mysql-tls-test.sh (T4.5), on the CI host.
#
#   mysql-tls-server.sh start DIR   write a throwaway CA, a server certificate for
#                                   css34-mariadb and an unrelated CA to DIR
#                                   ({ca,server,server-key,wrong-ca}.pem), then run
#                                   container css34-mariadb on network css34-db
#   mysql-tls-server.sh stop        remove both (logs are printed first)
#
# Accounts: css34_tls (REQUIRE SSL) and css34_plain, both mysql_native_password.
# The image is "mariadb:11.8" from builder/lines.json (pinned by digest).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
name=css34-mariadb
network=css34-db
image_name="mariadb:11.8"

docker_cmd() { if docker info >/dev/null 2>&1; then docker "$@"; else sudo docker "$@"; fi; }
die() { echo "FAIL: $*" >&2; exit 1; }

image_ref() {
  python3 - "$root/builder/lines.json" "$image_name" <<'PY'
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
    printf '%s\n' "subjectAltName=DNS:${name}" "basicConstraints=critical,CA:FALSE" \
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

start() {
  local dir="${1:?certificate directory required}"
  local image init
  image="$(image_ref)"
  make_certs "$dir"
  dir="$(cd "$dir" && pwd)"
  init="$dir/init.sql"
  cat >"$init" <<'SQL'
CREATE USER 'css34_tls'@'%' IDENTIFIED VIA mysql_native_password USING PASSWORD('css34-tls-probe') REQUIRE SSL;
CREATE USER 'css34_plain'@'%' IDENTIFIED VIA mysql_native_password USING PASSWORD('css34-plain-probe');
SQL
  chmod 0644 "$init"
  docker_cmd rm -f "$name" >/dev/null 2>&1 || true
  docker_cmd network inspect "$network" >/dev/null 2>&1 || docker_cmd network create "$network" >/dev/null
  echo "==> Starting ${name} (${image}) with TLS on network ${network}"
  docker_cmd run -d --name "$name" --network "$network" \
    -e MARIADB_RANDOM_ROOT_PASSWORD=1 \
    -v "$dir:/certs:ro" \
    -v "$init:/docker-entrypoint-initdb.d/css34.sql:ro" \
    "$image" \
    --ssl-ca=/certs/ca.pem --ssl-cert=/certs/server.pem --ssl-key=/certs/server-key.pem >/dev/null
  local deadline=$((SECONDS + 180))
  until docker_cmd exec "$name" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; do
    if [[ "$(docker_cmd inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" != true ]]; then
      docker_cmd logs "$name" 2>&1 | tail -n 40
      die "${name} exited during startup"
    fi
    (( SECONDS < deadline )) || { docker_cmd logs "$name" 2>&1 | tail -n 40; die "${name} did not become ready"; }
    sleep 2
  done
  docker_cmd exec "$name" mariadb --version
  echo "==> ${name} is ready"
}

stop() {
  if docker_cmd inspect "$name" >/dev/null 2>&1; then
    echo "==== ${name} log (tail) ===="
    docker_cmd logs "$name" 2>&1 | tail -n 30 || true
    docker_cmd rm -f "$name" >/dev/null 2>&1 || true
  fi
  docker_cmd network rm "$network" >/dev/null 2>&1 || true
}

case "${1:-}" in
  start) start "${2:-}" ;;
  stop) stop ;;
  *) echo "usage: $0 start DIR | stop" >&2; exit 2 ;;
esac
