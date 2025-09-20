#!/usr/bin/env bash
# server_create.sh — Buat server Minecraft dari Egg Pterodactyl (Paper/Bedrock)
# Fitur:
# - Pilih egg (.json), nama server, RAM, domain
# - Pilih port dengan pengecekan bentrok (TCP untuk Java/Paper, UDP untuk PocketMine)
# - Baca variables dari egg (rules bisa string/array) → diexport ke installer
# - Jalankan skrip instalasi egg (ganti /mnt/server ke direktori server)
# - Tulis panel.conf, pastikan ada server.jar (symlink jika nama lain)
# - Tulis server.properties: server-port=PORT
# - Buat start.sh (Java 21 flags); Xms/Xmx mengikuti input RAM
# - Otomatis setujui EULA (eula.txt = true)

set -euo pipefail

BASE_DIR="${BASE_DIR:-/root/mc-panel}"
SERVERS_DIR="${SERVERS_DIR:-$BASE_DIR/servers}"
EGGS_DIR="${EGGS_DIR:-$BASE_DIR/eggs}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

need_cmd(){ command -v "$1" >/dev/null 2>&1; }
pause(){ read -rp $'\nTekan [Enter] untuk kembali...'; }

port_in_use_tcp() { ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${1}$"; }
port_in_use_udp() { ss -lun 2>/dev/null | awk '{print $5}' | grep -q ":${1}$"; }

prompt_port_loop() {
  local prompt="$1" def="$2" mode="${3:-tcp}" port
  while true; do
    read -rp "${prompt} [Default: ${def}]: " port
    port="${port:-$def}"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
      echo -e "${RED}Port tidak valid. Masukkan angka 1..65535.${NC}"; continue
    fi
    local used=0
    case "$mode" in
      tcp)  port_in_use_tcp "$port" && used=1 ;;
      udp)  port_in_use_udp "$port" && used=1 ;;
      both) { port_in_use_tcp "$port" || port_in_use_udp "$port"; } && used=1 ;;
      *)    port_in_use_tcp "$port" && used=1 ;;
    esac
    if (( used == 1 )); then
      echo -e "${YELLOW}Port ${port} sedang digunakan. Coba port lain.${NC}"
      continue
    fi
    echo "$port"; return 0
  done
}

write_java_port() {
  local prop_file="$1" port="$2"
  if [ ! -f "$prop_file" ]; then
    echo "server-port=${port}" > "$prop_file"; return
  fi
  sed -i '/^server-port=/d' "$prop_file"
  echo "server-port=${port}" >> "$prop_file"
}

