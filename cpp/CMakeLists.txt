cmake_minimum_required(VERSION 3.16)
project(api_crud_server LANGUAGES CXX ASM)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(SQLite3 REQUIRED)

include(FetchContent)
set(FETCHCONTENT_QUIET OFF)

# cpp-httplib links OpenSSL/Brotli if found. On Apple Silicon with a Rosetta (x86) CMake,
# api_crud_asm is built arm64 while FindOpenSSL may pick /usr/local x86 — link fails.
# This project only uses HTTP for the local CRUD API.
set(HTTPLIB_USE_OPENSSL_IF_AVAILABLE OFF CACHE BOOL "" FORCE)
set(HTTPLIB_USE_BROTLI_IF_AVAILABLE OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
  httplib
  GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
  GIT_TAG v0.18.3
)
FetchContent_Declare(
  json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.11.3
)

FetchContent_MakeAvailable(httplib json)

add_executable(api_crud_server
  src/main.cpp
  src/app/config.cpp
  src/db/database.cpp
  src/db/item_repository.cpp
  src/http/server_app.cpp
)

target_include_directories(api_crud_server PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(api_crud_server PRIVATE
  httplib::httplib
  nlohmann_json::nlohmann_json
  SQLite::SQLite3
)

# ARM64 assembly entry + full C++ stack (same API as api_crud_server).
# Enable on: (1) configure-time uname arm64, or (2) Apple Silicon hardware (sysctl), so
# Rosetta/x86 CMake on M1/M2/M3 still gets the target; use OSX_ARCHITECTURES arm64 on it.
set(_API_TEST_IS_ARM64_MAC FALSE)
set(_API_TEST_APPLE_SILICON FALSE)
set(_API_TEST_UNAME_M "")
if(APPLE)
  execute_process(
    COMMAND uname -m
    OUTPUT_VARIABLE _API_TEST_UNAME_M
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  if(_API_TEST_UNAME_M STREQUAL "arm64")
    set(_API_TEST_IS_ARM64_MAC TRUE)
  endif()
  execute_process(
    COMMAND sysctl -n hw.optional.arm64
    OUTPUT_VARIABLE _API_TEST_HW_ARM64
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
  )
  if(_API_TEST_HW_ARM64 STREQUAL "1")
    set(_API_TEST_APPLE_SILICON TRUE)
  endif()
endif()

if(_API_TEST_IS_ARM64_MAC OR _API_TEST_APPLE_SILICON)
  add_executable(api_crud_asm
    ${CMAKE_CURRENT_SOURCE_DIR}/../asm/entry.s
    src/asm/asm_bridge.cpp
    src/app/config.cpp
    src/db/database.cpp
    src/db/item_repository.cpp
    src/http/server_app.cpp
  )
  target_include_directories(api_crud_asm PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
  )
  target_link_libraries(api_crud_asm PRIVATE
    httplib::httplib
    nlohmann_json::nlohmann_json
    SQLite::SQLite3
  )
  set_target_properties(api_crud_asm PROPERTIES
    LINKER_LANGUAGE CXX
    OSX_ARCHITECTURES arm64
  )
else()
  if(NOT APPLE)
    message(STATUS "api_crud_asm skipped (macOS only)")
  else()
    message(STATUS "api_crud_asm skipped (not Apple Silicon)")
  endif()
endif()
