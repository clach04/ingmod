#!/home/ingres/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python
#!python
##  ~/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python

#
# Demo to do basic, drop, create, insert, select, update, delete
#

import ingmod as sqlsession

DB = "clach04"

___cmc_DA_DEBUG=0
if ___cmc_DA_DEBUG==1:
    sqlsession.debug(turnon = 1)
    sqlsession.verbose(1)

con=sqlsession.connect(DB)
cur=con.cursor()

def do_one_select(table_name=None):
    #cur=con.cursor()
    if table_name==None:
        table_name='iidbconstants'
    query_text = "select * from %s" % table_name 
    print 'Query\n============================\n' + query_text + '\n============================'
    cur.execute(query_text)
    # fetchall not implemented in Ingres!!!!
    #print cur.fetchall()
    row = cur.fetchone()
    while row:
        print row
        row = cur.fetchone()
    print '---------------------------- End ----------------------------\n'
    #cur.close()
    # transaction commit/rollback/nothing has no impact on generated error
    #con.rollback()
    #con.commit()

# booleans are not available in old versions of python so use ints
drop_table=1
if drop_table==1:
    try:
        print 'about to drop table'
        cur.execute("drop table ingres_python")
    except sqlsession.Error, detail:
        print 'exception type'
        print sqlsession.Error
        print 'exception/error detail'
        print detail


print 'about to CREATE table'
cur.execute("create table ingres_python (col1 integer, col2 varchar(20))")

print 'about to INSERT into table'
cur.execute("insert into ingres_python (col1, col2) values (1, 'one')")


for x in range(1,5):
    print "x is " + str(x)
    #do_one_select()
    do_one_select(table_name='ingres_python')
    
#cur.execute("drop table ingres_python")
con.commit();
    
