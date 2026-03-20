# SPDX-License-Identifier: Apache-2.0
# hwip/_template/plugin/CMakeLists.txt
#
# Replace "mychip" with your HWIP name.
# This file is included from hwip/<your-name>/CMakeLists.txt when
# DEEPSPAN_BUILD_HWIP=ON and HWIP_TYPE=<your-name>.

add_library(hwip_mychip SHARED
    plugin.cpp
    register.cpp
)

target_compile_features(hwip_mychip PRIVATE cxx_std_20)

target_include_directories(hwip_mychip
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${CMAKE_SOURCE_DIR}/server/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/../gen/rpc"
        "${CMAKE_CURRENT_SOURCE_DIR}/../gen/sim"
)

target_link_libraries(hwip_mychip
    PRIVATE
        deepspan-appframework
        deepspan-userlib
        spdlog::spdlog
)

set_target_properties(hwip_mychip PROPERTIES
    OUTPUT_NAME "hwip_mychip"
    VERSION "${PROJECT_VERSION}"
    SOVERSION "${PROJECT_VERSION_MAJOR}"
)

install(TARGETS hwip_mychip
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
