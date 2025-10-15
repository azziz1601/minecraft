#!/usr/bin/env bash

set -euo pipefail

# ============================ KONFIG =============================
PANEL_DIR="${PANEL_DIR:-/root/mc-panel}"
REPO_URL="${REPO_URL:-https://github.com/azziz1601/minecraft.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
TMP_CLONE_DIR="/tmp/mc-panel-repo.$$"

# Paket dasar + dependensi ports.sh
PKGS_BASE=(bash coreutils findutils procps iproute2 net-tools tmux curl wget jq unzip zip tar git cron mc vnstat lsof gawk grep sed util-linux ncurses-bin)

# Java (Oracle)
ORACLE_DEBIAN_DEB_URL="${ORACLE_DEBIAN_DEB_URL:-https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb}"
ORACLE_TARGZ_AARCH64_URL="${ORACLE_TARGZ_AARCH64_URL:-https://download.oracle.com/java/21/latest/jdk-21_linux-aarch64_bin.tar.gz}"
JAVA_INSTALL_DIR="/opt/java"
PROFILE_SNIPPET="/etc/profile.d/java21.sh"

# gotop/btop
GOTOP_WRAPPER="/usr/local/bin/gotop"

# Profile script untuk alias & autostart panel
PANEL_PROFILE_SNIPPET="/etc/profile.d/mc-panel.sh"

# Log file
LOG_FILE="/var/log/mc-panel-setup.log"
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

# ============================ UTIL ===============================
trap 'tput cnorm 2>/dev/null || true' EXIT
log()  { echo "[SETUP] $*" >>"$LOG_FILE"; }
ok()   { printf "\r\033[1;32m[ OK ]\033[0m %s\n" "$1"; }
errm() { printf "\r\033[1;31m[ERR ]\033[0m %s\n" "$1"; }
warn() { printf "\r\033[1;33m[WARN]\033[0m %s\n" "$1"; }
need() { command -v "$1" >/dev/null 2>&1; }

spinner_run() {
  local msg="$1"; shift
  local cmd=( "$@" )
  local sp='-\|/'; local i=0
  tput civis 2>/dev/null || true
  printf "\033[1;36m[....]\033[0m %s " "$msg"
  "${cmd[@]}" >>"$LOG_FILE" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf "\b%s" "${sp:$i:1}"
    sleep 0.12
  done
  if wait "$pid"; then
    ok "$msg"
  else
    errm "$msg (lihat $LOG_FILE)"
    exit 1
  fi
  tput cnorm 2>/dev/null || true
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    errm "Jalankan sebagai root (sudo -i)."
    exit 1
  fi
}

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"; OS_VER="${VERSION_ID:-}"; OS_NAME="${PRETTY_NAME:-}"
  else
    OS_ID="unknown"; OS_VER=""; OS_NAME="Unknown"
  fi
  ARCH="$(uname -m)"
  log "OS: ${OS_NAME} | ID=${OS_ID} VER=${OS_VER} | ARCH=${ARCH}"
}

apt_update() {
  spinner_run "Memperbarui indeks paket" bash -c "apt-get update -y"
}

install_pkgs_base() {
  spinner_run "Menginstal paket dasar & dependensi" bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${PKGS_BASE[*]}"
}

install_java_smart() {
  if [[ "${OS_ID:-}" == "debian" ]]; then
    spinner_run "Mengunduh JDK 21 (.deb) untuk Debian" bash -c "curl -fsSL -o /tmp/jdk21.deb '$ORACLE_DEBIAN_DEB_URL'"
    spinner_run "Memasang JDK 21 (.deb) Oracle" bash -c "apt-get install -y /tmp/jdk21.deb && rm -f /tmp/jdk21.deb"
  else
    case "$ARCH" in
      x86_64|amd64)
        spinner_run "Mengunduh JDK 21 (.deb) untuk Ubuntu (amd64)" bash -c "curl -fsSL -o /tmp/jdk21.deb '$ORACLE_DEBIAN_DEB_URL'"
        spinner_run "Memasang JDK 21 (.deb) Oracle" bash -c "apt-get install -y /tmp/jdk21.deb && rm -f /tmp/jdk21.deb"
        ;;
      aarch64|arm64)
        spinner_run "Mengunduh JDK 21 (tar.gz) aarch64" bash -c "curl -fsSL -o /tmp/jdk21.tar.gz '$ORACLE_TARGZ_AARCH64_URL'"
        spinner_run "Ekstrak JDK 21 ke $JAVA_INSTALL_DIR" bash -c "mkdir -p '$JAVA_INSTALL_DIR' && tar -xzf /tmp/jdk21.tar.gz -C '$JAVA_INSTALL_DIR' && rm -f /tmp/jdk21.tar.gz"
        local jdk_dir
        jdk_dir="$(find "$JAVA_INSTALL_DIR" -maxdepth 1 -type d -name 'jdk-21*' | head -n1 || true)"
        [[ -z "$jdk_dir" ]] && { errm "Gagal menemukan folder hasil ekstrak JDK."; exit 1; }
        echo "export JAVA_HOME=\"$jdk_dir\"
