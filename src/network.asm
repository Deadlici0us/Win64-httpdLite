option casemap:none
include constants.inc

extern WSAStartup:proc
extern socket:proc
extern bind:proc
extern listen:proc
extern htons:proc
extern closesocket:proc
extern setsockopt:proc

.data
    wsaData db 400 dup(0)
    optVal  dd 1

.code

InitNetwork proc public
    sub rsp, 40
    mov rcx, WSA_VERSION
    lea rdx, wsaData
    call WSAStartup
    add rsp, 40
    ret
InitNetwork endp

EnableNoDelay proc public
    ; RCX = socket
    sub rsp, 40             ; Shadow space + alignment
    
    ; setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &optVal, sizeof(optVal))
    ; RCX = socket (already there)
    mov rdx, IPPROTO_TCP    ; Level
    mov r8, TCP_NODELAY     ; OptName
    lea r9, optVal          ; OptVal (pointer to 1)
    
    ; 5th arg on stack
    mov dword ptr [rsp + 32], 4 ; sizeof(int)
    
    call setsockopt
    
    add rsp, 40
    ret
EnableNoDelay endp

CreateListener proc public
    ; RCX = port
    push rsi
    push rdi
    sub rsp, 56             ; Shadow space + sockaddr_in (16) + alignment

    mov rsi, rcx            ; Save port

    ; socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    mov rcx, AF_INET
    mov rdx, SOCK_STREAM
    mov r8, IPPROTO_TCP
    call socket
    cmp rax, INVALID_SOCKET
    je done

    mov rdi, rax            ; Save socket

    ; Set SO_REUSEADDR
    ; setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &optVal, sizeof(optVal))
    mov rcx, rdi
    mov rdx, SOL_SOCKET
    mov r8, SO_REUSEADDR
    lea r9, optVal          ; Reuse existing optVal (1) from .data
    mov dword ptr [rsp + 32], 4 ; sizeof(int)
    call setsockopt

    ; Prepare sockaddr_in using the struct
    lea rdx, [rsp + 32]
    mov word ptr [rdx + sockaddr_in.sin_family], AF_INET
    
    mov rcx, rsi            ; port
    call htons
    lea rdx, [rsp + 32]
    mov word ptr [rdx + sockaddr_in.sin_port], ax
    mov dword ptr [rdx + sockaddr_in.sin_addr], INADDR_ANY

    ; bind(socket, sockaddr, sizeof)
    mov rcx, rdi
    lea rdx, [rsp + 32]
    mov r8, size sockaddr_in
    call bind
    cmp eax, SOCKET_ERROR
    je err_close

    ; listen(socket, SOMAXCONN)
    mov rcx, rdi
    mov rdx, SOMAXCONN
    call listen
    cmp eax, SOCKET_ERROR
    je err_close

    mov rax, rdi            ; Return socket
    jmp done

err_close:
    mov rcx, rdi
    call closesocket
    mov rax, INVALID_SOCKET

done:
    add rsp, 56
    pop rdi
    pop rsi
    ret
CreateListener endp

end