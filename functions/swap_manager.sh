#!/bin/bash

# Fungsi untuk mengecek status swap saat ini
function getSwapStatus() {
    if swapon --show | grep -q '/swapfile'; then
        echo -e "${GREEN}Aktif${NC}"
    else
        if [ -f /swapfile ]; then
            echo -e "${YELLOW}Nonaktif (File Ada)${NC}"
        else
            echo -e "${RED}Tidak Ada${NC}"
        fi
    fi
}

# Fungsi untuk membuat atau mengganti swap file
function createSwap() {
    local size=$1

    # Cek apakah swap sudah ada, jika ya, nonaktifkan dan hapus dulu
    if [ -f /swapfile ]; then
        echo -e "${YELLOW}Swap file sudah ada. Menonaktifkan dan menghapus yang lama...${NC}"
        sudo swapoff /swapfile
        sudo rm /swapfile
        # Hapus entri lama dari /etc/fstab agar tidak duplikat
        sudo sed -i '/\/swapfile/d' /etc/fstab
    fi

    echo -e "\n${YELLOW}Membuat swap file baru sebesar ${size}B...${NC}"
    sudo fallocate -l "${size}G" /swapfile
    if [ $? -ne 0 ]; then
        echo -e "${RED}Gagal membuat file dengan fallocate. Mencoba dengan dd (lebih lambat)...${NC}"
        sudo dd if=/dev/zero of=/swapfile bs=1G count="$size"
    fi
    
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile

    # Tambahkan ke /etc/fstab agar aktif otomatis saat reboot
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

    echo -e "\n${GREEN}✅ Swap file sebesar ${size}GB berhasil dibuat dan diaktifkan.${NC}"
    read -p "Tekan [Enter] untuk kembali."
}

# Fungsi untuk mengaktifkan/menonaktifkan swap
function toggleSwap() {
    if ! [ -f /swapfile ]; then
        echo -e "${RED}Swap file tidak ditemukan. Silakan buat terlebih dahulu.${NC}"
        sleep 3
        return
    fi

    if swapon --show | grep -q '/swapfile'; then
        echo -e "${YELLOW}Menonaktifkan swap...${NC}"
        sudo swapoff /swapfile
    else
        echo -e "${YELLOW}Mengaktifkan swap...${NC}"
        sudo swapon /swapfile
    fi
    sleep 2
}

# Fungsi utama untuk menu swap
function swapMenu() {
    while true; do
        clear
        local current_swap_size
        if [ -f /swapfile ]; then
            current_swap_size=$(ls -lh /swapfile | awk '{print $5}')
        else
            current_swap_size="N/A"
        fi

        echo -e "${BLUE}--- Manajemen RAM Swap ---${NC}"
        echo -e "Status Swap     : $(getSwapStatus)"
        echo -e "Ukuran Saat Ini : ${YELLOW}$current_swap_size${NC}"
        echo -e "${BLUE}------------------------------------${NC}"
        echo -e "Pilih aksi:"
        echo -e "${GREEN}1. Aktifkan / Nonaktifkan Swap${NC}"
        echo ""
        echo "   --- Buat Swap File Baru ---"
        echo "   (Membuat baru akan menghapus yang lama)"
        echo "2.  Buat Swap 1GB"
        echo "3.  Buat Swap 2GB"
        echo "4.  Buat Swap 4GB"
        echo "5.  Buat Swap 8GB"
        echo ""
        echo -e "${RED}9.  Hapus Swap File Secara Permanen${NC}"
        echo "0.  Kembali ke Menu Utama"
        echo -e "${BLUE}------------------------------------${NC}"

        read -p "Masukkan pilihan: " choice
        case $choice in
            1) toggleSwap ;;
            2) createSwap 1 ;;
            3) createSwap 2 ;;
            4) createSwap 4 ;;
            5) createSwap 8 ;;
            9)
                if [ -f /swapfile ]; then
                    echo -e "${RED}PERINGATAN: Ini akan menghapus swap file secara permanen.${NC}"
                    read -p "Apakah Anda yakin? (y/n): " confirm
                    if [[ "$confirm" == "y" ]]; then
                        sudo swapoff /swapfile
                        sudo rm /swapfile
                        sudo sed -i '/\/swapfile/d' /etc/fstab
                        echo -e "${GREEN}Swap file telah dihapus.${NC}"
                    else
                        echo "Dibatalkan."
                    fi
                else
                    echo -e "${YELLOW}Tidak ada swap file untuk dihapus.${NC}"
                fi
                sleep 2
                ;;
            0) return ;;
            *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}
