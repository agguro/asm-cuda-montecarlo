/*
 * ============================================================================
 * Architecture : x86_64 | Linux SysV ABI | AT&T Syntax
 * Description  : Professional SSL Ticker Fetcher (Corrected)
 * ============================================================================
 */

.section .rodata
    # Change to query2
    host:       .asciz "query2.finance.yahoo.com:443"
    
    # New V8 Chart Template
    # We use query2.finance.yahoo.com/v8/finance/chart/TICKER?range=60d&interval=1d
    req_fmt:    .asciz "GET /v8/finance/chart/%s?range=%s&interval=%s HTTP/1.1\r\nHost: query2.finance.yahoo.com\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n"
    
    # File Extension
    ext_json:    .asciz ".json"
    
    # Error Messages
    err_args:   .asciz "Usage: ./fetch_ticker <TICKER> <RANGE(e.g. 60d)> <INTERVAL(e.g. 1d)>\n"
    msg_conn:   .asciz "Connecting to Yahoo Finance...\n"
    msg_done:   .asciz "Data successfully written to %s\n"

    # OpenSSL BIO Control Constants
    BIO_C_SET_CONNECT = 100
    BIO_C_DO_STATE_MACHINE = 101

.section .data
    .align 8
    ctx:        .quad 0
    bio:        .quad 0
    file_fd:    .quad 0

.section .bss
    .align 16
    filename:   .skip 64
    request:    .skip 2048  # Increased for safety
    buf:        .skip 4096

.section .text
.globl _start

_start:
    # 1. Save original stack pointer
    movq    %rsp, %rbp
    
    # 2. Align stack to 16 bytes for ABI compliance
    andq    $-16, %rsp
    
    # 3. Access argc/argv via the saved RBP
    movq    (%rbp), %rdi       # argc
    cmpq    $4, %rdi
    jne     .L_arg_error
    
    movq    16(%rbp), %r12     # argv[1] (Ticker)
    movq    24(%rbp), %r13     # argv[2] (Range)
    movq    32(%rbp), %r14     # argv[3] (Interval)

    # --- Build Filename ---
    leaq    filename(%rip), %rdi
    movq    %r12, %rsi
    call    strcpy@PLT

    leaq    filename(%rip), %rdi
    leaq    ext_json(%rip), %rsi
    call    strcat@PLT

    # --- Build HTTP Request ---
    leaq    request(%rip), %rdi
    leaq    req_fmt(%rip), %rsi
    movq    %r12, %rdx
    movq    %r13, %rcx
    movq    %r14, %r8
    xorq    %rax, %rax         # Important: sprintf is variadic
    call    sprintf@PLT

    # --- Open Local Output File ---
    movq    $2, %rax           # SYS_open
    leaq    filename(%rip), %rdi
    movq    $0x241, %rsi       # O_WRONLY | O_CREAT | O_TRUNC
    movq    $0644, %rdx
    syscall
    testq   %rax, %rax
    js      .L_exit_err
    movq    %rax, file_fd(%rip)

    # --- OpenSSL Initialization ---
    xorq    %rdi, %rdi
    xorq    %rsi, %rsi
    call    OPENSSL_init_ssl@PLT

    call    TLS_client_method@PLT
    movq    %rax, %rdi
    call    SSL_CTX_new@PLT
    movq    %rax, ctx(%rip)

    movq    ctx(%rip), %rdi
    call    BIO_new_ssl_connect@PLT
    movq    %rax, bio(%rip)

    # BIO_set_conn_hostname
    movq    bio(%rip), %rdi
    movq    $BIO_C_SET_CONNECT, %rsi
    xorq    %rdx, %rdx
    leaq    host(%rip), %rcx
    call    BIO_ctrl@PLT

    # BIO_do_connect
    movq    bio(%rip), %rdi
    movq    $BIO_C_DO_STATE_MACHINE, %rsi
    xorq    %rdx, %rdx
    xorq    %rcx, %rcx
    call    BIO_ctrl@PLT
    testq   %rax, %rax
    jle     .L_exit_err

    # --- Send Request ---
    leaq    request(%rip), %rdi
    call    strlen@PLT
    movq    %rax, %rdx         # length from strlen
    movq    bio(%rip), %rdi
    leaq    request(%rip), %rsi
    call    BIO_write@PLT

    # --- Read Loop ---
