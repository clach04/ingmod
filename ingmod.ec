/*
** Copyright (c) 2000,2001,2003 by Holger Meyer, hm@ieee.org
**  
** By obtaining, using, and/or copying this software and/or its associated
** documentation, you agree that you have read, understood, and will
** comply with the following terms and conditions:
** 
** Permission to use, copy, modify, and distribute this software and its
** associated documentation for any purpose and without fee is hereby
** granted, provided that the above copyright notice appears in all
** copies, and that both that copyright notice and this permission notice
** appear in supporting documentation, and that the name of the author not
** be used in advertising or publicity pertaining to distribution of the
** software without specific, written prior permission.
** 
** THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
** INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS.  IN NO
** EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, INDIRECT OR
** CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
** USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
** OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
** PERFORMANCE OF THIS SOFTWARE.
*/
/*
** CHANGES:
**	See separate ChangeLog details.
**
** TODO:
**	-- DATA HANDLERS
**	   -- handlers should set aproppriate values in module dict
**	   -- multiple handlers per fetch
**	-- TABLE_KEY (CHAR(8)), OBJECT_KEY (CHAR(16))
**	-- SET AUTOCOMMIT, ...
**	-- SET_SQL(DBEVENTDISPLAY = ...)
**	-- SET_SQL(SAVEQUERY = 1), INQUIRE_SQL(:query = QUERYTEXT)
**	-- REPEATED SELECT * ...
**	-- DECLARE CURSOR FOR DEFERRED | DIRECT UPDATE OF
**		use parameter by name
**	-- date/time constraining
**	-- cursor.__call__
*/

#include	<stdio.h>
#include	<stdlib.h>
#include	<ctype.h>
#include	"Python.h"

EXEC SQL INCLUDE SQLCA;
EXEC SQL INCLUDE SQLDA;

#ifdef WIN32
void _declspec(dllexport) initingmod(void);
/* example py dec from cookbook
PyObject _declspec(dllexport) *NiGetSpamData(void) */
#endif /* WIN32 */

/*
** configurations
*/
#ifdef INGMOD_DEBUG
#undef INGMOD_DEBUG
#define	INGMOD_DEBUG		1	/**/
#define cmc_debug_cursorlog()	fprintf (stderr, "\nwin32onlyCMC CHECK_OPEN failed, state = %d, line:%d\n\n", (self)->state, __LINE__)
#else
#define	INGMOD_DEBUG		0	/**/
#define cmc_debug_cursorlog()	
#endif
#define	TRUNCATE_CHAR		1	/**/
#define	CLOSE_ON_NOT_FOUND	1	/**/

#define	NONE(str)			(str ? str : "<NULL>")
#define	STR(obj)			(PyString_AsString(PyObject_Str(obj)))
#if !defined(TRUE)
# define	TRUE				(1==1)
# define	FALSE			!TRUE
#endif
#if !defined(BUFSIZ)
# define	BUFSIZ			(4*512)
#endif
#if !defined(MIN)
# define	MIN(x,y)			((x)<(y)?(x):(y))
#endif

#define	MAXSTRSIZE		BUFSIZ
#define	CHUNKSIZE			BUFSIZ

#define	SQLCODE_NOT_FOUND	100

#define	CHECK_SQLCODE(stmnt, ret)	\
	if (sqlca.sqlcode < 0) {  \
		PyErr_SetString(ingmod_OperationalError, error_string(stmnt));  \
		conn_release_session(); 	\
		return(ret);  \
	}

#if !defined(IISQ_HDLR_TYPE)
# define	INGRES_64
#endif

typedef enum {
	II_DTE = IISQ_DTE_TYPE,		/* Date - Output */
	II_MNY = IISQ_MNY_TYPE,		/* Money - Output */
	II_DEC = IISQ_DEC_TYPE,		/* Decimal - Output */
	II_CHA = IISQ_CHA_TYPE,		/* Char - Input, Output */
	II_VCH = IISQ_VCH_TYPE,		/* Varchar - Input, Output */
#if !defined(INGRES_64)
	II_LBIT = IISQ_LBIT_TYPE,	/* Long Bit  - Input, Output */
	II_LVCH = IISQ_LVCH_TYPE,	/* Long Varchar - Output */
	II_BYTE = IISQ_BYTE_TYPE,	/* Byte - Input, Output */
	II_VBYTE = IISQ_VBYTE_TYPE,	/* Byte Varying - Input, Output */
	II_LBYTE = IISQ_LBYTE_TYPE,	/* Long Byte - Output */
	II_HDLR = IISQ_HDLR_TYPE,	/* IISQLHDLR type - Datahandler*/
	II_OBJ = IISQ_OBJ_TYPE,		/* 4GL object - Output */
#endif
	II_INT = IISQ_INT_TYPE,		/* Integer - Input, Output */
	II_FLT = IISQ_FLT_TYPE,		/* Float - Input, Output */
	II_CHR = IISQ_CHR_TYPE,		/* C - Not seen */
	II_TXT = IISQ_TXT_TYPE,		/* Text - Not seen */
	II_TBL = IISQ_TBL_TYPE,		/* Table field - Output */
	II_IGNORE = -1	/* this is nonsense, except for some stupid
				** compilers mapping enum otherwise to unsigned!
				*/
} ingtype;

#define	II_DTE_LEN	IISQ_DTE_LEN	/* Date length */                         

static PyObject *ingmod_module = NULL;
static PyObject *ingmod_dict = NULL;
static PyObject *ingmod_version = NULL;
static PyObject *ingmod_apilevel = NULL;
static PyObject *ingmod_paramstyle = NULL;
static PyObject *ingmod_threadsafety = NULL;
static int ingmod_num_session = 0;
static int ingmod_verbose = 0;
#if INGMOD_DEBUG
static int ingmod_debug = 0;
#else
# define ingmod_debug	0
#endif
static PyObject *ingmod_STRING;
static PyObject *ingmod_NUMBER;
static PyObject *ingmod_ROWID;

/* exceptions */
static PyObject *ingmod_Warning = NULL;
static PyObject *ingmod_Error = NULL;
static PyObject	*ingmod_InterfaceError = NULL;
static PyObject	*ingmod_DatabaseError = NULL;
static PyObject		*ingmod_DataError = NULL;
static PyObject		*ingmod_OperationalError = NULL;
static PyObject		*ingmod_IntegrityError = NULL;
static PyObject		*ingmod_InternalError = NULL;
static PyObject		*ingmod_ProgrammingError = NULL;
static PyObject		*ingmod_NotSupportedError = NULL;
EXEC SQL BEGIN DECLARE SECTION;
static char ingmod_error_type[MAXSTRSIZE] = { '\0' };
static char ingmod_error_text[MAXSTRSIZE] = { '\0' };
static int  ingmod_error_num = 0;
static char ingmod_event_name[MAXSTRSIZE] = { '\0' };
static char ingmod_event_text[MAXSTRSIZE] = { '\0' };
static char ingmod_message_text[MAXSTRSIZE] = { '\0' };
static char ingmod_warning_text[MAXSTRSIZE] = { '\0' };
EXEC SQL END DECLARE SECTION;

static void conn_release_session(void);
static int conn_setsid(int);


/* eliminate trailing blanks and newlines */
static
char *
clear_trail(char *str)
{
	char *s = str + strlen(str);
	while (str <= --s) {
		if (*s != ' ' && *s != '\n') {
			*++s = '\0';
			break;
		}
	}
	return(str);
}

/* count character within string */
/*TODO: don't count character in character literals */
static
int
count_chr(const char *str, char c)
{
	int cnt = 0;

	while (*str) {
		if (*str++ == c) {
			++cnt;
		}
	}
	return(cnt);
}


/*
** SQL Exception handling
*/

static
const char *
error_string(const char *str)
{
	static char buf[MAXSTRSIZE] = { '\0' };

	EXEC SQL INQUIRE_SQL(:ingmod_error_type = ERRORTYPE);
	EXEC SQL INQUIRE_SQL(:ingmod_error_text = ERRORTEXT);
	EXEC SQL INQUIRE_SQL(:ingmod_error_num = ERRORNO);
        #ifdef WIN32
	sprintf(buf, "ingmod.error[%s]:%s:%d:%s",
			str, ingmod_error_type, ingmod_error_num,
			clear_trail(ingmod_error_text));
        #else
	snprintf(buf, (size_t)MAXSTRSIZE, "ingmod.error[%s]:%s:%d:%s",
			str, ingmod_error_type, ingmod_error_num,
			clear_trail(ingmod_error_text));
        #endif /* WIN32 */
	return(buf);
}

static
int
error_handler()
{
	EXEC SQL INQUIRE_SQL(:ingmod_error_type = ERRORTYPE);
	EXEC SQL INQUIRE_SQL(:ingmod_error_text = ERRORTEXT);
	EXEC SQL INQUIRE_SQL(:ingmod_error_num = ERRORNO);
	if (ingmod_debug || ingmod_verbose) {
		fprintf(stderr, "ingmod.error:%s:%d:%s\n",
				ingmod_error_type, ingmod_error_num,
				clear_trail(ingmod_error_text));
	}
	return(sqlca.sqlcode);
}

static
int
warning_handler()
{
	EXEC SQL INQUIRE_SQL(:ingmod_warning_text = ERRORTEXT);
	if (ingmod_debug || ingmod_verbose) {
		fprintf(stderr, "ingmod.warning: %s\n",
				clear_trail(ingmod_warning_text));
	}
	return(sqlca.sqlcode);
}

static
int
message_handler()
{
	EXEC SQL INQUIRE_SQL(:ingmod_message_text = MESSAGETEXT);

	if (ingmod_debug || ingmod_verbose) {
		fprintf(stderr, "ingmod.message: %s\n",
				clear_trail(ingmod_message_text));
	}
	return(sqlca.sqlcode);
}

static
int
dbevent_handler()
{
	EXEC SQL INQUIRE_SQL(:ingmod_event_name = DBEVENTNAME,
			:ingmod_event_text = DBEVENTTEXT);
	if (ingmod_debug || ingmod_verbose) {
		fprintf(stderr, "ingmod.dbevent: event ='%s' text = '%s'\n",
				clear_trail(ingmod_event_name),
				clear_trail(ingmod_event_text));
	}
	return(sqlca.sqlcode);
}

EXEC SQL WHENEVER SQLWARNING CALL warning_handler;

static
PyObject *
notimplemented(PyObject *obj, PyObject *args)
{
	PyErr_SetString(ingmod_NotSupportedError, "not implemented yet");
	return(NULL);
}


/*
** Generic DB data types
*/
typedef struct {
	PyObject_HEAD
	PyObject	*real_obj;
} generic_obj;

static PyMethodDef generic_methods[] = {
	{ NULL,		NULL,			0,			NULL },
};

static
PyObject *
generic_value(generic_obj *obj)
{
	Py_INCREF(obj->real_obj);
	return(obj->real_obj);
}

static
PyObject *
generic_new(PyObject *pyobj, PyTypeObject *type)
{
	generic_obj *obj = NULL;

	if ((obj = PyObject_NEW(generic_obj, type))) {
		obj->real_obj = pyobj;
		Py_INCREF(pyobj);
	}
	return((PyObject *)obj);
}

static
void
generic_dealloc(generic_obj *self)
{
	Py_DECREF(self->real_obj);
	PyMem_DEL(self);
}

static
PyObject *
generic_getattr(generic_obj *self, char *name)
{
	if (ingmod_debug) {
		fprintf(stderr, "generic[%p].getattr('%s')\n", self, name);
	}
	if (!self || !name) {
		return(NULL);
	}
	if (strcmp(name, "value") == 0) {
		return(generic_value(self));
	}
	return(Py_FindMethod(generic_methods, (PyObject *)self, name));
}

