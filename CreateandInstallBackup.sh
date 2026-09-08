#!/data/data/com.termux/files/usr/bin/bash

# =========================================================
# SillyTavern Data Backup Manager for Termux
# Supports: curl -fsSL URL | bash
# =========================================================

ST_DIR="$HOME/SillyTavern"
DATA_DIR="$ST_DIR/data"

BACKUP_DIR="$HOME/ST-Backups"
EXTRACT_DIR="$HOME/ST-Restored"

TTY="/dev/tty"

# =========================================================
# Colors
# =========================================================

RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
GRAY="\033[0;90m"

# =========================================================
# Utility
# =========================================================

check_tty() {
    if [ ! -r "$TTY" ]; then
        echo
        echo -e "${RED}✗ ไม่พบ Interactive Terminal (/dev/tty)${RESET}"
        echo
        echo "สคริปต์นี้ต้องรันจาก Termux Terminal โดยตรง"
        echo
        exit 1
    fi
}

ask() {
    local prompt="$1"
    local variable="$2"
    local value

    IFS= read -r -p "$prompt" value < "$TTY"

    printf -v "$variable" '%s' "$value"
}

pause() {
    local dummy

    echo
    ask "กด Enter เพื่อกลับเมนู..." dummy
}

header() {
    clear 2>/dev/null || printf '\033[2J\033[H'

    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════╗"
    echo "║   SillyTavern Data Backup Manager   ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${RESET}"
}

format_size() {
    du -h "$1" 2>/dev/null | cut -f1
}

# =========================================================
# Dependency Check
# =========================================================

check_dependencies() {
    local missing_packages=()
    local confirm

    if ! command -v zip >/dev/null 2>&1; then
        missing_packages+=("zip")
    fi

    if ! command -v unzip >/dev/null 2>&1; then
        missing_packages+=("unzip")
    fi

    # ทุกอย่างมีครบแล้ว
    if [ "${#missing_packages[@]}" -eq 0 ]; then
        return 0
    fi

    echo
    echo -e "${YELLOW}⚠ พบว่าโปรแกรมที่จำเป็นยังติดตั้งไม่ครบ${RESET}"
    echo

    for pkg in "${missing_packages[@]}"; do
        echo -e "  ${RED}✗${RESET} $pkg"
    done

    echo
    ask "ต้องการติดตั้งให้อัตโนมัติไหม? [Y/n]: " confirm

    case "$confirm" in
        n|N|no|NO|No)
            echo
            echo -e "${RED}✗ ยกเลิกการติดตั้ง${RESET}"
            echo
            echo "สามารถติดตั้งเองภายหลังด้วย:"
            echo
            echo "pkg install ${missing_packages[*]}"
            echo
            exit 1
            ;;

        *)
            echo
            echo -e "${CYAN}→ กำลังติดตั้ง ${missing_packages[*]}...${RESET}"
            echo

            if pkg install "${missing_packages[@]}" -y; then
                echo
                echo -e "${GREEN}✓ ติดตั้งสำเร็จ${RESET}"
            else
                echo
                echo -e "${RED}✗ ติดตั้งไม่สำเร็จ${RESET}"
                echo
                exit 1
            fi
            ;;
    esac

    # เช็กซ้ำหลังติดตั้ง
    for cmd in zip unzip; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo
            echo -e "${RED}✗ ยังไม่พบคำสั่ง $cmd หลังการติดตั้ง${RESET}"
            echo
            exit 1
        fi
    done

    echo
    echo -e "${GREEN}✓ Dependency พร้อมใช้งานแล้ว${RESET}"

    sleep 1
}

# =========================================================
# SillyTavern Data Check
# =========================================================

check_data_dir() {
    if [ ! -d "$DATA_DIR" ]; then
        echo
        echo -e "${RED}✗ หาโฟลเดอร์ SillyTavern data ไม่เจอ${RESET}"
        echo
        echo "ตำแหน่งที่กำลังหา:"
        echo
        echo "  $DATA_DIR"
        echo
        echo -e "${YELLOW}กรุณาตรวจสอบว่าติดตั้ง SillyTavern อยู่ที่:${RESET}"
        echo
        echo "  $ST_DIR"
        echo

        return 1
    fi

    return 0
}

# =========================================================
# Backup
# =========================================================

