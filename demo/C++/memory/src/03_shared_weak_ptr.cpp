#include <iostream>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace {

struct Widget {
    explicit Widget(int id) : id(id) {
        std::cout << "Widget " << id << " constructed\n";
    }

    ~Widget() {
        std::cout << "Widget " << id << " destroyed\n";
    }

    int id;
};

struct Node {
    explicit Node(std::string name) : name(std::move(name)) {
        std::cout << "Node " << this->name << " constructed\n";
    }

    ~Node() {
        std::cout << "Node " << name << " destroyed\n";
    }

    std::string name;
    std::vector<std::shared_ptr<Node>> children;
    std::weak_ptr<Node> parent;
};

class Session : public std::enable_shared_from_this<Session> {
public:
    static std::shared_ptr<Session> create(std::string name) {
        return std::shared_ptr<Session>(new Session(std::move(name)));
    }

    std::shared_ptr<Session> self() {
        return shared_from_this();
    }

    void print() const {
        std::cout << "Session " << name_ << '\n';
    }

private:
    explicit Session(std::string name) : name_(std::move(name)) {}

    std::string name_;
};

void observe(const std::weak_ptr<Widget>& weak) {
    if (auto locked = weak.lock()) {
        std::cout << "observed Widget " << locked->id
                  << ", use_count=" << locked.use_count() << '\n';
    } else {
        std::cout << "Widget already expired\n";
    }
}

} // namespace

int main() {
    auto shared = std::make_shared<Widget>(10);
    std::weak_ptr<Widget> weak = shared;

    std::cout << "shared.use_count(): " << shared.use_count() << '\n';
    observe(weak);

    shared.reset();
    observe(weak);

    auto root = std::make_shared<Node>("root");
    auto child = std::make_shared<Node>("child");
    root->children.push_back(child);
    child->parent = root;
    std::cout << "child parent alive: " << !child->parent.expired() << '\n';

    auto session = Session::create("download");
    auto same_session = session->self();
    std::cout << "same control block use_count: " << same_session.use_count() << '\n';
    session->print();

    return 0;
}
