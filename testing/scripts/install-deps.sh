#!/usr/bin/env bash
# Install 32-bit runtime deps for CS:S v34 srcds on Debian-family or RHEL-family.
#
# The one package list of every smoke/botplay container. test-images.yml runs it
# at image build time with CSS34_DEPS_MARKER=1, which records this script's
# sha256 in /etc/css34-install-deps.sha256; in such an image a later run of the
# same script is a no-op (no apt/yum traffic). An image built from another
# version of this script installs as usual. CSS34_DEPS_FORCE=1 always installs;
# CSS34_DEPS_MARKER_FILE moves the marker (tests).
set -euo pipefail

DEPS_MARKER="${CSS34_DEPS_MARKER_FILE:-/etc/css34-install-deps.sha256}"

self_hash() {
  command -v sha256sum >/dev/null 2>&1 || return 0
  sha256sum "${BASH_SOURCE[0]}" | cut -d' ' -f1
}

detect_family() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      debian|ubuntu) echo debian ;;
      centos|rhel|rocky|almalinux|fedora) echo rhel ;;
      *)
        case "${ID_LIKE:-}" in
          *debian*) echo debian ;;
          *rhel*|*fedora*|*centos*) echo rhel ;;
          *) echo unknown ;;
        esac
        ;;
    esac
  else
    echo unknown
  fi
}

# Flaky mirrors (snapshot.debian.org in particular) drop single index downloads.
# Retries/Timeout exist in every apt down to Debian 8's apt 1.0.
configure_apt_network() {
  mkdir -p /etc/apt/apt.conf.d
  cat >/etc/apt/apt.conf.d/80css34-network <<'EOF'
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
EOF
}

# apt-get update exits 0 when single indexes fail ("W: Failed to fetch"), which
# later shows up as "unmet dependencies". Retry such runs, up to 3 attempts.
apt_update() {
  local attempt log rc=0
  log="$(mktemp)"
  for attempt in 1 2 3; do
    rc=0
    apt-get update -y "$@" >"${log}" 2>&1 || rc=$?
    cat "${log}"
    if [[ "${rc}" -eq 0 ]] && ! grep -Eq 'Failed to fetch|index files failed to download|Hash Sum mismatch' "${log}"; then
      rm -f "${log}"
      return 0
    fi
    if [[ "${attempt}" -lt 3 ]]; then
      echo "apt-get update incomplete (attempt ${attempt}/3, exit ${rc}); retrying in $((attempt * 10))s" >&2
      sleep $((attempt * 10))
    fi
  done
  rm -f "${log}"
  echo "WARNING: apt-get update still incomplete after 3 attempts (exit ${rc})" >&2
  return "${rc}"
}

