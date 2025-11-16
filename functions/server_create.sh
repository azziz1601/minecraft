set -euo pipefail
BASE_DIR="${BASE_DIR:-/root/mc-panel}"
SERVERS_DIR="${SERVERS_DIR:-$BASE_DIR/servers}"
EGGS_DIR="${EGGS_DIR:-$BASE_DIR/eggs}"

# Aktifkan warna jika output ke terminal
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# Loading bar biru dinamis
show_loading_bar() {
  local msg="${1:-"Menginstal..."}"
  local pid="${2:-}"
  local chars="/-\|"
  local i=0
  echo -ne "${BLUE}${msg} ${NC}"
  while true; do
    i=$(( (i+1) %4 ))
    printf "\b${BLUE}%s${NC}" "${chars:$i:1}"
    sleep 0.1
    if [ -n "$pid" ]; then
      if ! kill -0 "$pid" 2>/dev/null; then break; fi
    fi
  done
  printf "\b${BLUE}✓${NC}\n"
}

need_cmd(){ command -v "$1" >/dev/null 2>&1; }
pause(){ read -rp $'\nTekan [Enter] untuk lanjut...'; }
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
      udp) port_in_use_udp "$port" && used=1 ;;
      *)   port_in_use_tcp "$port" && used=1 ;;
    esac
    (( used==1 )) && { echo -e "${YELLOW}Port ${port} sedang digunakan. Coba port lain.${NC}"; continue; }
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

write_world_seed() {
  local prop_file="$1" seed="$2"
  if [ ! -f "$prop_file" ]; then
    echo "level-seed=${seed}" > "$prop_file"; return
  fi
  sed -i '/^level-seed=/d' "$prop_file"
  echo "level-seed=${seed}" >> "$prop_file"
}

prompt_seed_menu() {
  printf "\n${BLUE}--- Konfigurasi World Seed ---${NC}\n"
  printf " ${YELLOW}1${NC}) Random seed (default, tekan Enter)\n"
  printf " ${YELLOW}2${NC}) Custom seed\n"
  
  tput cnorm 2>/dev/null || true
  read -rp "Pilih [1 atau 2, atau Enter untuk random]: " seed_choice
  seed_choice="${seed_choice:-1}"
  
  local seed_value=""
  case "$seed_choice" in
    1|"")
      seed_value=""
      printf "${GREEN}✓ Random Seed${NC}\n"
      ;;
    2)
      read -rp "Masukkan seed custom: " seed_value
      if [[ -z "$seed_value" ]]; then
        printf "${YELLOW}⚠ Seed kosong, pakai random${NC}\n"
        seed_value=""
      else
        printf "${GREEN}✓ Seed: ${seed_value}${NC}\n"
      fi
      ;;
    *)
      printf "${YELLOW}Invalid, pakai random${NC}\n"
      seed_value=""
      ;;
  esac
  
  echo "$seed_value"
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
  elif [[ "$egg_name" == *"fabric"* ]]; then
    base_port=25565
    echo -e "${YELLOW}Egg terdeteksi Fabric — port default ${base_port}/tcp${NC}"
    SERVER_PORT="$(prompt_port_loop "Masukkan port TCP untuk server" "$base_port" "tcp")"
  else
    base_port=25565
    echo -e "${YELLOW}Egg terdeteksi Java/Paper — port default ${base_port}/tcp${NC}"
    SERVER_PORT="$(prompt_port_loop "Masukkan port TCP untuk server" "$base_port" "tcp")"
  fi
  echo -e "Port yang dipakai: ${GREEN}${SERVER_PORT}${NC}"
  local WORLD_SEED
  WORLD_SEED="$(prompt_seed_menu)"
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
      echo -e "Konfigurasi untuk: ${YELLOW}$var_name${NC}"
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
  echo "$server_memory" > "$server_path/memory.conf"
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

  bash "$temp_install_script" >install.log 2>&1 &
  install_pid=$!
  show_loading_bar "Menginstal server dari egg" "$install_pid"
  wait "$install_pid"
  rm -f "$temp_install_script"

  # panel.conf + folder mods/plugins
  {
    echo "EGG=$egg_name"
    echo "MEMORY=$server_memory"
    echo "DOMAIN=$server_domain"
    echo "PORT=$SERVER_PORT"
    echo "SEED=$WORLD_SEED"
    if [[ "$egg_name" == *"pocketmine"* ]]; then
      echo "VERSION=Bedrock"
      echo "LOADER=bedrock"
    elif [[ "$egg_name" == *"fabric"* ]]; then
      echo "VERSION=Java"
      echo "LOADER=fabric"
    else
      echo "VERSION=Java"
      echo "LOADER=paper"
    fi
  } > "panel.conf"

  if grep -q '^LOADER=fabric' panel.conf; then
    mkdir -p "mods"
  else
    mkdir -p "plugins"
  fi

  # Penyesuaian jar untuk Fabric
  local jar_file="server.jar"
  if [[ "$egg_name" == *"fabric"* ]]; then
    jar_file="fabric-server-launch.jar"
    if [ ! -f "$jar_file" ]; then
      jar_guess="$(ls -1 fabric-server-launch*.jar 2>/dev/null | head -n1 || true)"
      [ -n "$jar_guess" ] && ln -sf "$jar_guess" "$jar_file" || jar_file="server.jar"
    fi
  else
    [ -f server.jar ] || { jar_guess="$(ls -1 *.jar 2>/dev/null | head -n1 || true)"; [ -n "$jar_guess" ] && ln -sf "$jar_guess" server.jar; }
  fi

  # Tulis server-port untuk Java, bukan Bedrock
  if [[ "$egg_name" != *"pocketmine"* ]]; then
    write_java_port "server.properties" "$SERVER_PORT"
    if [[ -n "$WORLD_SEED" ]]; then
      write_world_seed "server.properties" "$WORLD_SEED"
    fi
  fi

  cat > "start.sh" <<SH
#!/usr/bin/env bash
cd "\$(dirname "\$0")"
RAM_ALLOC=\$(cat memory.conf)
JAVA_BIN="\${JAVA_BIN:-java}"
XMS="\$RAM_ALLOC"
XMX="\$RAM_ALLOC"
echo "==> Menjalankan server: $jar_file (Java: \$JAVA_BIN, Xms=\$XMS, Xmx=\$XMX)"
exec "\$JAVA_BIN" -Xms"\$XMS" -Xmx"\$XMX" -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \\
-XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch \\
-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \\
-XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 \\
-XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 \\
-XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 \\
-XX:+UseStringDeduplication \\
-Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true \\
-jar $jar_file nogui
SH
  chmod +x "start.sh"
  echo "eula=true" > "eula.txt"
  cd "$BASE_DIR"
  echo -e "\n${GREEN}✅   Instalasi server '$server_name' berdasarkan egg '$egg_name' selesai!${NC}"
  local seed_display="${WORLD_SEED:-Random}"
  echo -e "${YELLOW}Catatan:${NC} Port: ${SERVER_PORT}, Seed: ${seed_display}. start.sh memakai Java 21 flags. Xms/Xmx = ${server_memory}. EULA sudah disetujui."
  echo -e "${BLUE}Log detail tersimpan di ${server_path}/install.log${NC}"
  pause
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  createServer
fi
