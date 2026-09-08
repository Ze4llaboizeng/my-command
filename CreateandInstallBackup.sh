#!/data/data/com.termux/files/usr/bin/bash

# =========================================================
# SillyTavern Data Backup Manager for Termux
# Supports interactive use even when started with:
# curl -fsSL URL | bash
# =========================================================

ST_DIR="$HOME/SillyTavern"
DATA_DIR="$ST_DIR/data"

BACKUP_DIR="$HOME/ST-Backups"

TTY="/dev/tty"
TEMP_RESTORE_DIR=""

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
# Cleanup
# =========================================================

cleanup() {
    if [ -n "$TEMP_RESTORE_DIR" ] && [ -d "$TEMP_RESTORE_DIR" ]; then
        rm -rf -- "$TEMP_RESTORE_DIR" 2>/dev/null
    fi
}

trap cleanup EXIT
trap 'echo; echo -e "${YELLOW}ยกเลิกการทำงาน${RESET}"; exit 130' INT TERM

# =========================================================
# Utility
# =========================================================

check_tty() {
    if [ ! -r "$TTY" ]; then
        echo
        echo -e "${RED}✗ ไม่พบ Interactive Terminal (/dev/tty)${RESET}"
        echo
        echo "กรุณารันสคริปต์นี้จาก Termux Terminal โดยตรง"
        echo
        exit 1
    fi
}

ask() {
    local prompt="$1"
    local variable="$2"
    local value=""

    IFS= read -r -p "$prompt" value < "$TTY"
    printf -v "$variable" '%s' "$value"
}

