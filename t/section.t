package Test::AA::section;

BEGIN
{
    use strict;
    use Test;
    plan test => 6;
}

use Apache::Admin::Config;
ok(1);

my $apache = new Apache::Admin::Config ('t/httpd.conf-dist');
ok(defined $apache);

my @seclist = $apache->section;
ok(@seclist, 6);

my @secvals = $apache->section('directory');
ok(@secvals, 4);

my $obj = $secvals[0];
ok(defined $obj);
ok($obj->value, $secvals[0]);
