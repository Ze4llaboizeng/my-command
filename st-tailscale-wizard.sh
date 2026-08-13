#!/usr/bin/env bash
# SillyTavern + Tailscale Setup Wizard
# รองรับ Windows PC ผ่าน Git Bash / WSL, Android ผ่าน Termux, Linux และ macOS

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="3.2.0"
ST_DIR_OVERRIDE=""
START_STYLE="inline"
RUN_INSTALL="auto"
ST_DIR=""
CONFIG=""
HOST_IP_RESULT=""
CLIENT_IPS_RESULT=()
TEMP_FILES=()

supports_color() {
  [[ -t 1 ]] || return 1
  [[ -z "${NO_COLOR:-}" ]] || return 1
}

if supports_color; then
  RESET=$'\033[0m'
  BOLD=$'\033[1m'
  BLUE=$'\033[1;34m'
  YELLOW=$'\033[1;33m'
  PURPLE=$'\033[1;35m'
  RED=$'\033[1;31m'
  GREEN=$'\033[1;32m'
  GRAY=$'\033[0;37m'
else
  RESET=""
  BOLD=""
  BLUE=""
  YELLOW=""
  PURPLE=""
  RED=""
  GREEN=""
  GRAY=""
fi

line() {
  printf '%s\n' '----------------------------------------------------------------'
}

banner() {
  printf '\n'
  line
  printf '%s%s%s\n' "$BOLD" "$*" "$RESET"
  line
}

title()    { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }
info()     { printf '%s[ข้อมูล]%s %s\n' "$BLUE" "$RESET" "$*"; }
action()   { printf '%s[ทำตอนนี้]%s %s\n' "$YELLOW" "$RESET" "$*"; }
choice()   { printf '%s[เลือก]%s %s\n' "$PURPLE" "$RESET" "$*"; }
danger()   { printf '%s[สำคัญ]%s %s\n' "$RED" "$RESET" "$*" >&2; }
done_msg() { printf '%s[สำเร็จ]%s %s\n' "$GREEN" "$RESET" "$*"; }
muted()    { printf '%s%s%s\n' "$GRAY" "$*" "$RESET"; }
fail()     { printf '%s[หยุด]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<TXT
SillyTavern + Tailscale Setup Wizard v${VERSION}

วิธีใช้:
  bash sillytavern-tailscale-wizard.sh [ตัวเลือก] [คำสั่ง]

ตัวอย่าง:
  bash sillytavern-tailscale-wizard.sh
  bash sillytavern-tailscale-wizard.sh --dir "/path/to/SillyTavern" wizard
  bash sillytavern-tailscale-wizard.sh --dir "/path/to/SillyTavern" status

คำสั่ง:
  wizard      เริ่มตัวช่วยตั้งค่า (ค่าเริ่มต้น)
  status      ดูสถานะและ URL โดยไม่ถามคำถาม
  start       เริ่ม SillyTavern
  restore     คืน config.yaml จากแบ็กอัปล่าสุด
  help        แสดงวิธีใช้

ตัวเลือก:
  --dir PATH  ระบุโฟลเดอร์ SillyTavern (รับ /mnt/d/... หรือ D:\\... ก็ได้)
  --inline    แสดง log ของ SillyTavern ในเทอร์มินัลนี้ (ค่าเริ่มต้น)
  --window    เปิด Start.bat ในหน้าต่าง cmd ของ Windows แยกออกไป
  --install   บังคับรัน npm install ก่อนเริ่ม
  --no-install
              ข้าม npm install
  --no-color  ปิดสี
  -V, --version
              แสดงเวอร์ชัน
  -h, --help  แสดงวิธีใช้
TXT
}

cleanup_temp_files() {
  local file
  for file in "${TEMP_FILES[@]}"; do
    [[ -n "$file" ]] && rm -f -- "$file" 2>/dev/null || true
  done
}
trap cleanup_temp_files EXIT

register_temp_file() {
  TEMP_FILES+=("$1")
}

init_user_io() {
  # ใช้ /dev/tty โดยตรง เพื่อให้ Wizard ยังรอคีย์บอร์ดแม้สคริปต์ถูกส่งผ่าน pipe
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    if { exec 3</dev/tty 4>/dev/tty; } 2>/dev/null; then
      return 0
    fi
  fi

  if [[ -t 0 ]]; then
    exec 3<&0 4>&2
    return 0
  fi

  fail "Wizard ต้องรันใน Terminal ที่รับคีย์บอร์ดได้ กรุณาบันทึกไฟล์แล้วรันด้วย bash ชื่อไฟล์.sh"
}

