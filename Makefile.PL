use inc::Module::Install;

name     'Log-Log4perl-Appender-DBIx-Class';
all_from 'lib/Log/Log4perl/Appender/DBIx/Class.pm';
author   'Cory G Watson <gphat@cpan.org>';
license  'perl';

build_requires 'Test::More';

requires 'DBIx::Class';
requires 'Log::Log4perl';

WriteAll;

