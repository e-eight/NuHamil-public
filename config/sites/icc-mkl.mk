# Illinois Campus Cluster (ICC, UIUC) -- with MKL BLAS instead of Netlib
# reference.  A/B variant of icc.mk for the tuned-BLAS experiment.
# Loaded by config/site.mk.  Values here reproduce the previously hard-coded
# Makefile block byte-for-byte; Phase 2 removes the ICC-specific paths from the
# Makefile itself.
#--------------------------------------------------
# Illinois Campus Cluster (ICC, UIUC)
#--------------------------------------------------
# Toolchain / libraries provided by the cluster:
#   module load gcc/13.3.0   -> gfortran 13.3.0
#   module load gsl/2.8      -> GSL 2.8
#   system zlib              (/usr/include/zlib.h, /usr/lib64/libz.so)
#   /sw/apps/lapack/3.12.1   -> reference LAPACK + reference BLAS (gfortran build)
#   HDF5 1.12.1: the Fortran module file (.mod) comes from the cluster anaconda3
#                install, while the runtime library comes from the OS
#                (/usr/lib64/libhdf5*.so.200). Both are HDF5 1.12.1, so the
#                soname and ABI match. Using the OS library keeps the binary
#                linked only against the system libgfortran (no conda runtime).
# Serial + OpenMP build by default; "make MPI=on" builds an MPI+OpenMP hybrid
# (module load openmpi/5.0.1-gcc-13.3.0).

FC=gfortran
ifeq ($(MPI), on)
  FC=mpifort -DMPI -DSPARC
endif
ICC_GSL=/sw/apps/gsl/2.8
ICC_HDF5_INC=/sw/apps/anaconda3/2024.10/include
ICC_HDF5_VER=200
MKLROOT=/sw/apps/intel/oneapi/mkl/2025.0
LFLAGS+= -I$(ICC_HDF5_INC) -I$(ICC_GSL)/include
LFLAGS+= -L$(ICC_GSL)/lib -L/usr/lib64
LFLAGS+= -lgsl -lgslcblas -lz
LFLAGS+= -l:libhdf5_fortran.so.$(ICC_HDF5_VER) -l:libhdf5.so.$(ICC_HDF5_VER)
# Tuned BLAS/LAPACK instead of Netlib reference (40% of cycles were in
# reference dgemm_).
#
# LP64, NOT ILP64.  -fdefault-integer-8 makes the program's default integer
# 8 bytes, which suggests ILP64 -- but the BLAS interface is deliberately
# narrowed: Renormalization.F90 declares 'integer(4) :: n' for its dgemm
# arguments.  Linking ILP64 made MKL read 8-byte dimensions from 4-byte
# arguments and the deuteron segfaulted (exit 139).
#
# mkl_gnu_thread is the threading layer matching gfortran + libgomp.
LFLAGS+= -L$(MKLROOT)/lib -lmkl_intel_lp64 -lmkl_gnu_thread -lmkl_core
LFLAGS+= -lm -ldl -lpthread
LFLAGS+= -Wl,-rpath,$(ICC_GSL)/lib -Wl,-rpath,$(MKLROOT)/lib
FFLAGS= -O3
CFLAGS= -O3
FFLAGS+= -fopenmp
# GCC >= 13 turns free-form line truncation (>132 chars) into an error and the
# generic compile rules do not pass $(FLINES), so disable the limit globally.
FFLAGS+= -ffree-line-length-0
FFLAGS+= -DVERSION=\"$(VERSION)\"
FLINES = -ffree-line-length-0
FCHIRAL = $(FFLAGS)
ifeq ($(DEBUG_MODE),on)
  DFLAGS+= -pedantic -fbounds-check -O -Wuninitialized -fbacktrace -g
endif
LINT= -fdefault-integer-8
