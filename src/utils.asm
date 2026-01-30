option casemap:none
include constants.inc

extern GetStdHandle:proc
extern WriteFile:proc

.data
    hStdOut dq 0

.code

StrLen proc public
    xor rax, rax
    test rcx, rcx
    jz done
next:
    cmp byte ptr [rcx + rax], 0
    je done
    inc rax
    jmp next
done:
    ret
StrLen endp

InitUtils proc public
    sub rsp, 40             ; Shadow space + alignment
    mov rcx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [hStdOut], rax
    add rsp, 40
    ret
InitUtils endp

PrintString proc public
    push rbx                ; Save non-volatile RBX
    sub rsp, 48             ; Shadow space + written_ptr + alignment

    mov rbx, rcx            ; Store string pointer
    mov r10, [hStdOut]

    mov rcx, rbx
    call StrLen
    
    mov rcx, r10            ; hFile
    mov rdx, rbx            ; lpBuffer
    mov r8, rax             ; nNumberOfBytesToWrite
    lea r9, [rsp + 40]      ; lpNumberOfBytesWritten
    mov qword ptr [rsp + 32], 0 ; lpOverlapped
    call WriteFile

    add rsp, 48
    pop rbx
    ret
PrintString endp

MemCpy proc public
    ; RCX = Dest, RDX = Source, R8 = Count
    test r8, r8
    jz done_memcpy
    push rsi
    push rdi
    mov rsi, rdx
    mov rdi, rcx
    mov rcx, r8
    rep movsb
    pop rdi
    pop rsi
done_memcpy:
    ret
MemCpy endp

IntToDecString proc public
    ; RCX = Value, RDX = Buffer
    ; Returns: RAX = Length
    push rbx
    push rdi
    
    mov rax, rcx
    mov rdi, rdx
    mov rbx, 10
    xor rcx, rcx    ; Digit count
    
    test rax, rax
    jnz loop_digits
    mov byte ptr [rdi], '0'
    mov rax, 1
    jmp done_itoa
    
loop_digits:
    xor rdx, rdx
    div rbx
    push rdx        ; Push remainder
    inc rcx
    test rax, rax
    jnz loop_digits
    
    mov rax, rcx    ; Return length
    
store_digits:
    pop rdx
    add dl, '0'
    mov [rdi], dl
    inc rdi
    loop store_digits
    
done_itoa:
    pop rdi
    pop rbx
    ret
IntToDecString endp

end