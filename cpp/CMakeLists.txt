cmake_minimum_required(VERSION 3.20)
project(echo_guard LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(echo_guard_cli src/echo_guard_cli.cpp)

if(MSVC)
  target_compile_options(echo_guard_cli PRIVATE /W4)
else()
  target_compile_options(echo_guard_cli PRIVATE -Wall -Wextra -Wpedantic)
endif()

