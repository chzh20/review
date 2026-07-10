#include <cstddef>
#include <iostream>
#include <memory>
#include <new>

namespace {

struct Tracer {
    explicit Tracer(int id) : id(id) {
        std::cout << "Tracer(" << id << ") constructed\n";
    }

    ~Tracer() {
        std::cout << "Tracer(" << id << ") destroyed\n";
    }

    int id;
};

} // namespace

int main() {
    std::cout << "storage and object lifetime are separate concepts\n";

    alignas(Tracer) std::byte storage[sizeof(Tracer)];
    std::cout << "raw storage address: " << static_cast<void*>(storage) << '\n';

    Tracer* object = new (storage) Tracer(42);
    std::cout << "object address:      " << object << '\n';
    std::cout << "object id:           " << object->id << '\n';

    object->~Tracer();

    Tracer* heap_object = new Tracer(7);
    delete heap_object;

    return 0;
}
