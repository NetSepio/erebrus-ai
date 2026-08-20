include(ExternalProject)

set(EREBRUS_TURBOQUANT_REVISION
    "c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea")
set(EREBRUS_TURBOQUANT_ARCHIVE
    "https://github.com/TheTom/llama-cpp-turboquant/archive/${EREBRUS_TURBOQUANT_REVISION}.tar.gz")
set(EREBRUS_TURBOQUANT_ARCHIVE_SHA256
    "5a7221222d658ca93dbf62ba2ca0623712547e9640605c12ebdfa8963aeda239")

set(EREBRUS_TURBOQUANT_ACCELERATOR_DEFAULT "CPU")
if(DEFINED ENV{EREBRUS_TURBOQUANT_ACCELERATOR})
  set(EREBRUS_TURBOQUANT_ACCELERATOR_DEFAULT
      "$ENV{EREBRUS_TURBOQUANT_ACCELERATOR}")
endif()
set(EREBRUS_TURBOQUANT_ACCELERATOR
    "${EREBRUS_TURBOQUANT_ACCELERATOR_DEFAULT}" CACHE STRING
    "TurboQuant desktop accelerator: CPU, CUDA, or HIP")
set_property(CACHE EREBRUS_TURBOQUANT_ACCELERATOR
             PROPERTY STRINGS CPU CUDA HIP)

# Isolated sidecar build. FetchContent / add_subdirectory exports ggml,
# ggml-base, and ggml-cpu into the Flutter graph and collides with
# whisper_ggml_plus on Windows.
set(_tq_prefix "${CMAKE_CURRENT_BINARY_DIR}/turboquant-ep")
# Keep SOURCE_DIR off PREFIX/src. CMake stores stamp files there, and Windows
# then fails the extract rename with "Access is denied".
set(_tq_src "${_tq_prefix}/llama-cpp-turboquant")
set(_tq_bin "${_tq_prefix}/build")

set(_tq_cmake_args
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DGGML_CCACHE=OFF
  -DGGML_NATIVE=OFF
  -DLLAMA_ALL_WARNINGS=OFF
  -DLLAMA_BUILD_APP=OFF
  -DLLAMA_BUILD_COMMON=ON
  -DLLAMA_BUILD_EXAMPLES=OFF
  -DLLAMA_BUILD_SERVER=ON
  -DLLAMA_BUILD_TESTS=OFF
  -DLLAMA_BUILD_TOOLS=ON
  -DLLAMA_BUILD_UI=OFF
  -DLLAMA_CURL=OFF
  -DLLAMA_LLGUIDANCE=OFF
  -DLLAMA_OPENSSL=OFF
  -DLLAMA_USE_PREBUILT_UI=OFF
)

if(EREBRUS_TURBOQUANT_ACCELERATOR STREQUAL "CUDA")
  list(APPEND _tq_cmake_args -DGGML_CUDA=ON -DGGML_CUDA_FA=ON)
elseif(EREBRUS_TURBOQUANT_ACCELERATOR STREQUAL "HIP")
  list(APPEND _tq_cmake_args -DGGML_HIP=ON -DGGML_HIP_GRAPHS=ON)
elseif(NOT EREBRUS_TURBOQUANT_ACCELERATOR STREQUAL "CPU")
  message(FATAL_ERROR
          "Unsupported EREBRUS_TURBOQUANT_ACCELERATOR: "
          "${EREBRUS_TURBOQUANT_ACCELERATOR}")
endif()

# Reuse the parent generator. Forcing Ninja under Visual Studio inherits
# CMAKE_GENERATOR_PLATFORM=x64 and breaks the inner configure.
set(_tq_gen)
if(CMAKE_GENERATOR)
  list(APPEND _tq_gen CMAKE_GENERATOR "${CMAKE_GENERATOR}")
endif()
if(CMAKE_GENERATOR_PLATFORM)
  list(APPEND _tq_gen CMAKE_GENERATOR_PLATFORM "${CMAKE_GENERATOR_PLATFORM}")
endif()
if(CMAKE_GENERATOR_TOOLSET)
  list(APPEND _tq_gen CMAKE_GENERATOR_TOOLSET "${CMAKE_GENERATOR_TOOLSET}")
endif()

if(CMAKE_GENERATOR MATCHES "Visual Studio")
  set(_tq_server
      "${_tq_bin}/bin/Release/llama-server${CMAKE_EXECUTABLE_SUFFIX}")
else()
  set(_tq_server "${_tq_bin}/bin/llama-server${CMAKE_EXECUTABLE_SUFFIX}")
endif()

ExternalProject_Add(erebrus_turboquant_ep
  URL "${EREBRUS_TURBOQUANT_ARCHIVE}"
  URL_HASH "SHA256=${EREBRUS_TURBOQUANT_ARCHIVE_SHA256}"
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  PREFIX "${_tq_prefix}"
  SOURCE_DIR "${_tq_src}"
  BINARY_DIR "${_tq_bin}"
  ${_tq_gen}
  CMAKE_ARGS ${_tq_cmake_args}
  BUILD_COMMAND "${CMAKE_COMMAND}" --build "${_tq_bin}" --config Release --target llama-server --parallel
  INSTALL_COMMAND ""
  UPDATE_COMMAND ""
  BUILD_BYPRODUCTS "${_tq_server}"
  LOG_DOWNLOAD TRUE
  LOG_CONFIGURE TRUE
  LOG_BUILD TRUE
  LOG_OUTPUT_ON_FAILURE TRUE
  USES_TERMINAL_DOWNLOAD TRUE
  USES_TERMINAL_CONFIGURE TRUE
  USES_TERMINAL_BUILD TRUE
)

set(EREBRUS_TURBOQUANT_SERVER "${_tq_server}")
set(EREBRUS_TURBOQUANT_MANIFEST
    "${CMAKE_CURRENT_BINARY_DIR}/erebrus-turboquant-runtime.json")
file(GENERATE
  OUTPUT "${EREBRUS_TURBOQUANT_MANIFEST}"
  CONTENT
"{
  \"schema_version\": 1,
  \"revision\": \"${EREBRUS_TURBOQUANT_REVISION}\",
  \"source_archive_sha256\": \"${EREBRUS_TURBOQUANT_ARCHIVE_SHA256}\",
  \"accelerator\": \"${EREBRUS_TURBOQUANT_ACCELERATOR}\",
  \"key_cache\": \"q8_0\",
  \"value_cache\": \"turbo3\"
}
")
