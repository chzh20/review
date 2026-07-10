#include <cstdio>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <utility>

namespace {

struct Engine {
    explicit Engine(int version) : version(version) {
        std::cout << "Engine " << version << " constructed\n";
    }

    ~Engine() {
        std::cout << "Engine " << version << " destroyed\n";
    }

    void start() const {
        std::cout << "Engine " << version << " started\n";
    }

    int version;
};

struct FileCloser {
    void operator()(std::FILE* file) const noexcept {
        if (file != nullptr) {
            std::fclose(file);
            std::cout << "FILE* closed by custom deleter\n";
        }
    }
};

using UniqueFile = std::unique_ptr<std::FILE, FileCloser>;

std::unique_ptr<Engine> create_engine() {
    return std::make_unique<Engine>(1);
}

void replace_engine(std::unique_ptr<Engine>& target) {
    auto next = std::make_unique<Engine>(2);
    target = std::move(next);
}

UniqueFile open_current_source() {
    UniqueFile file(std::fopen(__FILE__, "r"));
    if (!file) {
        throw std::runtime_error("failed to open source file");
    }
    return file;
}

} // namespace

int main() {
    auto engine = create_engine();
    engine->start();

    replace_engine(engine);
    engine->start();

    auto file = open_current_source();
    char buffer[64] = {};
    if (std::fgets(buffer, sizeof(buffer), file.get()) != nullptr) {
        std::cout << "first bytes from source: " << buffer;
    }

    std::cout << "sizeof(unique_ptr<Engine>): " << sizeof(engine) << '\n';
    std::cout << "sizeof(unique_ptr<FILE, FileCloser>): " << sizeof(file) << '\n';

    return 0;
}
