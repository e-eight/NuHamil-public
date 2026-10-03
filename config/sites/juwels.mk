# Site fragment: juwels
# Extracted verbatim from the Makefile's hard-coded host block.
#-----------------------------
# juwels
#-----------------------------

FC=ifort
ifeq ($(MPI), on)
  FC=mpiifort -DMPI
endif
LFLAGS+= -qmkl -lgsl -lz -lhdf5_fortran
FFLAGS=-O3 -heap-arrays
FFLAGS+= -qopenmp
FFLAGS+= -DVERSION=\"$(VERSION)\"
ifeq ($(gauss_laguerre),on)
  FFLAGS+= -Dgauss_laguerre
endif
FCHIRAL = -O2 -heap-arrays
FLINES =
ifeq ($(DEBUG_MODE),on)
  DFLAGS+=-check all
endif
LINT= -i8
