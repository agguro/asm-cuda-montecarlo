/*
 * ============================================================================
 * MONTE CARLO ENGINE: X86_64 HOST ORCHESTRATOR
 * ============================================================================
 * Role: Handles File I/O, Analytics, and GPU Result Presentation.
 * Architecture: x86_64 Linux (System V ABI)
 * ============================================================================
 */

.section .rodata
    # --- UI Formatting Strings ---
    msg_dash:       .asciz "------------------------------------------------------------\n"
    msg_header:     .asciz "SIMULATION SUMMARY (%s)\n"
    
    # Statistical Outputs
    fmt_stats:      .asciz "Historical Drift    : %.6f\nHistorical Vol      : %.6f\n"
    fmt_forecast:   .ascii "Forecast Horizon    : %ld Days\n"
                    .asciz "Simulated Paths     : %ld\n\n"
    
    # Price and Probability Outputs
    fmt_prices:     .asciz "Current Price       : %.4f\nTarget Price        : %.4f\nExpected Average    : %.4f\n\n"
    fmt_prob:       .ascii "PROBABILITY ANALYSIS:\n"
                    .ascii ">> Probability of hitting target: %.2f%%\n"
                    .asciz ">> Likelihood of missing target : %.2f%%\n"
    
    # Error Handling
    err_args:       .asciz "Usage: ./monte_carlo <data.bin> <target> <iters> <horizon>\n"

    # Constant Doubles for Floating Point Math
    .align 8
    .L_hundred:     .double 100.0
    .L_one:         .double 1.0

.section .data
    # Parameters for GPU kernel (Must match CUDA Driver API layout)
    p_drift:        .double 0.0
    p_vol:          .double 0.0
    p_target:       .double 0.0
    p_start:        .double 0.0
    p_iters:        .quad 0
    p_horizon:      .quad 0
    
    # Internal Tracking Variables
    filename_ptr:   .quad 0
    total_records:  .quad 0
    host_input_ptr: .quad 0
    target_val:     .double 0.0
    
    # Results populated by GPU Reduction
    total_sum_acc:  .double 0.0
    total_hits_acc: .quad 0
    
    # Buffer for sys_fstat (Struct Stat)
    file_stat:      .skip 144

.section .text
.global _start

_start:
    # --- 1. SETUP & STACK FRAME ---
    # Standard prologue to establish a base pointer
    pushq   %rbp
    movq    %rsp, %rbp
    
    # ABI Requirement: The stack must be 16-byte aligned before calling C functions.
    # (printf, strtod, atoll). andq removes the lower bits to force alignment.
    andq    $-16, %rsp

    # --- 2. ARGUMENT PARSING (CLI) ---
    # [Stack Layout at _start]
    # 8(%rbp)  -> argc
    # 16(%rbp) -> argv[0] (binary name)
    # 24(%rbp) -> argv[1] (ticker file)
    # 32(%rbp) -> argv[2] (target price)
    
    movq    8(%rbp), %rax           # Load argc
    cmpq    $5, %rax                # Check for exactly 5 arguments
    jl      .L_fail_args            # Exit if arguments are missing

    # Extract Filename
    movq    24(%rbp), %rax
    movq    %rax, filename_ptr(%rip)

    # Convert Target Price (String -> Double)
    # strtod(rdi: string, rsi: endptr)
    movq    32(%rbp), %rdi
    xorl    %esi, %esi
    call    strtod@PLT
    movsd   %xmm0, target_val(%rip)

    # Convert Iterations (String -> Long)
    # atoll(rdi: string)
    movq    40(%rbp), %rdi
    call    atoll@PLT
    movq    %rax, p_iters(%rip)

    # Convert Horizon (String -> Long)
    movq    48(%rbp), %rdi
    call    atoll@PLT
    movq    %rax, p_horizon(%rip)

    # --- 3. DATA LOADING (Syscalls) ---
    
    # sys_open(rdi: filename, rsi: flags)
    movq    $2, %rax
    movq    filename_ptr(%rip), %rdi
    xorq    %rsi, %rsi              # O_RDONLY
    syscall
    movq    %rax, %r12              # Save File Descriptor to R12

    # sys_fstat(rdi: fd, rsi: stat_buf)
    # Used to determine the size of the ticker file for mmap
    movq    $5, %rax
    movq    %r12, %rdi
    leaq    file_stat(%rip), %rsi
    syscall
    
    # Offset 48 in 'struct stat' is st_size (Total Bytes)
    movq    48+file_stat(%rip), %r13 

    # Calculate count of 16-byte records (size >> 4)
    movq    %r13, %rax
    shrq    $4, %rax
    movq    %rax, total_records(%rip)

    # sys_mmap(rdi: addr, rsi: len, rdx: prot, r10: flags, r8: fd, r9: off)
    # Projects the file directly into process memory (Zero-Copy)
    movq    $9, %rax
    xorq    %rdi, %rdi
    movq    %r13, %rsi              # Length
    movl    $1, %edx                # PROT_READ
    movl    $2, %r10d               # MAP_PRIVATE
    movq    %r12, %r8               # File Descriptor
    xorq    %r9, %r9                # Offset 0
    syscall
    movq    %rax, host_input_ptr(%rip)

    # --- 4. ANALYTICS ENGINE (CPU) ---
    # Iterates through historical data to find Mu (Drift) and Sigma (Vol)
    movq    total_records(%rip), %rdx
    decq    %rdx                    # Intervals = n - 1
    movq    host_input_ptr(%rip), %rbx
    
    xorq    %rdi, %rdi              # Loop Index
    xorpd   %xmm0, %xmm0            # Sum(Returns)
    xorpd   %xmm1, %xmm1            # Sum(Returns^2)

