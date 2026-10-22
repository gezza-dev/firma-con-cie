cmake_minimum_required(VERSION 3.14)
project(cie_win32_resize_tests LANGUAGES CXX)
enable_testing()
set(RUNNER "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(FLUTTER_EPHEMERAL "${RUNNER}/../flutter/ephemeral")
add_executable(win32_resize_test win32_resize_test.cpp "${RUNNER}/win32_window.cpp")
target_compile_features(win32_resize_test PRIVATE cxx_std_17)
target_compile_definitions(win32_resize_test PRIVATE UNICODE _UNICODE NOMINMAX)
target_compile_options(win32_resize_test PRIVATE /W4 /WX /wd4100 /utf-8)
target_include_directories(win32_resize_test PRIVATE "${RUNNER}" "${FLUTTER_EPHEMERAL}")
target_link_libraries(win32_resize_test PRIVATE
  "${FLUTTER_EPHEMERAL}/flutter_windows.dll.lib" user32 dwmapi advapi32 uxtheme gdi32)
add_custom_command(TARGET win32_resize_test POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${FLUTTER_EPHEMERAL}/flutter_windows.dll" "$<TARGET_FILE_DIR:win32_resize_test>")
add_test(NAME win32_resize_reentrancy COMMAND win32_resize_test)
set_tests_properties(win32_resize_reentrancy PROPERTIES TIMEOUT 20)

add_executable(win32_caption_test win32_caption_test.cpp "${RUNNER}/win32_window.cpp")
target_compile_features(win32_caption_test PRIVATE cxx_std_17)
target_compile_definitions(win32_caption_test PRIVATE UNICODE _UNICODE NOMINMAX)
target_compile_options(win32_caption_test PRIVATE /W4 /WX /wd4100 /utf-8)
target_include_directories(win32_caption_test PRIVATE "${RUNNER}" "${FLUTTER_EPHEMERAL}")
target_link_libraries(win32_caption_test PRIVATE
  "${FLUTTER_EPHEMERAL}/flutter_windows.dll.lib" user32 dwmapi advapi32 uxtheme gdi32)
add_custom_command(TARGET win32_caption_test POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${FLUTTER_EPHEMERAL}/flutter_windows.dll" "$<TARGET_FILE_DIR:win32_caption_test>")
add_test(NAME win32_caption_buttons COMMAND win32_caption_test)
set_tests_properties(win32_caption_buttons PROPERTIES TIMEOUT 20)
