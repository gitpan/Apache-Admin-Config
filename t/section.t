package Test::AA::section;

BEGIN
{
    use strict;
    use Test;
    plan test => 7;
}

use Apache::Admin::Config;
ok(1);

my $apache = new Apache::Admin::Config ('t/httpd.conf-dist');
ok(defined $apache);

my $seclist = $apache->section;
ok(@$seclist, 3);

my $secvals = $apache->section($seclist->[0]);
ok(@$secvals, 4);

my $obj = $apache->section($seclist->[0], $secvals->[0]);
ok(defined $obj);
ok($obj->value, $secvals->[0]);

my $subseclist = $obj->section;
ok(@$seclist, 3);
