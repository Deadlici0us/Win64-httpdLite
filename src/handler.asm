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

extern HandleHttpRequest:proc

.data
    msgWorkerStart  db "Worker Thread Started.", 13, 10, 0
    msgRecvErr      db "WSARecv Failed.", 13, 10, 0
    msgSendErr      db "WSASend Failed.", 13, 10, 0
    msgClientDis    db "Client Disconnected.", 13, 10, 0
    msgAssocErr     db "Assoc Failed.", 13, 10, 0
    msgAllocErr     db "Alloc Failed.", 13, 10, 0

.code

; ---------------------------------------------------------
; WorkerThread
; Purpose:  The IOCP Loop. Waits for completion packets and dispatch.
; Args:     RCX = Completion Port Handle
; ---------------------------------------------------------
WorkerThread proc public
    push rbx
    push rsi
    push rdi
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
    ; Hand off to HTTP Handler
    ; RCX = IO_CONTEXT, RDX = BytesTransferred
    mov rcx, rsi
    mov edx, [rsp + 56]     ; Load Bytes Transferred
    
    call HandleHttpRequest
    
    test rax, rax
    jnz close_connection    ; If 1, Error
    
    ; If 0, Success/Pending. Back to loop.
    jmp iocp_loop

handle_send:
    ; Send complete. Close connection.
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
    mov [rsi + IO_CONTEXT.wsaBufs.len], BUFFER_SIZE
    lea rax, [rsi + IO_CONTEXT.buffer]
    mov [rsi + IO_CONTEXT.wsaBufs.buf], rax
    
    ; 4. WSARecv
    mov rcx, rbx
    lea rdx, [rsi + IO_CONTEXT.wsaBufs]
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