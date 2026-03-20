cmake_minimum_required(VERSION 3.27)
project(DeepspanHwModel VERSION 0.1.0 LANGUAGES C CXX)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

# ── Library target ───────────────────────────────────────────────────
add_library(deepspan_hw_model)
add_library(Deepspan::hw_model ALIAS deepspan_hw_model)

target_sources(deepspan_hw_model PRIVATE
    src/hw_model_server.cpp
    src/reg_map.cpp
    src/sim_transport.cpp
)

target_include_directories(deepspan_hw_model
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)

target_compile_features(deepspan_hw_model PUBLIC cxx_std_17)

target_compile_options(deepspan_hw_model PRIVATE
    -Wall -Wextra -Wpedantic
    $<$<CONFIG:Debug>:-g3 -O0>
    $<$<CONFIG:Release>:-O2>
)

# ── Executables ────────────────────────────────────────────────────────
add_executable(deepspan-hw-model src/main.cpp)
target_link_libraries(deepspan-hw-model PRIVATE deepspan_hw_model rt)

# firmware_sim: standalone simulated firmware for hw-model interaction testing
add_executable(deepspan-firmware-sim src/firmware_sim.cpp)
target_link_libraries(deepspan-firmware-sim PRIVATE deepspan_hw_model rt)
target_include_directories(deepspan-firmware-sim PRIVATE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

# ── Tests ────────────────────────────────────────────────────────────
if(DEEPSPAN_BUILD_TESTS OR BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()

# ── Install rules ─────────────────────────────────────────────────────
install(TARGETS deepspan_hw_model deepspan-hw-model deepspan-firmware-sim
    EXPORT  DeepspanHwModelTargets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
install(DIRECTORY include/ DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
install(EXPORT DeepspanHwModelTargets
    FILE      DeepspanHwModelTargets.cmake
    NAMESPACE Deepspan::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/DeepspanHwModel
)
configure_package_config_file(cmake/HwModelConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/DeepspanHwModelConfig.cmake
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/DeepspanHwModel
)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/DeepspanHwModelConfig.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/DeepspanHwModel
)
