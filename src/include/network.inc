; Winsock2 Constants and Structures
AF_INET           equ 2
SOCK_STREAM       equ 1
IPPROTO_TCP       equ 6
SOMAXCONN         equ 07FFFFFFFh
INADDR_ANY        equ 0
WSA_VERSION       equ 0202h

; Performance Optimization: Disable Nagle's Algorithm
TCP_NODELAY       equ 1

; Socket Options
SOL_SOCKET        equ 0FFFFh
SO_REUSEADDR      equ 4

; Configuration
BUFFER_SIZE       equ 1024
DEFAULT_PORT      equ 8080

; Socket Error Codes
INVALID_SOCKET    equ 0FFFFFFFFFFFFFFFFh ; Explicit 64-bit -1
SOCKET_ERROR      equ -1
WSAENOTSOCK       equ 10038
WSAEINVAL         equ 10022
WSAEFAULT         equ 10014
WSA_IO_PENDING    equ 997

; Operation Types
OP_RECV           equ 0
OP_SEND           equ 1

; HTTP Constants
HTTP_METHOD_GET   equ 20544547h ; "GET " (Little Endian)
HTTP_METHOD_HEAD  equ 44414548h ; "HEAD" (Little Endian)

; Structures
sockaddr_in STRUCT
    sin_family WORD ?
    sin_port WORD ?
    sin_addr DWORD ?
    sin_zero BYTE 8 DUP(? )
sockaddr_in ENDS

WSABUF STRUCT
    len   DWORD ?
    byte_pad DWORD ? ; Padding for x64 alignment
    buf   QWORD ?
WSABUF ENDS

WSAOVERLAPPED STRUCT
    Internal      QWORD ?
    InternalHigh  QWORD ?
    OffsetLow     DWORD ?
    OffsetHigh    DWORD ?
    hEvent        QWORD ?
WSAOVERLAPPED ENDS

; Extended structure to track state per I/O operation
; Alignment Note: WSAOVERLAPPED is 32 bytes.
; We place poolEntry at offset 32, which is 16-byte aligned, required for InterlockedPushEntrySList.
IO_CONTEXT STRUCT
    ov          WSAOVERLAPPED <> ; 0
    poolEntry   SLIST_ENTRY <>   ; 32 (Used for Memory Pool)
    wsaBufs     WSABUF 2 DUP(<>) ; 40 (Array of 2 buffers)
    socket      QWORD ?          ; 40 + 32 = 72
    opType      DWORD ?          ; 80
    buffer      BYTE BUFFER_SIZE DUP(?) ; 84...
IO_CONTEXT ENDS