.L_loop:
    cmpq    %rdx, %rdi
    jge     .L_stats
    
    # Each record is 16 bytes: [Timestamp(8) | Price(8)]
    movq    %rdi, %rax
    shlq    $4, %rax                # current index * 16
    movsd   8(%rbx, %rax), %xmm2    # Load Price[i]
    
    addq    $16, %rax               # move to next record
    movsd   8(%rbx, %rax), %xmm3    # Load Price[i+1]
    
    # Calculate Log Return Approximation: (Price[i+1] / Price[i]) - 1
    divsd   %xmm2, %xmm3
    subsd   .L_one(%rip), %xmm3
    
    # Accumulate for Mean and Variance
    addsd   %xmm3, %xmm0            # Drift accumulator
    movsd   %xmm3, %xmm4
    mulsd   %xmm4, %xmm4
    addsd   %xmm4, %xmm1            # Volatility (Variance) accumulator
    
    incq    %rdi
    jmp     .L_loop

.L_stats:
    # Finalize Statistical Calculations
    cvtsi2sd %rdx, %xmm4            # Convert count to double
    
    # Mean Drift (μ)
    divsd   %xmm4, %xmm0
    movsd   %xmm0, p_drift(%rip)
    
    # Standard Deviation / Vol (σ)
    divsd   %xmm4, %xmm1
    mulsd   %xmm0, %xmm0            # μ^2
    subsd   %xmm0, %xmm1            # Variance = E[X^2] - (E[X])^2
    sqrtsd  %xmm1, %xmm1
    movsd   %xmm1, p_vol(%rip)

    # --- 5. GPU PREPARATION ---
    # Establish the starting price (Latest record in the file)
    movq    total_records(%rip), %rax
    decq    %rax
    shlq    $4, %rax
    addq    host_input_ptr(%rip), %rax
    movsd   8(%rax), %xmm0
    movsd   %xmm0, p_start(%rip)

    # [!] NOTE: CUDA Driver API calls (cuLaunchKernel) happen here.
    # We assume the GPU has filled total_sum_acc and total_hits_acc.

    # --- 6. PRESENTATION LAYER (UI) ---
    
    # Print Decorative Dash
    leaq    msg_dash(%rip), %rdi
    xorl    %eax, %eax
    call    printf@PLT

    # Print Header with Filename
    leaq    msg_header(%rip), %rdi
    movq    filename_ptr(%rip), %rsi
    xorl    %eax, %eax
    call    printf@PLT

    # Print Calculated Analytics
    leaq    fmt_stats(%rip), %rdi
    movsd   p_drift(%rip), %xmm0
    movsd   p_vol(%rip), %xmm1
    movb    $2, %al                 # %al = 2 (Two float args in xmm0, xmm1)
    call    printf@PLT

    # Print Forecast Metadata
    leaq    fmt_forecast(%rip), %rdi
    movq    p_horizon(%rip), %rsi
    movq    p_iters(%rip), %rdx
    xorl    %eax, %eax
    call    printf@PLT

    # Calculate and Print Expected Average Price
    # Formula: StartPrice + (StartPrice * Drift * Horizon)
    leaq    fmt_prices(%rip), %rdi
    movsd   p_start(%rip), %xmm0
    movsd   target_val(%rip), %xmm1
    movsd   p_drift(%rip), %xmm2
    cvtsi2sd p_horizon(%rip), %xmm3
    mulsd   %xmm3, %xmm2            # Drift * Horizon
    mulsd   %xmm0, %xmm2            # (Drift * Horizon) * Start
    addsd   %xmm0, %xmm2            # ... + Start
    movb    $3, %al
    call    printf@PLT

    # Final Probability Analysis
    # hit_rate = total_hits / total_iterations
    cvtsi2sd total_hits_acc(%rip), %xmm0
    cvtsi2sd p_iters(%rip), %xmm9
    divsd   %xmm9, %xmm0            # hit ratio
    mulsd   .L_hundred(%rip), %xmm0 # % hit rate
    
    movsd   .L_hundred(%rip), %xmm1
    subsd   %xmm0, %xmm1            # % miss rate
    
    leaq    fmt_prob(%rip), %rdi
    movb    $2, %al
    call    printf@PLT

    # --- 7. EXIT ---
    # sys_exit(rdi: error_code)
    movq    $60, %rax
    xorq    %rdi, %rdi
    syscall

.L_fail_args:
    # Error state: Not enough arguments provided
    leaq    err_args(%rip), %rdi
    xorl    %eax, %eax
    call    printf@PLT
    movq    $60, %rax
    movq    $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
