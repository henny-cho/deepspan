# SPDX-License-Identifier: Apache-2.0
# DeepspanPlatformConfig.cmake — find_package(DeepspanPlatform) support.
#
# Usage in HWIP repos (e.g. deepspan-hwip):
#
#   find_package(DeepspanPlatform REQUIRED
#       HINTS "$ENV{DEEPSPAN_PLATFORM_DIR}/lib/cmake/DeepspanPlatform")
#
# Imported targets:
#   Deepspan::deepspan-appframework   — C++20 session manager library
#   Deepspan::deepspan-userlib        — C++20 async ioctl/io_uring client

include("${CMAKE_CURRENT_LIST_DIR}/DeepspanPlatformTargets.cmake")
