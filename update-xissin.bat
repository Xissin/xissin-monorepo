@echo off
setlocal enabledelayedexpansion
title Xissin App Updater v2.1
color 0A

:: ============================================================
::  XISSIN APP UPDATER v2.1
::  Full release flow — pubspec → GitHub → Drive → Admin Panel
::  v2.1: Auto-computes APK SHA-256 checksum for security
:: ============================================================

set "PUBSPEC=C:\Users\Nathaniel\Desktop\xissin-monorepo\app\pubspec.yaml"
set "REPO=C:\Users\Nathaniel\Desktop\xissin-monorepo"
set "ADMIN_URL=https://xissin-panel.streamlit.app"
set "ACTIONS_URL=https://github.com/Xissin/xissin-monorepo/actions"
set "RELEASES_URL=https://github.com/Xissin/xissin-monorepo/releases"
set "APK_DOWNLOAD_DIR=D:\Download"

:: ── Read current version from pubspec.yaml ──────────────────
for /f "tokens=2 delims=: " %%a in ('findstr /i "^version:" "%PUBSPEC%"') do (
    set "CURRENT_VERSION_FULL=%%a"
)
for /f "tokens=1,2 delims=+" %%a in ("!CURRENT_VERSION_FULL!") do (
    set "CURRENT_VERSION=%%a"
    set "CURRENT_BUILD=%%b"
)

:: ============================================================
cls
echo.
echo  +====================================================+
echo  ^|          XISSIN APP UPDATER v2.1                  ^|
echo  +====================================================+
echo.
echo  Current App Version : v!CURRENT_VERSION!
echo  Current Build Number: !CURRENT_BUILD!
echo.
echo  ====================================================
echo  RELEASE FLOW:
echo.
echo  [1] Update pubspec.yaml version
echo  [2] Write commit message + push to GitHub
echo  [3] Create version tag  (triggers APK build)
echo  [4] Wait for build -- download APK from GitHub
echo  [4b] AUTO-COMPUTE SHA-256 checksum  ^<-- NEW
echo  [5] Upload APK to Google Drive -- copy link
echo  [6] Update Admin Panel
echo       - latest_app_version
echo       - min_app_version  (force update, optional)
echo       - APK Download URL (paste Drive link)
echo       - APK SHA-256      (auto-filled for you)
echo       - Version Notes    (shown in update dialog)
echo  ====================================================
echo.
pause
goto STEP1

:: ============================================================
:STEP1
cls
echo.
echo  +====================================================+
echo  ^|   STEP 1 of 6 -- Update pubspec.yaml version      ^|
echo  +====================================================+
echo.
echo  Current version: v!CURRENT_VERSION! (Build !CURRENT_BUILD!)
echo.
echo  Version naming guide:
echo  +----------------------------------------------------+
echo  ^|  Bug fix only       --^>  1.0.0  becomes  1.0.1   ^|
echo  ^|  New feature added  --^>  1.0.0  becomes  1.1.0   ^|
echo  ^|  Major redesign     --^>  1.0.0  becomes  2.0.0   ^|
echo  +----------------------------------------------------+
echo.
set /p "NEW_VERSION=  Enter new version (e.g. 1.0.1): "

