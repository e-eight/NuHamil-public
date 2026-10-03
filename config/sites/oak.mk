# Site fragment: oak
# Extracted verbatim from the Makefile's hard-coded host block.
#-----------------------------
# oak (oak.arc.ubc.ca)
#-----------------------------

FC=ifort
EXEDIR=/global/scratch/exch/NuHamil/bin
LFLAGS+= -mkl -lgsl -lz -lhdf5_fortran
FFLAGS=-O3 -heap-arrays
FFLAGS+= -qopenmp
FFLAGS+= -DVERSION=\"$(VERSION)\"
FCHIRAL = $(FFLAGS)
FLINES =
ifeq ($(DEBUG_MODE),on)
  DFLAGS+=-check all
endif
LINT= -i8
