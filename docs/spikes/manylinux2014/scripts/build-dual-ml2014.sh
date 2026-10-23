#!/usr/bin/env bash
# Runs inside quay.io/pypa/manylinux2014_i686 with /workspace = dual-build repo copy.
# Based on research/oldos/scripts/build-css34-ml2014-sm11.sh (+ css34 dual MM mode).
set -euo pipefail
cp /proxy-ca.crt /etc/pki/ca-trust/source/anchors/ && update-ca-trust
export PIP_CERT=/etc/pki/tls/certs/ca-bundle.crt
# sandbox-only: NSS curl 7.29 ignores the anchor store for this proxy CA
printf '#!/bin/sh\nexec /usr/bin/curl --cacert /proxy-ca.crt "$@"\n' > /usr/local/bin/curl && chmod +x /usr/local/bin/curl
export PATH=/opt/python/cp312-cp312/bin:$PATH
# patch scripts hardcode gcc-9/g++-9 for logic.so
for t in gcc g++; do printf '#!/bin/sh\nexec /opt/rh/devtoolset-10/root/usr/bin/%s -Wno-format-truncation -Wno-stringop-truncation -Wno-sign-compare -Wl,--exclude-libs,ALL "$@"\n' $t > /usr/bin/$t-9; chmod +x /usr/bin/$t-9; done
echo "== $(gcc --version | head -1); $(ldd --version | head -1); $(python3 --version)"
# Static OpenSSL 1.1.1w for dbi.mysql (CentOS 7 only ships 1.0.2 static).
if [ ! -f /opt/ossl/lib/libssl.a ]; then
  mkdir -p /tmp/ossl && tar -xzf /dl/openssl-1.1.1w.tar.gz -C /tmp/ossl
  (cd /tmp/ossl/openssl-1.1.1w && ./Configure linux-elf no-shared no-tests no-dso -fPIC --prefix=/opt/ossl --openssldir=/opt/ossl/ssl >/tmp/ossl.log 2>&1 && make -j"$(nproc)" >>/tmp/ossl.log 2>&1 && make install_sw >>/tmp/ossl.log 2>&1) || { tail -30 /tmp/ossl.log; exit 5; }
fi
export CPATH=/opt/ossl/include LIBRARY_PATH=/opt/ossl/lib
git config --global --add safe.directory '*'
export SKIP_APT_INSTALL=1 USE_CLANG9=0 CC="gcc -Wno-format-truncation -Wno-stringop-truncation" CXX="g++ -Wno-format-truncation -Wno-stringop-truncation -Wno-volatile -Wno-sign-compare -static-libstdc++ -Wl,--exclude-libs=libstdc++.a" PURE_SOURCE_BUILD=1
export WDIR=/workspace DEPS_DIR=/workspace/deps PACKAGES_DIR=/workspace/${PKG_SUBDIR:-packages-dual}
cd /workspace
export CSS34_LINE=sm11-oldstable CSS34_EXCLUDE_LIBS_ALL=1 OLDOS_GNUC_FIX=1
# css34 dual: 2.ep1 + shared modules against Metamod 1.12-dev git1227 (75dd7b26).
export CSS34_DUAL_MM=1 CSS34_DUAL_BUILD_MM112=1
export CSS34_DUAL_MM_COMMIT=75dd7b26fe92e535a11f0318ead73c3e05130d0b CSS34_DUAL_MM_REV=1227
bash builder/run/linux.sh
