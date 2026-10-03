#--------------------------------------------------
# Make file for NuHamil code
#
# When we use ifort,
# -heap-arrays option is needed for built in transpose function with
#  large dimension matrix
#--------------------------------------------------
TARGET=NuHamil
INSTLDIR=$(HOME)/bin
EXEDIR=$(PWD)/exe
MODDIR = mod
use_mkl=off
DEBUG_MODE=off
MPI=off

OS = Linux
arch =
ifneq (,$(findstring arwin,$(shell uname)))
  OS = OSX
  arch = $(shell uname -p)
endif
$(info OS $(OS))
$(info Debug mode $(DEBUG_MODE))
BRANCH=$(shell git branch -v | grep '*' | awk '{printf "%s",$$2}')
COMMIT=$(shell git log -1 | awk 'NR==1 {printf "%s",$$2}')
ifneq (,$(findstring HEAD,$(BRANCH)))
  BRANCH=HEAD
endif

VERSION=$(BRANCH):$(COMMIT)
FDEP=
FC=
LFLAGS=  # library
FFLAGS=  # option
DFLAGS=  # debug
LINT=    # 8-byte integer

#--------------------------------------------------
# Site selection -- config/sites/<SITE>.mk, chosen by config/site.mk
#--------------------------------------------------
-include config/site.mk

ifeq ($(DEBUG_MODE),on)
  #DFLAGS+=-DTwoBodyRelativeChannelDebug
  #DFLAGS+=-DTwoBodyRelativeSpaceDebug
  #DFLAGS+=-DTwoBodyRelativeSpaceSpinMeshBasisDebug
  DFLAGS+=-DThreeBodyJacobiSpaceDebug
  #DFLAGS+=-DNNForceDebug
  DFLAGS+=-DNNNForceHODebug
  #DFLAGS+=-DDebugNNNForceLocal
  #DFLAGS+=-DNNNFFromFileDebug
  #DFLAGS+=-DThreeBodyTransCoefDebug
  #DFLAGS+=-DThreeBodyTransCoefIsoMonDebug
  DFLAGS+=-DABodyJacobiSpaceDebug
endif


#--------------------------------------------------
# Source Files
#--------------------------------------------------

SRCDIR = src
SRCDIR_LinAlg = submodules/LinAlgf90/src
SRCDIR_spline = submodules/NdSpline/src
SRCDIR_AtHamil = submodules/AtHamil/src
SRCDIR_1Body = src/OneBody
SRCDIR_2Body = src/TwoBody
SRCDIR_3Body = src/ThreeBody
SRCDIR_ABody = src/ABody
SRCDIR_chengdu = src/TwoBody/chengdu
DEPDIR = .
OBJDIR = obj

SRCS=
OBJS=
MODS=