export PATH=\"\$JAVA_HOME/bin:\$PATH\"" > "$PROFILE_SNIPPET"
        spinner_run "Menyetel JAVA_HOME & symlink biner" bash -c "mkdir -p /usr/local/bin && ln -sf '$jdk_dir/bin/java' /usr/local/bin/java && ln -sf '$jdk_dir/bin/javac' /usr/local/bin/javac"
        # shellcheck disable=SC1090
        source "$PROFILE_SNIPPET" 2>>"$LOG_FILE" || true
        ;;
      *)
        errm "Arsitektur '$ARCH' belum di-handle. Berikan URL JDK 21 yang sesuai."
        exit 1
        ;;
    esac
  fi
}

verify_java() {
  spinner_run "Verifikasi Java 21" bash -c "java -version 2>&1 | grep -q '\"21\.'"
}

install_gotop_smart() {
  # Pakai SNAP sesuai permintaan
  spinner_run "Menginstal snapd" bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends snapd"
  spinner_run "Mengaktifkan snapd" bash -c "systemctl enable --now snapd.socket && systemctl start snapd.socket || true"
  # Tunggu socket siap sebentar
  spinner_run "Menyiapkan lingkungan snap" bash -c "sleep 2"
  if ( spinner_run "Menginstal gotop (snap)" bash -c "snap install gotop" ); then
    return 0
  fi
  # Fallback: btop + wrapper 'gotop'
  warn "Install gotop via snap gagal. Menggunakan btop sebagai fallback."
  spinner_run "Menginstal btop (fallback)" bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends btop || true"
  if ! need btop; then
    warn "btop tidak tersedia. Menu monitor akan terbatas."
    return 0
  fi
  spinner_run "Membuat wrapper gotop -> btop" bash -c "
cat > '$GOTOP_WRAPPER' <<'WRAP'
#!/usr/bin/env bash
exec btop \"\$@\"
WRAP
chmod +x '$GOTOP_WRAPPER'
"
}

enable_services() {
  spinner_run "Mengaktifkan layanan vnstat" bash -c "systemctl enable --now vnstat"
  spinner_run "Mengaktifkan layanan cron"   bash -c "systemctl enable --now cron"
}

prepare_panel_dir() {
  spinner_run "Menyusun direktori panel ($PANEL_DIR)" bash -c "
    mkdir -p '$PANEL_DIR'/servers '$PANEL_DIR'/functions '$PANEL_DIR'/eggs
  "
}

clone_repo() {
  spinner_run "Mengambil kode panel dari GitHub ($REPO_BRANCH)" bash -c "
    rm -rf '$TMP_CLONE_DIR' &&
    git clone --depth 1 --branch '$REPO_BRANCH' '$REPO_URL' '$TMP_CLONE_DIR'
  "
}

