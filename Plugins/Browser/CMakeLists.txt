cmake_minimum_required(VERSION 3.20)
project(RMTBrowser LANGUAGES CXX)

set(CDP_SOURCE_DIR "" CACHE PATH "CDP-for-CPP source directory")
set(CDP_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
if(CDP_SOURCE_DIR)
    add_subdirectory("${CDP_SOURCE_DIR}" cdp EXCLUDE_FROM_ALL)
else()
    include(FetchContent)
    FetchContent_Declare(cdp
        GIT_REPOSITORY https://github.com/ByteAshen/CDP-for-CPP.git
        GIT_TAG 1298a9d4956d76eb45b8dd8a1ea607fcdd21e7e7
    )
    FetchContent_MakeAvailable(cdp)
endif()

include(cmake/BrowserSessions.cmake)

add_library(RMT_Browser SHARED RMT_Browser.cpp)
target_compile_definitions(RMT_Browser PRIVATE BROWSER_EXPORTS)
target_compile_options(RMT_Browser PRIVATE /utf-8 /bigobj)
target_link_libraries(RMT_Browser PRIVATE CDPLib::cdp crypt32 ole32 advapi32 user32)
