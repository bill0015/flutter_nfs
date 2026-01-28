
# flutter_nfs - High-performance NFS client for Flutter
#
# Copyright (c) 2024 Bill
#

cmake_minimum_required(VERSION 3.10)

project(flutter_nfs VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Android/Linux/Windows usually need this
if(WIN32)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
endif()

# We need the nfs library. We can assume it's built or available. 
# For now, let's include the libnfs source directly or find_package if installed
# This example assumes you have libnfs sources in `src/libnfs` or similar.

# Add libnfs subdirectory (assuming it has a CMakeLists.txt)
# If libnfs is not checked out, you might need to handle that.
# For simplicity, we assume `libnfs` is a submodule or copied into `src/libnfs`
add_subdirectory(libnfs)

add_library(flutter_nfs SHARED
  nfs_bridge.c
  libretro_vfs_impl.cpp
  block_cache.cpp
)

target_link_libraries(flutter_nfs PRIVATE nfs)

# Include directories
target_include_directories(flutter_nfs PRIVATE
  .
  libnfs/include
  libnfs/include/nfsc
)

# Android specific logs
if(ANDROID)
  find_library(log-lib log)
  target_link_libraries(flutter_nfs PRIVATE ${log-lib})
elseif(LINUX)
  # Linux linker flags if needed
  target_link_options(flutter_nfs PRIVATE "-Wl,-z,max-page-size=16384")
endif()

# Plugin properties
set_target_properties(flutter_nfs PROPERTIES
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

if (WIN32)
  target_link_libraries(flutter_nfs PRIVATE ws2_32)
  target_compile_definitions(flutter_nfs PRIVATE WIN32_LEAN_AND_MEAN)
endif()

# Compiler options
target_compile_options(flutter_nfs PRIVATE
  $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra>
  $<$<COMPILE_LANGUAGE:C>:-Wall -Wextra>
)


set_target_properties(flutter_nfs PROPERTIES
  OUTPUT_NAME "flutter_nfs"
)