static
int
generic_print(generic_obj *self, FILE *fp, int flags)
{
	fprintf(fp, "<ingres generic value('%s') at %p>",
			self->real_obj ? STR(self->real_obj) : "None", self);
	return(0);
}


/*
** DATETIME type
*/
static PyTypeObject date_type = {
	PyObject_HEAD_INIT(NULL)   /* see http://www.python.org/doc/2.1.3/ext/dnt-basics.html and also initingmod() function */
	0,						/*ob_size*/
	"Ingres date/time",			/*tp_name*/
	sizeof(generic_obj),		/*tp_basicsize*/
	0,						/*tp_itemsize*/
	/* methods */
	(destructor)generic_dealloc,	/*tp_dealloc*/
	(printfunc)generic_print,	/*tp_print*/
	(getattrfunc)generic_getattr,	/*tp_getattr*/
	(setattrfunc)0,			/*tp_setattr*/
	(cmpfunc)0,				/*tp_compare*/
	(reprfunc)0,				/*tp_repr*/
	0,						/* tp_as_number*/
	0,						/* tp_as_sequence*/
	0,						/* tp_as_mapping*/
	(hashfunc)0,				/*tp_hash*/
	(ternaryfunc)0,			/*tp_call*/
	(reprfunc)0,				/*tp_str*/

	/* Space for future expansion */
	0L,0L,0L,0L,
	"Ingres date/time object"		/* Documentation string */
};

static
PyObject *
date_new(PyObject *args)
{
	return(generic_new(args, &date_type));
}

static
int
date_check(PyObject * obj)
{
	return((PyTypeObject *)PyObject_Type(obj) == &date_type);
}

static char ingmod_timestamp__doc__[] =
		"usage: ingmod.timestamp(year, month, day, hour, minute, second)";
static
PyObject *
ingmod_timestamp(PyObject *self, PyObject *args)
{
	int year, month, day, hour, minute, second;
	char str[MAXSTRSIZE];
	PyObject *strobj;

	year = month = hour = minute = -1;
	day = 1;
	second = 0;
	if (!PyArg_ParseTuple(args, "|iiiiii", &year, &month, &day, &hour, &minute, &second)) {
		PyErr_SetString(ingmod_InterfaceError, ingmod_timestamp__doc__);
		return(NULL);
	}
	if (ingmod_debug) {
		fprintf(stderr, "ingmod.Timestamp(%d, %d, %d, %d, %d, %d)\n",
			year, month, day, hour, minute, second);
	}
	if (year == -1 && month == -1) { 
		strcpy(str, "today");
	}
	else if (hour == -1 && minute == -1) { 
		strcpy(str, "now");
	}
	else {
		/* with '/' ingres assumes always mm/dd and not dd/mm */
		#ifdef WIN32
		sprintf(str, "%02d/%02d/%04d %02d:%02d:%02d",
				month, day, year, hour, minute, second);
		#else
		snprintf(str, MAXSTRSIZE, "%02d/%02d/%04d %02d:%02d:%02d",
				month, day, year, hour, minute, second);
		#endif /* WIN32 */
	}
	if ((strobj = PyString_FromString(str))) {
		return(date_new(strobj));
	}
	PyErr_SetString(ingmod_InternalError, "couldn't build date/time string");
	return(NULL);
}


/*
** BINARY type
*/
static PyTypeObject binary_type = {
	PyObject_HEAD_INIT(NULL)   /* see http://www.python.org/doc/2.1.3/ext/dnt-basics.html and also initingmod() function */
	0,						/*ob_size*/
	"Ingres binary",			/*tp_name*/
	sizeof(generic_obj),		/*tp_basicsize*/
	0,						/*tp_itemsize*/
	/* methods */
	(destructor)generic_dealloc,	/*tp_dealloc*/
	(printfunc)generic_print,	/*tp_print*/
	(getattrfunc)generic_getattr,	/*tp_getattr*/
	(setattrfunc)0,			/*tp_setattr*/
	(cmpfunc)0,				/*tp_compare*/
	(reprfunc)0,				/*tp_repr*/
	0,						/* tp_as_number*/
	0,						/* tp_as_sequence*/
	0,						/* tp_as_mapping*/
	(hashfunc)0,				/*tp_hash*/
	(ternaryfunc)0,			/*tp_call*/
	(reprfunc)0,				/*tp_str*/

	/* Space for future expansion */
	0L,0L,0L,0L,
	"Ingres binary object"		/* Documentation string */
};

static
PyObject *
binary_new(PyObject *args)
{
	return(generic_new(args, &binary_type));
}

static
int
binary_check(PyObject *obj)
{
	return((PyTypeObject *)PyObject_Type(obj) == &binary_type);
}

static char ingmod_binary__doc__[] =
		"usage: ingmod.Binary(string)";
static
PyObject *
ingmod_binary(PyObject *self, PyObject *args)
{
	char *str = NULL;
	int len = 0;
	PyObject *strobj;

	if (!PyArg_ParseTuple(args, "s#", &str, &len)) {
		PyErr_SetString(ingmod_InterfaceError, ingmod_binary__doc__);
		return(NULL);
	}
	if (ingmod_debug) {
		fprintf(stderr, "ingmod.Binary%s\n", STR(args));
	}
	if ((strobj = PyString_FromStringAndSize(str, len))) {
		return(binary_new(strobj));
	}
	PyErr_SetString(PyExc_TypeError, "parameter is not a string");
	return(NULL);
}


/*
** DATA HANDLER type/methods
*/
#if defined(INGRES_64)
# define	handler_obj	void
#else

typedef struct {
	PyObject_HEAD
	PyObject	*callable;
	PyObject	*status;
	IISQLHDLR	put_handler;
	long		putsize;
	IISQLHDLR	get_handler;
	long		getsize;
} handler_obj;

static
void
handler_dealloc(handler_obj *self)
{
	if (!self) {
		return;
	}
	if (self->callable) {
		Py_DECREF(self->callable);
	}
	if (self->status) {
		Py_DECREF(self->status);
	}
	PyMem_DEL(self);
}

static
int
handler_print(handler_obj *self, FILE *fp, int flags)
{
	fprintf(fp, "<ingres handler callable(%s) at %p>",
			self->callable ? STR(self->callable) : "None", self);
	return(0);
}

static char handler_get__doc__[] =
		"usage: handler.get()";
static
int
handler_get(handler_obj *self)
{
	EXEC SQL BEGIN DECLARE SECTION;
		char chunk[CHUNKSIZE+1];
		int maxlength = CHUNKSIZE;
		int length;
		int dataend = 0;
	EXEC SQL END DECLARE SECTION;

	if (ingmod_debug) {
		fprintf(stderr, "handler.get(%p)\n", self);
	}
	while (dataend == 0) {
		PyObject *ret;

		/*__*/
		EXEC SQL GET DATA (
			:chunk = segment,
			:length = segmentlength,
			:dataend = dataend
		) with maxlength = :maxlength;
		CHECK_SQLCODE("GET DATA", 0);

		if (ingmod_debug) {
			fprintf(stderr, "handler.get: length = %d, dataend = %d\n",
					length, dataend);
		}
		/* call method supplied */
		if (!(ret = PyObject_CallMethod(self->callable,
				"get", "s#i", chunk, length, dataend))) {
			PyErr_SetString(ingmod_InterfaceError, "handler.get: method call failed");
			return(0);
		}
		self->getsize += length;
	}
	/*__*/
	EXEC SQL ENDDATA;
	CHECK_SQLCODE("ENDDATA", 0);
	return(0);
}

static char handler_put__doc__[] =
		"usage: handler.put()";
static
int
handler_put(handler_obj *self)
{
	EXEC SQL BEGIN DECLARE SECTION;
		char chunk[CHUNKSIZE+1];
		int length;
		int dataend = 0;
	EXEC SQL END DECLARE SECTION;

	if (ingmod_debug) {
		fprintf(stderr, "handler.put(%p)\n", self);
	}
	while (dataend == 0) {
		PyObject *str;

		/* call method  for object `callable' */
		if (!(str = PyObject_CallMethod(self->callable, "put", "i", CHUNKSIZE))) {
			PyErr_SetString(ingmod_InterfaceError, "handler.put: method call failed");
			return(0);
		}
		if (str == Py_None) {
			break;
		}
		if (!PyString_Check(str)) {
			PyErr_SetString(ingmod_InterfaceError,
					"handler.put: method did not return a string");
			return(0);
		}
		length = PyString_Size(str);
		if (ingmod_debug) {
			fprintf(stderr, "handler.put: str='%s', length=%d\n", STR(str), length);
		}
		if (length < CHUNKSIZE) {
			dataend = 1;
		}
		else if (length > CHUNKSIZE) {
			PyErr_SetString(ingmod_InterfaceError,
					"handler.put: length exceeds chunk size");
			return(0);
		}
		if (length > 0) {
			memcpy(chunk, PyString_AsString(str), length);
			/*__*/
			EXEC SQL PUT DATA (
				SEGMENTLENGTH = :length,
				SEGMENT = :chunk
			);
			CHECK_SQLCODE("PUT DATA", 0);
		}
		self->putsize += length;
	}
	/*__*/
	EXEC SQL PUT DATA (dataend = 1);
	CHECK_SQLCODE("PUT DATA", 0);
	return(0);
}

static PyMethodDef handler_methods[] = {
	{ "get",	(PyCFunction)handler_get,	METH_VARARGS, handler_get__doc__ },
	{ "put",	(PyCFunction)handler_put,	METH_VARARGS, handler_put__doc__ },
	{ NULL,		NULL,			0,			NULL },
};

static
PyObject *
handler_getattr(handler_obj *self, char *name)
{
	if (ingmod_debug) {
		fprintf(stderr, "handler[%p].getattr('%s')\n", self, name);
	}
	if (strcmp(name, "callable") == 0) {
		if (self->callable) {
			Py_INCREF(self->callable);
			return(self->callable);
		}
		Py_INCREF(Py_None);
		return(Py_None);
	}
	else if (strcmp(name, "status") == 0) {
		if (self->status) {
			Py_INCREF(self->status);
			return(self->status);
		}
		Py_INCREF(Py_None);
		return(Py_None);
	}
	else if (strcmp(name, "getsize") == 0) {
		return(PyInt_FromLong(self->getsize));
	}
	else if (strcmp(name, "putsize") == 0) {
		return(PyInt_FromLong(self->putsize));
	}
	else if (strcmp(name, "data") == 0) {
		return(PyObject_CallMethod(self->callable, "data", ""));
	}
	return(Py_FindMethod(handler_methods, (PyObject *)self, name));
}

static
PyTypeObject
handler_type = {
	PyObject_HEAD_INIT(NULL)   /* see http://www.python.org/doc/2.1.3/ext/dnt-basics.html and also initingmod() function */
	0,						/*ob_size*/
	"Ingres data handler",		/*tp_name*/
	sizeof(handler_obj),		/*tp_basicsize*/
	0,						/*tp_itemsize*/
	/* methods */
	(destructor)handler_dealloc,	/*tp_dealloc*/
	(printfunc)handler_print,	/*tp_print*/
	(getattrfunc)handler_getattr,	/*tp_getattr*/
	(setattrfunc)0,			/*tp_setattr*/
	(cmpfunc)0,				/*tp_compare*/
	(reprfunc)0,				/*tp_repr*/
	0,						/* tp_as_number*/
	0,						/* tp_as_sequence*/
	0,						/* tp_as_mapping*/
	(hashfunc)0,				/*tp_hash*/
	(ternaryfunc)0,			/*tp_call*/
	(reprfunc)0,				/*tp_str*/

	/* Space for future expansion */
	0L,0L,0L,0L,
	"Ingres data handler object"	/* Documentation string */
};

