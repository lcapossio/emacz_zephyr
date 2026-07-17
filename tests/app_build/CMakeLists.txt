# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

cmake_minimum_required(VERSION 3.20.0)

set(EMACZ_ROOT ${CMAKE_CURRENT_LIST_DIR}/../..)
list(APPEND ZEPHYR_EXTRA_MODULES ${EMACZ_ROOT})
set(CONF_FILE ${EMACZ_ROOT}/app/prj.conf)
set(DTC_OVERLAY_FILE ${EMACZ_ROOT}/app/boards/mbv32.overlay)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(emacz_app_build_test)

add_subdirectory(${EMACZ_ROOT}/drivers drivers)
target_include_directories(app PRIVATE ${EMACZ_ROOT}/drivers/ethernet)
target_sources(app PRIVATE
  ${EMACZ_ROOT}/app/src/main.c
  ${EMACZ_ROOT}/app/src/provision.c
)
