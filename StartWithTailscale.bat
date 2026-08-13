@echo off
setlocal enabledelayedexpansion
pushd %~dp0
title SillyTavern + Tailscale

REM ต้องสลับเป็น UTF-8 ก่อน ไม่งั้นข้อความภาษาไทยจะแสดงเป็นขยะใน cmd
for /f "tokens=2 delims=:" %%c in ('chcp') do set "OLDCP=%%c"
set "OLDCP=%OLDCP: =%"
chcp 65001 >nul

set "CONFIG=%~dp0config.yaml"
set "HELPER=%~dp0st-tailscale-config.ps1"
set "TSCLI="
if exist "%ProgramFiles%\Tailscale\tailscale.exe" set "TSCLI=%ProgramFiles%\Tailscale\tailscale.exe"
if not defined TSCLI if exist "%ProgramFiles(x86)%\Tailscale\tailscale.exe" set "TSCLI=%ProgramFiles(x86)%\Tailscale\tailscale.exe"

echo ================================================================
echo  SillyTavern + Tailscale
echo ================================================================
echo.

if not exist "%CONFIG%" (
    echo [หยุด] ไม่พบ config.yaml
    echo [ทำตอนนี้] เปิด Start.bat หนึ่งครั้งแล้วปิด เพื่อให้ระบบสร้าง config.yaml
    goto end
)

if not exist "%HELPER%" (
    echo [หยุด] ไม่พบ st-tailscale-config.ps1
    echo [ทำตอนนี้] วางไฟล์นี้ไว้ในโฟลเดอร์เดียวกับ StartWithTailscale.bat
    goto end
)

echo [ข้อมูล] โฟลเดอร์: %~dp0
if defined TSCLI (
    for /f "usebackq tokens=*" %%i in (`"%TSCLI%" ip -4 2^>nul`) do (
        if not defined HOSTIP set "HOSTIP=%%i"
    )
)
if defined HOSTIP (
    echo [ข้อมูล] Tailscale IP ของเครื่องนี้: !HOSTIP!
) else (
    echo [สำคัญ] อ่าน Tailscale IP ของเครื่องนี้ไม่ได้ เปิดแอป Tailscale แล้วดูเอง
)

echo.
echo ค่าปัจจุบันใน config.yaml
powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -ConfigPath "%CONFIG%" -Mode show > "%TEMP%\st-ts-show.txt"
if errorlevel 2 (
    type "%TEMP%\st-ts-show.txt"
    goto end
)
findstr /v /b "PORT=" "%TEMP%\st-ts-show.txt"
del "%TEMP%\st-ts-show.txt" >nul 2>&1

echo ================================================================
echo  เลือกสิ่งที่ต้องการทำ
echo ================================================================
echo   1) ตั้งค่าใหม่แบบปลอดภัย  (localhost + IP ที่ระบุ)
echo   2) เพิ่มเครื่อง Client     (เก็บ whitelist เดิมไว้)
echo   3) อนุญาตทุกเครื่องใน Tailnet  (100.64.0.0/10)
echo   4) ข้ามการตั้งค่า เปิด SillyTavern เลย
echo   5) คืนค่า config.yaml จากไฟล์สำรองล่าสุด
echo.

set "PICK="
set /p "PICK=เลือกหมายเลข [1-5]: "

if "%PICK%"=="4" goto launch
if "%PICK%"=="5" goto restore
if "%PICK%"=="3" goto modeall
if "%PICK%"=="2" goto modeadd
if "%PICK%"=="1" goto modereplace

echo [หยุด] กรุณาเลือกเลข 1 ถึง 5
goto end

:modeadd
set "MODE=add"
goto askip

:modereplace
set "MODE=replace"
goto askip

:askip
echo.
echo [ทำตอนนี้] เปิดแอป Tailscale บนเครื่องที่จะใช้เล่น (มือถือ/แท็บเล็ต/เครื่องอื่น)
echo [ทำตอนนี้] ดู IPv4 ของเครื่องนั้น เช่น 100.82.14.53
echo             ใส่หลายเครื่องได้ คั่นด้วยเว้นวรรค
echo.
set "CLIENTIPS="
set /p "CLIENTIPS=Client Tailscale IP: "

if not defined CLIENTIPS (
    echo [หยุด] ยังไม่ได้ใส่ IP จึงไม่มีการแก้ไฟล์
    goto end
)

set "IPARGS=%CLIENTIPS: =,%"
echo.
echo [ข้อมูล] จะบันทึก: %CLIENTIPS%
set "CONFIRM="
set /p "CONFIRM=พิมพ์ APPLY เพื่อยืนยันการแก้ config.yaml: "
if /i not "%CONFIRM%"=="APPLY" (
    echo [ข้อมูล] ยกเลิกแล้ว ไม่มีไฟล์ใดถูกแก้ไข
    goto end
)

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -ConfigPath "%CONFIG%" -Mode %MODE% -Ips %IPARGS%
if errorlevel 1 goto end
goto launch

:modeall
echo.
echo [สำคัญ] โหมดนี้อนุญาตทุกอุปกรณ์ใน Tailnet ของคุณ
echo [สำคัญ] ใช้เฉพาะ Tailnet ส่วนตัวที่ไว้ใจสมาชิกทุกคน
set "CONFIRM="
set /p "CONFIRM=พิมพ์ APPLY เพื่อยืนยัน: "
if /i not "%CONFIRM%"=="APPLY" (
    echo [ข้อมูล] ยกเลิกแล้ว ไม่มีไฟล์ใดถูกแก้ไข
    goto end
)

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -ConfigPath "%CONFIG%" -Mode all
if errorlevel 1 goto end
goto launch

:restore
set "LATEST="
for /f "delims=" %%f in ('dir /b /o-d "%CONFIG%.bak-*" 2^>nul') do (
    if not defined LATEST set "LATEST=%%f"
)
if not defined LATEST (
    echo [หยุด] ไม่พบไฟล์สำรองของ config.yaml
    goto end
)
copy /y "%~dp0!LATEST!" "%CONFIG%" >nul
echo [สำเร็จ] คืนค่าจาก !LATEST! แล้ว
goto end

:launch
for /f "usebackq tokens=2 delims==" %%p in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -ConfigPath "%CONFIG%" -Mode show ^| findstr /b "PORT="`) do set "PORT=%%p"
if not defined PORT set "PORT=8000"

echo.
echo ================================================================
echo  เปิด SillyTavern จากเครื่อง Client ด้วย URL นี้
echo ================================================================
if defined HOSTIP (
    echo    http://!HOSTIP!:!PORT!
) else (
    echo    http://HOST_IP:!PORT!
    echo    ^(แทน HOST_IP ด้วย Tailscale IPv4 ของเครื่องนี้^)
)
echo ================================================================
echo  ใช้ http:// ไม่ใช่ https://   และไม่ต้องเปิด Port Forwarding
echo ================================================================
echo.
echo [ข้อมูล] กำลังเริ่ม SillyTavern  กด Ctrl+C เพื่อหยุด
echo.

set NODE_ENV=production
call npm install --no-save --no-audit --no-fund --loglevel=error --no-progress --omit=dev --ignore-scripts
node server.js %*

:end
echo.
pause

:finish
if defined OLDCP chcp %OLDCP% >nul
popd
endlocal