static
int
handler_check(PyObject *obj)
{
	return((PyTypeObject *)PyObject_Type(obj) == &handler_type);
}

static
handler_obj *
handler_new(PyObject *callable)
{
	handler_obj *handler;

	if ((handler = PyObject_NEW(handler_obj, &handler_type))) {
		handler->callable = callable;
		if (callable) {
			Py_INCREF(callable);
		}
		handler->status = NULL;
		handler->put_handler.sqlarg = (char *)handler;
		handler->put_handler.sqlhdlr = handler_put;
		handler->putsize = 0L;
		handler->get_handler.sqlarg = (char *)handler;
		handler->get_handler.sqlhdlr = handler_get;
		handler->getsize = 0L;
	}
	return(handler);
}

static char ingmod_datahandler__doc__[] =
		"usage: ingmod.Datahandler(callable_object = None)";
static
PyObject *
ingmod_datahandler(PyObject *self, PyObject *args)
{
	PyObject *callable = NULL;

	if (!PyArg_ParseTuple(args, "O", &callable)) {
		PyErr_SetString(ingmod_InterfaceError, ingmod_datahandler__doc__);
		return(NULL);
	}
	if (ingmod_debug) {
		fprintf(stderr, "ingmod.Datahandler%s\n", STR(args));
	}
	return((PyObject *)handler_new(callable));
}
#endif


/*
** SQLVAR methods
*/

static
void
sqlvar_clear(IISQLVAR *v)
{
	if (ingmod_debug) {
		fprintf(stderr, "sqlvar.clear(%p)\n", v);
	}
#if !defined(INGRES_64)
	if (v->sqldata && v->sqltype != II_HDLR && v->sqltype != -II_HDLR) {
		free(v->sqldata);
		v->sqldata = NULL;
	}
#endif
	if (v->sqlind) {
		free(v->sqlind);
		v->sqlind = NULL;
	}
}

static
PyTypeObject *
sqlvar_pytype(IISQLVAR *v)
{
	ingtype itype = v->sqltype;

	if (itype < 0) {
		itype = -itype;
	}
	switch (itype) {
	case II_INT:		/* Integer - Input, Output */
		return(&PyInt_Type);	

	case II_FLT:		/* Float - Input, Output */
	case II_MNY:		/* Money - Output */
	case II_DEC:		/* Decimal - Output */
		return(&PyFloat_Type);	

	case II_CHA:		/* Char - Input, Output */
	case II_VCH:		/* Varchar - Input, Output */
	case II_CHR:		/* C - Not seen */
	case II_TXT:		/* Text - Not seen */
		return(&PyString_Type);	

#if !defined(INGRES_64)
	case II_HDLR:		/* IISQLHDLR type - Datahandler*/
	case II_LVCH:		/* Long Varchar - Output */
	case II_LBYTE:		/* Long Byte - Output */
		return(&handler_type);	
#endif

	case II_DTE:		/* Date - Output */
		return(&date_type);	

#if !defined(INGRES_64)
	case II_LBIT:		/* Long Bit  - Input, Output */
	case II_BYTE:		/* Byte - Input, Output */
	case II_VBYTE:		/* Byte Varying - Input, Output */
		return(&binary_type);	
#endif

	case II_TBL:		/* Table field - Output */
		/*TODO*/
		break;
	}
	PyErr_SetString(ingmod_InternalError, "illegal ingres type returned");
	return(NULL);
}

