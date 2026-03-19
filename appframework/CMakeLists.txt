cmake_minimum_required(VERSION 3.25)
project(deepspan-appframework VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(DEEPSPAN_USE_SYSTEM_DEPS "Use system-installed dependencies" ON)
option(DEEPSPAN_BUILD_TESTS "Build tests" OFF)

# userlib dependency
if(NOT TARGET deepspan-userlib)
    add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../userlib ${CMAKE_CURRENT_BINARY_DIR}/userlib)
endif()

add_library(deepspan-appframework STATIC
    src/device_pool.cpp
    src/circuit_breaker.cpp
    src/session_manager.cpp
)

target_include_directories(deepspan-appframework
    PUBLIC  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
            $<INSTALL_INTERFACE:include>
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(deepspan-appframework
    PUBLIC deepspan-userlib
)

target_compile_features(deepspan-appframework PUBLIC cxx_std_23)

target_compile_options(deepspan-appframework PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Wno-unused-parameter
)

if(DEEPSPAN_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

include(GNUInstallDirs)

# ── Platform install export ───────────────────────────────────────────
# Both deepspan-appframework and deepspan-userlib are exported together
# under the DeepspanPlatformTargets export set so that external repos
# (e.g. deepspan-accel) can consume them via find_package(DeepspanPlatform).
install(TARGETS deepspan-appframework deepspan-userlib
    EXPORT DeepspanPlatformTargets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)
install(DIRECTORY include/ DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
