@echo off
setlocal
if not exist build mkdir build

where cmake >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo Error: cmake not found in PATH.
    exit /b 1
)

echo Configuring and building win64-httpdLite...
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
echo Build complete.
endlocal