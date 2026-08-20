cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "erebrus_turboquant")
project(${PROJECT_NAME} LANGUAGES C CXX)

include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/ErebrusTurboQuant.cmake")

install(
  PROGRAMS "${EREBRUS_TURBOQUANT_SERVER}"
  DESTINATION "erebrus_turboquant"
  COMPONENT Runtime
)
install(
  FILES "${EREBRUS_TURBOQUANT_MANIFEST}"
  DESTINATION "erebrus_turboquant"
  COMPONENT Runtime
)