static
IISQLVAR *
sqlvar_alloc(IISQLVAR *v, const char *name, ingtype type, int len, char *value)
{
	int alloc_len, nullable;
	ingtype new_type;

	if (ingmod_debug) {
		fprintf(stderr, "sqlvar.init(%p, '%s', %d, %d, %p)\n",
				v, NONE(name), type, len, value);
	}
	/* free previous allocated memory */
	sqlvar_clear(v);

	/* nullable indicator */
	nullable = 0;
	v->sqlind = NULL;
	v->sqllen = len;
	new_type = v->sqltype = type;
	if (new_type < 0) {
		new_type = -new_type;
		nullable = 1;
		if (!(v->sqlind = (short *)calloc(1, sizeof(short)))) {
			Py_FatalError("sqlvar.init: out of memory");
			return(NULL);
		}
	}

	switch (new_type) {

	case II_INT:
		alloc_len = v->sqllen = sizeof(long);
		break;

	case II_DEC:
		/* as for now use float until we know how decimal is returned */

	case II_MNY: /* use float 8 (double) */
		v->sqltype = nullable ? -II_FLT : II_FLT;

	case II_FLT:
		alloc_len = v->sqllen = sizeof(double);
		break;

	case II_DTE:
		v->sqltype = nullable ? -II_CHA : II_CHA;
		v->sqllen = II_DTE_LEN;

	case II_CHA:
		alloc_len = v->sqllen + 1; /* for '\0' */
		break;

#if !defined(INGRES_64)
	case II_LVCH:
	case II_LBYTE:
		v->sqltype = II_HDLR;

	case II_HDLR:
		alloc_len = v->sqllen = 0;
		v->sqldata = value;
		break;

	case II_BYTE:
	case II_LBIT:
		alloc_len = v->sqllen;
		break;

	case II_VBYTE:
#endif
	case II_VCH:
		alloc_len = sizeof(short) + v->sqllen; /* for the (short) length variable */
		break;

	default:
		fprintf(stderr, "sqlvar.init: unsupported type %d\n", new_type);
		alloc_len = sizeof(double) + v->sqllen; /* for safety */
		break;
	}
	if (alloc_len  && !(v->sqldata = (char *)calloc(1, alloc_len))) {
		Py_FatalError("sqlda.init: out of memory");
		return(NULL);
	}

	if (name) { 
		v->sqlname.sqlnamel = MIN(strlen(name),sizeof(v->sqlname.sqlnamec));
		strncpy(v->sqlname.sqlnamec, name, v->sqlname.sqlnamel);
	}

	if (value && v->sqllen) {
#if defined(INGRES_64)
		if (new_type == II_VCH) {
#else
		if (new_type == II_VCH || new_type == II_VBYTE) {
#endif
			(void)memcpy(v->sqldata + sizeof(short), value, v->sqllen);
			*(short *)v->sqldata = v->sqllen;
		}
		else {
			(void)memcpy(v->sqldata, value, v->sqllen);
		}
	}

	if (ingmod_verbose) {
		fprintf(stderr, "sqlvar.init: name='%s', type=%d(%d), len=%d, allocated=%d, value=%p\n",
				v->sqlname.sqlnamel ? v->sqlname.sqlnamec : "",
				v->sqltype, type, v->sqllen, alloc_len, value);
	}
	return(v);
}

static
PyObject *
sqlvar_2pyobject(IISQLVAR *v, handler_obj *handler /*= NULL*/)
{
	short len;
	char *data;
	int type;

	if (v == NULL) {
		return(NULL);
	}

	type = v->sqltype;
	if (type < 0) {
		if (*(v->sqlind) < 0) {
			/* set None */
			Py_INCREF(Py_None);
			return(Py_None);
		}
		type = -type;
	}

	/* fetch field */
	switch (type) {

	case II_INT:
		return(PyInt_FromLong(*((long *)v->sqldata)));

	case II_DEC: /*TODO:I'm not shure how it is returned*/
	case II_FLT:
	case II_MNY:
		return(PyFloat_FromDouble(*((double *)v->sqldata)));

	case II_CHA:
#if TRUNCATE_CHAR
		clear_trail(v->sqldata);
#endif
		return(PyString_FromStringAndSize((char *)v->sqldata, MIN(v->sqllen, strlen(v->sqldata))));

#if !defined(INGRES_64)
	case II_LVCH: /* if exceeding 64k len set to 0 */
	case II_LBYTE: /* if exceeding 64k len set to 0 */
	case II_HDLR: /* use datahandler */
		/* work already done: calls to get-data handler */
		if (handler) {
			Py_INCREF(handler);
		}
		Py_INCREF(Py_None);
		return(Py_None);
#endif

	case II_VCH:
	case II_VBYTE:
		len = *((short *)v->sqldata);
		data = (char *)v->sqldata + sizeof(short);
		return(PyString_FromStringAndSize(data, len));

#if !defined(INGRES_64)
	case II_BYTE:
		return(PyString_FromStringAndSize((char *)v->sqldata, v->sqllen));
#endif

	default:
		fprintf(stderr, "sqlvar.2pyobject: unsupported type %d\n", type);
		return(NULL);
	}
}

/* print first DUMPLEN bytes of data area */
#define	DUMPLEN	20
static
char *
data_dump(const char *str)
{
	static char buf[4*DUMPLEN+1];
	char *cp;
	int i;

	for (i = 0, cp = buf; i < DUMPLEN; ++i, ++str) {
		if (isprint(*str)) {
			*cp++ = *str;
		}
		else {
			sprintf(cp, "\\%03o", *str);
			cp += 4;
		}
	}
	sprintf(cp, "...");
	return(buf);
}

static
void
sqlvar_print(IISQLVAR *v, FILE *fp)
{
	if (!v || !fp) { /* for safety */
		return;
	}
	fprintf(fp, " <ingres sqlvar name='%.*s', type=%d, len=%d, data=%p, ind=%p, null=%d,\n",
		v->sqlname.sqlnamel, v->sqlname.sqlnamec,
		v->sqltype, v->sqllen, v->sqldata,
		v->sqlind, v->sqlind ? *(v->sqlind) : 0);
	fprintf(fp, "  *data='%s'>\n", data_dump(v->sqldata));
}


/*
** SQLDA methods
*/

static
IISQLDA *
sqlda_alloc()
{
	IISQLDA *sqlda;

	/* allocate IISQLDA structure */
	if (!(sqlda = (IISQLDA *)calloc(1, sizeof(IISQLDA)))) {
		Py_FatalError("sqlda.alloc: out of memory");
		return(NULL);
	}
	sqlda->sqln = IISQ_MAX_COLS;
	sqlda->sqld = 0;
	return(sqlda);
}

static
void
sqlda_free(IISQLDA **sqldap)
{
	IISQLDA *sqlda = *sqldap;
	IISQLVAR *v = NULL;

	if (ingmod_debug) {
		fprintf(stderr, "sqlda.free(%p)\n", sqlda);
	}
	if (!sqlda) { /* for safety */
		return;
	}

	for (v = sqlda->sqlvar; v < &sqlda->sqlvar[sqlda->sqld]; ++v) {
		/* free previous allocated memory */
		sqlvar_clear(v);
	}
	sqlda->sqld = sqlda->sqln = 0;
	*sqldap = NULL;
}


/* allocate space for output binding */
static
IISQLDA *
sqlda_output_bind(IISQLDA *sqlda, handler_obj *handler /*= NULL*/)
{
	IISQLVAR *v = NULL;

	if (ingmod_debug) {
		fprintf(stderr, "sqlda.output_bind(%p)\n", sqlda);
	}
	if (!sqlda) {
		return(NULL);
	}

	if (ingmod_debug) {
		fprintf(stderr, "sqlda.output_bind: %d fields\n", sqlda->sqld);
	}
	for (v = sqlda->sqlvar; v < &sqlda->sqlvar[sqlda->sqld]; ++v) {
		char *value;

		switch (v->sqltype) {
#if !defined(INGRES_64)
		case II_HDLR:
		case II_LVCH:
		case II_LBYTE:
		case -II_HDLR:
		case -II_LVCH:
		case -II_LBYTE:
			if (!handler) {
				PyErr_SetString(ingmod_InterfaceError,
						"sqlda.output_bind: no output handler registered");
				return(NULL);
			}
			value = (char *)&handler->get_handler;
			break;
#endif

		default:
			value = NULL;
			break;
		}
		if (sqlvar_alloc(v, NULL, v->sqltype, v->sqllen, value) == NULL) {
			return(NULL);
		}
	}
	return(sqlda);
}

/* build a new sqlda from parameter sequence given */
static
IISQLDA *
sqlda_input_bind(IISQLDA *sqlda, PyObject *sequence, int expected, PyObject *names)
{
	IISQLVAR *v = NULL;
	PyObject *elem = NULL;
	PyObject *nelem = NULL;
	const char *name = NULL;
	int num;

	if (ingmod_debug) {
		fprintf(stderr, "sqlda.input_bind(%p, %s, %d, %s)\n",
				sqlda, STR(sequence), expected, STR(names));
	}
	if (!sqlda && !(sqlda = sqlda_alloc())) {
		return(NULL);
	}

	if (sequence && !PySequence_Check(sequence)) {
		PyErr_SetString(PyExc_TypeError, "parameter not a sequence");
		return(NULL);
	}

	if (names && !PySequence_Check(names)) {
		PyErr_SetString(PyExc_TypeError, "names not a sequence");
		return(NULL);
	}

	if (!sequence) { /* null paramters */
		sqlda->sqld = 0;
		return(sqlda);
	}
	for (num = 0, v = sqlda->sqlvar; v < &sqlda->sqlvar[IISQ_MAX_COLS]; ++num, ++v) {
		ingtype type;
		void *data;
		int len;
		long l;
		double d;

		/*
		 * 2003/07/06 - Richard Béneyt: Added PyErr_Clear().
		 */
		if (!(elem = PySequence_GetItem(sequence, num))) {
			PyErr_Clear();
			break;
		}
		if (names) {
			/*
			 * 2003/07/06 - Richard Béneyt: Added PyErr_Clear().
			 */
			if (!(nelem = PySequence_GetItem(names, num))) {
				PyErr_Clear();
				break;
			}
			if (!PyString_Check(nelem)) {
				PyErr_SetString(PyExc_TypeError, "parameter name not a string");
				break;
			}
			name = PyString_AsString(nelem);
		}
		else {
			name = NULL;
		}
		if (PyInt_Check(elem)) {
			l = PyInt_AsLong(elem);
			data = &l;
			type = II_INT;
			len = sizeof(long);
		}
		else if (PyLong_Check(elem)) {
			l = PyLong_AsLong(elem);
			data = &l;
			type = II_INT;
			len = sizeof(long);
		}
		else if (PyFloat_Check(elem)) {
			d = PyFloat_AsDouble(elem);
			data = &d;
			type = II_FLT;
			len = sizeof(d);
		}
		else if (PyString_Check(elem)) {
			data = PyString_AsString(elem);
			type = II_VCH;
			len = PyString_Size(elem);
		}
		else if (date_check(elem)) {
			generic_obj *obj = (generic_obj *)elem;
			data = PyString_AsString(obj->real_obj);
			type = II_DTE;
			len = PyString_Size(obj->real_obj);
		}
#if !defined(INGRES_64)
		else if (binary_check(elem)) {
			generic_obj *obj = (generic_obj *)elem;
			data = PyString_AsString(obj->real_obj);
			type = II_VBYTE;
			len = PyString_Size(obj->real_obj);
		}
		else if (handler_check(elem)) {
			handler_obj *obj = (handler_obj *)elem;
			data = (char *)&obj->put_handler;
			type = II_HDLR;
			len = 0;
		}
#endif
		else {
			PyErr_SetString(ingmod_InternalError,
					"sqlda.input_bind: unknown python parameter type");
			goto errorexit;
		}
		if (sqlvar_alloc(v, name, type, len, data) == NULL) {
			goto errorexit;
		}
		if (elem) {
			Py_DECREF(elem);
		}
		if (nelem) {
			Py_DECREF(nelem);
		}
	}
	if (v == &sqlda->sqlvar[IISQ_MAX_COLS]) {
		PyErr_SetString(ingmod_InternalError,
				"sqlda.input_bind: to many parameters");
		goto errorexit;
	}
	if (expected && num != expected) {
		PyErr_SetString(ingmod_InterfaceError,
				"sqlda.input_bind: illegal parameter count");
		goto errorexit;
	}
	sqlda->sqld = num;
	return(sqlda);

errorexit:
	if (elem) {
		Py_DECREF(elem);
	}
	if (nelem) {
		Py_DECREF(nelem);
	}
	sqlda_free(&sqlda);
	return(NULL);
}

static
void
sqlda_print(IISQLDA *sqlda, FILE *fp)
{
	IISQLVAR *v = NULL;

	if (!sqlda || !fp) { /* for safety */
		return;
	}
	fprintf(fp, "<ingres sqlda at %p: sqln=%d, sqld=%d\n",
			sqlda, sqlda->sqln, sqlda->sqld);
	for (v = sqlda->sqlvar; v < &sqlda->sqlvar[sqlda->sqld]; ++v) {
		sqlvar_print(v, fp);
	}
	fprintf(fp, ">\n");
}

/* build a tuble object from SQLDA */
static
PyObject *
sqlda_2pyobject(IISQLDA *this, handler_obj *handler /*= NULL*/)
{
	PyObject *tuple;
	IISQLVAR *v;
	int i;

	if (!this) {
		return(NULL);
	}

	if (!(tuple = PyTuple_New(this->sqld))) {
		PyErr_SetString(ingmod_InternalError,
				"sqlda.2pyobject: build tuple failed");
		return(NULL);
	}
	for (i = 0, v = this->sqlvar; i < this->sqld; ++i, ++v) {
		PyObject *field = sqlvar_2pyobject(v, handler);

		if (field == NULL) {
			Py_DECREF(tuple);
			PyErr_SetString(ingmod_InternalError,
					"sqlda.2pyobject: build value failed");
			return(NULL);
		}
		PyTuple_SetItem(tuple, i, field);
	}
	return(tuple);
}

/* build description sequence from SQLDA structure */
static
PyObject *
sqlda_description(IISQLDA *sqlda)
{
	/*
	**  Before calling this function, ensure that 
	**       conn_setsid(self->sid)
	**  has been called.
	*/

	IISQLVAR *v;
	PyObject *list = NULL;
	PyObject *tuple = NULL;
	int i;

	if (ingmod_debug) {
		fprintf(stderr, "sqlda.description(%p)\n", sqlda);
	}

	list = PyList_New(0);

	/*
	** this is no longer a saftey check
	** return empty lists for null sqlda
	** so that non select statements
	** set the description to an empty list
	*/
	if (!sqlda) { /* for safety */
		return(list);
	}

	for (i = 0, v = sqlda->sqlvar; i < sqlda->sqld; ++i, ++v) {
		PyObject *name, *type_code, *len, *nullable, *prec, *scale;

		tuple = PyTuple_New(7);
		/* name */
		name = PyString_FromStringAndSize(
				(char *)v->sqlname.sqlnamec, v->sqlname.sqlnamel);
		if (name == NULL)
			goto errexit;
		PyTuple_SetItem(tuple, 0, name);
		if (ingmod_debug) {
			fprintf(stderr, "... name = '%.*s'\n", v->sqlname.sqlnamel, v->sqlname.sqlnamec);
		}
		/* nullable */
		nullable = PyInt_FromLong(v->sqltype < 0 ? 1L : 0L);
		if (nullable == NULL)
			goto errexit;
		PyTuple_SetItem(tuple, 6, nullable);
		/* type_code */
		type_code = (PyObject *)sqlvar_pytype(v);
		if (type_code == NULL)
			goto errexit;
		PyTuple_SetItem(tuple, 1, type_code);
		/* TODO:diplay_size should be taken vfrom short for VCH, VBYTE ...*/
		Py_INCREF(Py_None);
		PyTuple_SetItem(tuple, 2, Py_None);
		/* internal_size */
		len = PyInt_FromLong((long)v->sqllen);
		if (len == NULL)
			goto errexit;
		PyTuple_SetItem(tuple, 3, len);
		/* precision & scale */
		if (v->sqltype == II_DEC || v->sqltype == -II_DEC) {
			prec = PyInt_FromLong((long)IISQL_PRCSN(v->sqllen));
			scale = PyInt_FromLong((long)IISQL_SCALE(v->sqllen));
		}
		else {
			Py_INCREF(Py_None);
			prec = Py_None;
			Py_INCREF(Py_None);
			scale = Py_None;
		}
		PyTuple_SetItem(tuple, 4, prec);
		PyTuple_SetItem(tuple, 5, scale);
		/* finished */
		PyList_Append(list, tuple);
	}
	return(list);

errexit:
	Py_DECREF(tuple);
	Py_DECREF(list);
	PyErr_SetString(ingmod_InternalError,
			"sqlda.description: ingres returns bad value");
	return(NULL);
}


/*
** Declarations for objects of type INGRES DB Cursor
*/
typedef enum { CLOSED = 0, PREPARED = 1, FETCHED = 2 } cursstate;
typedef enum { FOR_READONLY = 0, DEFERRED = 1, FOR_UPDATE = 2 } curstype;

typedef struct {
	PyObject_HEAD
	PyObject		*conn;
	curstype		type;
	cursstate		state;
	char			*cname;
	char			*sname;
	char			*query;
	int			sid;
	int			prefetchrows;
	int			arraysize;
	IISQLDA		*in;
	IISQLDA		*out;
	PyObject		*descr;
	handler_obj	*handler;
} curs_obj;

staticforward PyTypeObject curs_type;

#define	CHECK_OPEN(self)										\
	if ((self)->state <= CLOSED) {								\
		PyErr_SetString(ingmod_OperationalError, "cursor not open");	\
cmc_debug_cursorlog();\
		return(NULL);											\
	}

static int curs_realclose(curs_obj *self);

static
int
curs_print(curs_obj *self, FILE *fp, int flags)
{
	if (self->query && self->state >= PREPARED) {
		fprintf(fp, "<ingres cursor '%s' for %s'%s'['%s'] at %p>",
			self->cname, self->type == FOR_READONLY ? "readonly " : "",
			self->sname, self->query, self);
	}
	else {
		fprintf(fp, "<ingres cursor at %p>", self);
	}
	return(0);
}

static
curs_obj *
curs_new(int sid)
{
	curs_obj *n;
	char buf[128];

	if ((n = PyObject_NEW(curs_obj, &curs_type))) {
		n->sid = sid;
		n->query = NULL;
		sprintf(buf, "C_%p", n);
		n->cname = strdup(buf);
		sprintf(buf, "S_%p", n);
		n->sname = strdup(buf);
		n->type = FOR_READONLY;
		n->state = CLOSED;
		n->prefetchrows = n->arraysize = 0;
		n->descr = NULL;
		n->in = NULL;
		n->out = NULL;
		n->handler = NULL;
	}
	if (ingmod_debug) {
		fprintf(stderr, "cursor.new() = %p\n", n);
	}
	return(n);
}

static
void
curs_delete(curs_obj *self)
{
	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].delete()\n", self);
	}
	if (self->cname) {
		free(self->cname);
	}
	if (self->sname) {
		free(self->sname);
	}
	if (self->query) {
		free(self->query);
	}
	if (self->in) {
		sqlda_free(&self->in);
	}
	if (self->out) {
		sqlda_free(&self->out);
	}
	if (self->descr) {
		Py_DECREF(self->descr);
	}
#if !defined(INGRES_64)
	if (self->handler) {
		Py_DECREF(self->handler);
	}
