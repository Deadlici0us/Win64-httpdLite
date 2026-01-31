option casemap:none
include constants.inc

extern CreateFileA:proc
extern GetFileSize:proc
extern ReadFile:proc
extern CloseHandle:proc
extern GetProcessHeap:proc
extern HeapAlloc:proc
extern StrCompare:proc
extern StrCompareCaseInsensitive:proc
extern StrCopy:proc
extern StrLen:proc
extern MemCpy:proc
extern IntToDecString:proc
extern ExitProcess:proc
extern PrintString:proc
extern FindFirstFileA:proc
extern FindNextFileA:proc
extern FindClose:proc

.data
    CacheHead       dq 0        ; Head of the linked list
    ConfigHead      dq 0        ; Head of config list
    
    configFile      db "httpd.conf", 0
    htmlDir         db "html", 0   ; Root dir (no trailing slash)
    slash           db "\", 0
    star            db "*", 0
    
    ; Header Components
    hdrPart1        db "HTTP/1.1 200 OK", 13, 10, "Content-Type: ", 0
    hdrPart2        db 13, 10, "Connection: close", 13, 10, "Content-Length: ", 0
    hdrPart3        db 13, 10, 13, 10, 0
    
    msgCacheInit    db "Initializing File Cache...", 13, 10, 0
    msgFoundFile    db "Cached: ", 0
    msgConfig       db "Config: ", 0
    msgCRLF         db 13, 10, 0
    msgErrCache     db "Error: Could not read httpd.conf", 13, 10, 0
    msgErrLoad      db "Failed to load file: ", 0
    msgScanning     db "Scanning: ", 0

    ; Config Entry Structure
    ConfigEntry STRUCT
        Next        QWORD ?
        Extension   QWORD ?
        MimeType    QWORD ?
    ConfigEntry ENDS

.code

; ---------------------------------------------------------
; GetExtension
; Purpose:  Returns pointer to extension (including dot)
; Args:     RCX = Filename
; Returns:  RAX = Ptr to dot, or 0 if none
; ---------------------------------------------------------
GetExtension proc private
    push rbx
    mov rax, rcx
    xor rdx, rdx    ; Last dot pos
    
scan_ext:
    mov bl, [rax]
    test bl, bl
    jz done_scan_ext
    cmp bl, '.'
    jne next_char
    mov rdx, rax
next_char:
    inc rax
    jmp scan_ext
    
done_scan_ext:
    mov rax, rdx
    pop rbx
    ret
GetExtension endp

; ---------------------------------------------------------
; FindMimeType
; Purpose:  Finds mime type for extension
; Args:     RCX = Extension (e.g. ".html")
; Returns:  RAX = MimeType String Ptr, or 0
; ---------------------------------------------------------
FindMimeType proc private
    push rsi
    push rdi
    push rbx
    
    mov rbx, rcx
    mov rsi, [ConfigHead]
    
search_mime:
    test rsi, rsi
    jz not_found_mime
    
    ; Compare Extensions (Case Insensitive)
    mov rcx, rbx
    mov rdx, [rsi + ConfigEntry.Extension]
    call StrCompareCaseInsensitive
    test rax, rax
    jnz found_mime
    
    mov rsi, [rsi + ConfigEntry.Next]
    jmp search_mime
    
found_mime:
    mov rax, [rsi + ConfigEntry.MimeType]
    jmp done_mime
    
not_found_mime:
    xor rax, rax
    
done_mime:
    pop rbx
    pop rdi
    pop rsi
    ret
FindMimeType endp

