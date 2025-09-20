#!/bin/bash

# Pastikan kita berada di direktori yang benar
cd /root/mc-panel

LOG_DIR="logs"; LOG_FILE="$LOG_DIR/bot.log"; mkdir -p "$LOG_DIR"
exec &> "$LOG_FILE"

echo "=========================================="
echo "   Bot Listener Dinamis Dimulai pada $(date)"
echo "=========================================="

CONFIG_FILE="config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] File konfigurasi utama config.sh tidak ditemukan. Keluar."
    exit 1
fi
source "$CONFIG_FILE"

TELEGRAM_CONF="telegram.conf"; source "$TELEGRAM_CONF"
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then echo "[ERROR] Konfigurasi bot tidak lengkap. Keluar."; exit 1; fi

STATE_FILE="/tmp/bot_plugin_state.json"
echo "{}" > "$STATE_FILE"

# --- FUNGSI-FUNGSI BOT ---
sendMessage() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d chat_id="$1" -d text="$2" > /dev/null
}

sendServerList() {
    local chat_id=$1
    local keyboard_json="{\"inline_keyboard\":["
    
    shopt -s nullglob
    local servers=($SERVERS_DIR/*/)
    shopt -u nullglob

    if [ ${#servers[@]} -eq 0 ]; then
        sendMessage "$chat_id" "Tidak ada server yang ditemukan di folder '$SERVERS_DIR'."
        return
    fi
    
    for server_path in "${servers[@]}"; do
        local server_name=$(basename "$server_path")
        keyboard_json+="[{\"text\":\"$server_name\",\"callback_data\":\"select_server_$server_name\"}],"
    done
    keyboard_json=${keyboard_json%?} 
    keyboard_json+="]}"

    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
         -d chat_id="$chat_id" \
         -d text="Silakan pilih server tujuan untuk plugin:" \
         -d reply_markup="$keyboard_json" > /dev/null
}

# --- LOGIKA UTAMA LISTENER ---
echo "[INFO] Membersihkan antrian pesan lama..."
initial_updates=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getUpdates?timeout=1")
last_update_id=$(echo "$initial_updates" | jq -r ".result[-1].update_id // 0")
if [ "$last_update_id" -ne 0 ]; then last_update_id=$((last_update_id + 1)); fi
echo "[INFO] Listener aktif dan siap menerima perintah."

while true; do
    updates=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getUpdates?offset=$last_update_id&timeout=30")
    
    for row in $(echo "${updates}" | jq -r '.result[] | @base64'); do
        # --- PERBAIKAN DI SINI: Menambahkan tanda kutip ganda pada "${1}" ---
        _jq() { echo ${row} | base64 --decode | jq -r "${1}"; }

        update_type="message"
        [ "$(_jq '.callback_query.id')" != "null" ] && update_type="callback_query"

        current_chat_id=""
        if [ "$update_type" == "message" ]; then
            current_chat_id=$(_jq '.message.chat.id')
        else
            current_chat_id=$(_jq '.callback_query.message.chat.id')
        fi
        
        if [ "$current_chat_id" == "$CHAT_ID" ]; then
            if [ "$update_type" == "message" ] && [ "$(_jq '.message.text')" == "/add" ]; then
                echo "[INFO] Perintah /add diterima dari $current_chat_id. Mengirim daftar server..."
                sendServerList "$current_chat_id"

            elif [ "$update_type" == "callback_query" ] && [[ "$(_jq '.callback_query.data')" == "select_server_"* ]]; then
                selected_server=$(echo $(_jq '.callback_query.data') | sed 's/select_server_//')
                echo "[INFO] Server '$selected_server' dipilih oleh $current_chat_id."
                jq ".[\"$current_chat_id\"] = \"$selected_server\"" "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
                sendMessage "$current_chat_id" "Baik, silakan kirim file plugin (.jar) untuk server '$selected_server'."

            elif [ "$update_type" == "message" ] && [ "$(_jq '.message.document.file_name | endswith(".jar")')" == "true" ]; then
                target_server=$(jq -r ".[\"$current_chat_id\"]" "$STATE_FILE")
                if [ "$target_server" != "null" ] && [ -n "$target_server" ]; then
                    file_id=$(_jq '.message.document.file_id')
                    file_name=$(_jq '.message.document.file_name')
                    echo "[INFO] Menerima file '$file_name' untuk server '$target_server'."
                    
                    plugins_dir="$SERVERS_DIR/$target_server/plugins"
                    mkdir -p "$plugins_dir"
                    
                    file_info=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getFile?file_id=$file_id")
                    file_path=$(echo "$file_info" | jq -r ".result.file_path")

                    if [ -n "$file_path" ]; then
                        wget -q -O "$plugins_dir/$file_name" "https://api.telegram.org/file/bot$BOT_TOKEN/$file_path"
                        sendMessage "$current_chat_id" "✅ Plugin '$file_name' berhasil diinstal ke server '$target_server'."
                    else
                        sendMessage "$current_chat_id" "❌ Gagal mengunduh '$file_name'. Coba lagi."
                    fi
                    jq "del(.[\"$current_chat_id\"])" "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
                fi
            fi
        fi
    done

    last_update_id=$(echo "$updates" | jq -r ".result[-1].update_id // $last_update_id")
    if [ "$last_update_id" -ne 0 ]; then last_update_id=$((last_update_id + 1)); fi
    sleep 1
done
