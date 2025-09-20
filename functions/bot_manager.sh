#!/bin/bash

TELEGRAM_CONF="/root/mc-panel/telegram.conf"
BOT_LOG_FILE="/root/mc-panel/logs/bot.log"
LISTENER_SESSION_NAME="BotListener"

function setupBotApi() {
    clear
    echo -e "${BLUE}--- Setup Konfigurasi Bot Telegram ---${NC}"
    [ -f "$TELEGRAM_CONF" ] && source "$TELEGRAM_CONF"

    read -p "Masukkan BOT TOKEN [sebelumnya: $BOT_TOKEN]: " bot_token
    read -p "Masukkan CHAT ID Admin [sebelumnya: $CHAT_ID]: " chat_id

    [ -z "$bot_token" ] && bot_token=$BOT_TOKEN
    [ -z "$chat_id" ] && chat_id=$CHAT_ID

    echo "BOT_TOKEN=\"$bot_token\"" > "$TELEGRAM_CONF"
    echo "CHAT_ID=\"$chat_id\"" >> "$TELEGRAM_CONF"
    
    echo -e "\n${GREEN}✅ Konfigurasi berhasil disimpan!${NC}"
    read -p "Tekan [Enter] untuk kembali."
}

function sendTestMessage() {
    if [ ! -f "$TELEGRAM_CONF" ]; then echo -e "${RED}Konfigurasi bot belum diatur.${NC}"; sleep 2; return; fi
    source "$TELEGRAM_CONF"
    echo "Mengirim pesan tes ke $CHAT_ID..."
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d chat_id="$CHAT_ID" -d text="✅ Pesan tes dari panel VPS. Konfigurasi berhasil!" > /dev/null
    echo "Pesan terkirim."; sleep 2
}

function onOffBotMenu() {
    while true; do
        clear
        echo -e "${BLUE}--- Status Bot Listener ---${NC}"
        if tmux has-session -t $LISTENER_SESSION_NAME 2>/dev/null; then
            echo -e "Status: ${GREEN}AKTIF (Berjalan di latar belakang)${NC}"
            echo "--------------------------------"; echo "1. Matikan Bot Listener"; echo "0. Kembali"
            read -p "Pilihan: " choice
            if [ "$choice" == "1" ]; then echo -e "${YELLOW}Mematikan listener...${NC}"; tmux kill-session -t $LISTENER_SESSION_NAME; sleep 1;
            elif [ "$choice" == "0" ]; then return; fi
        else
            echo -e "Status: ${RED}TIDAK AKTIF${NC}"
            echo "--------------------------------"; echo "1. Aktifkan Bot Listener"; echo "0. Kembali"
            read -p "Pilihan: " choice
            if [ "$choice" == "1" ]; then
                if [ ! -f "$TELEGRAM_CONF" ]; then echo -e "${RED}Konfigurasi bot belum diatur.${NC}"; sleep 2; continue; fi
                echo -e "${YELLOW}Mengaktifkan listener... Pastikan file bot_listener.sh sudah chmod +x${NC}"
                tmux new-session -d -s $LISTENER_SESSION_NAME "bash /root/mc-panel/bot_listener.sh"; sleep 1
            elif [ "$choice" == "0" ]; then return; fi
        fi
    done
}

function botMenu() {
    while true; do
        clear
        echo -e "${BLUE}======= MENU BOT TELEGRAM =======${NC}"
        echo "1. Setup Bot API"
        echo "2. Aktifkan / Matikan Bot Listener"
        echo "3. Lihat Log Bot"
        echo "4. Kirim Pesan Tes"
        echo "0. Kembali ke Menu Utama"
        echo "---------------------------------"
        read -p "Pilihan: " choice
        case $choice in
            1) setupBotApi ;; 2) onOffBotMenu ;;
            3) 
               clear; echo -e "${YELLOW}Menampilkan log bot... Tekan CTRL+C untuk keluar.${NC}\n"
               [ ! -f "$BOT_LOG_FILE" ] && echo "File log belum ada." || tail -f "$BOT_LOG_FILE"
               read -p "Tekan [Enter] untuk kembali."; ;;
            4) sendTestMessage ;; 0) return ;;
            *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}
