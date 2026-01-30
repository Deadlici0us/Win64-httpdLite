@echo off
if exist build\httplite.exe (
    build\httplite.exe
) else (
    echo Error: httplite.exe not found. Please run build.bat first.
)