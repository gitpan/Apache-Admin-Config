use strict;
use Test;
plan test => 5;

use Apache::Admin::Config;
ok(1);

my $apache = new Apache::Admin::Config ('t/httpd.conf-dist');
ok(defined $apache);

my @dirlist = $apache->directive;
ok(@dirlist, 88);

my @dirvals = $apache->directive('browsermatch');
ok(@dirvals, 5);

my $obj = $dirvals[0];
ok(defined $obj);
