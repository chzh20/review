# 现代 Python 工程项目简明笔记

## 1. 核心概念

### Python 解释器

真正执行 Python 代码的程序：

```bash
python
python3
.venv/bin/python
```

查看当前解释器：

```bash
which python
python --version
```

***

### 虚拟环境

为项目隔离依赖环境：

```bash
python -m venv .venv
source .venv/bin/activate
```

如果是 `csh/tcsh`：

```csh
source .venv/bin/activate.csh
rehash
```

作用：

* 不污染系统 Python
* 不同项目使用不同依赖版本
* `pip install` 安装到 `.venv`

***

### 依赖环境

当前虚拟环境中安装的包：

```bash
pip list
pip freeze
```

***

## 2. 推荐项目结构

使用 `src layout`：

```text
mini_infer/
  pyproject.toml
  README.md
  .gitignore
  .pre-commit-config.yaml

  src/
    mini_infer/
      __init__.py
      core.py
      cli.py

  tests/
    test_core.py
    test_cli.py
```

含义：

```text
distribution package: mini_infer 或 mini-infer
import package:       mini_infer
console command:      mini_infer 或 mini-infer
```

***

## 3. `pyproject.toml`

推荐配置：

```toml
[build-system]
requires = ["setuptools>=77.0.3"]
build-backend = "setuptools.build_meta"

[project]
name = "mini_infer"
version = "0.1.0"
description = "A demo mini_infer"
readme = "README.md"
requires-python = ">=3.12"
dependencies = []

[project.optional-dependencies]
dev = [
    "pytest",
    "ruff",
    "mypy",
    "pre-commit",
    "build",
]

[project.scripts]
mini_infer = "mini_infer.cli:main"

[tool.setuptools.packages.find]
where = ["src"]

[tool.pytest.ini_options]
testpaths = ["tests"]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B"]

[tool.mypy]
python_version = "3.12"
strict = true
```

如果想让命令叫：

```bash
mini-infer
```

则改成：

```toml
[project.scripts]
mini-infer = "mini_infer.cli:main"
```

注意：  
左边是命令名，可以有 `-`；右边是 Python import 路径，必须用 `_`。

***

## 4. 安装项目

开发模式安装：

```bash
python -m pip install -e ".[dev]"
```

含义：

```text
-e      editable install
.       当前项目
[dev]   安装开发依赖
```

检查命令是否生成：

```bash
which mini_infer
```

如果找不到，`csh/tcsh` 中执行：

```csh
rehash
```

***

## 5. `core.py`

业务逻辑放这里：

```python
def add(a: float, b: float) -> float:
    return a + b


def sub(a: float, b: float) -> float:
    return a - b


def mul(a: float, b: float) -> float:
    return a * b


def div(a: float, b: float) -> float:
    return a / b
```

注意：  
`mypy strict = true` 要求参数也写类型。

错误写法：

```python
def add(a, b) -> float:
    return a + b
```

正确写法：

```python
def add(a: float, b: float) -> float:
    return a + b
```

***

## 6. `cli.py` 处理用户参数

使用标准库 `argparse`：

```python
import argparse

from .core import add, div, mul, sub


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Mini-Infer",
        prog="mini_infer",
    )

    parser.add_argument(
        "-v",
        "--version",
        action="version",
        version="%(prog)s 1.0.0",
    )

    parser.add_argument(
        "operation",
        choices=["add", "div", "mul", "sub"],
        help="Operation to perform",
    )

    parser.add_argument("a", type=float, help="First number")
    parser.add_argument("b", type=float, help="Second number")

    return parser


def run(operation: str, a: float, b: float) -> float:
    if operation == "add":
        return add(a, b)
    if operation == "div":
        return div(a, b)
    if operation == "mul":
        return mul(a, b)
    if operation == "sub":
        return sub(a, b)

    raise ValueError(f"Unsupported operation: {operation}")


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    print(run(args.operation, args.a, args.b))
```

使用：

```bash
mini_infer --help
mini_infer --version
mini_infer add 1 2
mini_infer sub 1 2
mini_infer mul 3 4
mini_infer div 10 2
```

***

## 7. `__init__.py`

```python
from .cli import main
from .core import add, div, mul, sub

__all__ = ["add", "div", "main", "mul", "sub"]
```

如果 Ruff 报：

```text
I001 Import block is un-sorted or un-formatted
```

可以运行：

```bash
ruff check . --fix
```

***

## 8. 测试

`tests/test_core.py`：

```python
from mini_infer.core import add, div, mul, sub


def test_add() -> None:
    assert add(1, 2) == 3


def test_sub() -> None:
    assert sub(1, 2) == -1


def test_mul() -> None:
    assert mul(3, 4) == 12


def test_div() -> None:
    assert div(10, 2) == 5
```

运行：

```bash
pytest
```

***

## 9. 常用质量检查

```bash
ruff check .
ruff check . --fix
ruff format .
mypy .
pytest
```

### Ruff 常见错误

#### import 顺序

```text
I001 Import block is un-sorted or un-formatted
```

修复：

```bash
ruff check . --fix
```

#### 行太长

```text
E501 Line too long
```

把长行拆成多行即可。

***

## 10. pre-commit

`.pre-commit-config.yaml`：

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.15.20
    hooks:
      - id: ruff-check
        args: [--fix]
      - id: ruff-format
```

安装：

```bash
pre-commit install
```

手动运行：

```bash
pre-commit run --all-files
```

***

## 11. 推荐开发流程

```bash
python -m venv .venv
source .venv/bin/activate

python -m pip install -e ".[dev]"

mini_infer --help
mini_infer add 1 2

ruff check .
ruff format .
mypy .
pytest
```

***

## 12. 一句话总结

现代 Python 工程推荐：

```text
src layout
+ pyproject.toml
+ setuptools
+ pip install -e ".[dev]"
+ argparse CLI
+ pytest
+ ruff
+ mypy
+ pre-commit
```

其中：

```text
core.py      写业务逻辑
cli.py       处理命令行参数
tests/       写测试
pyproject.toml 管构建、依赖、入口点和工具配置
```

