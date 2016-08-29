#!/usr/bin/env python
'''
a simple bugzilla data analysis tool
'''


import os, sys
import datetime
import MySQLdb as mysql

class bugDM():
    '''
    a simple bugzilla data analysis tool
    '''
    def __init__(self, config_file):
        ''' Get bugzilla configuration information '''
        self.conf = self.get_config(config_file)
        self.conn = self.get_db_conn(self.conf)
        self.cursor = self.conn.cursor()

    def get_config(self, config_file):
        '''
        Get bugs statics status
        read from localconf file
        get database type, username, passord, database
        '''
        config = {}
        content = config_file.readlines()
        for line in content:
            if '$db_driver' in line:
                config['db_driver'] = line.split("'")[1]
            elif '$db_host' in line:
                config['db_host'] = line.split("'")[1]
            elif '$db_name' in line:
                config['db_name'] = line.split("'")[1]
            elif '$db_user' in line:
                config['db_user'] = line.split("'")[1]
            elif '$db_pass' in line:
                config['db_pass'] = line.split("'")[1]
            elif '$db_port' in line:
                config['db_port'] = int(line[:-2].split("=")[1])
            else:
                continue
        #print config
        return config

    def get_db_conn(self, config):
        '''
        Get db conn
        '''
        conn = None
        if config['db_driver'] == 'mysql':
            conn = mysql.connect(host=config['db_host'],
                                 port=config['db_port'],
                                 user=config['db_user'],
                                 passwd=config['db_pass'],
                                 db=config['db_name'])
        return conn

    def db_disconn(self):
        '''
        Close db conn
        '''
        self.conn.close()

    def get_summary(self, interval="all"):
        '''
        Get summary of bugzilla usage
        nuber of users, projects, and bugs
        for all time being or
        recent year/month
        '''
        del interval
        users = self.get_number("profiles")
        projects = self.get_number("products")
        bugs = self.get_number("bugs")
        return (users, projects, bugs)

    def get_number(self, table):
        '''
        Get total num of the table
        '''
        num = 0
        sql = "SELECT count(*) FROM %s" % table
        num = self.fetch_data(sql)[0][0]
        return num

    def get_bug_hunter(self, num=10, interval="all"):
        '''
        Get top num of bug summiters
        '''
        user_list = None
        try:
            sql = "SELECT login_name, count(bug_id) as nr \
                   FROM bugs INNER JOIN profiles ON reporter=profiles.userid \
                   INNER JOIN products ON bugs.product_id = products.id \
                   group by login_name order by nr DESC limit %d" % num
            self.cursor.execute(sql)
            user_list = self.cursor.fetchall()
            #print user_list
        except Exception as e:
            print "Error: unable to fetch data", e
            self.conn.close()
            sys.exit(1)
        return user_list

    def get_bug_killer(self, num=10, interval="all"):
        '''
        Get top num of bug summiters
        '''
        user_list = None
        try:
            sql = "SELECT login_name, count(bug_id) as nr \
                   FROM bugs INNER JOIN profiles ON assigned_to=profiles.userid \
                   INNER JOIN products ON bugs.product_id = products.id \
                   WHERE bug_status  = 'RESOLVED' AND resolution = 'FIXED' \
                   group by login_name order by nr DESC limit %d" % num
            self.cursor.execute(sql)
            user_list = self.cursor.fetchall()
            #print user_list
        except Exception as e:
            print "Error: unable to fetch data", e
            self.conn.close()
            sys.exit(1)
        return user_list

    def get_bugs_status(self, interval="m"):
        '''
        Get bugs statics status
        could be totally, per year, per month, per day
        the bugs inflow
        not decide if include severity or not
        '''
        #TODO draw graph
        bugs_status_list = {}

        now = datetime.datetime.now()
        print "Current year is %d" % (now.year)

        sql = "select YEAR(min(creation_ts)) from bugs"
        year_begin = self.fetch_data(sql)[0][0]
        print "The earlist year is ", year_begin

        for year in range(year_begin, now.year+1):
            sql = "select MONTH(creation_ts), count(bug_id) from bugs \
                   WHERE YEAR(creation_ts)=%d GROUP BY MONTH(creation_ts)" % year
            bugs_status_list[str(year)] = self.fetch_data(sql)

        #for key in bugs_status_list:
        #    print key, bugs_status_list[key]

        sql = "SELECT AVG(DATEDIFF(delta_ts, creation_ts)) FROM bugs \
               WHERE bug_status  = 'RESOLVED' AND resolution = 'FIXED'"
        ave = self.fetch_data(sql)[0][0]
        print "The average bug period is %d days" % ave

        sql = "SELECT MAX(DATEDIFF(delta_ts, creation_ts)) FROM bugs \
               WHERE bug_status  = 'RESOLVED' AND resolution = 'FIXED'"
        lgt = self.fetch_data(sql)[0][0]
        print "The longest bug period is %d days" % lgt
        return ave, lgt, bugs_status_list


    def fetch_data(self, sql):
        '''
        Fetch data from database
        '''
        data = 0
        try:
            self.cursor.execute(sql)
            data = self.cursor.fetchall()
            #print data
        except Exception as e:
            print "Error: unable to fetch data", e
            self.conn.close()
            sys.exit(1)
        return data


    def get_user_status(self):
        '''
        Get some analysis of the users
        dont know how to do yet
        '''
        user_status_list = []

        sql = "select login_name, count(who) as nr from bugs_activity \
               inner join profiles on who=profiles.userid \
               group by who order by nr DESC"
        user_status_list = self.fetch_data(sql)

        print "The most active user is: ", user_status_list[0][0]

        sql = "select AVG(count) from (select who, count(who) as count \
               from bugs_activity group by who) q1"
        ave = self.fetch_data(sql)[0][0]
        print "The average number of activities of all users is ", ave

        sql = "select count(who) from (select who, count(who) as count \
               from bugs_activity group by who) q1 where count>100"
        act = self.fetch_data(sql)[0][0]
        print "The number of quite active user is ", act

        sql = "select count(who) from (select who, count(who) as count \
               from bugs_activity group by who) q1 where count<20"
        inact = self.fetch_data(sql)[0][0]
        print "The number of not that active user is ", inact

        new_users = []
        sql = "select count(userid) as 'new users', YEAR(profiles_when) as 'YEAR' \
               from profiles_activity where fieldid = 30 group by YEAR(profiles_when)"
        new_users = self.fetch_data(sql)
        return (user_status_list, new_users)

