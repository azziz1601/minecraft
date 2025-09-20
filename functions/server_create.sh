#!/bin/bash

# ===== Helper: Cek & pilih port =====

# Cek port TCP terpakai (return 0 = terpakai, 1 = bebas)
port_in_use_tcp() {
  local p="$1"
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${p}$"
}

# Cek port UDP terpakai (return 0 = terpakai, 1 = bebas)
port_in_use_udp() {
  local p="$1"
  ss -lun 2>/dev/null | awk '{print $5}' | grep -q ":${p}$"
}

# Minta port dari user + validasi ketersediaan; jika terpakai → minta ulang
# arg1: prompt text, arg2: default, arg3: mode ("tcp" | "udp" | "both")
prompt_port_loop() {
  local prompt="$1" def="$2" mode="${3:-tcp}" port
  while true; do
    read -p "${prompt} [Default: ${def}]: " port
    port="${port:-$def}"
    # valid angka 1..65535
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
      echo -e "Port tidak valid. Masukkan angka 1-65535."; continue
    fi
    # cek kepakai
    local used=0
    case "$mode" in
      tcp)  port_in_use_tcp "$port" && used=1 ;;
      udp)  port_in_use_udp "$port" && used=1 ;;
      both) { port_in_use_tcp "$port" || port_in_use_udp "$port"; } && used=1 ;;
      *)    port_in_use_tcp "$port" && used=1 ;;
    esac
    if (( used == 1 )); then
      echo -e "Port ${port} sedang digunakan. Silakan masukkan port lain."
      continue
    fi
    echo "$port"
    return 0
  done
}

# Tulis/replace server-port di server.properties (buat file jika belum ada)
write_java_port() {
  local prop_file="$1" port="$2"
  if [ ! -f "$prop_file" ]; then
    echo "server-port=${port}" > "$prop_file"
    return
  fi
  sed -i '/^server-port=/d' "$prop_file"
  echo "server-port=${port}" >> "$prop_file"
}

# ===== Buat systemd service =====
create_systemd_service() {
  local server_name="$1"
  local server_path="$2"
  local unit="/etc/systemd/system/mc-${server_name}.service"

  sudo tee "$unit" > /dev/null <<UNIT
[Unit]
Description=Minecraft Server $server_name
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$server_path
ExecStart=$server_path/start.sh
User=root
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT

  sudo systemctl daemon-reload
  sudo systemctl enable "mc-${server_name}.service"
  sudo systemctl restart "mc-${server_name}.service"

  echo -e "${GREEN:-}Systemd service mc-${server_name}.service berhasil dibuat & dijalankan.${NC:-}"
  echo "Gunakan: systemctl status mc-${server_name}.service"
}

