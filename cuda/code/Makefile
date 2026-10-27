NVCC    ?= nvcc
ARCH    ?= -arch=sm_80
NVFLAGS ?= -O3 -std=c++17 $(ARCH) -Xptxas -v -lineinfo

TARGETS = 00_sanity 01_vector_add 02_matmul 03_transpose 04_reduction 05_scan 06_histogram

all: $(TARGETS)

%: %.cu common.h
	$(NVCC) $(NVFLAGS) -o $@ $<

# 示例：用 ncu 看单个 kernel 的 SOL
prof: 02_matmul
	ncu --set full --kernel-name matmulTiled ./02_matmul 1024

clean:
	rm -f $(TARGETS)

.PHONY: all clean prof
