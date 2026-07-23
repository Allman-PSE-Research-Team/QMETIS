# These programs use internal metis data structures.
include_directories(../libmetis)

# Build program.
add_executable(qgpmetis gpmetis.c cmdline_gpmetis.c io.c stat.c)
add_executable(qndmetis ndmetis.c cmdline_ndmetis.c io.c smbfactor.c)
add_executable(qmpmetis mpmetis.c cmdline_mpmetis.c io.c stat.c)
add_executable(qm2gmetis m2gmetis.c cmdline_m2gmetis.c io.c)
add_executable(qgraphchk graphchk.c io.c)
add_executable(qcmpfillin cmpfillin.c io.c smbfactor.c)

# Link with the required libraries
foreach(prog qgpmetis qndmetis qmpmetis qm2gmetis qgraphchk qcmpfillin)
  target_link_libraries(${prog} qmetis GKlib)
  if(NOT MSVC)
    target_link_libraries(${prog} m)
  endif()
endforeach(prog)

if(METIS_INSTALL)
  install(TARGETS qgpmetis qndmetis qmpmetis qm2gmetis qgraphchk qcmpfillin
    RUNTIME DESTINATION bin)
endif()
