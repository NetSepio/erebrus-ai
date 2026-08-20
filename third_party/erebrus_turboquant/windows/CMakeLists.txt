cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "erebrus_turboquant")
project(${PROJECT_NAME} LANGUAGES C CXX)

include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/ErebrusTurboQuant.cmake")

# Flutter Windows sets CMAKE_INSTALL_PREFIX to $<TARGET_FILE_DIR:...> after
# plugins are included. install() here snapshots that genex literally and
# cmake_install.cmake then tries to mkdir "$<TARGET_FILE_DIR:erebrus_ai>/...".
# Export paths so the app windows/CMakeLists.txt can install after prefix.
set(EREBRUS_TURBOQUANT_SERVER "${EREBRUS_TURBOQUANT_SERVER}" PARENT_SCOPE)
set(EREBRUS_TURBOQUANT_MANIFEST "${EREBRUS_TURBOQUANT_MANIFEST}" PARENT_SCOPE)
