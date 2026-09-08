#!/data/data/com.termux/files/usr/bin/bash

# =========================================================
# SillyTavern Data Backup Manager for Termux
# =========================================================

ST_DIR="$HOME/SillyTavern"
DATA_DIR="$ST_DIR/data"

BACKUP_DIR="$HOME/ST-Backups"
EXTRACT_DIR="$HOME/ST-Restored"

# ---------- Colors ----------
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

pause() {
    echo
    read -rp "กด Enter เพื่อกลับเมนู..."
}

header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════╗"
    echo "║   SillyTavern Data Backup Manager   ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${RESET}"
}

check_dependencies() {
    local missing_packages=()

    # เช็ก zip
    if ! command -v zip >/dev/null 2>&1; then
        missing_packages+=("zip")
    fi

    # เช็ก unzip
    if ! command -v unzip >/dev/null 2>&1; then
        missing_packages+=("unzip")
    fi

    # ถ้ามีครบแล้ว
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
    read -rp "ต้องการติดตั้งให้อัตโนมัติไหม? [Y/n]: " confirm

    case "$confirm" in
        n|N)
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
                exit 1
            fi
            ;;
    esac

    # เช็กซ้ำหลังติดตั้ง
    for cmd in zip unzip; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo
            echo -e "${RED}✗ ยังไม่พบคำสั่ง $cmd หลังการติดตั้ง${RESET}"
            exit 1
        fi
    done

    echo
    echo -e "${GREEN}✓ Dependency พร้อมใช้งานแล้ว${RESET}"
    sleep 1
}

check_data_dir() {
    if [ ! -d "$DATA_DIR" ]; then
        echo -e "${RED}✗ หาโฟลเดอร์ SillyTavern data ไม่เจอ${RESET}"
        echo
        echo "ตำแหน่งที่กำลังหา:"
        echo "  $DATA_DIR"
        echo
        echo -e "${YELLOW}แก้ค่า ST_DIR ด้านบนของ script ให้ตรงกับที่ติดตั้ง SillyTavern${RESET}"
        return 1
    fi

    return 0
}

format_size() {
    du -h "$1" 2>/dev/null | cut -f1
}

# =========================================================
# Backup
# =========================================================

backup_data() {
    header

    echo -e "${BOLD}สร้าง Backup${RESET}"
    echo "──────────────────────────────────────"
    echo

    check_data_dir || {
        pause
        return
    }

    mkdir -p "$BACKUP_DIR"

    echo -e "Source : ${CYAN}$DATA_DIR${RESET}"
    echo -e "Backup : ${CYAN}$BACKUP_DIR${RESET}"
    echo

    read -rp "ตั้งชื่อ Backup: " name

    # ลบ .zip ถ้า user ใส่มาเอง
    name="${name%.zip}"

    if [ -z "$name" ]; then
        echo
        echo -e "${RED}✗ ชื่อ Backup ห้ามว่าง${RESET}"
        pause
        return
    fi

    # ป้องกันชื่อกลายเป็น path
    if [[ "$name" == *"/"* ]]; then
        echo
        echo -e "${RED}✗ ชื่อ Backup ห้ามมี /${RESET}"
        pause
        return
    fi

    zipfile="$BACKUP_DIR/$name.zip"

    if [ -f "$zipfile" ]; then
        echo
        echo -e "${YELLOW}⚠ มี Backup ชื่อนี้อยู่แล้ว${RESET}"
        echo "  $zipfile"
        echo
        read -rp "เขียนทับไหม? [y/N]: " confirm

        case "$confirm" in
            y|Y)
                rm -f "$zipfile"
                ;;
            *)
                echo
                echo "ยกเลิกการ Backup"
                pause
                return
                ;;
        esac
    fi

    echo
    echo -e "${CYAN}→ กำลังเตรียมไฟล์...${RESET}"

    file_count=$(find "$DATA_DIR" -type f 2>/dev/null | wc -l)
    data_size=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)

    echo "  จำนวนไฟล์ : $file_count"
    echo "  ขนาดข้อมูล : $data_size"
    echo

    echo -e "${CYAN}→ กำลังสร้าง ZIP...${RESET}"
    echo -e "${GRAY}  อาจใช้เวลาสักหน่อยถ้า data อ้วนจนแทบมีเลขประจำตัวประชาชน${RESET}"
    echo

    cd "$ST_DIR" || {
        echo -e "${RED}✗ เข้า SillyTavern directory ไม่ได้${RESET}"
        pause
        return
    }

    if zip -rq "$zipfile" data; then
        echo
        echo -e "${GREEN}✓ Backup สำเร็จ${RESET}"
        echo
        echo -e "ชื่อ       : ${BOLD}$name.zip${RESET}"
        echo -e "ขนาด      : $(format_size "$zipfile")"
        echo -e "ตำแหน่ง   : ${CYAN}$zipfile${RESET}"
    else
        echo
        echo -e "${RED}✗ Backup ไม่สำเร็จ${RESET}"
        rm -f "$zipfile"
    fi

    pause
}