#endif
	PyMem_DEL(self);
}

static
void
curs_dealloc(curs_obj *self)
{
	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].dealloc()\n", self);
	}
	conn_setsid(self->sid);
	curs_realclose(self);
	curs_delete(self);
	conn_release_session();
}

static char curs_callproc__doc__[] =
		"usage: sequence = cursor.callproc(procname, paramdict = None)";
static
PyObject *
curs_callproc(curs_obj *self, PyObject *args)
{
	EXEC SQL BEGIN DECLARE SECTION;
		long ret;
		char *procname;
	EXEC SQL END DECLARE SECTION;
	PyObject *dict = NULL;

	if (!PyArg_ParseTuple(args, "s|O", &procname, &dict)) {
		PyErr_SetString(ingmod_InterfaceError, curs_callproc__doc__);
		return(NULL);
	}

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].callproc%s\n", self, STR(args));
	}

	conn_setsid(self->sid);
	if (self->state >= PREPARED) {
		/* if cursor already open, may be there are some unfetched tuples */
		curs_realclose(self);
	}

	/* bind input parameters */
	if (self->in) {
		sqlda_free(&self->in);
	}
	if (dict) {
		PyObject *param = NULL;

		if (!PyDict_Check(dict)) {
			PyErr_SetString(PyExc_TypeError, "parameter not a dictionary");
			conn_release_session();
			return(NULL);
		}
		if ((param = PyDict_Values(dict))) {
			PyObject *names = PyDict_Keys(dict);

			if (!(self->in = sqlda_input_bind(self->in, param, 0, names))) {
				conn_release_session();
				return(NULL);
			}
		}
		else {
			PyErr_SetString(ingmod_InterfaceError,
					"cursor.callproc: empty parameter dictionary");
			conn_release_session();
			return(NULL);
		}
	}

	if (self->in) {
#if defined(INGRES_64)
# define	SQLDA	self->in
		EXEC SQL EXECUTE PROCEDURE :procname
				USING DESCRIPTOR :SQLDA INTO :ret;
# undef	SQLDA
#else
		/*__*/
		EXEC SQL EXECUTE PROCEDURE :procname
				USING DESCRIPTOR :self->in INTO :ret;
#endif
		sqlda_free(&self->in);
	}
	else {
		EXEC SQL EXECUTE PROCEDURE :procname INTO :ret;
	}
	CHECK_SQLCODE("EXECUTE PROCEDURE", NULL);

	conn_release_session();
	/* should return a modified copy of the input sequence */
	/*
	return(sqlda_2pyobject(self->in, self->handler));
	*/
	return(PyInt_FromLong((long)ret));
}

static char curs_execute__doc__[] =
		"usage: cursor.execute(operation, parameters = None)";
static
PyObject *
curs_execute(curs_obj *self, PyObject *args)
{
	EXEC SQL BEGIN DECLARE SECTION;
		char *query;
		char *cname;
		char *sname;
		int prefetchrows;
	EXEC SQL END DECLARE SECTION;
	PyObject *param = NULL;
	int reuse = FALSE;

	if (!PyArg_ParseTuple(args, "s|O", &query, &param)) {
		PyErr_SetString(ingmod_InterfaceError, curs_execute__doc__);
		return(NULL);
	}

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].execute%s: %s\n",
				self, STR(args), STR(param));
	}

	conn_setsid(self->sid);

	if (self->state >= PREPARED) {
		/* if cursor already open, may be there are some unfetched tuples */
		curs_realclose(self);
	}

	/* Try to reuse a prepared statement */
	if (self->query && strcmp(self->query, query) == 0 && self->state >= PREPARED) {
		reuse = TRUE;
		fprintf(stderr, "reuse prepared statement\n");
	}
	else {
		reuse = FALSE;
		if (self->query) {
			free(self->query);
		}
		self->query = strdup(query);
	}

	cname = self->cname;
	sname = self->sname;

	/* bind input parameters */
	if (self->in) {
		sqlda_free(&self->in);
	}
	if (param) {
		int nparam = count_chr(query, '?');
		if (!(self->in = sqlda_alloc())) {
			PyErr_SetString(ingmod_OperationalError,
					"cursor.execute: could not alloc input binding");
			conn_release_session();
			return(NULL);
		}
		if (!(self->in = sqlda_input_bind(self->in, param, nparam, NULL))) {
			conn_release_session();
			return(NULL);
		}
	}

	/* prepare query */
	EXEC SQL PREPARE :sname FROM :query;
	CHECK_SQLCODE("PREPARE", NULL);

	if (!self->out && !(self->out = sqlda_alloc())) {
		PyErr_SetString(ingmod_OperationalError,
				"cursor.execute: could not alloc output binding");
		conn_release_session();
		return(NULL);
	}
#if defined(INGRES_64)
# define	SQLDA	self->out
	EXEC SQL DESCRIBE :sname INTO :SQLDA;
# undef	SQLDA
#else
	/*__*/
	EXEC SQL DESCRIBE :sname INTO :self->out;
#endif
	CHECK_SQLCODE("DESCRIBE", NULL);

	if (self->out->sqld > self->out->sqln) {
		PyErr_SetString(ingmod_OperationalError,
				"cursor.execute: too many rows");
		conn_release_session();
		return(NULL);
	}

	/* check if it wasn't a select statement,
	** then, just execute the statement and
	** return error code
	*/
	if (self->out->sqld == 0) {
		if (self->in) {
#if defined(INGRES_64)
# define	SQLDA	self->in
			EXEC SQL EXECUTE :sname USING DESCRIPTOR :SQLDA;
# undef	SQLDA
#else
			/*__*/
			EXEC SQL EXECUTE :sname USING DESCRIPTOR :self->in;
#endif
			sqlda_free(&self->in);
		}
		else {
			EXEC SQL EXECUTE :sname;
		}
		CHECK_SQLCODE("EXECUTE", NULL);
		/* clach04: set description to be an empty list */
		self->descr = sqlda_description(NULL);
		conn_release_session();
		Py_INCREF(Py_None);
		return(Py_None);
	}

	/* TODO: may be optimized, same as with sqlda */
	if (self->descr) {
		self->state = CLOSED;
		Py_DECREF(self->descr);
		self->descr = NULL;
	}
	self->descr = sqlda_description(self->out);

	/* prepare the fields */
	if (ingmod_debug) {
		fprintf(stderr, "cursor.execute: %d fields.\n", self->out->sqld);
	}
	/* bind output parameters */
	if (!sqlda_output_bind(self->out, self->handler)) {
		sqlda_free(&self->out);
		conn_release_session();
		return(NULL);
	}

	/* declare cursor */
	EXEC SQL DECLARE :cname CURSOR FOR :sname;
	CHECK_SQLCODE("DECLARE", NULL);

	prefetchrows = self->prefetchrows;
	EXEC SQL SET_SQL(PREFETCHROWS = :prefetchrows);
	CHECK_SQLCODE("SET_SQL", NULL);
	EXEC SQL INQUIRE_SQL(:prefetchrows = PREFETCHROWS);
	CHECK_SQLCODE("INQUIRE_SQL", NULL);
	self->arraysize = prefetchrows;
	if (self->in) {
		if (self->type == FOR_READONLY) {
#if defined(INGRES_64)
# define	SQLDA	self->in
			EXEC SQL OPEN :cname FOR READONLY USING DESCRIPTOR :SQLDA;
		}
		else {
			EXEC SQL OPEN :cname USING DESCRIPTOR :SQLDA;
# undef	SQLDA
#else
			/*__*/
			EXEC SQL OPEN :cname FOR READONLY USING DESCRIPTOR :self->in;
		}
		else {
			/*__*/
			EXEC SQL OPEN :cname USING DESCRIPTOR :self->in;
#endif
		}
		sqlda_free(&self->in);
	}
	else {
		if (self->type == FOR_READONLY) {
			EXEC SQL OPEN :cname FOR READONLY;
		}
		else {
			EXEC SQL OPEN :cname;
		}
	}
	CHECK_SQLCODE("OPEN", NULL);
	self->state = PREPARED;
	Py_INCREF(Py_None);
	conn_release_session();
	return(Py_None);
}

static char curs_executemany__doc__[] =
		"usage: cursor.executemany(operation, sequence)";
static
PyObject *
curs_executemany(curs_obj *self, PyObject *args)
{
	const char *query;
	PyObject *seq;

	if (!PyArg_ParseTuple(args, "sO", &query, &seq)) {
		PyErr_SetString(ingmod_InterfaceError, curs_executemany__doc__);
		return(NULL);
	}

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].executemany%s\n", self, STR(args));
	}

	CHECK_OPEN(self);

	/* Execute the same statement several times.
	** This methods assumes, that optimisation is
	** done by the subsequently called method
	*/
	if (PySequence_Check(seq)) {
		int cnt = PyObject_Length(seq);
		int i;

		/*TODO*/
		PyErr_SetString(ingmod_NotSupportedError, "not implemented yet");
		return(NULL);

#if defined(NOT_IMPLEMENTED_YET)
		for (i = 0; i < cnt; ++i) {
			if (!(curs_execute(self, PySequence_GetItem(seq, i)))) {
				return(NULL);
			}
		}
		/*TODO*/
#endif
	}
	PyErr_SetString(PyExc_TypeError, "not a sequence");
	return(NULL);
}

static
int
curs_realclose(curs_obj *self)
{
	/*
	**  Before calling this function, ensure that 
	**       conn_setsid(self->sid)
	**  has been called.
	*/
	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].realclose()\n", self);
	}
	if (self->state >= PREPARED) {
		EXEC SQL BEGIN DECLARE SECTION;
			char *cname;
		EXEC SQL END DECLARE SECTION;
		cname = self->cname;
		EXEC SQL CLOSE :cname;
		self->state = CLOSED;
	}
	else {
		if (ingmod_debug) {
			fprintf(stderr, "cursor.realclose: ignored, cursor not open.\n");
		}
	}
	return(sqlca.sqlcode);
}

static char curs_close__doc__[] =
		"usage: cursor.close()";
static
PyObject *
curs_close(curs_obj *self, PyObject *args)
{
	if (!PyArg_ParseTuple(args, "")) {
		PyErr_SetString(ingmod_InterfaceError, curs_close__doc__);
		return(NULL);
	}

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].close()\n", self);
	}

	/*
	** clach04
	** I'd rather that the check below is REMOVED
	** because the cursor may already be closed (due to fetchall() which
	** performs an implicit closereal())
	** the DBI spec doesn't have anything to say on this but dumping an
	** and error and raising an exception that the cursor is already 
	** closed on a close attempt isn't helpful or Python-like
	** keeping it as-is for the time being.
	*/
	CHECK_OPEN(self);

	conn_setsid(self->sid);
	curs_realclose(self); /* may set sqlca.sqlcode */
	CHECK_SQLCODE("CLOSE", NULL);
	conn_release_session();
	Py_INCREF(Py_None);
	return(Py_None);
}

static char curs_fetchone__doc__[] =
		"usage: sequence = cursor.fetchone()";
static
PyObject *
curs_fetchone(curs_obj *self, PyObject *args)
{
	EXEC SQL BEGIN DECLARE SECTION;
		char *cname;
		char *sname;
	EXEC SQL END DECLARE SECTION;

	if (!PyArg_ParseTuple(args, "")) {
		PyErr_SetString(ingmod_InterfaceError, curs_fetchone__doc__);
		return(NULL);
	}


	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].fetchone()\n", self);
	}

	CHECK_OPEN(self);

	conn_setsid(self->sid);

	cname = self->cname;
	sname = self->sname;

