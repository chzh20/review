#include <atomic>
#include <cassert>
#include <cstddef>
#include <iostream>
#include <utility>

namespace {

template <typename Derived>
class RefCounted {
public:
    void retain() const noexcept {
        reference_count_.fetch_add(1, std::memory_order_relaxed);
    }

    void release() const noexcept {
        const auto previous =
            reference_count_.fetch_sub(1, std::memory_order_acq_rel);
        assert(previous > 0);
        if (previous == 1) {
            // CRTP is essential here: delete the Derived object, not a
            // RefCounted base that has no virtual destructor.
            delete static_cast<const Derived*>(this);
        }
    }

    [[nodiscard]] std::size_t use_count() const noexcept {
        return reference_count_.load(std::memory_order_relaxed);
    }

protected:
    RefCounted() = default;
    ~RefCounted() = default;

private:
    mutable std::atomic<std::size_t> reference_count_{0};
};

template <typename T>
class IntrusiveRef {
public:
    IntrusiveRef() = default;

    explicit IntrusiveRef(T* pointer) : pointer_(pointer) {
        if (pointer_ != nullptr) {
            pointer_->retain();
        }
    }

    IntrusiveRef(const IntrusiveRef& other) : pointer_(other.pointer_) {
        if (pointer_ != nullptr) {
            pointer_->retain();
        }
    }

    IntrusiveRef(IntrusiveRef&& other) noexcept
        : pointer_(std::exchange(other.pointer_, nullptr)) {}

    IntrusiveRef& operator=(IntrusiveRef other) noexcept {
        std::swap(pointer_, other.pointer_);
        return *this;
    }

    ~IntrusiveRef() {
        if (pointer_ != nullptr) {
            pointer_->release();
        }
    }

    T* operator->() const noexcept {
        return pointer_;
    }

private:
    T* pointer_ = nullptr;
};

class SyntaxNode final : public RefCounted<SyntaxNode> {
public:
    explicit SyntaxNode(int kind) noexcept : kind_{kind} {
        std::cout << "SyntaxNode(" << kind_ << ") constructed\n";
    }

    ~SyntaxNode() {
        std::cout << "SyntaxNode(" << kind_ << ") destroyed\n";
    }

    [[nodiscard]] int kind() const noexcept {
        return kind_;
    }

private:
    int kind_;
};

} // namespace

int main() {
    IntrusiveRef<SyntaxNode> first(new SyntaxNode(7));
    std::cout << "use_count after first: " << first->use_count() << '\n';

    {
        IntrusiveRef<SyntaxNode> second = first;
        std::cout << "second sees kind: " << second->kind() << '\n';
        std::cout << "use_count after copy: " << first->use_count() << '\n';
    }

    std::cout << "use_count after inner scope: " << first->use_count() << '\n';
    return 0;
}
