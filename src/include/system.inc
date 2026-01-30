; Win32 System Constants
STD_OUTPUT_HANDLE equ -11
INVALID_HANDLE_VALUE equ -1
INFINITE          equ 0FFFFFFFFh

; File I/O Constants
GENERIC_READ      equ 80000000h
FILE_SHARE_READ   equ 1
OPEN_EXISTING     equ 3
FILE_ATTRIBUTE_NORMAL equ 128

; Standard Types
NULL              equ 0
TRUE              equ 1
FALSE             equ 0

; Memory Constants
HEAP_ZERO_MEMORY  equ 8

; Externs (Kernel32)
extern CreateIoCompletionPort:proc
extern GetQueuedCompletionStatus:proc
extern CreateThread:proc
extern CloseHandle:proc
extern GetProcessHeap:proc
extern HeapAlloc:proc
extern HeapFree:proc
extern ExitThread:proc
extern GetSystemInfo:proc
extern InitializeSListHead:proc
extern InterlockedPushEntrySList:proc
extern InterlockedPopEntrySList:proc
extern CreateFileA:proc
extern GetFileSize:proc
extern ReadFile:proc


; SLIST Structures
SLIST_ENTRY STRUCT
    Next QWORD ?
SLIST_ENTRY ENDS

SLIST_HEADER STRUCT
    Alignment   QWORD 2 DUP(?)
SLIST_HEADER ENDS