read_user() {
  local target_var="$1" prompt="$2" value=""
  printf '%s' "$prompt" >&4
  if ! IFS= read -r value <&3; then
    printf '\n' >&4
    fail "ไม่ได้รับคำตอบจากผู้ใช้ (อาจกด Ctrl+D หรือ Terminal ปิด input)"
  fi
  printf -v "$target_var" '%s' "$value"
}

is_termux() {
  [[ "${PREFIX:-}" == *"com.termux"* ]] || [[ "$(uname -o 2>/dev/null || true)" == "Android" ]]
}

is_windows_bash() {
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
  [[ -n "${WSL_INTEROP:-}" ]] && return 0
  grep -qi 'microsoft' /proc/version 2>/dev/null
}

# true = ไดเรกทอรีอยู่บนดิสก์ของ Windows (/mnt/c, /mnt/d ...) ที่มองเห็นจาก WSL
is_windows_mount() {
  [[ "$1" == /mnt/[a-zA-Z]/* ]]
}

platform_name() {
  if is_termux; then
    printf 'Android / Termux'
  elif is_windows_bash; then
    printf 'Windows / Git Bash'
  elif is_wsl; then
    printf 'Windows / WSL (%s)' "${WSL_DISTRO_NAME:-wsl}"
  else
    printf '%s' "$(uname -s 2>/dev/null || printf 'Unix')"
  fi
}

# คืน path ของ node.exe ฝั่ง Windows เพื่อรัน ST ที่ติดตั้งบนไดรฟ์ Windows
find_windows_node() {
  local candidate
  for candidate in \
    "/mnt/c/Program Files/nodejs/node.exe" \
    "/mnt/c/Program Files (x86)/nodejs/node.exe" \
    "${LOCALAPPDATA_WSL:-/mnt/c/Users}"/*/AppData/Local/Programs/nodejs/node.exe \
    "/mnt/c/Users"/*/scoop/apps/nodejs/current/node.exe; do
    [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done

  if command -v node.exe >/dev/null 2>&1; then
    command -v node.exe
    return 0
  fi

  return 1
}

find_cmd_exe() {
  local candidate
  for candidate in /mnt/c/Windows/System32/cmd.exe /mnt/c/Windows/system32/cmd.exe; do
    [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done

  if command -v cmd.exe >/dev/null 2>&1; then
    command -v cmd.exe
    return 0
  fi

  return 1
}

# โฟลเดอร์ที่ทั้ง WSL และ Windows มองเห็นตรงกัน สำหรับวางไฟล์ช่วยรัน
windows_temp_dir() {
  local dir
  for dir in /mnt/c/Users/*/AppData/Local/Temp; do
    if [[ -d "$dir" && -w "$dir" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done

  if [[ -d /mnt/c/Windows/Temp && -w /mnt/c/Windows/Temp ]]; then
    printf '%s\n' /mnt/c/Windows/Temp
    return 0
  fi

  # สำรองสุดท้าย ใช้โฟลเดอร์ ST เพราะ Windows เข้าถึงได้แน่นอน
  printf '%s\n' "$ST_DIR"
}

to_windows_path() {
  if command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$1" 2>/dev/null && return 0
  fi
  printf '%s\n' "$1"
}

script_dir() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
}

looks_like_st_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  [[ -f "$dir/package.json" ]] || return 1
  [[ -f "$dir/start.sh" || -f "$dir/Start.bat" || -f "$dir/server.js" ]] || return 1
}

normalize_dir_input() {
  local raw="$1"

  # รับ path แบบ Windows (D:\Runbot\SillyTavern) แล้วแปลงเป็น /mnt/d/... เมื่ออยู่ใน WSL
  if [[ "$raw" =~ ^[A-Za-z]:[\\/] ]]; then
    if command -v wslpath >/dev/null 2>&1; then
      wslpath -u "$raw" 2>/dev/null && return 0
    fi
    local drive rest
    drive="${raw:0:1}"
    drive="${drive,,}"
    rest="${raw:2}"
    rest="${rest//\\//}"
    printf '/mnt/%s%s\n' "$drive" "$rest"
    return 0
  fi

  printf '%s\n' "$raw"
}

resolve_st_dir() {
  local candidates=() dir

  [[ -n "$ST_DIR_OVERRIDE" ]] && candidates+=("$(normalize_dir_input "$ST_DIR_OVERRIDE")")
  candidates+=("$(script_dir)" "$PWD")
  [[ -n "${HOME:-}" ]] && candidates+=("$HOME/SillyTavern")

  if is_wsl; then
    # จุดติดตั้งยอดนิยมของ ST ฝั่ง Windows เมื่อสั่งงานจาก WSL
    candidates+=(
      "/mnt/d/Runbot/SillyTavern"
      "/mnt/d/SillyTavern"
      "/mnt/c/SillyTavern"
    )
    for dir in /mnt/c/Users/*/SillyTavern /mnt/d/*/SillyTavern; do
      [[ -d "$dir" ]] && candidates+=("$dir")
    done
  fi

  for dir in "${candidates[@]}"; do
    if looks_like_st_dir "$dir"; then
      cd -- "$dir" >/dev/null 2>&1
      pwd -P
      return 0
    fi
  done

  fail "หาโฟลเดอร์ SillyTavern ไม่เจอ วางสคริปต์ไว้ข้าง Start.bat/start.sh หรือใช้ --dir PATH"
}

require_config() {
  [[ -f "$CONFIG" ]] || {
    danger "ยังไม่พบ config.yaml"
    action "รัน SillyTavern หนึ่งครั้ง แล้วปิด ก่อนเปิด Wizard ใหม่"
    exit 1
  }
}

timestamp() {
  date '+%Y%m%d-%H%M%S'
}

backup_config() {
  require_config
  local base backup number

  base="${CONFIG}.bak-$(timestamp)"
  backup="$base"
  number=1

  while [[ -e "$backup" ]]; do
    backup="${base}-${number}"
    ((number++))
  done

  cp -p -- "$CONFIG" "$backup"
  done_msg "สำรอง config.yaml แล้ว"
  muted "  ไฟล์: $(basename "$backup")"
}

disable_legacy_whitelist() {
  local legacy="$ST_DIR/whitelist.txt"

  if [[ -f "$legacy" ]]; then
    local base renamed number
    base="${legacy}.disabled-$(timestamp)"
    renamed="$base"
    number=1

    while [[ -e "$renamed" ]]; do
      renamed="${base}-${number}"
      ((number++))
    done

    mv -- "$legacy" "$renamed"
    danger "พบ whitelist.txt ซึ่งมีสิทธิ์ทับค่าใน config.yaml"
    info "เปลี่ยนชื่อเก็บไว้แล้ว: $(basename "$renamed")"
  fi
}

validate_ipv4() {
  local ip="$1" a b c d extra number

  IFS='.' read -r a b c d extra <<< "$ip"
  [[ -z "${extra:-}" ]] || return 1
  [[ -n "${a:-}" && -n "${b:-}" && -n "${c:-}" && -n "${d:-}" ]] || return 1

  for number in "$a" "$b" "$c" "$d"; do
    [[ "$number" =~ ^[0-9]{1,3}$ ]] || return 1
    ((10#$number >= 0 && 10#$number <= 255)) || return 1
  done
}

is_tailscale_ipv4() {
  local ip="$1" a b c d

  validate_ipv4 "$ip" || return 1
  IFS='.' read -r a b c d <<< "$ip"
  ((10#$a == 100 && 10#$b >= 64 && 10#$b <= 127))
}

validate_tailscale_ips() {
  local ip

  if (($# == 0)); then
    danger "ยังไม่ได้ใส่ Tailscale IP"
    return 1
  fi

  for ip in "$@"; do
    if ! is_tailscale_ipv4 "$ip"; then
      danger "IP '$ip' ไม่อยู่ในช่วง Tailscale 100.64.0.0/10"
      return 1
    fi
  done
}

unique_lines() {
  awk 'NF && !seen[$0]++'
}

extract_whitelist() {
  require_config
  local output status

  if output="$(awk '
    BEGIN { inside=0; found=0 }
    {
      sub(/\r$/, "")

      if ($0 ~ /^whitelist:[[:space:]]*/) {
        found=1
        rest=$0
        sub(/^whitelist:[[:space:]]*/, "", rest)

        if (rest == "") {
          inside=1
          next
        }

        if (rest ~ /^\[[^]]*\][[:space:]]*(#.*)?$/) {
          sub(/[[:space:]]*#.*$/, "", rest)
          sub(/^\[/, "", rest)
          sub(/\]$/, "", rest)
          count=split(rest, values, ",")
          for (i=1; i<=count; i++) {
            value=values[i]
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^"|"$/, "", value)
            gsub(/^\047|\047$/, "", value)
            if (length(value)) print value
          }
          exit
        }

        exit 2
      }

      if (inside) {
        if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
          line=$0
          sub(/^[[:space:]]*-[[:space:]]*/, "", line)
          sub(/[[:space:]]+#.*$/, "", line)
          gsub(/^"|"$/, "", line)
          gsub(/^\047|\047$/, "", line)
          if (length(line)) print line
          next
        }
        if ($0 ~ /^[^[:space:]-]/) exit
      }
    }
  ' "$CONFIG")"; then
    printf '%s\n' "$output"
    return 0
  else
    status=$?
    if ((status == 2)); then
      danger "อ่าน whitelist เดิมไม่ได้ เพราะรูปแบบ YAML ไม่รองรับอย่างปลอดภัย"
      action "เปลี่ยน whitelist ให้เป็นรายการแบบ '- IP' แล้วลองใหม่"
    else
      danger "อ่าน whitelist เดิมไม่สำเร็จ"
    fi
    return "$status"
  fi
}

rewrite_config() {
  require_config
  (($# > 0)) || fail "ไม่มีรายการ whitelist สำหรับบันทึก"

  local entries_file temp_file
  entries_file="$(mktemp "${TMPDIR:-/tmp}/st-whitelist.XXXXXX")"
  temp_file="$(mktemp "${CONFIG}.tmp.XXXXXX")"
  register_temp_file "$entries_file"
  register_temp_file "$temp_file"

  printf '%s\n' "$@" | unique_lines > "$entries_file"

  # รักษา permission เดิมเท่าที่ระบบอนุญาต ก่อนเขียนเนื้อหาใหม่ลงไฟล์ชั่วคราว
  cp -p -- "$CONFIG" "$temp_file" 2>/dev/null || cp -- "$CONFIG" "$temp_file"

  if ! awk -v listfile="$entries_file" '
    function print_whitelist(line) {
      print "whitelist:"
      while ((getline line < listfile) > 0) print "  - " line
      close(listfile)
    }

    BEGIN {
      found_listen=0
      found_mode=0
      found_whitelist=0
      skip_old_whitelist=0
    }

    {
      sub(/\r$/, "")

      if (skip_old_whitelist) {
        if ($0 ~ /^[^[:space:]-]/) skip_old_whitelist=0
        else next
      }

      if ($0 ~ /^listen:[[:space:]]*/) {
        print "listen: true"
        found_listen=1
        next
      }

      if ($0 ~ /^whitelistMode:[[:space:]]*/) {
        print "whitelistMode: true"
        found_mode=1
        next
      }

      if ($0 ~ /^whitelist:[[:space:]]*/) {
        print_whitelist()
        found_whitelist=1
        skip_old_whitelist=1
        next
      }

      print
    }

    END {
      if (!found_listen) {
        print ""
        print "listen: true"
      }
      if (!found_mode) print "whitelistMode: true"
      if (!found_whitelist) print_whitelist()
    }
  ' "$CONFIG" > "$temp_file"; then
    fail "เขียน config.yaml ชั่วคราวไม่สำเร็จ ไฟล์จริงยังไม่ถูกแทนที่"
  fi

  [[ -s "$temp_file" ]] || fail "ไฟล์ config.yaml ที่สร้างใหม่ว่างเปล่า จึงยกเลิกเพื่อความปลอดภัย"
  mv -- "$temp_file" "$CONFIG"
  rm -f -- "$entries_file"
}

find_tailscale_cli() {
  local candidate

  if command -v tailscale >/dev/null 2>&1; then
    command -v tailscale
    return 0
  fi

  if command -v tailscale.exe >/dev/null 2>&1; then
    command -v tailscale.exe
    return 0
  fi

  for candidate in \
    "/c/Program Files/Tailscale/tailscale.exe" \
    "/c/Program Files (x86)/Tailscale/tailscale.exe" \
    "/mnt/c/Program Files/Tailscale/tailscale.exe" \
    "/mnt/c/Program Files (x86)/Tailscale/tailscale.exe"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

get_host_tailscale_ip() {
  is_termux && return 1

  local cli output first_ip
  cli="$(find_tailscale_cli)" || return 1
  output="$("$cli" ip -4 2>/dev/null)" || return 1
  first_ip="$(printf '%s\n' "$output" | tr -d '\r' | awk 'NF { print; exit }')"

  [[ -n "$first_ip" ]] || return 1
  printf '%s\n' "$first_ip"
}

get_port() {
  require_config
  local port

  port="$(awk '
    /^port:[[:space:]]*/ {
      sub(/\r$/, "")
      value=$0
      sub(/^port:[[:space:]]*/, "", value)   # เหลือเฉพาะค่า
      sub(/[[:space:]]*#.*$/, "", value)     # ตัดคอมเมนต์ท้ายบรรทัด
      gsub(/[[:space:]]|"|\047/, "", value)
      if (value ~ /^[0-9]+$/) print value
      exit
    }
  ' "$CONFIG")"

  printf '%s\n' "${port:-8000}"
}

resolve_host_ip() {
  local allow_prompt="${1:-false}" detected_ip="" entered_ip=""
  HOST_IP_RESULT=""

  if detected_ip="$(get_host_tailscale_ip 2>/dev/null)" && is_tailscale_ipv4 "$detected_ip"; then
    HOST_IP_RESULT="$detected_ip"
    return 0
  fi

  [[ "$allow_prompt" == "true" ]] || return 1

  action "เปิดแอป Tailscale บนเครื่อง Host" >&2
  action "ดู IPv4 ของเครื่องนี้ เช่น 100.101.24.17" >&2

  while true; do
    read_user entered_ip "Host Tailscale IP (กด Enter เพื่อข้าม): "

    if [[ -z "$entered_ip" ]]; then
      return 1
    fi

    if is_tailscale_ipv4 "$entered_ip"; then
      HOST_IP_RESULT="$entered_ip"
      return 0
    fi

    danger "Host IP ต้องอยู่ในช่วง Tailscale 100.64.0.0/10"
    muted "ลองใหม่ หรือกด Enter เพื่อข้าม"
  done
}

print_connection_url() {
  local allow_prompt="${1:-false}" port host_ip
  port="$(get_port)"

  banner "เปิด SillyTavern จากเครื่อง Client"

  if resolve_host_ip "$allow_prompt"; then
    host_ip="$HOST_IP_RESULT"
    info "Host Tailscale IP: $host_ip"
    done_msg "เปิด URL ด้านล่างจากเครื่อง Client"
    printf '\n'
    line
    printf '  %shttp://%s:%s%s\n' "$BOLD" "$host_ip" "$port" "$RESET"
    line
  else
    action "แทน HOST_IP ด้วย Tailscale IPv4 ของเครื่อง Host"
    printf '\n'
    line
    printf '  %shttp://HOST_IP:%s%s\n' "$BOLD" "$port" "$RESET"
    line
  fi

  printf '\n'
  danger "ใช้ http:// ไม่ใช่ https://"
  danger "ไม่ต้องเปิด Port Forwarding"
}

print_config_summary() {
  require_config
  awk '
    BEGIN { inside=0 }
    {
      sub(/\r$/, "")
      if ($0 ~ /^(listen|whitelistMode|port):[[:space:]]*/) print "  " $0
      if ($0 ~ /^whitelist:[[:space:]]*$/) {
        print "  " $0
        inside=1
        next
      }
      if (inside) {
        if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
          print "  " $0
          next
        }
        if ($0 ~ /^[^[:space:]-]/) inside=0
      }
    }
  ' "$CONFIG"
}

show_status() {
  require_config
  banner "สถานะปัจจุบัน"
  info "Host: $(platform_name)"
  info "โฟลเดอร์: $ST_DIR"
  printf '\n'
  line
  print_config_summary
  line

  # status เป็นคำสั่งดูข้อมูล จึงไม่ควรถาม input เพิ่ม
  print_connection_url false
}

# ST ที่ติดตั้งบนไดรฟ์ Windows ต้องรันด้วย node ของ Windows
# เพราะ node_modules ถูก build ไว้สำหรับ Windows และพอร์ตต้องเปิดบน network stack ของ Windows
# ไม่ใช่ใน netns ของ WSL (ไม่งั้น client ที่ต่อผ่าน Tailscale จะเข้าไม่ถึง)
should_use_windows_node() {
  is_wsl && is_windows_mount "$ST_DIR"
}

ensure_windows_dependencies() {
  local cmd_exe="$1" win_dir

  [[ "$RUN_INSTALL" == "never" ]] && return 0

  if [[ "$RUN_INSTALL" == "auto" && -d "$ST_DIR/node_modules" ]]; then
    muted "  พบ node_modules แล้ว จึงข้าม npm install"
    return 0
  fi

  win_dir="$(to_windows_path "$ST_DIR")"
  action "ติดตั้ง dependencies ด้วย npm (ฝั่ง Windows)"
  muted "  โฟลเดอร์: $win_dir"

  # cmd.exe /c รับคำสั่งเป็นสตริงเดียว การซ้อน \" ชั้นในทำให้ path เพี้ยน
  # จึงใช้ pushd/popd และส่ง path เป็น argument แยก เพื่อเลี่ยงปัญหา quoting
  (
    cd -- "$ST_DIR" || exit 1
    "$cmd_exe" /d /c npm install --no-save --no-audit --no-fund \
      --loglevel=error --no-progress --omit=dev --ignore-scripts
  ) || danger "npm install ไม่สำเร็จ จะลองเปิด SillyTavern ต่อไป"
}

start_windows_console() {
  local cmd_exe win_dir runner runner_win launcher launcher_win
  cmd_exe="$(find_cmd_exe)" || fail "ไม่พบ cmd.exe จึงเปิดหน้าต่าง Windows ให้ไม่ได้"
  win_dir="$(to_windows_path "$ST_DIR")"

  # เครื่องหมายคำพูดจะถูกตัดเมื่อส่ง argument ข้ามจาก WSL ไป cmd.exe
  # จึงเขียนเป็นไฟล์ .cmd สองชั้น เพื่อให้ cmd แปลคำสั่งเองทั้งหมด
  # วางไว้ใน TEMP ของ Windows เพื่อไม่ให้ไฟล์ชั่วคราวไปโผล่ใน repo ของ SillyTavern
  local helper_dir
  helper_dir="$(windows_temp_dir)"
  runner="$helper_dir/st-wizard-run.cmd"
  launcher="$helper_dir/st-wizard-launch.cmd"
  runner_win="$(to_windows_path "$runner")"

  {
    printf '@echo off\r\n'
    printf 'title SillyTavern\r\n'
    printf 'cd /d "%s"\r\n' "$win_dir"
    printf 'call Start.bat\r\n'
  } > "$runner"

  {
    printf '@echo off\r\n'
    printf 'start "SillyTavern" cmd /k call "%s"\r\n' "$runner_win"
  } > "$launcher"

  launcher_win="$(to_windows_path "$launcher")"

  action "เปิด Start.bat ในหน้าต่าง cmd ของ Windows"
  muted "  log จะแสดงในหน้าต่างใหม่ ปิดหน้าต่างนั้นเพื่อหยุด SillyTavern"

  # ปิด stdio และปล่อยให้หน้าต่างลูกทำงานต่อ ไม่งั้น bash จะค้างรอ process ลูกจบ
  (
    cd -- "$ST_DIR" || exit 1
    "$cmd_exe" /d /c "$launcher_win" </dev/null >/dev/null 2>&1 &
  )

  sleep 2
  done_msg "สั่งเปิดแล้ว"
  muted "  หน้าต่างใหม่จะแสดง log ของ SillyTavern"
}

start_sillytavern() {
  cd -- "$ST_DIR"

  if is_termux && command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock >/dev/null 2>&1 || true
    info "เปิด Termux wake lock แล้ว"
  fi

  banner "กำลังเริ่ม SillyTavern"

  if should_use_windows_node; then
    if [[ "$START_STYLE" == "window" ]]; then
      [[ -f "$ST_DIR/Start.bat" ]] || fail "ไม่พบ Start.bat จึงเปิดหน้าต่างแยกไม่ได้"
      start_windows_console
      return 0
    fi

    local node_exe cmd_exe
    node_exe="$(find_windows_node)" || fail "ไม่พบ node.exe ของ Windows กรุณาติดตั้ง Node.js บน Windows ก่อน (หรือใช้ --window)"
    info "Node (Windows): $node_exe"

    if cmd_exe="$(find_cmd_exe)"; then
      ensure_windows_dependencies "$cmd_exe"
    else
      muted "  ไม่พบ cmd.exe จึงข้ามขั้น npm install"
    fi

    action "เปิด server.js ด้วย node.exe และแสดง log ในหน้าต่างนี้"
    muted "  กด Ctrl+C เพื่อหยุด SillyTavern"
    printf '\n'
    # ต้อง export ก่อน เพราะ prefix assignment ไม่ส่งต่อผ่าน exec (special builtin)
    # และต้องลงทะเบียนใน WSLENV ไม่งั้นตัวแปรจะไม่ข้ามไปยัง process ฝั่ง Windows
    export NODE_ENV=production
    if is_wsl; then
      case ":${WSLENV:-}:" in
        *":NODE_ENV:"*|*":NODE_ENV/"*) ;;
        *) export WSLENV="${WSLENV:+$WSLENV:}NODE_ENV" ;;
      esac
    fi
    exec "$node_exe" server.js
  fi

  if is_windows_bash && [[ -f "$ST_DIR/Start.bat" ]]; then
    action "เปิด Start.bat"
    exec cmd.exe /c Start.bat
  fi

  if [[ -f "$ST_DIR/start.sh" ]]; then
    action "เปิด start.sh"
    exec bash "$ST_DIR/start.sh"
  fi

  if [[ -f "$ST_DIR/server.js" ]]; then
    command -v node >/dev/null 2>&1 || fail "พบ server.js แต่ไม่พบคำสั่ง node"
    action "เปิด server.js ด้วย Node.js"
    exec node "$ST_DIR/server.js"
  fi

  fail "ไม่พบ Start.bat, start.sh หรือ server.js"
}

restore_latest() {
  require_config
  local latest

  latest="$(ls -1t "${CONFIG}".bak-* 2>/dev/null | head -n 1 || true)"
  [[ -n "$latest" ]] || fail "ไม่พบไฟล์สำรอง config.yaml"

  cp -p -- "$latest" "$CONFIG"
  done_msg "คืนค่าจาก $(basename "$latest") แล้ว"
  show_status
}

ask_menu() {
  local target_var="$1" prompt="$2" answer="" number item max
  shift 2

  while true; do
    printf '\n' >&4
    choice "$prompt" >&4
    number=1

    for item in "$@"; do
      printf '  %s%d)%s %s\n' "$PURPLE" "$number" "$RESET" "$item" >&4
      ((number++))
    done

    max=$((number - 1))
    read_user answer "เลือกหมายเลข [1-${max}]: "

    if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= max)); then
      printf -v "$target_var" '%s' "$answer"
      return 0
    fi

    danger "กรุณาเลือกเลข 1 ถึง ${max}"
  done
}

ask_yes_no() {
  local prompt="$1" answer=""

  while true; do
    read_user answer "$prompt [y/n]: "
    case "$answer" in
      y|Y|yes|YES|Yes|ใช่|ช|1) return 0 ;;
      n|N|no|NO|No|ไม่|ม|0) return 1 ;;
      *) danger "กรุณาพิมพ์ y หรือ n" ;;
    esac
  done
}

ask_client_ips() {
  local entered="" old_ifs="$IFS"
  local values=()
  CLIENT_IPS_RESULT=()

  action "เปิด Tailscale บนเครื่อง Client" >&4
  action "คัดลอก IPv4 ของ Client เช่น 100.82.14.53" >&4
  muted "ใส่หลายเครื่องได้ โดยคั่นแต่ละ IP ด้วยเว้นวรรค" >&4

  while true; do
    read_user entered "Client Tailscale IP: "

    IFS=$' \t\n'
    read -r -a values <<< "$entered"
    IFS="$old_ifs"

    if validate_tailscale_ips "${values[@]}"; then
      CLIENT_IPS_RESULT=("${values[@]}")
      return 0
    fi

    muted "กรุณาตรวจ IP แล้วลองอีกครั้ง" >&4
  done
}

wizard() {
  require_config
  init_user_io

  if [[ -t 4 ]]; then
    clear 2>/dev/null || true
  fi

  banner "SillyTavern + Tailscale Setup Wizard v${VERSION}"
  info "อ่านทีละขั้น ระบบจะไม่แก้ไฟล์จนกว่าจะพิมพ์ APPLY"

  banner "ขั้น 1/5  ตรวจเครื่อง Host"
  done_msg "พบ SillyTavern"
  info "ระบบ: $(platform_name)"
  info "โฟลเดอร์: $ST_DIR"

  local operation="" mode="" client_type="" type_number="" confirmation="" ip=""
  local existing_text=""
  local ips=() existing=()

  banner "ขั้น 2/5  เลือกงาน"
  ask_menu operation "ต้องการทำอะไร?" \
    "ตั้งค่าใหม่แบบปลอดภัย" \
    "เพิ่มเครื่อง Client" \
    "อนุญาตทุกเครื่องใน Tailnet"

  case "$operation" in
    1) mode="replace" ;;
    2) mode="add" ;;
    3) mode="all" ;;
  esac

  if [[ "$mode" != "all" ]]; then
    banner "ขั้น 3/5  ระบุเครื่อง Client"

    ask_menu type_number "เครื่องที่ใช้เปิด SillyTavern คืออะไร?" \
      "Android" \
      "iPad / iPhone" \
      "PC / Mac" \
      "หลายเครื่อง / อื่น ๆ"

    case "$type_number" in
      1) client_type="Android" ;;
      2) client_type="iPad / iPhone" ;;
      3) client_type="PC / Mac" ;;
      4) client_type="หลายเครื่อง / อื่น ๆ" ;;
    esac

    ask_client_ips
    ips=("${CLIENT_IPS_RESULT[@]}")
  else
    banner "ขั้น 3/5  ตรวจความเสี่ยง"
    danger "โหมดนี้อนุญาตทุกอุปกรณ์ใน Tailnet"
    danger "ใช้เฉพาะ Tailnet ส่วนตัวที่ไว้ใจสมาชิกทุกคน"
    action "หากไม่แน่ใจ ให้ตอบ n แล้วเลือกแบบปลอดภัย"

    if ! ask_yes_no "ยืนยันใช้โหมดกว้างหรือไม่?"; then
      info "ยกเลิกแล้ว ไม่มีไฟล์ใดถูกแก้ไข"
      exit 0
    fi
  fi

  banner "ขั้น 4/5  ตรวจสรุปก่อนบันทึก"
  info "Host: $(platform_name)"

  if [[ "$mode" == "all" ]]; then
    danger "การเข้าถึง: ทุกอุปกรณ์ใน Tailnet (100.64.0.0/10)"
  else
    info "ประเภท Client: $client_type"
    for ip in "${ips[@]}"; do
      info "Client IP: $ip"
    done

    if [[ "$mode" == "replace" ]]; then
      info "การทำงาน: แทนที่ whitelist เดิม"
    else
      info "การทำงาน: เพิ่มเข้า whitelist เดิม"
    fi
  fi

  printf '\n' >&4
  action "พิมพ์ APPLY เพื่อยืนยันการแก้ config.yaml" >&4
  read_user confirmation "> "

  if [[ "$confirmation" != "APPLY" ]]; then
    info "ยกเลิกแล้ว ไม่มีไฟล์ใดถูกแก้ไข"
    exit 0
  fi

  banner "ขั้น 5/5  สำรองและบันทึก"
  backup_config

  case "$mode" in
    replace)
      rewrite_config "::1" "127.0.0.1" "${ips[@]}"
      ;;
    add)
      if ! existing_text="$(extract_whitelist)"; then
        fail "ยกเลิกการเพิ่ม Client เพื่อป้องกัน whitelist เดิมสูญหาย"
      fi

      while IFS= read -r ip; do
        [[ -n "$ip" ]] && existing+=("$ip")
      done <<< "$existing_text"

      rewrite_config "::1" "127.0.0.1" "${existing[@]}" "${ips[@]}"
      ;;
    all)
      rewrite_config "::1" "127.0.0.1" "100.64.0.0/10"
      ;;
  esac

  disable_legacy_whitelist
  done_msg "ตั้งค่าเรียบร้อย"
  muted "หากต้องย้อนกลับ ใช้คำสั่ง restore"

  print_connection_url true

  printf '\n' >&4
  if ask_yes_no "เริ่ม SillyTavern ตอนนี้หรือไม่?"; then
    start_sillytavern
  else
    banner "จบการตั้งค่า"
    action "เริ่มภายหลังด้วยคำสั่ง:"
    printf '  %sbash "%s" --dir "%s" start%s\n' \
      "$BOLD" "$ST_DIR/$(basename "$0")" "$ST_DIR" "$RESET"
  fi
}

