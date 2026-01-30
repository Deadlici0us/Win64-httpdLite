; Set case sensitivity to none for labels and symbols
option casemap:none 
include constants.inc

; External Windows functions
extern accept:proc
extern closesocket:proc
extern WSACleanup:proc
extern ExitProcess:proc
extern CreateIoCompletionPort:proc
extern GetSystemInfo:proc
extern CreateThread:proc
extern CloseHandle:proc
extern CreateFileA:proc
extern GetFileSize:proc
extern ReadFile:proc

; External Modular functions
extern InitUtils:proc
extern PrintString:proc
extern InitNetwork:proc
extern CreateListener:proc
extern WorkerThread:proc
extern PostAccept:proc
extern InitMemory:proc
extern EnableNoDelay:proc
extern StrLen:proc
extern MemCpy:proc
extern IntToDecString:proc
extern GetProcessHeap:proc
extern HeapAlloc:proc

public cachedResponse
public cachedResponseLen
public cachedHeaderLen
public cachedPngResponse
public cachedPngLen
public cachedPngHeaderLen

.data
    ; Null-terminated strings for console logging
    msgStart        db "Starting Echo Server on port 80 (IOCP)...", 13, 10, 0
    msgSocketErr    db "Socket creation failed.", 13, 10, 0
    msgBindErr      db "Bind failed.", 13, 10, 0
    msgListenErr    db "Listen failed.", 13, 10, 0
    msgAcceptErr    db "Accept failed.", 13, 10, 0
    msgIOCPErr      db "CreateIoCompletionPort failed.", 13, 10, 0
    msgThreadErr    db "CreateThread failed.", 13, 10, 0
    msgLoadFail     db "Failed to load html/index.html", 13, 10, 0
    
    hIOCP           dq 0
    sysInfo         BYTE 48 DUP(0) ; SYSTEM_INFO struct (approx size)

    ; HTTP Response Cache
    cachedResponse      dq 0
    cachedResponseLen   dd 0
    cachedHeaderLen     dd 0

    cachedPngResponse   dq 0
    cachedPngLen        dd 0
    cachedPngHeaderLen  dd 0
    
    filename            db "html/index.html", 0
    filenamePng         db "html/httpdLite.png", 0
    
    ; Response components
    headerPart1         db "HTTP/1.1 200 OK", 13, 10, "Content-Type: text/html", 13, 10, "Connection: close", 13, 10, "Content-Length: ", 0
    headerPart2         db 13, 10, 13, 10, 0

    headerPngPart1      db "HTTP/1.1 200 OK", 13, 10, "Content-Type: image/png", 13, 10, "Connection: close", 13, 10, "Content-Length: ", 0

.code

; ---------------------------------------------------------
; LoadContent
; Purpose:  Reads index.html and prepares global cachedResponse
; ---------------------------------------------------------
LoadContent proc private
    sub rsp, 88             ; Shadow space + locals

    ; 1. Open File
    lea rcx, [filename]
    mov rdx, GENERIC_READ
    mov r8, FILE_SHARE_READ
    mov r9, 0               ; Security
    mov qword ptr [rsp + 32], OPEN_EXISTING
    mov qword ptr [rsp + 40], FILE_ATTRIBUTE_NORMAL
    mov qword ptr [rsp + 48], 0 ; Template
    call CreateFileA
    
    cmp rax, INVALID_HANDLE_VALUE
    je err_load

    mov rbx, rax            ; File Handle
    
    ; 2. Get File Size
    mov rcx, rbx
    mov rdx, 0
    call GetFileSize
    mov rsi, rax            ; File Size (RSI)
    
    ; 3. Calculate Buffer Size
    ; Len(Part1) + 20 (Int) + Len(Part2) + FileSize
    lea rcx, [headerPart1]
    call StrLen
    mov rdi, rax            ; Running total (RDI)
    add rdi, 20
    
    lea rcx, [headerPart2]
    call StrLen
    add rdi, rax
    add rdi, rsi            ; + FileSize
    
    ; 4. Allocate Buffer
    call GetProcessHeap
    mov rcx, rax
    mov rdx, 8              ; HEAP_ZERO_MEMORY
    mov r8, rdi
    call HeapAlloc
    test rax, rax
    jz err_load
    
    mov [cachedResponse], rax
    mov r12, rax            ; Current Ptr (R12)
    
    ; 5. Construct Response
    ; Copy Part 1
    lea rcx, [headerPart1]
    call StrLen
    mov r13, rax            ; Len1
    
    mov rcx, r12
    lea rdx, [headerPart1]
    mov r8, r13
    call MemCpy
    add r12, r13
    
    ; Convert FileSize to String
    mov rcx, rsi
    mov rdx, r12
    call IntToDecString
    add r12, rax            ; Advance by digits
    
    ; Copy Part 2
    lea rcx, [headerPart2]
    call StrLen
    mov r13, rax            ; Len2
    
    mov rcx, r12
    lea rdx, [headerPart2]
    mov r8, r13
    call MemCpy
    add r12, r13
    
    ; Calculate Header Length
    mov rax, r12
    sub rax, [cachedResponse]
    mov [cachedHeaderLen], eax

    ; Read File Content
    mov rcx, rbx            ; hFile
    mov rdx, r12            ; Buffer ptr
    mov r8, rsi             ; Bytes to Read
    lea r9, [rsp + 64]      ; BytesRead (scratch)
    mov qword ptr [rsp + 32], 0 ; Overlapped
    call ReadFile
    
    ; Close Handle
    mov rcx, rbx
    call CloseHandle
    
    ; Calculate Final Length
    mov rax, r12
    sub rax, [cachedResponse]
    add rax, rsi            ; + FileContent bytes
    mov [cachedResponseLen], eax
    
    add rsp, 88
    ret

