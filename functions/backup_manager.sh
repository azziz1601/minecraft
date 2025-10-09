#!/bin/bash

BACKUP_DIR="/tmp/mc_panel_backups" # Folder sementara untuk backup

# Fungsi untuk membuat backup langsung
function runCreateDirectBackup() {
    clear
    mapfile -t servers < <(find "$SERVERS_DIR" -mindepth 1 -maxdepth 1 -type d)
    if [ ${#servers[@]} -eq 0 ]; then echo -e "${YELLOW}Belum ada server untuk dibackup.${NC}"; read -p "..."; return; fi

    echo -e "${BLUE}--- Pilih Server untuk di-Backup ---${NC}"; i=1
    for server_path in "${servers[@]}"; do echo "$i. $(basename "$server_path")"; i=$((i+1)); done
    read -p "Masukkan nomor server [1-${#servers[@]}] (atau 0 untuk kembali): " server_choice

    if ! [[ "$server_choice" =~ ^[0-9]+$ ]] || [ "$server_choice" -lt 0 ] || [ "$server_choice" -gt ${#servers[@]} ]; then echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 2; return; fi
    if [ "$server_choice" -eq 0 ]; then return; fi

    local server_name; server_name=$(basename "${servers[$server_choice-1]}")
    read -p "Lanjutkan backup untuk '$server_name'? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo "Dibatalkan."; sleep 2; return; fi

    clear
    echo -e "${BLUE}Memulai proses backup untuk: ${YELLOW}$server_name${NC}"

    mkdir -p "$BACKUP_DIR" && rm -f "$BACKUP_DIR"/*

    local backup_file="backup-${server_name}-$(date +%F-%H%M).tar.gz"
    local temp_path="$BACKUP_DIR/$backup_file"
    echo "-> Mengarsipkan data server..."
    tar -czf "$temp_path" -C "$SERVERS_DIR" "$server_name"

    local port=8080
    local vps_ip=$(hostname -I | awk '{print $1}')
    echo "-> Membuka port firewall $port..."
    ufw allow $port/tcp > /dev/null

    echo "-> Menyalakan web server sementara..."
    python3 -m http.server $port --directory "$BACKUP_DIR" &> /dev/null &
    local server_pid=$!

    clear
    echo -e "${GREEN}✅ Sesi Backup Dimulai!${NC}"
    echo -e "${YELLOW}Gunakan link di bawah ini untuk proses restore di VPS baru.${NC}"
    echo -e "\nLink Download/Restore:\n${GREEN}http://$vps_ip:$port/$backup_file${NC}\n"
    echo -e "${RED}PENTING: Sesi ini dan link ini hanya akan aktif selama 10 menit.${NC}"
    echo "Jangan tutup jendela ini sampai proses restore di VPS baru selesai."

    # Tunggu 10 menit (600 detik)
    sleep 600

    echo -e "\n\n${YELLOW}Waktu habis. Mematikan web server dan membersihkan...${NC}"
    kill $server_pid
    ufw delete allow $port/tcp > /dev/null
    rm -f "$temp_path"
    echo -e "${GREEN}Sesi backup selesai.${NC}"
    read -p "Tekan [Enter] untuk kembali."
}

# Fungsi untuk restore dari link
function runRestoreViaLink() {
    clear
    echo -e "${BLUE}--- Restore Server dari Link Backup ---${NC}"
    echo "Pastikan Anda sudah menjalankan 'Buat Backup' di VPS lama dan sesi-nya masih aktif."
    echo
    read -p "Masukkan link backup dari VPS lama: " restore_link

    if [ -z "$restore_link" ]; then
        echo "Dibatalkan. Link tidak boleh kosong."
        sleep 2
        return
    fi

    echo -e "\n${YELLOW}Mencoba mengunduh dari link...${NC}"
    wget -O /tmp/backup_restore.tar.gz "$restore_link"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Download berhasil.${NC}"
        echo -e "\n${YELLOW}PERINGATAN: Proses ini akan menimpa data server yang ada jika namanya sama.${NC}"
        read -p "Lanjutkan proses ekstraksi? (y/n): " confirm_extract

        if [[ "$confirm_extract" == "y" ]]; then
            echo "-> Mengekstrak backup ke direktori servers..."
            tar -xzf /tmp/backup_restore.tar.gz -C "$SERVERS_DIR/"
            echo -e "\n${GREEN}✅ Restore selesai! Server berhasil dipindahkan.${NC}"
        else
            echo "Dibatalkan."
        fi

        echo "-> Membersihkan file download..."
        rm /tmp/backup_restore.tar.gz
    else
        echo -e "\n${RED}GAGAL: Tidak dapat mengunduh dari link tersebut.${NC}"
        echo "Pastikan link sudah benar dan sesi backup di VPS lama masih aktif."
    fi

    read -p "Tekan [Enter] untuk kembali."
}

# Fungsi baru: Migrasi server ke VPS lain via rsync (lebih cepat untuk file besar)
function runMigrateViaRsync() {
    clear
    echo -e "${BLUE}--- Migrasi Server ke VPS Lain (via rsync SSH) ---${NC}"

    mapfile -t servers < <(find "$SERVERS_DIR" -mindepth 1 -maxdepth 1 -type d)
    if [ ${#servers[@]} -eq 0 ]; then echo -e "${YELLOW}Belum ada server yang bisa dimigrasi.${NC}"; read -p "..."; return; fi

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
        echo -e "${YELLOW}Metode ini cocok untuk memindahkan server antar VPS.${NC}"
        echo "-----------------------------------------------------"
        echo "1. Buat Backup (Menghasilkan Link)"
        echo "2. Restore dari Link"
        echo "3. Migrasi Server ke VPS Lain (via rsync/SSH)"
        echo "0. Kembali ke Menu Utama"
        echo "-----------------------------------------------------"
        read -p "Masukkan pilihan: " choice
        case $choice in
            1) runCreateDirectBackup ;;
            2) runRestoreViaLink ;;
            3) runMigrateViaRsync ;;
            0) return ;;
            *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}
