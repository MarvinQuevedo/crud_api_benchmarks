cmake_minimum_required(VERSION 3.16)
project(api_crud_server LANGUAGES CXX ASM)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(SQLite3 REQUIRED)

include(FetchContent)
set(FETCHCONTENT_QUIET OFF)

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
# Gate matches the CMake/host toolchain (uname -m). If you are on Apple Silicon but see
# x86_64 here (Rosetta), use a native arm64 shell: `arch -arm64 zsh` then reconfigure build/.
set(_API_TEST_IS_ARM64_MAC FALSE)
if(APPLE)
  execute_process(
    COMMAND uname -m
    OUTPUT_VARIABLE _API_TEST_UNAME_M
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  if(_API_TEST_UNAME_M STREQUAL "arm64")
    set(_API_TEST_IS_ARM64_MAC TRUE)
  endif()
endif()

if(_API_TEST_IS_ARM64_MAC)
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
  )
else()
  if(NOT APPLE)
    message(STATUS "api_crud_asm skipped (macOS only)")
  else()
    message(STATUS "api_crud_asm skipped (configure saw uname='${_API_TEST_UNAME_M}'). On Apple Silicon under Rosetta run: scripts/build_asm_arm64.sh → cpp/build-arm64/api_crud_asm")
  endif()
endif()