err_load:
    lea rcx, [msgLoadFail]
    call PrintString
    mov rcx, 1
    call ExitProcess
LoadContent endp

; ---------------------------------------------------------
; LoadPngContent
; Purpose:  Reads httpdLite.png and prepares global cachedPngResponse
; ---------------------------------------------------------
LoadPngContent proc private
    sub rsp, 88             ; Shadow space + locals

    ; 1. Open File
    lea rcx, [filenamePng]
    mov rdx, GENERIC_READ
    mov r8, FILE_SHARE_READ
    mov r9, 0               ; Security
    mov qword ptr [rsp + 32], OPEN_EXISTING
    mov qword ptr [rsp + 40], FILE_ATTRIBUTE_NORMAL
    mov qword ptr [rsp + 48], 0 ; Template
    call CreateFileA
    
    cmp rax, INVALID_HANDLE_VALUE
    je err_load_png

    mov rbx, rax            ; File Handle
    
    ; 2. Get File Size
    mov rcx, rbx
    mov rdx, 0
    call GetFileSize
    mov rsi, rax            ; File Size (RSI)
    
    ; 3. Calculate Buffer Size
    lea rcx, [headerPngPart1]
    call StrLen
    mov rdi, rax            ; Running total (RDI)
    add rdi, 20
    
    lea rcx, [headerPart2] ; Reuse headerPart2 (CRLFs)
    call StrLen
    add rdi, rax
    add rdi, rsi            ; + FileSize
    
    ; 4. Allocate Buffer
    call GetProcessHeap
    mov rcx, rax
    mov rdx, 8              ; HEAP_ZERO_MEMORY
    mov r8, rdi
    call HeapAlloc
    test rax, rax
    jz err_load_png
    
    mov [cachedPngResponse], rax
    mov r12, rax            ; Current Ptr (R12)
    
    ; 5. Construct Response
    ; Copy Part 1
    lea rcx, [headerPngPart1]
    call StrLen
    mov r13, rax            ; Len1
    
    mov rcx, r12
    lea rdx, [headerPngPart1]
    mov r8, r13
    call MemCpy
    add r12, r13
    
    ; Convert FileSize to String
    mov rcx, rsi
    mov rdx, r12
    call IntToDecString
    add r12, rax            ; Advance by digits
    
    ; Copy Part 2
    lea rcx, [headerPart2]
    call StrLen
    mov r13, rax            ; Len2
    
    mov rcx, r12
    lea rdx, [headerPart2]
    mov r8, r13
    call MemCpy
    add r12, r13
    
    ; Calculate Header Length
    mov rax, r12
    sub rax, [cachedPngResponse]
    mov [cachedPngHeaderLen], eax

    ; Read File Content
    mov rcx, rbx            ; hFile
    mov rdx, r12            ; Buffer ptr
    mov r8, rsi             ; Bytes to Read
    lea r9, [rsp + 64]      ; BytesRead (scratch)
    mov qword ptr [rsp + 32], 0 ; Overlapped
    call ReadFile
    
    ; Close Handle
    mov rcx, rbx
    call CloseHandle
    
    ; Calculate Final Length
    mov rax, r12
    sub rax, [cachedPngResponse]
    add rax, rsi            ; + FileContent bytes
    mov [cachedPngLen], eax
    
    add rsp, 88
    ret