def main(argv):
    '''
    test bugDM class
    usage: bugDM.py <bugzilla localconfig file>
    '''
    fn = 'localconfig'
    if argv:
        fn = argv[0]
    if not os.path.isfile(fn):
        print __doc__
        sys.exit(1)

    #try:
    if 1:
        fo = open(fn, 'r')
        bugdm = bugDM(fo)
        print "Totally %d users, %d projects and %d bugs" % bugdm.get_summary()
        print "=================================================================\n\n"

        num = 10
        print "             Top %d bug hunters           | num of submitted bugs" % num
        print "================================================================="
        top_hunters = bugdm.get_bug_hunter()
        for item in top_hunters:
            print "%40s | %d" %(item[0], item[1])
        print "=================================================================\n\n"

        print "             Top %d bug killers           | num of resolved bugs" % num
        print "================================================================="
        top_hunters = bugdm.get_bug_killer()
        for item in top_hunters:
            print "%40s | %d" %(item[0], item[1])
        print "=================================================================\n\n"

        fix_time_mean, fix_time_long, bugs_status_list = bugdm.get_bugs_status()

        print "=================================================================\n\n"
        user_status_list, new_users = bugdm.get_user_status()
        print "             new users           |  year"
        print "================================================================="
        for item in new_users:
            print "%30d  | %d" %(item[0], item[1])
        print "=================================================================\n\n"


        bugdm.db_disconn()
        fo.close()
    #except Exception as e:
    #    print "error happens", e
        sys.exit(1)

    # test

if __name__ == '__main__':
    main(sys.argv[1:])
