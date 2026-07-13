#!/usr/bin/env bash
# Install 32-bit runtime deps for CS:S v34 srcds on Debian-family or RHEL-family.
set -euo pipefail

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

fix_debian_archives() {
  # shellcheck disable=SC1091
  . /etc/os-release
  local codename="${VERSION_CODENAME:-}"
  case "${VERSION_ID:-}" in
    8) codename=jessie ;;
    9) codename=stretch ;;
    10) codename=buster ;;
  esac
  case "${codename}" in
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
  local extra_opts=()
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${VERSION_ID:-}" in
    8|9)
      extra_opts+=(--force-yes)
      ;;
  esac
  apt-get install -y --allow-unauthenticated "${extra_opts[@]}" "$@" \
    || apt-get install -y --allow-unauthenticated --force-yes "$@" \
    || apt-get install -y "$@"
}

install_debian() {
  export DEBIAN_FRONTEND=noninteractive
  fix_debian_archives
  dpkg --add-architecture i386 || true
  apt-get update -y || apt-get update -y --allow-unauthenticated || true

  local pkgs=(
    ca-certificates curl wget unzip bzip2 file procps expect
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
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/*.repo || true
  fi
}

install_rhel() {
  fix_centos_vault
  local pkgs=(glibc.i686 libstdc++.i686 zlib.i686 ca-certificates unzip bzip2 file procps-ng expect)
  if command -v dnf >/dev/null 2>&1; then
    # Align x86_64 runtime with the i686 packages we are about to install.
    dnf -y update libstdc++ libgcc glibc zlib ca-certificates || true
    dnf -y install "${pkgs[@]}" wget \
      || dnf -y install --allowerasing "${pkgs[@]}" wget \
      || dnf -y install --allowerasing "${pkgs[@]}"
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
