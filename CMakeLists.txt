cmake_minimum_required(VERSION 3.27)
project(Deepspan VERSION 0.1.0 LANGUAGES C CXX)

# ── Options ───────────────────────────────────────────────────────────
option(DEEPSPAN_BUILD_HW_MODEL    "Build hw-model simulator"     ON)
option(DEEPSPAN_BUILD_USERLIB     "Build userlib"                ON)
option(DEEPSPAN_BUILD_APPFRAMEWORK "Build appframework"          ON)
option(DEEPSPAN_BUILD_MGMT_DAEMON "Build mgmt-daemon"           ON)
option(DEEPSPAN_BUILD_FIRMWARE    "Build Zephyr firmware (West)" OFF)
option(DEEPSPAN_BUILD_KERNEL      "Build Linux kernel module"    OFF)
option(DEEPSPAN_BUILD_TESTS       "Build tests"                  ON)
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
    add_subdirectory(hw-model)
endif()

if(DEEPSPAN_BUILD_USERLIB)
    add_subdirectory(userlib)
endif()

if(DEEPSPAN_BUILD_APPFRAMEWORK)
    add_subdirectory(appframework)
endif()

if(DEEPSPAN_BUILD_MGMT_DAEMON)
    add_subdirectory(mgmt-daemon)
endif()

if(DEEPSPAN_BUILD_KERNEL)
    include(ExternalProject)
    ExternalProject_Add(deepspan-kernel
        SOURCE_DIR  ${CMAKE_SOURCE_DIR}/kernel
        BINARY_DIR  ${CMAKE_BINARY_DIR}/kernel
        CONFIGURE_COMMAND ""
        BUILD_COMMAND
            $(MAKE) -C /lib/modules/$ENV{KVER}/build
            M=${CMAKE_SOURCE_DIR}/kernel/drivers/deepspan
            modules
            CONFIG_DEEPSPAN_TRANSPORT_SIM=y
        INSTALL_COMMAND ""
        BUILD_ALWAYS TRUE
    )
endif()
