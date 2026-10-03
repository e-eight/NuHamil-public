# Site fragment: cedar
# Extracted verbatim from the Makefile's hard-coded host block.
#-----------------------------
# cedar
#-----------------------------

	# gfortran
MPI=on
FC=gfortran
EXEDIR=/project/6006601/shared/NuHamil/bin
ifeq ($(MPI), on)
  FC=mpifort -DMPI -DSPARC
endif
LFLAGS+= -I/cvmfs/soft.computecanada.ca/easybuild/software/2020/avx2/Compiler/gcc9/hdf5/1.10.6/include -L$(HOME)/lib
LFLAGS+= -lopenblas -llapack -lgsl -lz -lhdf5_fortran
FFLAGS=-O3 -fopenmp
FFLAGS+= -DVERSION=\"$(VERSION)\"
FCHIRAL = -O2
FLINES =-ffree-line-length-0
ifeq ($(DEBUG_MODE),on)
  DFLAGS+= -pedantic -fbounds-check -O -Wuninitialized -fbacktrace
  #FDFLAGS+=-ffpe-trap=invalid,zero,overflow # Note: gsl larguerre signal
  ifneq ($(OS), OSX)
    DFLAGS+= -pg -g
  endif
endif
LINT= -fdefault-integer-8

	# intel fortran
#FC=ifort
#EXEDIR=/project/6006601/shared/NuHamil/bin
#ifeq ($(MPI), on)
#  FC=mpiifort -DMPI
#endif
#LFLAGS+= -mkl -lgsl -lz -lhdf5_fortran
#FFLAGS=-O3 -heap-arrays
#FFLAGS+= -qopenmp
#FFLAGS+= -DVERSION=\"$(VERSION)\"
#FCHIRAL = -O2 -heap-arrays
#FLINES =
#ifeq ($(DEBUG_MODE),on)
#  DFLAGS+=-check all
#endif
#LINT= -i8
