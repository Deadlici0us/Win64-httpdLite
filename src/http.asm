option casemap:none
include constants.inc

extern WSASend:proc
extern WSAGetLastError:proc
extern StrLen:proc
extern PrintString:proc
extern FindCacheEntry:proc

.data
    response405     db "HTTP/1.1 405 Method Not Allowed", 13, 10, "Connection: close", 13, 10, "Content-Length: 0", 13, 10, 13, 10, 0
    response404     db "HTTP/1.1 404 Not Found", 13, 10, "Connection: close", 13, 10, "Content-Length: 0", 13, 10, 13, 10, 0
    defaultPage     db "index.html", 0
    
    ; Debug/Log Strings
    msgRecvTooShort db "Request too short.", 13, 10, 0

.code

; ---------------------------------------------------------
; ParsePath
; Purpose:  Extracts the path from the HTTP request line securely
; Args:     RCX = Buffer Pointer
;           RDX = Max Length (Bytes Transferred)
; Returns:  RAX = Pointer to Path String (null terminated), or 0 if failed
; ---------------------------------------------------------
ParsePath proc private
    push rbx
    push rsi
    push rdi
    
    mov rsi, rcx            ; Start of Buffer
    mov rdi, rcx
    add rdi, rdx            ; End of Buffer (Limit)
    
    ; 1. Find first space (After Method)
    mov rax, rsi
scan_space1:
    cmp rax, rdi
    jae fail_parse          ; Hit end of buffer
    cmp byte ptr [rax], ' '
    je found_space1
    inc rax
    jmp scan_space1
    
found_space1:
    inc rax                 ; Skip space
    mov rbx, rax            ; Start of Path
    
    ; 2. Find second space (End of Path)
scan_space2:
    cmp rax, rdi
    jae fail_parse          ; Hit end of buffer
    cmp byte ptr [rax], ' '
    je found_space2
    inc rax
    jmp scan_space2

found_space2:
    ; Valid path found between RBX and RAX
    ; Null terminate it.
    ; SAFETY: RAX is strictly < RDI (End of Buffer), so [rax] is within valid memory (it was the space)
    mov byte ptr [rax], 0
    
    mov rax, rbx            ; Return Start of Path
    
    ; Sanitize: If path starts with '/', skip it
    cmp byte ptr [rax], '/'
    jne check_empty
    inc rax
    
check_empty:
    ; If empty string (originally "/"), map to index.html
    cmp byte ptr [rax], 0
    jne done_parse
    lea rax, [defaultPage]
    
done_parse:
    pop rdi
    pop rsi
    pop rbx
    ret

fail_parse:
    xor rax, rax
    pop rdi
    pop rsi
    pop rbx
    ret
ParsePath endp

; ---------------------------------------------------------
; HandleHttpRequest
; Purpose:  Parses and dispatches the HTTP request
; Args:     RCX = Pointer to IO_CONTEXT
;           RDX = Bytes Transferred
; Returns:  RAX = 0 (Success/Pending), 1 (Error/Close)
; ---------------------------------------------------------
HandleHttpRequest proc public
    push rbx
    push rsi
    push rdi
    push r12
    sub rsp, 72             ; Shadow space + alignment

    mov rsi, rcx            ; IO_CONTEXT
    mov r12, rdx            ; Bytes Transferred

    lea rbx, [rsi + IO_CONTEXT.buffer] ; Buffer

    ; Check Method
    ; Ensure we have enough bytes for at least "GET /" (5 bytes)
    cmp r12, 5
    jl send_405             ; Too short, treat as invalid/405

    mov eax, dword ptr [rbx]
    cmp eax, HTTP_METHOD_GET
    je do_get
    cmp eax, HTTP_METHOD_HEAD
    je do_head
    
    jmp send_405

do_get:
    ; Parse Path
    mov rcx, rbx
    mov rdx, r12
    call ParsePath
    test rax, rax
    jz send_404             ; Parse failed
    
    mov rdi, rax            ; Path
    
    ; DEBUG: Print Path
    mov rcx, rdi
    call PrintString
    
    ; Lookup Cache
    mov rcx, rdi
    call FindCacheEntry
    test rax, rax
    jz send_404
    
    mov rdx, rax            ; CachedFile Ptr
    
    ; Setup Send (GET: Header + Content)
    ; Buffer 0: Header
    mov rax, [rdx + CachedFile.Header]
    mov [rsi + IO_CONTEXT.wsaBufs.buf], rax
    mov eax, [rdx + CachedFile.HeaderLen]
    mov [rsi + IO_CONTEXT.wsaBufs.len], eax
    
    ; Buffer 1: Content
    mov rax, [rdx + CachedFile.Content]
    mov [rsi + IO_CONTEXT.wsaBufs + 16 + WSABUF.buf], rax
    mov eax, [rdx + CachedFile.ContentLen]
    mov [rsi + IO_CONTEXT.wsaBufs + 16 + WSABUF.len], eax
    
    mov r8, 2               ; Buffer Count
    jmp send_response

do_head:
    ; Parse Path
    mov rcx, rbx
    mov rdx, r12
    call ParsePath
    test rax, rax
    jz send_404
    
    mov rdi, rax
    
    mov rcx, rdi
    call FindCacheEntry
    test rax, rax
    jz send_404
    
    mov rdx, rax
    
    ; Setup Send (HEAD: Header Only)
    mov rax, [rdx + CachedFile.Header]
    mov [rsi + IO_CONTEXT.wsaBufs.buf], rax
    mov eax, [rdx + CachedFile.HeaderLen]
    mov [rsi + IO_CONTEXT.wsaBufs.len], eax
    
    mov r8, 1               ; Buffer Count
    jmp send_response

send_404:
    lea rax, [response404]
    mov [rsi + IO_CONTEXT.wsaBufs.buf], rax
    lea rcx, [response404]
    call StrLen
    mov [rsi + IO_CONTEXT.wsaBufs.len], eax
    mov r8, 1
    jmp send_response

send_405:
    lea rax, [response405]
    mov [rsi + IO_CONTEXT.wsaBufs.buf], rax
    lea rcx, [response405]
    call StrLen
    mov [rsi + IO_CONTEXT.wsaBufs.len], eax
    mov r8, 1
    jmp send_response

send_response:
    ; Set OpType
    mov [rsi + IO_CONTEXT.opType], OP_SEND
    
    ; WSASend
    mov rcx, [rsi + IO_CONTEXT.socket]
    lea rdx, [rsi + IO_CONTEXT.wsaBufs]
    ; r8 is Buffer Count
    lea r9, [rsp + 56]      ; lpNumberOfBytesSent (Scratch)
    
    mov qword ptr [rsp + 32], 0     ; Flags
    mov qword ptr [rsp + 40], rsi   ; Overlapped
    mov qword ptr [rsp + 48], 0     ; CompletionRoutine
    
    call WSASend
    
    cmp eax, SOCKET_ERROR
    je check_error
    
    ; Success (Immediate)
    mov rax, 0
    jmp done
    
check_error:
    call WSAGetLastError
    cmp eax, WSA_IO_PENDING
    je pending
    
    ; Real Error
    mov rax, 1
    jmp done

pending:
    mov rax, 0
    jmp done

done:
    add rsp, 72
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
HandleHttpRequest endp

end