#include <iostream>
#include <type_traits>

namespace {

template <typename Derived>
class Base {
    friend Derived;

public:
    void interface() {
        static_assert(
            std::is_base_of_v<Base<Derived>, Derived>,
            "Derived must inherit from Base<Derived>"
        );
        derived().implementation();
    }

private:
    Base() = default;
    ~Base() = default;

    Derived& derived() noexcept {
        return static_cast<Derived&>(*this);
    }
};

class Good final : public Base<Good> {
public:
    void implementation() {
        std::cout << "Good::implementation\n";
    }
};

} // namespace

int main() {
    Good good;
    good.interface();

    std::cout << "Base<Good> is a base of Good: "
              << std::is_base_of_v<Base<Good>, Good> << '\n';

    return 0;
}
