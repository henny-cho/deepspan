cmake_minimum_required(VERSION 3.27)
project(Deepspan VERSION 0.2.0 LANGUAGES C CXX)

include(GNUInstallDirs)

# ── Options ───────────────────────────────────────────────────────────
option(DEEPSPAN_BUILD_HW_MODEL    "Build hw-model simulator"     ON)
option(DEEPSPAN_BUILD_USERLIB     "Build userlib"                ON)
option(DEEPSPAN_BUILD_APPFRAMEWORK "Build appframework"          ON)
option(DEEPSPAN_BUILD_FIRMWARE    "Build Zephyr firmware (West)" OFF)
option(DEEPSPAN_BUILD_KERNEL      "Build Linux kernel module"    OFF)
option(DEEPSPAN_BUILD_TESTS       "Build tests"                  ON)
option(DEEPSPAN_BUILD_HWIP        "Build HWIP implementations"   OFF)
set(HWIP_TYPE "accel" CACHE STRING "HWIP type to build (accel)")

if(DEEPSPAN_BUILD_TESTS)
    enable_testing()
endif()
option(DEEPSPAN_USE_SYSTEM_DEPS   "Use Conan/system packages (OFF=submodule)" ON)

# ── Dependencies ──────────────────────────────────────────────────────
if(NOT DEEPSPAN_USE_SYSTEM_DEPS)
    # git submodule approach: build sources from third_party/
    if(EXISTS "${CMAKE_SOURCE_DIR}/third_party/googletest/CMakeLists.txt")
        add_subdirectory(third_party/googletest EXCLUDE_FROM_ALL)
    endif()
    if(EXISTS "${CMAKE_SOURCE_DIR}/third_party/spdlog/CMakeLists.txt")
        add_subdirectory(third_party/spdlog EXCLUDE_FROM_ALL)
    endif()
else()
    find_package(GTest QUIET)
    find_package(spdlog QUIET)
endif()

# ETL (Embedded Template Library) — firmware/Zephyr only.
# userlib and appframework use std::expected (C++23) instead.
if(DEEPSPAN_BUILD_FIRMWARE)
    if(EXISTS "${CMAKE_SOURCE_DIR}/third_party/etl/CMakeLists.txt")
        add_subdirectory(third_party/etl EXCLUDE_FROM_ALL)
    endif()
endif()

# ── Layer builds ──────────────────────────────────────────────────────
if(DEEPSPAN_BUILD_HW_MODEL)
    add_subdirectory(l3/hw-model)
endif()

if(DEEPSPAN_BUILD_USERLIB)
    add_subdirectory(l3/userlib)
endif()

if(DEEPSPAN_BUILD_APPFRAMEWORK)
    add_subdirectory(l3/appframework)
endif()

if(DEEPSPAN_BUILD_KERNEL)
    include(ExternalProject)
    ExternalProject_Add(deepspan-kernel
        SOURCE_DIR  ${CMAKE_SOURCE_DIR}/l2/kernel
        BINARY_DIR  ${CMAKE_BINARY_DIR}/l2/kernel
        CONFIGURE_COMMAND ""
        BUILD_COMMAND
            $(MAKE) -C /lib/modules/$ENV{KVER}/build
            M=${CMAKE_SOURCE_DIR}/l2/kernel/drivers/deepspan
            modules
            CONFIG_DEEPSPAN_TRANSPORT_SIM=y
        INSTALL_COMMAND ""
        BUILD_ALWAYS TRUE
    )
endif()

if(DEEPSPAN_BUILD_HWIP)
    include(cmake/hwip-plugin.cmake)
    add_subdirectory(hwip/${HWIP_TYPE})
endif()

# ── Platform install export ───────────────────────────────────────────
# Enables external repos (e.g. deepspan-accel) to consume the platform
# libraries via find_package(DeepspanPlatform REQUIRED).
if(DEEPSPAN_BUILD_APPFRAMEWORK AND DEEPSPAN_BUILD_USERLIB)
    include(CMakePackageConfigHelpers)
    write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/DeepspanPlatformConfigVersion.cmake"
        VERSION ${PROJECT_VERSION}
        COMPATIBILITY SameMajorVersion
    )
    install(EXPORT DeepspanPlatformTargets
        NAMESPACE Deepspan::
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/DeepspanPlatform
    )
    install(FILES
        cmake/DeepspanPlatformConfig.cmake
        "${CMAKE_CURRENT_BINARY_DIR}/DeepspanPlatformConfigVersion.cmake"
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/DeepspanPlatform
    )
endif()
