cmake_minimum_required(VERSION 3.14)
project(cie_desktop_geometry_tests LANGUAGES C CXX)
enable_testing()
add_executable(window_geometry_c window_geometry_test.c)
target_compile_features(window_geometry_c PRIVATE c_std_99)
target_compile_options(window_geometry_c PRIVATE -Wall -Wextra -Werror)
target_link_libraries(window_geometry_c PRIVATE m)
add_test(NAME desktop_window_geometry_c COMMAND window_geometry_c)
add_executable(window_geometry_cpp window_geometry_cpp_test.cc)
target_compile_features(window_geometry_cpp PRIVATE cxx_std_14)
target_compile_options(window_geometry_cpp PRIVATE -Wall -Wextra -Werror)
add_test(NAME desktop_window_geometry_cpp COMMAND window_geometry_cpp)
find_program(CIE_CLANG clang)
if(CIE_CLANG)
  add_test(NAME desktop_window_clang_module
    COMMAND "${CIE_CLANG}" -fmodules
      "-fmodules-cache-path=${CMAKE_CURRENT_BINARY_DIR}/module-cache"
      "-fmodule-map-file=${CMAKE_CURRENT_SOURCE_DIR}/../module.modulemap"
      -Wall -Wextra -Werror -fsyntax-only "${CMAKE_CURRENT_SOURCE_DIR}/module_import.m")
endif()
