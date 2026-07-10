#include <iostream>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace {

class Counter {
public:
    void increment() {
        std::lock_guard<std::mutex> lock(mutex_);
        ++value_;
    }

    int value() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return value_;
    }

private:
    mutable std::mutex mutex_;
    int value_ = 0;
};

} // namespace

int main() {
    auto counter = std::make_shared<Counter>();
    std::vector<std::thread> workers;

    for (int i = 0; i < 4; ++i) {
        workers.emplace_back([counter] {
            for (int j = 0; j < 1000; ++j) {
                counter->increment();
            }
        });
    }

    for (auto& worker : workers) {
        worker.join();
    }

    std::cout << "final value: " << counter->value() << '\n';
    std::cout << "shared_ptr use_count after joins: " << counter.use_count() << '\n';

    return 0;
}
