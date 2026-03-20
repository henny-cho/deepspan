// SPDX-License-Identifier: GPL-2.0
/*
 * deepspan_test.c - KUnit unit tests
 *
 * Run: make -C /lib/modules/$(uname -r)/build M=$PWD \
 *           CONFIG_DEEPSPAN_KUNIT_TEST=y
 *       ./tools/testing/kunit/kunit.py run
 */

#include <kunit/test.h>
#include <linux/xarray.h>
#include <linux/ida.h>

/* ── XArray tests ───────────────────────────────────────────────── */

static void test_xarray_alloc_free(struct kunit *test)
{
    DEFINE_XARRAY(xa);
    u32 id1, id2;
    int ret;

    ret = xa_alloc(&xa, &id1, (void *)0xDEAD,
                   XA_LIMIT(1, 4096), GFP_KERNEL);
    KUNIT_EXPECT_EQ(test, ret, 0);
    KUNIT_EXPECT_GE(test, id1, 1u);

    ret = xa_alloc(&xa, &id2, (void *)0xBEEF,
                   XA_LIMIT(1, 4096), GFP_KERNEL);
    KUNIT_EXPECT_EQ(test, ret, 0);
    KUNIT_EXPECT_NE(test, id1, id2);

    KUNIT_EXPECT_PTR_EQ(test, xa_erase(&xa, id1), (void *)0xDEAD);
    KUNIT_EXPECT_PTR_EQ(test, xa_erase(&xa, id2), (void *)0xBEEF);

    xa_destroy(&xa);
}

static void test_xarray_limit(struct kunit *test)
{
    DEFINE_XARRAY(xa);
    u32 id;
    int ret;

    /* IDs outside the range must not be allocated */
    ret = xa_alloc(&xa, &id, (void *)1,
                   XA_LIMIT(10, 10), GFP_KERNEL);
    KUNIT_EXPECT_EQ(test, ret, 0);
    KUNIT_EXPECT_EQ(test, id, 10u);

    /* -EBUSY when already full */
    ret = xa_alloc(&xa, &id, (void *)2,
                   XA_LIMIT(10, 10), GFP_KERNEL);
    KUNIT_EXPECT_EQ(test, ret, -EBUSY);

    xa_destroy(&xa);
}

/* ── IDA tests ──────────────────────────────────────────────────── */

static void test_ida_minor_alloc(struct kunit *test)
{
    DEFINE_IDA(ida);
    int m0, m1;

    m0 = ida_alloc_range(&ida, 0, 15, GFP_KERNEL);
    KUNIT_EXPECT_GE(test, m0, 0);

    m1 = ida_alloc_range(&ida, 0, 15, GFP_KERNEL);
    KUNIT_EXPECT_GE(test, m1, 0);
    KUNIT_EXPECT_NE(test, m0, m1);

    ida_free(&ida, m0);
    ida_free(&ida, m1);
    ida_destroy(&ida);
}

/* ── Test suite registration ─────────────────────────────────────── */

static struct kunit_case deepspan_test_cases[] = {
    KUNIT_CASE(test_xarray_alloc_free),
    KUNIT_CASE(test_xarray_limit),
    KUNIT_CASE(test_ida_minor_alloc),
    {},
};

static struct kunit_suite deepspan_test_suite = {
    .name  = "deepspan",
    .test_cases = deepspan_test_cases,
};

kunit_test_suite(deepspan_test_suite);

MODULE_LICENSE("GPL");
