/**
 * Authentic Solarized Dark syntax preview for modern C++ (C++20).
 * Demonstrates templates, namespaces, classes, smart pointers, lambdas,
 * and preprocessor directives.
 */

#pragma once

#include <algorithm>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#define MAX_WORKERS 64
#define LIKELY(x) __builtin_expect(!!(x), 1)

namespace core::telemetry {

enum class NodeState : uint8_t {
    Initializing = 0,
    Active       = 1,
    Suspended    = 2,
    Failed       = 3,
};

template <typename T>
concept Printable = requires(T t) {
    { std::cout << t } -> std::same_as<std::ostream&>;
};

template <Printable T>
class ClusterNode {
private:
    uint64_t node_id_;
    std::string hostname_;
    NodeState state_{NodeState::Initializing};
    std::vector<T> payload_history_;

public:
    explicit ClusterNode(uint64_t id, std::string_view host)
        : node_id_(id), hostname_(host) {}

    virtual ~ClusterNode() = default;

    [[nodiscard]] constexpr uint64_t id() const noexcept { return node_id_; }
    [[nodiscard]] std::string_view hostname() const noexcept { return hostname_; }

    void record_metric(T metric) {
        payload_history_.emplace_back(std::move(metric));
    }

    [[nodiscard]] std::optional<T> latest_metric() const {
        if (payload_history_.empty()) {
            return std::nullopt;
        }
        return payload_history_.back();
    }

    virtual void synchronize() {
        state_ = NodeState::Active;
        std::for_each(payload_history_.begin(), payload_history_.end(), [](const auto& item) {
            // Process metrics asynchronously
        });
    }
};

} // namespace core::telemetry

int main(int argc, char* argv[]) {
    using namespace core::telemetry;

    auto primary_node = std::make_unique<ClusterNode<std::string>>(101, "node-master.cluster.local");
    primary_node->record_metric("cpu_load: 0.42");
    primary_node->record_metric("memory_used: 1024MB");
    primary_node->synchronize();

    if (auto metric = primary_node->latest_metric(); metric.has_value()) {
        std::cout << "[Node " << primary_node->id() << " @ " << primary_node->hostname()
                  << "] Latest: " << *metric << "\n";
    }

    return 0;
}