# Initialize our Gatekeeper flag to 0 (Headers mode)
    xorq    %r15, %r15

# Initialize Gatekeeper: %r12 = 0 (Headers), %r12 = 1 (Body)
    xorq    %r12, %r12

.L_read_loop:
    movq    bio(%rip), %rdi
    leaq    buf(%rip), %rsi
    movq    $4096, %rdx
    call    BIO_read@PLT
    
    testq   %rax, %rax
    jle     .L_finish_up        # Exit on EOF or error

    # If we already found the body, go straight to writing
    cmpq    $1, %r12
    je      .L_do_write_full

    # --- Header Search Mode ---
    movq    %rax, %rcx          # rcx = bytes read
    leaq    buf(%rip), %rdx     # rdx = current pointer
    
.L_scan_headers:
    cmpq    $4, %rcx            # Need 4 bytes to match \r\n\r\n
    jl      .L_read_loop        # Not enough in this chunk, read more
    
    # Check for \r\n\r\n
    # Note: \n is 0x0A, \r is 0x0D
    cmpl    $0x0A0D0A0D, (%rdx)
    je      .L_found_headers
    
    incq    %rdx
    decq    %rcx
    jmp     .L_scan_headers

.L_found_headers:
    addq    $4, %rdx            # Skip the \r\n\r\n
    subq    $4, %rcx            # Subtract 4 from remaining count
    movq    $1, %r12            # Set Gatekeeper = 1 (Body found)
    
    # If JSON follows immediately in this same buffer:
    testq   %rcx, %rcx
    jz      .L_read_loop        # No JSON yet, get next chunk
    
    # We have some JSON data left in RDX, length in RCX
    movq    %rcx, %rdx          # length
    movq    %rdx, %r13          # Save length for syscall
    movq    %rdx, %rsi          # Use pointer we found in RDX
    jmp     .L_syscall_write

.L_do_write_full:
    movq    %rax, %rdx          # Write the whole buffer
    leaq    buf(%rip), %rsi

.L_syscall_write:
    movq    $1, %rax            # SYS_write
    movq    file_fd(%rip), %rdi
    syscall
    jmp     .L_read_loop

.L_finish_up:
    # --- 1. Close the file first to flush buffers ---
    movq    file_fd(%rip), %rdi
    movq    $3, %rax                # SYS_close
    syscall

    # --- 2. Re-open for writing/truncating ---
    movq    $2, %rax                # SYS_open
    leaq    filename(%rip), %rdi
    movq    $2, %rsi                # O_RDWR
    syscall
    movq    %rax, %rdi              # File descriptor in RDI

    # --- 3. Seek to the very end ---
    movq    $0, %rsi                # offset 0
    movq    $2, %rdx                # SEEK_END
    movq    $8, %rax                # SYS_lseek
    syscall
    # RAX now contains the total file size

    # --- 4. Backtrack to find the end of the data ---
    # We want to remove: ,"error":null}}
    # That is exactly 16 bytes.
    subq    $16, %rax               
    
    # --- 5. Truncate the file at the new shorter length ---
    movq    %rax, %rsi              # The new length
    movq    $77, %rax               # SYS_ftruncate
    syscall

    # --- 6. Final Close ---
    movq    $3, %rax                # SYS_close
    syscall
    
    # --- FIXED PRINTF CALL ---
    leaq    msg_done(%rip), %rdi  # Arg 1: Format string
    leaq    filename(%rip), %rsi  # Arg 2: Filename variable
    xorq    %rax, %rax            # 0 vector registers
    call    printf@PLT

    # --- Cleanup ---
    movq    bio(%rip), %rdi
    call    BIO_free_all@PLT
    movq    ctx(%rip), %rdi
    call    SSL_CTX_free@PLT
    
    movq    file_fd(%rip), %rdi
    movq    $3, %rax           # SYS_close
    syscall

    movq    $60, %rax          # SYS_exit
    xorq    %rdi, %rdi
    syscall

.L_arg_error:
    # write to stderr using syscall
    movq    $1, %rax           # SYS_write
    movq    $2, %rdi           # stderr
    leaq    err_args(%rip), %rsi
    movq    $61, %rdx
    syscall
    movq    $60, %rax
    movq    $1, %rdi
    syscall

.L_exit_err:
    movq    $60, %rax
    movq    $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