# =========================================================
# List backups
# =========================================================

get_backups() {
    shopt -s nullglob
    BACKUPS=("$BACKUP_DIR"/*.zip)
    shopt -u nullglob
}

list_backups() {
    get_backups

    if [ "${#BACKUPS[@]}" -eq 0 ]; then
        echo -e "${YELLOW}ยังไม่มี Backup${RESET}"
        return 1
    fi

    local i=1

    for file in "${BACKUPS[@]}"; do
        basename_file=$(basename "$file")
        size=$(format_size "$file")

        printf "  ${CYAN}%2d)${RESET} %-35s ${GRAY}%s${RESET}\n" \
            "$i" "$basename_file" "$size"

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
# Extract
# =========================================================

extract_backup() {
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
    read -rp "เลือกหมายเลข Backup: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo
        echo -e "${RED}✗ กรุณาใส่เป็นตัวเลข${RESET}"
        pause
        return
    fi

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

    if [ -d "$destination" ]; then
        echo
        echo -e "${YELLOW}⚠ มีโฟลเดอร์ชื่อนี้อยู่แล้ว${RESET}"
        echo
        read -rp "ลบของเดิมแล้วแตกใหม่ไหม? [y/N]: " confirm

        case "$confirm" in
            y|Y)
                echo
                echo -e "${CYAN}→ กำลังลบโฟลเดอร์เดิม...${RESET}"
                rm -rf -- "$destination"
                ;;
            *)
                echo
                echo "ยกเลิกการแตกไฟล์"
                pause
                return
                ;;
        esac
    fi

    mkdir -p "$destination"

    echo
    echo -e "${CYAN}→ กำลังตรวจสอบ ZIP...${RESET}"

    if ! unzip -tq "$zipfile" >/dev/null 2>&1; then
        echo
        echo -e "${RED}✗ ZIP เสียหรืออ่านไม่ได้${RESET}"
        rm -rf -- "$destination"
        pause
        return
    fi

    echo -e "${GREEN}✓ ZIP ปกติ${RESET}"

    echo
    echo -e "${CYAN}→ กำลังแตกไฟล์...${RESET}"
    echo

    if unzip -q "$zipfile" -d "$destination"; then
        echo
        echo -e "${GREEN}✓ แตกไฟล์สำเร็จ${RESET}"
        echo
        echo -e "Backup    : ${BOLD}$filename${RESET}"
        echo -e "ตำแหน่ง   : ${CYAN}$destination${RESET}"

        if [ -d "$destination/data" ]; then
            echo -e "Data      : ${CYAN}$destination/data${RESET}"
        fi
    else
        echo
        echo -e "${RED}✗ แตกไฟล์ไม่สำเร็จ${RESET}"
        rm -rf -- "$destination"
    fi

    pause
}

# =========================================================
# Main menu
# =========================================================

main_menu() {
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
        echo

        read -rp "เลือก: " option

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
                clear
                echo -e "${GREEN}Bye~ Backup ดี ๆ ล่ะ อย่ารอจน data ระเบิดค่อยนึกถึงมัน 😏${RESET}"
                exit 0
                ;;
            *)
                echo
                echo -e "${RED}✗ เลือก 0-3 สิ เด็กดื้อ${RESET}"
                sleep 1
                ;;
        esac
    done
}

# =========================================================
# Start
# =========================================================

check_dependencies
main_menu
