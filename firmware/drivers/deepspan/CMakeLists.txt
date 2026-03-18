zephyr_library_named(deepspan_hwip_driver)

if(CONFIG_DEEPSPAN_HWIP_DRIVER)
  zephyr_library_sources(deepspan_hwip.c)
endif()

if(CONFIG_DEEPSPAN_HWIP_DRIVER_SIM)
  zephyr_library_sources(deepspan_hwip_sim.c)
  # Export the public header so app and driver code can include it
  zephyr_include_directories(${CMAKE_CURRENT_SOURCE_DIR})
endif()
