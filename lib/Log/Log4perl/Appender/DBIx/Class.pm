package Log::Log4perl::Appender::DBIx::Class;
use strict;

use Carp;

use base qw(Log::Log4perl::Appender);

sub new {
    my $class = shift;

    my $self = { @_ };

    die 'Must suppy a schema' unless(exists($self->{schema}));

    $self->{class} = 'Log' unless(exists($self->{class}));
    $self->{category_column} = 'category' unless(exists($self->{category_column}));
    $self->{level_column} = 'level' unless(exists($self->{level_column}));
    $self->{message_column} = 'message' unless(exists($self->{message_column}));

    return bless($self, $class);
}

sub log {
    my $self = shift;
    my %p = @_;

    #%p is
    #    { name    => $appender_name,
    #      level   => loglevel
    #      message => $message,
    #      log4p_category => $category,
    #      log4p_level  => $level,);
    #    },

    my $rs = $self->{schema}->resultset($self->{class});
    unless(defined($rs)) {
        carp('Could not find resultset for "'.$self->{class}.'"');
        return;
    }

    my $message = $p{message};
    chomp($message);

    my $row = $rs->new_result({
        $self->{message_column} => $message,
        $self->{category_column} => $p{log4p_category},
        $self->{level_column} => $p{log4p_level}
    });

    if($self->{datetime_column}) {
        my $accessor = $self->{datetime_column};
        $row->$accessor($self->{datetime_subref}->());
    }

    $row->insert;
}

1;

__END__

=head1 NAME

Log::Log4perl::Appender::DBI - implements appending to a DB

=head1 SYNOPSIS

    my $config = <<'EOT';
    log4j.category = WARN, DBAppndr
    log4j.appender.DBAppndr             = Log::Log4perl::Appender::DBI
    log4j.appender.DBAppndr.datasource  = DBI:CSV:f_dir=t/tmp
    log4j.appender.DBAppndr.username    = bobjones
    log4j.appender.DBAppndr.password    = 12345
    log4j.appender.DBAppndr.sql         = \
       insert into log4perltest           \
       (loglevel, custid, category, message, ipaddr) \
       values (?,?,?,?,?)
    log4j.appender.DBAppndr.params.1 = %p    
                                  #2 is custid from the log() call
    log4j.appender.DBAppndr.params.3 = %c
                                  #4 is the message from log()
                                  #5 is ipaddr from log()
        
    
    log4j.appender.DBAppndr.usePreparedStmt = 1
     #--or--
    log4j.appender.DBAppndr.bufferSize = 2
    
    #just pass through the array of message items in the log statement 
    log4j.appender.DBAppndr.layout    = Log::Log4perl::Layout::NoopLayout
    log4j.appender.DBAppndr.warp_message = 0
    
    
    $logger->warn( $custid, 'big problem!!', $ip_addr );


=head1 CAVEAT

This is a very young module and there are a lot of variations
in setups with different databases and connection methods,
so make sure you test thoroughly!  Any feedback is welcome!

=head1 DESCRIPTION

This is a specialized Log::Dispatch object customized to work with
log4perl and its abilities, originally based on Log::Dispatch::DBI 
by Tatsuhiko Miyagawa but with heavy modifications.

It is an attempted compromise between what Log::Dispatch::DBI was 
doing and what log4j's JDBCAppender does.  Note the log4j docs say
the JDBCAppender "is very likely to be completely replaced in the future."

The simplest usage is this:

    log4j.category = WARN, DBAppndr
    log4j.appender.DBAppndr            = Log::Log4perl::Appender::DBI
    log4j.appender.DBAppndr.datasource = DBI:CSV:f_dir=t/tmp
    log4j.appender.DBAppndr.username   = bobjones
    log4j.appender.DBAppndr.password   = 12345
    log4j.appender.DBAppndr.sql        = \
       INSERT INTO logtbl                \
          (loglevel, message)            \
          VALUES ('%c','%m')
    
    log4j.appender.DBAppndr.layout    = Log::Log4perl::Layout::PatternLayout


    $logger->fatal('fatal message');
    $logger->warn('warning message');

    ===============================
    |FATAL|fatal message          |
    |WARN |warning message        |
    ===============================


But the downsides to that usage are:

=over 4

=item * 

