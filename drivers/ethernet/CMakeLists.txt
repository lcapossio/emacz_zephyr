# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

if(CONFIG_ETH_EMACZERO)
  if(TARGET app)
    target_sources(app PRIVATE eth_emaczero.c)
    if(CONFIG_ETH_EMACZERO_PROFILE)
      target_sources(app PRIVATE eth_emaczero_profile.c)
    endif()
  else()
    zephyr_library()
    zephyr_library_sources(eth_emaczero.c)
    zephyr_library_sources_ifdef(CONFIG_ETH_EMACZERO_PROFILE eth_emaczero_profile.c)
  endif()
endif()