if "!NEW_VERSION!"=="" (
    echo.
    echo  ERROR: Version cannot be empty!
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

set "OLD_VER_FULL=!CURRENT_VERSION!+!CURRENT_BUILD!"
set "NEW_VER_FULL=!NEW_VERSION!+!NEW_BUILD!"

:: Verify we actually have a build number before replacing
if "!CURRENT_BUILD!"=="" (
    echo.
    echo  ERROR: Could not read build number from pubspec.yaml
    echo  Check that your pubspec.yaml has: version: X.X.X+BUILD
    echo.
    pause
    goto STEP1
)

powershell -Command "(Get-Content '!PUBSPEC!') -replace [regex]::Escape('!OLD_VER_FULL!'), '!NEW_VER_FULL!' | Set-Content '!PUBSPEC!'"

echo.
echo  [OK] pubspec.yaml updated to v!NEW_VERSION!+!NEW_BUILD!
echo.
pause
goto STEP2

:: ============================================================
:STEP2
cls
echo.
echo  +====================================================+
echo  ^|   STEP 2 of 6 -- Git Add, Commit and Push         ^|
echo  +====================================================+
echo.
echo  Enter a short description of what changed.
echo  Examples:
echo    - fix crash on sms bomber screen
echo    - add NGL bomber improvements
echo    - update UI design
echo    - add APK auto-update system
echo.
set /p "COMMIT_MSG=  Commit message: "
if "!COMMIT_MSG!"=="" set "COMMIT_MSG=release version !NEW_VERSION!"

echo.
echo  --------------------------------------------------
echo  Running git commands...
echo  --------------------------------------------------
echo.

cd /d "%REPO%"

echo  ^> git add -A
git add -A
echo.

echo  ^> git commit -m "release: v!NEW_VERSION! - !COMMIT_MSG!"
git commit -m "release: v!NEW_VERSION! - !COMMIT_MSG!"
echo.

echo  ^> git push
git push

if !ERRORLEVEL! NEQ 0 (
    echo.
    echo  ERROR: Git push failed!
    echo  Check your internet connection and GitHub login.
    echo.
    pause
    goto STEP2
)

echo.
echo  [OK] Code pushed to GitHub successfully!
echo.
pause
goto STEP3

:: ============================================================
:STEP3
cls
echo.
echo  +====================================================+
echo  ^|   STEP 3 of 6 -- Create Version Tag               ^|
echo  ^|                   (Triggers GitHub Actions Build)  ^|
echo  +====================================================+
echo.
echo  This will create and push tag: v!NEW_VERSION!
echo  GitHub Actions will START BUILDING your APK!
echo.
echo  --------------------------------------------------
echo.

cd /d "%REPO%"

:: Delete local tag first if it already exists (safe retry)
git tag -d v!NEW_VERSION! 2>nul

echo  ^> git tag v!NEW_VERSION!
git tag v!NEW_VERSION!
echo.

echo  ^> git push origin v!NEW_VERSION!
git push origin v!NEW_VERSION!

if !ERRORLEVEL! NEQ 0 (
    echo.
    echo  ERROR: Tag push failed!
    echo  If the tag already exists on remote, run:
    echo    git push origin --delete v!NEW_VERSION!
    echo  Then run this step again.
    echo.
    pause
    exit /b
)

echo.
echo  [OK] Tag v!NEW_VERSION! pushed! Build is now running.
echo.
echo  Opening GitHub Actions in browser...
start "" "!ACTIONS_URL!"
echo.
pause
goto STEP4

:: ============================================================
:STEP4
cls
echo.
echo  +====================================================+
echo  ^|   STEP 4 of 6 -- Wait for Build + Download APK    ^|
echo  +====================================================+
echo.
echo  Your APK is being built by GitHub Actions right now.
echo.
echo  +----------------------------------------------------+
echo  ^|  1. Wait for the build to finish (usually 5-10min)^|
echo  ^|  2. Go to your GitHub Releases page               ^|
echo  ^|  3. Find release v!NEW_VERSION!                   ^|
echo  ^|  4. Download the APK file to:                     ^|
echo  ^|     D:\Download\                                  ^|
echo  ^|  5. Name it:  xissin_v!NEW_VERSION!.apk           ^|
echo  +----------------------------------------------------+
echo.
echo  Opening GitHub Releases page...
start "" "!RELEASES_URL!"
echo.

:STEP4_WAIT
set /p "DONE4=  Have you downloaded the APK to D:\Download\? (Y/N): "
if /i "!DONE4!" equ "Y" goto STEP4_HASH
if /i "!DONE4!" equ "N" (
    echo.
    echo  Take your time -- wait for the build to finish.
    echo  Opening GitHub Actions to check progress...
    start "" "!ACTIONS_URL!"
    echo.
    goto STEP4_WAIT
)
echo  Please type Y or N only.
goto STEP4_WAIT

:: ── Step 4b: Auto-compute SHA-256 ────────────────────────────
:STEP4_HASH
cls
echo.
echo  +====================================================+
echo  ^|   STEP 4b -- Computing APK SHA-256 Checksum       ^|
echo  +====================================================+
echo.

:: Try the expected filename first
set "APK_PATH=!APK_DOWNLOAD_DIR!\xissin_v!NEW_VERSION!.apk"
set "APK_FOUND=0"

if exist "!APK_PATH!" (
    set "APK_FOUND=1"
) else (
    :: Ask user to point to the APK if not found at expected path
    echo  Could not find: !APK_PATH!
    echo.
    echo  Please enter the full path to your downloaded APK.
    echo  Example: D:\Download\app-release.apk
    echo.
    set /p "APK_PATH=  APK file path: "
    if exist "!APK_PATH!" (
        set "APK_FOUND=1"
    ) else (
        echo.
        echo  ERROR: File not found at that path.
        echo  Please download the APK first then press any key to retry.
        pause
        goto STEP4_HASH
    )
)

echo.
echo  Computing SHA-256 for:
echo  !APK_PATH!
echo.
echo  Please wait...
echo.

:: Use PowerShell to get SHA-256 hash and capture it cleanly
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash [char]34+'!APK_PATH!'+[char]34 -Algorithm SHA256).Hash.ToLower()"`) do (
    set "APK_SHA256=%%H"
)