# ===== Fungsi utama pembuatan server =====
function createServer() {
    clear
    echo -e "${BLUE:-}--- Membuat Server Baru dari Egg ---${NC:-}"
    mapfile -t eggs < <(find "$EGGS_DIR" -type f -name "*.json")
    if [ ${#eggs[@]} -eq 0 ]; then echo -e "${RED:-}Tidak ada file egg (.json) ditemukan.${NC:-}"; read -p "Tekan [Enter]..."; return; fi
    
    echo "Pilih Egg untuk server baru:"
    i=1; for egg in "${eggs[@]}"; do echo "$i. $(basename "$egg")"; i=$((i+1)); done
    read -p "Masukkan nomor egg [1-${#eggs[@]}]: " egg_choice
    selected_egg_file="${eggs[$egg_choice-1]}"
    if [ -z "$selected_egg_file" ]; then echo -e "${RED:-}Pilihan tidak valid.${NC:-}"; sleep 2; return; fi
    local egg_name=$(basename "$selected_egg_file")
    echo -e "Egg yang dipilih: ${GREEN:-}$egg_name${NC:-}\n"

    read -p "Masukkan nama unik untuk server (tanpa spasi): " server_name
    if [ -z "$server_name" ] || [ -d "$SERVERS_DIR/$server_name" ]; then echo -e "${RED:-}Nama server tidak valid atau sudah ada.${NC:-}"; sleep 2; return; fi

    read -p "Masukkan alokasi memori (cth: 1024M): " server_memory
    if ! [[ "$server_memory" =~ ^[0-9]+M$ ]]; then echo -e "${RED:-}Format memori salah.${NC:-}"; sleep 2; return; fi

    read -p "Masukkan domain (kosongkan jika tidak ada): " server_domain

    # === Tentukan port sebelum instalasi (supaya bisa dipakai env jika egg butuh) ===
    local base_port
    if [[ "$egg_name" == *"pocketmine"* ]]; then
      base_port=19132  # UDP (Bedrock)
      echo -e "${YELLOW:-}Egg terdeteksi Bedrock/PocketMine — port default ${base_port}/udp${NC:-}"
      SERVER_PORT=$(prompt_port_loop "Masukkan port UDP untuk server" "$base_port" "udp")
    else
      base_port=25565  # TCP (Java/Paper/Spigot)
      echo -e "${YELLOW:-}Egg terdeteksi Java/Paper — port default ${base_port}/tcp${NC:-}"
      SERVER_PORT=$(prompt_port_loop "Masukkan port TCP untuk server" "$base_port" "tcp")
    fi
    echo -e "Port yang dipakai: ${GREEN:-}${SERVER_PORT}${NC:-}\n"

    local env_variables_exports=()
    local variable_count
    variable_count=$(jq '.variables | length' "$selected_egg_file")

    if [[ $variable_count -gt 0 ]]; then
        echo -e "\n${BLUE:-}--- Konfigurasi Variabel Egg ---${NC:-}"
        for (( i=0; i<variable_count; i++ )); do
            local var_name var_desc var_env var_default var_rules user_value
            var_name=$(jq -r ".variables[$i].name" "$selected_egg_file")
            var_desc=$(jq -r ".variables[$i].description" "$selected_egg_file")
            var_env=$(jq -r ".variables[$i].env_variable" "$selected_egg_file")
            var_default=$(jq -r ".variables[$i].default_value" "$selected_egg_file")
            var_rules=$(jq -r ".variables[$i].rules | join(\", \")" "$selected_egg_file")

            echo "Konfigurasi untuk: ${YELLOW:-}$var_name${NC:-}"
            echo "Deskripsi: $var_desc"
            echo "Aturan: $var_rules"
            read -p "Masukkan nilai [Default: $var_default]: " user_value
            [ -z "$user_value" ] && user_value=$var_default
            
            env_variables_exports+=("export $var_env=\"$user_value\"")
            echo ""
        done
    fi

    local server_path="$SERVERS_DIR/$server_name"
    mkdir -p "$server_path"
    cd "$server_path" || { echo "Gagal masuk ke direktori server."; return; }
    
    echo -e "\n${YELLOW:-}Memulai instalasi untuk server '$server_name'...${NC:-}"
    
    local install_script_raw install_script_clean
    install_script_raw=$(jq -r '.scripts.installation.script' "$selected_egg_file")
    install_script_clean=$(echo "$install_script_raw" | sed 's/\r$//' | sed 's/\\"/"/g')

    local temp_install_script="/tmp/install_${server_name}.sh"
    
    {
      echo "#!/bin/bash"
      echo "export SERVER_MEMORY=${server_memory::-1}"
      echo "export SERVER_PORT=${SERVER_PORT}"
      for export_cmd in "${env_variables_exports[@]}"; do
        echo "$export_cmd"
      done
      echo
      # Ganti /mnt/server dengan path saat ini
      install_script_clean=$(echo "$install_script_clean" | sed "s|/mnt/server|$(pwd)|g")
      echo "$install_script_clean"
    } > "$temp_install_script"

    chmod +x "$temp_install_script"
    
    echo "Menjalankan skrip instalasi dari egg. Ini mungkin memakan waktu lama..."
    bash "$temp_install_script"
    rm -f "$temp_install_script"

    # Buat panel.conf ringkas
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

    # Pastikan ada server.jar (kalau egg meletakkan nama JAR lain, buat symlink)
    if [ ! -f server.jar ]; then
        jar_guess=$(ls -1 *.jar 2>/dev/null | head -n1 || true)
        if [ -n "$jar_guess" ]; then
            ln -sf "$jar_guess" server.jar
        fi
    fi

    # === Tulis port ke server.properties ===
    write_java_port "server.properties" "$SERVER_PORT"

    # ===== start.sh: Java 21 + Aikar Flags + AUTO SYSTEMD =====
    cat > "start.sh" <<'SH'
#!/usr/bin/env bash
# start.sh — Java 21 + Aikar Flags + AUTO systemd handoff
set -euo pipefail
cd "$(dirname "$0")"

# --- Konfigurasi dasar ---
JAVA_BIN="/usr/lib/jvm/java-21-openjdk-amd64/bin/java"   # ubah jika path Java 21 beda
JAR="server.jar"                                         # pastikan ada; gunakan symlink jika perlu

# --- Pastikan JAR ada ---
if [[ ! -f "$JAR" ]]; then
  guess=$(ls -1 *.jar 2>/dev/null | head -n1 || true)
  [[ -n "${guess:-}" ]] && ln -sf "$guess" "$JAR"
fi
[[ -f "$JAR" ]] || { echo "ERROR: $JAR tidak ditemukan."; exit 1; }

# --- Pastikan Java 21 ---
if [[ ! -x "$JAVA_BIN" ]]; then
  if command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -qE 'version "21\.'; then
    JAVA_BIN="$(command -v java)"
  else
    echo "ERROR: Java 21 tidak ditemukan pada $JAVA_BIN maupun PATH." >&2
    exit 1
  fi
fi

# --- Auto systemd (kecuali dipaksa direct run) ---
SERVICE_NAME="mc-$(basename "$PWD")"
UNIT="/etc/systemd/system/${SERVICE_NAME}.service"

if [[ "${MC_DIRECT:-0}" != "1" ]]; then
  need_sudo=
  if [[ ! -f "$UNIT" ]]; then
    need_sudo=1
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if [[ "${need_sudo:-}" == "1" ]]; then
      # Buat unit
      sudo tee "$UNIT" > /dev/null <<UNIT
[Unit]
Description=Minecraft Server ${SERVICE_NAME}
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=${PWD}
ExecStart=${PWD}/start.sh MC_DIRECT=1
User=root
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT
      sudo systemctl daemon-reload
      sudo systemctl enable "${SERVICE_NAME}.service"
    fi
    # Start/Restart via systemd, lalu keluar
    sudo systemctl restart "${SERVICE_NAME}.service"
    echo "✅ Diserahkan ke systemd: ${SERVICE_NAME}.service"
    echo "Log: journalctl -u ${SERVICE_NAME}.service -f"
    exit 0
  fi
fi

# --- Jalankan langsung (fallback atau MC_DIRECT=1) ---
exec "$JAVA_BIN" \
  -Xms8G -Xmx8G \
  -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch \
  -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \
  -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 \
  -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 \
  -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 \
  -XX:+UseStringDeduplication \
  -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true \
  -jar "$JAR" --nogui
SH
    chmod +x "start.sh"

    # Buat systemd service otomatis (langsung jalan)
    create_systemd_service "$server_name" "$server_path"
    
    # Kembali ke direktori utama panel
    cd "$BASE_DIR"

    echo -e "\n${GREEN:-}✅ Instalasi server '$server_name' berdasarkan egg '$egg_name' selesai!${NC:-}"
    echo -e "${YELLOW:-}Catatan:${NC:-} Port: ${SERVER_PORT}. start.sh auto-systemd; direct run: MC_DIRECT=1 ./start.sh"
    read -p "Tekan [Enter] untuk kembali."
}

# (opsional) panggil createServer jika file ini dijalankan langsung
# createServer