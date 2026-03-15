@echo off
setlocal enabledelayedexpansion
title Xissin App Updater
color 0A

:: ============================================================
::  XISSIN APP UPDATER
::  Guides you through every step of releasing a new version
:: ============================================================

set "PUBSPEC=C:\Users\Nathaniel\Desktop\xissin-monorepo\app\pubspec.yaml"
set "REPO=C:\Users\Nathaniel\Desktop\xissin-monorepo"

:: BUG FIX 1: Wrong URL — your admin is on Streamlit Cloud, not Railway
set "ADMIN_URL=https://xissin-panel.streamlit.app"

:: ── Read current version from pubspec.yaml ──────────────────
for /f "tokens=2 delims=: " %%a in ('findstr /i "^version:" "%PUBSPEC%"') do (
    set "CURRENT_VERSION_FULL=%%a"
)

:: Split version and build number (e.g. 1.0.0+1 → 1.0.0 and 1)
for /f "tokens=1,2 delims=+" %%a in ("!CURRENT_VERSION_FULL!") do (
    set "CURRENT_VERSION=%%a"
    set "CURRENT_BUILD=%%b"
)

:: ============================================================
cls
echo.
echo  +==================================================+
echo  ^|           XISSIN APP UPDATER v1.0               ^|
echo  +==================================================+
echo.
echo  Current App Version : v!CURRENT_VERSION!
echo  Current Build Number: !CURRENT_BUILD!
echo.
echo  ==================================================
echo.
echo  This tool will guide you through:
echo  [1] Update pubspec.yaml version
echo  [2] Confirm Admin Panel update
echo  [3] Confirm Min Version update (optional)
echo  [4] Git add, commit, push
echo  [5] Create and push version tag (triggers build)
echo.
echo  ==================================================
echo.
pause
goto STEP1

:: ============================================================
:STEP1
cls
echo.
echo  +==================================================+
echo  ^|   STEP 1 of 5 -- Update pubspec.yaml version    ^|
echo  +==================================================+
echo.
echo  Current version: v!CURRENT_VERSION! (Build !CURRENT_BUILD!)
echo.
echo  Version naming guide:
echo  +--------------------------------------------------+
echo  ^|  Bug fix only      --^> 1.0.0 becomes 1.0.1      ^|
echo  ^|  New feature added --^> 1.0.0 becomes 1.1.0      ^|
echo  ^|  Major redesign    --^> 1.0.0 becomes 2.0.0      ^|
echo  +--------------------------------------------------+
echo.
set /p "NEW_VERSION=  Enter new version (e.g. 1.0.1): "

if "!NEW_VERSION!"=="" (
    echo.
    echo  ERROR: Version cannot be empty! Please try again.
    echo.
    pause
    goto STEP1
)

if "!NEW_VERSION!"=="!CURRENT_VERSION!" (
    echo.
    echo  WARNING: That is the same as the current version!
    echo  Please enter a different version number.
    echo.
    pause
    goto STEP1
)

set /a "NEW_BUILD=!CURRENT_BUILD!+1"

echo.
echo  --------------------------------------------------
echo  Summary of changes:
echo     Version : v!CURRENT_VERSION! --^> v!NEW_VERSION!
echo     Build   : !CURRENT_BUILD! --^> !NEW_BUILD!
echo  --------------------------------------------------
echo.
set /p "CONFIRM=  Confirm? (Y/N): "
if /i "!CONFIRM!" neq "Y" goto STEP1

:: BUG FIX 2: The + sign in version string (1.0.0+1) breaks PowerShell replace.
:: We must escape it properly using a temp variable approach.
set "OLD_VER_FULL=!CURRENT_VERSION!+!CURRENT_BUILD!"
set "NEW_VER_FULL=!NEW_VERSION!+!NEW_BUILD!"

powershell -Command "(Get-Content '%PUBSPEC%') -replace [regex]::Escape('!OLD_VER_FULL!'), '!NEW_VER_FULL!' | Set-Content '%PUBSPEC%'"

echo.
echo  pubspec.yaml updated successfully!
echo  version: !NEW_VERSION!+!NEW_BUILD!
echo.
pause
goto STEP2

:: ============================================================
:STEP2
cls
echo.
echo  +==================================================+
echo  ^|   STEP 2 of 5 -- Update Admin Panel (Latest)    ^|
echo  +==================================================+
echo.
echo  You need to update the Latest App Version in your
echo  Admin Panel so users get the update notification.
echo.
echo  +--------------------------------------------------+
echo  ^|  Field to update: latest_app_version            ^|
echo  ^|  Set it to:       !NEW_VERSION!                 ^|
echo  +--------------------------------------------------+
echo.
echo  Opening Admin Panel now...
start "" "!ADMIN_URL!"
echo.
echo  --------------------------------------------------
echo  Steps in Admin Panel:
echo   1. Go to Settings page
echo   2. Change latest_app_version to: !NEW_VERSION!
echo   3. Click Save
echo  --------------------------------------------------
echo.
:STEP2_CONFIRM
set /p "DONE2=  Have you updated latest_app_version? (Y/N): "
if /i "!DONE2!" equ "Y" goto STEP3
if /i "!DONE2!" equ "N" (
    echo.
    echo  WARNING: Please update it before continuing!
    echo  Opening Admin Panel again...
    start "" "!ADMIN_URL!"
    echo.
    goto STEP2_CONFIRM
)
echo  ERROR: Please type Y or N only.
goto STEP2_CONFIRM