You'd better be darn sure there are not quotes in your log message, or your
insert could have unforseen consequences!  This is a very insecure way to
handle database inserts, using place holders and bind values is much better, 
keep reading. (Note that the log4j docs warn "Be careful of quotes in your 
messages!") B<*>.

=item *

It's not terribly high-performance, a statement is created and executed
for each log call.

=item *

The only run-time parameter you get is the %m message, in reality
you probably want to log specific data in specific table columns.

=back

So let's try using placeholders, and tell the logger to create a
prepared statement handle at the beginning and just reuse it 
(just like Log::Dispatch::DBI does)


    log4j.appender.DBAppndr.sql = \
       INSERT INTO logtbl \
          (custid, loglevel, message) \
          VALUES (?,?,?)

    #---------------------------------------------------
    #now the bind values:
                                  #1 is the custid
    log4j.appender.DBAppndr.params.2 = %p    
                                  #3 is the message
    #---------------------------------------------------

    log4j.appender.DBAppndr.layout    = Log::Log4perl::Layout::NoopLayout
    log4j.appender.DBAppndr.warp_message = 0
    
    log4j.appender.DBAppndr.usePreparedStmt = 1
    
    
    $logger->warn( 1234, 'warning message' ); 


Now see how we're using the '?' placeholders in our statement?  This
means we don't have to worry about messages that look like 

    invalid input: 1234';drop table custid;

fubaring our database!

Normally a list of things in the logging statement gets concatenated into 
a single string, but setting C<warp_message> to 0 and using the 
NoopLayout means that in

    $logger->warn( 1234, 'warning message', 'bgates' );

the individual list values will still be available for the DBI appender later 
on.  (If C<warp_message> is not set to 0, the default behavior is to
join the list elements into a single string.   If PatternLayout or SimpleLayout
are used, their attempt to C<render()> your layout will result in something 
like "ARRAY(0x841d8dc)" in your logs.  More information on C<warp_message>
is in Log::Log4perl::Appender.)

In your insert SQL you can mix up '?' placeholders with conversion specifiers 
(%c, %p, etc) as you see fit--the logger will match the question marks to 
params you've defined in the config file and populate the rest with values 
from your list.  If there are more '?' placeholders than there are values in 
your message, it will use undef for the rest.  For instance, 

	log4j.appender.DBAppndr.sql =                 \
	   insert into log4perltest                   \
	   (loglevel, message, datestr, subpoena_id)\
	   values (?,?,?,?)
	log4j.appender.DBAppndr.params.1 = %p
	log4j.appender.DBAppndr.params.3 = %d

	log4j.appender.DBAppndr.warp_message=0


	$logger->info('arrest him!', $subpoena_id);

results in the first '?' placholder being bound to %p, the second to
"arrest him!", the third to the date from "%d", and the fourth to your
$subpoenaid.  If you forget the $subpoena_id and just log

	$logger->info('arrest him!');

then you just get undef in the fourth column.


If the logger statement is also being handled by other non-DBI appenders,
they will just join the list into a string, joined with 
C<$Log::Log4perl::JOIN_MSG_ARRAY_CHAR> (default is an empty string).

And see the C<usePreparedStmt>?  That creates a statement handle when
the logger object is created and just reuses it.  That, however, may
be problematic for long-running processes like webservers, in which case
you can use this parameter instead

    log4j.appender.DBAppndr.bufferSize=2

This copies log4j's JDBCAppender's behavior, it saves up that many
log statements and writes them all out at once.  If your INSERT
statement uses only ? placeholders and no %x conversion specifiers
it should be quite efficient because the logger can re-use the
same statement handle for the inserts.

If the program ends while the buffer is only partly full, the DESTROY
block should flush the remaining statements, if the DESTROY block
runs of course.

* I<As I was writing this, Danko Mannhaupt was coming out with his
improved log4j JDBCAppender (http://www.mannhaupt.com/danko/projects/)
which overcomes many of the drawbacks of the original JDBCAppender.>

=head1 DESCRIPTION 2

Or another way to say the same thing:

The idea is that if you're logging to a database table, you probably
want specific parts of your log information in certain columns.  To this
end, you pass an list to the log statement, like 

    $logger->warn('big problem!!',$userid,$subpoena_nr,$ip_addr);

and the array members drop into the positions defined by the placeholders
in your SQL statement. You can also define information in the config
file like

    log4j.appender.DBAppndr.params.2 = %p    

in which case those numbered placeholders will be filled in with
the specified values, and the rest of the placeholders will be
filled in with the values from your log statement's array.

=head1 MISC PARAMETERS


=over 4

=item usePreparedStmt

See above.

=item warp_message

see Log::Log4perl::Appender

=item max_col_size

If you're used to just throwing debugging messages like huge stacktraces
into your logger, some databases (Sybase's DBD!!) may suprise you 
by choking on data size limitations.  Normally, the data would
just be truncated to fit in the column, but Sybases's DBD it turns out
maxes out at 255 characters.  Use this parameter in such a situation
to truncate long messages before they get to the INSERT statement.

=back

=head1 CHANGING DBH CONNECTIONS (POOLING)

If you want to get your dbh from some place in particular, like
maybe a pool, subclass and override _init() and/or create_statement(), 
for instance 

    sub _init {
        ; #no-op, no pooling at this level
    }
    sub create_statement {
        my ($self, $stmt) = @_;
    
        $stmt || croak "Log4perl: sql not set in ".__PACKAGE__;
    
        return My::Connections->getConnection->prepare($stmt) 
            || croak "Log4perl: DBI->prepare failed $DBI::errstr\n$stmt";
    }


=head1 LIFE OF CONNECTIONS

If you're using C<log4j.appender.DBAppndr.usePreparedStmt>
this module creates an sth when it starts and keeps it for the life
of the program.  For long-running processes (e.g. mod_perl), connections
might go stale, but if C<Log::Log4perl::Appender::DBI> tries to write
a message and figures out that the DB connection is no longer working
(using DBI's ping method), it will reconnect.

The reconnection process can be controlled by two parameters,
C<reconnect_attempts> and C<reconnect_sleep>. C<reconnect_attempts>
specifies the number of reconnections attempts the DBI appender 
performs until it gives up and dies. C<reconnect_sleep> is the
time between reconnection attempts, measured in seconds.
C<reconnect_attempts> defaults to 1,  C<reconnect_sleep> to 0.

Alternatively, use C<Apache::DBI> or C<Apache::DBI::Cache> and read
CHANGING DB CONNECTIONS above.

Note that C<Log::Log4perl::Appender::DBI> holds one connection open
for every appender, which might be too many.

=head1 AUTHOR

Kevin Goess <cpan@goess.org> December, 2002

=head1 SEE ALSO

L<Log::Dispatch::DBI>

L<Log::Log4perl::JavaMap::JDBCAppender>

=cut