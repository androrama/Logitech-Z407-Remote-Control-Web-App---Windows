@echo off
setlocal EnableDelayedExpansion
title Logitech Z407 Remote Control - Build Assistant Debug Mode

echo ========================================================
echo      Logitech Z407 Remote Control - Build Helper
echo ========================================================
echo.
echo [DEBUG] Script started.
echo [DEBUG] Checking Admin privileges...

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Admin privileges recommended. 
    echo     Please run as Administrator if installation fails.
) else (
    echo [OK] Admin privileges detected.
)
echo.

set "PYTHON_CMD="
set "BUILD_SUCCESS=0"

REM --- 1. CHECK PYTHON IN PATH ---
echo [DEBUG] Checking for 'python' in PATH...
python --version >nul 2>&1
if %errorlevel% equ 0 (
    set "PYTHON_CMD=python"
    echo [OK] Found 'python' command.
    goto :PYTHON_FOUND
)
echo [DEBUG] 'python' command not found.

REM --- 2. CHECK PY LAUNCHER ---
echo [DEBUG] Checking for 'py' launcher...
py --version >nul 2>&1
if %errorlevel% equ 0 (
    set "PYTHON_CMD=py"
    echo [OK] Found 'py' launcher.
    goto :PYTHON_FOUND
)
echo [DEBUG] 'py' launcher not found.

REM --- 3. CHECK STANDARD INSTALL PATHS LINEARLY ---
echo [DEBUG] Checking standard install paths...

if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
    set "PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    set "PATH=%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;!PATH!"
    echo [OK] Found Python 3.12 in AppData.
    goto :PYTHON_FOUND
)

if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" (
    set "PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
    set "PATH=%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python311\Scripts;!PATH!"
    echo [OK] Found Python 3.11 in AppData.
    goto :PYTHON_FOUND
)

if exist "C:\Python312\python.exe" (
    set "PYTHON_CMD=C:\Python312\python.exe"
    set "PATH=C:\Python312;C:\Python312\Scripts;!PATH!"
    echo [OK] Found Python 3.12 in C:\Python312.
    goto :PYTHON_FOUND
)

REM --- NOT FOUND ---
echo.
echo [!] Python is NOT installed or not detected.
echo.
set /p "INSTALL_PY=Would you like to install Python automatically? (Y/N): "
if /i "!INSTALL_PY!" neq "Y" goto :PYTHON_REQUIRED_EXIT

:INSTALL_PYTHON
echo.
echo [*] Attempting install via Winget...
winget source update >nul 2>&1

echo [*] Installing Python 3.12...
winget install --id Python.Python.3.12 --source winget --accept-package-agreements --accept-source-agreements
if %errorlevel% neq 0 (
    echo.
    echo [!] Winget Installation Failed! Error Code: %errorlevel%
    echo     (If code is 1625, it means 'Blocked by Group Policy')
    echo.
    echo [*] Trying fallback: Direct Download...
    powershell -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.12.1/python-3.12.1-amd64.exe' -OutFile 'python_installer.exe'"
    if exist "python_installer.exe" (
        echo [*] Running manual installer...
        start /wait "" "python_installer.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
        del "python_installer.exe"
        echo [OK] Installer finished.
    ) else (
        echo [X] Failed to download installer.
        echo     Please install Python 3.12 manually from python.org
        pause
        exit /b 1
    )
)

echo.
echo [*] verifying installation...
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
    set "PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    set "PATH=%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;!PATH!"
    echo [OK] Python detected after install.
    goto :PYTHON_FOUND
)

REM Fallback check
echo [DEBUG] Fallback PATH check...
call :RefreshEnv
python --version >nul 2>&1
if %errorlevel% equ 0 (
    set "PYTHON_CMD=python"
    echo [OK] Python detected in PATH.
    goto :PYTHON_FOUND
)

echo [!] Python installed but still not detected by script.
echo     Please restart the script or checking your path manually.
pause
exit /b 0

:PYTHON_REQUIRED_EXIT
echo [!] Python is required. Exiting.
pause
exit /b 1

:PYTHON_FOUND
echo.
echo [DEBUG] Using Python: "!PYTHON_CMD!"
echo.

REM --- INSTALL DEPENDENCIES ---
echo [DEBUG] Installing dependencies...
"!PYTHON_CMD!" -m pip install -r requirements.txt
if %errorlevel% neq 0 (
    echo [X] Failed to install dependencies.
    echo     Please check your internet connection.
    pause
    goto :CLEANUP
)
echo [OK] Dependencies installed.

REM --- BUILD ---
echo.
echo [DEBUG] Starting Build Process...

