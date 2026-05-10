# /src/x86_64/tools/fetch_ticker/meson.build

# Assemble the source
fetcher_obj = custom_target(
  'fetch_ticker_obj',
  input: 'fetch_ticker.s',
  output: 'fetch_ticker.o',
  command: [as, as_flags, '@INPUT@', '-o', '@OUTPUT@']
)

# Link the executable
# Note: We manually add -lssl -lcrypto because fetcher needs networking
executable_fetcher = custom_target(
  'fetch_ticker',
  input: fetcher_obj,
  output: 'fetch_ticker',
  command: [
    ld, ld_flags, 
    '@INPUT@', 
    '-o', '@OUTPUT@',
    '-lssl', '-lcrypto', '-lc'
  ],
  build_by_default: true
)