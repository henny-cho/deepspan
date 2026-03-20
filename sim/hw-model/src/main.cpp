#include "deepspan/hw_model/hw_model_server.hpp"
#include <iostream>
#include <csignal>
#include <cstring>
#include <string>
#include <stdexcept>

static deepspan::hw_model::HwModelServer* g_server = nullptr;

static void signal_handler(int sig) {
    (void)sig;
    if (g_server) g_server->stop();
}

static void usage(const char* prog) {
    std::cerr << "Usage: " << prog << " [OPTIONS]\n"
              << "  --shm-name=NAME   Shared memory name (default: /deepspan_hwip_0)\n"
              << "  --latency-us=N    Artificial response latency (default: 0)\n"
              << "  --no-auto-irq     Disable automatic IRQ\n"
              << "  -h, --help        Help\n";
}

int main(int argc, char* argv[]) {
    deepspan::hw_model::HwModelConfig cfg;

    for (int i = 1; i < argc; ++i) {
        std::string arg(argv[i]);
        if (arg.rfind("--shm-name=", 0) == 0) {
            cfg.shm_name = arg.substr(11);
        } else if (arg.rfind("--latency-us=", 0) == 0) {
            cfg.latency_us = static_cast<uint32_t>(std::stoul(arg.substr(13)));
        } else if (arg == "--no-auto-irq") {
            cfg.auto_irq = false;
        } else if (arg == "-h" || arg == "--help") {
            usage(argv[0]);
            return 0;
        } else {
            std::cerr << "Unknown option: " << arg << "\n";
            usage(argv[0]);
            return 1;
        }
    }

    deepspan::hw_model::HwModelServer server(cfg);
    g_server = &server;

    std::signal(SIGINT,  signal_handler);
    std::signal(SIGTERM, signal_handler);

    if (!server.init()) {
        std::cerr << "Failed to initialize hw-model server\n";
        return 1;
    }

    std::cout << "[deepspan-hw-model] shm: " << cfg.shm_name
              << ", latency: " << cfg.latency_us << "us\n";
    std::cout << "[deepspan-hw-model] waiting for Zephyr native_sim...\n";

    server.run();  // blocking
    return 0;
}
