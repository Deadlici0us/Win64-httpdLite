option casemap:none
include constants.inc

extern WSARecv:proc
extern WSASend:proc
extern closesocket:proc
extern WSAGetLastError:proc
extern PrintString:proc
extern GetProcessHeap:proc
extern HeapAlloc:proc
extern HeapFree:proc
extern GetQueuedCompletionStatus:proc
extern ExitThread:proc

extern AllocContext:proc
extern FreeContext:proc

extern cachedResponse:qword
extern cachedResponseLen:dword
extern cachedHeaderLen:dword
extern cachedPngResponse:qword
extern cachedPngLen:dword
extern cachedPngHeaderLen:dword
extern StrLen:proc

.data
    msgWorkerStart  db "Worker Thread Started.", 13, 10, 0
    msgRecvErr      db "WSARecv Failed.", 13, 10, 0
    msgSendErr      db "WSASend Failed.", 13, 10, 0
    msgClientDis    db "Client Disconnected.", 13, 10, 0
    msgAssocErr     db "Assoc Failed.", 13, 10, 0
    msgAllocErr     db "Alloc Failed.", 13, 10, 0
    response405     db "HTTP/1.1 405 Method Not Allowed", 13, 10, "Connection: close", 13, 10, "Content-Length: 0", 13, 10, 13, 10, 0
    
.code

; ---------------------------------------------------------
; CheckPath
; Purpose:  Checks if request path contains "httpdLite.png" (Case Insensitive)
; Args:     RCX = Buffer Pointer, RDX = Length
; Returns:  RAX = 1 if PNG, 0 if not
; ---------------------------------------------------------
CheckPath proc private
    mov r8, rdx         ; limit
    mov rdx, rcx        ; ptr
    
    cmp r8, 64
    jbe scan_loop
    mov r8, 64

scan_loop:
    cmp r8, 0
    jz not_found
    
    ; Check for 'h' or 'H'
    mov al, [rdx]
    or al, 20h          ; To Lower
    cmp al, 'h'
    jne next_char
    
    ; Check "httpdlite.png"
    ; We can unroll and OR 20h for each char
    
    ; +1 't'
    mov al, [rdx+1]
    or al, 20h
    cmp al, 't'
    jne next_char

    ; +2 't'
    mov al, [rdx+2]
    or al, 20h
    cmp al, 't'
    jne next_char

    ; +3 'p'
    mov al, [rdx+3]
    or al, 20h
    cmp al, 'p'
    jne next_char

    ; +4 'd'
    mov al, [rdx+4]
    or al, 20h
    cmp al, 'd'
    jne next_char

    ; +5 'l' (Lower case L)
    mov al, [rdx+5]
    or al, 20h
    cmp al, 'l'
    jne next_char

    ; +6 'i'
    mov al, [rdx+6]
    or al, 20h
    cmp al, 'i'
    jne next_char

    ; +7 't'
    mov al, [rdx+7]
    or al, 20h
    cmp al, 't'
    jne next_char

    ; +8 'e'
    mov al, [rdx+8]
    or al, 20h
    cmp al, 'e'
    jne next_char

    ; +9 '.'
    mov al, [rdx+9]
    ; No case for dot
    cmp al, '.'
    jne next_char

    ; +10 'p'
    mov al, [rdx+10]
    or al, 20h
    cmp al, 'p'
    jne next_char

    ; +11 'n'
    mov al, [rdx+11]
    or al, 20h
    cmp al, 'n'
    jne next_char

    ; +12 'g'
    mov al, [rdx+12]
    or al, 20h
    cmp al, 'g'
    jne next_char
    
    mov rax, 1
    ret

next_char:
    inc rdx
    dec r8
    jmp scan_loop

not_found:
    xor rax, rax
    ret
CheckPath endp

; ---------------------------------------------------------
; WorkerThread
; Purpose:  The IOCP Loop. Waits for completion packets and dispatch.
; Args:     RCX = Completion Port Handle
; ---------------------------------------------------------
WorkerThread proc public
    push rbx
    push rsi
    push rdi
    ; Alignment: Entry ...8 -> Push x3 -> ...0.
    ; Alloc 112 -> ...0. Correct.
    sub rsp, 112

    mov rbx, rcx            ; Save Completion Port Handle
    
    lea rcx, [msgWorkerStart]
    call PrintString

