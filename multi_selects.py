#!/home/ingres/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python
#!python
##  ~/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python

import ingmod as sqlsession

DB = "clach04"

con=sqlsession.connect(DB)
#cur=con.cursor()

def do_one_select():
    #cur=con.cursor()
    cur.execute("select * from iidbconstants")
    # fetchall not implemented in Ingres!!!!
    #print cur.fetchall()
    row = cur.fetchone()
    while row:
        print row
        row = cur.fetchone()
    #cur.close()
    # transaction commit/rollback/nothing has no impact on generated error
    #con.rollback()
    #con.commit()


for x in range(1,20):
    print "x is " + str(x)
    do_one_select()
    
    

    