fix_ubuntu_archives() {
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || return 0
  local codename="${VERSION_CODENAME:-}"
  case "${VERSION_ID:-}" in
    14.04) codename=trusty ;;
    16.04) codename=xenial ;;
    18.04) codename=bionic ;;
    *) return 0 ;;
  esac
  echo "Configuring apt for Ubuntu ${codename}"
  cat >/etc/apt/apt.conf.d/99oldubuntu <<'EOF'
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
EOF
  write_ubuntu_sources() {
    local host="$1"
    cat >/etc/apt/sources.list <<EOF
deb [trusted=yes] http://${host}/ubuntu ${codename} main universe multiverse
deb [trusted=yes] http://${host}/ubuntu ${codename}-updates main universe multiverse
deb [trusted=yes] http://${host}/ubuntu ${codename}-security main universe multiverse
EOF
  }
  # 14.04/16.04 still answer on archive.ubuntu.com; old-releases is the fallback
  # once a suite is removed. 18.04 is on archive.ubuntu.com.
  rm -f /etc/apt/sources.list.d/* || true
  write_ubuntu_sources archive.ubuntu.com
  if ! apt_update; then
    echo "archive.ubuntu.com failed for ${codename}; trying old-releases.ubuntu.com"
    write_ubuntu_sources old-releases.ubuntu.com
    apt_update || apt_update --allow-unauthenticated
  fi
}

fix_debian_archives() {
  # shellcheck disable=SC1091
  . /etc/os-release
  local codename="${VERSION_CODENAME:-}"
  case "${VERSION_ID:-}" in
    8) codename=jessie ;;
    9) codename=stretch ;;
    10) codename=buster ;;
    11) codename=bullseye ;;
  esac
  case "${codename}" in
    bullseye)
      local snap="${BULLSEYE_APT_SNAPSHOT:-20260813T000000Z}"
      echo "Pinning bullseye apt to snapshot.debian.org/${snap}"
      rm -f /etc/apt/sources.list.d/* || true
      cat >/etc/apt/sources.list <<EOF
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${snap} bullseye main contrib non-free
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${snap} bullseye-updates main contrib non-free
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/${snap} bullseye-security main contrib non-free
EOF
      cat >/etc/apt/apt.conf.d/99snapshot <<EOF
Acquire::Check-Valid-Until "false";
EOF
      ;;
    jessie|stretch|buster)
      echo "Configuring archive.debian.org for ${codename}"
      rm -f /etc/apt/sources.list.d/* || true
      if [[ "${codename}" == "buster" ]]; then
        cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian ${codename} main contrib non-free
deb http://archive.debian.org/debian-security ${codename}/updates main contrib non-free
deb http://archive.debian.org/debian ${codename}-updates main contrib non-free
EOF
      else
        cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian ${codename} main contrib non-free
deb http://archive.debian.org/debian-security ${codename}/updates main contrib non-free
EOF
      fi
      cat >/etc/apt/apt.conf.d/99archive <<'EOF'
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
EOF
      ;;
  esac
}

apt_install() {
  # bash < 4.4 treats an empty "${arr[@]}" as unbound under set -u.
  local extra_opts=()
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${VERSION_ID:-}" in
    8|9)
      extra_opts+=(--force-yes)
      ;;
  esac
  apt-get install -y --no-install-recommends --allow-unauthenticated ${extra_opts[@]+"${extra_opts[@]}"} "$@" \
    || apt-get install -y --no-install-recommends --allow-unauthenticated --force-yes "$@" \
    || apt-get install -y --no-install-recommends "$@"
}

install_debian() {
  export DEBIAN_FRONTEND=noninteractive
  configure_apt_network
  fix_ubuntu_archives
  fix_debian_archives
  dpkg --add-architecture i386 || true
  rm -rf /var/lib/apt/lists/* 2>/dev/null || true
  apt_update || apt_update --allow-unauthenticated

  local pkgs=(
    ca-certificates curl wget unzip bzip2 file procps expect git python3 binutils
    libstdc++6 libstdc++6:i386 zlib1g:i386
  )
  if apt-cache show libc6-i386 >/dev/null 2>&1; then
    pkgs+=(libc6-i386)
  fi
  if apt-cache show lib32gcc-s1 >/dev/null 2>&1; then
    pkgs+=(lib32gcc-s1 lib32z1 lib32stdc++6)
  elif apt-cache show lib32gcc1 >/dev/null 2>&1; then
    pkgs+=(lib32gcc1 lib32z1 lib32stdc++6)
  fi
  # Optional tools — don't fail the job if unavailable
  for opt in gdb screen; do
    if apt-cache show "${opt}" >/dev/null 2>&1; then
      pkgs+=("${opt}")
    fi
  done
  apt_install "${pkgs[@]}"
}

fix_centos_vault() {
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" == "centos" && "${VERSION_ID:-}" == "7" ]]; then
    echo "Pointing CentOS 7 repos at vault.centos.org"
    sed -i 's/mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/*.repo || true
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=https://vault.centos.org|g' /etc/yum.repos.d/*.repo || true
  fi
}

configure_rhel_network() {
  local conf
  for conf in /etc/yum.conf /etc/dnf/dnf.conf; do
    [[ -f "${conf}" ]] || continue
    grep -q '^retries=' "${conf}" || sed -i '0,/^\[main\]/s//[main]\nretries=5/' "${conf}"
    grep -q '^timeout=' "${conf}" || sed -i '0,/^\[main\]/s//[main]\ntimeout=30/' "${conf}"
  done
}

install_rhel() {
  fix_centos_vault
  configure_rhel_network
  local pkgs=(glibc.i686 libstdc++.i686 zlib.i686 ca-certificates unzip bzip2 file procps-ng expect git python3 binutils)
  if command -v dnf >/dev/null 2>&1; then
    # Align x86_64 runtime with the i686 packages we are about to install.
    dnf -y update libstdc++ libgcc glibc zlib ca-certificates || true
    dnf -y install "${pkgs[@]}" wget \
      || dnf -y install --allowerasing "${pkgs[@]}" wget \
      || dnf -y install --allowerasing "${pkgs[@]}"
    # RHEL 8+: libnsl moved out of glibc; old srcds/steamclient may need it.
    dnf -y install libnsl.i686 libnsl || true
    dnf -y install gdb || true
  else
    # CentOS 7: update matching x86_64 libs first to avoid multilib skew.
    yum -y update zlib glibc libstdc++ libgcc nss-softokn-freebl nspr nss-util || true
    yum -y install "${pkgs[@]}" wget \
      --setopt=protected_multilib=false \
      || yum -y install glibc.i686 libstdc++.i686 zlib.i686 ca-certificates unzip \
        --setopt=protected_multilib=false
    yum -y install gdb screen || true
  fi
}

main() {
  local family hash
  hash="$(self_hash)"
  if [[ "${CSS34_DEPS_FORCE:-0}" != 1 && -n "${hash}" && -f "${DEPS_MARKER}" ]]; then
    if [[ "$(cat "${DEPS_MARKER}")" == "${hash}" ]]; then
      echo "Dependencies prebuilt in this image (install-deps.sh ${hash:0:12}); nothing to install."
      return 0
    fi
    echo "Image was prebuilt by another install-deps.sh ($(cut -c1-12 "${DEPS_MARKER}")); installing ${hash:0:12}"
  fi
  family="$(detect_family)"
  echo "Detected package family: ${family}"
  case "${family}" in
    debian) install_debian ;;
    rhel) install_rhel ;;
    *)
      echo "Unsupported distro for install-deps.sh" >&2
      exit 1
      ;;
  esac
  if [[ "${CSS34_DEPS_MARKER:-0}" == 1 ]]; then
    [[ -n "${hash}" ]] || { echo "CSS34_DEPS_MARKER=1 needs sha256sum" >&2; exit 1; }
    printf '%s\n' "${hash}" >"${DEPS_MARKER}"
    echo "Recorded ${DEPS_MARKER} (${hash:0:12})"
  fi
  echo "Dependencies installed."
}

main "$@"
