# ipfs_node_flutter_native (Windows FFI plugin)
#
# Builds the Go native IPFS core (ipfs_node_core.dll) automatically whenever the
# app builds for Windows, and bundles it next to the executable so the Dart FFI
# layer can load it at runtime. This file is picked up by the Flutter plugin
# system because the pubspec marks the Windows platform as an FFI plugin.
#
# Requirements detected at build time:
#   * A Go toolchain on PATH (https://go.dev/dl/).
#   * A mingw-w64 gcc (Go's cgo uses it to emit the DLL). The build reuses one
#     found on PATH, then the portable toolchain downloaded by
#     native/go/scripts/build-windows.ps1 into %LOCALAPPDATA%.

cmake_minimum_required(VERSION 3.14)

set(PLUGIN_NAME "ipfs_node_flutter_native")

# --- Go toolchain ---
find_program(GO_EXECUTABLE go)
if(NOT GO_EXECUTABLE)
  message(FATAL_ERROR
    "ipfs_node_flutter_native: Go toolchain not found on PATH. "
    "Install Go from https://go.dev/dl/ and rebuild.")
endif()

# --- mingw-w64 gcc (required by Go cgo to build a Windows shared library) ---
if(DEFINED ENV{CC} AND NOT "$ENV{CC}" STREQUAL "")
  set(IPFS_NODE_CC "$ENV{CC}")
else()
  find_program(IPFS_NODE_CC gcc)
endif()
if(NOT IPFS_NODE_CC)
  set(_portable_gcc "$ENV{LOCALAPPDATA}/ipfs-node-flutter-tools/mingw64/bin/gcc.exe")
  if(EXISTS "${_portable_gcc}")
    set(IPFS_NODE_CC "${_portable_gcc}")
  endif()
endif()
if(NOT IPFS_NODE_CC)
  message(FATAL_ERROR
    "ipfs_node_flutter_native: a mingw-w64 gcc is required to build "
    "ipfs_node_core.dll. Install one, or run native/go/scripts/build-windows.bat "
    "once to fetch a portable toolchain.")
endif()

# --- Locate the Go module ---
# Two layouts are supported:
#   1. The plugin package bundles its own Go source at <plugin>/native/go
#      (the shape used when the plugin is published to pub.dev).
#   2. The workspace monorepo keeps the Go module at <repo>/native/go.
# Flutter references plugins through .plugin_symlinks junctions on Windows;
# CMake does not resolve those, so resolve the real path with PowerShell first.
get_filename_component(IPFS_NODE_PLUGIN_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(IPFS_NODE_GO_DIR "${IPFS_NODE_PLUGIN_DIR}/native/go")
if(NOT EXISTS "${IPFS_NODE_GO_DIR}/go.mod")
  execute_process(
    COMMAND powershell -NoProfile -Command "(Get-Item '${IPFS_NODE_PLUGIN_DIR}').Target"
    OUTPUT_VARIABLE IPFS_NODE_REAL_PLUGIN_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
  )
  if(IPFS_NODE_REAL_PLUGIN_DIR)
    # Normalize the resolved Windows path (trailing backslash) to a CMake path.
    file(TO_CMAKE_PATH "${IPFS_NODE_REAL_PLUGIN_DIR}" IPFS_NODE_REAL_PLUGIN_DIR)
    set(IPFS_NODE_GO_DIR "${IPFS_NODE_REAL_PLUGIN_DIR}/native/go")
    if(NOT EXISTS "${IPFS_NODE_GO_DIR}/go.mod")
      # Workspace monorepo: the Go module lives at <repo>/native/go.
      set(IPFS_NODE_GO_DIR "${IPFS_NODE_REAL_PLUGIN_DIR}/../../native/go")
    endif()
  endif()
endif()
if(NOT EXISTS "${IPFS_NODE_GO_DIR}/go.mod")
  message(FATAL_ERROR
    "ipfs_node_flutter_native: cannot locate the Go module. Looked for go.mod "
    "under ${IPFS_NODE_PLUGIN_DIR}.")
endif()

file(GLOB_RECURSE IPFS_NODE_GO_SOURCES CONFIGURE_DEPENDS
  "${IPFS_NODE_GO_DIR}/cmd/*.go"
  "${IPFS_NODE_GO_DIR}/internal/*.go"
)

set(IPFS_NODE_CORE_DLL "${CMAKE_CURRENT_BINARY_DIR}/ipfs_node_core.dll")

add_custom_command(
  OUTPUT "${IPFS_NODE_CORE_DLL}"
  COMMAND ${CMAKE_COMMAND} -E env
    "GOOS=windows"
    "CGO_ENABLED=1"
    "CC=${IPFS_NODE_CC}"
    ${GO_EXECUTABLE} build -buildmode=c-shared -o "${IPFS_NODE_CORE_DLL}" ./cmd/ipfs_node_core
  WORKING_DIRECTORY "${IPFS_NODE_GO_DIR}"
  DEPENDS ${IPFS_NODE_GO_SOURCES}
  COMMENT "Building native IPFS node core (ipfs_node_core.dll)"
  VERBATIM
)

add_custom_target(ipfs_node_core_dll ALL DEPENDS "${IPFS_NODE_CORE_DLL}")

# Flutter FFI plugin convention: publishing the DLL through this variable makes
# the app's generated_plugins.cmake bundle it next to the executable.
set(${PLUGIN_NAME}_bundled_libraries "${IPFS_NODE_CORE_DLL}" PARENT_SCOPE)
