#!/home/ingres/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python
#!python
##  ~/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python

import ingmod as sqlsession
#sqlsession.debug(turnon = 1)

DB = "clach04"
DB2 = "iidbdb"

print "CMC create session connection 1\n"
con=sqlsession.connect(DB)
print "CMC create session cursor 1\n"
cur=con.cursor()

print "CMC create session connection 2\n"
con2=sqlsession.connect(DB2)
print "CMC create session cursor 2\n"
cur2=con2.cursor()
print "CMC close session connection 2\n"
con2.close()



print "CMC session 1 execute\n"
cur.execute("select * from phone_book where account like '%s%%'" % 'clach')
# fetchall not implemented in Ingres!!!!
#print cur.fetchall()
row = cur.fetchone()
while row:
    print row
    row = cur.fetchone()
# transaction commit/rollback/nothing has no impact on generated error


print "CMC session 1 execute\n"
curb=con.cursor()
curb.execute("select * from phone_book where account like '%s%%'" % 'clach')
# fetchall not implemented in Ingres!!!!
#print cur.fetchall()
row = curb.fetchone()
while row:
    print row
    row = curb.fetchone()
# transaction commit/rollback/nothing has no impact on generated error

