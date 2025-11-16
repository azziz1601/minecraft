#!/bin/bash

function deleteServer() {
    clear
    mapfile -t servers < <(find "$SERVERS_DIR" -mindepth 1 -maxdepth 1 -type d)
    if [ ${#servers[@]} -eq 0 ]; then echo -e "${YELLOW}Belum ada server untuk dihapus.${NC}"; read -p "Tekan [Enter]..."; return; fi
    
    echo -e "${BLUE}--- Hapus Server ---${NC}"; echo -e "${RED}PERINGATAN: Tindakan ini akan menghapus semua file server secara permanen.${NC}"
    i=1; for server_path in "${servers[@]}"; do echo "$i. $(basename "$server_path")"; i=$((i+1)); done
    
    read -p "Pilih server yang akan dihapus [1-${#servers[@]}] (atau 0 untuk kembali): " server_choice
    if [ "$server_choice" -eq 0 ]; then return; fi

    local selected_server_path="${servers[$server_choice-1]}"
    if [ -z "$selected_server_path" ]; then echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 2; return; fi

    local server_name=$(basename "$selected_server_path")
    echo -e "\n${YELLOW}Anda akan menghapus server: ${RED}$server_name${NC}"
    read -p "Untuk konfirmasi, ketik nama server ini ('$server_name'): " confirmation_input

    if [ "$confirmation_input" != "$server_name" ]; then echo -e "\n${GREEN}Input tidak sesuai. Penghapusan dibatalkan.${NC}"; sleep 2; return; fi

    echo -e "\n${YELLOW}Konfirmasi diterima. Memproses penghapusan...${NC}"
    if [[ "$(getServerStatus "$server_name")" == *Berjalan* ]]; then
        echo "Mematikan sesi tmux '$server_name'..."
        tmux kill-session -t "$server_name"
        sleep 2
    fi
    echo "Menghapus direktori server: $selected_server_path..."; rm -rf "$selected_server_path"
    echo -e "\n${GREEN}✅ Server '$server_name' telah berhasil dihapus.${NC}"; read -p "Tekan [Enter]..."
}