:: ============================================================
:STEP3
cls
echo.
echo  +==================================================+
echo  ^|   STEP 3 of 5 -- Force Update? (Optional)       ^|
echo  +==================================================+
echo.
echo  Do you want to FORCE users to update?
echo.
echo  +--------------------------------------------------+
echo  ^|  YES --^> Users on older versions CANNOT use app ^|
echo  ^|           until they update. (Hard block)        ^|
echo  ^|                                                  ^|
echo  ^|  NO  --^> Users see a soft notification but can  ^|
echo  ^|           still use the old version.             ^|
echo  +--------------------------------------------------+
echo.
set /p "FORCE=  Force update? (Y/N): "
if /i "!FORCE!" equ "Y" (
    echo.
    echo  +--------------------------------------------------+
    echo  ^|  Update min_app_version to: !NEW_VERSION!        ^|
    echo  ^|  in your Admin Panel Settings                    ^|
    echo  +--------------------------------------------------+
    echo.
    start "" "!ADMIN_URL!"
    echo.
    :STEP3_CONFIRM
    set /p "DONE3=  Have you updated min_app_version? (Y/N): "
    if /i "!DONE3!" equ "Y" goto STEP4
    if /i "!DONE3!" equ "N" (
        echo.
        echo  WARNING: Please update it before continuing!
        start "" "!ADMIN_URL!"
        goto STEP3_CONFIRM
    )
    echo  ERROR: Please type Y or N only.
    goto STEP3_CONFIRM
)
if /i "!FORCE!" equ "N" (
    echo.
    echo  Skipping force update -- users can still use old version.
    echo.
    pause
    goto STEP4
)
echo  ERROR: Please type Y or N only.
goto STEP3

:: ============================================================
:STEP4
cls
echo.
echo  +==================================================+
echo  ^|   STEP 4 of 5 -- Git Add, Commit and Push       ^|
echo  +==================================================+
echo.
echo  Enter a short description of what changed.
echo  Examples:
echo    - fix crash on sms bomber screen
echo    - add new tool to home screen
echo    - update UI design
echo.
set /p "COMMIT_MSG=  Commit message: "

if "!COMMIT_MSG!"=="" set "COMMIT_MSG=release version !NEW_VERSION!"

echo.
echo  --------------------------------------------------
echo  Running git commands...
echo  --------------------------------------------------
echo.

cd /d "%REPO%"

echo  Running: git add .
git add .
echo.

echo  Running: git commit -m "release: v!NEW_VERSION! - !COMMIT_MSG!"
git commit -m "release: v!NEW_VERSION! - !COMMIT_MSG!"
echo.

echo  Running: git push
git push

if !errorlevel! neq 0 (
    echo.
    echo  ERROR: Git push failed! Please check your connection
    echo  and make sure you are logged into GitHub.
    echo.
    pause
    goto STEP4
)

echo.
echo  Code pushed to GitHub successfully!
echo.
pause
goto STEP5

:: ============================================================
:STEP5
cls
echo.
echo  +==================================================+
echo  ^|   STEP 5 of 5 -- Create Version Tag             ^|
echo  ^|                  (Triggers GitHub Actions Build) ^|
echo  +==================================================+
echo.
echo  This will create tag: v!NEW_VERSION!
echo  GitHub Actions will START BUILDING your APK!
echo.
echo  --------------------------------------------------
echo.

cd /d "%REPO%"

:: BUG FIX 3: Delete local tag first if it already exists (prevents error on retry)
git tag -d v!NEW_VERSION! 2>nul

echo  Running: git tag v!NEW_VERSION!
git tag v!NEW_VERSION!
echo.

echo  Running: git push origin v!NEW_VERSION!
git push origin v!NEW_VERSION!

if !errorlevel! neq 0 (
    echo.
    echo  ERROR: Tag push failed!
    echo  If the tag already exists on remote, run:
    echo    git push origin --delete v!NEW_VERSION!
    echo  Then run this step again.
    echo.
    pause
    exit /b
)

:: ============================================================
:DONE
cls
echo.
echo  +==================================================+
echo  ^|   ALL DONE! RELEASE v!NEW_VERSION! IN PROGRESS  ^|
echo  +==================================================+
echo.
echo  Step 1 -- pubspec.yaml updated to v!NEW_VERSION!
echo  Step 2 -- Admin Panel latest_app_version updated
echo  Step 3 -- Force update preference set
echo  Step 4 -- Code committed and pushed to GitHub
echo  Step 5 -- Tag v!NEW_VERSION! pushed, build triggered!
echo.
echo  ==================================================
echo.
echo  You will receive a Telegram notification when
echo  the APK build is complete!
echo.
echo  Monitor build progress:
echo  https://github.com/Xissin/xissin-monorepo/actions
echo.
echo  Download APK when done:
echo  https://github.com/Xissin/xissin-monorepo/releases
echo.
echo  ==================================================
echo.
set /p "OPEN=  Open GitHub Actions in browser? (Y/N): "
if /i "!OPEN!" equ "Y" (
    start "" "https://github.com/Xissin/xissin-monorepo/actions"
)
echo.
echo  Press any key to exit...
pause >nul
exit