; ---------------------------------------------------------
; LoadFileToCache
; Purpose: Loads a single file into a CachedFile node
; Args:    RCX = Full Path (for CreateFile)
;          RDX = Cache Key (Relative Path, forward slashes)
;          R8  = MimeType Pointer
; ---------------------------------------------------------
LoadFileToCache proc private
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64
    
    mov rsi, rcx            ; Full Path
    mov rdi, rdx            ; Cache Key
    mov r15, r8             ; MimeType
    
    ; 1. Open File
    mov rcx, rsi
    mov rdx, GENERIC_READ
    mov r8, FILE_SHARE_READ
    mov r9, 0
    mov qword ptr [rsp + 32], OPEN_EXISTING
    mov qword ptr [rsp + 40], FILE_ATTRIBUTE_NORMAL
    mov qword ptr [rsp + 48], 0
    call CreateFileA
    
    cmp rax, -1
    je err_file_open
    
    mov rbx, rax            ; File Handle
    
    ; 2. Get Size
    mov rcx, rbx
    mov rdx, 0
    call GetFileSize
    mov r12, rax            ; File Size
    
    ; 3. Allocate CachedFile Node
    call GetProcessHeap
    mov r13, rax            ; Heap Handle
    
    mov rcx, r13
    mov rdx, 8              ; ZERO_MEMORY
    mov r8, sizeof CachedFile
    call HeapAlloc
    test rax, rax
    jz close_file
    
    mov r14, rax            ; Node Ptr
    
    ; 4. Alloc & Copy Filename (Cache Key)
    mov rcx, rdi
    call StrLen
    inc rax
    push rax                ; Save Len
    
    mov rcx, r13
    mov rdx, 8
    mov r8, rax
    call HeapAlloc
    mov [r14 + CachedFile.FileName], rax
    
    mov rcx, rax
    mov rdx, rdi
    call StrCopy
    pop rax                 ; Restore Len
    
    ; 5. Alloc & Read Content
    mov rcx, r13
    mov rdx, 8
    mov r8, r12
    call HeapAlloc
    mov [r14 + CachedFile.Content], rax
    mov [r14 + CachedFile.ContentLen], r12d
    
    mov rcx, rbx            ; hFile
    mov rdx, rax            ; Buffer
    mov r8, r12             ; Size
    lea r9, [rsp + 40]      ; BytesRead (scratch)
    mov qword ptr [rsp + 32], 0
    call ReadFile
    
    ; 6. Generate Header
    ; Calc Header Size
    lea rcx, [hdrPart1]
    call StrLen
    mov rdi, rax
    
    mov rcx, r15
    call StrLen
    add rdi, rax
    
    lea rcx, [hdrPart2]
    call StrLen
    add rdi, rax
    
    add rdi, 20             ; Size String Space
    
    lea rcx, [hdrPart3]
    call StrLen
    add rdi, rax
    
    ; Alloc Header
    mov rcx, r13
    mov rdx, 8
    mov r8, rdi
    call HeapAlloc
    mov [r14 + CachedFile.Header], rax
    
    ; Build Header String
    mov rdi, rax            ; Cursor
    
    ; Part 1
    lea rcx, [hdrPart1]
    call StrLen
    mov r8, rax
    mov rcx, rdi
    lea rdx, [hdrPart1]
    call MemCpy
    add rdi, r8
    
    ; Mime
    mov rcx, r15
    call StrLen
    mov r8, rax
    mov rcx, rdi
    mov rdx, r15
    call MemCpy
    add rdi, r8
    
    ; Part 2
    lea rcx, [hdrPart2]
    call StrLen
    mov r8, rax
    mov rcx, rdi
    lea rdx, [hdrPart2]
    call MemCpy
    add rdi, r8
    
    ; Size
    mov rcx, r12
    mov rdx, rdi
    call IntToDecString
    add rdi, rax
    
    ; Part 3
    lea rcx, [hdrPart3]
    call StrLen
    mov r8, rax
    mov rcx, rdi
    lea rdx, [hdrPart3]
    call MemCpy
    add rdi, r8
    
    ; Calc Header Len
    mov rax, rdi
    sub rax, [r14 + CachedFile.Header]
    mov [r14 + CachedFile.HeaderLen], eax
    
    ; 7. Link to Head
    mov rax, [CacheHead]
    mov [r14 + CachedFile.Next], rax
    mov [CacheHead], r14
    
    ; Log
    lea rcx, [msgFoundFile]
    call PrintString
    mov rcx, [r14 + CachedFile.FileName]
    call PrintString
    lea rcx, [msgCRLF]
    call PrintString
    
close_file:
    mov rcx, rbx
    call CloseHandle
    jmp done_load
    
err_file_open:
    lea rcx, [msgErrLoad]
    call PrintString
    mov rcx, rsi
    call PrintString
    lea rcx, [msgCRLF]
    call PrintString

done_load:
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
LoadFileToCache endp

; ---------------------------------------------------------
; Helper: NormalizePath
; Purpose: Converts backslashes to forward slashes in-place
; Args:    RCX = String
; ---------------------------------------------------------
NormalizePath proc private
    mov rax, rcx
norm_loop:
    mov dl, [rax]
    test dl, dl
    jz norm_done
    cmp dl, '\'
    jne next_norm
    mov byte ptr [rax], '/'
next_norm:
    inc rax
    jmp norm_loop
norm_done:
    ret
NormalizePath endp

