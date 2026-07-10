cmake_minimum_required(VERSION 3.16)

project(memory_management_demos LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(MEMORY_DEMO_ENABLE_SANITIZERS "Enable AddressSanitizer and UndefinedBehaviorSanitizer on supported compilers" OFF)

find_package(Threads REQUIRED)

function(add_memory_demo target source)
    add_executable(${target} ${source})
    target_compile_features(${target} PRIVATE cxx_std_17)

    if(MSVC)
        target_compile_options(${target} PRIVATE /W4 /permissive-)
    else()
        target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic)
    endif()

    if(MEMORY_DEMO_ENABLE_SANITIZERS AND NOT MSVC)
        target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
        target_link_options(${target} PRIVATE -fsanitize=address,undefined)
    endif()
endfunction()

add_memory_demo(01_lifetime_storage src/01_lifetime_storage.cpp)
add_memory_demo(02_raii_unique_ptr src/02_raii_unique_ptr.cpp)
add_memory_demo(03_shared_weak_ptr src/03_shared_weak_ptr.cpp)
add_memory_demo(04_alignment_pmr src/04_alignment_pmr.cpp)
add_memory_demo(05_exception_safety src/05_exception_safety.cpp)
add_memory_demo(06_intrusive_ptr src/06_intrusive_ptr.cpp)
add_memory_demo(07_thread_safety src/07_thread_safety.cpp)

target_link_libraries(07_thread_safety PRIVATE Threads::Threads)
