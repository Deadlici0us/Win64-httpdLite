cmake_minimum_required(VERSION 3.10)
project(win64-httpdLite LANGUAGES C ASM_MASM)

add_executable(httpdLite src/main.asm src/utils.asm src/network.asm src/handler.asm src/memory.asm)

# Ensure MASM can find our .inc files in the source directory
target_compile_options(httpdLite PRIVATE /I${CMAKE_CURRENT_SOURCE_DIR}/src/include)

# --- Build Type Logic ---
if(CMAKE_BUILD_TYPE STREQUAL "Debug" OR NOT CMAKE_BUILD_TYPE)
    message(STATUS "Configuring for DEBUG build")
    target_compile_options(httpdLite PRIVATE /Zi)
    target_link_options(httpdLite PRIVATE /DEBUG /INCREMENTAL:YES)
else()
    message(STATUS "Configuring for RELEASE build")
    # Linker optimizations belong ONLY in Release
    target_link_options(httpdLite PRIVATE /OPT:REF /OPT:ICF /INCREMENTAL:NO)
endif()

# --- Linker Configuration ---
set_target_properties(httpdLite PROPERTIES LINKER_LANGUAGE C)

# Note: We removed /OPT:REF from here so it doesn't break Debug mode
target_link_options(httpdLite PRIVATE /ENTRY:main /SUBSYSTEM:CONSOLE)

target_link_libraries(httpdLite PRIVATE Ws2_32)

# Copy HTML folder to build directory
add_custom_command(TARGET httpdLite POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/html
        $<TARGET_FILE_DIR:httpdLite>/html)