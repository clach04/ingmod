#!/home/ingres/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python
#!python
##  ~/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python

import ingmod as sqlsession

DB = "clach04"

con=sqlsession.connect(DB)
cur=con.cursor()

#cur.execute("select * from phone_book where account = 'clach04'")
#cur.execute("select * from phone_book where account = '%s'" % 'clach04')
cur.execute("select * from phone_book where account like '%s%%'" % 'clach')
#cur.execute("select * from myblob")

# fetchall not implemented in Ingres!!!!
#print cur.fetchall()

row = cur.fetchone()
while row:
    print row
    row = cur.fetchone()


