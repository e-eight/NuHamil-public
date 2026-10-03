# Site fragment: apt
# Extracted verbatim from the Makefile's hard-coded host block.
#-----------------------------
# apt1
#-----------------------------

FC=ifort
LFLAGS+= -mkl -lgsl -lz
FFLAGS=-O3 -heap-arrays -static
FFLAGS+= -openmp
FFLAGS+= -DVERSION=\"$(VERSION)\"
ifeq ($(DEBUG_MODE),on)
  DFLAGS+=-check all
endif
LINT= -i8