; ---------------------------------------------------------
; ScanDirectory
; Purpose: Recursively scans directory
; Args:    RCX = Path (No trailing slash)
; ---------------------------------------------------------
ScanDirectory proc private
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 1040           ; 16-byte aligned frame (1040 = 16 * 65)
                            ; [rsp] = Shadow Space (32 bytes)
                            ; [rsp+32] = WIN32_FIND_DATA (320 bytes)
                            ; [rsp+352] = Current Search Path (260 bytes)
                            ; [rsp+612] = Subdir Path / File Path (260 bytes)
    
    mov rsi, rcx            ; Base Path
    
    ; Construct Search Path: BasePath + \ + *
    lea rdi, [rsp + 352]
    mov rcx, rdi
    mov rdx, rsi
    call StrCopy
    
    mov rcx, rdi
    call StrLen
    add rdi, rax
    
    lea rdx, [slash]
    mov rcx, rdi
    call StrCopy
    inc rdi
    
    lea rdx, [star]
    mov rcx, rdi
    call StrCopy
    
    ; FindFirstFile
    lea rcx, [rsp + 352]    ; Search Pattern
    lea rdx, [rsp + 32]     ; WIN32_FIND_DATA (Offset 32, preserving Shadow Space at 0)
    call FindFirstFileA
    
    cmp rax, -1
    je done_scan
    
    mov rbx, rax            ; Find Handle
    
scan_loop:
    ; Skip . and ..
    lea rcx, [rsp + 32 + WIN32_FIND_DATAA.cFileName] ; Offset 32 + Struct Offset
    cmp byte ptr [rcx], '.'
    je check_dots
    jmp process_item
    
check_dots:
    cmp byte ptr [rcx+1], 0
    je next_file
    cmp byte ptr [rcx+1], '.'
    jne process_item
    cmp byte ptr [rcx+2], 0
    je next_file
    
process_item:
    ; Build Full Path: BasePath + \ + FileName
    lea rdi, [rsp + 612]
    mov rcx, rdi
    mov rdx, rsi            ; Base Path
    call StrCopy
    
    mov rcx, rdi
    call StrLen
    add rdi, rax
    
    lea rdx, [slash]
    mov rcx, rdi
    call StrCopy
    inc rdi
    
    lea rdx, [rsp + 32 + WIN32_FIND_DATAA.cFileName]
    mov rcx, rdi
    call StrCopy
    
    ; Check if Directory
    test dword ptr [rsp + 32 + WIN32_FIND_DATAA.dwFileAttributes], FILE_ATTRIBUTE_DIRECTORY
    jz is_file
    
    ; Recurse
    lea rcx, [rsp + 612]
    call ScanDirectory
    jmp next_file
    
is_file:
    ; Check Extension
    lea rcx, [rsp + 32 + WIN32_FIND_DATAA.cFileName]
    call GetExtension
    test rax, rax
    jz next_file
    
    mov rcx, rax
    call FindMimeType
    test rax, rax
    jz next_file
    
    mov r12, rax            ; MimeType
    
    ; Found matching file!
    ; Arg1: Full Path (for open) -> [rsp + 612]
    ; Arg2: Cache Key (Relative Path)
    ; Strip "html\" (5 chars)
    lea r13, [rsp + 612]
    add r13, 5              ; Skip "html\"
    
    ; Use Search Path buffer [rsp+352] as temp for Key
    lea rcx, [rsp + 352]
    mov rdx, r13
    call StrCopy
    
    lea rcx, [rsp + 352]
    call NormalizePath
    
    lea rcx, [rsp + 612]    ; Full Path
    lea rdx, [rsp + 352]    ; Key
    mov r8, r12             ; Mime
    call LoadFileToCache
    
next_file:
    mov rcx, rbx
    lea rdx, [rsp + 32]     ; WIN32_FIND_DATA
    call FindNextFileA
    test rax, rax
    jnz scan_loop
    
    mov rcx, rbx
    call FindClose

done_scan:
    add rsp, 1040
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
ScanDirectory endp

; ---------------------------------------------------------
; InitCache
; Purpose: Reads httpd.conf and populates cache
; ---------------------------------------------------------
InitCache proc public
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 80
    
    lea rcx, [msgCacheInit]
    call PrintString
    
    ; 1. Open httpd.conf
    lea rcx, [configFile]
    mov rdx, GENERIC_READ
    mov r8, FILE_SHARE_READ
    mov r9, 0
    mov qword ptr [rsp + 32], OPEN_EXISTING
    mov qword ptr [rsp + 40], FILE_ATTRIBUTE_NORMAL
    mov qword ptr [rsp + 48], 0
    call CreateFileA
    
    cmp rax, -1
    je err_conf
    
    mov rbx, rax            ; File Handle
    
    ; 2. Get Size
    mov rcx, rbx
    mov rdx, 0
    call GetFileSize
    mov r12, rax            ; Size
    
    test rax, rax
    jz close_conf
    
    ; 3. Alloc Buffer
    call GetProcessHeap
    mov r13, rax            ; Heap
    
    mov rcx, r13
    mov rdx, 8
    mov r8, r12
    add r8, 1
    call HeapAlloc
    
    test rax, rax
    jz close_conf
    
    mov rsi, rax            ; Buffer
    
    ; 4. Read File
    mov rcx, rbx
    mov rdx, rsi
    mov r8, r12
    lea r9, [rsp + 64]
    mov qword ptr [rsp + 32], 0
    call ReadFile
    
    ; 5. Parse Config Loop
    lea r12, [rsi + r12]    ; End of buffer
    
