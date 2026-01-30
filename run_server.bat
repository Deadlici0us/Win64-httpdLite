@echo off
if exist build\httpdLite.exe (
    build\httpdLite.exe
) else (
    echo Error: httpLite.exe not found. Please run build.bat first.
)