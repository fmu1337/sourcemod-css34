#!/usr/bin/env bash
# css34: always emit Mapchange log on first map (Logger::_UpdateFiles else-branch gap).
set -euo pipefail

sourcemod_dir="${1:?sourcemod directory required}"
logger="${sourcemod_dir}/core/logic/Logger.cpp"
marker="CSS34 LOGGER_MAPCHANGE_FIX"

if [[ ! -f "$logger" ]]; then
  echo "skip: $logger missing" >&2
  exit 0
fi

if grep -q "$marker" "$logger"; then
  echo "==> Logger mapchange fix already applied"
  exit 0
fi

PY=(bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../py.sh")
SOURCEMOD_DIR="$sourcemod_dir" MARKER="$marker" "${PY[@]}" - <<'PY'
from pathlib import Path
import os

path = Path(os.environ['SOURCEMOD_DIR']) / 'core' / 'logic' / 'Logger.cpp'
text = path.read_text()
marker = os.environ['MARKER']

old = """\tif (m_NormalFileName.compare(buff))
\t{
\t\t_CloseNormal();
\t\tm_NormalFileName = buff;
\t}
\telse
\t{
\t\tif (bLevelChange)
\t\t{
\t\t\tLogMessage("-------- Mapchange to %s --------", m_CurrentMapName.c_str());
\t\t}
\t}"""

new = f"""\t/* {marker}: log first mapchange even when daily log path is new */
\tif (m_NormalFileName.compare(buff))
\t{{
\t\t_CloseNormal();
\t\tm_NormalFileName = buff;
\t}}
\tif (bLevelChange)
\t{{
\t\tLogMessage("-------- Mapchange to %s --------", m_CurrentMapName.c_str());
\t}}"""

if old not in text:
    # Boot-trace variant may already wrap the block.
    boot_old = """\tif (m_NormalFileName.compare(buff))
\t{
\t\tsm_boot_tracef("CSS34 SM_BOOT_TRACE Logger::_UpdateFiles: new file %s (no mapchange log yet)", buff);
\t\t_CloseNormal();
\t\tm_NormalFileName = buff;
\t}
\telse
\t{
\t\tif (bLevelChange)
\t\t{
\t\t\tsm_boot_trace("CSS34 SM_BOOT_TRACE Logger::_UpdateFiles: mapchange LogMessage");
\t\t\tLogMessage("-------- Mapchange to %s --------", m_CurrentMapName.c_str());
\t\t}
\t}"""
    if boot_old in text:
        boot_new = f"""\t/* {marker} */
\tif (m_NormalFileName.compare(buff))
\t{{
\t\tsm_boot_tracef("CSS34 SM_BOOT_TRACE Logger::_UpdateFiles: new file %s", buff);
\t\t_CloseNormal();
\t\tm_NormalFileName = buff;
\t}}
\tif (bLevelChange)
\t{{
\t\tsm_boot_trace("CSS34 SM_BOOT_TRACE Logger::_UpdateFiles: mapchange LogMessage");
\t\tLogMessage("-------- Mapchange to %s --------", m_CurrentMapName.c_str());
\t}}"""
        path.write_text(text.replace(boot_old, boot_new, 1))
        print('==> Patched Logger mapchange fix (boot-trace variant)')
    else:
        raise SystemExit('Logger::_UpdateFiles mapchange anchor not found')
else:
    path.write_text(text.replace(old, new, 1))
    print('==> Patched Logger mapchange fix')
PY
