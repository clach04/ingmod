#!/bin/env python

import ingmod

DB = "iidbdb"

def Date(yy = -1, mm = -1, dd = 1):
	return ingmod.Timestamp(yy, mm, dd, 0, 0, 0)

def Time(hh = -1, mm = -1, ss = 0):
	return ingmod.Timestamp(0, 0, 0, hh, mm, ss)

def Datahandler(o = None):
	return ingmod.Datahandler(o)

class datahandler:
	def __init__(self, obj = None):
		self._str = obj
		self._size = len(obj)
		self._pos = 0

	def get(self, string, end):
		print "datahandler.get:", self, len(string), end
		if self._str == None:
			self._str = string
		else:
			self._str = self._str + string

	def put(self, maxsize):
		print "datahandler.put:", self, maxsize
		if self._pos < self._size:
			if (self._pos + maxsize) >= self._size:
				end = self._size
			else:
				end = self._pos + maxsize
			sobj = self._str[self._pos:end]
			self._pos = end
			return sobj
		return None

	def data(self):
		return self._str

#ingmod.debug(0)
#ingmod.verbose(0)
print dir(ingmod)
cn1 = ingmod.connect(DB)
print cn1.__doc__, dir(cn1)
cu1 = cn1.cursor()
print cu1.__doc__, dir(cu1)
cn2 = ingmod.connect(DB)
cu2 = cn2.cursor()
cu2.arraysize = 24
cu2.execute("select tid,reltid,relid,relatts from iirelation where reltid = 33")
#cu2.execute("select tid,reltid,relid,relatts from iirelation")
print "rowcount =", cu2.rowcount, "arraysize =", cu2.arraysize
print cu2.description
t = cu2.fetchone()
while t:
	print t
	t = cu2.fetchone()
print "rowcount =", cu2.rowcount, "arraysize =", cu2.arraysize
print cn1, cu1, cn2, cu2
try:
	cu1.close()
except ingmod.Error, detail:
	print ingmod.Error, detail
print cu2.connection()
cn2.commit()
cn2.close()
cn1.close()
cn = ingmod.connect(DB)
cu = cn.cursor()
cn.immediate("create table abc ( id integer )")
cu.arraysize = 24
cu.execute("select * from iiattribute where attrelid = 33")
for t in cu.description:
	print t
t = cu.fetchone()
print "rowcount =", cu.rowcount, "arraysize =", cu.arraysize
while t:
	print t
	t = cu.fetchone()
#ingmod.debug(1)
#ingmod.verbose(1)
cu.execute("select * from iiattribute where attrelid = ?", (33, ))
print "rowcount =", cu.rowcount, "arraysize =", cu.arraysize
for t in cu.description:
	print t
print cn
print cu
print "ingtypes:", cu.ingtypes
cn.immediate("drop table abc")
t = cu.fetchone()
while t:
	print t
	t = cu.fetchone()
t = Time(11, 05, 00)
print "DATETIME:", t, type(t)
t = Time()
print "DATETIME:", t, type(t)
d = Date(1999, 3, 21)
print "DATETIME:", d, type(d)
d = Date(2000, 4)
print "DATETIME:", d, type(d)
d = Date()
print "DATETIME:", d, type(d)
ingres_64 = 0
try:
	b = ingmod.Binary("\001\002\003\004\000\005")
	print "BINARY:", b, type(b)
except:
	print "BINARY and DATA HANDLER not supported"
	ingres_64 = 1
if ingres_64:
	try:
		cn.immediate("create table testit (id int, datum date, num float)")
	except ingmod.Error, detail:
		print ingmod.Error, detail
	cn.immediate("insert into testit values (1, 'now', 23.45)")
	cn.commit()
	cu.execute("select * from testit")
	print "rowcount =", cu.rowcount, "arraysize =", cu.arraysize
	print cu.lens, cu.description
	t = cu.fetchone()
	while t:
		print t
		t = cu.fetchone()
	print "rowcount =", cu.rowcount, "arraysize =", cu.arraysize
else:
	dh = datahandler(100*'ABCDEFGHIJKLMNOPQRSTUVWXYZ')
	h = Datahandler(dh)
	print "DATA HANDLER:", h, type(h)
	# long varchar, byte varying ...
	try:
		cn.immediate("create table testit (id int, datum date, num decimal(5,3), descr long varchar, blub long byte, blib byte(6))")
	except ingmod.Error, detail:
		print ingmod.Error, detail
	cn.commit()
	cn.immediate("insert into testit values (1, 'now', 23.45, 'hallo!ballo', 'AAABBB', '123456789')")
	cu.execute("insert into testit values (?, ?, ?, ?, ?, ?)",
		(2, Date(), 67.89, 'hallo?ballo', h, ingmod.Binary('9876543210')))
	print "putsize =", h.putsize, "rowcount =", cu.rowcount, "arraysize =", cu.arraysize
	cn.commit()
	cu.register(h)
	cu.execute("select blub from testit")
	print "getsize =", h.getsize, "rowcount =", cu.rowcount, "arraysize =", cu.arraysize
	print cu.lens, cu.description
	t = cu.fetchone()
	while t:
		print t
		t = cu.fetchone()
	print "getsize =", h.getsize, "rowcount =", cu.rowcount, "arraysize =", cu.arraysize
	#print "handler.data =", h.data
cn.immediate("""
create procedure testproc(id int) as
declare
	rid int not null;
begin
	select id into :rid
	from testit
	where id = :id;
	if iirowcount = 1 then
		return rid;
	endif;
	return 0;
end""")
print "rowcount =", cu.rowcount, "arraysize =", cu.arraysize
try:
	print cu.callproc('testproc', ())
except Exception, detail:
	print "expected: not a dictionary:", Exception, detail
print cu.callproc('testproc', {'id':2})
cn.immediate("drop procedure testproc")
cu.execute("delete from testit")
print "rowcount =", cu.rowcount, "arraysize =", cu.arraysize
cn.immediate("drop table testit")
cn.commit()
print "apilevel = '%s', threadsafety = %d, paramstyle = '%s'" % (ingmod.apilevel, ingmod.threadsafety, ingmod.paramstyle)
