#include <atomic>
#include <iostream>
#include <utility>

namespace {

class IntrusiveRefCounted {
public:
    void add_ref() const noexcept {
        ref_count_.fetch_add(1, std::memory_order_relaxed);
    }

    void release_ref() const noexcept {
        if (ref_count_.fetch_sub(1, std::memory_order_acq_rel) == 1) {
            delete this;
        }
    }

    int use_count() const noexcept {
        return ref_count_.load(std::memory_order_acquire);
    }

protected:
    IntrusiveRefCounted() = default;
    virtual ~IntrusiveRefCounted() = default;

private:
    mutable std::atomic<int> ref_count_{0};
};

template <typename T>
class IntrusivePtr {
public:
    IntrusivePtr() = default;

    explicit IntrusivePtr(T* pointer) : pointer_(pointer) {
        add_ref();
    }

    IntrusivePtr(const IntrusivePtr& other) : pointer_(other.pointer_) {
        add_ref();
    }

    IntrusivePtr(IntrusivePtr&& other) noexcept : pointer_(other.pointer_) {
        other.pointer_ = nullptr;
    }

    IntrusivePtr& operator=(IntrusivePtr other) noexcept {
        swap(other);
        return *this;
    }

    ~IntrusivePtr() {
        release_ref();
    }

    T* operator->() const noexcept {
        return pointer_;
    }

    T& operator*() const noexcept {
        return *pointer_;
    }

    explicit operator bool() const noexcept {
        return pointer_ != nullptr;
    }

    void swap(IntrusivePtr& other) noexcept {
        std::swap(pointer_, other.pointer_);
    }

private:
    void add_ref() noexcept {
        if (pointer_ != nullptr) {
            pointer_->add_ref();
        }
    }

    void release_ref() noexcept {
        if (pointer_ != nullptr) {
            pointer_->release_ref();
        }
    }

    T* pointer_ = nullptr;
};

class Packet : public IntrusiveRefCounted {
public:
    explicit Packet(int id) : id_(id) {
        std::cout << "Packet " << id_ << " constructed\n";
    }

    ~Packet() override {
        std::cout << "Packet " << id_ << " destroyed\n";
    }

    int id() const noexcept {
        return id_;
    }

private:
    int id_;
};

} // namespace

int main() {
    IntrusivePtr<Packet> first(new Packet(7));
    std::cout << "first use_count: " << first->use_count() << '\n';

    {
        IntrusivePtr<Packet> second = first;
        std::cout << "second points to packet: " << second->id() << '\n';
        std::cout << "after copy use_count: " << first->use_count() << '\n';
    }

    std::cout << "after inner scope use_count: " << first->use_count() << '\n';

    IntrusivePtr<Packet> moved = std::move(first);
    std::cout << "moved packet id: " << moved->id() << '\n';
    std::cout << "first still owns object: " << static_cast<bool>(first) << '\n';

    return 0;
}
