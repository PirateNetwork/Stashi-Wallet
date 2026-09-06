# Ship the toolchain's redistributable CRT beside the executable. Both the
# portable archive and per-user installer consume this same installed bundle.
# Windows 10+ supplies the UCRT; debug runtimes must never be redistributed.
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
set(CMAKE_INSTALL_DEBUG_LIBRARIES FALSE)
include(InstallRequiredSystemLibraries)
if(MSVC)
  foreach(required msvcp140.dll vcruntime140.dll vcruntime140_1.dll)
    set(found FALSE)
    foreach(library IN LISTS CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
      get_filename_component(name "${library}" NAME)
      if(name STREQUAL required AND EXISTS "${library}")
        set(found TRUE)
      endif()
    endforeach()
    if(NOT found)
      message(FATAL_ERROR "Missing Visual C++ redistributable: ${required}")
    endif()
  endforeach()
  install(PROGRAMS ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS}
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime
    CONFIGURATIONS Profile Release)
endif()
