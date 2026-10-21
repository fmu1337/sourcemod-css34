#!/usr/bin/env bash
# Thin wrapper. The shipping Linux build is builder/docker/build.sh
# (manylinux2014_i686, glibc 2.17, GCC 10.2.1). Removed in T1.4.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build.sh" "$@"
