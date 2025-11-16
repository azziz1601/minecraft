#!/bin/bash

# Folder sementara untuk backup lokal sebelum diunggah
LOCAL_BACKUP_TEMP_DIR="/tmp/mc_panel_mega_backups"

# Fungsi untuk memastikan pengguna sudah login ke Mega
function ensureMegaLogin() {
    echo -e "${YELLOW}[DEBUG] Memulai ensureMegaLogin.${NC}" # DEBUG
    echo -e "${YELLOW}[DEBUG] PATH saat ini: $PATH${NC}" # DEBUG

    local MEGA_CMD_BIN="$(command -v mega-cmd)"
    if [ -z "$MEGA_CMD_BIN" ]; then
        # Jika tidak ditemukan di PATH, coba jalur snap default
        MEGA_CMD_BIN="/snap/bin/mega-cmd"
        if [ ! -x "$MEGA_CMD_BIN" ]; then
            echo -e "${RED}ERROR: mega-cmd tidak ditemukan di PATH maupun di /snap/bin/.${NC}"
            return 1
        fi
    fi
    echo -e "${YELLOW}[DEBUG] Menggunakan mega-cmd dari: $MEGA_CMD_BIN${NC}" # DEBUG

    sleep 1 # Beri waktu MEGAcmd untuk berinisialisasi
    echo -e "${YELLOW}[DEBUG] Menjalankan \"$MEGA_CMD_BIN\" help untuk diagnosis dengan timeout 10s...${NC}" # DEBUG
    local help_output; help_output="$(timeout 10s "$MEGA_CMD_BIN" help 2>&1)"
    local help_exit_code=$?
    echo -e "${YELLOW}[DEBUG] Output help: $help_output${NC}" # DEBUG
    echo -e "${YELLOW}[DEBUG] Exit code help: $help_exit_code${NC}" # DEBUG

    if [ "$help_exit_code" -ne 0 ]; then
        echo -e "${RED}ERROR: Gagal menjalankan 'mega-cmd help' (Exit code: $help_exit_code). Ini mungkin menunjukkan masalah instalasi atau lingkungan dengan MEGAcmd.${NC}"
        if [[ "$help_output" == *"Segmentation fault"* ]]; then
            echo -e "${RED}Terdeteksi 'Segmentation fault'. Coba instal ulang MEGAcmd atau periksa kompatibilitas sistem.${NC}"
        elif [ "$help_exit_code" -eq 124 ]; then
            echo -e "${RED}Perintah 'mega-cmd help' timeout. MEGAcmd mungkin macet atau memerlukan inisialisasi interaktif yang tidak dapat ditangani skrip ini.${NC}"
        fi
        read -p "Tekan [Enter] untuk kembali."
        return 1
    fi
    echo -e "${GREEN}✅ mega-cmd help berhasil dijalankan.${NC}"
    sleep 1 # Beri waktu MEGAcmd untuk berinisialisasi setelah help

    # --- Tahap Login --- 
    echo -e "${YELLOW}[DEBUG] Mencoba memeriksa status login dengan whoami...${NC}" # DEBUG
    local whoami_output; whoami_output="$("$MEGA_CMD_BIN" whoami 2>&1)"
    local whoami_exit_code=$?
    echo -e "${YELLOW}[DEBUG] Output whoami: $whoami_output${NC}" # DEBUG
    echo -e "${YELLOW}[DEBUG] Exit code whoami: $whoami_exit_code${NC}" # DEBUG

    # mega-cmd whoami mengembalikan exit code 0 bahkan jika tidak login, tetapi outputnya kosong atau berisi pesan 'not logged in'
    # Cek apakah output mengandung '@' (email) untuk mengonfirmasi login
    if [ "$whoami_exit_code" -eq 0 ] && [[ "$whoami_output" == *"@"* ]]; then
        echo -e "${GREEN}✅ Sudah login ke MEGA sebagai: ${whoami_output}${NC}"
        return 0 # Sudah login
    else
        echo -e "${YELLOW}[DEBUG] mega-cmd whoami gagal atau tidak login, perlu login.${NC}" # DEBUG
        clear
        echo -e "${YELLOW}Anda belum login ke akun MEGA Anda.${NC}"
        echo "Harap login sekarang untuk menggunakan fitur backup/restore MEGA."
        echo "(Email dan password Anda tidak akan disimpan oleh skrip ini, hanya oleh MEGAcmd)"
        echo
        read -rp "Masukkan Email MEGA Anda: " mega_email
        read -rsp "Masukkan Password MEGA Anda: " mega_password
        echo

        if [ -z "$mega_email" ] || [ -z "$mega_password" ]; then
            echo -e "${RED}Email dan Password tidak boleh kosong. Login dibatalkan.${NC}"
            sleep 2
            return 1
        fi

        echo -e "${BLUE}Mencoba login ke MEGA...${NC}"
        if "$MEGA_CMD_BIN" login "$mega_email" "$mega_password"; then
            echo -e "${GREEN}✅ Login MEGA berhasil!${NC}"
            sleep 2
            return 0
        else
            echo -e "${RED}Login MEGA gagal. Periksa kembali kredensial Anda.${NC}"
            sleep 2
            return 1
        fi
    fi
}

