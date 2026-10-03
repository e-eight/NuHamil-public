#--------------------------------------------------
# Site selection
#
#   make SITE=icc           explicit; a command-line SITE wins over everything
#   NUHAMIL_SITE=icc make   from the environment
#   (unset)                 fall back to config/detect-site.sh (hostname table)
#
# A "site" is a fragment file, config/sites/<SITE>.mk.  Adding a machine means
# adding one file here rather than editing the Makefile.  An unknown SITE warns
# and falls back to the generic config/sites/other.mk instead of failing
# silently or building with the wrong toolchain.
#--------------------------------------------------
ifeq ($(origin SITE),undefined)
  SITE := $(if $(NUHAMIL_SITE),$(NUHAMIL_SITE),$(shell sh config/detect-site.sh))
endif

ifeq ($(wildcard config/sites/$(SITE).mk),)
  $(warning No config/sites/$(SITE).mk for SITE=$(SITE); using config/sites/other.mk)
  SITE := other
endif

include config/sites/$(SITE).mk

$(info SITE $(SITE))
