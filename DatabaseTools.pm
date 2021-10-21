##############################################################
#
# DB.pm 
# A series of DB functions of use with Chris Doten's 
# Diplomacy adjudicator
# Begun 5.18.01 Last modified 5.18.01
# Copyright (c)2001 Chris Doten
#
##############################################################

package DB;
use DBI;
use Carp;
use strict;

##############################################################
# Connect
##############################################################

sub Connect {

        my ( $database, $dbUser, $dbPassword ) = @_;

        # Open a connection to the database to get the info
        my $dbh = DBI->connect( "DBI:mysql:$database", $dbUser, $dbPassword ) 
		or croak "Can't connect to DB $database!\n";

	return $dbh;

} # End Connect


##############################################################
# Disconnect
##############################################################

sub Disconnect {

        my $dbh = shift;

        $dbh->disconnect();
	return 1;

} # End Disconnect


##############################################################################
# FetchCell
##############################################################################

sub FetchCell{

        my ( $query, $cellName, $dbh ) = @_;

        unless( ( $query and $dbh ) and $cellName ) {
                croak ( "FetchCell not passed enough info!" );
        }

        my $sth = $dbh->prepare( $query );
        if ( !$sth ) {
                croak "Error in $query:" . $dbh->errstr . "\n";
        }
        if ( !$sth->execute ) {
                croak "Error in execution of $query:" . $sth->errstr . "\n";
        }

        my $row = $sth->fetchrow_hashref;
        my $cell = $row->{$cellName};

        return $cell;

} # End FetchCell


##############################################################################
# FetchRow
##############################################################################

sub FetchRow{

        my ( $query, $dbh ) = @_;

        unless( $query and $dbh ) {
                croak ( "FetchRow not passed enough info!" );
        }

        my $sth = $dbh->prepare( $query );
        if ( !$sth ) {
                croak "Error in $query:" . $dbh->errstr . "\n";
        }
        if ( !$sth->execute ) {
                croak "Error in execution of $query:" . $sth->errstr . "\n";
        }

        my $row = $sth->fetchrow_hashref;

        return $row;

} # End FetchRow


##############################################################################
# FetchHandle
##############################################################################

sub FetchHandle {

        my ( $query, $dbh ) = @_;

        unless( $query and $dbh ) {
                croak ( "DBFetchHandle not passed enough info!" );
        }

        my $sth = $dbh->prepare( $query );
        if ( !$sth ) {
                croak "Error in $query:" . $dbh->errstr . "\n";
        }
        if ( !$sth->execute ) {
                croak "Error in execution of $query:" . $sth->errstr . "\n";
        }

        return $sth;

} # End FetchHandle

#############################################################################
# Process
#############################################################################

sub Process {

	my ( $query, $dbh, $doNotWriteToDB ) = @_;

	my $sth;
 
	unless( $query and $dbh ) {
		croak ( "Process not passed enough info: query=$query, dbh=$dbh\n" );
	}

        unless( $doNotWriteToDB ) {

		$sth = $dbh->prepare( $query );
        	if ( !$sth ) {
        		croak "Error in $query:" . $dbh->errstr . "\n";
        	}
        	if ( !$sth->execute ) {
        		croak "Error in execution of $query:" . $sth->errstr . "\n";
        	}
	} else {
       		print "Normally I would now $query.\n";
       	}

	return $sth;

} # End Process

return 1;
