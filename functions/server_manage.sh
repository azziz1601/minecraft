#!/usr/bin/env bash

SERVERS_DIR="${SERVERS_DIR:-/root/mc-panel/servers}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SELF_DIR/.." && pwd)"
FUNCTIONS_DIR="${FUNCTIONS_DIR:-$BASE_DIR/functions}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
EDITOR_BIN="${EDITOR:-nano}"

# --- Load semua modul di functions/ (agar systemdMenu, dll. tersedia) ---
if [[ -d "$FUNCTIONS_DIR" ]]; then
  shopt -s nullglob
  for f in "$FUNCTIONS_DIR"/*.sh; do
    [[ "$(basename "$f")" == "server_manage.sh" ]] && continue
    # shellcheck source=/dev/null
    source "$f"
  done
  shopt -u nullglob
fi

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
  local server_name="$1"
  local server_path="$SERVERS_DIR/$server_name"
  local memory_conf_path="$server_path/memory.conf"
  
  if [ ! -f "$memory_conf_path" ]; then
    echo -e "${RED}File memory.conf tidak ditemukan!${NC}"
    echo "File ini seharusnya dibuat saat server dibuat. Mungkin ini server lama."
    echo "Anda bisa membuatnya manual: echo '2G' > $memory_conf_path"
    pause
    return
  fi

  local current_ram
  current_ram=$(cat "$memory_conf_path")
  
  clear
  echo -e "${BLUE}--- Pengaturan RAM untuk ${YELLOW}$server_name${BLUE} ---${NC}"
  echo -e "Alokasi saat ini: ${GREEN}${current_ram:-Tidak diatur}${NC}"
  read -rp "Alokasi baru (mis: 4G, 2048M) [Enter batal]: " new_ram
  
  if [ -z "$new_ram" ]; then
    echo -e "${YELLOW}Dibatalkan.${NC}"; sleep 1; return;
  fi

  if ! [[ "$new_ram" =~ ^[0-9]+[MmGg]$ ]]; then
    echo -e "${RED}Format memori salah. Contoh: 1024M atau 2G.${NC}"; sleep 2; return
  fi

  loadingAnimation "Menyimpan perubahan" & local pid=$!
  echo "$new_ram" > "$memory_conf_path"
  sleep 0.5; kill $pid &>/dev/null; tput cnorm
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

changeJvmTemplate(){
  local server_name="$1"
  local server_path="$SERVERS_DIR/$server_name"
  local start_script_path="$server_path/start.sh"
  local graalvm_path="$BASE_DIR/graalvm-community-openjdk-21.0.1+12.1"
  local graalvm_native_executable="$server_name-native" # Assuming this naming convention
  local current_java_home=""
  local graalvm_status=""
  local graalvm_native_status=""
  local temurin_hilltty_status="" # New status variable

  if [ -f "$start_script_path" ]; then
    # Check if JAVA_HOME is set and if it's GraalVM
    current_java_home=$(grep -oP '^export JAVA_HOME="\K[^"]+' "$start_script_path" | head -n1)
    if [[ "$current_java_home" == "$graalvm_path" ]]; then
      # Check if it's running java -jar or the native executable
      if grep -q "java -Xms" "$start_script_path"; then
        graalvm_status=" ${GREEN}🟢${NC}" # GraalVM JDK is active
      elif grep -q "./$graalvm_native_executable" "$start_script_path"; then # Check for native executable
        graalvm_native_status=" ${GREEN}🟢${NC}" # GraalVM Native is active
      fi
    # If JAVA_HOME is not GraalVM, check if it's a native executable without explicit JAVA_HOME
    elif grep -q "^./$graalvm_native_executable" "$start_script_path" && ! grep -q "java -Xms" "$start_script_path"; then
        graalvm_native_status=" ${GREEN}🟢${NC}" # GraalVM Native is active (without explicit JAVA_HOME export)
    else # If JAVA_HOME is not GraalVM, check for Hilltty flags
      if grep -q "-XX:-OmitStackTraceInFastThrow" "$start_script_path" && grep -q "-Dfml.queryResult=confirm" "$start_script_path"; then
        temurin_hilltty_status=" ${GREEN}🟢${NC}"
      fi
    fi
  fi

  while true; do
    clear
    echo -e "${BLUE}--- Ganti JVM Template untuk ${YELLOW}$server_name${BLUE} ---${NC}"
    echo "Pilih template JVM untuk diterapkan."
    echo ""
    echo -e " 1) GraalVM Community Edition (G1GC)$graalvm_status"
    echo -e " 2) GraalVM Native Image (Experimental - Untuk Expert)$graalvm_native_status"
    echo -e " 3) Adoptium (Eclipse Temurin) + Hilltty Flags$temurin_hilltty_status" # New menu item
    echo " 0) Kembali"
    read -rp "Pilih: " choice
    case "$choice" in
      1) installAndApplyGraalVM "$server_name";;
      2) installAndApplyGraalVMNative "$server_name";;
      3) applyTemurinHillttyFlags "$server_name";; # New case
      0) return ;;
      *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
  done
}

installAndApplyGraalVMNative(){
  local server_name="$1"
  local server_path="$SERVERS_DIR/$server_name"
  local start_script_path="$server_path/start.sh"
  local graalvm_path="$BASE_DIR/graalvm-community-openjdk-21.0.1+12.1"
  local native_executable_name="$server_name-native"
  local native_executable_path="$server_path/$native_executable_name"

  clear
  echo -e "${BLUE}--- Template GraalVM Native Image untuk ${YELLOW}$server_name${BLUE} ---${NC}"
  echo -e "${YELLOW}⚠️ Peringatan: Fitur ini masih eksperimental dan belum semua plugin kompatibel.${NC}"
  echo -e "${YELLOW}   Proses build Native Image akan memakan waktu cukup lama (~10-30 menit).${NC}"
  pause

  # 1. Ensure GraalVM JDK is installed
  if [ ! -d "$graalvm_path" ]; then
    echo -e "${RED}GraalVM JDK tidak ditemukan. Harap instal GraalVM Community Edition terlebih dahulu.${NC}"
    pause
    return
  fi

  # 2. Set JAVA_HOME for the build process
  local OLD_JAVA_HOME="${JAVA_HOME:-}" # Use default empty string if unbound
  local OLD_PATH="$PATH"
  export JAVA_HOME="$graalvm_path"
  export PATH="$JAVA_HOME/bin:$PATH"

  # 3. Install native-image component
  if ! run_with_spinner "Menginstal komponen Native Image" gu install native-image; then
    echo -e "${RED}Gagal menginstal komponen Native Image.${NC}"
    export JAVA_HOME="$OLD_JAVA_HOME" # Restore
    export PATH="$OLD_PATH" # Restore
    pause
    return
  fi

  # 4. Get current JAR name
  local current_jar
  current_jar=$(grep -oP -- '-jar \K\S+\.jar' "$start_script_path" | head -n1)
  if [[ -z "$current_jar" ]]; then
    echo -e "${RED}Tidak dapat menemukan nama JAR server di start.sh.${NC}"
    export JAVA_HOME="$OLD_JAVA_HOME" # Restore
    export PATH="$OLD_PATH" # Restore
    pause
    return
  fi

  # 5. Build Native Image
  echo "" # Newline for cleaner output
  if ! run_with_spinner "Membangun Native Image ($current_jar -> $native_executable_name)" \
     native-image \
     --no-fallback \
     -H:+UnlockExperimentalVMOptions \
     -H:+ReportExceptionStackTraces \
     -jar "$server_path/$current_jar" \
     "$native_executable_path"; then
    echo -e "${RED}Gagal membangun Native Image.${NC}"
    export JAVA_HOME="$OLD_JAVA_HOME" # Restore
    export PATH="$OLD_PATH" # Restore
    pause
    return
  fi

  # 6. Update start.sh to run native executable
  local new_content
  read -r -d '' new_content << EOM
#!/usr/bin/env bash
# GraalVM Native Image Flags
# Source: https://www.graalvm.org/latest/reference-manual/native-image/
# Warning: Experimental, not all plugins compatible.

# JAVA_HOME is not strictly needed for native binary, but kept for consistency if other tools rely on it
export JAVA_HOME="$graalvm_path"
export PATH="\$JAVA_HOME/bin:\$PATH"

cd "$(dirname "$0")"
./$native_executable_name
EOM

  echo "$new_content" > "$start_script_path"
  chmod +x "$start_script_path"

  echo -e "${GREEN}Native Image berhasil dibangun dan diterapkan ke start.sh.${NC}"
  
  export JAVA_HOME="$OLD_JAVA_HOME" # Restore
  export PATH="$OLD_PATH" # Restore
  pause
}

applyTemurinHillttyFlags(){
  local server_name="$1"
  local server_path="$SERVERS_DIR/$server_name"
  local start_script_path="$server_path/start.sh"
  local memory_conf_path="$server_path/memory.conf"

  clear
  echo -e "${BLUE}--- Template Adoptium (Eclipse Temurin) + Hilltty Flags untuk ${YELLOW}$server_name${BLUE} ---${NC}"
  echo -e "${YELLOW}Catatan: Template ini mengasumsikan Anda memiliki OpenJDK (seperti Adoptium Temurin) yang terinstal dan dapat diakses melalui perintah 'java' di PATH Anda.${NC}"
  pause

  if [ ! -f "$memory_conf_path" ]; then
    echo -e "${RED}File memory.conf tidak ditemukan!${NC}"
    echo "File ini seharusnya dibuat saat server dibuat. Mungkin ini server lama."
    echo "Anda bisa membuatnya manual: echo '2G' > $memory_conf_path"
    pause
    return
  fi

  # Read RAM allocation from the dedicated config file
  local RAM_ALLOC=$(cat "$memory_conf_path")

  # Get the current jar file from the existing start script
  local jar_value
  jar_value=$(grep -oP -- '-jar \K\S+\.jar' "$start_script_path" | head -n1)
  if [[ -z "$jar_value" ]]; then
    jar_value="server.jar"
  fi
  local current_jar="$jar_value"

  if run_with_spinner "Menerapkan Hilltty Flags" true; then # Use 'true' as a dummy command for spinner
    local new_content
    read -r -d '' new_content << EOM
#!/usr/bin/env bash
# Hilltty's Optimized Flags for Modded Servers
# Source: Reddit r/feedthebeast community

# Read RAM allocation from the dedicated config file
RAM_ALLOC=\$(cat memory.conf)

# JAVA_HOME is not explicitly set, assumes system default 'java' command
# export JAVA_HOME="/path/to/adoptium-temurin-jdk" # Uncomment and modify if specific JDK path is needed
# export PATH="\$JAVA_HOME/bin:\$PATH"

java -Xms\$RAM_ALLOC -Xmx\$RAM_ALLOC \\
-XX:+UseG1GC \\
-XX:+ParallelRefProcEnabled \\
-XX:MaxGCPauseMillis=200 \\
-XX:+UnlockExperimentalVMOptions \\
-XX:+DisableExplicitGC \\
-XX:-OmitStackTraceInFastThrow \\
-XX:+AlwaysPreTouch \\
-XX:G1NewSizePercent=30 \\
-XX:G1MaxNewSizePercent=40 \\
-XX:G1HeapRegionSize=8M \\
-XX:G1ReservePercent=20 \\
-XX:G1HeapWastePercent=5 \\
-XX:G1MixedGCCountTarget=4 \\
-XX:InitiatingHeapOccupancyPercent=15 \\
-XX:G1MixedGCLiveThresholdPercent=90 \\
-XX:G1RSetUpdatingPauseTimePercent=5 \\
-XX:SurvivorRatio=32 \\
-XX:+PerfDisableSharedMem \\
-XX:MaxTenuringThreshold=1 \\
-Dusing.aikars.flags=https://mcflags.emc.gs \\
-Daikars.new.flags=true \\
-Dfml.queryResult=confirm \\
-jar ${current_jar} nogui
EOM

    echo "$new_content" > "$start_script_path"
    chmod +x "$start_script_path"
    echo -e "${GREEN}Template Adoptium (Eclipse Temurin) + Hilltty Flags berhasil diterapkan.${NC}"
  else
    echo -e "${RED}Gagal menerapkan template Adoptium (Eclipse Temurin) + Hilltty Flags.${NC}"
  fi
  
  pause
}

# Fungsi untuk menampilkan spinner saat sebuah perintah sedang dieksekusi
# Penggunaan: run_with_spinner "Deskripsi tugas" perintah_anda arg1 arg2 ...
run_with_spinner() {
    local desc="$1"
    shift
    local cmd=("$@")
    local spin_chars='-\|/'
    local i=0
    local pid=""
    local exit_code=0

    cleanup() {
        printf "\r%s\n" "$(tput el)"
        tput cnorm
    }
    trap cleanup EXIT

    tput civis
    printf "%s... " "$desc"

    # Jalankan perintah di latar belakang, alihkan outputnya
    "${cmd[@]}" > /dev/null 2>&1 &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r%s... %c" "$desc" "${spin_chars:$i:1}"
        sleep 0.1
    done

    wait "$pid"
    exit_code=$?

    printf "\r%s... " "$desc"
    if [ "$exit_code" -eq 0 ]; then
        printf "\033[32mSELESAI\033[0m\n"
    else
        printf "\033[31mGAGAL (Kode Keluar: %d)\033[0m\n" "$exit_code"
    fi

    tput cnorm
    trap - EXIT
    return "$exit_code"
}



installAndApplyGraalVM(){
  local server_name="$1"
  local graalvm_dir="$BASE_DIR/graalvm-community-openjdk-21.0.1+12.1"
  local graalvm_archive="$BASE_DIR/graalvm-community-jdk-21.0.1_linux-x64_bin.tar.gz"
  local graalvm_url="https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-21.0.1/graalvm-community-jdk-21.0.1_linux-x64_bin.tar.gz"

  clear
  echo -e "${BLUE}--- Template GraalVM untuk ${YELLOW}$server_name${BLUE} ---${NC}"

  if [ -d "$graalvm_dir" ]; then
    echo -e "${GREEN}GraalVM Installed${NC}"
  else
    echo -e "${YELLOW}Direktori GraalVM tidak ditemukan. Memulai download...${NC}"
    echo "URL: $graalvm_url"
    
    if ! curl -# -L -o "$graalvm_archive" "$graalvm_url"; then
      echo -e "${RED}Download gagal! Silakan periksa koneksi Anda atau URL.${NC}"
      rm -f "$graalvm_archive"
      pause
      return
    fi
    
    echo ""

    if ! run_with_spinner "Mengekstrak arsip" tar -xzf "$graalvm_archive" -C "$BASE_DIR"; then
        echo -e "${RED}Ekstraksi gagal! Arsip mungkin rusak.${NC}"
        rm -f "$graalvm_archive"
        pause
        return
    fi
    
    rm -f "$graalvm_archive"
  fi

  if run_with_spinner "Menerapkan flag JVM" applyGraalVMFlags "$server_name" "$graalvm_dir"; then
    echo -e "${GREEN}Template JVM berhasil diterapkan.${NC}"
  else
    echo -e "${RED}Gagal menerapkan template JVM.${NC}"
  fi
  
  pause
}

applyGraalVMFlags(){
  local server_name="$1"
  local graalvm_path="$2"
  local server_path="$SERVERS_DIR/$server_name"
  local start_script_path="$server_path/start.sh"
  local memory_conf_path="$server_path/memory.conf"

  if [ ! -f "$memory_conf_path" ]; then
    # Fallback for older servers without memory.conf
    echo "2G" > "$memory_conf_path"
  fi

  # Get the current jar file from the existing start script
  local jar_value
  jar_value=$(grep -oP -- '-jar \K\S+\.jar' "$start_script_path" | head -n1)
  if [[ -z "$jar_value" ]]; then
    jar_value="server.jar"
  fi
  local current_jar="$jar_value"

  local new_content
  read -r -d '' new_content << EOM
#!/usr/bin/env bash
# GraalVM G1GC Flags - Tested by Obydux & Community
# Source: https://github.com/Obydux/Minecraft-GraalVM-Flags

# Read RAM allocation from the dedicated config file
RAM_ALLOC=\$(cat memory.conf)

export JAVA_HOME="$graalvm_path"
export PATH="\$JAVA_HOME/bin:\$PATH"

java -Xms\$RAM_ALLOC -Xmx\$RAM_ALLOC \\
-XX:+UseG1GC \\
-XX:+ParallelRefProcEnabled \\
-XX:MaxGCPauseMillis=200 \\
-XX:+UnlockExperimentalVMOptions \\
-XX:+UnlockDiagnosticVMOptions \\
-XX:+DisableExplicitGC \\
-XX:+AlwaysPreTouch \\
-XX:G1NewSizePercent=30 \\
-XX:G1MaxNewSizePercent=40 \\
-XX:G1HeapRegionSize=8M \\
-XX:G1ReservePercent=20 \\
-XX:G1HeapWastePercent=5 \\
-XX:G1MixedGCCountTarget=4 \\
-XX:InitiatingHeapOccupancyPercent=15 \\
-XX:G1MixedGCLiveThresholdPercent=90 \\
-XX:G1RSetUpdatingPauseTimePercent=5 \\
-XX:SurvivorRatio=32 \\
-XX:+PerfDisableSharedMem \\
-XX:MaxTenuringThreshold=1 \\
-XX:G1SATBBufferEnqueueingThresholdPercent=30 \\
-XX:G1ConcMarkStepDurationMillis=5 \\
-XX:G1ConcRSHotCardLimit=16 \\
-XX:G1RSetUpdatingPauseTimePercent=5 \\
-XX:GCTimeRatio=99 \\
-jar ${current_jar} nogui
EOM

  echo "$new_content" > "$start_script_path"
  chmod +x "$start_script_path"
}

customJvmEditor(){
  local server_name="$1" server_path="$SERVERS_DIR/$server_name" start_script_path="$server_path/start.sh"
  [ -f "$start_script_path" ] || { echo -e "${RED}File start.sh tidak ditemukan!${NC}"; sleep 2; return; }
  clear
  echo -e "${BLUE}--- Editor JVM Kustom untuk ${YELLOW}$server_name${BLUE} ---${NC}"
  echo "Anda akan membuka file start.sh."
  echo "Anda dapat mengedit argumen Java (flags) secara manual."
  echo "Contoh: -Xmx4G -Xms4G -XX:+UseG1GC ..."
  pause
  "$EDITOR_BIN" "$start_script_path"
  echo -e "${GREEN}File start.sh telah disimpan.${NC}"
  sleep 1
}

systemConfigurationMenu(){
  local server_name="$1" choice
  while true; do
    clear
    echo -e "${BLUE}--- System Configuration: ${YELLOW}${server_name}${BLUE} ---${NC}"
    echo " 1) Ram Allocation"
    echo " 2) Ganti JVM Template"
    echo " 3) Custom JVM"
    echo " 0) Kembali"
    read -rp "Pilih: " choice
    case "$choice" in
      1) ramAllocationMenu "$server_name" ;;
      2) changeJvmTemplate "$server_name" ;;
      3) customJvmEditor "$server_name" ;;
      0) return ;;
      *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
  done
}

whitelistMenu(){
  local server_name="$1"
  local server_path="$SERVERS_DIR/$server_name"
  local choice target

  while true; do
    clear
    echo -e "${BLUE}--- Manajemen Whitelist: ${YELLOW}${server_name}${BLUE} ---${NC}"
    
    local whitelist_status="Tidak diketahui"
    if [ -f "$server_path/server.properties" ]; then
      if grep -q "white-list=true" "$server_path/server.properties"; then
        whitelist_status="${GREEN}AKTIF${NC}"
      elif grep -q "white-list=false" "$server_path/server.properties"; then
        whitelist_status="${RED}NON-AKTIF${NC}"
      fi
    fi
    echo -e "Status saat ini (dari server.properties): $whitelist_status"
    
    echo ""
    echo " 1) Aktifkan Whitelist"
    echo " 2) Non-aktifkan Whitelist"
    echo " 3) Tampilkan Daftar Pemain di Whitelist"
    echo " 4) Tambah Pemain ke Whitelist"
    echo " 5) Hapus Pemain dari Whitelist"
    echo " 6) Reload Whitelist"
    echo " 0) Kembali"
    read -rp "Pilih: " choice
    case "$choice" in
      1) consoleCmd "$server_name" "whitelist on" && echo -e "${GREEN}Perintah untuk mengaktifkan whitelist telah dikirim.${NC}"; pause ;;
      2) consoleCmd "$server_name" "whitelist off" && echo -e "${GREEN}Perintah untuk menon-aktifkan whitelist telah dikirim.${NC}"; pause ;;
      3) 
         consoleCmd "$server_name" "whitelist list" >/dev/null
         sleep 1
         echo "Pemain di whitelist (menunggu log server...):"
         lastLogMatch "$server_path" "whitelisted players:" | sed 's/.*: //; s/, /\n/g'
         pause
         ;;
      4) read -rp "Tambah pemain: " target; [ -z "$target" ] && continue
         consoleCmd "$server_name" "whitelist add $target" && echo -e "${GREEN}Perintah untuk menambahkan ${target} telah dikirim.${NC}"; pause ;;
      5) read -rp "Hapus pemain: " target; [ -z "$target" ] && continue
         consoleCmd "$server_name" "whitelist remove $target" && echo -e "${GREEN}Perintah untuk menghapus ${target} telah dikirim.${NC}"; pause ;;
      6) consoleCmd "$server_name" "whitelist reload" && echo -e "${GREEN}Perintah untuk me-reload whitelist telah dikirim.${NC}"; pause ;;
      0) return ;;
      *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
  done
}

serverActionMenu(){
  local server_path="$1"
  local server_name; server_name="$(basename "$server_path")"
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
    echo " 8. System Configuration"
    echo " 9. Manajemen Whitelist"
    echo "10. Set Auto Restart"
    echo "11. Website Upload Plugin"
    echo "12. Systemd Autostart"
    echo "13. Download Plugin via Link"
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
        if ! tmux has-session -t "$server_name" 2>/dev/null; then
          echo -e "${RED}Server tidak berjalan.${NC}"; sleep 1
        else
          loadingAnimation "Mengirim perintah stop (graceful shutdown)" & local pid=$!
          tmux send-keys -t "$server_name" "stop" C-m
          for i in {1..30}; do
            ! tmux has-session -t "$server_name" 2>/dev/null && break
            sleep 1
          done
          kill $pid &>/dev/null; tput cnorm
          if tmux has-session -t "$server_name" 2>/dev/null; then
            echo -e "\r${YELLOW}Graceful shutdown gagal (timeout). Memaksa penghentian...${NC}"
            loadingAnimation "Menghentikan paksa (kill session)" & pid=$!
            tmux kill-session -t "$server_name" &>/dev/null
            sleep 1
            kill $pid &>/dev/null; tput cnorm
            echo -e "\r${GREEN}Server dihentikan paksa.${NC}"; sleep 1
          else
            echo -e "\r${GREEN}Server dihentikan dengan sukses.${NC}"; sleep 1
          fi
        fi
        ;;
      3)
        echo "Memulai proses restart..."
        # --- Bagian Stop yang Ditingkatkan ---
        if tmux has-session -t "$server_name" 2>/dev/null; then
          loadingAnimation "Mengirim perintah stop (graceful shutdown)" & local pid=$!
          tmux send-keys -t "$server_name" "stop" C-m
          for i in {1..30}; do ! tmux has-session -t "$server_name" 2>/dev/null && break; sleep 1; done
          kill $pid &>/dev/null; tput cnorm
          if tmux has-session -t "$server_name" 2>/dev/null; then
            echo -e "\r${YELLOW}Graceful shutdown gagal (timeout). Memaksa penghentian...${NC}"
            loadingAnimation "Menghentikan paksa (kill session)" & pid=$!
            tmux kill-session -t "$server_name" &>/dev/null; sleep 1
            kill $pid &>/dev/null; tput cnorm
            echo -e "\r${GREEN}Server dihentikan paksa.${NC}"
          else
            echo -e "\r${GREEN}Server dihentikan dengan sukses.${NC}"
          fi
        else
          echo -e "${YELLOW}Server sudah berhenti, lanjut memulai...${NC}"
        fi
        
        # --- Bagian Start ---
        echo "Memulai server..."
        if ! tmux has-session -t "$server_name" 2>/dev/null; then
          loadingAnimation "Memulai server" & local pid=$!
          tmux new-session -d -s "$server_name" "cd '$server_path' && ./start.sh"
          sleep 2; kill $pid &>/dev/null; tput cnorm
          echo -e "\r${GREEN}Server di-restart/dimulai.${NC}"; sleep 1
        else
          echo -e "${YELLOW}Gagal memulai, server sepertinya sudah berjalan.${NC}"; sleep 1
        fi
        ;;
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
      8) systemConfigurationMenu "$server_name" ;;
      9) whitelistMenu "$server_name" ;;
      10) autoRestartMenu "$server_name" ;;
      11) pluginWebMenu "$server_name" ;;
      12) 
  if declare -F systemdMenu >/dev/null; then
    systemdMenu "$server_name"
  else
    echo "Module systemd_manager.sh belum dimuat."
    read -rp "Tekan [Enter]..."
  fi
  ;;
      13) downloadPluginFromLink "$server_name" ;;
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
    serverActionMenu "$selected_server_path"
  elif [ "$server_choice" = "0" ]; then
    return
  else
    echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1
  fi
}

# if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
#   manageServers
# fi
