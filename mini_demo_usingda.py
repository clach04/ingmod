#!/home/ingres/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python
#!python
##  ~/clach04/wip/zope/Zope-2.6.4rc2-linux2-x86/bin/python

#
# Demo to do basic, drop, create, insert, select, update, delete
#

import sys
sys.path.append('E:\\programs\\Plone1\\Zope\\lib\\python')


import ZODB, Acquisition

import Products.ZIngresDA

DB = "clach04"

mydb = Products.ZIngresDA.db.DB(connection=DB)

def do_one_select(table_name=None):
    if table_name==None:
        table_name='iidbconstants'
    query_text = "select * from %s" % table_name 
    print 'Query\n============================\n' + query_text + '\n============================'
    results=mydb.query(query_string=query_text)
    for row in results:
        print row
    print '---------------------------- End ----------------------------\n'



# booleans are not available in old versions of python so use ints
drop_table=1
if drop_table==1:
    #try:
        print 'about to drop table'
        print mydb.query(query_string="drop table ingres_python")
        '''
    except Error, detail:
        print 'exception type'
        print Error
        print 'exception/error detail'
        print detail
        '''


print 'about to CREATE table'
print mydb.query(query_string="create table ingres_python (col1 integer, col2 varchar(20))")

print 'about to INSERT into table'
print mydb.query(query_string="insert into ingres_python (col1, col2) values (1, 'one')")


for x in range(1,2):
    print "x is " + str(x)
    #do_one_select()
    do_one_select(table_name='ingres_python')
    
print 'about to drop table'
print mydb.query(query_string="drop table ingres_python")


# finish()
    
