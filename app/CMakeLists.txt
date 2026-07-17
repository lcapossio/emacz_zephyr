# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

cmake_minimum_required(VERSION 3.20.0)

list(APPEND ZEPHYR_EXTRA_MODULES ${CMAKE_CURRENT_LIST_DIR}/..)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(emacz_zephyr_app)

add_subdirectory(${CMAKE_CURRENT_LIST_DIR}/../drivers drivers)
target_include_directories(app PRIVATE ${CMAKE_CURRENT_LIST_DIR}/../drivers/ethernet)
target_sources(app PRIVATE src/main.c src/provision.c)
