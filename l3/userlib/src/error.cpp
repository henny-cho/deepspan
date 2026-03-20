// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// error.cpp — Implementation of to_string(Error).

#include "deepspan/userlib/error.hpp"

namespace deepspan::userlib {

std::string_view to_string(Error e) noexcept {
    switch (e) {
        case Error::UnsupportedKernelVersion:
            return "UnsupportedKernelVersion";
        case Error::DeviceOpenFailed:
            return "DeviceOpenFailed";
        case Error::IouringSetupFailed:
            return "IouringSetupFailed";
        case Error::SubmitFailed:
            return "SubmitFailed";
        case Error::Timeout:
            return "Timeout";
        case Error::IoError:
            return "IoError";
    }
    return "Unknown";
}

} // namespace deepspan::userlib
