#!/data/data/com.termux/files/usr/bin/bash

# ===== ตั้งค่า =====
ST_DIR="$HOME/SillyTavern"
EXPORT_DIR="$HOME/storage/downloads/ST-chat-export"

# หา chats folder อัตโนมัติ เช่น data/default-user/chats
CHAT_ROOT="$(find "$ST_DIR/data" \
    -mindepth 2 -maxdepth 2 \
    -type d -name "chats" \
    2>/dev/null | head -n 1)"

if [ -z "$CHAT_ROOT" ]; then
    echo "❌ หาโฟลเดอร์ chats ไม่เจอใน:"
    echo "   $ST_DIR/data"
    exit 1
fi

mkdir -p "$EXPORT_DIR"

echo
echo "📁 Chat root:"
echo "$CHAT_ROOT"
echo
echo "กำลังค้นหาโฟลเดอร์แชท..."
echo

# เก็บเฉพาะ folder ที่มีไฟล์ .jsonl
folders=()

while IFS= read -r -d '' dir; do
    if find "$dir" -maxdepth 1 -type f -name '*.jsonl' -print -quit | grep -q .; then
        folders+=("$dir")
    fi
done < <(
    find "$CHAT_ROOT" \
        -mindepth 1 -maxdepth 1 \
        -type d \
        -print0 | sort -z
)

if [ "${#folders[@]}" -eq 0 ]; then
    echo "❌ ไม่พบโฟลเดอร์ที่มีไฟล์ .jsonl"
    exit 1
fi

# function หาไฟล์ล่าสุด
get_latest_file() {
    local dir="$1"
    local latest=""
    local latest_time=0
    local file
    local mtime

    while IFS= read -r -d '' file; do
        mtime=$(stat -c %Y "$file" 2>/dev/null)

        if [ -n "$mtime" ] && [ "$mtime" -gt "$latest_time" ]; then
            latest_time="$mtime"
            latest="$file"
        fi
    done < <(
        find "$dir" \
            -maxdepth 1 \
            -type f \
            -name '*.jsonl' \
            -print0
    )

    printf '%s' "$latest"
}

# แสดง menu
for i in "${!folders[@]}"; do
    dir="${folders[$i]}"
    latest="$(get_latest_file "$dir")"

    printf "%2d) %s\n" "$((i + 1))" "$(basename "$dir")"

    if [ -n "$latest" ]; then
        printf "    └─ ล่าสุด: %s\n" "$(basename "$latest")"
    fi
done

echo
printf "เลือกหมายเลขโฟลเดอร์: "
read -r choice

# ตรวจเลข
if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "❌ ต้องใส่เป็นตัวเลข"
    exit 1
fi

index=$((choice - 1))

if [ "$index" -lt 0 ] || [ "$index" -ge "${#folders[@]}" ]; then
    echo "❌ ไม่มีตัวเลือกหมายเลข $choice"
    exit 1
fi

selected="${folders[$index]}"
latest="$(get_latest_file "$selected")"

if [ -z "$latest" ]; then
    echo "❌ ไม่พบไฟล์ .jsonl ใน:"
    echo "$selected"
    exit 1
fi

echo
echo "📂 เลือก:"
echo "   $(basename "$selected")"
echo
echo "🕒 ไฟล์ล่าสุด:"
echo "   $(basename "$latest")"
echo

# กันชื่อไฟล์ซ้ำ โดยเติมชื่อ folder ข้างหน้า
folder_name="$(basename "$selected")"
file_name="$(basename "$latest")"

destination="$EXPORT_DIR/${folder_name}__${file_name}"

mv "$latest" "$destination"

if [ $? -eq 0 ]; then
    echo "✅ ย้ายสำเร็จแล้ว"
    echo
    echo "จาก:"
    echo "   $latest"
    echo
    echo "ไปที่:"
    echo "   $destination"
else
    echo "❌ เกิดอาเพศสักอย่าง"
    exit 1
fi
