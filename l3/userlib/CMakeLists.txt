# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024 Deepspan Project Authors

cmake_minimum_required(VERSION 3.25)
project(deepspan-userlib
    VERSION 0.1.0
    DESCRIPTION "Deepspan HWIP userspace library (io_uring async API)"
    LANGUAGES CXX
)

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
option(DEEPSPAN_USE_SYSTEM_DEPS
    "Use system-installed dependencies (liburing). OFF = use vendored googletest for tests."
    ON
)
option(DEEPSPAN_BUILD_TESTS
    "Build unit and integration tests for deepspan-userlib."
    OFF
)

# ---------------------------------------------------------------------------
# Language standard
# ---------------------------------------------------------------------------
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

# ETL is used only in Zephyr firmware; userlib uses std::expected (C++23).

# liburing — always sourced from the system (not vendored)
find_package(PkgConfig REQUIRED)
pkg_check_modules(liburing REQUIRED IMPORTED_TARGET liburing)

# ---------------------------------------------------------------------------
# Library target
# ---------------------------------------------------------------------------
add_library(deepspan-userlib STATIC
    src/device.cpp
    src/async_client.cpp
    src/error.cpp
)

set(DEEPSPAN_KERNEL_UAPI_DIR "${PROJECT_SOURCE_DIR}/../../l2/kernel/include/uapi"
    CACHE PATH "Kernel UAPI header directory (provides <linux/deepspan.h>)")

target_include_directories(deepspan-userlib
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        # Expose the kernel UAPI headers as <linux/deepspan.h>
        ${DEEPSPAN_KERNEL_UAPI_DIR}
)

target_link_libraries(deepspan-userlib
    PRIVATE
        PkgConfig::liburing
)

target_compile_features(deepspan-userlib PUBLIC cxx_std_23)

target_compile_options(deepspan-userlib PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Wno-unused-parameter
)

# ---------------------------------------------------------------------------
# Install rules
# ---------------------------------------------------------------------------
include(GNUInstallDirs)

install(TARGETS deepspan-userlib
    EXPORT deepspan-userlib-targets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(DIRECTORY include/
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(EXPORT deepspan-userlib-targets
    FILE deepspan-userlib-targets.cmake
    NAMESPACE deepspan::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/deepspan-userlib
)

include(CMakePackageConfigHelpers)
write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/deepspan-userlib-config-version.cmake"
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion
)

install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/deepspan-userlib-config-version.cmake"
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/deepspan-userlib
)

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
if(DEEPSPAN_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
