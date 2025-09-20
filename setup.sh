#!/usr/bin/env bash
# setup.sh — Siapkan VPS untuk Panel Minecraft (Debian 11/12, Ubuntu 22.04/24.04)
# Menyiapkan paket, Java 21, vnStat, cron, struktur folder, dan izin eksekusi.

set -euo pipefail

# --------- CONFIG ---------
PANEL_DIR="${PANEL_DIR:-/root/mc-panel}"
REQUIRED_DIRS=(servers functions eggs)
PKGS_BASE=(bash coreutils findutils procps iproute2 net-tools tmux curl wget jq unzip zip tar git cron mc vnstat)
PKG_JAVA="openjdk-21-jre-headless"
PKG_GOTOP="gotop"     # opsional; kalau gagal, di-skip

# --------- UTIL ---------
log() { echo -e "\033[1;36m[SETUP]\033[0m $*"; }
ok()  { echo -e "\033[1;32m[ OK ]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERR ]\033[0m $*"; }
need() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "Jalankan sebagai root. Gunakan: sudo -i  atau  sudo bash setup.sh"
    exit 1
  fi
}

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_VER="${VERSION_ID:-}"
  else
    err "Tidak dapat mendeteksi OS (tidak ada /etc/os-release)."
    exit 1
  fi

  case "${OS_ID}-${OS_VER}" in
    debian-11*) OS_FAMILY="debian"; OS_CODENAME="bullseye" ;;
    debian-12*) OS_FAMILY="debian"; OS_CODENAME="bookworm" ;;
    ubuntu-22.04) OS_FAMILY="ubuntu"; OS_CODENAME="jammy" ;;
    ubuntu-24.04) OS_FAMILY="ubuntu"; OS_CODENAME="noble" ;;
    *)
      warn "OS terdeteksi: ${OS_ID}-${OS_VER}. Skrip ditargetkan untuk Debian 11/12 & Ubuntu 22.04/24.04."
      OS_FAMILY="${OS_ID}"
      OS_CODENAME="${VERSION_CODENAME:-unknown}"
      ;;
  esac

  log "OS: ${OS_ID} ${OS_VER} (codename: ${OS_CODENAME})"
}

apt_update_once() {
  if [[ ! -f /var/lib/apt/periodic/update-success-stamp ]] || \
     find /var/lib/apt/periodic/update-success-stamp -mmin +30 >/dev/null 2>&1; then
    log "apt update..."
    apt-get update -y
  else
    log "apt update (skip: cache masih baru)"
  fi
}

add_backports_if_needed() {
  # Untuk Debian, siapkan backports jika Java 21 tidak tersedia di repo utama.
  if [[ "$OS_FAMILY" == "debian" ]]; then
    local backports_line="deb http://deb.debian.org/debian ${OS_CODENAME}-backports main"
    if ! grep -Rqs "^${backports_line}$" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
      log "Menambahkan ${OS_CODENAME}-backports..."
      echo "${backports_line}" >/etc/apt/sources.list.d/${OS_CODENAME}-backports.list
      apt-get update -y
    fi
  fi
}

install_pkgs_base() {
  log "Menginstal paket dasar..."
  apt_update_once
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS_BASE[@]}" || {
    err "Gagal menginstal paket dasar."
    exit 1
  }
  ok "Paket dasar terinstal."
}

install_java21() {
  log "Memeriksa Java 21..."
  if need java; then
    local v
    v="$(java -version 2>&1 | sed -n '1s/.*"\(.*\)".*/\1/p')"
    if [[ "$v" =~ ^21\. ]]; then
      ok "Java sudah versi 21 ($v)."
      return 0
    else
      warn "Java terpasang tapi bukan 21 (versi: $v). Akan dipasang $PKG_JAVA."
    fi
  fi

  log "Mencoba memasang $PKG_JAVA dari repo default..."
  if apt-get install -y --no-install-recommends "$PKG_JAVA"; then
    ok "Berhasil memasang $PKG_JAVA."
    return 0
  fi

  if [[ "$OS_FAMILY" == "debian" ]]; then
    # Coba dari backports
    add_backports_if_needed
    log "Mencoba memasang Java 21 dari backports..."
    if apt-get install -y -t "${OS_CODENAME}-backports" --no-install-recommends "$PKG_JAVA"; then
      ok "Berhasil memasang Java 21 dari backports."
      return 0
    fi
  fi

  if [[ "$OS_FAMILY" == "ubuntu" ]]; then
    # Pastikan tools repository ada
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends software-properties-common || true
    log "Mencoba memperbarui indeks & memasang $PKG_JAVA (Ubuntu)..."
    apt-get update -y
    if apt-get install -y --no-install-recommends "$PKG_JAVA"; then
      ok "Berhasil memasang $PKG_JAVA."
      return 0
    fi
  fi

  err "Gagal memasang Java 21. Silakan pasang manual (mis. Temurin/Adoptium) lalu jalankan ulang setup."
  exit 1
}

install_gotop_optional() {
  log "Memasang gotop (opsional, untuk menu monitor)..."
  if apt-get install -y --no-install-recommends "$PKG_GOTOP"; then
    ok "gotop terpasang."
  else
    warn "gotop tidak tersedia di repositori ini. Menu monitor tetap bisa jalan, tapi gotop tidak ada."
  fi
}

enable_services() {
  log "Mengaktifkan layanan penting (vnstat, cron)..."
  systemctl enable --now vnstat || warn "Gagal enable/start vnstat (cek paket & interface)."
  systemctl enable --now cron   || warn "Gagal enable/start cron."
  ok "Layanan vnstat & cron diaktifkan (jika tersedia)."
}

prepare_panel_dir() {
  log "Menyiapkan struktur direktori panel: $PANEL_DIR"
  mkdir -p "$PANEL_DIR"
  for d in "${REQUIRED_DIRS[@]}"; do
    mkdir -p "$PANEL_DIR/$d"
  done

  # Jadikan semua .sh di root & functions executable (jika ada)
  shopt -s nullglob
  if compgen -G "$PANEL_DIR/*.sh" >/dev/null; then
    chmod +x "$PANEL_DIR"/*.sh || true
  fi
  if compgen -G "$PANEL_DIR/functions/*.sh" >/dev/null; then
    chmod +x "$PANEL_DIR"/functions/*.sh || true
  fi
  shopt -u nullglob

  ok "Direktori panel disiapkan."
}

print_summary() {
  echo
  echo -e "\033[1;34m══════════════════════════════════════════════════════════════\033[0m"
  echo -e "\033[1;34m  SETUP SELESAI \033[0m"
  echo -e "\033[1;34m══════════════════════════════════════════════════════════════\033[0m"
  echo -e "• Panel Dir       : $PANEL_DIR"
  echo -e "• Java            : $(java -version 2>&1 | sed -n '1p')"
  echo -e "• tmux            : $(tmux -V || echo 'tmux tidak ada')"
  echo -e "• vnstat          : $(vnstat --version 2>/dev/null | head -n1 || echo 'vnstat tidak ada')"
  echo -e "• gotop (opsional): $(gotop -v 2>/dev/null || echo 'tidak terpasang')"
  echo
  echo -e "Jalankan panel:"
  echo -e "  \033[1;33mcd $PANEL_DIR && ./main.sh\033[0m"
  echo
}

# --------- MAIN ---------
require_root
detect_os
install_pkgs_base
install_java21
install_gotop_optional || true
enable_services
prepare_panel_dir
print_summary