deploy_repo() {
  spinner_run "Menyalin skrip panel ke $PANEL_DIR" bash -c "
    shopt -s dotglob &&
    cp -r '$TMP_CLONE_DIR'/* '$PANEL_DIR'/
  "
  spinner_run "Mengatur izin eksekusi skrip" bash -c "
    chmod +x '$PANEL_DIR'/*.sh 2>/dev/null || true
    chmod +x '$PANEL_DIR'/functions/*.sh 2>/dev/null || true
    dos2unix /root/mc-panel/functions/plugin_web.sh
    dos2unix /root/mc-panel/functions/plugin_web.py
  "
  spinner_run "Membersihkan berkas sementara" bash -c "rm -rf '$TMP_CLONE_DIR'"
}

install_alias_and_autostart() {
  spinner_run "Menyiapkan alias 'menu' & autostart panel" bash -c "
cat > '$PANEL_PROFILE_SNIPPET' <<'EOF'
# mc-panel profile
export MCPANEL_DIR=\"$PANEL_DIR\"
alias menu='cd \"$PANEL_DIR\" && ./main.sh'

# Auto start panel saat login interaktif oleh root (bisa dimatikan dengan: export MCPANEL_AUTOSTART=0)
if [ -z \"\$MCPANEL_AUTOSTART\" ] || [ \"\$MCPANEL_AUTOSTART\" = \"1\" ]; then
  if [ \"\$USER\" = \"root\" ] && [ -t 0 ] && [ -t 1 ]; then
    case \"\$-\" in
      *i*)
        if [ -x \"\$MCPANEL_DIR/main.sh\" ] && [ -z \"\$MCPANEL_INVOKED\" ]; then
          export MCPANEL_INVOKED=1
          cd \"\$MCPANEL_DIR\"
          ./main.sh
          unset MCPANEL_INVOKED
        fi
      ;;
    esac
  fi
fi
EOF
chmod 0644 '$PANEL_PROFILE_SNIPPET'
"
}

post_info() {
  echo
  printf "\033[1;34m═══════════════════════════════════════════════════════\033[0m\n"
  printf "\033[1;34m                   SETUP SELESAI \033[0m\n"
  printf "\033[1;34m═══════════════════════════════════════════════════════\033[0m\n"
  echo "• Panel   : $PANEL_DIR"
  echo "• Log     : $LOG_FILE"
  echo "• Java    : $(java -version 2>&1 | sed -n '1p')"
  echo "• Alias   : ketik \`menu\` untuk membuka panel"
  echo "• AutoRun : panel akan otomatis terbuka saat login."
  echo
  echo -e "Jalankan panel sekarang:"
  echo -e "  \033[1;33mcd $PANEL_DIR && ./main.sh\033[0m"
  echo -e "Nonaktifkan autostart sementara (sesi ini): \033[1;33mexport MCPANEL_AUTOSTART=0\033[0m"
  echo
}

write_systemd_unit() {
  log "Menulis /etc/systemd/system/minecraft@.service"
  cat > /etc/systemd/system/minecraft@.service <<'UNIT'
# /etc/systemd/system/minecraft@.service
[Unit]
Description=Minecraft Server (%i) via tmux
Wants=network-online.target
After=network-online.target

[Service]
Type=forking
GuessMainPID=no
RemainAfterExit=yes

# -- SESUAIKAN JIKA PERLU --
User=root
Environment=PANEL_DIR=/root/mc-panel
Environment=SESSION=%i
Environment=PATH=/usr/local/bin:/usr/bin:/bin
# ---------------------------

WorkingDirectory=/

ExecStartPre=/usr/bin/test -x /usr/bin/tmux
ExecStartPre=/usr/bin/test -d ${PANEL_DIR}/servers/%i
ExecStartPre=/usr/bin/test -x ${PANEL_DIR}/servers/%i/start.sh

ExecStart=/bin/bash -lc '\
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then \
    tmux new-session -d -s "$SESSION" "cd \"${PANEL_DIR}/servers/${SESSION}\" && ./start.sh"; \
  fi \
'

ExecStartPost=/bin/bash -lc '\
  for i in {1..15}; do \
    tmux has-session -t "$SESSION" 2>/dev/null && exit 0; \
    sleep 1; \
  done; \
  echo "ERROR: tmux session $SESSION tidak ditemukan (start.sh mungkin error)"; \
  exit 1 \
'

ExecStop=/bin/bash -lc '\
  if tmux has-session -t "$SESSION" 2>/dev/null; then \
    tmux send-keys -t "$SESSION" "say [Panel] Server stopping in 5s..." C-m; \
    sleep 5; \
    tmux send-keys -t "$SESSION" "stop" C-m; \
    for i in {1..60}; do tmux has-session -t "$SESSION" 2>/dev/null || break; sleep 1; done; \
    tmux has-session -t "$SESSION" 2>/dev/null && tmux kill-session -t "$SESSION"; \
  fi; \
  true \
'

Restart=on-failure
RestartSec=10
KillMode=process
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
UNIT

  chmod 0644 /etc/systemd/system/minecraft@.service
  systemctl daemon-reload
}

# ============================ MAIN ================================
require_root
detect_os
apt_update
install_pkgs_base
install_java_smart
verify_java
install_gotop_smart
enable_services
prepare_panel_dir
clone_repo
deploy_repo
install_alias_and_autostart
write_systemd_unit
post_info





