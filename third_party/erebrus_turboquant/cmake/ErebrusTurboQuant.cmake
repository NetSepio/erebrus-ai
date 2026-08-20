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

# Build llama-server in an isolated CMake graph. FetchContent / add_subdirectory
# exports ggml, ggml-base, and ggml-cpu into the Flutter project and collides
# with whisper_ggml_plus on Windows.
set(_tq_prefix "${CMAKE_CURRENT_BINARY_DIR}/turboquant-ep")
set(_tq_src "${_tq_prefix}/src")
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
set(_tq_cache_args)
if(CMAKE_C_COMPILER)
  list(APPEND _tq_cache_args
    "-DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}")
endif()
if(CMAKE_CXX_COMPILER)
  list(APPEND _tq_cache_args
    "-DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}")
endif()

if(EREBRUS_TURBOQUANT_ACCELERATOR STREQUAL "CUDA")
  list(APPEND _tq_cmake_args -DGGML_CUDA=ON -DGGML_CUDA_FA=ON)
  if(CMAKE_CUDA_COMPILER)
    list(APPEND _tq_cache_args
      "-DCMAKE_CUDA_COMPILER:FILEPATH=${CMAKE_CUDA_COMPILER}")
  endif()
elseif(EREBRUS_TURBOQUANT_ACCELERATOR STREQUAL "HIP")
  list(APPEND _tq_cmake_args -DGGML_HIP=ON -DGGML_HIP_GRAPHS=ON)
elseif(NOT EREBRUS_TURBOQUANT_ACCELERATOR STREQUAL "CPU")
  message(FATAL_ERROR
          "Unsupported EREBRUS_TURBOQUANT_ACCELERATOR: "
          "${EREBRUS_TURBOQUANT_ACCELERATOR}")
endif()

set(_tq_ep_unparsed)
find_program(_tq_ninja NAMES ninja ninja.exe)
if(_tq_ninja)
  list(APPEND _tq_ep_unparsed CMAKE_GENERATOR "Ninja")
  list(APPEND _tq_cache_args
    "-DCMAKE_MAKE_PROGRAM:FILEPATH=${_tq_ninja}")
  set(_tq_server "${_tq_bin}/bin/llama-server${CMAKE_EXECUTABLE_SUFFIX}")
else()
  if(CMAKE_GENERATOR)
    list(APPEND _tq_ep_unparsed CMAKE_GENERATOR "${CMAKE_GENERATOR}")
  endif()
  if(CMAKE_GENERATOR_PLATFORM)
    list(APPEND _tq_ep_unparsed
      CMAKE_GENERATOR_PLATFORM "${CMAKE_GENERATOR_PLATFORM}")
  endif()
  if(CMAKE_GENERATOR MATCHES "Visual Studio")
    set(_tq_server
        "${_tq_bin}/bin/Release/llama-server${CMAKE_EXECUTABLE_SUFFIX}")
  else()
    set(_tq_server "${_tq_bin}/bin/llama-server${CMAKE_EXECUTABLE_SUFFIX}")
  endif()
endif()

set(_tq_cache_kw)
if(_tq_cache_args)
  set(_tq_cache_kw CMAKE_CACHE_ARGS ${_tq_cache_args})
endif()

ExternalProject_Add(erebrus_turboquant_ep
  URL "${EREBRUS_TURBOQUANT_ARCHIVE}"
  URL_HASH "SHA256=${EREBRUS_TURBOQUANT_ARCHIVE_SHA256}"
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  PREFIX "${_tq_prefix}"
  SOURCE_DIR "${_tq_src}"
  BINARY_DIR "${_tq_bin}"
  ${_tq_ep_unparsed}
  CMAKE_ARGS ${_tq_cmake_args}
  ${_tq_cache_kw}
  BUILD_COMMAND "${CMAKE_COMMAND}" --build "${_tq_bin}" --config Release --target llama-server
  INSTALL_COMMAND ""
  UPDATE_COMMAND ""
  BUILD_BYPRODUCTS "${_tq_server}"
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
