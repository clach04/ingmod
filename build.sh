#!/bin/sh

# Build script to build ingmod (available from 
#  http://www.informatik.uni-rostock.de/~hme/software/ ).

# II_SYSTEM must be set and in path as per usual Ingres user

# Hacky build script written to target rpm's used in plone/Zope project
# Under RedHat (easily modified to handle other targets).

# Internal Plone project is using RedHat AS 3.0 so we make some assumptions
# relating to that:
#
# If using Plone RPM:
# We make the assumption that the python that Zope is using
# is in the Zope directory structure (i.e. not external)
# Assume that the Zope Home dir is the Python home dir
# This is NOT the case with, say, the SUSE rpm's for Zope

# Possible assumption we _could_ make, not sure if it is useful though
# We could assume that the Zope products dir is in the Zope home dir, e.g.
# Assume the current dir when running this script is:
# 	$ZOPE_HOME/lib/python/Products/ZIngresDA/ingmod
#
# I.e. python home is ${PWD}/../../../../..
# Could use nested "dirname" instead of ..

# Code below is for AS 3.0 Zope 2.70 3rd party rpm's (for rh9)

# zope_PYTHONHOME=/disk3/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86
#zope_PYTHONHOME=${PWD}/../../../../..
zope_PYTHONHOME=/usr
export zope_PYTHONHOME

#zope_PYTHON_VER=python2.1
#zope_PYTHON_VER=`basename ${zope_PYTHONHOME}/lib/python?*`
zope_PYTHON_VER=python2.2
# for plone 2 which uses python 2.3.3
zope_PYTHON_VER=python2.3
export zope_PYTHON_VER

zope_PYTHON_EXE=python2.2
# for plone 2 which uses python 2.3.3
zope_PYTHON_EXE=python2.3
export zope_PYTHON_EXE

#CC=gcc
#export CC

echo zope_PYTHONHOME $zope_PYTHONHOME
echo zope_PYTHON_VER $zope_PYTHON_VER
echo zope_PYTHON_EXE $zope_PYTHON_EXE


# Ensure we pre-compile the esql/c file
rm ingmod.c

make

