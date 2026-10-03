# Illinois Campus Cluster (ICC, UIUC) -- Netlib reference BLAS/LAPACK.
#
# This is the pre-2026-10-03 ICC build, kept so that earlier measurements stay
# reproducible: `make SITE=icc-refblas`.  The default ICC build (config/sites/
# icc.mk) now links MKL LP64, which was measured 1.98x faster on rampsmall
# e3max6 8x4 with unchanged numerics.  See docs/FINDINGS.md.
#
# Everything except the BLAS/LAPACK link line is identical to icc.mk.
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
ICC_LAPACK=/sw/apps/lapack/3.12.1/lib
LFLAGS+= -I$(ICC_HDF5_INC) -I$(ICC_GSL)/include
LFLAGS+= -L$(ICC_GSL)/lib -L/usr/lib64 -L$(ICC_LAPACK)
LFLAGS+= -lgsl -lgslcblas -lz
LFLAGS+= -l:libhdf5_fortran.so.$(ICC_HDF5_VER) -l:libhdf5.so.$(ICC_HDF5_VER)
LFLAGS+= -lm -ldl -llapack -lrefblas
LFLAGS+= -Wl,-rpath,$(ICC_GSL)/lib
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
