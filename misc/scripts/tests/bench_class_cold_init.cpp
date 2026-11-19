// Standalone GCC/Clang model of Cgame's cold SafeFlag-backed GDCLASS init path.
#include <atomic>
#include <cassert>
#include <cstdlib>
#include <iostream>
#include <mutex>
#include <thread>
#include <vector>

#if defined(__GNUC__)
#define COLD __attribute__((cold))
#else
#define COLD
#endif

struct SafeFlag {
    std::atomic<bool> state{false};
    bool is_set() const { return state.load(std::memory_order_acquire); }
    void set() { state.store(true, std::memory_order_release); }
};

struct MockGDClass {
    static std::atomic<int> bindings;
    static std::atomic<int> parents;
    static std::atomic<int> derived;
    static void initialize_class() {
        static SafeFlag initialized;
        if (initialized.is_set()) {
            return;
        }
        _initialize_class_cold(initialized);
    }

private:
#if defined(__GNUC__)
    __attribute__((noinline))
#endif
    COLD static void _initialize_class_cold(SafeFlag &initialized) {
        static std::mutex mutex;
        std::lock_guard<std::mutex> lock(mutex);
        if (initialized.is_set()) {
            return;
        }
        ++parents;
        ++bindings;
        ++derived;
        initialized.set();
    }
};

std::atomic<int> MockGDClass::bindings{0};
std::atomic<int> MockGDClass::parents{0};
std::atomic<int> MockGDClass::derived{0};

int main() {
    constexpr int threads = 24;
    constexpr int attempts = 10000;
    std::vector<std::thread> workers;
    workers.reserve(threads);
    for (int i = 0; i < threads; ++i) {
        workers.emplace_back([] {
            for (int j = 0; j < attempts; ++j) {
                MockGDClass::initialize_class();
            }
        });
    }
    for (std::thread &thread : workers) {
        thread.join();
    }
    if (MockGDClass::bindings != 1 || MockGDClass::parents != 1 || MockGDClass::derived != 1) {
        std::cerr << "Class initialization executed more than once\n";
        return EXIT_FAILURE;
    }
    std::cout << "PASS: cold initialization called once over " << (threads * attempts) << " concurrent calls\n";
    return EXIT_SUCCESS;
}