#if defined(INGRES_64)
# define	SQLDA	self->out
	EXEC SQL FETCH :cname USING DESCRIPTOR :SQLDA;
# undef	SQLDA
#else
	/*__*/
	EXEC SQL FETCH :cname USING DESCRIPTOR :self->out;
#endif
	if (ingmod_verbose) {
		sqlda_print(self->out, stderr);
	}
	if (sqlca.sqlcode) { /* error occured, set to close state */
		if (sqlca.sqlcode == SQLCODE_NOT_FOUND) {
			/* no real error but no more tuples */
#if CLOSE_ON_NOT_FOUND
			curs_realclose(self);
#endif
			Py_INCREF(Py_None);
			conn_release_session();
			return(Py_None);
		}
		PyErr_SetString(ingmod_OperationalError, error_string("FETCH"));
		curs_realclose(self);
		conn_release_session();
		return(NULL);
	}
	conn_release_session();
	return(sqlda_2pyobject(self->out, self->handler));
}

static char curs_fetchmany__doc__[] =
		"usage: sequence = cursor.fetchmany(size = cursor.arraysize)";
static
PyObject *
curs_fetchmany(curs_obj *self, PyObject *args)
{
	int arraysize = self->arraysize;

	if (!PyArg_ParseTuple(args, "|i", &arraysize)) {
		PyErr_SetString(ingmod_InterfaceError, curs_fetchmany__doc__);
		return(NULL);
	}

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].fetchmany(%d)\n", self, arraysize);
	}

	CHECK_OPEN(self);

	PyErr_SetString(ingmod_NotSupportedError, "not implemented yet");
	return(NULL);
}

static char curs_fetchall__doc__[] =
		"usage: sequence = cursor.fetchall()";
static
PyObject *
curs_fetchall(curs_obj *self, PyObject *args)
{
	if (!PyArg_ParseTuple(args, "")) {
		PyErr_SetString(ingmod_InterfaceError, curs_fetchall__doc__);
		return(NULL);
	}

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].fetchall()\n", self);
	}

	CHECK_OPEN(self);

	PyErr_SetString(ingmod_NotSupportedError, "not implemented yet");
	return(NULL);
}

static char curs_nextset__doc__[] =
		"usage: ret = cursor.nextset()";
static
PyObject *
curs_nextset(curs_obj *self, PyObject *args)
{
	if (!PyArg_ParseTuple(args, "")) {
		PyErr_SetString(ingmod_InterfaceError, curs_nextset__doc__);
		return(NULL);
	}

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].nextset()\n", self);
	}
	CHECK_OPEN(self);

	PyErr_SetString(ingmod_NotSupportedError, "not implemented yet");
	return(NULL);
}

static char curs_setinputsizes__doc__[] =
		"usage: cursor.setinputsizes(sizes)";
static
PyObject *
curs_setinputsizes(curs_obj *self, PyObject *args)
{
	if (!PyArg_ParseTuple(args, "")) {
		PyErr_SetString(ingmod_InterfaceError, curs_setinputsizes__doc__);
		return(NULL);
	}

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].setinputsizes%s\n", self, STR(args));
	}
	CHECK_OPEN(self);

	PyErr_SetString(ingmod_NotSupportedError, "not implemented yet");
	return(NULL);
}

static char curs_setoutputsize__doc__[] =
		"usage: ret = cursor.setoutputsize(size, column = None)";
static
PyObject *
curs_setoutputsize(curs_obj *self, PyObject *args)
{
	if (!PyArg_ParseTuple(args, "")) {
		PyErr_SetString(ingmod_InterfaceError, curs_setoutputsize__doc__);
		return(NULL);
	}

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].setoutputsize%s\n", self, STR(args));
	}
	CHECK_OPEN(self);

	PyErr_SetString(ingmod_NotSupportedError, "not implemented yet");
	return(NULL);
}

#if !defined(INGRES_64)
static char curs_register__doc__[] =
		"usage: cursor.register(handler)";
static
PyObject *
curs_register(curs_obj *self, PyObject *args)
{
	PyObject *handler = NULL;

	if (!PyArg_ParseTuple(args, "O", &handler)) {
		PyErr_SetString(ingmod_InterfaceError, curs_register__doc__);
		return(NULL);
	}
	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].register%s\n", self, STR(args));
	}
	if (self->handler) {
		Py_DECREF(self->handler);
		self->handler = NULL;
	}
	if (!handler || !handler_check(handler)) {
		PyErr_SetString(PyExc_TypeError, "not a Datahandler");
		return(NULL);
	}
	self->handler = (handler_obj *)handler;
	Py_INCREF(self->handler);
	Py_INCREF(Py_None);
	return(Py_None);
}
#endif

static char curs_connection__doc__[] =
		"usage: connection = cursor.connection()";
static
PyObject *
curs_connection(curs_obj *self, PyObject *args)
{
	if (!PyArg_ParseTuple(args, "")) {
		PyErr_SetString(ingmod_InterfaceError, curs_connection__doc__);
		return(NULL);
	}
	/*
	CHECK_OPEN(self);
	*/

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].connection()\n", self);
	}
	Py_INCREF(self->conn);
	return((PyObject *)self->conn);
}

static
PyObject *
curs_names(curs_obj *self)
{
	IISQLVAR *v;
	PyObject *tuple;
	int i;

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].names\n", self);
	}
	CHECK_OPEN(self);

	conn_setsid(self->sid);
	tuple = PyTuple_New(self->out->sqld);
	for (i = 0, v = self->out->sqlvar; i < self->out->sqld; ++i, ++v) {
		PyObject *field = PyString_FromStringAndSize(
				(char *)v->sqlname.sqlnamec, v->sqlname.sqlnamel);
		if (field == NULL) {
			Py_DECREF(tuple);
			PyErr_SetString(ingmod_InternalError,
					"cursor.names: build value failed");
			conn_release_session();
			return(NULL);
		}
		PyTuple_SetItem(tuple, i, field);
	}
	conn_release_session();
	return(tuple);
}

static
PyObject *
curs_lens(curs_obj *self)
{
	IISQLVAR *v;
	PyObject *tuple;
	int i;

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].lens\n", self);
	}
	CHECK_OPEN(self);

	conn_setsid(self->sid);
	tuple = PyTuple_New(self->out->sqld);
	for (i = 0, v = self->out->sqlvar; i < self->out->sqld; ++i, ++v) {
		PyObject *field = PyInt_FromLong((long)v->sqllen);
		if (field == NULL) {
			Py_DECREF(tuple);
			PyErr_SetString(ingmod_InternalError,
					"cursor.lens: build value failed");
			conn_release_session();
			return(NULL);
		}
		PyTuple_SetItem(tuple, i, field);
	}
	conn_release_session();
	return(tuple);
}

static
PyObject *
curs_ingtypes(curs_obj *self)
{
	IISQLVAR *v;
	PyObject *tuple;
	int i;

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].ingtypes\n", self);
	}
	CHECK_OPEN(self);

	conn_setsid(self->sid);
	tuple = PyTuple_New(self->out->sqld);
	for (i = 0, v = self->out->sqlvar; i < self->out->sqld; ++i, ++v) {
		PyObject *field = PyInt_FromLong((long)v->sqltype);
		if (field == NULL) {
			Py_DECREF(tuple);
			PyErr_SetString(ingmod_InternalError, "cursor.ingtypes: build value failed");
			conn_release_session();
			return(NULL);
		}
		PyTuple_SetItem(tuple, i, field);
	}
	conn_release_session();
	return(tuple);
}

static PyMethodDef curs_methods[] = {
	{ "callproc",		(PyCFunction)curs_callproc,		METH_VARARGS,
		curs_callproc__doc__ },
	{ "close", 		(PyCFunction)curs_close,			METH_VARARGS,
		curs_close__doc__ },
	{ "execute",		(PyCFunction)curs_execute,		METH_VARARGS,
		curs_execute__doc__ },
	{ "fetch",		(PyCFunction)curs_fetchone,		METH_VARARGS,
		curs_fetchone__doc__ },
	{ "fetchone", 		(PyCFunction)curs_fetchone,		METH_VARARGS,
		curs_fetchone__doc__ },
	{ "executemany", 	(PyCFunction)curs_executemany,	METH_VARARGS,
		curs_executemany__doc__ },
	{ "fetchmany", 	(PyCFunction)curs_fetchmany,		METH_VARARGS,
		curs_fetchmany__doc__ },
	{ "fetchall", 		(PyCFunction)curs_fetchall,		METH_VARARGS,
		curs_fetchall__doc__ },
	{ "nextset", 		(PyCFunction)curs_nextset,		METH_VARARGS,
		curs_nextset__doc__ },
	{ "setinputsizes", 	(PyCFunction)curs_setinputsizes,	METH_VARARGS,
		curs_setinputsizes__doc__ },
	{ "setoutputsize", 	(PyCFunction)curs_setoutputsize,	METH_VARARGS,
		curs_setoutputsize__doc__ },
#if !defined(INGRES_64)
	{ "register",		(PyCFunction)curs_register,		METH_VARARGS,
		curs_register__doc__ },
#endif
	{ "connection",	(PyCFunction)curs_connection,		METH_VARARGS,
		curs_connection__doc__ },
	{ NULL,			NULL,		0,				NULL }
};

static
PyObject *
curs_getattr(curs_obj *self, char *name)
{
	EXEC SQL BEGIN DECLARE SECTION;
		char msg[MAXSTRSIZE];
		char event[MAXSTRSIZE];
		char text[MAXSTRSIZE];
	EXEC SQL END DECLARE SECTION;

	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].getattr('%s')\n", self, name);
	}
	event[0] = text[0] = msg[0] = '\0';
	if (strcmp(name, "arraysize") == 0) {
		return(PyInt_FromLong((long)self->arraysize));
	}
	if (strcmp(name, "prefetchrows") == 0) {
		return(PyInt_FromLong((long)self->prefetchrows));
	}
	else if (strcmp(name, "dbevent") == 0) {
		conn_setsid(self->sid);
		EXEC SQL INQUIRE_SQL(:event = DBEVENTNAME, :text = DBEVENTTEXT);
		conn_release_session();
		return(Py_BuildValue("(ss)", clear_trail(name), clear_trail(text)));
	}
	else if (strcmp(name, "description") == 0) {
		if (self->out) {
			if (!self->descr) {
				conn_setsid(self->sid);
				self->descr = sqlda_description(self->out);
				conn_release_session();
			}
			if (self->descr) {
				Py_INCREF(self->descr);
				return(self->descr);
			}
		}
		Py_INCREF(Py_None);
		return(Py_None);
	}
	else if (strcmp(name, "rowcount") == 0) {
		return(PyInt_FromLong((long)sqlca.sqlerrd[2]));
	}
	else if (strcmp(name, "sqlcode") == 0) {
		return(PyInt_FromLong((long)sqlca.sqlcode));
	}
	else if (strcmp(name, "sqlerror") == 0) {
		conn_setsid(self->sid);
		EXEC SQL INQUIRE_SQL(:msg = ERRORTEXT);
		conn_release_session();
		return(PyString_FromString(clear_trail(msg)));
	}
#if !defined(INGRES_64)
	else if (strcmp(name, "handler") == 0) {
		if (self->handler) {
			Py_INCREF(self->handler);
			return((PyObject *)self->handler);
		}
		Py_INCREF(Py_None);
		return(Py_None);
	}
#endif
	else if (strcmp(name, "lens") == 0) {
		return(curs_lens(self));
	}
	else if (strcmp(name, "names") == 0) {
		return(curs_names(self));
	}
	else if (strcmp(name, "ingtypes") == 0) {
		return(curs_ingtypes(self));
	}
	return(Py_FindMethod(curs_methods, (PyObject *)self, name));
}