if "!APK_SHA256!"=="" (
    echo  ERROR: Could not compute hash. Make sure the file is not corrupted.
    pause
    goto STEP4_HASH
)

echo  +----------------------------------------------------+
echo  ^|  SHA-256 CHECKSUM:                                ^|
echo  ^|  !APK_SHA256!  ^|
echo  +----------------------------------------------------+
echo.
echo  [OK] Checksum computed! Copy it to the Admin Panel in Step 6.
echo.
echo  (This has also been saved to clipboard for you)
powershell -Command "Set-Clipboard -Value '!APK_SHA256!'"
echo.
pause
goto STEP5

:: ============================================================
:STEP5
cls
echo.
echo  +====================================================+
echo  ^|   STEP 5 of 6 -- Upload APK to Google Drive       ^|
echo  +====================================================+
echo.
echo  +----------------------------------------------------+
echo  ^|  1. Open Google Drive                             ^|
echo  ^|  2. Upload your new APK file                      ^|
echo  ^|  3. Right-click it -- ^> Share                    ^|
echo  ^|  4. Set to "Anyone with the link can view"        ^|
echo  ^|  5. Click "Copy link"                             ^|
echo  ^|  6. Paste the link below                         ^|
echo  +----------------------------------------------------+
echo.
echo  The link will look like:
echo  https://drive.google.com/file/d/FILEID/view?usp=sharing
echo.
echo  Opening Google Drive in browser...
start "" "https://drive.google.com"
echo.

:STEP5_PASTE
set /p "DRIVE_LINK=  Paste your Google Drive link here: "

if "!DRIVE_LINK!"=="" (
    echo.
    echo  ERROR: Link cannot be empty! Please paste the link.
    echo.
    goto STEP5_PASTE
)

:: Validate it looks like a Drive link
echo !DRIVE_LINK! | findstr /i "drive.google.com" >nul
if !ERRORLEVEL! NEQ 0 (
    echo.
    echo  WARNING: That does not look like a Google Drive link.
    echo  Expected: https://drive.google.com/file/d/.../view
    echo.
    set /p "RETRY=  Try again? (Y/N): "
    if /i "!RETRY!" equ "Y" goto STEP5_PASTE
)

echo.
echo  [OK] Drive link saved: !DRIVE_LINK!
echo  (The Admin Panel will auto-convert it to a direct download URL)
echo.
pause
goto STEP6