while (($#)); do
  case "$1" in
    --dir)
      (($# >= 2)) || fail "--dir ต้องตามด้วย path"
      ST_DIR_OVERRIDE="$2"
      shift 2
      ;;
    --inline)
      START_STYLE="inline"
      shift
      ;;
    --window|--new-window)
      START_STYLE="window"
      shift
      ;;
    --install)
      RUN_INSTALL="always"
      shift
      ;;
    --no-install)
      RUN_INSTALL="never"
      shift
      ;;
    --no-color)
      RESET=""
      BOLD=""
      BLUE=""
      YELLOW=""
      PURPLE=""
      RED=""
      GREEN=""
      GRAY=""
      shift
      ;;
    -V|--version)
      printf '%s\n' "$VERSION"
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

command_name="${1:-wizard}"
[[ $# -gt 0 ]] && shift || true

case "$command_name" in
  help)
    usage
    exit 0
    ;;
  wizard|status|start|restore)
    ;;
  *)
    usage
    fail "ไม่รู้จักคำสั่ง: $command_name"
    ;;
esac

(($# == 0)) || fail "พบ argument ที่ไม่รองรับ: $*"

ST_DIR="$(resolve_st_dir)"
CONFIG="$ST_DIR/config.yaml"

case "$command_name" in
  wizard) wizard ;;
  status) show_status ;;
  start) start_sillytavern ;;
  restore) restore_latest ;;
esac