err_load_png:
    ; For now, just print error and continue (or exit)
    ; We'll reuse msgLoadFail context conceptually, but maybe print a different char or just fail
    lea rcx, [msgLoadFail] 
    call PrintString
    mov rcx, 1
    call ExitProcess
LoadPngContent endp

; ---------------------------------------------------------
; Main Entry Point
; ---------------------------------------------------------
main proc
    ; Allocate shadow space + locals
    sub rsp, 88             

    call InitUtils
    call InitNetwork
    test rax, rax
    jnz exit_proc
    
    call InitMemory
    
    call LoadContent
    call LoadPngContent

    lea rcx, [msgStart]
    call PrintString

    ; 1. Create I/O Completion Port
    ; CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 0)
    mov rcx, INVALID_HANDLE_VALUE
    mov rdx, 0
    mov r8, 0
    mov r9, 0
    call CreateIoCompletionPort
    test rax, rax
    jz err_iocp
    mov [hIOCP], rax
    mov rsi, rax            ; Keep hIOCP in RSI (non-volatile)

    ; 2. Determine Number of Processors
    lea rcx, [sysInfo]
    call GetSystemInfo
    
    ; NumberOfProcessors is at offset 32 (DWORD) in SYSTEM_INFO
    mov eax, dword ptr [sysInfo + 32]
    
    ; 3. Create Worker Threads (NumProcessors * 2)
    add eax, eax            ; * 2
    mov rdi, rax            ; Loop counter
    
thread_loop:
    test rdi, rdi
    jz threads_created
    
    ; CreateThread(NULL, 0, WorkerThread, hIOCP, 0, NULL)
    mov rcx, 0              ; Security Attributes
    mov rdx, 0              ; Stack Size
    mov r8, WorkerThread    ; Start Address
    mov r9, rsi             ; Parameter (hIOCP)
    
    mov qword ptr [rsp + 32], 0 ; Flags
    mov qword ptr [rsp + 40], 0 ; ThreadId
    
    call CreateThread
    test rax, rax
    jz err_thread
    
    ; Close thread handle immediately (we don't need to join them)
    mov rcx, rax
    call CloseHandle
    
    dec rdi
    jmp thread_loop

threads_created:

    ; 4. Create Listener Socket
    mov rcx, DEFAULT_PORT
    call CreateListener
    cmp rax, INVALID_SOCKET
    je clean_exit
    mov rdi, rax            ; Save server socket in RDI

accept_loop:
    ; 5. Accept a new connection
    mov rcx, rdi
    mov rdx, 0
    mov r8, 0
    call accept
    cmp rax, INVALID_SOCKET
    je err_accept

    ; Connection successful. Socket handle is in RAX.
    mov rbx, rax            ; Client Socket

    ; Enable TCP NoDelay
    mov rcx, rbx
    call EnableNoDelay

    ; 6. Associate with IOCP and Post Recv
    mov rcx, rbx
    mov rdx, rsi            ; hIOCP
    call PostAccept

    jmp accept_loop

err_iocp:
    lea rcx, [msgIOCPErr]
    call PrintString
    jmp exit_proc

err_thread:
    lea rcx, [msgThreadErr]
    call PrintString
    jmp clean_exit

err_socket:
    lea rcx, [msgSocketErr]
    call PrintString
    jmp clean_exit

err_bind:
    lea rcx, [msgBindErr]
    call PrintString
    jmp clean_exit

err_listen:
    lea rcx, [msgListenErr]
    call PrintString
    jmp clean_exit

err_accept:
    lea rcx, [msgAcceptErr]
    call PrintString
    jmp accept_loop

clean_exit:
    mov rcx, rdi
    call closesocket
    call WSACleanup

exit_proc:
    mov rcx, 0
    call ExitProcess

main endp
end