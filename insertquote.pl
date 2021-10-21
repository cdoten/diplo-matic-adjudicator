#!/usr/bin/perl

# A script to add quotes to the DB

use DBI;
use Carp;
use strict;

my $database = 'diplomacy';
my $dbUser = 'dotenc';
my $dbPassword = 'sysspice';


# Open a connection to the database to get the info
my $dbh = DBI->connect( "DBI:mysql:$database", $dbUser, $dbPassword ) or croak "Can't connect to DB $database!\n";

my $fileName = 'morequotes.txt';

open( QUOTES, $fileName ) or die "Couldn't open $fileName for reading.";

my( $quote, $author, $source, $i ) = 0;


while( <QUOTES> ) {

	if ( /^\s*$/ ) { $i=0; next; }	
	
	chomp( $_ );

	$_ =~ s/\s*^//;
	
	print "I is $i\n";
	if( $i == 0 ) {
		
		$quote = $_;

	} elsif ( $i == 1 ) {

		$author = $_;

	} else  {

		$source = $_;


		AddToDB( $quote, $author, $source );

	}
	

	$i++;
}

sub AddToDB {

	my( $quote, $author, $source ) = @_;

	$quote = $dbh->quote($quote);
	$author = $dbh->quote($author);
	$source = $dbh->quote($source);

	my $query = "INSERT INTO quotes VALUES( NULL, $quote, $author, $source)";

	print "\n\n$query\n\n";

	my $sth = $dbh->prepare( $query );
                if ( !$sth ) {
                        croak "Error in $query:" . $dbh->errstr . "\n";
                }
                if ( !$sth->execute ) {
                        croak "Error in execution of $query:" . $sth->errstr . "
\n";
        }
}

