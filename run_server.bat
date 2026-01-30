@echo off
if exist build\httpdlite.exe (
    build\httpdlite.exe
) else (
    echo Error: httplite.exe not found. Please run build.bat first.
)