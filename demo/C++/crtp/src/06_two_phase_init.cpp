#include <iostream>
#include <memory>

namespace {

template <typename Derived>
class Initializable {
protected:
    void initialize_after_construction() {
        static_cast<Derived&>(*this).initialize_impl();
    }
};

class Service final : public Initializable<Service> {
public:
    static std::unique_ptr<Service> create(int configuration) {
        // Two-phase init: the full object is constructed first, only then
        // do we call into the derived hook. Calling initialize_impl() from
        // the base constructor would run before Service's members exist.
        auto service = std::unique_ptr<Service>(new Service(configuration));
        service->initialize_after_construction();
        return service;
    }

    [[nodiscard]] int configuration() const noexcept {
        return configuration_;
    }

private:
    friend class Initializable<Service>;

    explicit Service(int configuration) : configuration_{configuration} {
        std::cout << "Service constructed with configuration "
                  << configuration_ << '\n';
    }

    void initialize_impl() {
        std::cout << "initialize_impl sees fully-constructed configuration "
                  << configuration_ << '\n';
    }

    int configuration_;
};

} // namespace

int main() {
    auto service = Service::create(42);
    std::cout << "service configuration: " << service->configuration() << '\n';
    return 0;
}
