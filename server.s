.section __TEXT,__text,regular,pure_instructions
.align 2
.globl _main

_main:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    // socket(AF_INET, SOCK_STREAM, 0)
    mov x0, #2
    mov x1, #1
    mov x2, #0
    bl _socket
    cmp x0, #0
    blt fatal
    mov x19, x0                  // listener fd

    // bind(listener, &addr, 16)
    mov x0, x19
    adrp x1, sockaddr@PAGE
    add x1, x1, sockaddr@PAGEOFF
    mov x2, #16
    bl _bind
    cmp x0, #0
    blt fatal_close_listener

    // listen(listener, 64)
    mov x0, x19
    mov x1, #64
    bl _listen
    cmp x0, #0
    blt fatal_close_listener

accept_loop:
    // accept(listener, NULL, NULL)
    mov x0, x19
    mov x1, #0
    mov x2, #0
    bl _accept
    cmp x0, #0
    blt accept_loop
    mov x20, x0                  // client fd

    // read(client, request_buf, 1024)
    mov x0, x20
    adrp x1, request_buf@PAGE
    add x1, x1, request_buf@PAGEOFF
    mov x2, #1024
    bl _read
    cmp x0, #0
    ble close_client
    mov x23, x0                  // bytes read

    // default response: 404
    adrp x21, response_404@PAGE
    add x21, x21, response_404@PAGEOFF

    adrp x9, request_buf@PAGE
    add x9, x9, request_buf@PAGEOFF

    // Check minimal "GET / "
    cmp x23, #6
    blt send_response

    ldrb w10, [x9, #0]
    cmp w10, #'G'
    b.ne send_response
    ldrb w10, [x9, #1]
    cmp w10, #'E'
    b.ne send_response
    ldrb w10, [x9, #2]
    cmp w10, #'T'
    b.ne send_response
    ldrb w10, [x9, #3]
    cmp w10, #' '
    b.ne send_response
    ldrb w10, [x9, #4]
    cmp w10, #'/'
    b.ne send_response

    // Route: GET / HTTP/1.1
    ldrb w10, [x9, #5]
    cmp w10, #' '
    b.ne check_health
    adrp x21, response_root@PAGE
    add x21, x21, response_root@PAGEOFF
    b send_response

check_health:
    // Route: GET /health HTTP/1.1
    cmp x23, #12
    blt send_response

    ldrb w10, [x9, #5]
    cmp w10, #'h'
    b.ne send_response
    ldrb w10, [x9, #6]
    cmp w10, #'e'
    b.ne send_response
    ldrb w10, [x9, #7]
    cmp w10, #'a'
    b.ne send_response
    ldrb w10, [x9, #8]
    cmp w10, #'l'
    b.ne send_response
    ldrb w10, [x9, #9]
    cmp w10, #'t'
    b.ne send_response
    ldrb w10, [x9, #10]
    cmp w10, #'h'
    b.ne send_response
    ldrb w10, [x9, #11]
    cmp w10, #' '
    b.ne send_response

    adrp x21, response_health@PAGE
    add x21, x21, response_health@PAGEOFF

send_response:
    // len = strlen(response)
    mov x0, x21
    bl _strlen
    mov x22, x0

    // write(client, response, len)
    mov x0, x20
    mov x1, x21
    mov x2, x22
    bl _write

close_client:
    mov x0, x20
    bl _close
    b accept_loop

fatal_close_listener:
    mov x0, x19
    bl _close

fatal:
    mov x0, #1
    bl _exit

.section __TEXT,__cstring,cstring_literals
response_root:
    .asciz "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 34\r\nConnection: close\r\n\r\n{\"message\":\"hello from arm64 asm\"}"
response_health:
    .asciz "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 15\r\nConnection: close\r\n\r\n{\"status\":\"ok\"}"
response_404:
    .asciz "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: 21\r\nConnection: close\r\n\r\n{\"error\":\"not found\"}"

.section __DATA,__data
sockaddr:
    .byte 16                     // sin_len
    .byte 2                      // AF_INET
    .hword 0xA046                // port 18080 in network order
    .word 0                      // INADDR_ANY
    .quad 0                      // sin_zero[8]

.section __DATA,__bss
.align 4
request_buf:
    .space 1024