parse_loop:
    cmp rsi, r12
    jae start_scan
    cmp byte ptr [rsi], 0
    je start_scan
    
    ; Skip CR/LF/Space
    cmp byte ptr [rsi], 13
    je skip_char
    cmp byte ptr [rsi], 10
    je skip_char
    cmp byte ptr [rsi], ' '
    je skip_char
    
    ; Found Token 1 (Extension or Mime)
    ; Format: .html text/html
    mov rdi, rsi            ; Start
    
find_space:
    cmp rsi, r12
    jae start_scan
    cmp byte ptr [rsi], ' '
    je found_space
    cmp byte ptr [rsi], 13
    je line_err             ; Early end
    inc rsi
    jmp find_space
    
found_space:
    mov byte ptr [rsi], 0
    inc rsi
    
    ; Skip spaces
skip_spaces:
    cmp rsi, r12
    jae start_scan
    cmp byte ptr [rsi], ' '
    jne found_token2
    inc rsi
    jmp skip_spaces
    
found_token2:
    mov rbx, rsi            ; Start Token 2
    
find_eol:
    cmp rsi, r12
    jae eol_eof
    cmp byte ptr [rsi], 13
    je eol_cr
    cmp byte ptr [rsi], 10
    je eol_lf
    inc rsi
    jmp find_eol
    
eol_cr:
    mov byte ptr [rsi], 0
    inc rsi
    cmp rsi, r12
    jae process_config
    cmp byte ptr [rsi], 10
    jne process_config
    inc rsi
    jmp process_config

eol_lf:
    mov byte ptr [rsi], 0
    inc rsi
    jmp process_config
    
eol_eof:
    ; OK
    
process_config:
    ; RDI = Token1, RBX = Token2
    ; Determine which is extension (starts with .)
    cmp byte ptr [rdi], '.'
    je rdi_is_ext
    
    ; RBX must be extension
    cmp byte ptr [rbx], '.'
    jne line_err ; No extension found
    
    ; Swap so RDI=Ext, RBX=Mime
    xchg rdi, rbx
    
rdi_is_ext:
    ; Add to Config List
    ; Alloc ConfigEntry
    mov rcx, r13
    mov rdx, 8
    mov r8, sizeof ConfigEntry
    call HeapAlloc
    mov r8, rax             ; Node
    
    ; Link
    mov r9, [ConfigHead]
    mov [r8 + ConfigEntry.Next], r9
    mov [ConfigHead], r8
    
    ; Store Strings (Pointers into buffer are fine, buffer leaks but that's ok for global config)
    mov [r8 + ConfigEntry.Extension], rdi
    mov [r8 + ConfigEntry.MimeType], rbx
    
    ; Log
    lea rcx, [msgConfig]
    call PrintString
    mov rcx, rdi
    call PrintString
    lea rcx, [msgCRLF]
    call PrintString
    
    jmp parse_loop

line_err:
    inc rsi
    jmp parse_loop
    
skip_char:
    inc rsi
    jmp parse_loop

start_scan:
    ; Close Conf
    mov rcx, rbx
    call CloseHandle
    
    ; Scan HTML Directory
    lea rcx, [msgScanning]
    call PrintString
    lea rcx, [htmlDir]
    call PrintString
    lea rcx, [msgCRLF]
    call PrintString
    
    lea rcx, [htmlDir]
    call ScanDirectory
    
    add rsp, 80
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

close_conf:
    mov rcx, rbx
    call CloseHandle
    jmp err_conf

err_conf:
    lea rcx, [msgErrCache]
    call PrintString
    add rsp, 80
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
InitCache endp

; ---------------------------------------------------------
; FindCacheEntry
; Purpose:  Finds a file by name (Case Sensitive)
; Args:     RCX = Filename Ptr
; Returns:  RAX = Pointer to CachedFile struct, or 0
; ---------------------------------------------------------
FindCacheEntry proc public
    push rbx
    push rsi
    
    mov rbx, rcx            ; Search Name
    mov rsi, [CacheHead]
    
search_loop:
    test rsi, rsi
    jz not_found
    
    ; Use StrCompare (Case Sensitive)
    mov rcx, rbx
    mov rdx, [rsi + CachedFile.FileName]
    call StrCompare
    test rax, rax
    jnz found
    
    mov rsi, [rsi + CachedFile.Next]
    jmp search_loop
    
found:
    mov rax, rsi
    pop rsi
    pop rbx
    ret
    
not_found:
    xor rax, rax
    pop rsi
    pop rbx
    ret
FindCacheEntry endp

end