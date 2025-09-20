# 🛠️Minecraft Panel

Panel sederhana berbasis **Bash** untuk mengelola server Minecraft di VPS/Linux. dengan integrasi **Java 21, tmux, vnstat, gotop**, dan otomatisasi penuh.

# Support Untuk OS
- Debian 11 ✅
- Debian 12 ✅
- Ubuntu 22 ✅
- Ubuntu 24 ✅

---

## 🚀 Fitur Utama
- **Menu Interaktif**  
  Navigasi mudah untuk semua fungsi.

- **Manajemen Server Minecraft**  
  - Buat server baru dari *egg* (misalnya Paper/PocketMine).  
  - Start, Stop, Restart server dengan `tmux`.  
  - Akses konsol langsung.  
  - Atur RAM secara dinamis.  
  - Konfigurasi file penting (server.properties, spigot.yml, paper.yml, dll).  
  - Jadwal restart otomatis dengan `cron`.

- **Manajemen Pemain**  
  Kick, Ban, Op/Deop, Whitelist langsung dari menu.

- **Monitoring VPS**  
  - CPU, RAM, Disk, Traffic (via `vnstat`).  
  - Monitoring real-time dengan `gotop`.

- **Manajemen Tambahan**  
  - Backup & migrasi.  
  - Pengaturan RAM Swap.  
  - Menu Bot Telegram (opsional).  
  - Cek port & layanan aktif.

---

## 📦 Persyaratan Sistem
- VPS dengan Debian 11/12 atau Ubuntu 22.04/24.04  
- Minimal RAM **2 GB** (disarankan **4 GB+** untuk server Minecraft stabil).  
- Paket yang dibutuhkan:
  - `curl`, `wget`, `git`, `tmux`, `vnstat`, `snapd`  
  - `Java 21 (Oracle JDK)`  

---

## ⚡ Instalasi Otomatis
Jalankan perintah berikut di VPS Anda:

<pre><code></code>sudo apt update && sudo apt install -y curl wget git
git clone https://github.com/azziz1601/minecraft.git mc-panel
cd mc-panel
chmod +x setup.sh
./setup.sh</pre></code>

# 📌 Script akan otomatis:

Menginstal semua dependensi.

Mengatur Java 21 (Oracle JDK).

Menginstal gotop via snap.

Mengatur alias menu → otomatis membuka main.sh.

Menjalankan panel saat login pertama ke VPS.



---

# 🖥️ Cara Penggunaan

Setelah instalasi, cukup jalankan:

menu

Atau login ke VPS, panel akan terbuka otomatis.

Menu utama:

1) Buat Server Baru
2) Kelola Server
3) Hapus Server
4) Manajemen RAM Swap
5) Monitor Sumber Daya (gotop)
6) Cek Port & Layanan
7) Menu Bot Telegram
8) Backup & Migrasi
9) Keluar


---

# 📑 Catatan

File server otomatis dibuat dengan Java 21 + Aikar’s Flags.

eula.txt otomatis diset ke true.

Multi-server didukung (setiap server punya folder & port unik).

Pastikan port yang dipilih tidak konflik dengan layanan lain.



---

# 🤝 Kontribusi

Pull Request dan saran sangat diterima!