iocp_loop:
    ; GetQueuedCompletionStatus(hPort, &dwBytes, &lpKey, &lpOverlapped, INFINITE)
    mov rcx, rbx            ; hPort
    lea rdx, [rsp + 56]     ; lpNumberOfBytes
    lea r8,  [rsp + 64]     ; lpCompletionKey
    lea r9,  [rsp + 72]     ; lpOverlapped
    mov dword ptr [rsp + 32], INFINITE ; Timeout
    call GetQueuedCompletionStatus

    test rax, rax
    jz iocp_fail            ; If 0, check GetLastError/Overlapped

    ; Check if bytes transferred is 0 (Client disconnected)
    mov rax, [rsp + 72]     ; Get lpOverlapped
    mov rsi, rax            ; RSI = Pointer to IO_CONTEXT
    
    mov eax, [rsp + 56]     ; Get Bytes Transferred
    test eax, eax
    je client_disconnect

    ; Check Operation Type
    mov eax, [rsi + IO_CONTEXT.opType]
    cmp eax, OP_RECV
    je handle_recv
    cmp eax, OP_SEND
    je handle_send
    
    jmp iocp_loop

handle_recv:
    ; Data received.
    lea rdx, [rsi + IO_CONTEXT.buffer]

    ; Check for "GET " (0x20544547)
    cmp dword ptr [rdx], 20544547h
    je do_get

    ; Check for "HEAD" (0x44414548)
    cmp dword ptr [rdx], 44414548h
    je do_head
    
    ; Else 405
    jmp do_405

do_get:
    ; Check Path
    mov rcx, rdx            ; Buffer
    mov eax, [rsp + 56]     ; Bytes Transferred
    mov rdx, rax            ; Length
    call CheckPath
    test rax, rax
    jnz serve_png

    ; Default serve index.html
    mov rax, [cachedResponse]
    mov [rsi + IO_CONTEXT.wsabuf.buf], rax
    mov eax, [cachedResponseLen]
    mov [rsi + IO_CONTEXT.wsabuf.len], eax
    jmp send_response

serve_png:
    mov rax, [cachedPngResponse]
    mov [rsi + IO_CONTEXT.wsabuf.buf], rax
    mov eax, [cachedPngLen]
    mov [rsi + IO_CONTEXT.wsabuf.len], eax
    jmp send_response

do_head:
    ; Check Path for HEAD too
    lea rcx, [rsi + IO_CONTEXT.buffer]
    mov eax, [rsp + 56]
    mov rdx, rax
    call CheckPath
    test rax, rax
    jnz serve_png_head

    mov rax, [cachedResponse]
    mov [rsi + IO_CONTEXT.wsabuf.buf], rax
    mov eax, [cachedHeaderLen]
    mov [rsi + IO_CONTEXT.wsabuf.len], eax
    jmp send_response

serve_png_head:
    mov rax, [cachedPngResponse]
    mov [rsi + IO_CONTEXT.wsabuf.buf], rax
    mov eax, [cachedPngHeaderLen]
    mov [rsi + IO_CONTEXT.wsabuf.len], eax
    jmp send_response

do_405:
    lea rax, [response405]
    mov [rsi + IO_CONTEXT.wsabuf.buf], rax
    lea rcx, [response405]
    call StrLen
    mov [rsi + IO_CONTEXT.wsabuf.len], eax
    jmp send_response

send_response:
    ; Prepare for Send
    mov [rsi + IO_CONTEXT.opType], OP_SEND
    
    ; WSASend(s, lpBuffers, dwBufferCount, lpNumberOfBytesSent, dwFlags, lpOverlapped, lpCompletionRoutine)
    mov rcx, [rsi + IO_CONTEXT.socket]
    lea rdx, [rsi + IO_CONTEXT.wsabuf]
    mov r8, 1               ; Buffer Count
    lea r9, [rsp + 88]      ; lpNumberOfBytesSent (Scratch)
    mov qword ptr [rsp + 32], 0 ; dwFlags
    mov qword ptr [rsp + 40], rsi ; lpOverlapped
    mov qword ptr [rsp + 48], 0 ; lpCompletionRoutine
    call WSASend

    cmp eax, SOCKET_ERROR
    je check_pending_send
    jmp iocp_loop