:: ============================================================
:STEP6
cls
echo.
echo  +====================================================+
echo  ^|   STEP 6 of 6 -- Update Admin Panel               ^|
echo  +====================================================+
echo.
echo  You need to update 5 things in the Admin Panel.
echo  Open Settings page now.
echo.
echo  Opening Admin Panel...
start "" "!ADMIN_URL!"
echo.

:: ── 6A: Latest App Version ──────────────────────────────────
echo  --------------------------------------------------
echo  [6A] LATEST APP VERSION
echo  --------------------------------------------------
echo  Set "Latest App Version" to: !NEW_VERSION!
echo  --------------------------------------------------
echo.
:STEP6A
set /p "DONE6A=  Done updating latest_app_version to !NEW_VERSION!? (Y/N): "
if /i "!DONE6A!" equ "Y" goto STEP6B
if /i "!DONE6A!" equ "N" (
    echo.
    echo  Please update it before continuing.
    start "" "!ADMIN_URL!"
    goto STEP6A
)
echo  Please type Y or N only.
goto STEP6A

:: ── 6B: Force Update (Min Version) ─────────────────────────
:STEP6B
echo.
echo  --------------------------------------------------
echo  [6B] FORCE UPDATE? (Minimum App Version)
echo  --------------------------------------------------
echo  +----------------------------------------------------+
echo  ^|  YES --^> Users on older versions CANNOT use app  ^|
echo  ^|           until they update. (Hard block)          ^|
echo  ^|                                                    ^|
echo  ^|  NO  --^> Users see update dialog but can skip it  ^|
echo  ^|           and still use the old version.           ^|
echo  +----------------------------------------------------+
echo.
set /p "FORCE=  Force update? (Y/N): "
if /i "!FORCE!" equ "Y" (
    echo.
    echo  Set "Minimum App Version" to: !NEW_VERSION!
    echo  Opening Admin Panel...
    start "" "!ADMIN_URL!"
    echo.
    :STEP6B_CONFIRM
    set /p "DONE6B=  Done updating min_app_version to !NEW_VERSION!? (Y/N): "
    if /i "!DONE6B!" equ "Y" goto STEP6C
    if /i "!DONE6B!" equ "N" (
        echo.
        echo  Please update it before continuing.
        start "" "!ADMIN_URL!"
        goto STEP6B_CONFIRM
    )
    echo  Please type Y or N only.
    goto STEP6B_CONFIRM
)
if /i "!FORCE!" equ "N" (
    echo.
    echo  Skipping force update -- users can skip the update dialog.
    echo.
    goto STEP6C
)
echo  Please type Y or N only.
goto STEP6B

:: ── 6C: APK Download URL ────────────────────────────────────
:STEP6C
echo.
echo  --------------------------------------------------
echo  [6C] APK DOWNLOAD URL
echo  --------------------------------------------------
echo  Paste this link into the "Google Drive APK Link" field:
echo.
echo  !DRIVE_LINK!
echo.
echo  The Admin Panel will auto-convert it to a direct
echo  download URL. You will see a green preview before saving.
echo  --------------------------------------------------
echo.
:STEP6C_CONFIRM
set /p "DONE6C=  Done pasting the APK URL into Admin Panel? (Y/N): "
if /i "!DONE6C!" equ "Y" goto STEP6D
if /i "!DONE6C!" equ "N" (
    echo.
    echo  Please paste it before continuing.
    start "" "!ADMIN_URL!"
    goto STEP6C_CONFIRM
)
echo  Please type Y or N only.
goto STEP6C_CONFIRM

