#include <algorithm>
#include <cstddef>
#include <iostream>
#include <memory>
#include <stdexcept>

namespace {

class Buffer {
public:
    explicit Buffer(std::size_t size)
        : data_(std::make_unique<int[]>(size)), size_(size) {
        std::fill_n(data_.get(), size_, 0);
    }

    void resize_strong(std::size_t new_size, bool fail_before_commit) {
        auto next = std::make_unique<int[]>(new_size);
        const std::size_t common = std::min(size_, new_size);
        std::copy_n(data_.get(), common, next.get());

        if (fail_before_commit) {
            throw std::runtime_error("simulated failure before ownership commit");
        }

        data_ = std::move(next);
        size_ = new_size;
    }

    std::size_t size() const noexcept {
        return size_;
    }

    int& operator[](std::size_t index) {
        return data_[index];
    }

    int operator[](std::size_t index) const {
        return data_[index];
    }

private:
    std::unique_ptr<int[]> data_;
    std::size_t size_;
};

} // namespace

int main() {
    Buffer buffer(3);
    buffer[0] = 11;
    buffer[1] = 22;
    buffer[2] = 33;

    try {
        buffer.resize_strong(8, true);
    } catch (const std::exception& error) {
        std::cout << "caught: " << error.what() << '\n';
    }

    std::cout << "after failed resize, size: " << buffer.size() << '\n';
    std::cout << "after failed resize, first value: " << buffer[0] << '\n';

    buffer.resize_strong(8, false);
    std::cout << "after successful resize, size: " << buffer.size() << '\n';
    std::cout << "after successful resize, first value: " << buffer[0] << '\n';

    return 0;
}
