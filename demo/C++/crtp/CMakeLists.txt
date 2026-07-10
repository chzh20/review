cmake_minimum_required(VERSION 3.16)

project(crtp_demos LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

function(add_crtp_demo target source)
    add_executable(${target} ${source})
    target_compile_features(${target} PRIVATE cxx_std_17)

    if(MSVC)
        target_compile_options(${target} PRIVATE /W4 /permissive-)
    else()
        target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic)
    endif()
endfunction()

add_crtp_demo(01_static_polymorphism src/01_static_polymorphism.cpp)
add_crtp_demo(02_object_layout src/02_object_layout.cpp)
add_crtp_demo(03_type_safety src/03_type_safety.cpp)
add_crtp_demo(04_mixin_and_operators src/04_mixin_and_operators.cpp)
add_crtp_demo(05_intrusive_refcount src/05_intrusive_refcount.cpp)
add_crtp_demo(06_two_phase_init src/06_two_phase_init.cpp)
add_crtp_demo(07_production_skeleton src/07_production_skeleton.cpp)
