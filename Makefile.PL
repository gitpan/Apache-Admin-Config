use ExtUtils::MakeMaker;

WriteMakefile
(
    'NAME'		=> 'Apache::Admin::Config',
    'DISTNAME'          => 'Apache-Admin-Config',
    'VERSION_FROM'	=> 'lib/Apache/Admin/Config.pm', # finds $VERSION
    'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
    'PMLIBDIRS'         => ['lib'],
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/Apache/Admin/Config.pm', # retrieve abstract from module
       AUTHOR     => 'Olivier Poitrey <rs@rhapsodyk.net>') : ()),
);