createServer() {
  clear
  echo -e "${BLUE}--- Membuat Server Baru dari Egg ---${NC}"

  if ! need_cmd jq; then
    echo -e "${RED}jq tidak ditemukan. Install: apt-get install -y jq${NC}"
    pause; return
  fi

  mapfile -t eggs < <(find "$EGGS_DIR" -type f -name "*.json" | sort)
  if [ ${#eggs[@]} -eq 0 ]; then
    echo -e "${RED}Tidak ada file egg (.json) ditemukan di ${EGGS_DIR}.${NC}"
    pause; return
  fi

  echo "Pilih Egg untuk server baru:"
  local i=1
  for egg in "${eggs[@]}"; do
    echo "$i. $(basename "$egg")"; i=$((i+1))
  done
  read -rp "Masukkan nomor egg [1-${#eggs[@]}]: " egg_choice
  local selected_egg_file="${eggs[$egg_choice-1]:-}"
  if [ -z "$selected_egg_file" ]; then
    echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1; return
  fi
  local egg_name; egg_name="$(basename "$selected_egg_file")"
  echo -e "Egg yang dipilih: ${GREEN}$egg_name${NC}"

  read -rp "Masukkan nama unik untuk server (tanpa spasi): " server_name
  if [[ -z "$server_name" || -d "$SERVERS_DIR/$server_name" ]]; then
    echo -e "${RED}Nama server kosong atau sudah ada.${NC}"; sleep 1; return
  fi

  read -rp "Masukkan alokasi memori (cth: 1024M atau 2G): " server_memory
  if ! [[ "$server_memory" =~ ^[0-9]+[MmGg]$ ]]; then
    echo -e "${RED}Format memori salah. Contoh: 1024M atau 2G.${NC}"; sleep 1; return
  fi

  read -rp "Masukkan domain (kosongkan jika tidak ada): " server_domain

  local SERVER_PORT base_port
  if [[ "$egg_name" == *"pocketmine"* ]]; then
    base_port=19132
    echo -e "${YELLOW}Egg terdeteksi Bedrock/PocketMine — port default ${base_port}/udp${NC}"
    SERVER_PORT="$(prompt_port_loop "Masukkan port UDP untuk server" "$base_port" "udp")"
  else
    base_port=25565
    echo -e "${YELLOW}Egg terdeteksi Java/Paper — port default ${base_port}/tcp${NC}"
    SERVER_PORT="$(prompt_port_loop "Masukkan port TCP untuk server" "$base_port" "tcp")"
  fi
  echo -e "Port yang dipakai: ${GREEN}${SERVER_PORT}${NC}"

  local -a env_variables_exports=()
  local variable_count
  variable_count=$(jq '.variables | length' "$selected_egg_file")

  if [[ $variable_count -gt 0 ]]; then
    echo -e "\n${BLUE}--- Konfigurasi Variabel Egg ---${NC}"
    local idx
    for (( idx=0; idx<variable_count; idx++ )); do
      local var_name var_desc var_env var_default var_rules
      var_name=$(jq -r ".variables[$idx].name // \"(tanpa nama)\"" "$selected_egg_file")
      var_desc=$(jq -r ".variables[$idx].description // \"\"" "$selected_egg_file")
      var_env=$(jq -r ".variables[$idx].env_variable // \"\"" "$selected_egg_file")
      var_default=$(jq -r ".variables[$idx].default_value // \"\"" "$selected_egg_file")
      var_rules=$(jq -r ".variables[$idx].rules
        | if type==\"array\" then join(\", \")
          elif type==\"string\" then .
          else \"-\"
          end" "$selected_egg_file")
      echo "Konfigurasi untuk: ${YELLOW}$var_name${NC}"
      [[ -n "$var_desc" ]] && echo "Deskripsi: $var_desc"
      echo "Aturan: $var_rules"
      read -rp "Masukkan nilai [Default: $var_default]: " user_value
      [ -z "$user_value" ] && user_value=$var_default
      if [[ -n "$var_env" ]]; then
        env_variables_exports+=("export $var_env=\"$user_value\"")
      fi
      echo ""
    done
  fi

  local server_path="$SERVERS_DIR/$server_name"
  mkdir -p "$server_path/logs"
  cd "$server_path" || { echo "Gagal masuk ke direktori server."; return; }

  echo -e "\n${YELLOW}Memulai instalasi untuk server '${server_name}'...${NC}"

  local install_script_raw install_script_clean
  install_script_raw=$(jq -r '.scripts.installation.script // ""' "$selected_egg_file")
  if [[ -z "$install_script_raw" || "$install_script_raw" == "null" ]]; then
    echo -e "${RED}Egg tidak memiliki installation.script yang valid.${NC}"
    pause; return
  fi
  install_script_clean=$(echo "$install_script_raw" | sed 's/\r$//' | sed 's/\\"/"/g')

  local temp_install_script="/tmp/install_${server_name}.sh"
  {
    echo "#!/usr/bin/env bash"
    case "$server_memory" in
      *[Gg]) echo "export SERVER_MEMORY=$(( ${server_memory%[Gg]} * 1024 ))" ;;
      *[Mm]) echo "export SERVER_MEMORY=${server_memory%[Mm]}" ;;
      *)     echo "export SERVER_MEMORY=1024" ;;
    esac
    echo "export SERVER_PORT=${SERVER_PORT}"
    for export_cmd in "${env_variables_exports[@]}"; do echo "$export_cmd"; done
    echo
    echo "$install_script_clean" | sed "s|/mnt/server|$(pwd)|g"
  } > "$temp_install_script"

  chmod +x "$temp_install_script"
  echo "Menjalankan skrip instalasi dari egg. Mohon tunggu..."
  bash "$temp_install_script"
  rm -f "$temp_install_script"

  {
    echo "EGG=$egg_name"
    echo "MEMORY=$server_memory"
    echo "DOMAIN=$server_domain"
    echo "PORT=$SERVER_PORT"
    if [[ "$egg_name" == *"pocketmine"* ]]; then
      echo "VERSION=Bedrock"
    else
      echo "VERSION=Java"
    fi
  } > "panel.conf"

  if [ ! -f server.jar ]; then
    local jar_guess
    jar_guess="$(ls -1 *.jar 2>/dev/null | head -n1 || true)"
    if [ -n "$jar_guess" ]; then ln -sf "$jar_guess" server.jar; fi
  fi

  write_java_port "server.properties" "$SERVER_PORT"

  cat > "start.sh" <<SH
#!/usr/bin/env bash
cd "\$(dirname "\$0")"
JAVA_BIN="\${JAVA_BIN:-java}"
XMS="$server_memory"
XMX="$server_memory"

echo "==> Menjalankan server: server.jar (Java: \$JAVA_BIN, Xms=\$XMS, Xmx=\$XMX)"
exec "\$JAVA_BIN" -Xms"\$XMS" -Xmx"\$XMX" -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \\
-XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch \\
-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \\
-XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 \\
-XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 \\
-XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 \\
-XX:+UseStringDeduplication \\
-Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true \\
-jar server.jar --nogui
SH
  chmod +x "start.sh"

  # === Setujui EULA otomatis ===
  echo "eula=true" > "eula.txt"

  cd "$BASE_DIR"

  echo -e "\n${GREEN}✅ Instalasi server '$server_name' berdasarkan egg '$egg_name' selesai!${NC}"
  echo -e "${YELLOW}Catatan:${NC} Port: ${SERVER_PORT}. start.sh memakai Java 21 flags. Xms/Xmx = ${server_memory}. EULA sudah disetujui."
  pause
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  createServer
fi

