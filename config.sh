#!/bin/bash

# --- KONFIGURASI PATH ---
# Menentukan direktori utama tempat skrip ini berada
BASE_DIR=$(cd "$(dirname "$0")" && pwd)

# Mendefinisikan sub-direktori penting
SERVERS_DIR="$BASE_DIR/servers"
EGGS_DIR="$BASE_DIR/eggs"
FUNCTIONS_DIR="$BASE_DIR/functions"

# --- KONFIGURASI WARNA ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color