:: ── 6D: APK SHA-256 Checksum ─────────────────────────────────
:STEP6D
echo.
echo  --------------------------------------------------
echo  [6D] APK SHA-256 CHECKSUM  ^<-- NEW
echo  --------------------------------------------------
echo  Paste this into the "APK SHA-256 Checksum" field:
echo.
echo  !APK_SHA256!
echo.
echo  (It was also copied to your clipboard in Step 4b)
echo  Ctrl+V to paste it directly.
echo  --------------------------------------------------
echo.
:STEP6D_CONFIRM
set /p "DONE6D=  Done pasting the SHA-256 into Admin Panel? (Y/N): "
if /i "!DONE6D!" equ "Y" goto STEP6E
if /i "!DONE6D!" equ "N" (
    echo.
    echo  Please paste it before continuing.
    start "" "!ADMIN_URL!"
    goto STEP6D_CONFIRM
)
echo  Please type Y or N only.
goto STEP6D_CONFIRM

:: ── 6E: Version Notes ───────────────────────────────────────
:STEP6E
echo.
echo  --------------------------------------------------
echo  [6E] VERSION NOTES  (shown in update dialog)
echo  --------------------------------------------------
echo  Fill in the "Version Notes" field in Admin Panel.
echo  Write what changed in this version. Examples:
echo.
echo    * Bug fixes and performance improvements
echo    * Added new SMS Bomber feature
echo    * Fixed crash on home screen
echo    * UI design improvements
echo.
echo  Opening Admin Panel...
start "" "!ADMIN_URL!"
echo.
:STEP6E_CONFIRM
set /p "DONE6E=  Done filling in Version Notes? (Y/N): "
if /i "!DONE6E!" equ "Y" goto STEP6F
if /i "!DONE6E!" equ "N" (
    echo.
    echo  Please fill it in before continuing.
    start "" "!ADMIN_URL!"
    goto STEP6E_CONFIRM
)
echo  Please type Y or N only.
goto STEP6E_CONFIRM

:: ── 6F: Save Settings ───────────────────────────────────────
:STEP6F
echo.
echo  --------------------------------------------------
echo  [6F] SAVE SETTINGS
echo  --------------------------------------------------
echo  Click the "Save All Settings" button in Admin Panel!
echo  Do NOT forget this step or none of the changes
echo  will be applied to the live app.
echo  --------------------------------------------------
echo.
:STEP6F_CONFIRM
set /p "DONE6F=  Have you clicked SAVE ALL SETTINGS? (Y/N): "
if /i "!DONE6F!" equ "Y" goto DONE
if /i "!DONE6F!" equ "N" (
    echo.
    echo  Please save before continuing!
    start "" "!ADMIN_URL!"
    goto STEP6F_CONFIRM
)
echo  Please type Y or N only.
goto STEP6F_CONFIRM

:: ============================================================
:DONE
cls
echo.
echo  +====================================================+
echo  ^|    ALL DONE!  v!NEW_VERSION! IS NOW LIVE!         ^|
echo  +====================================================+
echo.
echo  Summary of what was done:
echo.
echo  [1] pubspec.yaml   --^> v!NEW_VERSION!+!NEW_BUILD!
echo  [2] Git            --^> Committed and pushed
echo  [3] GitHub Tag     --^> v!NEW_VERSION! created
echo  [4] APK            --^> Downloaded + SHA-256 computed
echo  [5] Google Drive   --^> APK uploaded, link saved
echo  [6] Admin Panel    --^> All 5 fields updated + saved
echo       latest_app_version   = !NEW_VERSION!
if /i "!FORCE!" equ "Y" (
echo       min_app_version      = !NEW_VERSION!  [FORCE UPDATE ON]
) else (
echo       min_app_version      = unchanged      [soft update]
)
echo       apk_download_url     = Drive link set
echo       apk_sha256           = !APK_SHA256!
echo       apk_version_notes    = filled in
echo.
echo  ====================================================
echo.
echo  Users will now see the update dialog when they
echo  open the app. The app will verify the APK checksum
echo  before installing to prevent tampering.
echo.
echo  ====================================================
echo.
set /p "OPEN_ACTIONS=  Open GitHub Actions to confirm build? (Y/N): "
if /i "!OPEN_ACTIONS!" equ "Y" start "" "!ACTIONS_URL!"

echo.
echo  Press any key to exit...
pause >nul
exit