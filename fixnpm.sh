 #!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}=======================================${NC}"
echo -e "${CYAN}${BOLD}     SillyTavern - Fix Script          ${NC}"
echo -e "${CYAN}${BOLD}=======================================${NC}"
echo ""
echo -e "  เลือกปัญหาที่พบ:"
echo ""
echo -e "  ${YELLOW}[1]${NC} ERR_MODULE_NOT_FOUND"
echo -e "        (ขึ้น error ตอนรัน ./start.sh)"
echo ""
echo -e "  ${YELLOW}[2]${NC} npm มีปัญหา / npm path not found"
echo -e "        (npm ใช้งานไม่ได้ หรือขึ้น command not found)"
echo ""
echo -e "  ${YELLOW}[3]${NC} Error webpack compilation error"
echo -e "        (ไฟล์แคชพัง, Cannot read properties of undefined)"
echo ""
echo -e "  ${YELLOW}[0]${NC} ออก"
echo ""
read -p "  เลือก (0/1/2/3): " CHOICE < /dev/tty
echo ""

# ─────────────────────────────────────────────
#  Helper functions
# ─────────────────────────────────────────────

goto_sillytavern() {
    echo -e "${YELLOW}[•] เข้าโฟลเดอร์ SillyTavern...${NC}"
    cd ~/SillyTavern || {
        echo -e "${RED}❌ ไม่พบโฟลเดอร์ ~/SillyTavern${NC}"
        exit 1
    }
    echo -e "${GREEN}✅ $(pwd)${NC}"
    echo ""
}

check_npm() {
    NPM_VERSION=$(npm -v 2>/dev/null)
    [ $? -eq 0 ] && [ -n "$NPM_VERSION" ]
}

check_node_modules() {
    # 0 = ปกติ | 1 = ไม่มีโฟลเดอร์ | 2 = มีแต่ไม่สมบูรณ์
    [ ! -d ~/SillyTavern/node_modules ]      && return 1
    [ ! -d ~/SillyTavern/node_modules/.bin ] && return 2
    return 0
}

# ─────────────────────────────────────────────
#  Diagnose — ตรวจหาปัญหาทั้งหมด
# ─────────────────────────────────────────────

run_diagnosis() {
    echo -e "${CYAN}${BOLD}--- ตรวจสอบปัญหาทั้งหมด ---${NC}"
    echo ""

    NEED_FIX_NPM=0
    NEED_FIX_MODULES=0

    # ── npm ──
    echo -e "${YELLOW}[•] ตรวจสอบ npm...${NC}"
    if check_npm; then
        echo -e "${GREEN}  ✅ npm $(npm -v) — ปกติ${NC}"
    else
        NEED_FIX_NPM=1
        echo -e "${RED}  ❌ npm: ใช้งานไม่ได้  [ต้องแก้]${NC}"
    fi
    echo ""

    # ── node_modules ──
    echo -e "${YELLOW}[•] ตรวจสอบ node_modules (~SillyTavern)...${NC}"
    check_node_modules; NM_STATUS=$?
    if [ $NM_STATUS -eq 0 ]; then
        echo -e "${GREEN}  ✅ node_modules — ปกติ${NC}"
    elif [ $NM_STATUS -eq 1 ]; then
        NEED_FIX_MODULES=1
        echo -e "${RED}  ❌ node_modules: ไม่พบโฟลเดอร์  [ต้องแก้]${NC}"
    else
        NEED_FIX_MODULES=1
        echo -e "${RED}  ❌ node_modules: มีแต่ไม่สมบูรณ์  [ต้องแก้]${NC}"
    fi
    echo ""

    # ── สรุปแผน ──
    echo -e "${CYAN}${BOLD}--- สรุปแผนการแก้ไข ---${NC}"
    echo ""
    if [ $NEED_FIX_NPM -eq 0 ] && [ $NEED_FIX_MODULES -eq 0 ]; then
        echo -e "${GREEN}  ✅ ไม่พบปัญหาใดๆ — ระบบดูปกติแล้ว${NC}"
        echo ""
        echo -e "${YELLOW}${BOLD}═══════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}${BOLD}   📌  อยู่ในโฟลเดอร์ SillyTavern แล้ว${NC}"
        echo -e "${YELLOW}${BOLD}═══════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${GREEN}${BOLD}   กรุณารันคำสั่งเปิด SillyTavern เพื่อทำการใช้งาน:${NC}"
        echo ""
        echo -e "        ${CYAN}${BOLD}./start.sh${NC}"
        echo ""
        echo -e "${YELLOW}   (โดยไม่ต้องใส่ cd SillyTavern ซ้ำอีกครั้ง — อยู่ในโฟลเดอร์นี้อยู่แล้ว)${NC}"
        echo ""
        echo -e "${YELLOW}${BOLD}═══════════════════════════════════════════════${NC}"
        echo ""
        exit 0
    fi

    STEP=1
    [ $NEED_FIX_NPM -eq 1 ]     && echo -e "  ${YELLOW}ขั้นที่ $((STEP++))${NC} — แก้ npm (ติดตั้งใหม่ผ่าน yarn)"
    [ $NEED_FIX_MODULES -eq 1 ] && echo -e "  ${YELLOW}ขั้นที่ $((STEP++))${NC} — แก้ node_modules (ลบแล้วติดตั้งใหม่)"
    echo ""
    echo -e "${CYAN}  → จะดำเนินการทั้งหมดโดยอัตโนมัติ${NC}"
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────${NC}"
    echo ""
}

