# /src/meson.build

# We read the variable defined in our root meson.build
if target_arch == 'x86_64'
  subdir('x86_64')
else
  error('Unsupported target architecture: ' + target_arch)
endif