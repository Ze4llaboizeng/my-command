"""Run with: python tests/test_restore_backup.py (requires Bash and unzip)."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import zipfile


REPO = Path(__file__).resolve().parents[1]
assert b"\r\n" not in (REPO / "CreateandInstallBackup.sh").read_bytes(), (
    "CreateandInstallBackup.sh must use LF line endings for Termux"
)
bash = shutil.which("bash")
if not bash and os.name == "nt":
    bash = str(Path(os.environ["ProgramFiles"]) / "Git/bin/bash.exe")
assert bash, "Bash is required"

# Load the real functions without starting the interactive menu or installing packages.
source, marker, _ = (REPO / "CreateandInstallBackup.sh").read_text(
    encoding="utf-8"
).partition("\ncheck_tty\nprepare_directories\n")
assert marker, "Could not locate the backup manager entry point"

exercise = r'''
ST_DIR="$1/SillyTavern"
DATA_DIR="$ST_DIR/data"
BACKUP_DIR="$1/ST-Backups"
INSTALLER_BACKUP_ROOT="$1"
wanted="$2"
scenario="$3"
header() { :; }
pause() { :; }
ask() {
    if [ "$2" = choice ]; then
        local i
        for ((i = 0; i < ${#BACKUPS[@]}; i++)); do
            if [ "${BACKUPS[i]##*/}" = "$wanted" ]; then
                printf -v "$2" '%s' "$((i + 1))"
                return
            fi
        done
        exit 1
    else
        if [ "$scenario" = cancel ]; then
            printf -v "$2" '%s' n
        else
            printf -v "$2" '%s' y
        fi
    fi
}
cp() {
    command cp "$@" || return
    # Simulate a copy that fails after writing some staged data.
    [ "$scenario" != copy_failure ]
}
mv() {
    if [ "$scenario" = swap_failure ] && [ "$2" = "$TEMP_RESTORE_DIR/data" ]; then
        return 1
    fi
    command mv "$@"
}
get_backups
[ "${#BACKUPS[@]}" -eq 2 ] || exit 1
[ "${BACKUPS[0]##*/}" = archive.zip ] || exit 1
[ "${BACKUPS[1]##*/}" = SillyTavern_backup_20260910_120000 ] || exit 1
restore_backup
'''


def snapshot(folder):
    return {
        path.relative_to(folder).as_posix(): path.read_bytes()
        for path in folder.rglob("*")
        if path.is_file()
    }


for scenario in ("folder", "zip", "no_current_data", "cancel", "copy_failure", "swap_failure", "cwd"):
    with tempfile.TemporaryDirectory(prefix="restore check ", dir=REPO / "tests") as temp:
        root = Path(temp).resolve()
        # All copy, rename and cleanup operations are confined to this test workspace.
        assert root.is_relative_to(REPO / "tests")
        current = root / "SillyTavern"
        installer = root / "SillyTavern_backup_20260910_120000"
        archives = root / "ST-Backups"
        (current / "data").mkdir(parents=True)
        (installer / "data/chats with spaces").mkdir(parents=True)
        (root / "SillyTavern_backup_without_data").mkdir()
        archives.mkdir()
        (current / "data/new-only.txt").write_text("new installation", encoding="utf-8")
        (current / "data/.hidden").write_text("new hidden", encoding="utf-8")
        (current / "server.js").write_text("new server", encoding="utf-8")
        (current / "config.yaml").write_text("new config", encoding="utf-8")
        (installer / "data/.hidden").write_text("backup hidden", encoding="utf-8")
        (installer / "data/chats with spaces/chat.jsonl").write_text("แชตเดิม", encoding="utf-8")
        (installer / "server.js").write_text("old server", encoding="utf-8")
        (installer / "config.yaml").write_text("old config", encoding="utf-8")
        with zipfile.ZipFile(archives / "archive.zip", "w") as archive:
            for file in (installer / "data").rglob("*"):
                if file.is_file():
                    archive.write(file, file.relative_to(installer).as_posix())
        expected = snapshot(installer / "data")
        original_backup = snapshot(installer)
        original_data = snapshot(current / "data")
        if scenario == "no_current_data":
            shutil.rmtree(current / "data")

        if scenario == "cwd":
            exercise_for_scenario = exercise.replace(
                'INSTALLER_BACKUP_ROOT="$1"',
                'INSTALLER_BACKUP_ROOT="$1/missing"\ncd "$1/SillyTavern_backup_20260910_120000"',
            )
        else:
            exercise_for_scenario = exercise

        selected = "archive.zip" if scenario == "zip" else installer.name
        harness = root / "restore-check.sh"
        harness.write_text(source + exercise_for_scenario, encoding="utf-8", newline="\n")
        result = subprocess.run(
            [bash, harness.as_posix(), root.as_posix(), selected, scenario],
            capture_output=True, text=True, encoding="utf-8", timeout=30,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        restored = scenario in ("folder", "zip", "no_current_data", "cwd")
        assert snapshot(current / "data") == (expected if restored else original_data), result.stdout
        assert snapshot(installer) == original_backup
        assert (current / "server.js").read_text() == "new server"
        assert (current / "config.yaml").read_text() == "new config"
        assert sorted(path.name for path in current.iterdir()) == ["config.yaml", "data", "server.js"]
        assert "[install.sh b / data]" in result.stdout
        print(f"PASS: {scenario}")
