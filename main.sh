#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
#   PANEL SERVER MINECRAFT (BASH) - Versi Final
# ==============================================================================

# --- Konfigurasi Path Utama ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVERS_DIR="${SERVERS_DIR:-$BASE_DIR/servers}"
FUNCTIONS_DIR="${FUNCTIONS_DIR:-$BASE_DIR/functions}"
EGGS_DIR="${EGGS_DIR:-$BASE_DIR/eggs}"

# --- Definisi Warna ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m';
MAG='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m' # No Color

# --- Memuat Semua Fungsi dari Direktori 'functions' ---
if [[ -d "$FUNCTIONS_DIR" ]]; then
  shopt -s nullglob
  for f in "$FUNCTIONS_DIR"/*.sh; do
    # shellcheck source=/dev/null
    source "$f"
  done
  shopt -u nullglob
else
  echo -e "${YELLOW}Peringatan: Direktori fungsi ('$FUNCTIONS_DIR') tidak ditemukan.${NC}"
  echo "Beberapa fitur mungkin tidak akan berfungsi."
  sleep 3
fi

# ==============================================================================
#   Fungsi Utilitas & Dasbor
# ==============================================================================

# Cek apakah sebuah perintah/command ada di sistem.
need_cmd(){
  command -v "$1" >/dev/null 2>&1
}

# Mendapatkan interface jaringan default untuk statistik traffic.
get_default_iface(){
  local dev
  dev="$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if ($i=="dev"){print $(i+1); exit}}' || true)"
  [[ -n "$dev" ]] && { echo "$dev"; return; }
  if need_cmd vnstat; then
    dev="$(vnstat --iflist 2>/dev/null | sed -n 's/^Available interfaces: //p' | tr ',' ' ' | awk '{print $1; exit}' || true)"
    [[ -n "$dev" ]] && { echo "$dev"; return; }
  fi
  echo "eth0"
}

# Menampilkan informasi dasbor utama.
print_header(){
  local RAM CPU DSK CNT BOT
  RAM=$(free -m | awk '/^Mem:/ {printf "%s/%s MiB (%s%%)", $3, $2, int($3/$2*100)}')
  CPU=$(awk '{printf "%.2f %.2f %.2f", $1, $2, $3}' /proc/loadavg)
  DSK=$(df -hP / | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}')
  CNT=$(find "$SERVERS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

  if need_cmd tmux && tmux has-session -t "BotListener" 2>/dev/null; then
      BOT="${GREEN}AKTIF${NC}"
  else
      BOT="${RED}NON-AKTIF${NC}"
  fi

  echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║${NC}              ${GREEN}PANEL SERVER MINECRAFT${NC} ${MAG}BY ZERO END${NC}              ${BLUE}║${NC}"
  echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
  printf "${BLUE}║${NC} ${CYAN}%-10s${NC} : ${MAG}%-45s${NC}   ${BLUE}║${NC}\n" "RAM" "$RAM"  
  printf "${BLUE}║${NC} ${CYAN}%-10s${NC} : ${MAG}%-45s${NC}   ${BLUE}║${NC}\n" "CPU Load" "$CPU"  
  printf "${BLUE}║${NC} ${CYAN}%-10s${NC} : ${MAG}%-45s${NC}   ${BLUE}║${NC}\n" "Disk (/)" "$DSK"  
  printf "${BLUE}║${NC} ${CYAN}%-10s${NC} : ${MAG}%-18s${NC}    ${CYAN}%-13s${NC} : %-9b ${BLUE}║${NC}\n" "Server" "$CNT Terpasang" "Bot Listener" "$BOT"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# ==============================================================================
#   Fungsi Wrapper untuk Memanggil Fitur dari File Eksternal
# ==============================================================================

do_create_server(){ if declare -F createServer >/dev/null; then createServer; else echo -e "${RED}ERROR: Fungsi 'createServer' tidak ditemukan.${NC}"; read -rp "Tekan [Enter]..."; fi; }
do_delete_server(){ if declare -F deleteServer >/dev/null; then deleteServer; else echo -e "${RED}ERROR: Fungsi 'deleteServer' tidak ditemukan.${NC}"; read -rp "Tekan [Enter]..."; fi; }
do_swap_menu(){ if declare -F swapMenu >/dev/null; then swapMenu; else echo -e "${RED}ERROR: Fungsi 'swapMenu' tidak ditemukan.${NC}"; read -rp "Tekan [Enter]..."; fi; }
do_bot_menu(){ if declare -F botMenu >/dev/null; then botMenu; else echo -e "${RED}ERROR: Fungsi 'botMenu' tidak ditemukan.${NC}"; read -rp "Tekan [Enter]..."; fi; }
do_backup_menu(){ if declare -F backupMenu >/dev/null; then backupMenu; else echo -e "${RED}ERROR: Fungsi 'backupMenu' tidak ditemukan.${NC}"; read -rp "Tekan [Enter]..."; fi; }
do_ports_menu(){ if declare -F portsMenu >/dev/null; then portsMenu; else echo -e "${RED}ERROR: Fungsi 'portsMenu' tidak ditemukan.${NC}"; read -rp "Tekan [Enter]..."; fi; }
do_monitor(){
  if ! need_cmd btop; then
    read -p "Perintah 'btop' tidak ditemukan. Coba install sekarang? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
      echo "Menginstal btop..."
      sudo apt-get update && sudo apt-get install -y btop
    else
      return
    fi
  fi
  clear; btop
}

# ==============================================================================
#   Menu Utama
# ==============================================================================

mainMenu(){
  while true; do
    clear
    print_header
    echo -e "${BLUE}--- MANAJEMEN SERVER ---${NC}"
    echo -e " ${YELLOW}1${NC}) Buat Server Baru"
    echo -e " ${YELLOW}2${NC}) Kelola Server"
    echo -e " ${YELLOW}3${NC}) Hapus Server"
    echo -e "\n${BLUE}--- UTILITAS VPS ---${NC}"
    echo -e " ${YELLOW}4${NC}) Manajemen RAM Swap"
    echo -e " ${YELLOW}5${NC}) Monitor Sumber Daya"
    echo -e " ${YELLOW}6${NC}) Cek Port & Layanan"
    echo -e "\n${BLUE}--- FITUR TAMBAHAN ---${NC}"
    echo -e " ${YELLOW}7${NC}) Menu Bot Telegram"
    echo -e " ${YELLOW}8${NC}) Backup & Migrasi"
    echo -e "\n${RED}9) Keluar${NC}"
    echo -e "${BLUE}--------------------------------------------------------------${NC}"
    read -rp "Pilih Opsi: " ch
    case "$ch" in
      1) do_create_server ;;
      2) "$FUNCTIONS_DIR/server_manage.sh" ;;
      3) do_delete_server ;;
      4) do_swap_menu ;;
      5) do_monitor ;;
      6) do_ports_menu ;;
      7) do_bot_menu ;;
      8) do_backup_menu ;;
      9) echo -e "${GREEN}Sampai jumpa!${NC}"; exit 0 ;;
      *) echo -e "${YELLOW}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
  done
}

# Memulai eksekusi menu utama.
mainMenu
