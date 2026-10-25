cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

find_program(GLIB_COMPILE_RESOURCES glib-compile-resources)
if(NOT GLIB_COMPILE_RESOURCES)
  message(FATAL_ERROR "glib-compile-resources is required to embed the CIE ID icon")
endif()
set(ICON_RESOURCE "${CMAKE_CURRENT_BINARY_DIR}/cie_id_icons.c")
add_custom_command(OUTPUT "${ICON_RESOURCE}"
  COMMAND "${GLIB_COMPILE_RESOURCES}"
    "${CMAKE_CURRENT_SOURCE_DIR}/cie-id.gresource.xml"
    "--sourcedir=${CMAKE_CURRENT_SOURCE_DIR}/../resources"
    "--target=${ICON_RESOURCE}" --generate-source --c-name=cie_id_icons
  DEPENDS "cie-id.gresource.xml" "../resources/cie-id.png"
  VERBATIM)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "${ICON_RESOURCE}"
  "main.cc"
  "my_application.cc"
  "text_scaling.cc"
  "window_sizing.cc"
  "window_chrome.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
pkg_check_modules(X11 REQUIRED IMPORTED_TARGET x11)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::X11)
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
