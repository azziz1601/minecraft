#!/bin/bash

# Fungsi pembantu untuk mendapatkan nilai properti dari server.properties
function getProperty() {
    local server_path=$1
    local property=$2
    grep "^$property=" "$server_path/server.properties" | cut -d'=' -f2
}

# Fungsi pembantu untuk mengubah nilai properti
function setProperty() {
    local server_path=$1
    local property=$2
    local value=$3
    # Gunakan sed untuk mencari dan mengganti baris yang sesuai
    sed -i "s/^$property=.*/$property=$value/" "$server_path/server.properties"
    echo -e "${GREEN}✅ Properti '$property' telah diubah menjadi '$value'.${NC}"
    sleep 2
}

# Fungsi baru untuk menampilkan menu on/off (true/false)
function toggleProperty() {
    local server_path=$1
    local property=$2
    local display_name=$3
    local current_val=$(getProperty "$server_path" "$property")

    clear
    echo -e "${BLUE}--- Mengubah ${display_name} ---${NC}"
    echo -e "Status saat ini: ${YELLOW}${current_val}${NC}"
    echo "1. Aktifkan (true)"
    echo "2. Matikan (false)"
    echo "0. Batal"
    read -p "Pilihan: " choice

    case $choice in
        1) setProperty "$server_path" "$property" "true" ;;
        2) setProperty "$server_path" "$property" "false" ;;
        0) echo "Dibatalkan."; sleep 1 ;;
        *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
    esac
}

# Menu utama editor konfigurasi yang sudah dirombak
function configEditorMenu() {
    local server_name=$1
    local server_path="$SERVERS_DIR/$server_name"

    while true; do
        clear
        # --- Pengumpulan Data (Lebih Lengkap) ---
        local motd_val=$(getProperty "$server_path" "motd")
        local max_players_val=$(getProperty "$server_path" "max-players")
        local gamemode_val=$(getProperty "$server_path" "gamemode")
        local difficulty_val=$(getProperty "$server_path" "difficulty")
        local view_dist_val=$(getProperty "$server_path" "view-distance")
        local pvp_val=$(getProperty "$server_path" "pvp")
        local whitelist_val=$(getProperty "$server_path" "white-list")
        local flight_val=$(getProperty "$server_path" "allow-flight")

        # --- Tampilan Menu Baru (Lebih Lengkap & Warna Diperbaiki) ---
        echo -e "${BLUE}--- Editor Konfigurasi: $server_name ---${NC}"
        echo "Pilih properti yang ingin diubah:"
        # Menggunakan printf untuk perataan yang sempurna dan echo -e untuk warna
        printf "%-4s %-26s : %s\n" "1." "MOTD (Nama Server)" "$(echo -e "${GREEN}$motd_val${NC}")"
        printf "%-4s %-26s : %s\n" "2." "Max Pemain" "$(echo -e "${GREEN}$max_players_val${NC}")"
        printf "%-4s %-26s : %s\n" "3." "Gamemode" "$(echo -e "${GREEN}$gamemode_val${NC}")"
        printf "%-4s %-26s : %s\n" "4." "Tingkat Kesulitan" "$(echo -e "${GREEN}$difficulty_val${NC}")"
        printf "%-4s %-26s : %s\n" "5." "Jarak Pandang (View Dist)" "$(echo -e "${GREEN}$view_dist_val${NC}")"
        printf "%-4s %-26s : %s\n" "6." "PVP" "$(echo -e "${GREEN}$pvp_val${NC}")"
        printf "%-4s %-26s : %s\n" "7." "Whitelist" "$(echo -e "${GREEN}$whitelist_val${NC}")"
        printf "%-4s %-26s : %s\n" "8." "Izinkan Terbang (Flight)" "$(echo -e "${GREEN}$flight_val${NC}")"
        echo -e "--------------------------------------------------"
        echo "0. Kembali ke Dasbor Server"
        
        read -p "Pilihan: " choice
        case $choice in
            1)
                read -p "Masukkan MOTD baru: " new_motd
                [ -n "$new_motd" ] && setProperty "$server_path" "motd" "$new_motd"
                ;;
            2)
                read -p "Masukkan Max Pemain baru: " new_max
                [ -n "$new_max" ] && setProperty "$server_path" "max-players" "$new_max"
                ;;
            3)
                read -p "Masukkan Gamemode baru (survival/creative/adventure): " new_gm
                [ -n "$new_gm" ] && setProperty "$server_path" "gamemode" "$new_gm"
                ;;
            4)
                read -p "Masukkan Tingkat Kesulitan baru (peaceful/easy/normal/hard): " new_diff
                [ -n "$new_diff" ] && setProperty "$server_path" "difficulty" "$new_diff"
                ;;
            5)
                read -p "Masukkan Jarak Pandang baru (misal: 10): " new_vd
                [ -n "$new_vd" ] && setProperty "$server_path" "view-distance" "$new_vd"
                ;;
            6) toggleProperty "$server_path" "pvp" "PVP" ;;
            7) toggleProperty "$server_path" "white-list" "Whitelist" ;;
            8) toggleProperty "$server_path" "allow-flight" "Izinkan Terbang" ;;
            0) return ;;
            *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}
