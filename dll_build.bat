REM # Build script to build ingmod (available from
REM #  http://www.informatik.uni-rostock.de/~hme/software/ ).
REM # Needs MS VC++ version 6 minimum (or what ever was used to build python


REM We need VC++ version 6
set VCSETUP="E:\Program Files\Microsoft Visual Studio\VC98\Bin\VCVARS32.BAT"
REM using VC++5 with python 2.1 library causes a link failure
REM set VCSETUP="C:\Program Files\DevStudio\VC\bin\VCVARS32.BAT"
if "%VCVARSSET%" == "" call %VCSETUP%
set VCVARSSET=true



set SRCFILE=ingmod

REM You need a Python SDK for the version of Python you are using
REM
REM set my_PYTHON_HOME_DIR=C:\Python22
set my_PYTHON_VER=Python21
REM set my_PYTHON_VER=Python23
set my_PYTHON_HOME_DIR=E:\programs\%my_PYTHON_VER%

REM comment/uncomment as required
set ingmodDEBUG_FLAGS=-DINGMOD_DEBUG
set ingmodDEBUG_FLAGS=

REM probably should put this in an "nmake" file

del %SRCFILE%.c
esqlc -multi -p -prototypes %SRCFILE%.ec

REM Compile and link settings taken from python cookbook and the /MD was 
REM required due to the way dependent libraries where built
cl -DWIN32 %ingmodDEBUG_FLAGS% -I %II_SYSTEM%\ingres\files -I %my_PYTHON_HOME_DIR%\include /LD /MD %SRCFILE%.c %my_PYTHON_HOME_DIR%\libs\%my_PYTHON_VER%.lib %II_SYSTEM%\ingres\lib\ingres.lib

del ingmod.c ingmod.obj ingmod.exp ingmod.lib

