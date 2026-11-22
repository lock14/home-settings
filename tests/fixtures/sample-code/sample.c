/*
 * Authentic Solarized Dark syntax preview for C (ISO C23 / C17).
 * Demonstrates preprocessors, macros, C23 attributes, constexpr, nullptr, structs, enums, pointers, and control flow.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

#define MAX_BUFFER_SIZE 2048
#define CLAMP(x, low, high) (((x) > (high)) ? (high) : (((x) < (low)) ? (low) : (x)))
#define MASK_STATUS_BYTE 0x00FF00AAUL

#ifndef LOG_LEVEL
#define LOG_LEVEL 2
#endif

#ifdef __linux__
#define PLATFORM_TARGET "Linux"
#elif defined(__APPLE__)
#define PLATFORM_TARGET "macOS"
#else
#define PLATFORM_TARGET "Generic Unix"
#endif

static_assert(MAX_BUFFER_SIZE >= 1024, "Buffer must be at least 1 KiB");

typedef enum {
    LOG_DEBUG = 0,
    LOG_INFO  = 1,
    LOG_WARN  = 2,
    LOG_ERROR = 3
} SeverityLevel;

typedef struct {
    uint32_t worker_id;
    char hostname[64];
    double current_load;
    bool is_healthy;
} WorkerNode;

static inline void emit_log(SeverityLevel level, const char *msg) {
    const char *label = "UNKNOWN";
    switch (level) {
        case LOG_DEBUG: label = "DEBUG"; break;
        case LOG_INFO:  label = "INFO";  break;
        case LOG_WARN:  label = "WARN";  break;
        case LOG_ERROR: label = "ERROR"; break;
        default: break;
    }
    printf("[%s] %s\n", label, msg);
}

[[nodiscard]] static bool validate_worker(const WorkerNode *node) {
    if (node == nullptr || !node->is_healthy) {
        return false;
    }
    return node->worker_id > 0;
}

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;
    WorkerNode *node = malloc(sizeof(WorkerNode));
    if (node == NULL) {
        emit_log(LOG_ERROR, "Memory allocation failure");
        return EXIT_FAILURE;
    }

    constexpr uint32_t DEFAULT_PORT_OFFSET = 1000U;
    uint32_t feature_flags = 0b10101100U;
    node->worker_id = 42;
    strncpy(node->hostname, "worker-01.lan", sizeof(node->hostname) - 1);
    node->current_load = CLAMP(0.725, 0.0, 1.0);
    node->is_healthy = true;

    if (!validate_worker(node)) {
        free(node);
        return EXIT_FAILURE;
    }

    for (uint32_t attempt = 0; attempt < 1U; ++attempt) {
        emit_log(LOG_INFO, "Worker node initialized successfully");
    }
    printf("Platform: %s | Max Buffer: %d | Align: %zu | Port Offset: %u | Flags: 0x%X | Mask: 0x%lX\n",
           PLATFORM_TARGET, MAX_BUFFER_SIZE, alignof(WorkerNode), DEFAULT_PORT_OFFSET,
           feature_flags, (unsigned long)MASK_STATUS_BYTE);
    printf("Node %u (%s) -> Load: %.2f%%\n",
           node->worker_id, node->hostname, node->current_load * 100.0);

    free(node);
    return EXIT_SUCCESS;
}
