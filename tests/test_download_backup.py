"""Run: python tests/test_download_backup.py (Bash and unzip required)."""

from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

REPO = Path(__file__).resolve().parents[1]
assert b"\r\n" not in (REPO / "CreateandInstallBackup.sh").read_bytes()
bash = shutil.which("bash") or str(Path(os.environ["ProgramFiles"]) / "Git/bin/bash.exe")
source, marker, _ = (REPO / "CreateandInstallBackup.sh").read_text(encoding="utf-8").partition(
    "\ncheck_tty\nprepare_directories\n"
)
assert marker

harness = r'''
ST_DIR="$1/SillyTavern"
DATA_DIR="$ST_DIR/data"
BACKUP_DIR="$1/ST-Backups"
scenario="$2"
header() { :; }
pause() { :; }
ensure_download_access() {
    DOWNLOAD_DIR="$test_root/Download"
    [ "$scenario" != denied ]
}
test_root="$1"
ask() {
    case "$2" in
        name) printf -v "$2" '%s' 'my backup';;
        confirm)
            if [ "$scenario" = cancel ]; then
                printf -v "$2" n
            else
                printf -v "$2" y
            fi;;
    esac
}
# Git Bash has unzip but may lack zip. Use real zip when available,
# otherwise generate the same archive with Python for workflow checks.
if ! command -v zip >/dev/null || [ "$scenario" = zip_failure ] || [ "$scenario" = corrupt ]; then
    zip() {
        if [ "$scenario" = zip_failure ]; then return 1; fi
        if [ "$scenario" = corrupt ]; then printf broken > "$2"; return; fi
        "$python_exe" "$test_root/make_zip.py" "$2"
    }
fi
mv() {
    if [ "$scenario" = move_failure ]; then return 1; fi
    command mv "$@"
}
python_exe="$3"
if [ "$scenario" = local ]; then backup_data; else backup_data downloads; fi
get_download_zips
if [ "$scenario" = success ]; then
    [ "${#DOWNLOAD_ZIPS[@]}" -eq 1 ] || exit 1
    validate_backup_zip "${DOWNLOAD_ZIPS[0]}" || exit 1
fi
'''

for scenario in ("success", "overwrite", "cancel", "denied", "zip_failure", "corrupt", "move_failure", "local"):
    with tempfile.TemporaryDirectory(prefix="export check ", dir=REPO / "tests") as temp:
        root = Path(temp).resolve()
        assert root.is_relative_to(REPO / "tests")
        data = root / "SillyTavern/data"
        (data / "chats with spaces").mkdir(parents=True)
        (data / "chats with spaces/chat.jsonl").write_bytes("แชต".encode())
        (data / ".hidden").write_bytes(b"hidden")
        (root / "Download").mkdir()
        target = root / "Download/data-my backup.zip"
        has_old = scenario not in ("success", "denied", "local")
        if has_old:
            target.write_bytes(b"original backup")
        before = {p.relative_to(data).as_posix(): p.read_bytes() for p in data.rglob("*") if p.is_file()}
        (root / "make_zip.py").write_text(
            'from pathlib import Path\nimport sys, zipfile\n'
            'with zipfile.ZipFile(sys.argv[1], "w") as z:\n'
            '    for p in Path("data").rglob("*"):\n'
            '        z.write(p, p.as_posix())\n', encoding="utf-8",
        )
        script = root / "check.sh"
        script.write_text(source + harness, encoding="utf-8", newline="\n")
        result = subprocess.run(
            [bash, script.as_posix(), root.as_posix(), scenario, Path(sys.executable).as_posix()],
            capture_output=True, text=True, encoding="utf-8", timeout=30,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        if scenario in ("success", "overwrite", "local"):
            if scenario == "local":
                target = root / "ST-Backups/my backup.zip"
            with zipfile.ZipFile(target) as archive:
                actual = {n[5:]: archive.read(n) for n in archive.namelist() if not n.endswith("/")}
                assert actual == before
        elif has_old:
            assert target.read_bytes() == b"original backup", result.stdout
        else:
            assert not target.exists()
        assert before == {p.relative_to(data).as_posix(): p.read_bytes() for p in data.rglob("*") if p.is_file()}
        assert not list(root.rglob(".stbackup-export.*"))
        print(f"PASS: {scenario}")
