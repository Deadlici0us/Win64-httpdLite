option casemap:none
include constants.inc

extern GetProcessHeap:proc
extern HeapAlloc:proc
extern HeapFree:proc
extern InitializeSListHead:proc
extern InterlockedPushEntrySList:proc
extern InterlockedPopEntrySList:proc

.data
    ALIGN 16
    FreeListHead SLIST_HEADER <>
    hHeap        QWORD 0

.code

; ---------------------------------------------------------
; InitMemory
; Purpose:  Initialize the memory subsystem (SList and Heap Handle)
; ---------------------------------------------------------
InitMemory proc public
    sub rsp, 40
    
    ; Initialize SList Head
    lea rcx, [FreeListHead]
    call InitializeSListHead
    
    ; Cache Process Heap Handle
    call GetProcessHeap
    mov [hHeap], rax
    
    add rsp, 40
    ret
InitMemory endp

; ---------------------------------------------------------
; AllocContext
; Purpose:  Allocates an IO_CONTEXT from the Pool or Heap
; Returns:  RAX = Pointer to IO_CONTEXT, or NULL
; ---------------------------------------------------------
AllocContext proc public
    sub rsp, 40

    ; Try to pop from the list
    lea rcx, [FreeListHead]
    call InterlockedPopEntrySList
    
    test rax, rax
    jz alloc_new
    
    ; Found in pool. RAX points to poolEntry (Offset 32).
    ; We need to return the base of IO_CONTEXT (Offset 0).
    sub rax, 32
    
    ; Zero out the WSAOVERLAPPED (first 32 bytes)
    ; This is critical as reused contexts have dirty state.
    ; Optimization: Use SSE to clear 32 bytes (2 x 16 bytes)
    pxor xmm0, xmm0
    movups [rax], xmm0      ; Offsets 0-15
    movups [rax+16], xmm0   ; Offsets 16-31
    
    jmp done

alloc_new:
    ; List empty, allocate from Heap
    mov rcx, [hHeap]
    mov rdx, 8              ; HEAP_ZERO_MEMORY
    mov r8, sizeof IO_CONTEXT
    call HeapAlloc
    ; HeapAlloc with ZERO_MEMORY already clears it.

done:
    add rsp, 40
    ret
AllocContext endp

; ---------------------------------------------------------
; FreeContext
; Purpose:  Returns an IO_CONTEXT to the Pool
; Args:     RCX = Pointer to IO_CONTEXT
; ---------------------------------------------------------
FreeContext proc public
    sub rsp, 40
    
    ; We need to push the address of poolEntry (Offset 32)
    ; RCX is currently Base (Offset 0)
    lea rdx, [rcx + 32]     ; RDX = Item
    lea rcx, [FreeListHead] ; RCX = ListHead
    
    call InterlockedPushEntrySList
    
    add rsp, 40
    ret
FreeContext endp

end
