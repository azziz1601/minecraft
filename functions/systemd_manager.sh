#!/usr/bin/env bash
set -euo pipefail

# ==== Konfigurasi dasar ====
PANEL_DIR="${PANEL_DIR:-/root/mc-panel}"

unit_template_path="/etc/systemd/system/minecraft@.service"

ensureSystemdTemplate() {
  if [ ! -f "$unit_template_path" ]; then
    echo -e "\n[ERR] Unit template $unit_template_path belum ada."
    echo "Salin file template ke $unit_template_path lalu jalankan: systemctl daemon-reload"
    read -rp "Tekan [Enter] untuk kembali..."
    return 1
  fi
  return 0
}

# ---- Helpers ----
sysd_name() {  # nama service untuk server tertentu
  local server="$1"
  echo "minecraft@${server}.service"
}

enableAutostart() {  # enable + start via systemd
  local server="$1"
  ensureSystemdTemplate || return
  if [ ! -x "$PANEL_DIR/servers/$server/start.sh" ]; then
    echo "[ERR] $PANEL_DIR/servers/$server/start.sh tidak ditemukan atau tidak executable."
    read -rp "Tekan [Enter]..." ; return
  fi
  systemctl daemon-reload
  systemctl enable "$(sysd_name "$server")"
  systemctl start  "$(sysd_name "$server")"
  echo "✅ Autostart ENABLED & server dijalankan via systemd."
  read -rp "Tekan [Enter]..."
}

disableAutostart() { # disable + stop via systemd
  local server="$1"
  ensureSystemdTemplate || return
  systemctl disable "$(sysd_name "$server")" || true
  systemctl stop    "$(sysd_name "$server")" || true
  echo "🛑 Autostart DISABLED & server dihentikan (jika jalan)."
  read -rp "Tekan [Enter]..."
}

statusAutostart() {
  local server="$1"
  ensureSystemdTemplate || return
  echo "=== systemctl status $(sysd_name "$server") ==="
  systemctl status "$(sysd_name "$server")" --no-pager || true
  echo
  echo "=== tmux sessions ==="
  tmux ls 2>/dev/null || echo "(no tmux session)"
  echo
  read -rp "Tekan [Enter]..."
}

restartService() {
  local server="$1"
  ensureSystemdTemplate || return
  systemctl restart "$(sysd_name "$server")"
  echo "🔁 Server di-restart via systemd."
  read -rp "Tekan [Enter]..."
}

# ---- Menu per server ----
systemdMenu() {
  local server_name="$1"
  while true; do
    clear
    echo "=== Systemd Autostart untuk server: $server_name ==="
    echo "1) Enable & Start"
    echo "2) Disable & Stop"
    echo "3) Status"
    echo "4) Restart"
    echo "0) Kembali"
    read -rp "> " c
    case "$c" in
      1) enableAutostart "$server_name" ;;
      2) disableAutostart "$server_name" ;;
      3) statusAutostart "$server_name" ;;
      4) restartService "$server_name" ;;
      0) return ;;
      *) echo "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}
