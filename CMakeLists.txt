cmake_minimum_required(VERSION 3.15)
project(bhack)

set(PDCMAKE_FILE ${CMAKE_BINARY_DIR}/pd.cmake)
if(NOT EXISTS ${PDCMAKE_FILE})
    message(STATUS "Downloading pd.cmake")
    file(DOWNLOAD 
    https://github.com/pure-data/pd.cmake/releases/download/v2.0.11/pd.cmake ${PDCMAKE_FILE} 
    STATUS DOWNLOAD_STATUS)
endif()
include(${PDCMAKE_FILE})

add_custom_target(bhack COMMAND echo "Installing dependencies from bhack...")
pd_add_datafile(bhack "${CMAKE_CURRENT_SOURCE_DIR}/src/")

