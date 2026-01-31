; Win32 System Constants
STD_OUTPUT_HANDLE equ -11
INVALID_HANDLE_VALUE equ -1
INFINITE          equ 0FFFFFFFFh

; File I/O Constants
GENERIC_READ      equ 80000000h
FILE_SHARE_READ   equ 1
OPEN_EXISTING     equ 3
FILE_ATTRIBUTE_NORMAL equ 128
FILE_ATTRIBUTE_DIRECTORY equ 10h

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
extern FindFirstFileA:proc
extern FindNextFileA:proc
extern FindClose:proc

; SLIST Structures
SLIST_ENTRY STRUCT
    Next QWORD ?
SLIST_ENTRY ENDS

SLIST_HEADER STRUCT
    Alignment   QWORD 2 DUP(?)
SLIST_HEADER ENDS

; File Search Structure
WIN32_FIND_DATAA STRUCT
    dwFileAttributes    DWORD ?
    ftCreationTimeLow   DWORD ?
    ftCreationTimeHigh  DWORD ?
    ftLastAccessTimeLow DWORD ?
    ftLastAccessTimeHigh DWORD ?
    ftLastWriteTimeLow  DWORD ?
    ftLastWriteTimeHigh DWORD ?
    nFileSizeHigh       DWORD ?
    nFileSizeLow        DWORD ?
    dwReserved0         DWORD ?
    dwReserved1         DWORD ?
    cFileName           BYTE 260 DUP(?)
    cAlternateFileName  BYTE 14 DUP(?)
    ; Padding to align structure size if needed, but MASM handles field offsets
WIN32_FIND_DATAA ENDS

; Cached File Structure (Linked List)
CachedFile STRUCT
    Next        QWORD ?         ; Pointer to next node
    FileName    QWORD ?         ; Pointer to filename string
    Content     QWORD ?         ; Pointer to file content
    ContentLen  DWORD ?         ; Length of content
    Header      QWORD ?         ; Pointer to HTTP Header
    HeaderLen   DWORD ?         ; Length of Header
    Padding     DWORD ?         ; Alignment
CachedFile ENDS
