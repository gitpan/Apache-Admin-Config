package Test::AA::handle;

BEGIN
{
    use strict;
    use Test;
    plan test => 9;
}

use Apache::Admin::Config;
ok(1);

open(HTTPD_CONF, 't/httpd.conf-dist');
ok(HTTPD_CONF);

my $apache = new Apache::Admin::Config (\*HTTPD_CONF);
ok(defined $apache);

my @dirlist = $apache->directive;
ok(@dirlist, 88);

my @dirvals = $apache->directive('browsermatch');
ok(@dirvals, 5);

my $obj = $dirvals[0];
ok(defined $obj);
ok($obj->value, $dirvals[0]);

open(HTTPD_TMP, ">/tmp/httpd.conf-$$-aac");
ok(HTTPD_TMP);

ok($apache->save(\*HTTPD_TMP));

unlink("/tmp/httpd.conf-$$-aac");