pause() {
    local dummy=""
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

yes_answer() {
    case "$1" in
        y|Y|yes|YES|Yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

no_answer() {
    case "$1" in
        n|N|no|NO|No)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =========================================================
# Dependency Check
# =========================================================

check_dependencies() {
    local missing_packages=()
    local confirm=""

    if ! command -v zip >/dev/null 2>&1; then
        missing_packages+=("zip")
    fi

    if ! command -v unzip >/dev/null 2>&1; then
        missing_packages+=("unzip")
    fi

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

    if no_answer "$confirm"; then
        echo
        echo -e "${RED}✗ ยกเลิกการติดตั้ง${RESET}"
        echo
        echo "สามารถติดตั้งเองภายหลังด้วย:"
        echo
        echo "  pkg install ${missing_packages[*]}"
        echo
        exit 1
    fi

    echo
    echo -e "${CYAN}→ กำลังติดตั้ง ${missing_packages[*]}...${RESET}"
    echo

    if ! command -v pkg >/dev/null 2>&1; then
        echo -e "${RED}✗ ไม่พบคำสั่ง pkg${RESET}"
        echo "สคริปต์นี้ออกแบบมาสำหรับ Termux"
        exit 1
    fi

    if pkg install "${missing_packages[@]}" -y; then
        echo
        echo -e "${GREEN}✓ ติดตั้งสำเร็จ${RESET}"
    else
        echo
        echo -e "${RED}✗ ติดตั้งไม่สำเร็จ${RESET}"
        exit 1
    fi

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

# =========================================================
# SillyTavern Check
# =========================================================

check_st_dir() {
    if [ ! -d "$ST_DIR" ]; then
        echo
        echo -e "${RED}✗ หาโฟลเดอร์ SillyTavern ไม่เจอ${RESET}"
        echo
        echo "ตำแหน่งที่กำลังหา:"
        echo "  $ST_DIR"
        echo
        return 1
    fi

    return 0
}

check_data_dir() {
    if ! check_st_dir; then
        return 1
    fi

    if [ ! -d "$DATA_DIR" ]; then
        echo
        echo -e "${RED}✗ หาโฟลเดอร์ SillyTavern/data ไม่เจอ${RESET}"
        echo
        echo "ตำแหน่งที่กำลังหา:"
        echo "  $DATA_DIR"
        echo
        return 1
    fi

    return 0
}

# =========================================================
# Backup
# =========================================================

backup_data() {
    local name=""
    local zipfile=""
    local confirm=""
    local file_count=""
    local data_size=""

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

    name="${name%.zip}"

    if [ -z "$name" ]; then
        echo
        echo -e "${RED}✗ ชื่อ Backup ห้ามว่าง${RESET}"
        pause
        return
    fi

    if [[ "$name" == *"/"* ]]; then
        echo
        echo -e "${RED}✗ ชื่อ Backup ห้ามมีเครื่องหมาย /${RESET}"
        pause
        return
    fi

    if [ "$name" = "." ] || [ "$name" = ".." ]; then
        echo
        echo -e "${RED}✗ ชื่อ Backup นี้ใช้ไม่ได้${RESET}"
        pause
        return
    fi

    zipfile="$BACKUP_DIR/$name.zip"

    if [ -f "$zipfile" ]; then
        echo
        echo -e "${YELLOW}⚠ มี Backup ชื่อนี้อยู่แล้ว${RESET}"
        echo
        echo "  $zipfile"
        echo

        ask "ต้องการเขียนทับไหม? [y/N]: " confirm

        if ! yes_answer "$confirm"; then
            echo
            echo -e "${YELLOW}ยกเลิกการ Backup${RESET}"
            pause
            return
        fi

        echo
        echo -e "${CYAN}→ กำลังลบ Backup เดิม...${RESET}"
        rm -f -- "$zipfile"
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
    echo -e "${GRAY}  อย่าปิด Termux ระหว่างขั้นตอนนี้${RESET}"
    echo

    if (
        cd "$ST_DIR" &&
        zip -rq "$zipfile" data
    ); then
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
    local file=""
    local basename_file=""
    local size=""

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
# ZIP Validation
# =========================================================

validate_backup_zip() {
    local zipfile="$1"
    local entry=""

    echo -e "${CYAN}→ กำลังตรวจสอบความสมบูรณ์ของ ZIP...${RESET}"

    if ! unzip -tq "$zipfile" >/dev/null 2>&1; then
        echo -e "${RED}✗ ZIP เสียหรืออ่านไม่ได้${RESET}"
        return 1
    fi

    echo -e "${GREEN}✓ ZIP อ่านได้ปกติ${RESET}"

    echo -e "${CYAN}→ กำลังตรวจสอบโครงสร้าง Backup...${RESET}"

    while IFS= read -r entry; do
        case "$entry" in
            data|data/*)
                ;;
            *)
                echo -e "${RED}✗ พบไฟล์นอกโฟลเดอร์ data/${RESET}"
                echo "  $entry"
                echo
                echo "เพื่อความปลอดภัย จะไม่ทำการ Restore"
                return 1
                ;;
        esac

        case "$entry" in
            /*|../*|*/../*|*/..)
                echo -e "${RED}✗ พบ path ที่ไม่ปลอดภัยใน ZIP${RESET}"
                echo "  $entry"
                return 1
                ;;
        esac
    done < <(unzip -Z1 "$zipfile")

    if ! unzip -Z1 "$zipfile" | grep -q '^data/'; then
        echo -e "${RED}✗ Backup นี้ไม่มีโฟลเดอร์ data/${RESET}"
        return 1
    fi

    echo -e "${GREEN}✓ โครงสร้าง Backup ถูกต้อง${RESET}"

    return 0
}

# =========================================================
# Restore Backup
# =========================================================

restore_backup() {
    local choice=""
    local zipfile=""
    local filename=""
    local confirm=""
    local current_size=""
    local backup_size=""
    local old_data=""

    header

    echo -e "${BOLD}Restore SillyTavern Data${RESET}"
    echo "──────────────────────────────────────"
    echo

    if ! check_st_dir; then
        pause
        return
    fi

    mkdir -p "$BACKUP_DIR"

    if ! list_backups; then
        pause
        return
    fi

    echo
    ask "เลือกหมายเลข Backup: " choice

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
    backup_size=$(format_size "$zipfile")

    echo
    echo -e "Backup ที่เลือก : ${CYAN}$filename${RESET}"
    echo -e "ขนาด Backup    : ${CYAN}$backup_size${RESET}"
    echo -e "Restore ไปที่  : ${CYAN}$DATA_DIR${RESET}"
    echo

    if ! validate_backup_zip "$zipfile"; then
        pause
        return
    fi

    TEMP_RESTORE_DIR="$ST_DIR/.stbackup-restore-$$"

    rm -rf -- "$TEMP_RESTORE_DIR" 2>/dev/null
    mkdir -p "$TEMP_RESTORE_DIR"

    echo
    echo -e "${CYAN}→ กำลังเตรียม Backup สำหรับ Restore...${RESET}"
    echo -e "${GRAY}  ตอนนี้ยังไม่ได้แตะ data ปัจจุบัน${RESET}"
    echo

    if ! unzip -q "$zipfile" -d "$TEMP_RESTORE_DIR"; then
        echo -e "${RED}✗ แตก Backup ไปยังพื้นที่ชั่วคราวไม่สำเร็จ${RESET}"
        rm -rf -- "$TEMP_RESTORE_DIR"
        TEMP_RESTORE_DIR=""
        pause
        return
    fi

    if [ ! -d "$TEMP_RESTORE_DIR/data" ]; then
        echo -e "${RED}✗ หลังแตก ZIP ไม่พบโฟลเดอร์ data/${RESET}"
        rm -rf -- "$TEMP_RESTORE_DIR"
        TEMP_RESTORE_DIR=""
        pause
        return
    fi

    echo -e "${GREEN}✓ Backup พร้อมสำหรับ Restore${RESET}"

    if [ -d "$DATA_DIR" ]; then
        current_size=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
    else
        current_size="ไม่มี data ปัจจุบัน"
    fi

    echo
    echo -e "${RED}${BOLD}⚠ คำเตือนก่อน Restore${RESET}"
    echo
    echo "Backup:"
    echo -e "  ${CYAN}$filename${RESET}"
    echo
    echo "Data ปัจจุบัน:"
    echo -e "  ${CYAN}$DATA_DIR${RESET}"
    echo "  ขนาด: $current_size"
    echo
    echo -e "${YELLOW}แนะนำให้ปิด SillyTavern ก่อน Restore${RESET}"
    echo
    echo "เมื่อยืนยัน ระบบจะ:"
    echo "  1) ย้าย data ปัจจุบันไปเก็บชั่วคราว"
    echo "  2) นำ data จาก Backup กลับเข้า SillyTavern"
    echo "  3) ถ้า Restore สำเร็จ จะลบ data เก่าที่พักไว้"
    echo "  4) ถ้ามีปัญหา จะพยายามคืน data เดิมให้อัตโนมัติ"
    echo

    ask "ต้องการ Restore จริง ๆ ไหม? [y/N]: " confirm

    if ! yes_answer "$confirm"; then
        echo
        echo -e "${YELLOW}ยกเลิกการ Restore${RESET}"

        rm -rf -- "$TEMP_RESTORE_DIR"
        TEMP_RESTORE_DIR=""

        pause
        return
    fi

    old_data="$ST_DIR/.data-before-restore-$$"

    rm -rf -- "$old_data" 2>/dev/null

    echo
    echo -e "${CYAN}→ เริ่ม Restore...${RESET}"
    echo

    if [ -d "$DATA_DIR" ]; then
        echo -e "${CYAN}→ กำลังพัก data ปัจจุบันไว้ชั่วคราว...${RESET}"

        if ! mv -- "$DATA_DIR" "$old_data"; then
            echo
            echo -e "${RED}✗ ไม่สามารถย้าย data ปัจจุบันได้${RESET}"
            echo "ยังไม่มีการเปลี่ยนแปลงข้อมูลเดิม"
            rm -rf -- "$TEMP_RESTORE_DIR"
            TEMP_RESTORE_DIR=""
            pause
            return
        fi

        echo -e "${GREEN}✓ พัก data เดิมแล้ว${RESET}"
    fi

    echo
    echo -e "${CYAN}→ กำลังนำ data จาก Backup กลับเข้า SillyTavern...${RESET}"

    if mv -- "$TEMP_RESTORE_DIR/data" "$DATA_DIR"; then
        echo -e "${GREEN}✓ วาง data ใหม่สำเร็จ${RESET}"

        rm -rf -- "$TEMP_RESTORE_DIR"
        TEMP_RESTORE_DIR=""

        if [ -d "$old_data" ]; then
            echo
            echo -e "${CYAN}→ กำลังลบ data เก่าที่พักไว้...${RESET}"
            rm -rf -- "$old_data"
        fi

        echo
        echo -e "${GREEN}${BOLD}✓ Restore สำเร็จ${RESET}"
        echo
        echo -e "Backup  : ${BOLD}$filename${RESET}"
        echo -e "Data    : ${CYAN}$DATA_DIR${RESET}"
        echo -e "ขนาด    : $(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)"
    else
        echo
        echo -e "${RED}${BOLD}✗ Restore ไม่สำเร็จ${RESET}"
        echo
        echo -e "${YELLOW}→ กำลังพยายามคืน data เดิม...${RESET}"

        rm -rf -- "$DATA_DIR" 2>/dev/null

        if [ -d "$old_data" ] && mv -- "$old_data" "$DATA_DIR"; then
            echo -e "${GREEN}✓ คืน data เดิมสำเร็จ${RESET}"
        else
            echo -e "${RED}✗ ไม่สามารถคืน data เดิมให้อัตโนมัติได้${RESET}"
            echo
            echo "Data เดิมอาจยังอยู่ที่:"
            echo "  $old_data"
        fi

        rm -rf -- "$TEMP_RESTORE_DIR" 2>/dev/null
        TEMP_RESTORE_DIR=""
    fi

    pause
}

# =========================================================
# Main Menu
# =========================================================

main_menu() {
    local option=""

    while true; do
        header

        echo -e "${BOLD}เลือกสิ่งที่ต้องการทำ${RESET}"
        echo
        echo -e "  ${GREEN}1)${RESET} 📦 Backup SillyTavern data"
        echo -e "  ${CYAN}2)${RESET} ♻️  Restore Backup"
        echo -e "  ${YELLOW}3)${RESET} 📋 ดูรายการ Backup"
        echo -e "  ${RED}0)${RESET} 🚪 ออก"
        echo
        echo "──────────────────────────────────────"
        echo -e "${GRAY}SillyTavern : $ST_DIR${RESET}"
        echo -e "${GRAY}Data        : $DATA_DIR${RESET}"
        echo -e "${GRAY}Backups     : $BACKUP_DIR${RESET}"
        echo

        ask "เลือก: " option

        case "$option" in
            1)
                backup_data
                ;;

            2)
                restore_backup
                ;;

            3)
                show_backups
                ;;

            0)
                clear 2>/dev/null || true
                echo
                echo -e "${GREEN}ออกจาก SillyTavern Backup Manager แล้ว${RESET}"
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
