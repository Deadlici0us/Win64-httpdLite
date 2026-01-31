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

; ---------------------------------------------------------
; StrCompare (Case Insensitive)
; Args:     RCX = String1, RDX = String2
; Returns:  RAX = 1 (Match), 0 (No Match)
; ---------------------------------------------------------
StrCompareCaseInsensitive proc public
    push rsi
    push rdi
    
    mov rsi, rcx
    mov rdi, rdx
    
cmp_loop:
    mov al, [rsi]
    mov dl, [rdi]
    
    ; Check for end of strings
    test al, al
    jz check_end
    test dl, dl
    jz no_match     ; s1 has chars, s2 ended
    
    ; Lowercase conversion for comparison
    or al, 20h
    or dl, 20h
    
    cmp al, dl
    jne no_match
    
    inc rsi
    inc rdi
    jmp cmp_loop
    
check_end:
    test dl, dl
    jnz no_match    ; s1 ended, s2 has chars
    
    mov rax, 1      ; Match
    pop rdi
    pop rsi
    ret

no_match:
    xor rax, rax
    pop rdi
    pop rsi
    ret
StrCompareCaseInsensitive endp

; ---------------------------------------------------------
; StrCompare (Case Sensitive)
; Args:     RCX = String1, RDX = String2
; Returns:  RAX = 1 (Match), 0 (No Match)
; ---------------------------------------------------------
StrCompare proc public
    push rsi
    push rdi
    
    mov rsi, rcx
    mov rdi, rdx
    
cmp_loop_cs:
    mov al, [rsi]
    mov dl, [rdi]
    
    cmp al, dl
    jne no_match_cs
    
    test al, al
    jz match_cs
    
    inc rsi
    inc rdi
    jmp cmp_loop_cs
    
match_cs:
    mov rax, 1
    pop rdi
    pop rsi
    ret

no_match_cs:
    xor rax, rax
    pop rdi
    pop rsi
    ret
StrCompare endp

; ---------------------------------------------------------
; StrCopy
; Purpose:  Copy null-terminated string
; Args:     RCX = Dest, RDX = Source
; ---------------------------------------------------------
StrCopy proc public
    push rsi
    push rdi
    
    mov rdi, rcx
    mov rsi, rdx
    
copy_loop:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz copy_loop
    
    pop rdi
    pop rsi
    ret
StrCopy endp

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
    mov byte ptr [rdi+1], 0 ; Null terminate
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

    mov byte ptr [rdi], 0 ; Null terminate
    
done_itoa:
    pop rdi
    pop rbx
    ret
IntToDecString endp

end