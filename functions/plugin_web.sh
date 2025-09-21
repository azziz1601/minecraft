#!/usr/bin/env bash

SERVERS_DIR="${SERVERS_DIR:-/root/mc-panel/servers}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_FILE="$SELF_DIR/plugin_web.py"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
color() { printf "%b%s%b\n" "$1" "$2" "$NC"; }
need() { command -v "$1" >/dev/null 2>&1; }

pub_ip() {
  ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' \
  || hostname -I 2>/dev/null | awk '{print $1}'
}

port_free() {
  local p="$1"
  ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$p\$"
}

pick_port() {
  local start="${1:-8088}" end="${2:-8188}" p
  for ((p=start; p<=end; p++)); do
    if port_free "$p"; then echo "$p"; return 0; fi
  done
  echo ""; return 1
}

ensure_python() {
  if need python3; then return 0; fi
  if need apt-get; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y python3 >/dev/null 2>&1 || true
  fi
  need python3 || { color "$RED" "python3 tidak tersedia"; exit 1; }
}

ensure_pyfile() {
  [[ -f "$PY_FILE" ]] || { color "$RED" "plugin_web.py tidak ditemukan di $PY_FILE"; exit 1; }
}

ufw_open() {
  local port="$1"
  if need ufw; then
    local status; status="$(ufw status 2>/dev/null | head -n1 || true)"
    ufw allow "$port"/tcp >/dev/null 2>&1 || true
    if echo "$status" | grep -qi "inactive"; then
      color "$YELLOW" "ufw belum aktif; rule ditambahkan (ufw tidak diaktifkan otomatis)."
    else
      color "$GREEN" "ufw: port $port diizinkan."
    fi
  fi
}

start() {
  local name="${1:-}"; [[ -z "$name" ]] && { color "$RED" "Usage: $0 start <server_name>"; exit 1; }
  local server_path="$SERVERS_DIR/$name"
  [[ -d "$server_path" ]] || { color "$RED" "Server tidak ditemukan: $server_path"; exit 1; }

  ensure_python
  ensure_pyfile
  mkdir -p "$server_path/logs" "$server_path/plugins"

  if tmux has-session -t "plugweb-$name" 2>/dev/null; then
    color "$YELLOW" "Website sudah berjalan (session: plugweb-$name)."
    url "$name"; exit 0
  fi

  local ip_pub port
  ip_pub="$(pub_ip)"; [[ -z "$ip_pub" ]] && ip_pub="127.0.0.1"
  port="$(pick_port 8088 8188)"; [[ -z "$port" ]] && { color "$RED" "Tidak menemukan port bebas 8088-8188"; exit 1; }

  ufw_open "$port"

  echo "$ip_pub" > "$server_path/logs/plugweb.ip"
  echo "$port"   > "$server_path/logs/plugweb.port"
  echo "http://${ip_pub}:${port}/" > "$server_path/logs/plugweb.url"

  tmux new-session -d -s "plugweb-$name" \
    "cd '$server_path' && MC_SERVER_NAME='$name' MC_SERVER_DIR='$server_path' MC_WEB_HOST='0.0.0.0' MC_WEB_PORT='$port' python3 '$PY_FILE' >> '$server_path/logs/plugweb.log' 2>&1"

  color "$GREEN" "Website dimulai (plugweb-$name)"
  echo "URL: http://${ip_pub}:${port}/"
}

stop() {
  local name="${1:-}"; [[ -z "$name" ]] && { color "$RED" "Usage: $0 stop <server_name>"; exit 1; }
  if tmux has-session -t "plugweb-$name" 2>/dev/null; then
    tmux kill-session -t "plugweb-$name"
    color "$GREEN" "Website dihentikan (plugweb-$name)."
  else
    color "$YELLOW" "Website tidak berjalan."
  fi
}

status() {
  local name="${1:-}"; [[ -z "$name" ]] && { color "$RED" "Usage: $0 status <server_name>"; exit 1; }
  if tmux has-session -t "plugweb-$name" 2>/dev/null; then
    color "$GREEN" "AKTIF"
  else
    color "$RED" "NON-AKTIF"
  fi
}

url() {
  local name="${1:-}"; [[ -z "$name" ]] && { color "$RED" "Usage: $0 url <server_name>"; exit 1; }
  local server_path="$SERVERS_DIR/$name"
  if [[ -f "$server_path/logs/plugweb.url" ]]; then
    cat "$server_path/logs/plugweb.url"; return
  fi
  local ip port
  ip="$( [[ -f "$server_path/logs/plugweb.ip" ]] && cat "$server_path/logs/plugweb.ip" || pub_ip )"
  port="$( [[ -f "$server_path/logs/plugweb.port" ]] && cat "$server_path/logs/plugweb.port" || true )"
  if [[ -n "${ip:-}" && -n "${port:-}" ]]; then
    echo "http://${ip}:${port}/"
  else
    echo "URL belum terdeteksi. Cek: $server_path/logs/plugweb.log"
  fi
}

# HANYA eksekusi CLI jika file ini dijalankan langsung (bukan di-source)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  case "${1:-}" in
    start) shift; start "${1:-}";;
    stop) shift; stop "${1:-}";;
    status) shift; status "${1:-}";;
    url) shift; url "${1:-}";;
    *)
      echo "Usage:"
      echo "  $0 start <server_name>"
      echo "  $0 stop <server_name>"
      echo "  $0 status <server_name>"
      echo "  $0 url <server_name>"
      exit 1
    ;;
  esac
fi