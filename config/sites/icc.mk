# Illinois Campus Cluster (ICC, UIUC) -- site fragment
# Loaded by config/site.mk.  Phase 2 moved the ICC-specific paths out of the
# Makefile; the build is selected entirely by this file.
#
# BLAS/LAPACK: MKL LP64 by default.  The former Netlib reference link line is
# kept in config/sites/icc-refblas.mk, so pre-2026-10-03 results remain
# reproducible with `make SITE=icc-refblas`.
#--------------------------------------------------
# Illinois Campus Cluster (ICC, UIUC)
#--------------------------------------------------
# Toolchain / libraries provided by the cluster:
#   module load gcc/13.3.0   -> gfortran 13.3.0
#   module load gsl/2.8      -> GSL 2.8
#   system zlib              (/usr/include/zlib.h, /usr/lib64/libz.so)
#   /sw/apps/intel/oneapi/mkl/2025.0 -> MKL, the default BLAS/LAPACK
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
# Tuned BLAS/LAPACK, measured at 1.98x on rampsmall e3max6 8x4 with unchanged
# numerics (bench/accept.py PASS).  The profile that motivated it found 40 % of
# cycles inside the Netlib *reference* dgemm_ -- see docs/FINDINGS.md.
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
# Instruction set: deliberately NOT set.  -march=x86-64-v3 (AVX2/FMA) was tried
# and measured neutral -- 148 s vs 150 s on the ramp small case at 16x2, inside
# the 1.6 % run-to-run noise -- so it is not worth the portability constraint it
# adds.  The hot loops are dominated by library calls and memory access, not by
# scalar-vs-vector codegen, and MKL picks its own kernels at run time anyway.
# (If it is ever revisited: not -march=native, since the pool is heterogeneous,
# and not x86-64-v4, since AVX-512 would exclude the Zen 2 nodes.)
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
