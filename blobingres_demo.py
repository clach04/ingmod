#!/home/ingres/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python
#!python
##  ~/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python

import ingmod as sqlsession

DB = "clach04"

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


con=sqlsession.connect(DB)
cur=con.cursor()

my_long_string = "hello not really that long"
d=datahandler(my_long_string)
dh = sqlsession.Datahandler(d)
cur.register(dh)

#cur.execute("select * from phone_book where account like '%s%%'" % 'clach')
cur.execute("select * from myblob")

print cur.description

# fetchall not implemented in Ingres!!!!
#print cur.fetchall()

row = cur.fetchone()
while row:
    print row
    print "lob", d.data()
    row = cur.fetchone()

