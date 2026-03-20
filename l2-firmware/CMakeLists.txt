# Zephyr builds are managed by west, so this file holds West module meta information.
# Actual build: west build -b native_sim/native/64 firmware/app
cmake_minimum_required(VERSION 3.27)

# When used as a West module: Zephyr build system includes this directory
if(DEFINED ZEPHYR_CURRENT_MODULE_DIR)
    add_subdirectory(lib)
    add_subdirectory(drivers)
endif()