static
int
curs_setattr(curs_obj *self, char *name, PyObject *value)
{
	if (ingmod_debug) {
		fprintf(stderr, "cursor[%p].setattr('%s', %s)\n",
				self, name, STR(value));
	}
	if (strcmp(name, "arraysize") == 0) {
		long arraysize;
		arraysize = PyInt_AsLong(value);
		if (arraysize == -1 && PyErr_Occurred()) {
			return(-1);
		}
		self->arraysize = arraysize;
		return(0);
     }
	else if (strcmp(name, "prefetchrows") == 0) {
		long prefetchrows;
		prefetchrows = PyInt_AsLong(value);
		if (prefetchrows == -1 && PyErr_Occurred()) {
			return(-1);
		}
		self->prefetchrows = prefetchrows;
		return(0);
     }
#if !defined(INGRES_64)
	else if (strcmp(name, "handler") == 0) {
		if (self->handler) {
			Py_DECREF(self->handler);
			self->handler = NULL;
		}
		if (!value || !handler_check(value)) {
			PyErr_SetString(PyExc_TypeError, "not a Datahandler");
			return(-1);
		}
		self->handler = (handler_obj *)value;
		return(0);
	}
#endif
	PyErr_SetString(PyExc_AttributeError, name);
	return(-1);
}

static PyTypeObject curs_type = {
	PyObject_HEAD_INIT(NULL)   /* see http://www.python.org/doc/2.1.3/ext/dnt-basics.html and also initingmod() function */
	0,						/*ob_size*/
	"Ingres cursor",			/*tp_name*/
	sizeof(curs_obj),			/*tp_basicsize*/
	0,						/*tp_itemsize*/
	/* methods */
	(destructor)curs_dealloc,	/*tp_dealloc*/
	(printfunc)curs_print,		/*tp_print*/
	(getattrfunc)curs_getattr,	/*tp_getattr*/
	(setattrfunc)curs_setattr,	/*tp_setattr*/
	(cmpfunc)0,				/*tp_compare*/
	(reprfunc)0,				/*tp_repr*/
	0,						/* tp_as_number*/
	0,						/* tp_as_sequence*/
	0,						/* tp_as_mapping*/
	(hashfunc)0,				/*tp_hash*/
	(ternaryfunc)0,			/*tp_call*/
	(reprfunc)0,				/*tp_str*/

	/* Space for future expansion */
	0L,0L,0L,0L,
	"Ingres cursor object, DB API 2.0"	/* Documentation string */
};



/*
** Declarations for objects of type INGRES DB Connection
*/
#define	MAXCURSPERSESSION	16

typedef enum { NOTCONNECTED = 0, CONNECTED = 1, COMMITED } connstate;

typedef struct {
	PyObject_HEAD
	int		sid;
	connstate	state;
	int		cmax;	/* maximal # of cursor objects per connection */
	int		cnum;	/* # of cursor objects in use */
	curs_obj	**curs;
} conn_obj;

staticforward PyTypeObject conn_type;

static
int
conn_print(conn_obj *self, FILE *fp, int flags)
{
	fprintf(fp, "<ingres connection %d at %p>", self->sid, self);
	return(0);
}

static
conn_obj *
conn_new()
{
	conn_obj *n;

	if (ingmod_debug) {
		fprintf(stderr, "connection[%d].new()\n", ingmod_num_session + 1);
	}
	if ((n = PyObject_NEW(conn_obj, &conn_type))) {
		n->sid = ++ingmod_num_session;
		n->state = NOTCONNECTED;
		n->cmax = MAXCURSPERSESSION;
		n->cnum = 0;
		if (!(n->curs = calloc(n->cmax, sizeof(curs_obj *)))) {
			Py_FatalError("connection.new: out of memory");
			return(NULL);
		}
	}
	return(n);
}

static
void
conn_delete(conn_obj *self)
{
	int i;

	if (ingmod_debug) {
		fprintf(stderr, "connection[%d].delete()\n", self->sid);
	}
	if (self->curs) {
		for (i = 0; i < self->cnum; ++i) {
			if (self->curs[i]) {
				Py_DECREF(self->curs[i]);
			}
		}
		free(self->curs);
	}
	PyMem_DEL(self);
}

static
void
conn_dealloc(conn_obj *self)
{
	if (ingmod_debug) {
		fprintf(stderr, "connection[%d].dealloc()\n", self->sid);
	}
	/*TODO*/
	/* conn_realclose(self); */
	conn_delete(self);
}

/* get session, returns sid, may set sqlca.sqlcode */
static
int
conn_getsid()
{
	EXEC SQL BEGIN DECLARE SECTION;
		int sid = -1;
	EXEC SQL END DECLARE SECTION;

	EXEC SQL INQUIRE_SQL(:sid = SESSION);
	/*
	** clach04
	** I think we should check the sid here not the sqlda.sqlcode
	** e.g. drop a table that does not exist, then inquire ingres the sid
	** you get the drop error no such table error returned!
	*/
	if (sid < 0) {
		fprintf(stderr, "connection.getsid: failed.\n");
		return(-1);
	}
	if (ingmod_debug) {
		fprintf(stderr, "connection.getsid() = %d\n", sid);
	}
	return(sid);
}

/* set session to self->sid, returns sqlcode */
static
int
conn_setsid(sid)
EXEC SQL BEGIN DECLARE SECTION;
	int sid;
EXEC SQL END DECLARE SECTION;
{
	int current_sid = conn_getsid();

	if (ingmod_debug) {
		fprintf(stderr, "connection.setsid(%d)\n", sid);
	}
	/* zero return possible under _certain_ circumstances */
	if (current_sid != sid) {
		EXEC SQL SET_SQL(SESSION = :sid);
	}
	return(sqlca.sqlcode);
}

/*
** Release a DBMS connection so that other threads can use it
** this does NOT close the DBMS session, just releases the thread
** "lock" so that other threads can switch to it.
*/
static
void
conn_release_session(void)
{
	int current_sid = conn_getsid();

	if (ingmod_debug) {
		fprintf(stderr, "connection.release_session(%d)\n", current_sid);
	}

	/* Without this get
E_LQ00C9 Attempt to switch to a session which is currently active.
 when setting the session id (numeric not string)
 followed by
E_LQ002E The 'prepare' query has been issued outside of a DBMS session.

on selects, etc.
	*/
	/* set connection NAME is Ingres 2.0 (maybe 1.x) and later */
	/* none is new for 2.5 and means NONE */
	/* passing in none to 2.0 has no effect, i.e. sessions stays the same */
	EXEC SQL set connection none;
}

static
int
conn_disconnect(int sid)
{
	EXEC SQL BEGIN DECLARE SECTION;
		int nocommit;
	EXEC SQL END DECLARE SECTION;
		int return_value=0;

	if (ingmod_debug) {
		fprintf(stderr, "connection.disconnect(sid=%d)\n", sid);
	}
	if (conn_setsid(sid)) {
		return(sqlca.sqlcode);
	}
	/* ask for open transactions
	 * I hope this applies only to the current session
	 * otherwise rollback should be done unconditional */
	EXEC SQL INQUIRE_SQL(:nocommit = TRANSACTION);
	if (nocommit) { /* no commit or rollback done */
		fprintf(stderr, "connection.disconnect: warning: roll back changes.\n");
		EXEC SQL ROLLBACK;
		if (sqlca.sqlcode) {
			fprintf(stderr, "connection.disconnect: couldn't roll back.\n");
		}
	}
	EXEC SQL DISCONNECT;
	return_value=sqlca.sqlcode;
	/*
	** probably over kill but release anyway
	*/
	conn_release_session();
	return(return_value);
}


static char conn_close__doc__[] =
		"usage: ret = connection.close()";
static
PyObject *
conn_close(conn_obj *self, PyObject *args)
{
	if (!PyArg_ParseTuple(args, "")) {
		PyErr_SetString(ingmod_InterfaceError, conn_close__doc__);
		return(NULL);
	}
	if (ingmod_debug) {
		fprintf(stderr, "connection[%d].close()\n", self->sid);
	}
	conn_disconnect(self->sid);
	CHECK_SQLCODE("DISCONNECT", NULL);
	self->sid = -1;
	self->state = NOTCONNECTED;
	Py_INCREF(Py_None);
	return(Py_None);
}

static char conn_commit__doc__[] =
		"usage: ret = connection.commit()";
static
PyObject *
conn_commit(conn_obj *self, PyObject *args)
{
	if (!PyArg_ParseTuple(args, "")) {
		PyErr_SetString(ingmod_InterfaceError, conn_commit__doc__);
		return(NULL);
	}
	if (ingmod_debug) {
		fprintf(stderr, "connection[%d].commit()\n", self->sid);
	}
	conn_setsid(self->sid);
	EXEC SQL COMMIT;
	CHECK_SQLCODE("COMMIT", NULL);
	Py_INCREF(Py_None);
	conn_release_session();
	return(Py_None);
}

static char conn_rollback__doc__[] =
		"usage: ret = connection.rollback()";
static
PyObject *
conn_rollback(conn_obj *self, PyObject *args)
{
	if (!PyArg_ParseTuple(args, "")) {
		PyErr_SetString(ingmod_InterfaceError, conn_rollback__doc__);
		return(NULL);
	}
	if (ingmod_debug) {
		fprintf(stderr, "connection[%d].rollback()\n", self->sid);
	}
	conn_setsid(self->sid);
	EXEC SQL ROLLBACK;
	CHECK_SQLCODE("ROLLBACK", NULL);
	Py_INCREF(Py_None);
	conn_release_session();
	return(Py_None);
}

static char conn_immediate__doc__[] =
		"usage: sqlcode = connection.immediate(query, parameters = None)";
static
PyObject *
conn_immediate(conn_obj *self, PyObject *args)
{
	EXEC SQL BEGIN DECLARE SECTION;
		char *query;
	EXEC SQL END DECLARE SECTION;
	PyObject *param = NULL;

	if (!PyArg_ParseTuple(args, "s|O", &query, &param)) {
		PyErr_SetString(ingmod_InterfaceError, conn_immediate__doc__);
		return(NULL);
	}
	if (ingmod_debug) {
		fprintf(stderr, "connection.immediate%s\n", STR(args));
	}
	conn_setsid(self->sid);
	if (param) {
		IISQLDA *sqlda = NULL;

		int nparam = count_chr(query, '?');
		if (!(sqlda = sqlda_input_bind(sqlda, param, nparam, NULL))) {
			conn_release_session();
			return(NULL);
		}
		EXEC SQL EXECUTE IMMEDIATE :query USING DESCRIPTOR :sqlda;
		CHECK_SQLCODE("IMMEDIATE", NULL);
		sqlda_free(&sqlda);
	}
	else {
		EXEC SQL EXECUTE IMMEDIATE :query;
		CHECK_SQLCODE("IMMEDIATE", NULL);
	}
	conn_release_session();
	Py_INCREF(Py_None);
	return(Py_None);
}

static char conn_cursor__doc__[] =
		"usage: ret = connection.cursor()";
static
PyObject *
conn_cursor(conn_obj *self, PyObject *args)
{
	curs_obj *newcurs = NULL;

	if (!PyArg_ParseTuple(args, "")) {
		PyErr_SetString(ingmod_InterfaceError, conn_cursor__doc__);
		return(NULL);
	}
	if (ingmod_debug) {
		fprintf(stderr, "connection[%d].cursor()\n", self->sid);
	}
	if (self->cnum >= self->cmax) {
		PyErr_SetString(ingmod_OperationalError,
				"max # of cursors per session reached");
		return(NULL);
	}
	if ((newcurs = curs_new(self->sid))) {
		self->curs[self->cnum++] = newcurs;
		/* reference to the connection object */
		newcurs->conn = (PyObject *)self;
		Py_INCREF(self);
	}
	return((PyObject *)newcurs);
}

