#--------------------------------------------------
# Site selection
#
#   make SITE=icc           explicit; a command-line SITE wins over everything
#   NUHAMIL_SITE=icc make   from the environment
#   (unset)                 fall back to the hostname detection in the Makefile
#
# A "site" is just a fragment file, config/sites/<SITE>.mk.  Adding a machine
# means adding one file here instead of editing the Makefile.  Sites with no
# fragment (including "other") get the generic gfortran defaults built into
# the Makefile.
#--------------------------------------------------
ifeq ($(origin SITE),undefined)
  SITE := $(if $(NUHAMIL_SITE),$(NUHAMIL_SITE),$(HOST))
endif

ifeq ($(SITE),other)
  # no fragment; the Makefile's built-in generic defaults apply
else ifeq ($(wildcard config/sites/$(SITE).mk),)
  $(warning No config/sites/$(SITE).mk for SITE=$(SITE); using built-in defaults)
else
  include config/sites/$(SITE).mk
endif

$(info SITE $(SITE))