check_pending_send:
    call WSAGetLastError
    cmp eax, WSA_IO_PENDING
    je iocp_loop
    ; Real error
    jmp close_connection

handle_send:
    ; Send complete. 
    ; For this simple HTTP server, we close the connection after the response.
    ; This ensures clients (like the tests) don't hang waiting for stream end.
    jmp close_connection

    ; (Old Keep-Alive Logic Removed)

check_pending_recv:
    call WSAGetLastError
    cmp eax, WSA_IO_PENDING
    je iocp_loop
    jmp close_connection

client_disconnect:
    lea rcx, [msgClientDis]
    call PrintString
    jmp close_connection

iocp_fail:
    cmp qword ptr [rsp + 72], 0 ; Check lpOverlapped
    je exit_worker
    mov rsi, [rsp + 72]     ; Get Context
    jmp close_connection

close_connection:
    mov rcx, [rsi + IO_CONTEXT.socket]
    call closesocket
    mov rcx, rsi
    call FreeContext
    jmp iocp_loop

exit_worker:
    add rsp, 112
    pop rdi
    pop rsi
    pop rbx
    mov rcx, 0
    call ExitThread
    ret
WorkerThread endp

; ---------------------------------------------------------
; PostAccept
; Purpose:  Called by Main to associate socket and post first Recv
; Args:     RCX = Socket, RDX = hIOCP
; ---------------------------------------------------------
PostAccept proc public
    push rbx
    push rdi
    push rsi                ; Preserve RSI!
    sub rsp, 80

    mov rbx, rcx            ; Socket
    mov rdi, rdx            ; hIOCP

    ; 1. Associate Socket
    mov rcx, rbx
    mov rdx, rdi
    mov r8, rbx             ; Key
    mov r9, 0
    call CreateIoCompletionPort
    test rax, rax
    jz assoc_fail

    ; 2. Alloc Context
    call AllocContext
    test rax, rax
    jz alloc_fail
    mov rsi, rax            ; Context

    ; 3. Setup
    mov [rsi + IO_CONTEXT.socket], rbx
    mov [rsi + IO_CONTEXT.opType], OP_RECV
    mov [rsi + IO_CONTEXT.wsabuf.len], BUFFER_SIZE
    lea rax, [rsi + IO_CONTEXT.buffer]
    mov [rsi + IO_CONTEXT.wsabuf.buf], rax
    
    ; 4. WSARecv
    mov rcx, rbx
    lea rdx, [rsi + IO_CONTEXT.wsabuf]
    mov r8, 1               ; Buffer Count
    lea r9, [rsp + 64]      ; BytesRecvd (Local)
    
    ; Flags
    mov qword ptr [rsp + 56], 0 ; Local Flags var
    lea rax, [rsp + 56]
    mov [rsp + 32], rax     ; lpFlags pointer
    
    mov qword ptr [rsp + 40], rsi ; lpOverlapped
    mov qword ptr [rsp + 48], 0 ; CompletionRoutine
    call WSARecv

    cmp eax, SOCKET_ERROR
    je check_pending_recv_init
    jmp done

check_pending_recv_init:
    call WSAGetLastError
    cmp eax, WSA_IO_PENDING
    je done
    ; Error
    jmp error_cleanup

done:
    add rsp, 80
    pop rsi
    pop rdi
    pop rbx
    ret

assoc_fail:
    lea rcx, [msgAssocErr]
    call PrintString
    jmp done

alloc_fail:
    lea rcx, [msgAllocErr]
    call PrintString
    jmp done

error_cleanup:
    lea rcx, [msgRecvErr]
    call PrintString
    
    mov rcx, rbx
    call closesocket
    mov rcx, rsi
    call FreeContext
    jmp done

PostAccept endp

end