# Included from the West module build system
zephyr_library_named(deepspan_transport)

zephyr_library_sources(
    src/virtio_transport.cpp
)

zephyr_library_include_directories(
    include
)

zephyr_library_compile_options(
    $<$<COMPILE_LANGUAGE:CXX>:-std=c++17>
)
