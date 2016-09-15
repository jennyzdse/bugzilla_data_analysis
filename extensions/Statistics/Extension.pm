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
use Bugzilla::Util;
use Data::Dumper;

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

    if ($page =~ m{^statistics/search_res\.}) {
        _page_search($vars);
    }
    if ($page =~ m{^statistics/stat\.}) {
        _page_stat($vars);
    }
    if ($page =~ m{^statistics/user_stat\.}) {
        _page_user($vars);
    }
}

sub _page_user {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;
    my $user_id = 1;
    if ($input->{'user_id'} != "") {
	    $user_id = $input->{'user_id'};
	    trick_taint($user_id);
    }
    ($vars->{'user'}) = $dbh->selectrow_hashref('SELECT login_name FROM profiles WHERE userid = ?', undef, $user_id);

    $vars->{'fixed'} = $dbh->selectrow_hashref(
			     'SELECT count(bug_id) AS nr
				FROM bugs
			       WHERE assigned_to = ? 
				 AND bug_status  = \'RESOLVED\'
				 AND resolution = \'FIXED\'',
				 undef, $user_id);
    $vars->{'submitted'} = $dbh->selectrow_hashref(
			     'SELECT count(bug_id) AS nr
				FROM bugs
			       WHERE reporter = ?',
				 undef, $user_id);
    $vars->{'fix_days'} =
        $dbh->selectrow_hashref('SELECT AVG(DATEDIFF(delta_ts, creation_ts)) AS avg,
                                         MAX(DATEDIFF(delta_ts, creation_ts)) AS max,
                                         MIN(DATEDIFF(delta_ts, creation_ts)) AS min
				    FROM bugs
				   WHERE assigned_to = ? 
				     AND bug_status = \'RESOLVED\'
				     AND resolution = \'FIXED\'',
                                  undef, $user_id);

    $vars->{'products'} = $dbh->selectall_arrayref(
			     'SELECT product_id, products.name, COUNT(bug_id) AS nr
				FROM bugs
			  INNER JOIN products ON bugs.product_id = products.id
			       WHERE reporter = ?
				  OR assigned_to = ?
		            GROUP BY product_id',
			  {Slice=>{}}, $user_id, $user_id);
}


sub _page_stat {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;
    my $prd = 1;
    my $prdN = 1;
    my $eq  = '!=';
    $vars->{'prd_name'} = "All Products";
    if ($input->{'product_id'} != "") {
	    $prd = $input->{'product_id'};
	    $eq  = '=';
	    trick_taint($prd);
	    $vars->{'prd_name'} =
		    $dbh->selectrow_array('SELECT name FROM products WHERE id = ?', undef, $prd);
    }
    

    $vars->{'years'} =
        $dbh->selectall_arrayref('SELECT q1.year, new_users, new_bugs
                                  FROM (
					SELECT COUNT(userid) AS new_users, YEAR(profiles_when) AS year
					FROM profiles_activity
					WHERE fieldid = 30
                                        GROUP BY year) q1
				  INNER JOIN (
					SELECT YEAR(creation_ts) AS year, COUNT(bug_id) AS new_bugs
					FROM bugs
					WHERE product_id ' . $eq . ' ? 
					GROUP BY year) q2
				  ON q1.year = q2.year',
                                {Slice=>{}}, $prd);
    $vars->{'fixers'} =
        $dbh->selectall_arrayref('SELECT login_name, profiles.userid AS id, count(bug_id) AS nr
				    FROM bugs
			      INNER JOIN profiles
				      ON assigned_to = profiles.userid
				   WHERE product_id ' . $eq . ' ? 
				     AND bug_status  = \'RESOLVED\'
				     AND resolution = \'FIXED\'
				GROUP BY login_name
				ORDER BY nr DESC
				   LIMIT 10',
                                  {Slice=>{}}, $prd);

    $vars->{'submitters'} =
        $dbh->selectall_arrayref('SELECT login_name, profiles.userid AS id, count(bug_id) AS nr
				    FROM bugs
			      INNER JOIN profiles
				      ON reporter = profiles.userid
				   WHERE product_id ' . $eq . ' ? 
				GROUP BY login_name
				ORDER BY nr DESC
				   LIMIT 10',
                                  {Slice=>{}}, $prd);

    $vars->{'fix_days'} =
        $dbh->selectall_arrayref('SELECT AVG(DATEDIFF(delta_ts, creation_ts)) AS avg,
                                         MAX(DATEDIFF(delta_ts, creation_ts)) AS max,
                                         MIN(DATEDIFF(delta_ts, creation_ts)) AS min
				    FROM bugs
				   WHERE product_id ' . $eq . ' ? 
				     AND bug_status = \'RESOLVED\'
				     AND resolution = \'FIXED\'',
                                  {Slice=>{}}, $prd);

    $vars->{'last30days'} =
        $dbh->selectall_arrayref('SELECT bug_status,COUNT(bug_id) AS count
				    FROM bugs
				   WHERE product_id ' . $eq . ' ? 
				   AND   bugs.creation_ts > CURDATE() - INTERVAL 60 DAY
				GROUP BY bug_status',
				{Slice=>{}}, $prd);

    $vars->{'products'} =
        $dbh->selectall_arrayref("SELECT product_id, products.name, count(bug_id) as count
				    FROM bugs
			      INNER JOIN products
				      ON bugs.product_id = products.id
				   GROUP BY product_id
				   ORDER BY count",
				{Slice=>{}});
}

sub _page_search {
    my ($vars) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;
    my $query = "%a%";
    my $tmp = $input->{'query'};
    $query = "%$tmp%";
    trick_taint($query);

    $vars->{'users'} = $dbh->selectall_arrayref(
		    'SELECT profiles.realname AS name, profiles.userid AS id, COUNT(bug_id) AS nr
		    FROM bugs
		    INNER JOIN profiles ON  assigned_to = profiles.userid
		    WHERE profiles.login_name like ?
		    OR    profiles.realname like ?
		    AND bug_status  = \'RESOLVED\'
		    AND resolution = \'FIXED\'
		    GROUP BY profiles.realname
		    ORDER BY nr',
		    {Slice=>{}}, $query, $query);

    $vars->{'products'} = $dbh->selectall_arrayref(
			     'SELECT product_id, products.name, COUNT(bug_id) AS nr
				FROM bugs
			  INNER JOIN products ON bugs.product_id = products.id
			       WHERE products.name like ?
		            GROUP BY product_id',
			  {Slice=>{}}, $query);
}




__PACKAGE__->NAME;
