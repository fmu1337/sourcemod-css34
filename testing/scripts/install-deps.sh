#!/usr/bin/env bash
# Install 32-bit runtime deps for CS:S v34 srcds on Debian-family or RHEL-family.
set -euo pipefail

detect_family() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID_LIKE:-}${ID:-}" in
      *debian*|*ubuntu*) echo debian ;;
      *rhel*|*centos*|*fedora*|*rocky*|*almalinux*) echo rhel ;;
      *)
        if [[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" ]]; then
          echo debian
        elif [[ "${ID:-}" == "centos" || "${ID:-}" == "rhel" || "${ID:-}" == "rocky" || "${ID:-}" == "almalinux" ]]; then
          echo rhel
        else
          echo unknown
        fi
        ;;
    esac
  else
    echo unknown
  fi
}

fix_debian_archives() {
  # shellcheck disable=SC1091
  . /etc/os-release
  local codename="${VERSION_CODENAME:-}"
  case "${VERSION_ID:-}" in
    8) codename=jessie ;;
    9) codename=stretch ;;
  esac
  case "${codename}" in
    jessie|stretch)
      echo "Configuring archive.debian.org for ${codename}"
      rm -f /etc/apt/sources.list.d/* || true
      cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian ${codename} main contrib non-free
deb http://archive.debian.org/debian-security ${codename}/updates main contrib non-free
EOF
      printf 'Acquire::Check-Valid-Until "false";\nAcquire::AllowInsecureRepositories "true";\n' \
        >/etc/apt/apt.conf.d/99archive
      ;;
  esac
}

fix_centos_vault() {
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" == "centos" && "${VERSION_ID:-}" == "7" ]]; then
    echo "Pointing CentOS 7 repos at vault.centos.org"
    sed -i 's/mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/*.repo || true
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/*.repo || true
  fi
}

install_debian() {
  export DEBIAN_FRONTEND=noninteractive
  fix_debian_archives
  dpkg --add-architecture i386 || true
  apt-get update -y
  # Package names differ across Debian generations.
  local pkgs=(
    ca-certificates curl wget unzip bzip2 file gdb screen procps
    libstdc++6 libstdc++6:i386 zlib1g:i386
  )
  # 32-bit glibc / gcc runtime
  if apt-cache show libc6-i386 >/dev/null 2>&1; then
    pkgs+=(libc6-i386)
  fi
  if apt-cache show lib32gcc-s1 >/dev/null 2>&1; then
    pkgs+=(lib32gcc-s1 lib32z1 lib32stdc++6)
  elif apt-cache show lib32gcc1 >/dev/null 2>&1; then
    pkgs+=(lib32gcc1 lib32z1 lib32stdc++6)
  fi
  apt-get install -y --no-install-recommends "${pkgs[@]}" || \
    apt-get install -y "${pkgs[@]}"
}

install_rhel() {
  fix_centos_vault
  if command -v dnf >/dev/null 2>&1; then
    dnf -y install glibc.i686 libstdc++.i686 zlib.i686 \
      ca-certificates curl wget unzip bzip2 file gdb screen procps-ng \
      || dnf -y install glibc.i686 libstdc++.i686 zlib.i686 ca-certificates curl unzip
  else
    yum -y install glibc.i686 libstdc++.i686 zlib.i686 \
      ca-certificates curl wget unzip bzip2 file gdb screen procps-ng \
      || yum -y install glibc.i686 libstdc++.i686 zlib.i686 ca-certificates curl unzip
  fi
}

main() {
  local family
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
  echo "Dependencies installed."
}

main "$@"
