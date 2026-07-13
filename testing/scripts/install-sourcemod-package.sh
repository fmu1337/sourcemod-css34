#!/usr/bin/env bash
# Install SourceMod only (tar.gz or myarena zip tree) into SERVER_DIR/cstrike.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
SM_PACKAGE="${SM_PACKAGE:?SM_PACKAGE path required}"

mkdir -p "${SERVER_DIR}/cstrike"

case "${SM_PACKAGE}" in
  *.tar.gz|*.tgz)
    tar -xzf "${SM_PACKAGE}" -C "${SERVER_DIR}/cstrike"
    ;;
  *.zip)
    unzip -q -o "${SM_PACKAGE}" -d "${tmpdir:=$(mktemp -d)}"
    if [[ -d "${tmpdir}/addons/sourcemod" ]]; then
      cp -a "${tmpdir}/addons/sourcemod" "${SERVER_DIR}/cstrike/addons/"
    else
      cp -a "${tmpdir}/"* "${SERVER_DIR}/cstrike/" 2>/dev/null || cp -a "${tmpdir}/addons" "${SERVER_DIR}/cstrike/"
    fi
    rm -rf "${tmpdir}"
    ;;
  *)
    if [[ -d "${SM_PACKAGE}/addons/sourcemod" ]]; then
      cp -a "${SM_PACKAGE}/addons/sourcemod" "${SERVER_DIR}/cstrike/addons/"
    else
      echo "Unsupported SM_PACKAGE: ${SM_PACKAGE}" >&2
      exit 1
    fi
    ;;
esac

mkdir -p "${SERVER_DIR}/cstrike/addons/metamod"
cat >"${SERVER_DIR}/cstrike/addons/metamod/sourcemod.vdf" <<'EOF'
"Metamod Plugin"
{
	"alias"		"sourcemod"
	"file"		"addons/sourcemod/bin/sourcemod_mm"
}
EOF

if [[ -f "${SERVER_DIR}/cstrike/addons/sourcemod/configs/core.cfg" ]]; then
  sed -i 's/"AutoUpdate"[[:space:]]*"yes"/"AutoUpdate"\t\t"no"/' \
    "${SERVER_DIR}/cstrike/addons/sourcemod/configs/core.cfg" || true
fi

chmod +x "${SERVER_DIR}/cstrike/addons/sourcemod/bin/"*.so 2>/dev/null || true
find "${SERVER_DIR}/cstrike/addons/sourcemod/extensions" -name '*.so' -exec chmod +x {} + 2>/dev/null || true

echo "SourceMod installed from ${SM_PACKAGE}"
ls -la "${SERVER_DIR}/cstrike/addons/sourcemod/bin/" 2>/dev/null || true
