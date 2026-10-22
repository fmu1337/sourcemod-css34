#!/usr/bin/env bash
# One-off PR #127 evidence; removed after recording the CI result.
set -euo pipefail
git init /tmp/css34-master
git -C /tmp/css34-master remote add origin https://github.com/fmu1337/sourcemod-css34.git
git -C /tmp/css34-master fetch --depth=1 origin 59eb2476b8646b76852796660d865c49c38bfefc
git -C /tmp/css34-master checkout --detach FETCH_HEAD
(cd /tmp/css34-master && bash builder/docker/build.sh)
PACKAGES_DIR=/tmp/css34-master/packages source /tmp/css34-master/builder/package-paths.sh
export SM_PACKAGE
if bash testing/scripts/check-package.sh > /tmp/master-abi.log 2>&1; then
  cat /tmp/master-abi.log
  echo 'FAIL: master sm13 unexpectedly passed the new ABI check'
  exit 1
fi
cat /tmp/master-abi.log
grep -E 'FAIL: .*dbi.pgsql.ext.so: unversioned undefined symbol explicit_bzero' /tmp/master-abi.log
echo 'OK: master 59eb247 sm13 rejected for explicit_bzero'
