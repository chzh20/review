#include <cstddef>
#include <cstdint>
#include <iostream>

namespace {

class DynamicBase {
public:
    virtual ~DynamicBase() = default;
    virtual void process() = 0;
};

class DynamicDerived final : public DynamicBase {
public:
    void process() override {}

private:
    std::int32_t value_{};
};

template <typename Derived>
class StaticBase {
public:
    void process() {
        static_cast<Derived&>(*this).process_impl();
    }
};

class StaticDerived final : public StaticBase<StaticDerived> {
public:
    void process_impl() {}

private:
    std::int32_t value_{};
};

class Prefix {
public:
    std::int64_t prefix{};
};

template <typename Derived>
class Feature {
public:
    Derived* derived_address() noexcept {
        return static_cast<Derived*>(this);
    }
};

class Object final : public Prefix, public Feature<Object> {
public:
    std::int32_t value{};
};

} // namespace

int main() {
    std::cout << "sizeof(DynamicDerived) with vptr: "
              << sizeof(DynamicDerived) << '\n';
    std::cout << "sizeof(StaticDerived) via CRTP:   "
              << sizeof(StaticDerived) << '\n';
    std::cout << "empty CRTP base is elided (EBO): StaticDerived == int32? "
              << (sizeof(StaticDerived) == sizeof(std::int32_t)) << '\n';

    Object object;
    auto* feature = static_cast<Feature<Object>*>(&object);
    auto* recovered = feature->derived_address();

    const auto object_address = reinterpret_cast<std::uintptr_t>(&object);
    const auto feature_address = reinterpret_cast<std::uintptr_t>(feature);

    std::cout << "under multiple inheritance, Feature* may differ from Object*: "
              << (object_address != feature_address) << '\n';
    std::cout << "static_cast<Derived*> recovers the full object: "
              << (recovered == &object) << '\n';

    return 0;
}
