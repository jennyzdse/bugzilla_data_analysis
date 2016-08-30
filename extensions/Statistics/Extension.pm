# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Statistics;

use 5.10.1;
use strict;
use warnings;

use parent qw(Bugzilla::Extension);

# This code for this is in ../extensions/Statistics/lib/Util.pm
use Bugzilla::Extension::Statistics::Util;

our $VERSION = '0.01';

# See the documentation of Bugzilla::Hook ("perldoc Bugzilla::Hook" 
# in the bugzilla directory) for a list of all available hooks.
sub install_update_db {
    my ($self, $args) = @_;

}

#########
# Pages #
#########

sub page_before_template {
    my ($self, $args) = @_;
    my $page = $args->{page_id};
    my $vars = $args->{vars};

    if ($page =~ m{^statistics/topfixers\.}) {
        _page_topfixers($vars);
    }
    if ($page =~ m{^statistics/anual\.}) {
        _page_anual($vars);
    }
    if ($page =~ m{^statistics/stat\.}) {
        _page_stat($vars);
    }
}

sub _page_topfixers {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;

    $vars->{'users'} =
        $dbh->selectall_arrayref('SELECT login_name, count(bug_id) AS nr
				    FROM bugs
			      INNER JOIN profiles
				      ON assigned_to = profiles.userid
				   WHERE bug_status  = \'RESOLVED\'
				     AND resolution = \'FIXED\'
				GROUP BY login_name
				ORDER BY nr DESC
				   LIMIT 10',
                                  {Slice=>{}});
}

sub _page_anual {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;

    $vars->{'years'} =
        $dbh->selectall_arrayref('SELECT q1.year,new_users,new_bugs
                                  FROM (
					SELECT COUNT(userid) AS new_users, YEAR(profiles_when) AS year
					FROM profiles_activity
					WHERE fieldid = 30
                                        GROUP BY year) q1
				  INNER JOIN (
					SELECT YEAR(creation_ts) AS year, COUNT(bug_id) AS new_bugs
					FROM bugs
					GROUP BY year) q2
				  ON q1.year = q2.year',
                                {Slice=>{}});

}

sub _page_stat {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;

    $vars->{'years'} =
        $dbh->selectall_arrayref('SELECT q1.year,new_users,new_bugs
                                  FROM (
					SELECT COUNT(userid) AS new_users, YEAR(profiles_when) AS year
					FROM profiles_activity
					WHERE fieldid = 30
                                        GROUP BY year) q1
				  INNER JOIN (
					SELECT YEAR(creation_ts) AS year, COUNT(bug_id) AS new_bugs
					FROM bugs
					GROUP BY year) q2
				  ON q1.year = q2.year',
                                {Slice=>{}});
    $vars->{'fixers'} =
        $dbh->selectall_arrayref('SELECT login_name, count(bug_id) AS nr
				    FROM bugs
			      INNER JOIN profiles
				      ON assigned_to = profiles.userid
				   WHERE bug_status  = \'RESOLVED\'
				     AND resolution = \'FIXED\'
				GROUP BY login_name
				ORDER BY nr DESC
				   LIMIT 10',
                                  {Slice=>{}});

    $vars->{'submitters'} =
        $dbh->selectall_arrayref('SELECT login_name, count(bug_id) AS nr
				    FROM bugs
			      INNER JOIN profiles
				      ON reporter = profiles.userid
				   WHERE bug_status  = \'RESOLVED\'
				     AND resolution = \'FIXED\'
				GROUP BY login_name
				ORDER BY nr DESC
				   LIMIT 10',
                                  {Slice=>{}});

    $vars->{'fix_days'} =
        $dbh->selectall_arrayref('SELECT AVG(DATEDIFF(delta_ts, creation_ts)) AS avg,
                                         MAX(DATEDIFF(delta_ts, creation_ts)) AS max,
                                         MIN(DATEDIFF(delta_ts, creation_ts)) AS min
				    FROM bugs
				   WHERE bug_status = \'RESOLVED\'
			             AND resolution = \'FIXED\'',
                                  {Slice=>{}});

    $vars->{'last30days'} =
        $dbh->selectall_arrayref('SELECT bug_status,COUNT(bug_id) AS count
				    FROM bugs
				   WHERE bugs.creation_ts > CURDATE() - INTERVAL 60 DAY
				GROUP BY bug_status',
				{Slice=>{}});
}


__PACKAGE__->NAME;
