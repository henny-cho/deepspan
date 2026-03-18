// SPDX-License-Identifier: Apache-2.0
/**
 * firmware_sim — Simulated firmware for hw-model interaction testing.
 *
 * Connects to the hw-model shared memory (same shm as deepspan-hw-model),
 * reads version/capabilities, then sends periodic ECHO commands and reads
 * results.  Demonstrates the full RegMap MMIO protocol without requiring a
 * Zephyr build.
 *
 * Usage:
 *   deepspan-firmware-sim [--shm-name=/deepspan-sim] [--interval-ms=1000]
 */
#include "deepspan/hw_model/reg_map.hpp"
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <atomic>
#include <chrono>
#include <iostream>
#include <string>
#include <thread>

using namespace deepspan::hw_model;

static std::atomic<bool> g_running{true};
static void sighandler(int) { g_running = false; }

static std::string hex32(uint32_t v) {
    char buf[11];
    std::snprintf(buf, sizeof(buf), "0x%08X", v);
    return buf;
}

int main(int argc, char* argv[]) {
    std::string shm_name    = "/deepspan-sim";
    uint32_t    interval_ms = 1000;

    for (int i = 1; i < argc; ++i) {
        std::string arg(argv[i]);
        if (arg.rfind("--shm-name=", 0) == 0)
            shm_name = arg.substr(11);
        else if (arg.rfind("--interval-ms=", 0) == 0)
            interval_ms = static_cast<uint32_t>(std::stoul(arg.substr(14)));
        else if (arg == "-h" || arg == "--help") {
            std::cout << "Usage: deepspan-firmware-sim [--shm-name=NAME] [--interval-ms=N]\n";
            return 0;
        }
    }

    std::signal(SIGINT,  sighandler);
    std::signal(SIGTERM, sighandler);

    std::cout << "[fw-sim] starting, waiting for hw-model shm: " << shm_name << "\n";

    // ── Connect to hw-model shm (retry until hw-model creates it) ────────
    int fd = -1;
    for (int attempt = 0; attempt < 50 && g_running; ++attempt) {
        fd = shm_open(shm_name.c_str(), O_RDWR, 0);
        if (fd >= 0) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
    if (fd < 0) {
        std::cerr << "[fw-sim] ERROR: could not open shm '" << shm_name
                  << "' after 10s — is deepspan-hw-model running?\n";
        return 1;
    }

    void* base = mmap(nullptr, SHM_TOTAL_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);  // fd no longer needed after mmap
    if (base == MAP_FAILED) {
        std::cerr << "[fw-sim] ERROR: mmap failed: " << std::strerror(errno) << "\n";
        return 1;
    }

    auto* reg   = static_cast<RegMap*>(base);
    auto* stats = reinterpret_cast<ShmStats*>(static_cast<char*>(base) + SHM_STATS_OFFSET);

    // Wait for hw-model to set status=READY
    for (int i = 0; i < 20 && g_running; ++i) {
        uint32_t st = __atomic_load_n(&reg->status, __ATOMIC_ACQUIRE);
        if (st & status_bits::READY) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    uint32_t version  = __atomic_load_n(&reg->version,      __ATOMIC_ACQUIRE);
    uint32_t caps     = __atomic_load_n(&reg->capabilities,  __ATOMIC_ACQUIRE);
    uint32_t major    = (version >> 16) & 0xFF;
    uint32_t minor    = (version >> 8)  & 0xFF;
    uint32_t patch    =  version        & 0xFF;

    std::cout << "[fw-sim] connected to hw-model\n"
              << "[fw-sim]   version      = " << hex32(version)
              << "  (v" << major << "." << minor << "." << patch << ")\n"
              << "[fw-sim]   capabilities = " << hex32(caps)
              << (caps & HW_CAPS_DMA   ? "  DMA"   : "")
              << (caps & HW_CAPS_IRQ   ? "  IRQ"   : "")
              << (caps & HW_CAPS_MULTI ? "  MULTI" : "") << "\n";

    // ── Command loop ──────────────────────────────────────────────────────
    uint64_t fw_count = 0;
    while (g_running) {
        uint32_t opcode = 0x01; // ECHO
        uint32_t arg0   = 0xDEAD0000u | static_cast<uint32_t>(fw_count & 0xFFFF);
        uint32_t arg1   = static_cast<uint32_t>(fw_count);

        // Write command to RegMap
        reg->cmd_opcode = opcode;
        reg->cmd_arg0   = arg0;
        reg->cmd_arg1   = arg1;
        // Set CTRL.START (release: cmd writes must be visible before START)
        __atomic_or_fetch(&reg->ctrl, ctrl_bits::START, __ATOMIC_RELEASE);

        std::cout << "[fw-sim] cmd #" << fw_count
                  << "  opcode=" << hex32(opcode)
                  << "  arg0=" << hex32(arg0)
                  << "  arg1=" << hex32(arg1) << "\n";

        // Poll until hw-model clears START (command processed)
        bool ok = false;
        for (int t = 0; t < 2000 && g_running; ++t) {
            uint32_t ctrl = __atomic_load_n(&reg->ctrl, __ATOMIC_ACQUIRE);
            if (!(ctrl & ctrl_bits::START)) { ok = true; break; }
            std::this_thread::sleep_for(std::chrono::microseconds(500));
        }

        if (ok) {
            uint32_t rs = reg->result_status;
            uint32_t r0 = reg->result_data0;
            uint32_t r1 = reg->result_data1;
            std::cout << "[fw-sim] result #" << fw_count
                      << "  status=" << hex32(rs)
                      << "  data0=" << hex32(r0)
                      << "  data1=" << hex32(r1) << "\n";
        } else {
            std::cout << "[fw-sim] WARNING: cmd #" << fw_count << " timed out\n";
        }

        ++fw_count;
        // Update fw_cmd_count in ShmStats so server can display it
        __atomic_store_n(&stats->fw_cmd_count, fw_count, __ATOMIC_RELEASE);

        std::this_thread::sleep_for(std::chrono::milliseconds(interval_ms));
    }

    munmap(base, SHM_TOTAL_SIZE);
    std::cout << "[fw-sim] exiting after " << fw_count << " command(s)\n";
    return 0;
}
