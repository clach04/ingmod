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
    print "description: " + str(cur.description)
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



'''
# Assume table already exists and was created thusly:


create table int_string(
        col1 integer,
        col2 varchar(20)
);
\p\g
\q

'''



print 'about to INSERT into int_string'
cur.execute("insert into int_string (col1, col2) values (1, 'one')")
print "description: " + str(cur.description)

do_one_select(table_name='int_string')


print 'about to INSERT into int_string'
cur.execute("insert into int_string (col1, col2) values (1, 'one')")
print "description: " + str(cur.description)

do_one_select(table_name='int_string')
    

# no need to commit, we want an implicit rollback
# con.commit();
    
