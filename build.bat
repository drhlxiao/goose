@echo off
REM
REM Build goose on Windows.
REM
REM Builds the Rust backend (goose.exe) and the Electron desktop app.
REM The desktop app spawns the CLI binary it ships with, so the CLI is built and
REM copied into ui\desktop\src\bin before the UI is packaged.
REM
REM Usage:
REM   build.bat [target] [options]
REM
REM Targets:
REM   make      Build distributables (installers/archives) with electron-forge. Default.
REM   installer Build the NSIS installer with electron-builder (requires a prior make).
REM   package   Build an unpacked app bundle (fast, good for local testing).
REM   dev       Build the CLI and start the desktop app in development mode.
REM   cli       Build only the Rust CLI binary.
REM
REM Options:
REM   --debug              Build the CLI in debug mode instead of release.
REM   --skip-cli           Do not rebuild the CLI; reuse the existing build output.
REM   --skip-install       Do not run "pnpm install".
REM   --skip-prepare       Do not run scripts\prepare-platform-binaries.js.
REM   -h, --help           Show this help.
REM
REM Examples:
REM   build.bat                 :: release CLI + distributables
REM   build.bat package         :: release CLI + unpacked app
REM   build.bat dev             :: release CLI + run the app from source
REM   build.bat make --debug    :: debug CLI + distributables
REM
setlocal
cd /d "%~dp0"

set "TARGET=make"
set "BUILD_MODE=release"
set "SKIP_CLI=0"
set "SKIP_INSTALL=0"
set "SKIP_PREPARE=0"
set "TARGET_TRIPLE=x86_64-pc-windows-msvc"

:parse_args
if "%~1"=="" goto after_args
if /i "%~1"=="make"         ( set "TARGET=make"      & shift & goto parse_args )
if /i "%~1"=="installer"    ( set "TARGET=installer" & shift & goto parse_args )
if /i "%~1"=="package"      ( set "TARGET=package"   & shift & goto parse_args )
if /i "%~1"=="dev"          ( set "TARGET=dev"       & shift & goto parse_args )
if /i "%~1"=="cli"          ( set "TARGET=cli"       & shift & goto parse_args )
if /i "%~1"=="--debug"      ( set "BUILD_MODE=debug"   & shift & goto parse_args )
if /i "%~1"=="--release"    ( set "BUILD_MODE=release" & shift & goto parse_args )
if /i "%~1"=="--skip-cli"     ( set "SKIP_CLI=1"     & shift & goto parse_args )
if /i "%~1"=="--skip-install" ( set "SKIP_INSTALL=1" & shift & goto parse_args )
if /i "%~1"=="--skip-prepare" ( set "SKIP_PREPARE=1" & shift & goto parse_args )
if /i "%~1"=="-h"     goto show_help
if /i "%~1"=="--help" goto show_help
echo Unknown argument: %~1
echo.
call :show_help
exit /b 1

:after_args

echo ==^> goose build - target=%TARGET% mode=%BUILD_MODE%

where cargo >nul 2>&1
if errorlevel 1 (
  echo error: cargo not found. Install Rust or run "bin\activate-hermit" first.
  exit /b 1
)

if "%TARGET%"=="cli" (
  call :build_cli
  if errorlevel 1 exit /b 1
  echo ==^> Done: target\%TARGET_TRIPLE%\%BUILD_MODE%\goose.exe
  exit /b 0
)

call :build_cli
if errorlevel 1 exit /b 1
call :build_ui
if errorlevel 1 exit /b 1

echo ==^> Build complete
exit /b 0

REM ---------------------------------------------------------------- functions

:build_cli
if "%SKIP_CLI%"=="1" (
  echo ==^> Skipping CLI build [--skip-cli]
  goto :eof
)