static PyMethodDef conn_methods[] = {
	{ "close",	(PyCFunction)conn_close,		METH_VARARGS,	conn_close__doc__ },
	{ "commit", 	(PyCFunction)conn_commit,	METH_VARARGS,	conn_commit__doc__ },
	{ "immediate", (PyCFunction)conn_immediate,	METH_VARARGS,	conn_immediate__doc__ },
	{ "cursor", 	(PyCFunction)conn_cursor,	METH_VARARGS,	conn_cursor__doc__ },
	{ "rollback",	(PyCFunction)conn_rollback,	METH_VARARGS,	conn_rollback__doc__ },
	{ NULL,		NULL,		0,			NULL }
};

static
PyObject *
conn_getattr(conn_obj *self, char *name)
{
	if (ingmod_debug) {
		fprintf(stderr, "connection[%d].getattr('%s')\n", self->sid, name);
	}
	else if (strcmp(name, "sqlcode") == 0) {
		return(PyInt_FromLong((long)sqlca.sqlcode));
	}
	return(Py_FindMethod(conn_methods, (PyObject *)self, name));
}

static PyTypeObject conn_type = {
	PyObject_HEAD_INIT(NULL)   /* see http://www.python.org/doc/2.1.3/ext/dnt-basics.html and also initingmod() function */
	0,						/*ob_size*/
	"Ingres connction",			/*tp_name*/
	sizeof(conn_obj),			/*tp_basicsize*/
	0,						/*tp_itemsize*/
	/* methods */
	(destructor)conn_dealloc,	/*tp_dealloc*/
	(printfunc)conn_print,		/*tp_print*/
	(getattrfunc)conn_getattr,	/*tp_getattr*/
	(setattrfunc)0,			/*tp_setattr*/
	(cmpfunc)0,				/*tp_compare*/
	(reprfunc)0,				/*tp_repr*/
	0,						/* tp_as_number*/
	0,						/* tp_as_sequence*/
	0,						/* tp_as_mapping*/
	(hashfunc)0,				/*tp_hash*/
	(ternaryfunc)0,			/*tp_call*/
	(reprfunc)0,				/*tp_str*/

	/* Space for future expansion */
	0L,0L,0L,0L,
	"Ingres connection object, DB API 2.0"	/* Documentation string */
};


/*
** Module methods
*/

static char ingmod_connect__doc__[] =
		"usage: conn = ingmod.connect(database, options = None, user = None)";
static
PyObject *
ingmod_connect(PyObject *self, PyObject *args)
{
	EXEC SQL BEGIN DECLARE SECTION;
	char *db = NULL;
	char *opts = NULL;
	char *usr = NULL;
	int sid;
	EXEC SQL END DECLARE SECTION;
	conn_obj *newconn;

	if (!PyArg_ParseTuple(args, "s|zz", &db, &opts, &usr)) {
		PyErr_SetString(ingmod_InterfaceError, ingmod_connect__doc__);
		return(NULL);
	}
	if (ingmod_debug) {
		fprintf(stderr, "ingmod.connect%s\n", STR(args));
	}
	if (!getenv("II_SYSTEM")) {
		PyErr_SetString(ingmod_OperationalError, "connect: II_SYSTEM not set");
		return(NULL);
	}

	if ((newconn = conn_new()) != NULL) {
		sid = newconn->sid;
		if (usr && opts) {
			EXEC SQL CONNECT :db SESSION :sid IDENTIFIED BY :usr OPTIONS = :opts;
		}
		else if (usr) {
			EXEC SQL CONNECT :db SESSION :sid IDENTIFIED BY :usr;
		}
		else if (opts) {
			EXEC SQL CONNECT :db SESSION :sid OPTIONS = :opts;
		}
		else {
			EXEC SQL CONNECT :db SESSION :sid;
		}
		if (sqlca.sqlcode) { /* failed */
			Py_DECREF(newconn);
		}
		CHECK_SQLCODE("CONNECT", NULL);
		/* make this session the current */
		conn_setsid(sid);
	}
	conn_release_session();
	return((PyObject *)newconn);
}

static char ingmod_getsetdebug__doc__[] =
		"usage: value = ingmod.debug(value)";
static
PyObject *
ingmod_getsetdebug(PyObject *self, PyObject *args)
{
#if INGMOD_DEBUG
	int on = 1;
	if (PyArg_ParseTuple(args, "|i", &on)) {
		ingmod_debug = on;
	}
	fprintf(stderr, "ingmod.debug = %d\n", ingmod_debug);
	return(PyInt_FromLong(ingmod_debug));
#else
	PyErr_SetString(ingmod_InterfaceError, "not compiled with debug option");
	return(NULL);
#endif
}

static char ingmod_getsetverbose__doc__[] =
		"usage: value = ingmod.verbose(value)";
static
PyObject *
ingmod_getsetverbose(PyObject *self, PyObject *args)
{
	int on = 1;

	if (PyArg_ParseTuple(args, "|i", &on)) {
		ingmod_verbose = on;
	}
	if (ingmod_debug) {
		fprintf(stderr, "ingmod.verbose = %d\n", ingmod_verbose);
	}
	return(PyInt_FromLong(ingmod_verbose));
}

#if defined(INGRES_64)
static char iingmod_module_doc[] = "Ingres 6.4 connectivity";
#else
static char iingmod_module_doc[] = "OpenIngres 1.2 connectivity";
#endif

static PyMethodDef ingmod_methods[] = {
	{ "connect",			ingmod_connect,	METH_VARARGS,
		ingmod_connect__doc__ },
	{ "debug",			ingmod_getsetdebug,	METH_VARARGS,
		ingmod_getsetdebug__doc__ },
	{ "verbose",			ingmod_getsetverbose,	METH_VARARGS,
		ingmod_getsetverbose__doc__ },
	{ "Timestamp",			ingmod_timestamp,	METH_VARARGS,
		ingmod_timestamp__doc__ },
	{ "TimestampFromTicks",	ingmod_timestamp,	METH_VARARGS,
		ingmod_timestamp__doc__ },
#if !defined(INGRES_64)
	{ "Binary",		 	ingmod_binary,		METH_VARARGS,
		ingmod_binary__doc__ },
	{ "Datahandler",	 	ingmod_datahandler,	METH_VARARGS,
		ingmod_datahandler__doc__ },
#endif
	{ NULL,		NULL,			0,			NULL }
};

void
initingmod()
{
	/*
	** clach04 compile problems under win32 require change to object definition/initialisation
	**
    	** From :
	** http://mail.python.org/pipermail/python-announce-list/1999-July/000101.html 
	** section 3.24. "Initializer not a constant" while building DLL on MS-Windows
    	**
	** http://www.python.org/doc/2.1.3/ext/dnt-basics.html
	**
    	** http://www.python.org/doc/1.6/ext/win-cookbook.html
	** 
	** Want to set object type in init code for object/class
	** 
	** From:
	** http://www.python.org/doc/current/ext/dnt-basics.html
	** 
	** Want to set object type with function call too:
	**        PyType_Ready()
	** 
	** 
	** Note quite sure which advice to follow so following OLD python 
	** version advice (as PyType_Ready() appears to be for new versions)
	*/
        #define ingmod_init_type(X) X.ob_type = &PyType_Type
        ingmod_init_type(date_type);
        ingmod_init_type(binary_type);
        ingmod_init_type(handler_type);
        ingmod_init_type(curs_type);
        ingmod_init_type(conn_type);
        
	if (!(ingmod_module = Py_InitModule4("ingmod", ingmod_methods, iingmod_module_doc,
			(PyObject*)NULL, PYTHON_API_VERSION))) {
		Py_FatalError("can not init ingmod module");
	}
	if (!(ingmod_dict = PyModule_GetDict(ingmod_module))) {
		Py_FatalError("can not create ingmod dictionary");
	}

	/* exception hierarchy */
#define NEW_EXCEPTION(super, exc)	\
	if (!(ingmod_##exc = PyErr_NewException("ingmod."#exc, super, NULL))) {	\
		Py_FatalError("can not create "#exc" exception");					\
	}															\
	if (PyDict_SetItemString(ingmod_dict, #exc, ingmod_##exc)) {			\
		Py_FatalError("can not add "#exc" object to ingmod dictionary");		\
	}
	NEW_EXCEPTION(PyExc_StandardError, Warning);
	NEW_EXCEPTION(PyExc_StandardError, Error);
	NEW_EXCEPTION(ingmod_Error, InterfaceError);
	NEW_EXCEPTION(ingmod_Error, DatabaseError);
	NEW_EXCEPTION(ingmod_DatabaseError, DataError);
	NEW_EXCEPTION(ingmod_DatabaseError, OperationalError);
	NEW_EXCEPTION(ingmod_DatabaseError, IntegrityError);
	NEW_EXCEPTION(ingmod_DatabaseError, InternalError);
	NEW_EXCEPTION(ingmod_DatabaseError, NotSupportedError);

#define NEW_OBJECT(obj, constructor)	\
	if (!(ingmod_##obj = constructor)) {								\
		Py_FatalError("can not create "#obj" object");					\
	}															\
	if (PyDict_SetItemString(ingmod_dict, #obj, ingmod_##obj)) {			\
		Py_FatalError("can not add "#obj" object to ingmod dictionary");		\
	}

	NEW_OBJECT(version, PyString_FromString("1.2 (C) hm@baltic.de"));
	NEW_OBJECT(apilevel, PyString_FromString("2.0"));
	NEW_OBJECT(threadsafety, PyInt_FromLong(0L));
	NEW_OBJECT(paramstyle, PyString_FromString("qmark"));

	NEW_OBJECT(STRING, PyString_FromString("STRING"));
	NEW_OBJECT(NUMBER, PyString_FromString("NUMBER"));
	NEW_OBJECT(ROWID, PyString_FromString("ROWID"));

	if (PyDict_SetItemString(ingmod_dict, "connection", (PyObject *)&conn_type)) {
		Py_FatalError("can not add connection object to ingmod dictionary");
	}

	if (PyDict_SetItemString(ingmod_dict, "cursor", (PyObject *)&curs_type)) {
		Py_FatalError("can not add cursor object to ingmod dictionary");
	}

	if (PyDict_SetItemString(ingmod_dict, "DATETIME", (PyObject *)&date_type)) {
		Py_FatalError("can not add DATETIME object to ingmod dictionary");
	}

#if !defined(INGRES_64)
	if (PyDict_SetItemString(ingmod_dict, "BINARY", (PyObject *)&binary_type)) {
		Py_FatalError("can not add BINARY object to ingmod dictionary");
	}

	if (PyDict_SetItemString(ingmod_dict, "HANDLER", (PyObject *)&handler_type)) {
		Py_FatalError("can not add HANDLER object to ingmod dictionary");
	}
#endif

	EXEC SQL SET_SQL(ERRORHANDLER = error_handler);
	EXEC SQL SET_SQL(DBEVENTHANDLER = dbevent_handler);
	EXEC SQL SET_SQL(MESSAGEHANDLER = message_handler);

	if (INGMOD_DEBUG) {
		fprintf(stderr, "ingmod version %s: level=%s, style='%s', thread=%s, built with DEBUG available\n",
				STR(ingmod_version),
				STR(ingmod_apilevel),
				STR(ingmod_paramstyle),
				STR(ingmod_threadsafety));
	}
}

/*vi: set ts=5 sw=5 :*/
