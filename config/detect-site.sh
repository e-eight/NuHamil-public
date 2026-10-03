#!/bin/sh
# Map this host to a site name, i.e. config/sites/<name>.mk.
#
# This is the ONLY hostname-specific logic left in the build.  Extend the table
# when adding a machine, or bypass it entirely with `make SITE=<name>` or
# NUHAMIL_SITE=<name>.
h=$(hostname)
case "$h" in
  apt1*)     echo apt ;;
  oak*)      echo oak ;;
  cedar*)    echo cedar ;;
  strongint*) echo strongint ;;
  juwels*)   echo juwels ;;
  ccc*)      echo icc ;;
  *)         echo other ;;
esac
