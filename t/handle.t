use strict;
use Test;
plan test => 8;

use Apache::Admin::Config;
ok(1);

open(HTTPD_CONF, 't/httpd.conf-dist');
ok(fileno HTTPD_CONF);

my $apache = new Apache::Admin::Config (\*HTTPD_CONF);
ok(defined $apache);

my @dirlist = $apache->directive;
ok(@dirlist, 88);

my @dirvals = $apache->directive('browsermatch');
ok(@dirvals, 5);

my $obj = $dirvals[0];
ok(defined $obj);

open(HTTPD_TMP, ">/tmp/httpd.conf-$$-aac");
ok(fileno HTTPD_TMP);

ok($apache->save(\*HTTPD_TMP));

unlink("/tmp/httpd.conf-$$-aac");
close(HTTPD_TMP);
close(HTTPD_CONF);
