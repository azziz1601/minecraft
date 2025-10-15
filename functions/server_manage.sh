#!/usr/bin/env bash

SERVERS_DIR="${SERVERS_DIR:-/root/mc-panel/servers}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SELF_DIR/.." && pwd)"
FUNCTIONS_DIR="${FUNCTIONS_DIR:-$BASE_DIR/functions}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
EDITOR_BIN="${EDITOR:-nano}"

need_cmd(){ command -v "$1" >/dev/null 2>&1; }

ensure_dos2unix(){
  if ! need_cmd dos2unix; then
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y dos2unix >/dev/null 2>&1 || true
  fi
}

normalize_scripts(){
  ensure_dos2unix
  find "$FUNCTIONS_DIR" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) -print0 2>/dev/null | xargs -0 -r dos2unix >/dev/null 2>&1 || true
  find "$BASE_DIR" -maxdepth 1 -type f -name '*.sh' -print0 2>/dev/null | xargs -0 -r dos2unix >/dev/null 2>&1 || true
  chmod +x "$FUNCTIONS_DIR"/*.sh 2>/dev/null || true
  chmod +x "$BASE_DIR"/*.sh 2>/dev/null || true
}

getServerStatus(){
  local server_name="$1"
  if tmux has-session -t "$server_name" 2>/dev/null; then
    echo -e "${GREEN}Berjalan${NC}"
  else
    echo -e "${RED}Berhenti${NC}"
  fi
}

getServerPort(){
  local server_path="$1"
  local port_info="Tidak diketahui"
  if [ -f "$server_path/server.properties" ]; then
    port_info="$(grep -E '^server-port=' "$server_path/server.properties" | cut -d'=' -f2)"
  fi
  echo "$port_info"
}

loadingAnimation(){
  local text="$1"; tput civis 2>/dev/null || true
  local spin='-\|/'; local i=0
  while true; do
    i=$(( (i+1) % 4 ))
    echo -ne "\r\033[K${text} ${spin:$i:1}"
    sleep 0.1
  done
}

consoleCmd(){
  local server_name="$1"; shift
  local cmd="$*"
  if tmux has-session -t "$server_name" 2>/dev/null; then
    tmux send-keys -t "$server_name" "$cmd" C-m
    return 0
  else
    echo -e "${RED}Server tidak berjalan.${NC}"
    return 1
  fi
}

lastLogMatch(){
  local server_path="$1" pattern="$2"
  tac "$server_path/logs/latest.log" 2>/dev/null | grep -m1 -E "$pattern"
}

pause(){ read -rp $'\nTekan [Enter] untuk lanjut...'; }

getOnlinePlayers(){
  local server_name="$1"
  local server_path="$SERVERS_DIR/$server_name"
  consoleCmd "$server_name" "list" >/dev/null 2>&1 || return 1
  sleep 1
  local line
  line="$(lastLogMatch "$server_path" 'There are .* players online|players online:')"
  if echo "$line" | grep -q ":"; then
    echo "$line" | sed 's/.*online: *//; s/, /\n/g; s/ //g' | sed '/^$/d'
  fi
}

playersMenu(){
  local server_name="$1" choice target msg
  while true; do
    clear
    echo -e "${BLUE}--- Kelola Pemain: ${YELLOW}${server_name}${BLUE} ---${NC}"
    echo "Pemain online:"
    mapfile -t players < <(getOnlinePlayers "$server_name")
    if [ ${#players[@]} -eq 0 ]; then
      echo " (tidak ada pemain online)"
    else
      local i=1; for p in "${players[@]}"; do echo " $i) $p"; i=$((i+1)); done
    fi
    echo -e "\nAksi:"
    echo " 1) Kirim pesan (tell)"
    echo " 2) Kick pemain"
    echo " 3) Ban pemain"
    echo " 4) Unban pemain"
    echo " 5) Whitelist add"
    echo " 6) Whitelist remove"
    echo " 7) Op pemain"
    echo " 8) Deop pemain"
    echo " 0) Kembali"
    read -rp "Pilih: " choice
    case "$choice" in
      0) return ;;
      1) read -rp "Nama pemain: " target; [ -z "$target" ] && continue
         read -rp "Pesan: " msg
         consoleCmd "$server_name" "tell $target $msg" && echo -e "${GREEN}Pesan dikirim.${NC}"; pause ;;
      2) read -rp "Kick siapa: " target; [ -z "$target" ] && continue
         read -rp "Alasan (opsional): " msg
         consoleCmd "$server_name" "kick $target $msg" && echo -e "${GREEN}Kick terkirim.${NC}"; pause ;;
      3) read -rp "Ban siapa: " target; [ -z "$target" ] && continue
         read -rp "Alasan (opsional): " msg
         consoleCmd "$server_name" "ban $target $msg" && echo -e "${GREEN}Ban ditambahkan.${NC}"; pause ;;
      4) read -rp "Unban siapa: " target; [ -z "$target" ] && continue
         consoleCmd "$server_name" "pardon $target" && echo -e "${GREEN}Pemain di-unban.${NC}"; pause ;;
      5) read -rp "Whitelist add siapa: " target; [ -z "$target" ] && continue
         consoleCmd "$server_name" "whitelist add $target" && echo -e "${GREEN}Ditambahkan ke whitelist.${NC}"; pause ;;
      6) read -rp "Whitelist remove siapa: " target; [ -z "$target" ] && continue
         consoleCmd "$server_name" "whitelist remove $target" && echo -e "${GREEN}Dihapus dari whitelist.${NC}"; pause ;;
      7) read -rp "Op siapa: " target; [ -z "$target" ] && continue
         consoleCmd "$server_name" "op $target" && echo -e "${GREEN}Pemain di-op.${NC}"; pause ;;
      8) read -rp "Deop siapa: " target; [ -z "$target" ] && continue
         consoleCmd "$server_name" "deop $target" && echo -e "${GREEN}Pemain di-deop.${NC}"; pause ;;
      *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
  done
}

