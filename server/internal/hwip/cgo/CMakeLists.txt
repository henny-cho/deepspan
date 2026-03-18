cmake_minimum_required(VERSION 3.25)
project(deepspan-hwip-cgo CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ── appframework dependency ───────────────────────────────────────
# Expect appframework already built at ../../../../appframework/build
# (relative to this CMakeLists.txt: server/internal/hwip/cgo/)
# Path: cgo/ -> hwip/ -> internal/ -> server/ -> deepspan/appframework
set(APPFRAMEWORK_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../appframework")
set(APPFRAMEWORK_BUILD "${APPFRAMEWORK_ROOT}/build")

# ── Kernel UAPI headers ───────────────────────────────────────────
set(KERNEL_UAPI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../kernel/include/uapi")

# ── CGo shim static library ───────────────────────────────────────
add_library(deepspan_hwip_cgo STATIC
    appframework_cgo.cpp
)

target_include_directories(deepspan_hwip_cgo
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}               # appframework_cgo.h
    PRIVATE
        ${APPFRAMEWORK_ROOT}/include              # deepspan/appframework/*.hpp
        ${APPFRAMEWORK_BUILD}/userlib/include     # deepspan/userlib/*.hpp (install tree)
        ${APPFRAMEWORK_ROOT}/../userlib/include   # deepspan/userlib/*.hpp (source tree)
        ${KERNEL_UAPI_DIR}                        # linux/deepspan.h
)

target_compile_options(deepspan_hwip_cgo PRIVATE
    -Wall -Wextra -Wno-unused-parameter
)

# ── Build output info for go build ───────────────────────────────
message(STATUS "deepspan_hwip_cgo: output → ${CMAKE_CURRENT_BINARY_DIR}/libdeepspan_hwip_cgo.a")
message(STATUS "  links against: ${APPFRAMEWORK_BUILD}/libdeepspan-appframework.a")
message(STATUS "  links against: ${APPFRAMEWORK_BUILD}/userlib/libdeepspan-userlib.a")
