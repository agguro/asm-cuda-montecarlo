# src/libs/meson.build

# Assemble your library sources into object files
lib_objs = []

helper_sources = [
  
]

foreach s : helper_sources
  base = s.split('.')[0]
  lib_objs += custom_target(
    base + '_obj',
    input: s,
    output: [base + '.o', base + '.lst'],
    command: [as, as_flags, '-al=@OUTPUT1@', '@INPUT@', '-o', '@OUTPUT0@']
  )
endforeach

# Extract just the .o files to be linked later
asm_lib_inputs = []
foreach o : lib_objs
  asm_lib_inputs += o[0]
endforeach