echo [DEBUG] Killing running instances...
REM Try to kill multiple times just in case
taskkill /F /IM "Z407_Control_Windows.exe" >nul 2>&1
timeout /t 1 /nobreak >nul
taskkill /F /IM "Z407_Control_Windows.exe" >nul 2>&1
timeout /t 1 /nobreak >nul

:TRY_DELETE
if exist dist\Z407_Control_Windows.exe (
    echo [DEBUG] Attempting to remove old executable...
    del /f /q dist\Z407_Control_Windows.exe >nul 2>&1
    
    if exist dist\Z407_Control_Windows.exe (
        echo [!] Delete failed. Trying to rename...
        ren dist\Z407_Control_Windows.exe "Z407_Control_Windows_old_%random%.exe" >nul 2>&1
    )

    if exist dist\Z407_Control_Windows.exe (
        echo.
        echo [!] CRITICAL ERROR: Could not delete or move existing executable.
        echo     Path: %CD%\dist\Z407_Control_Windows.exe
        echo.
        echo     Possible causes:
        echo     1. The app is still open.
        echo     2. Antivirus is scanning it.
        echo     3. You need to run this script as Administrator.
        echo.
        echo     ACTION REQUIRED:
        echo     Please manually close the program or delete the file above.
        echo.
        pause
        echo [DEBUG] Retrying...
        goto :TRY_DELETE
    )
)
if exist build rmdir /s /q build

echo [DEBUG] Running PyInstaller (Console Mode)...

REM Convert PNG to ICO if needed
set "ICON_ARG="
if exist icon.png (
    echo [DEBUG] Found icon.png. Checking conversion...
    if not exist icon.ico (
        echo [DEBUG] Converting icon.png to icon.ico...
        "!PYTHON_CMD!" -c "from PIL import Image; img=Image.open('icon.png'); img.save('icon.ico', format='ICO', sizes=[(256, 256)])"
        if errorlevel 1 (
            echo [!] Icon conversion failed. Use 'pip install Pillow' if needed.
        )
    )
)

if exist icon.ico (
    echo [OK] Using custom icon: icon.ico
    set "ICON_ARG=--icon icon.ico"
) else (
    echo [!] No icon.ico found. Building with default icon.
)

"!PYTHON_CMD!" -m PyInstaller --noconfirm --onefile --console --name "Z407_Control_Windows" ^
    !ICON_ARG! ^
    --add-data "templates;templates" ^
    --hidden-import "pyscreeze" ^
    --hidden-import "PIL" ^
    --hidden-import "pyautogui" ^
    --collect-all "quart" ^
    app.py

if %errorlevel% neq 0 (
    echo.
    echo [X] Build Failed!
    set "BUILD_SUCCESS=0"
) else (
    set "BUILD_SUCCESS=1"
    echo.
    echo ========================================================
    echo [OK] BUILD SUCCESS!
    echo Executable: dist\Z407_Control_Windows.exe
    echo ========================================================
)

:CLEANUP
echo.
echo [DEBUG] Reached Cleanup.
if "!BUILD_SUCCESS!"=="0" (
    echo [!] The process failed.
) else (
    echo [OK] Process completed.
)
echo.

set /p "DO_CLEANUP=Do you want to delete the TEMPORARY 'build' folder? (Y/N): "
if /i "!DO_CLEANUP!"=="Y" (
    echo [*] Cleaning up build artifacts...
    echo     (This does NOT uninstall Python, it only removes temp files)
    if exist build rmdir /s /q build
    if exist *.spec del *.spec
    if exist __pycache__ rmdir /s /q __pycache__
    echo [OK] Temporary files removed.
    timeout /t 2 >nul
)

echo.
set /p "UNINSTALL_PYTHON=Do you want to UNINSTALL Python as well? (Y/N): "
if /i "!UNINSTALL_PYTHON!"=="Y" (
    echo.
    echo [*] Uninstalling Python 3.12...
    winget uninstall --id Python.Python.3.12 --accept-source-agreements
    if errorlevel 1 (
         echo [!] Winget uninstall failed or not found.
         echo     Please uninstall Python manually from Control Panel.
    ) else (
         echo [OK] Uninstallation finished.
    )
)

echo.
echo Press any key to exit...
pause >nul
exit /b 0

:RefreshEnv
for /f "tokens=2,*" %%A in ('reg query "HKLM\System\CurrentControlSet\Control\Session Manager\Environment" /v Path') do set "PATH=%%B"
for /f "tokens=2,*" %%A in ('reg query "HKCU\Environment" /v Path') do set "PATH=!PATH!;%%B"
exit /b