if "%BUILD_MODE%"=="release" (
  echo ==^> Building goose CLI [release, %TARGET_TRIPLE%]
  rustup target add %TARGET_TRIPLE%
  if errorlevel 1 exit /b 1
  cargo build --release --target %TARGET_TRIPLE% -p goose-cli --bin goose
) else (
  echo ==^> Building goose CLI [debug, %TARGET_TRIPLE%]
  rustup target add %TARGET_TRIPLE%
  if errorlevel 1 exit /b 1
  cargo build --target %TARGET_TRIPLE% -p goose-cli --bin goose
)
if errorlevel 1 exit /b 1

set "GOOSE_EXE=target\%TARGET_TRIPLE%\%BUILD_MODE%\goose.exe"
if not exist "%GOOSE_EXE%" (
  echo error: CLI binary not found at %GOOSE_EXE%
  exit /b 1
)

if not exist "ui\desktop\src\bin" mkdir "ui\desktop\src\bin"
REM Remove before copying: overwriting a running executable in place is unsafe.
del /q "ui\desktop\src\bin\goosed.exe" 2>nul
del /q "ui\desktop\src\bin\goose.exe"  2>nul
copy /y "%GOOSE_EXE%" "ui\desktop\src\bin\goose.exe" >nul
if errorlevel 1 (
  echo error: failed to copy CLI binary into ui\desktop\src\bin
  exit /b 1
)
echo ==^> Copied CLI binary to ui\desktop\src\bin\goose.exe
goto :eof

:build_ui
if "%SKIP_INSTALL%"=="1" goto ui_skip_install
where pnpm >nul 2>&1
if errorlevel 1 (
  echo error: pnpm not found. Install pnpm or run "bin\activate-hermit" first.
  exit /b 1
)
echo ==^> Installing desktop dependencies
pushd "ui\desktop"
call pnpm install
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" exit /b %RC%
:ui_skip_install

if "%SKIP_PREPARE%"=="1" goto ui_skip_prepare
echo ==^> Preparing platform binaries
call node "ui\desktop\scripts\prepare-platform-binaries.js"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" exit /b %RC%
:ui_skip_prepare

set "ELECTRON_PLATFORM=win32"

if /i "%TARGET%"=="make"      goto ui_make
if /i "%TARGET%"=="installer" goto ui_installer
if /i "%TARGET%"=="package"   goto ui_package
if /i "%TARGET%"=="dev"       goto ui_dev
goto :eof

:ui_make
echo ==^> Building distributables [electron-forge make]
pushd "ui\desktop"
call pnpm run make --platform=win32 --arch=x64
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" exit /b %RC%
echo ==^> Artifacts are in ui\desktop\out
goto :eof

:ui_installer
echo ==^> Building NSIS installer [electron-builder]
pushd "ui\desktop"
call pnpm run make:win32-installer
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" exit /b %RC%
echo ==^> Installer is in ui\desktop\out
goto :eof

:ui_package
echo ==^> Packaging app [electron-forge package]
pushd "ui\desktop"
call pnpm run package
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" exit /b %RC%
echo ==^> App bundle is in ui\desktop\out
goto :eof

:ui_dev
echo ==^> Starting desktop app in development mode
pushd "ui\desktop"
call pnpm run start-gui
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%

:show_help
echo Build goose on Windows.
echo.
echo Usage:
echo   build.bat [target] [options]
echo.
echo Targets:
echo   make       Build distributables (electron-forge make). Default.
echo   installer  Build the NSIS installer (electron-builder; run "make" first).
echo   package    Build an unpacked app bundle.
echo   dev        Build the CLI and start the desktop app.
echo   cli        Build only the Rust CLI binary.
echo.
echo Options:
echo   --debug        Build the CLI in debug mode.
echo   --skip-cli     Do not rebuild the CLI.
echo   --skip-install Do not run "pnpm install".
echo   --skip-prepare Do not run scripts\prepare-platform-binaries.js.
echo   -h, --help     Show this help.
echo.
echo Examples:
echo   build.bat
echo   build.bat package
echo   build.bat dev
echo   build.bat make --debug
exit /b 0
