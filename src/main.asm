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

extern InitCache:proc

.data
    ; Null-terminated strings for console logging
    msgStart        db "Starting Echo Server on port 8080 (IOCP)...", 13, 10, 0
    msgSocketErr    db "Socket creation failed.", 13, 10, 0
    msgBindErr      db "Bind failed.", 13, 10, 0
    msgListenErr    db "Listen failed.", 13, 10, 0
    msgAcceptErr    db "Accept failed.", 13, 10, 0
    msgIOCPErr      db "CreateIoCompletionPort failed.", 13, 10, 0
    msgThreadErr    db "CreateThread failed.", 13, 10, 0
    
    hIOCP           dq 0
    sysInfo         BYTE 48 DUP(0) ; SYSTEM_INFO struct (approx size)

.code

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
    
    ; Initialize File Cache (Scans html/ folder)
    call InitCache

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