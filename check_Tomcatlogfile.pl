#!/usr/bin/perl

# This plugin processes a logfile ( -l ) with "%a %t %H %p %U %s %S %D %I %b" pattern and
# report on all time taken entries for last ( -m ) minutes
use strict;
use warnings;

use File::ReadBackwards;
use Date::Manip;
use Monitoring::Plugin;
use POSIX;
use POSIX 'strftime';

use vars qw($VERSION $PROGNAME $verbose $warn $critical $timeout $result);
$VERSION = '1.0';

# get the base name of this script for use in the examples
use File::Basename;
$PROGNAME = basename($0);

sub parse {
	my $Line=shift;
	my $Ref;
	my $Rest;
	my $R2;
	
	($Ref->{host},$Ref->{date},$Ref->{proto},$Ref->{port},$Ref->{file},$Ref->{code},$Ref->{algo},$Ref->{timeTaken},$Ref->{algo},$Ref->{bytes}) = $Line =~ m,^([^\s]+)\s\[([^\s]+\s[^\s]+)\]\s([^\s]+)\s([^\s]+)\s([^\s]+)\s([^\s]+)\s([^\s]+)\s([^\s]+)\s([^\s]+)\s([^\s]+),;
	
	my @Dsplit=split(/\s+/,$Ref->{date});
	$Ref->{diffgmt}=$Dsplit[1];
	my @Ds2=split(/\:/,$Dsplit[0],2);
	$Ref->{date}=$Ds2[0];
	$Ref->{time}=$Ds2[1];
	#printf("DEBUG: $Ref->{file}\n");
	    return $Ref;
}


# use Nagios::Plugin::Getopt to process the @ARGV command line options:
# --verbose, --help, --usage, --timeout and --host are defined automatically.

my $np = Monitoring::Plugin->new(
	shortname => "ACCESS_STATUS",
	usage => "Usage: %s [ -v|--verbose ] -f|--folderPath=path -p|--prefixlog=access_log -s|--sufixlog=.log -m|--m=minutes " .
	"[ -c|--critical=<threshold>(20)(ms) ] [ -w|--warning=<threshold>(10)(ms) ] ".
	"-r|--resource=file",
	blurb => "Report status summary for the last minutes of an tomcat access log"
);

# Parse arguments and process standard ones (e.g. usage, help, version)
$np->add_arg(
	spec => 'folderpath|f=s',
	help => qq{-f, --folderpath=STRING},
	required => 1,
);
$np->add_arg(
	spec => 'prefixlog|p=s',
	help => qq{-p, --prefixlog=STRING},
	required => 1,
);
$np->add_arg(
	spec => 'sufixlog|s=s',
	help => qq{-s, --sufixlog=STRING},
	required => 1,
);
$np->add_arg(
	spec => 'minutes|m=i',
	help => qq{-m, --minutes=INTEGER},
	default => 5,
);
$np->add_arg(
	spec => 'warning|w=i',
	help => qq{-w, --warning=FLOAT Warn when % failures is above the specified threshold},
	default => 2000,
);
$np->add_arg(
	spec => 'critical|c=i',
	help => qq{-c, --critical=FLOAT Critical when % failures is above the specified threshold},
	default => 3000,
	);
$np->add_arg(
	spec => 'resource|r=s',
	help => qq{-r, --resource=STRING Resource file that is monitored},
	required => 1,
);
$np->getopts;


my $folder_path= $np->opts->folderpath or $np->nagios_die("No folderpath defined");
my $prefix_log= $np->opts->prefixlog or $np->nagios_die("No prefixlog defined");
my $sufix_log= $np->opts->sufixlog or $np->nagios_die("No sufixlog defined");

my $resource= $np->opts->resource or $np->nagios_die("No resource string defined");

my $minutes = $np->opts->minutes;
my $start = DateCalc ("epoch ".time(),"$minutes minutes ago");

#my $start = "2010092012:59:30"; # sample for multiple runs on same file

my $dateFormat = strftime("%Y-%m-%d", localtime);
my $log_file = join "", $folder_path, "/", $prefix_log, $dateFormat, $sufix_log;

my $bytes_served=0;

my $max = 0;
my $totalTime = 0;
my $min = 999999;
my $count = 0;

tie *BW, 'File::ReadBackwards', $log_file or $np->nagios_die("can't read $log_file $!") ;

print STDERR "Opening $log_file\n" if $np->opts->verbose;

# Start looping backward thru logfile
my $prior_logdate=""; # Set prior lines' logdate to nothing

while (<BW>) 
{
	my $line_ref = parse($_);
    
	# skip tests from load-balancers
	# next if ($line_ref->{host} =~ m/^192\.168\.30\.1/);

	# each 1000 lines prints a line
	if ( ( $count %1000 == 0 ) and $np->opts->verbose) 
	{
		print STDERR "line: $count\n";
		print $_;
	}

	my $logdate = $line_ref->{date} . " " . $line_ref->{time};
	
	if ( $logdate eq $prior_logdate || ParseDate($logdate) gt $start ) 
	{
		$prior_logdate = $logdate;
		
		if ($line_ref->{file} eq $resource)
		{
			$bytes_served += $line_ref->{bytes} if ($line_ref->{bytes} ne '-');
			
			if ($max < $line_ref->{timeTaken}) 
			{
				$max = $line_ref->{timeTaken};
			}
			
			if ($min > $line_ref->{timeTaken}) 
			{
				$min = $line_ref->{timeTaken};
			}
			
			$totalTime += $line_ref->{timeTaken};
			$count++;
		}
	} 
	else 
	{
		last; # break out of <BW>;
	}
}

my $averageTime = 0;
if ( $count > 0) 
{
    # Tomcat logs in miliseconds (Apache HTTP server logs in microseconds)
	$max = ceil($max);
	$min = ceil($min);
	$totalTime = ceil($totalTime);
	$averageTime = $totalTime / $count;
}
else 
{
	$min = 0;
}

$np->add_perfdata(
	label => 'Count',
	value => $count,
);

$np->add_perfdata(
	label => 'Average',
	value => int($averageTime),
);

$np->add_perfdata(
	label => 'Max',
	value => int($max),
);

$np->add_perfdata(
	label => 'Min',
	value => int($min),
);

$np->add_perfdata(
	label => 'TotalTime',
	value => int($totalTime),
);

$np->add_perfdata(
	label => 'BytesServed',
	uom => 'kB',
	value => int($bytes_served/1024),
);

# Threshold methods 
my $return_code = 0;
$return_code = $np->check_threshold(
     check => int($max),
     warning => $np->opts->warning,
     critical => $np->opts->critical,
   );
   
my $message = sprintf("$resource requested $count times, with max time: $max");
$np->nagios_exit( $return_code, "Threshold check failed: $message" ) if $return_code != OK;

if ($count > 0)
{
        $np->nagios_exit( $return_code, $message );
}
else 
{
        $np->nagios_exit ( $return_code, "Found 0 requests to resource: $resource");
}
