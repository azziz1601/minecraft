#!/bin/bash

# File untuk melacak ban berdurasi
BANS_LOG="/root/mc-panel/logs/timed_bans.log"
mkdir -p "$(dirname "$BANS_LOG")" && touch "$BANS_LOG"

# Fungsi pembantu untuk mengirim perintah ke konsol server
function sendCmd() {
    local server_name=$1
    local cmd=$2
    tmux send-keys -t "$server_name" "$cmd" C-m
}

# Fungsi untuk ban berdurasi
function timedBanPlayer() {
    local server_name=$1
    clear
    echo -e "${BLUE}--- Ban Pemain dengan Durasi ---${NC}"
    read -p "Masukkan nama pemain: " player_name
    if [ -z "$player_name" ]; then echo "Dibatalkan."; sleep 1; return; fi

    echo "Pilih satuan waktu:"
    echo "1. Jam (1-24)"
    echo "2. Hari (1-30)"
    read -p "Pilihan [1-2]: " unit_choice

    local duration; local unit_text
    case $unit_choice in
        1) 
            read -p "Masukkan durasi (1-24 jam): " duration
            if ! [[ "$duration" =~ ^[0-9]+$ ]] || [ "$duration" -lt 1 ] || [ "$duration" -gt 24 ]; then
                echo -e "${RED}Durasi tidak valid.${NC}"; sleep 2; return
            fi
            unit_text="hours"
            ;;
        2)
            read -p "Masukkan durasi (1-30 hari): " duration
            if ! [[ "$duration" =~ ^[0-9]+$ ]] || [ "$duration" -lt 1 ] || [ "$duration" -gt 30 ]; then
                echo -e "${RED}Durasi tidak valid.${NC}"; sleep 2; return
            fi
            unit_text="days"
            ;;
        *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 2; return;;
    esac

    echo -e "\n${YELLOW}Melakukan ban pada '$player_name' selama $duration $unit_text...${NC}"
    sendCmd "$server_name" "ban $player_name Durasi: $duration $unit_text"

    # Jadwalkan unban otomatis menggunakan 'at'
    local unban_cmd="bash -c 'source /root/mc-panel/functions/player_manager.sh && unbanPlayer \"$server_name\" \"$player_name\"'"
    local job_output=$(echo "$unban_cmd" | at now + $duration $unit_text 2>&1)
    local job_id=$(echo "$job_output" | awk '/job/ {print $2}')

    if [ -n "$job_id" ]; then
        # Simpan informasi ban agar bisa di-unban manual
        echo "$server_name|$player_name|$job_id" >> "$BANS_LOG"
        echo -e "${GREEN}✅ Pemain berhasil di-ban. Unban otomatis dijadwalkan (Job ID: $job_id).${NC}"
    else
        echo -e "${RED}Gagal menjadwalkan unban otomatis. Silakan unban manual nanti.${NC}"
    fi
    read -p "Tekan [Enter]..."
}

# Fungsi untuk unban (bisa dipanggil manual atau otomatis oleh 'at')
function unbanPlayer() {
    local server_name=$1
    local player_name
    
    # Jika player_name tidak diberikan sebagai argumen, minta input manual
    if [ -z "$2" ]; then
        clear
        echo -e "${BLUE}--- Unban Pemain ---${NC}"
        read -p "Masukkan nama pemain yang akan di-unban: " player_name
        if [ -z "$player_name" ]; then echo "Dibatalkan."; sleep 1; return; fi
        echo -e "\n${YELLOW}Mengirim perintah unban untuk '$player_name'...${NC}"
    else
        # Ini dieksekusi oleh jadwal 'at'
        player_name=$2
        echo "Unban otomatis untuk $player_name di server $server_name pada $(date)" >> /root/mc-panel/logs/bot.log
    fi
    
    sendCmd "$server_name" "pardon $player_name"

    # Cari dan batalkan jadwal 'at' jika ada
    local ban_info=$(grep "|$player_name|" "$BANS_LOG")
    if [ -n "$ban_info" ]; then
        local job_id=$(echo "$ban_info" | cut -d'|' -f3)
        atrm "$job_id" 2>/dev/null # Hapus jadwal 'at'
        # Hapus entri dari log
        grep -v "|$player_name|" "$BANS_LOG" > "$BANS_LOG.tmp" && mv "$BANS_LOG.tmp" "$BANS_LOG"
    fi
    
    if [ -z "$2" ]; then
        echo -e "${GREEN}✅ Perintah unban terkirim dan jadwal (jika ada) telah dibatalkan.${NC}"
        read -p "Tekan [Enter]..."
    fi
}

# Menu utama untuk manajer pemain
function playerMenu() {
    local server_name=$1
    if [[ "$(getServerStatus "$server_name")" == *Berhenti* ]]; then
        echo -e "${RED}Server harus berjalan untuk menggunakan Manajer Pemain.${NC}"; sleep 2; return
    fi

    while true; do
        clear
        echo -e "${BLUE}--- Manajer Pemain: $server_name ---${NC}"
        echo "1. Jadikan Operator (OP)"
        echo "2. Cabut Operator (De-OP)"
        echo "3. Ban Pemain"
        echo "4. Unban Pemain"
        echo "5. Tambah ke Whitelist"
        echo "0. Kembali ke Dasbor Server"
        read -p "Pilihan: " choice
        
        local player_name
        case $choice in
            1|2|5)
                case $choice in
                    1) read -p "Masukkan nama pemain yang akan di-OP: " player_name; [ -n "$player_name" ] && sendCmd "$server_name" "op $player_name" ;;
                    2) read -p "Masukkan nama pemain yang akan di-DeOP: " player_name; [ -n "$player_name" ] && sendCmd "$server_name" "deop $player_name" ;;
                    5) read -p "Masukkan nama pemain untuk di-whitelist: " player_name; [ -n "$player_name" ] && sendCmd "$server_name" "whitelist add $player_name" ;;
                esac
                if [ -n "$player_name" ]; then echo -e "${GREEN}Perintah terkirim.${NC}"; fi
                sleep 2
                ;;
            3) # Menu Ban
               clear
               echo "Pilih tipe Ban:"; echo "1. Ban Permanen"; echo "2. Ban dengan Durasi"
               read -p "> " ban_choice
               case $ban_choice in
                   1) read -p "Masukkan nama pemain yang akan di-ban permanen: " player_name; [ -n "$player_name" ] && sendCmd "$server_name" "ban $player_name" ;;
                   2) timedBanPlayer "$server_name" ;;
               esac
               ;;
            4) unbanPlayer "$server_name" ;;
            0) return ;;
            *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}
