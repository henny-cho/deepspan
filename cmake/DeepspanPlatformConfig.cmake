# SPDX-License-Identifier: Apache-2.0
# DeepspanPlatformConfig.cmake — find_package(DeepspanPlatform) support.
#
# Usage in external repos (e.g. deepspan-accel):
#
#   find_package(DeepspanPlatform REQUIRED
#       HINTS "$ENV{DEEPSPAN_PLATFORM_DIR}/lib/cmake/DeepspanPlatform")
#
# Imported targets:
#   Deepspan::deepspan-appframework   — C++23 session manager library
#   Deepspan::deepspan-userlib        — C++23 async ioctl/io_uring client

include("${CMAKE_CURRENT_LIST_DIR}/DeepspanPlatformTargets.cmake")