# ─────────────────────────────────────────────
#  Fix npm
# ─────────────────────────────────────────────

fix_npm() {
    echo -e "${CYAN}${BOLD}[แก้ไข] npm${NC}"
    echo ""

    echo -e "${YELLOW}[•] ติดตั้ง yarn...${NC}"
    pkg install yarn -y
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ ติดตั้ง yarn ไม่สำเร็จ — แคปหน้าจอส่งให้ทีมช่วยเหลือ${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ ติดตั้ง yarn สำเร็จ${NC}"
    echo ""

    echo -e "${YELLOW}[•] ใช้ yarn ติดตั้ง npm...${NC}"
    yarn global add npm
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ yarn global add npm ไม่สำเร็จ — แคปหน้าจอส่งให้ทีมช่วยเหลือ${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[•] ตรวจสอบ npm อีกครั้ง...${NC}"
    if ! check_npm; then
        echo -e "${RED}❌ ยังไม่พบ npm — แคปหน้าจอส่งให้ทีมช่วยเหลือ${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ npm $(npm -v) — พร้อมใช้งาน${NC}"
    echo ""
}

# ─────────────────────────────────────────────
#  Fix node_modules
# ─────────────────────────────────────────────

fix_node_modules() {
    echo -e "${CYAN}${BOLD}[แก้ไข] node_modules${NC}"
    echo ""

    echo -e "${YELLOW}[•] ลบ node_modules เก่า...${NC}"
    rm -rf ~/SillyTavern/node_modules
    echo -e "${GREEN}✅ ลบเรียบร้อย${NC}"
    echo ""

    echo -e "${YELLOW}[•] ติดตั้ง dependencies ใหม่ (npm install)...${NC}"
    npm install
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ npm install ไม่สำเร็จ — แคปหน้าจอส่งให้ทีมช่วยเหลือ${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ npm install สำเร็จ${NC}"
    echo ""
}

# ─────────────────────────────────────────────
#  Fix Webpack Cache
# ─────────────────────────────────────────────

fix_webpack() {
    echo -e "${CYAN}${BOLD}[แก้ไข] Webpack Cache Error${NC}"
    echo ""

    echo -e "${YELLOW}[•] ลบโฟลเดอร์แคชของ Webpack...${NC}"
    rm -rf ~/SillyTavern/data/_webpack
    echo -e "${GREEN}✅ ลบแคชเรียบร้อย ระบบจะสร้างใหม่เมื่อรันเซิร์ฟเวอร์${NC}"
    echo ""
}

# ─────────────────────────────────────────────
#  Main fix flow
# ─────────────────────────────────────────────

run_fix() {
    goto_sillytavern
    run_diagnosis

    # แก้ npm ก่อนเสมอ (ถ้าจำเป็น)
    if [ $NEED_FIX_NPM -eq 1 ]; then
        fix_npm
    fi

    # แก้ node_modules ถัดไป (ถ้าจำเป็น)
    if [ $NEED_FIX_MODULES -eq 1 ]; then
        fix_node_modules
    fi

    echo -e "${GREEN}${BOLD}✅ แก้ไขทุกปัญหาเรียบร้อยแล้ว — กำลังรัน SillyTavern...${NC}"
    echo ""
    ./start.sh
}

# ─────────────────────────────────────────────
#  Entry point
# ─────────────────────────────────────────────

case "$CHOICE" in
    1|2) run_fix ;;
    3)
        goto_sillytavern
        fix_webpack
        echo -e "${GREEN}${BOLD}✅ แก้ไขปัญหา Webpack เรียบร้อยแล้ว — กำลังรัน SillyTavern...${NC}"
        echo ""
        ./start.sh
        ;;
    0)   echo -e "${CYAN}ออกจากสคริปต์${NC}"; exit 0 ;;
    *)   echo -e "${RED}❌ ตัวเลือกไม่ถูกต้อง กรุณาเลือก 0, 1, 2 หรือ 3${NC}"; exit 1 ;;
esac
