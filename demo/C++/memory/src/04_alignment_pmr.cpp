#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <new>
#include <string>
#include <vector>

#if __has_include(<memory_resource>)
#include <memory_resource>
#define MEMORY_DEMO_HAS_PMR 1
#else
#define MEMORY_DEMO_HAS_PMR 0
#endif

namespace {

struct alignas(64) CacheLineValue {
    explicit CacheLineValue(int value) : value(value) {
        std::cout << "CacheLineValue constructed at " << this << '\n';
    }

    ~CacheLineValue() {
        std::cout << "CacheLineValue destroyed\n";
    }

    int value;
};

} // namespace

int main() {
    alignas(CacheLineValue) std::byte storage[sizeof(CacheLineValue)];
    auto* value = new (storage) CacheLineValue(123);

    const auto address = reinterpret_cast<std::uintptr_t>(value);
    std::cout << "address % alignof(CacheLineValue): "
              << address % alignof(CacheLineValue) << '\n';
    std::cout << "value: " << value->value << '\n';
    value->~CacheLineValue();

#if MEMORY_DEMO_HAS_PMR
    std::array<std::byte, 1024> arena{};
    std::pmr::monotonic_buffer_resource pool(arena.data(), arena.size());
    std::pmr::vector<std::pmr::string> names(&pool);

    names.emplace_back("allocator-aware");
    names.emplace_back("pmr::vector");
    names.emplace_back("monotonic_buffer_resource");

    for (const auto& name : names) {
        std::cout << name << '\n';
    }

    std::cout << "arena bytes: " << arena.size() << '\n';
#else
    std::cout << "<memory_resource> is not available in this standard library\n";
#endif

    return 0;
}
