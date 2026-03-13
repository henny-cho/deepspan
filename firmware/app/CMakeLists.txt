# Zephyr app build configuration
# Build: west build -b native_sim/native/64 firmware/app
cmake_minimum_required(VERSION 3.27)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(DeepspanFirmware VERSION 0.1.0 LANGUAGES C CXX)

target_sources(app PRIVATE
    src/main.cpp
)

target_include_directories(app PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../lib/transport/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../lib/components
)