# Fungsi untuk membuat backup dan mengunggahnya ke Mega
function runBackupToMega() {
    clear
    echo -e "${BLUE}--- Backup Server ke MEGA Cloud Storage ---${NC}"
    echo -e "${YELLOW}[DEBUG] Memulai runBackupToMega.${NC}" # DEBUG

    # Pastikan MEGAcmd terinstal
    if ! command -v mega-cmd &> /dev/null; then
        echo -e "${RED}ERROR: MEGAcmd tidak ditemukan. Harap instal MEGAcmd terlebih dahulu.${NC}"
        read -p "Tekan [Enter] untuk kembali."
        return
    fi

    # Pastikan pengguna sudah login ke Mega
    if ! ensureMegaLogin; then
        echo -e "${RED}Login MEGA gagal atau dibatalkan. Backup tidak dapat dilanjutkan.${NC}"
        read -p "Tekan [Enter] untuk kembali."
        return
    fi

    echo -e "${YELLOW}[DEBUG] Setelah ensureMegaLogin.${NC}" # DEBUG
    mapfile -t servers < <(find "$SERVERS_DIR" -mindepth 1 -maxdepth 1 -type d)
    echo -e "${YELLOW}[DEBUG] Server ditemukan: ${#servers[@]}${NC}" # DEBUG
    if [ ${#servers[@]} -eq 0 ]; then echo -e "${YELLOW}Belum ada server untuk dibackup.${NC}\n"; read -p "Tekan [Enter] untuk kembali."; return; fi

    echo -e "${BLUE}Pilih Server untuk di-Backup:${NC}"; i=1
    for server_path in "${servers[@]}"; do echo "$i. $(basename "$server_path")"; i=$((i+1)); done
    read -p "Masukkan nomor server [1-${#servers[@]}] (atau 0 untuk kembali): " server_choice

    if ! [[ "$server_choice" =~ ^[0-9]+$ ]] || [ "$server_choice" -lt 0 ] || [ "$server_choice" -gt ${#servers[@]} ]; then echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 2; return; fi
    if [ "$server_choice" -eq 0 ]; then return; fi

    local server_path="${servers[$server_choice-1]}"
    local server_name; server_name=$(basename "$server_path")
    
    read -p "Lanjutkan backup untuk '$server_name' ke MEGA? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo "Dibatalkan."; sleep 2; return; fi

    clear
    echo -e "${BLUE}Memulai proses backup untuk: ${YELLOW}$server_name${NC}"

    mkdir -p "$LOCAL_BACKUP_TEMP_DIR"
    local backup_file="backup-${server_name}-$(date +%F-%H%M).tar.gz"
    local temp_archive_path="$LOCAL_BACKUP_TEMP_DIR/$backup_file"

    echo "-> Mengarsipkan data server ke $temp_archive_path..."
    tar -czf "$temp_archive_path" -C "$SERVERS_DIR" "$server_name"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Gagal membuat arsip backup.${NC}"
        rm -f "$temp_archive_path"
        read -p "Tekan [Enter] untuk kembali."
        return
    fi

    echo "-> Mengunggah backup ke MEGA..."
    # Buat folder di MEGA jika belum ada
    mega-mkdir -p /Root/mc-panel-backups &> /dev/null
    if mega-put "$temp_archive_path" "/Root/mc-panel-backups/$backup_file"; then
        echo -e "${GREEN}✅ Backup berhasil diunggah ke MEGA!${NC}"
        echo -e "\nFile tersedia di MEGA Anda: ${GREEN}/Root/mc-panel-backups/$backup_file${NC}\n"
        echo -e "${YELLOW}Anda dapat membagikan file ini dari antarmuka web MEGA untuk mendapatkan direct link permanen.${NC}"
    else
        echo -e "${RED}Gagal mengunggah backup ke MEGA.${NC}"
    fi

    echo "-> Membersihkan file lokal sementara..."
    rm -f "$temp_archive_path"
    read -p "Tekan [Enter] untuk kembali."
}

# Fungsi untuk restore server dari Mega
function runRestoreFromMega() {
    clear
    echo -e "${BLUE}--- Restore Server dari MEGA Cloud Storage ---${NC}"

    # Pastikan MEGAcmd terinstal
    if ! command -v mega-cmd &> /dev/null; then
        echo -e "${RED}ERROR: MEGAcmd tidak ditemukan. Harap instal MEGAcmd terlebih dahulu.${NC}"
        read -p "Tekan [Enter] untuk kembali."
        return
    fi

    # Pastikan pengguna sudah login ke Mega
    if ! ensureMegaLogin; then
        echo -e "${RED}Login MEGA gagal atau dibatalkan. Restore tidak dapat dilanjutkan.${NC}"
        read -p "Tekan [Enter] untuk kembali."
        return
    fi

    echo "Masukkan path file backup di MEGA Anda (misal: /Root/mc-panel-backups/backup-server-2023-11-15.tar.gz)"
    echo "Atau masukkan direct link publik dari MEGA (jika Anda sudah membuatnya di web MEGA)"
    echo
    read -p "Masukkan path/link backup MEGA: " restore_source

    if [ -z "$restore_source" ]; then
        echo "Dibatalkan. Path/link tidak boleh kosong."
        sleep 2
        return
    fi

    local temp_download_path="/tmp/mega_restore_download.tar.gz"
    echo -e "\n${YELLOW}Mencoba mengunduh dari MEGA...${NC}"

    # Cek apakah input adalah path MEGA atau URL
    if [[ "$restore_source" == /Root/* ]] || [[ "$restore_source" == /* ]]; then
        # Ini adalah path MEGA
        if mega-get "$restore_source" "$temp_download_path"; then
            echo -e "${GREEN}✅ Download dari MEGA berhasil.${NC}"
        else
            echo -e "${RED}GAGAL: Tidak dapat mengunduh dari path MEGA tersebut. Pastikan path benar dan Anda memiliki akses.${NC}"
            rm -f "$temp_download_path"
            read -p "Tekan [Enter] untuk kembali."
            return
        fi
    else
        # Ini mungkin URL publik
        if wget -O "$temp_download_path" "$restore_source"; then
            echo -e "${GREEN}✅ Download dari URL berhasil.${NC}"
        else
            echo -e "${RED}GAGAL: Tidak dapat mengunduh dari URL tersebut. Pastikan link benar dan dapat diakses publik.${NC}"
            rm -f "$temp_download_path"
            read -p "Tekan [Enter] untuk kembali."
            return
        fi
    fi

    if [ -f "$temp_download_path" ]; then
        echo -e "\n${YELLOW}PERINGATAN: Proses ini akan mengekstrak data ke direktori servers/. Jika ada server dengan nama yang sama di dalam arsip, datanya akan ditimpa.${NC}"
        read -p "Lanjutkan proses ekstraksi? (y/n): " confirm_extract

        if [[ "$confirm_extract" == "y" ]]; then
            echo "-> Mengekstrak backup ke direktori servers/..."
            tar -xzf "$temp_download_path" -C "$SERVERS_DIR/"
            if [ $? -eq 0 ]; then
                echo -e "\n${GREEN}✅ Restore selesai! Server berhasil dipindahkan.${NC}"
            else
                echo -e "${RED}ERROR: Gagal mengekstrak arsip backup.${NC}"
            fi
        else
            echo "Dibatalkan."
        fi

        echo "-> Membersihkan file download sementara..."
        rm -f "$temp_download_path"
    else
        echo -e "${RED}ERROR: File backup tidak ditemukan setelah diunduh.${NC}"
    fi

    read -p "Tekan [Enter] untuk kembali."
}

# Fungsi migrasi server ke VPS lain via rsync (tetap dipertahankan)
function runMigrateViaRsync() {
    clear
    echo -e "${BLUE}--- Migrasi Server ke VPS Lain (via rsync SSH) ---${NC}"

    mapfile -t servers < <(find "$SERVERS_DIR" -mindepth 1 -maxdepth 1 -type d)
    if [ ${#servers[@]} -eq 0 ]; then echo -e "${YELLOW}Belum ada server yang bisa dimigrasi.${NC}\n"; read -p "Tekan [Enter] untuk kembali."; return; fi

    echo -e "${BLUE}Pilih Server yang ingin di-migrate:${NC}"; i=1
    for server_path in "${servers[@]}"; do echo "$i. $(basename "$server_path")"; i=$((i+1)); done
    read -p "Masukkan nomor server [1-${#servers[@]}] (atau 0 untuk batal): " server_choice

    if ! [[ "$server_choice" =~ ^[0-9]+$ ]] || [ "$server_choice" -lt 0 ] || [ "$server_choice" -gt ${#servers[@]} ]; then echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 2; return; fi
    if [ "$server_choice" -eq 0 ]; then return; fi

    local server_name; server_name=$(basename "${servers[$server_choice-1]}")

    read -p "Masukkan user VPS tujuan      [default: root]: " vps_user
    vps_user=${vps_user:-root}
    read -p "Masukkan IP VPS tujuan        : " vps_ip
    if [ -z "$vps_ip" ]; then echo -e "${RED}IP tidak boleh kosong!${NC}"; sleep 2; return; fi
    read -p "Masukkan port SSH [default: 22]: " vps_port
    vps_port=${vps_port:-22}
    read -p "Masukkan path folder panel di VPS tujuan [default: /root/mc-panel]: " vps_panel_dir
    vps_panel_dir=${vps_panel_dir:-/root/mc-panel}

    echo -e "${BLUE}Mengirim folder server menggunakan rsync...${NC}"
    rsync -avz --progress -e "ssh -p $vps_port" "$SERVERS_DIR/$server_name/" "$vps_user@$vps_ip:$vps_panel_dir/servers/$server_name/"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Migrasi selesai! Server telah dikopi ke VPS tujuan (dengan rsync).${NC}"
    else
        echo -e "${RED}Gagal melakukan migrasi dengan rsync.${NC}"
    fi
    read -p "Tekan [Enter] untuk kembali."
}

# Menu utama backup
function backupMenu() {
    while true; do
        clear
        echo -e "${BLUE}--- Manajemen Backup & Migrasi Server ---${NC}"
        echo -e "${YELLOW}Pilih metode backup/migrasi yang Anda inginkan.${NC}"
        echo "-----------------------------------------------------
"
        echo "1. Backup ke MEGA Cloud Storage"
        echo "2. Restore dari MEGA Cloud Storage"
        echo "3. Transfer Data Server Via SSH (rsync)"
        echo "0. Kembali ke Menu Utama"
        echo "-----------------------------------------------------
"
        read -p "Masukkan pilihan: " choice
        case $choice in
            1) runBackupToMega ;; 

            2) runRestoreFromMega ;; 

            3) runMigrateViaRsync ;; 

            0) return ;; 

            *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;; 

        esac
    done
}
