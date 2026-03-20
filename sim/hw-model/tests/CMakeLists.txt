find_package(GTest QUIET)
if(NOT GTest_FOUND AND TARGET GTest::gtest)
    # Already added when building as a submodule
endif()

add_executable(hw_model_tests
    unit/test_reg_map.cpp
    unit/test_sim_transport.cpp
)

target_link_libraries(hw_model_tests PRIVATE
    deepspan_hw_model
    GTest::gtest_main
)

include(GoogleTest)
gtest_discover_tests(hw_model_tests)