backup_data() {
    local name
    local zipfile
    local confirm
    local file_count
    local data_size

    header

    echo -e "${BOLD}สร้าง Backup${RESET}"
    echo "──────────────────────────────────────"
    echo

    if ! check_data_dir; then
        pause
        return
    fi

    mkdir -p "$BACKUP_DIR"

    echo -e "Source : ${CYAN}$DATA_DIR${RESET}"
    echo -e "Backup : ${CYAN}$BACKUP_DIR${RESET}"
    echo

    ask "ตั้งชื่อ Backup: " name

    # ลบ .zip ออกถ้า user ใส่มาเอง
    name="${name%.zip}"

    # เช็กชื่อว่าง
    if [ -z "$name" ]; then
        echo
        echo -e "${RED}✗ ชื่อ Backup ห้ามว่าง${RESET}"

        pause
        return
    fi

    # ป้องกัน user ใส่ path
    if [[ "$name" == *"/"* ]]; then
        echo
        echo -e "${RED}✗ ชื่อ Backup ห้ามมีเครื่องหมาย /${RESET}"

        pause
        return
    fi

    # ป้องกัน . และ ..
    if [ "$name" = "." ] || [ "$name" = ".." ]; then
        echo
        echo -e "${RED}✗ ชื่อ Backup นี้ใช้ไม่ได้${RESET}"

        pause
        return
    fi

    zipfile="$BACKUP_DIR/$name.zip"

    # เช็กชื่อซ้ำ
    if [ -f "$zipfile" ]; then
        echo
        echo -e "${YELLOW}⚠ มี Backup ชื่อนี้อยู่แล้ว${RESET}"
        echo
        echo "  $zipfile"
        echo

        ask "ต้องการเขียนทับไหม? [y/N]: " confirm

        case "$confirm" in
            y|Y|yes|YES|Yes)
                echo
                echo -e "${CYAN}→ กำลังลบ Backup เดิม...${RESET}"

                rm -f -- "$zipfile"
                ;;

            *)
                echo
                echo -e "${YELLOW}ยกเลิกการ Backup${RESET}"

                pause
                return
                ;;
        esac
    fi

    echo
    echo -e "${CYAN}→ กำลังตรวจสอบข้อมูล...${RESET}"
    echo

    file_count=$(find "$DATA_DIR" -type f 2>/dev/null | wc -l)
    data_size=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)

    echo "  จำนวนไฟล์ : $file_count"
    echo "  ขนาดข้อมูล : $data_size"

    echo
    echo -e "${CYAN}→ กำลังสร้าง ZIP...${RESET}"
    echo
    echo -e "${GRAY}กรุณารอสักครู่ อย่าเพิ่งปิด Termux กลางทาง${RESET}"
    echo

    if ! cd "$ST_DIR"; then
        echo
        echo -e "${RED}✗ ไม่สามารถเข้าโฟลเดอร์ SillyTavern ได้${RESET}"

        pause
        return
    fi

    if zip -rq "$zipfile" data; then
        echo
        echo -e "${GREEN}✓ Backup สำเร็จ${RESET}"
        echo
        echo -e "ชื่อ      : ${BOLD}$name.zip${RESET}"
        echo -e "ขนาด     : $(format_size "$zipfile")"
        echo -e "ตำแหน่ง  : ${CYAN}$zipfile${RESET}"
    else
        echo
        echo -e "${RED}✗ Backup ไม่สำเร็จ${RESET}"

        rm -f -- "$zipfile"
    fi

    pause
}

# =========================================================
# Backup List
# =========================================================

