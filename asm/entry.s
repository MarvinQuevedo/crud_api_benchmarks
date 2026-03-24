// macOS ARM64 entry point: reads PORT and DB_PATH via libc, then calls C++ server (asm_bridge.cpp).
// Linked with the same objects/libraries as api_crud_server (httplib, SQLite, etc.).

.section __TEXT,__text,regular,pure_instructions
.align 2
.globl _main

_main:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp

    // x19 = port (default 18080)
    adrp    x0, port_env@PAGE
    add     x0, x0, port_env@PAGEOFF
    bl      _getenv
    cbz     x0, L_default_port
    bl      _atoi
    mov     w19, w0
    cbz     w19, L_default_port
    b       L_got_port
L_default_port:
    movz    w19, #0x46A0            // 18080
L_got_port:

    // x20 = db_path char* or NULL
    adrp    x0, dbpath_env@PAGE
    add     x0, x0, dbpath_env@PAGEOFF
    bl      _getenv
    mov     x20, x0

    // asm_crud_run(bind, port, db_path)
    adrp    x0, bind_default@PAGE
    add     x0, x0, bind_default@PAGEOFF
    mov     w1, w19
    mov     x2, x20
    bl      _asm_crud_run

    // return status as process exit code (already in w0 from asm_crud_run)

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.section __TEXT,__cstring,cstring_literals
port_env:
    .asciz "PORT"
dbpath_env:
    .asciz "DB_PATH"
bind_default:
    .asciz "0.0.0.0"
