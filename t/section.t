package Test::AA::section;

BEGIN
{
    use strict;
    use Test;
    plan test => 2;
}

use Apache::Admin::Config;
ok(1);

my $apache = new Apache::Admin::Config ('t/htaccess');
ok(defined $apache);


