#!/home/ingres/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python
#!python
##  ~/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python

import ingmod as sqlsession

DB = "clach04"
DB2 = "iidbdb"

con=sqlsession.connect(DB)
cur=con.cursor()

cur.execute("select table_name, table_owner from iitables where table_name like '%s%%'" % 'iitables')
# fetchall not implemented in Ingres!!!!
#print cur.fetchall()
row = cur.fetchone()
while row:
    print row
    row = cur.fetchone()
# transaction commit/rollback/nothing has no impact on generated error
#con.rollback()
#con.commit()


con2=sqlsession.connect(DB2)
cur2=con2.cursor()
cur2.execute("select name, own from iidatabase where own != '$ingres'")
# fetchall not implemented in Ingres!!!!
row = cur2.fetchone()
while row:
    print row
    row = cur2.fetchone()
# transaction commit/rollback/nothing has no impact on generated error
con2.close()



cur.execute("select * from phone_book where account like '%s%%'" % 'clach')
# fetchall not implemented in Ingres!!!!
#print cur.fetchall()
row = cur.fetchone()
while row:
    print row
    row = cur.fetchone()
# transaction commit/rollback/nothing has no impact on generated error

