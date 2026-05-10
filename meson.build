# /meson.build
project('asm-cuda-montecarlo', ['c'], version: '0.1.0')

# --- 1. Define variables early for scoping ---
inst_path = 'monte_carlo'
target_arch = 'x86_64'

# --- 2. Toolchain ---
as = find_program('as', required: true)
ld = find_program('ld', required: true)
ptxas = find_program('ptxas', required: true)

# --- 3. Dependency Check ---
# This uses pkg-config behind the scenes. 
# If 'libssl-dev' (Ubuntu) or 'openssl-devel' (Fedora) is missing, this stops the build.
openssl_dep = dependency('openssl', required: true)

# --- 4. Extra verification for humans ---
if openssl_dep.found()
    message('OpenSSL found: ' + openssl_dep.version())
    # Extract the actual library directory to help our manual 'ld' call
    ssl_libdir = openssl_dep.get_variable(pkgconfig: 'libdir')
else
    error('SSL/Crypto libraries not found. Please install libssl-dev or openssl-devel.')
endif

# --- 5. Global Flags ---
as_flags = ['--64', '--noexecstack']

# Add the discovered SSL path to the linker flags so 'ld' knows where to look
ld_flags = [
    '-m', 'elf_x86_64', 
    '-pie', 
    '-z', 'noexecstack',
    '-L' + ssl_libdir,   # Dynamic path to libssl.so / libcrypto.so
    '--dynamic-linker', '/lib64/ld-linux-x86-64.so.2'
]

subdir('src')