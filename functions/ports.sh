#!/usr/bin/env bash

# Definisi warna untuk tampilan
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m';
BLUE='\033[0;34m'; MAG='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

# Direktori server untuk identifikasi proses (opsional, bisa disesuaikan)
SERVERS_DIR="${SERVERS_DIR:-/root/mc-panel/servers}"

# Fungsi utama untuk menampilkan menu port
portsMenu() {
    # Cek dependensi esensial
    if ! command -v "ss" >/dev/null 2>&1; then
        echo -e "${RED}Perintah 'ss' tidak ditemukan. Fitur ini tidak dapat berjalan.${NC}"
        read -p "Tekan [Enter] untuk kembali..."; return
    fi

    clear
    
    # --- Header Tampilan ---
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}             ${CYAN}DAFTAR SEMUA PORT SERVER YANG SEDANG DIGUNAKAN${NC}             ${BLUE}║${NC}"
    echo -e "${BLUE}╠═════════╤═══════════╤════════════════════════════╤═════════════════════╣${NC}"
    printf "${BLUE}║${NC} %-5s│ %-9s │ %-26s │ %-20s ${BLUE}" "Protokol" "Port" "Nama Proses" "Status"
    echo -e "${BLUE}╠═════════╪═══════════╪════════════════════════════╪═════════════════════╣${NC}"

    # --- Mengumpulkan dan Menampilkan Data ---
    # Menggunakan 'ss' untuk mengambil data TCP dan UDP yang listening, lalu 'awk' untuk memformatnya
    ss -lntup 2>/dev/null | awk '
        NR > 1 {
            # Ekstrak informasi port dan proses
            port = $5; sub(/.*:/, "", port);
            proc = "-";
            if (match($7, /users:\(\("([^"]+)"/, m)) {
                proc = m[1];
            }
            # Tentukan warna protokol
            proto_color = "\033[0;32m"; # Hijau untuk TCP
            if ($1 ~ /^udp/) {
                proto_color = "\033[0;35m"; # Magenta untuk UDP
            }
            
            # Cetak baris tabel dengan format
            printf("\033[0;34m║\033[0m %-13s     │ %-9s │ %-26.26s │ \033[1;33m%-20s\033[0;34m \033[0m\n", proto_color toupper(substr($1,1,3)) "\033[0m", port, proc, "DIGUNAKAN");
        }
    '

    # --- Footer Tampilan ---
    echo -e "${BLUE}╚═════════╧═══════════╧════════════════════════════╧═════════════════════╝${NC}"
    echo
    read -p "Tekan [Enter] untuk kembali ke menu utama..."
}