configEditorMenu(){
  local server_name="$1" server_path="$SERVERS_DIR/$server_name"
  while true; do
    clear
    echo -e "${BLUE}--- Editor Konfigurasi: ${YELLOW}${server_name}${BLUE} ---${NC}"
    declare -A files; local idx=1
    for f in server.properties spigot.yml paper.yml paper-global.yml bukkit.yml commands.yml ops.json whitelist.json permissions.yml; do
      if [ -f "$server_path/$f" ]; then files[$idx]="$f"; printf " %2d) %s\n" "$idx" "$f"; idx=$((idx+1)); fi
    done
    [ $idx -eq 1 ] && echo " (Belum ada file konfigurasi umum yang terdeteksi.)"
    echo -e "\nAksi lain:"
    echo " 99) Buka folder server"
    echo "  0) Kembali"
    read -rp "Pilih nomor file untuk diedit: " pick
    if [ "$pick" = "0" ]; then
      return
    elif [ "$pick" = "99" ]; then
      mc "$server_path"
    elif [[ "$pick" =~ ^[0-9]+$ ]] && [ -n "${files[$pick]:-}" ]; then
      "$EDITOR_BIN" "$server_path/${files[$pick]}"
    else
      echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1
    fi
  done
}

ensureRestartScript(){
  local server_name="$1" server_path="$SERVERS_DIR/$server_name" script="$server_path/restart.sh"
  if [ ! -f "$script" ]; then
    cat > "$script" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
NAME="$(basename "$PWD")"
if tmux has-session -t "$NAME" 2>/dev/null; then
  tmux send-keys -t "$NAME" "stop" C-m
  for i in {1..60}; do tmux has-session -t "$NAME" 2>/dev/null || break; sleep 1; done
  tmux kill-session -t "$NAME" 2>/dev/null || true
fi
tmux new-session -d -s "$NAME" "cd '$(pwd)' && ./start.sh"
SH
    chmod +x "$script"
  fi
  echo "$script"
}

cronAddDailyRestart(){
  local server_name="$1" hhmm="$2"
  local h="${hhmm%:*}" m="${hhmm#*:}" server_path="$SERVERS_DIR/$server_name"
  local script; script="$(ensureRestartScript "$server_name")"
  local tag="# mc-restart:${server_name}"
  local tmp; tmp="$(mktemp)"
  crontab -l 2>/dev/null | sed "/${tag}/d" > "$tmp"
  echo "$m $h * * * /bin/bash '$script' >> '$server_path/logs/auto-restart.log' 2>&1 ${tag}" >> "$tmp"
  crontab "$tmp"; rm -f "$tmp"
}

cronRemoveRestart(){
  local server_name="$1" tag="# mc-restart:${server_name}"
  local tmp; tmp="$(mktemp)"
  crontab -l 2>/dev/null | sed "/${tag}/d" > "$tmp"
  crontab "$tmp"; rm -f "$tmp"
}

autoRestartMenu(){
  local server_name="$1" c t
  while true; do
    clear
    echo -e "${BLUE}--- Jadwal Restart Otomatis: ${YELLOW}${server_name}${BLUE} ---${NC}"
    echo " 1) Set harian (HH:MM)"
    echo " 2) Hapus jadwal"
    echo " 0) Kembali"
    read -rp "Pilih: " c
    case "$c" in
      1) read -rp "Masukkan waktu (HH:MM): " t
         if [[ "$t" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
           cronAddDailyRestart "$server_name" "$t"; echo -e "${GREEN}Jadwal diset ${t}.${NC}"
         else
           echo -e "${RED}Format waktu tidak valid.${NC}"
         fi; pause ;;
      2) cronRemoveRestart "$server_name"; echo -e "${GREEN}Jadwal dihapus.${NC}"; pause ;;
      0) return ;;
      *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
  done
}

