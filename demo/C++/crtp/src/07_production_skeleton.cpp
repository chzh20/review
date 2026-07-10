#include <iostream>
#include <type_traits>
#include <utility>

#if defined(__cpp_concepts) && __cpp_concepts >= 201907L
#include <concepts>
#define CRTP_HAS_CONCEPTS 1
#else
#define CRTP_HAS_CONCEPTS 0
#endif

namespace {

#if CRTP_HAS_CONCEPTS
template <typename T>
concept RunnableImplementation = requires(T& object) {
    { object.run_impl() } -> std::same_as<void>;
};
#endif

template <typename Derived>
class Runnable {
    friend Derived;

public:
    void run() {
        static_assert(
            std::is_base_of_v<Runnable<Derived>, Derived>,
            "Derived must inherit from Runnable<Derived>"
        );
#if CRTP_HAS_CONCEPTS
        static_assert(
            RunnableImplementation<Derived>,
            "Derived must provide: void run_impl()"
        );
#endif
        derived().run_impl();
    }

protected:
    [[nodiscard]] Derived& derived() noexcept {
        return static_cast<Derived&>(*this);
    }

private:
    Runnable() = default;
    ~Runnable() = default;
};

class Task final : public Runnable<Task> {
public:
    Task() = default;

    void run_impl() {
        std::cout << "Task::run_impl executed\n";
    }
};

} // namespace

int main() {
    Task task;
    task.run();

    std::cout << "concepts available: " << CRTP_HAS_CONCEPTS << '\n';
    return 0;
}
