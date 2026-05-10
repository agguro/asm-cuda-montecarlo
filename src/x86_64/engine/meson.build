# src/x86_64/engine/meson.build

# 1. Dynamically locate the kernel relative to the project root
# This works regardless of which subdir() you are in
kernel_ptx = meson.project_source_root() / 'kernels' / 'monte_carlo_kernel.ptx'

# 2. Compile PTX to CUBIN
gen_cubin = custom_target(
    'mc_kernel_cubin',
    input: kernel_ptx,
    output: 'monte_carlo.cubin',
    command: [ptxas, '-v', '-arch=sm_61', '@INPUT@', '-o', '@OUTPUT@']
)

# 3. Assemble the host orchestrator
# Use the current build directory as an include path so .incbin finds the .cubin
engine_obj = custom_target(
    'monte_carlo_obj',
    input: 'monte_carlo.s',
    output: 'monte_carlo.o',
    command: [
        as, as_flags, 
        '-I', meson.current_build_dir(), 
        '@INPUT@', 
        '-o', '@OUTPUT@'
    ],
    depends: [gen_cubin]
)

# 4. Link the final engine
# Note: inst_path is inherited from the root meson.build
executable_engine = custom_target(
    'monte_carlo',
    input: engine_obj,
    output: 'monte_carlo',
    command: [
        ld, ld_flags, 
        '@INPUT@', 
        '-o', '@OUTPUT@',
        '-lcuda', '-lc'
    ],
    build_by_default: true,
    install: true,
    install_dir: inst_path
)