ramAllocationMenu(){
  local server_name="$1" server_path="$SERVERS_DIR/$server_name" start_script_path="$server_path/start.sh"
  [ -f "$start_script_path" ] || { echo -e "${RED}File start.sh tidak ditemukan!${NC}"; sleep 2; return; }
  local current_ram; current_ram=$(grep -oE '(-Xmx)[0-9]+[GgMm]' "$start_script_path" | head -n1 | sed 's/-Xmx//')
  clear
  echo -e "${BLUE}--- Pengaturan RAM untuk ${YELLOW}$server_name${BLUE} ---${NC}"
  echo -e "Alokasi saat ini (Xmx): ${GREEN}${current_ram:-Tidak diatur}${NC}"
  read -rp "Alokasi baru (mis: 4G, 2048M) [Enter batal]: " new_ram
  [ -z "$new_ram" ] && { echo -e "${YELLOW}Dibatalkan.${NC}"; sleep 1; return; }
  loadingAnimation "Menyimpan perubahan" & local pid=$!
  sed -i -E "s/(-Xms)[0-9]+[GgMm]/\1$new_ram/g" "$start_script_path"
  sed -i -E "s/(-Xmx)[0-9]+[GgMm]/\1$new_ram/g" "$start_script_path"
  sleep 1; kill $pid &>/dev/null; tput cnorm
  echo -e "\r${GREEN}RAM diubah ke ${new_ram}.${NC}"; sleep 1
}

pluginWebMenu(){
  local server_name="$1"
  local PLUG_SH="$FUNCTIONS_DIR/plugin_web.sh"
  local PLUG_PY="$FUNCTIONS_DIR/plugin_web.py"
  normalize_scripts
  if [ ! -x "$PLUG_SH" ]; then
    echo -e "${RED}plugin_web.sh tidak ditemukan di $PLUG_SH${NC}"; pause; return
  fi
  while true; do
    clear
    echo -e "${BLUE}--- Website Upload Plugin: ${YELLOW}${server_name}${BLUE} ---${NC}"
    echo " 1) Start website"
    echo " 2) Stop website"
    echo " 3) Status"
    echo " 4) Tampilkan URL"
    echo " 0) Kembali"
    read -rp "Pilih: " c
    case "$c" in
      1) "$PLUG_SH" start "$server_name"; pause ;;
      2) "$PLUG_SH" stop "$server_name"; pause ;;
      3) "$PLUG_SH" status "$server_name"; pause ;;
      4) "$PLUG_SH" url "$server_name"; echo; pause ;;
      0) return ;;
      *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
  done
}

