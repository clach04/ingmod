import sys
sys.path.append('E:\\programs\\Plone1\\Zope\\lib\\python')


import ZODB, Acquisition

import Products.ZIngresDA

mydb = Products.ZIngresDA.db.DB(connection='clach04')
print mydb.query(query_string="select * from iidbconstants")

