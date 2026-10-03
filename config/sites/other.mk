# Site fragment: other
# Extracted verbatim from the Makefile's hard-coded host block.
#--------------------------------------------------
# Default Parameters
#--------------------------------------------------

FDEP=makedepf90
FC=gfortran
ifeq ($(MPI), on)
  FC=mpif90 -DMPI -DSPARC
endif
LFLAGS+= -I/usr/local/include -L/usr/local/lib #-I/usr/include/hdf5/serial
ifeq ($(arch), arm)
  LFLAGS+= -I/opt/homebrew/include -L/opt/homebrew/lib
endif
LFLAGS+= -lgsl -lz -lhdf5_fortran -lm -ldl
ifeq ($(use_mkl), on)
  LFLAGS+= -lmkl_intel_lp64 -lmkl_gnu_thread -lmkl_core -lpthread
else
  LFLAGS+= -lblas -llapack
endif
FFLAGS= -O3
CFLAGS= -O3
FFLAGS+= -fopenmp #-fdec-math
FFLAGS+= -DVERSION=\"$(VERSION)\"
FLINES = -ffree-line-length-0
FCHIRAL = $(FFLAGS)
#FFLAGS+= -ff2c # for dot product (LinAlgf90)
ifeq ($(DEBUG_MODE),on)
  DFLAGS+= -pedantic -fbounds-check -O -Wuninitialized -fbacktrace
  #DFLAGS+=-ffpe-trap=invalid,zero,overflow # Note: gsl larguerre signal
  ifneq ($(OS), OSX)
    DFLAGS+= -pg -g
  endif
endif
LINT= -fdefault-integer-8