serverActionMenu(){
  local server_name="$1" server_path="$SERVERS_DIR/$server_name"
  normalize_scripts
  while true; do
    local status version_info domain_info port_info
    status=$(getServerStatus "$server_name")
    version_info=$(grep 'VERSION=' "$server_path/panel.conf" 2>/dev/null | cut -d'=' -f2)
    domain_info=$(grep 'DOMAIN=' "$server_path/panel.conf" 2>/dev/null | cut -d'=' -f2)
    port_info=$(getServerPort "$server_path")
    [ -z "$version_info" ] && version_info="?"
    [ -z "$domain_info" ] && domain_info="Tidak diatur"
    clear
    echo -e "${BLUE}==================== DASBOR SERVER: ${YELLOW}$server_name ${BLUE}====================${NC}"
    printf " %-12s : %s\n" "Status" "$status"
    printf " %-12s : ${YELLOW}%s${NC}\n" "Versi" "$version_info"
    printf " %-12s : ${YELLOW}%s${NC}\n" "Domain" "$domain_info"
    printf " %-12s : ${YELLOW}%s${NC}\n" "Port" "$port_info"
    echo -e "\n${BLUE}--- KONTROL SERVER ---${NC}"
    echo " 1. Start Server"
    echo " 2. Stop Server"
    echo " 3. Restart Server"
    echo " 4. Open Console"
    echo -e "\n${BLUE}--- MANAJEMEN & KONFIGURASI ---${NC}"
    echo " 5. Kelola Pemain"
    echo " 6. Editor Konfigurasi"
    echo " 7. File Manager"
    echo " 8. RAM Alocation"
    echo " 9. Set Auto Restart"
    echo "10. Website Upload Plugin"
    echo "11. Systemd Autostart"
    echo -e "\n${YELLOW} 0. Back To Main Menu${NC}"
    read -rp "Masukkan pilihan: " choice
    case "$choice" in
      1)
        if ! tmux has-session -t "$server_name" 2>/dev/null; then
          loadingAnimation "Starting server" & local pid=$!
          tmux new-session -d -s "$server_name" "cd '$server_path' && ./start.sh"
          sleep 2; kill $pid &>/dev/null; tput cnorm
          echo -e "\r${GREEN}Server run.${NC}"; sleep 1
        else
          echo -e "${YELLOW}Server sudah berjalan.${NC}"; sleep 1
        fi ;;
      2)
        if tmux has-session -t "$server_name" 2>/dev/null; then
          loadingAnimation "Menghentikan server" & local pid=$!
          tmux send-keys -t "$server_name" "stop" C-m
          for i in {1..30}; do ! tmux has-session -t "$server_name" 2>/dev/null && break; sleep 1; done
          tmux kill-session -t "$server_name" &>/dev/null
          sleep 1; kill $pid &>/dev/null; tput cnorm
          echo -e "\r${GREEN}Server dihentikan.${NC}"; sleep 1
        else
          echo -e "${RED}Server tidak berjalan.${NC}"; sleep 1
        fi ;;
      3)
        if tmux has-session -t "$server_name" 2>/dev/null; then
          loadingAnimation "Restart (hentikan)" & local pid=$!
          tmux send-keys -t "$server_name" "stop" C-m
          for i in {1..30}; do ! tmux has-session -t "$server_name" 2>/dev/null && break; sleep 1; done
          tmux kill-session -t "$server_name" &>/dev/null
          kill $pid &>/dev/null; tput cnorm
          echo -e "\r\033[KRestart (mulai)..."
          loadingAnimation "Memulai server" & pid=$!
          tmux new-session -d -s "$server_name" "cd '$server_path' && ./start.sh"
          sleep 2; kill $pid &>/dev/null; tput cnorm
          echo -e "\r${GREEN}Server di-restart.${NC}"; sleep 1
        else
          echo -e "${YELLOW}Server tidak berjalan. Memulai...${NC}"
          loadingAnimation "Memulai server" & local pid=$!
          tmux new-session -d -s "$server_name" "cd '$server_path' && ./start.sh"
          sleep 2; kill $pid &>/dev/null; tput cnorm
          echo -e "\r${GREEN}Server dimulai.${NC}"; sleep 1
        fi ;;
      4)
        if tmux has-session -t "$server_name" 2>/dev/null; then
          echo "Menghubungkan ke konsol (CTRL+B lalu D untuk keluar)..."
          sleep 1; tmux attach-session -t "$server_name"
        else
          echo -e "${RED}Server tidak berjalan.${NC}"; sleep 1
        fi ;;
      5) playersMenu "$server_name" ;;
      6) configEditorMenu "$server_name" ;;
      7) mc "$server_path" ;;
      8) ramAllocationMenu "$server_name" ;;
      9) autoRestartMenu "$server_name" ;;
      10) pluginWebMenu "$server_name" ;;
      11) 
  if declare -F systemdMenu >/dev/null; then
    systemdMenu "$server_name"
  else
    echo "Module systemd_manager.sh belum dimuat."
    read -rp "Tekan [Enter]..."
  fi
  ;;
      0) return ;;
      *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
  done
}

manageServers(){
  normalize_scripts
  clear
  mapfile -t servers < <(find "$SERVERS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
  if [ ${#servers[@]} -eq 0 ]; then
    echo -e "${YELLOW}Belum ada server yang dibuat.${NC}"
    read -rp "Tekan [Enter] untuk kembali..."; return
  fi
  echo -e "${BLUE}--- Kelola Server yang Ada ---${NC}"
  local i=1
  for server_path in "${servers[@]}"; do
    local server_name; server_name="$(basename "$server_path")"
    local version_info; version_info=$(grep 'VERSION=' "$server_path/panel.conf" 2>/dev/null | cut -d'=' -f2)
    [ -z "$version_info" ] && version_info="?"
    echo "$i. $server_name ($version_info) ($(getServerStatus "$server_name"))"
    i=$((i+1))
  done
  echo -e "\n${YELLOW}0. Kembali${NC}"
  read -rp "Masukkan nomor server [1-${#servers[@]}]: " server_choice
  if [[ "$server_choice" =~ ^[0-9]+$ ]] && [ "$server_choice" -ge 1 ] && [ "$server_choice" -le ${#servers[@]} ]; then
    local selected_server_path="${servers[$((server_choice-1))]}"
    serverActionMenu "$(basename "$selected_server_path")"
  elif [ "$server_choice" = "0" ]; then
    return
  else
    echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  manageServers
fi
