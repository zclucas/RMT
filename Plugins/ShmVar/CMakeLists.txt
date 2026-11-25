cmake_minimum_required(VERSION 3.20)
project(ShmVar LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ==========================================
# Build Configuration
# ==========================================

if(MSVC)
    set(SHMVAR_COMPILE_OPTIONS
            /O2 /GL /Gy /DNDEBUG /DNOMINMAX /utf-8
    )

    set(SHMVAR_LINK_OPTIONS
            /LTCG /OPT:REF /OPT:ICF
    )
else()
    set(SHMVAR_COMPILE_OPTIONS
            -O3 -DNDEBUG -flto
            -ffunction-sections -fdata-sections
    )

    set(SHMVAR_LINK_OPTIONS
            -flto
            -static-libgcc -static-libstdc++
            -Wl,--gc-sections
    )
endif()

# ==========================================
# Shared Library (DLL)
# ==========================================

add_library(ShmVar SHARED
    shm_var.cpp
    shm_core.cpp
    shm_core.hpp
    shm_var.h
    shm_internal.hpp
    shm_allocator.hpp
    shm_rwlock.hpp
    buddy_alloc.hpp
)

target_compile_definitions(ShmVar
    PRIVATE SHMVAR_EXPORTS
)

target_include_directories(ShmVar
    PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_options(ShmVar
    PRIVATE ${SHMVAR_COMPILE_OPTIONS}
)

target_link_options(ShmVar
    PRIVATE ${SHMVAR_LINK_OPTIONS}
)

# ==========================================
# Test Executable
# ==========================================

add_executable(test_shm
    test_shm.cpp
)

target_link_libraries(test_shm
    PRIVATE ShmVar
)

target_compile_options(test_shm
    PRIVATE ${SHMVAR_COMPILE_OPTIONS}
)

if(NOT MSVC)
    # Test executable does not need static C++ runtime duplication
    target_link_options(test_shm
        PRIVATE -flto
    )
endif()

# ==========================================
# Output Configuration
# ==========================================

set_target_properties(ShmVar PROPERTIES
        PREFIX ""
        OUTPUT_NAME "ShmVar"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)

set_target_properties(test_shm PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)