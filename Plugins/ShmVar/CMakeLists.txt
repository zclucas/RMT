cmake_minimum_required(VERSION 3.20)
project(ShmVar LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Shared Library (DLL)
add_library(ShmVar SHARED
    shm_var.cpp
    shm_var.h
    shm_internal.h
)

target_compile_definitions(ShmVar PRIVATE SHMVAR_EXPORTS)
target_include_directories(ShmVar PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

# Test executable
add_executable(test_shm test_shm.cpp)
target_link_libraries(test_shm PRIVATE ShmVar)
