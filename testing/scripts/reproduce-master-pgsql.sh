#!/usr/bin/env bash
# One-off PR #127 evidence; removed after recording the CI result.
set -euo pipefail
git fetch origin 59eb2476b8646b76852796660d865c49c38bfefc
git worktree add --detach /tmp/css34-master 59eb2476b8646b76852796660d865c49c38bfefc
(cd /tmp/css34-master && bash builder/docker/build.sh)
source /tmp/css34-master/builder/package-paths.sh
export SM_PACKAGE
if bash testing/scripts/check-package.sh > /tmp/master-abi.log 2>&1; then
  cat /tmp/master-abi.log
  echo 'FAIL: master sm13 unexpectedly passed the new ABI check'
  exit 1
fi
cat /tmp/master-abi.log
grep -E 'FAIL: .*dbi.pgsql.ext.so: unversioned undefined symbol explicit_bzero' /tmp/master-abi.log
echo 'OK: master 59eb247 sm13 rejected for explicit_bzero'
