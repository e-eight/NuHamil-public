# Site fragment: strongint
# Extracted verbatim from the Makefile's hard-coded host block.
#--------------------------------------------------
# Strongint cluster
#--------------------------------------------------

FC=gfortran
LFLAGS+= -lz -lhdf5_fortran -lgsl -lm -ldl -I/$(HOME)/include
ifeq ($(use_mkl), on)
  LFLAGS+= -L/opt/intel/mkl/lib/intel64/ -L/opt/intel/lib/intel64/
  LFLAGS+= -lmkl_intel_lp64 -lmkl_gnu_thread -lmkl_core -lpthread
else
  LFLAGS+= -lblas -llapack
endif
FFLAGS= -O3
FFLAGS+= -fopenmp -fdec-math
FFLAGS+= -DVERSION=\"$(VERSION)\"
FLINES = -ffree-line-length-0
FCHIRAL = $(FFLAGS)
LINT= -fdefault-integer-8
