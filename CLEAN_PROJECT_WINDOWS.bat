@echo off
setlocal
cd /d "%~dp0"
echo ==============================================
echo Hala Talab - Project Cleanup
echo ==============================================
echo This removes generated build/cache folders only.
echo Source code and assets are NOT deleted.

echo [1/4] flutter clean...
call flutter clean

echo [2/4] Removing local Dart build cache...
if exist .dart_tool rmdir /s /q .dart_tool
if exist build rmdir /s /q build

echo [3/4] Removing project-local Gradle cache...
if exist .gradle rmdir /s /q .gradle
if exist android\.gradle rmdir /s /q android\.gradle

echo [4/4] Restoring Flutter packages...
call flutter pub get

echo.
echo Cleanup finished. Large generated folders will be recreated only when needed.
pause