get_backups() {
    shopt -s nullglob

    BACKUPS=("$BACKUP_DIR"/*.zip)

    shopt -u nullglob
}

list_backups() {
    local i=1
    local file
    local basename_file
    local size

    get_backups

    if [ "${#BACKUPS[@]}" -eq 0 ]; then
        echo -e "${YELLOW}ยังไม่มี Backup${RESET}"

        return 1
    fi

    for file in "${BACKUPS[@]}"; do
        basename_file=$(basename "$file")
        size=$(format_size "$file")

        printf \
            "  ${CYAN}%2d)${RESET} %-35s ${GRAY}%s${RESET}\n" \
            "$i" \
            "$basename_file" \
            "$size"

        ((i++))
    done

    return 0
}

show_backups() {
    header

    echo -e "${BOLD}รายการ Backup${RESET}"
    echo "──────────────────────────────────────"
    echo

    mkdir -p "$BACKUP_DIR"

    list_backups

    echo
    echo -e "${GRAY}Folder: $BACKUP_DIR${RESET}"

    pause
}

# =========================================================
# Extract Backup
# =========================================================

extract_backup() {
    local choice
    local zipfile
    local filename
    local name
    local destination
    local confirm

    header

    echo -e "${BOLD}แตก Backup${RESET}"
    echo "──────────────────────────────────────"
    echo

    mkdir -p "$BACKUP_DIR"
    mkdir -p "$EXTRACT_DIR"

    if ! list_backups; then
        pause
        return
    fi

    echo
    ask "เลือกหมายเลข Backup: " choice

    # เช็กว่าเป็นตัวเลข
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo
        echo -e "${RED}✗ กรุณาใส่เป็นตัวเลข${RESET}"

        pause
        return
    fi

    # เช็กช่วงตัวเลข
    if (( choice < 1 || choice > ${#BACKUPS[@]} )); then
        echo
        echo -e "${RED}✗ ไม่มี Backup หมายเลขนี้${RESET}"

        pause
        return
    fi

    zipfile="${BACKUPS[$((choice - 1))]}"

    filename=$(basename "$zipfile")
    name="${filename%.zip}"

    destination="$EXTRACT_DIR/$name"

    echo
    echo -e "เลือกแล้ว : ${CYAN}$filename${RESET}"
    echo -e "แตกไปที่ : ${CYAN}$destination${RESET}"

    # ถ้ามี folder เดิมอยู่แล้ว
    if [ -d "$destination" ]; then
        echo
        echo -e "${YELLOW}⚠ มีโฟลเดอร์ชื่อนี้อยู่แล้ว${RESET}"
        echo
        echo "  $destination"
        echo

        ask "ลบของเดิมแล้วแตกใหม่ไหม? [y/N]: " confirm

        case "$confirm" in
            y|Y|yes|YES|Yes)
                echo
                echo -e "${CYAN}→ กำลังลบโฟลเดอร์เดิม...${RESET}"

                rm -rf -- "$destination"
                ;;

            *)
                echo
                echo -e "${YELLOW}ยกเลิกการแตกไฟล์${RESET}"

                pause
                return
                ;;
        esac
    fi

    echo
    echo -e "${CYAN}→ กำลังตรวจสอบ ZIP...${RESET}"
    echo

    if ! unzip -tq "$zipfile" >/dev/null 2>&1; then
        echo -e "${RED}✗ ZIP เสียหรืออ่านไม่ได้${RESET}"

        pause
        return
    fi

    echo -e "${GREEN}✓ ZIP ปกติ${RESET}"

    mkdir -p "$destination"

    echo
    echo -e "${CYAN}→ กำลังแตกไฟล์...${RESET}"
    echo
    echo -e "${GRAY}กรุณารอสักครู่ อย่าปิด Termux ระหว่างแตกไฟล์${RESET}"
    echo

    if unzip -q "$zipfile" -d "$destination"; then
        echo
        echo -e "${GREEN}✓ แตกไฟล์สำเร็จ${RESET}"
        echo
        echo -e "Backup   : ${BOLD}$filename${RESET}"
        echo -e "ตำแหน่ง  : ${CYAN}$destination${RESET}"

        if [ -d "$destination/data" ]; then
            echo -e "Data     : ${CYAN}$destination/data${RESET}"
        fi
    else
        echo
        echo -e "${RED}✗ แตกไฟล์ไม่สำเร็จ${RESET}"

        rm -rf -- "$destination"
    fi

    pause
}

# =========================================================
# Main Menu
# =========================================================

main_menu() {
    local option

    while true; do
        header

        echo -e "${BOLD}เลือกสิ่งที่ต้องการทำ${RESET}"
        echo

        echo -e "  ${GREEN}1)${RESET} 📦 Backup SillyTavern data"
        echo -e "  ${CYAN}2)${RESET} 📂 แตก Backup"
        echo -e "  ${YELLOW}3)${RESET} 📋 ดูรายการ Backup"
        echo -e "  ${RED}0)${RESET} 🚪 ออก"

        echo
        echo "──────────────────────────────────────"

        echo -e "${GRAY}SillyTavern : $ST_DIR${RESET}"
        echo -e "${GRAY}Backups     : $BACKUP_DIR${RESET}"
        echo -e "${GRAY}Extract     : $EXTRACT_DIR${RESET}"

        echo

        ask "เลือก: " option

        case "$option" in
            1)
                backup_data
                ;;

            2)
                extract_backup
                ;;

            3)
                show_backups
                ;;

            0)
                clear 2>/dev/null || true

                echo
                echo -e "${GREEN}Bye~ Backup ให้ดีล่ะ อย่ารอจน data หายแล้วค่อยวิ่งมาร้อง 😏${RESET}"
                echo

                exit 0
                ;;

            *)
                echo
                echo -e "${RED}✗ กรุณาเลือก 0 - 3${RESET}"

                sleep 1
                ;;
        esac
    done
}

# =========================================================
# Start
# =========================================================

check_tty
check_dependencies
main_menu