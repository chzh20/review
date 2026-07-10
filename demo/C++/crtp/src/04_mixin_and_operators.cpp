#include <iostream>
#include <string_view>

namespace {

template <typename Derived>
class Printable {
public:
    void print() const {
        std::cout << derived().to_string() << '\n';
    }

protected:
    Printable() = default;
    ~Printable() = default;

private:
    const Derived& derived() const noexcept {
        return static_cast<const Derived&>(*this);
    }
};

class ErrorCode final : public Printable<ErrorCode> {
public:
    explicit ErrorCode(int value) : value_{value} {}

    [[nodiscard]] std::string_view to_string() const noexcept {
        switch (value_) {
        case 0:
            return "success";
        case 1:
            return "invalid argument";
        default:
            return "unknown error";
        }
    }

private:
    int value_;
};

template <typename Derived>
class Addable {
    friend Derived operator+(Derived lhs, const Derived& rhs) {
        lhs += rhs;
        return lhs;
    }

protected:
    Addable() = default;
    ~Addable() = default;
};

class Distance final : public Addable<Distance> {
public:
    explicit constexpr Distance(double meters = 0.0) noexcept
        : meters_{meters} {}

    constexpr Distance& operator+=(const Distance& rhs) noexcept {
        meters_ += rhs.meters_;
        return *this;
    }

    [[nodiscard]] constexpr double meters() const noexcept {
        return meters_;
    }

private:
    double meters_;
};

} // namespace

int main() {
    ErrorCode{0}.print();
    ErrorCode{1}.print();
    ErrorCode{99}.print();

    const Distance total = Distance{1.5} + Distance{2.5};
    std::cout << "distance sum: " << total.meters() << " m\n";

    return 0;
}
