#include <iostream>

namespace {

template <typename Derived>
class Processor {
public:
    void process() {
        derived().process_impl();
    }

protected:
    Processor() = default;
    ~Processor() = default;

private:
    Derived& derived() noexcept {
        return static_cast<Derived&>(*this);
    }
};

class JsonProcessor final : public Processor<JsonProcessor> {
public:
    void process_impl() {
        std::cout << "Processing JSON\n";
    }
};

class XmlProcessor final : public Processor<XmlProcessor> {
public:
    void process_impl() {
        std::cout << "Processing XML\n";
    }
};

template <typename T>
void run(T& processor) {
    processor.process();
}

} // namespace

int main() {
    JsonProcessor json;
    XmlProcessor xml;

    json.process();
    xml.process();

    run(json);
    run(xml);

    return 0;
}