SRCC:=$(wildcard $(SRCDIR)/*.c)
SRCF77:=$(wildcard $(SRCDIR)/*.f)
SRCF90:=$(wildcard $(SRCDIR)/*.f90)
SRCF95:=$(wildcard $(SRCDIR)/*.F90)
OBJC:=$(addprefix $(OBJDIR)/, $(patsubst %c, %o, $(notdir $(SRCC))))
OBJF77:=$(addprefix $(OBJDIR)/, $(patsubst %f, %o, $(notdir $(SRCF77))))
OBJF90:=$(addprefix $(OBJDIR)/, $(patsubst %f90, %o, $(notdir $(SRCF90))))
OBJF95:=$(addprefix $(OBJDIR)/, $(patsubst %F90, %o, $(notdir $(SRCF95))))
SRCS= $(SRCC) $(SRCF77) $(SRCF90) $(SRCF95)
OBJS= $(OBJC) $(OBJF77) $(OBJF90) $(OBJF95)

SRCC_LinAlg:=$(wildcard $(SRCDIR_LinAlg)/*.c)
SRCF77_LinAlg:=$(wildcard $(SRCDIR_LinAlg)/*.f)
SRCF90_LinAlg:=$(wildcard $(SRCDIR_LinAlg)/*.f90)
SRCF95_LinAlg:=$(wildcard $(SRCDIR_LinAlg)/*.F90)
OBJC_LinAlg:=$(addprefix $(OBJDIR)/, $(patsubst %c, %o, $(notdir $(SRCC_LinAlg))))
OBJF77_LinAlg:=$(addprefix $(OBJDIR)/, $(patsubst %f, %o, $(notdir $(SRCF77_LinAlg))))
OBJF90_LinAlg:=$(addprefix $(OBJDIR)/, $(patsubst %f90, %o, $(notdir $(SRCF90_LinAlg))))
OBJF95_LinAlg:=$(addprefix $(OBJDIR)/, $(patsubst %F90, %o, $(notdir $(SRCF95_LinAlg))))
SRCS_LinAlg= $(SRCC_LinAlg) $(SRCF77_LinAlg) $(SRCF90_LinAlg) $(SRCF95_LinAlg)
OBJS_LinAlg= $(OBJC_LinAlg) $(OBJF77_LinAlg) $(OBJF90_LinAlg) $(OBJF95_LinAlg)

SRCF95_spline:=$(wildcard $(SRCDIR_spline)/*.F90)
OBJF95_spline:=$(addprefix $(OBJDIR)/, $(patsubst %F90, %o, $(notdir $(SRCF95_spline))))
SRCS_spline=  $(SRCF95_spline)
OBJS_spline=  $(OBJF95_spline)

SRCF90_AtHamil:=$(wildcard $(SRCDIR_AtHamil)/*.f90)
SRCF95_AtHamil:=$(wildcard $(SRCDIR_AtHamil)/*.F90)
OBJF90_AtHamil:=$(addprefix $(OBJDIR)/, $(patsubst %f90, %o, $(notdir $(SRCF90_AtHamil))))
OBJF95_AtHamil:=$(addprefix $(OBJDIR)/, $(patsubst %F90, %o, $(notdir $(SRCF95_AtHamil))))
SRCS_AtHamil= $(SRCF90_AtHamil) $(SRCF95_AtHamil)
OBJS_AtHamil= $(OBJF90_AtHamil) $(OBJF95_AtHamil)

SRCF95_1Body:=$(wildcard $(SRCDIR_1Body)/*.F90)
OBJF95_1Body:=$(addprefix $(OBJDIR)/, $(patsubst %F90, %o, $(notdir $(SRCF95_1Body))))
SRCS_1Body= $(SRCF95_1Body)
OBJS_1Body= $(OBJF95_1Body)

SRCC_2Body:=$(wildcard $(SRCDIR_2Body)/*.c)
SRCF77_2Body:=$(wildcard $(SRCDIR_2Body)/*.f)
SRCF90_2Body:=$(wildcard $(SRCDIR_2Body)/*.f90)
SRCF95_2Body:=$(wildcard $(SRCDIR_2Body)/*.F90)
OBJC_2Body:=$(addprefix $(OBJDIR)/, $(patsubst %c, %o, $(notdir $(SRCC_2Body))))
OBJF77_2Body:=$(addprefix $(OBJDIR)/, $(patsubst %f, %o, $(notdir $(SRCF77_2Body))))
OBJF90_2Body:=$(addprefix $(OBJDIR)/, $(patsubst %f90, %o, $(notdir $(SRCF90_2Body))))
OBJF95_2Body:=$(addprefix $(OBJDIR)/, $(patsubst %F90, %o, $(notdir $(SRCF95_2Body))))
SRCS_2Body= $(SRCC_2Body) $(SRCF77_2Body) $(SRCF90_2Body) $(SRCF95_2Body)
OBJS_2Body= $(OBJC_2Body) $(OBJF77_2Body) $(OBJF90_2Body) $(OBJF95_2Body)

SRCC_3Body:=$(wildcard $(SRCDIR_3Body)/*.c)
SRCF77_3Body:=$(wildcard $(SRCDIR_3Body)/*.f)
SRCF90_3Body:=$(wildcard $(SRCDIR_3Body)/*.f90)
SRCF95_3Body:=$(wildcard $(SRCDIR_3Body)/*.F90)
OBJC_3Body:=$(addprefix $(OBJDIR)/, $(patsubst %c, %o, $(notdir $(SRCC_3Body))))
OBJF77_3Body:=$(addprefix $(OBJDIR)/, $(patsubst %f, %o, $(notdir $(SRCF77_3Body))))
OBJF90_3Body:=$(addprefix $(OBJDIR)/, $(patsubst %f90, %o, $(notdir $(SRCF90_3Body))))
OBJF95_3Body:=$(addprefix $(OBJDIR)/, $(patsubst %F90, %o, $(notdir $(SRCF95_3Body))))
SRCS_3Body= $(SRCC_3Body) $(SRCF77_3Body) $(SRCF90_3Body) $(SRCF95_3Body)
OBJS_3Body= $(OBJC_3Body) $(OBJF77_3Body) $(OBJF90_3Body) $(OBJF95_3Body)

SRCC_ABody:=$(wildcard $(SRCDIR_ABody)/*.c)
SRCF77_ABody:=$(wildcard $(SRCDIR_ABody)/*.f)
SRCF90_ABody:=$(wildcard $(SRCDIR_ABody)/*.f90)
SRCF95_ABody:=$(wildcard $(SRCDIR_ABody)/*.F90)
OBJC_ABody:=$(addprefix $(OBJDIR)/, $(patsubst %c, %o, $(notdir $(SRCC_ABody))))
OBJF77_ABody:=$(addprefix $(OBJDIR)/, $(patsubst %f, %o, $(notdir $(SRCF77_ABody))))
OBJF90_ABody:=$(addprefix $(OBJDIR)/, $(patsubst %f90, %o, $(notdir $(SRCF90_ABody))))
OBJF95_ABody:=$(addprefix $(OBJDIR)/, $(patsubst %F90, %o, $(notdir $(SRCF95_ABody))))
SRCS_ABody= $(SRCC_ABody) $(SRCF77_ABody) $(SRCF90_ABody) $(SRCF95_ABody)
OBJS_ABody= $(OBJC_ABody) $(OBJF77_ABody) $(OBJF90_ABody) $(OBJF95_ABody)

SRCF90_chengdu:=$(wildcard $(SRCDIR_chengdu)/*.f90)
OBJF90_chengdu:=$(addprefix $(OBJDIR)/, $(patsubst %f90, %o, $(notdir $(SRCF90_chengdu))))
SRCS_chengdu= $(SRCF90_chengdu)
OBJS_chengdu= $(OBJF90_chengdu)


SRCS_ALL = $(SRCS) $(SRCS_LinAlg) $(SRCS_spline) $(SRCS_AtHamil) $(SRCS_1Body) $(SRCS_2Body) $(SRCS_3Body) $(SRCS_ABody) $(SRCS_chengdu)
OBJS_ALL = $(OBJS) $(OBJS_LinAlg) $(OBJS_spline) $(OBJS_AtHamil) $(OBJS_1Body) $(OBJS_2Body) $(OBJS_3Body) $(OBJS_ABody) $(OBJS_chengdu)
SRCS_DEP = $(filter-out src/dvode_f90_m.f90, $(SRCS_ALL))

MODOUT=
$(info $(findstring mpif90,$(FC)))
ifeq ($(findstring gfortran,$(FC)),gfortran)
  MODOUT=-J$(MODDIR)
endif

ifeq ($(findstring mpif90,$(FC)),mpif90)
  MODOUT=-J$(MODDIR)
endif

ifeq ($(findstring ifort,$(FC)),ifort)
  MODOUT=-module $(MODDIR)
endif

ifeq ($(findstring mpiifort,$(FC)),mpiifort)
  MODOUT=-module $(MODDIR)
endif

ifeq ($(findstring mpifort,$(FC)),mpifort)
  MODOUT=-J$(MODDIR)
endif


#--------------------------------------------------
# Rules
#--------------------------------------------------
all: dirs $(TARGET)
$(TARGET): $(OBJS_ALL)
	$(FC) $(FFLAGS) $(DFLAGS) -o $(TARGET).exe $^ $(LFLAGS)
	mv $(TARGET).exe $(EXEDIR)
	@printf "\n#####################################################################################\n"
	@printf "To complete the installation, please do 'make install'.\n"
	@printf "#####################################################################################\n"


$(OBJDIR)/dvode_f90_m.o:$(SRCDIR)/dvode_f90_m.f90
	$(FC) $(FFLAGS) $(LINT) $(MODOUT) -o $@ -c $(SRCDIR)/dvode_f90_m.f90

$(OBJDIR)/Renormalization.o:$(SRCDIR)/Renormalization.F90
	$(FC) $(FFLAGS) $(LINT) $(MODOUT)  -o $@ -c $(SRCDIR)/Renormalization.F90

$(OBJDIR)/NNNFFromFile.o:$(SRCDIR_3Body)/NNNFFromFile.F90
	$(FC) $(FFLAGS) $(LFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $(SRCDIR_3Body)/NNNFFromFile.F90

$(OBJDIR)/chiral-twobody-potentials.o:$(SRCDIR_2Body)/chiral-twobody-potentials.f90
	$(FC) $(FCHIRAL) $(FLINES) $(DFLAGS) $(MODOUT)  -o $@ -c $(SRCDIR_2Body)/chiral-twobody-potentials.f90


$(OBJDIR)/%.o:$(SRCDIR)/%.c
	$(CC) $(CFLAGS)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR)/%.f
	$(FC) $(FFLAGS) $(MODOUT)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR)/%.f90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR)/%.F90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<

$(OBJDIR)/%.o:$(SRCDIR_LinAlg)/%.c
	$(CC) $(CFLAGS)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_LinAlg)/%.f
	$(FC) $(FFLAGS) $(MODOUT)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_LinAlg)/%.f90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_LinAlg)/%.F90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<

$(OBJDIR)/%.o:$(SRCDIR_spline)/%.F90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<

$(OBJDIR)/%.o:$(SRCDIR_AtHamil)/%.f90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_AtHamil)/%.F90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<

$(OBJDIR)/%.o:$(SRCDIR_1Body)/%.F90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<

$(OBJDIR)/%.o:$(SRCDIR_2Body)/%.c
	$(CC) $(CFLAGS)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_2Body)/%.f
	$(FC) $(FFLAGS) $(MODOUT)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_2Body)/%.f90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_2Body)/%.F90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<

$(OBJDIR)/%.o:$(SRCDIR_3Body)/%.c
	$(CC) $(CFLAGS)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_3Body)/%.f
	$(FC) $(FFLAGS) $(MODOUT)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_3Body)/%.f90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_3Body)/%.F90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<

$(OBJDIR)/%.o:$(SRCDIR_ABody)/%.c
	$(CC) $(CFLAGS)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_ABody)/%.f
	$(FC) $(FFLAGS) $(MODOUT)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_ABody)/%.f90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<
$(OBJDIR)/%.o:$(SRCDIR_ABody)/%.F90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT)  -o $@ -c $<

$(OBJDIR)/%.o:$(SRCDIR_chengdu)/%.f90
	$(FC) $(FFLAGS) $(DFLAGS) $(MODOUT) $(FLINES) -o $@ -c $<

dep:
	$(FDEP) $(SRCS_DEP) -b $(OBJDIR)/ > $(DEPDIR)/makefile.d

dirs:
	if test -d $(OBJDIR); then \
		: ; \
	else \
		mkdir $(OBJDIR); \
	fi
	if test -d $(MODDIR); then \
		: ; \
	else \
		mkdir $(MODDIR); \
	fi
	if test -d $(EXEDIR); then \
		: ; \
	else \
		mkdir -p $(EXEDIR); \
	fi
	if test -d $(INSTLDIR); then \
		: ; \
	else \
		mkdir -p $(INSTLDIR); \
	fi

install:
	ln -sf $(EXEDIR)/$(TARGET).exe $(INSTLDIR)
	@printf "\n####################################################################\n"
	@printf " To finish the installation, please hit the following command: \n\n"
	@printf "echo 'export PATH=$$PATH:$(INSTLDIR)' >> $(HOME)/.bashrc \n"
	@printf "source $(HOME)/.bashrc \n"

clean:
	rm -rf obj
	rm -rf mod
	if [ -f $(EXEDIR)/$(TARGET).exe ]; then \
	  rm -f $(EXEDIR)/$(TARGET).exe; \
	fi

#--------------------------------------------------
-include $(wildcard $(DEPDIR)/*.d)
obj/dvode_f90_m.o : src/dvode_f90_m.f90
obj/Renormalization.o : src/Renormalization.F90 obj/dvode_f90_m.o obj/Profiler.o obj/LinAlgLib.o
