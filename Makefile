#II_SYSTEM = $(II_SYSTEM)
PYTHONHOME = $(zope_PYTHONHOME)

# PYTHON_VER = python2.1
PYTHON_VER = $(zope_PYTHON_VER)

PYTHON = $(zope_PYTHON_EXE)
ESQL = $(II_SYSTEM)/ingres/bin/esqlc
ESQLLIBS = -lingres
#ESQLFLAGS = -multi -p -wsql=entry_SQL92 -prototypes	# Ingres II
ESQLFLAGS = -multi -p -wsql=open -prototypes	# Ingres II
#ESQLFLAGS = -p -wopen	# Ingres 6.4, OpenIngres 1.2

INGMOD_DEBUG_FLAGS = -DINGMOD_DEBUG
INGMOD_DEBUG_FLAGS =
WARN = #-Wall
WARN = -v
CFLAGS = $(WARN) -O -I $(PYTHONHOME)/include/$(PYTHON_VER) $(INGMOD_DEBUG_FLAGS)
LIBS = $(ESQLLIBS) -lnsl -lm
LDFLAGS = -L$(II_SYSTEM)/ingres/lib

LDSO = $(CC) -shared # on linux
#LDSO = $(CC) -G -B dynamic # on solaris
#LDSO = $(CC) -G -B dynamic

DIST = Copyright Makefile README Extensions ChangeLog ingmod.ec ingtest.py switchexec
DISTFILE = ingmod.tar


all:	ingmod.so
	$(PYTHON) ingtest.py


dist:
	tar cvf $(DISTFILE) $(DIST)
	gzip -v9 $(DISTFILE)

# new rule set for ESQL/C
.SUFFIXES:	.ec .so

.ec.c:
	$(ESQL) $(ESQLFLAGS) $<

.ec.o:
	$(ESQL) $(ESQLFLAGS) $<
	$(CC) $(CFLAGS) $*.c
	-rm -f $*.c

.c.so:
	$(LDSO) $(CFLAGS) $(LDFLAGS) $< $(LIBS) -o $*.so

#.o.so:
#	$(LDSO) $(LDFLAGS) $< $(LIBS) -o $*.so

.ec:
	$(ESQL) $(ESQLFLAGS) $<
	$(CC) $(CFLAGS) $(LDFLAGS) -o $* $*.c $(ESQLLIBS) $(LIBS)
	-rm -f $*.c
