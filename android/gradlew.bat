@echo off
setlocal
set "DIR=%~dp0"
call "%DIR%SDL\android-project\gradlew.bat" -p "%DIR%" %*
