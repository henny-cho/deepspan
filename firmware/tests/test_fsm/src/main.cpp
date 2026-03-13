/**
 * @file main.cpp
 * @brief ETL FSM unit tests (runs on native_sim)
 *
 * west twister -T firmware/tests/ -p native_sim/native/64
 */

#include <zephyr/ztest.h>
#include <etl/fsm.h>
#include <etl/message.h>

/* Simple 2-state FSM test definitions */
enum StateId { STATE_IDLE = 0, STATE_RUNNING, STATE_COUNT };
enum EventId { EVT_START = 0, EVT_STOP };

struct StartEvent : etl::message<EVT_START> {};
struct StopEvent  : etl::message<EVT_STOP>  {};

ZTEST_SUITE(etl_fsm, NULL, NULL, NULL, NULL, NULL);

ZTEST(etl_fsm, test_message_id)
{
    StartEvent se;
    StopEvent  st;
    zassert_equal(se.get_message_id(), EVT_START, "StartEvent id mismatch");
    zassert_equal(st.get_message_id(), EVT_STOP,  "StopEvent id mismatch");
}

ZTEST(etl_fsm, test_state_count)
{
    zassert_equal(STATE_COUNT, 2, "State count mismatch");
}
