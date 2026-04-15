cmake_minimum_required(VERSION 3.15)
project(bhack)

#╭──────────────────────────────────────╮
#│             Get Pd Cmake             │
#╰──────────────────────────────────────╯
set(PDCMAKE_FILE ${CMAKE_BINARY_DIR}/pd.cmake)
if(NOT EXISTS ${PDCMAKE_FILE})
    message(STATUS "Downloading pd.cmake")
    file(DOWNLOAD 
    https://github.com/pure-data/pd.cmake/releases/download/v2.0.11/pd.cmake ${PDCMAKE_FILE} 
    STATUS DOWNLOAD_STATUS)
endif()
include(${PDCMAKE_FILE})

#╭──────────────────────────────────────╮
#│               Get DDDD               │
#╰──────────────────────────────────────╯
include(FetchContent)
FetchContent_Declare(
    dddd
    GIT_REPOSITORY https://github.com/EL-LOCUS-SOLUS/pd-dddd
    GIT_TAG main
)
FetchContent_MakeAvailable(dddd)
FetchContent_GetProperties(dddd)
set(DDDD_PATH ${dddd_SOURCE_DIR})
set(DDDD_LUA ${DDDD_PATH}/path/to/file.lua)
message(STATUS "dddd file: ${DDDD_LUA}")

# add object
add_custom_target(bhack COMMAND echo "Installing dependencies from bhack...")
pd_add_datafile(bhack "${CMAKE_CURRENT_SOURCE_DIR}/src/")

