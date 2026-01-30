; x64 Architecture Macros

; Macro to handle the 32-byte Shadow Space (Home Space)
; Usage: ENTER_API_CALL
ENTER_API_CALL MACRO
    sub rsp, 32
ENDM

; Macro to clean up Shadow Space
LEAVE_API_CALL MACRO
    add rsp, 32
ENDM

; Note: Ensure stack is 16-byte aligned before calling ENTER_API_CALL
; if the previous operations pushed an odd number of QWORDs.