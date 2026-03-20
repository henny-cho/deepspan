// SPDX-License-Identifier: Apache-2.0
// register.cpp — static Registrar skeleton
// Replace "mychip" with your HWIP name.
#include "plugin.hpp"
#include "deepspan/server/registry.hpp"

namespace {

struct MychipRegistrar {
    MychipRegistrar() {
        deepspan::server::HwipRegistry::instance().register_type(
            "mychip",  // TODO: replace with your HWIP name
            [](std::string_view device_id) {
                return std::make_unique<deepspan::hwip::mychip::MychipPlugin>(
                    device_id);
            });
    }

    ~MychipRegistrar() {
        deepspan::server::HwipRegistry::instance().unregister_type("mychip");
    }
};

static MychipRegistrar reg;  // NOLINT(cert-err58-cpp)

}  // namespace
