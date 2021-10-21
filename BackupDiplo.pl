#!/usr/bin/perl

# A simple script to backup the Diplomacy system on a daily basis.
# Written by Chris Doten, 6.6.01

use MIME::Lite;

$mysqlDB = 'diplomacy';
$mysqlPassword = 'sysspice';
$emailTo = 'constantinev@hotmail.com';
$emailFrom = 'chris@snowplow.org';

($day, $month, $year) = (localtime)[3,4,5];
$month = $month + 1;
$year = $year + 1900;
$date = "$month-$day-$year";

$rootDir = '/home/chris';
$backupRoot = "$rootDir/backup_diplo";
$backupDir = "diplomacy-$date";
$develDir = "$rootDir/diplomacy";
$backupTar = "diplomacy-$date.tgz";

# Copy the development system, tar it up, and email it off to Microsoft.
# Hmm. the last part seems like a bad idea.

print "cd $develDir\n";
chdir( $develDir );

print "cvs update\n";
system( "cvs update -d" );

print "cp -RL $develDir $backupRoot/$backupDir\n";
system( "cp -RL $develDir $backupRoot/$backupDir" );

 print "cd $backupRoot\n";
chdir( $backupRoot );

print "tar -zcvf $backupTar $backupDir\n";
system( "tar -zcvf $backupTar $backupDir" );

# Save the contents of the database
system( "mysqldump -p$mysqlPassword $mysqlDB >$backupRoot/$backupDir/diplomacy-$date.sql" );


# Then send the stuff off to a safe place
$message = MIME::Lite->new(
                From     =>"$emailFrom",
                To       =>"$emailTo",
                Subject  =>"Diplo backup $date",
                Type     =>'multipart/mixed',
                );

$message->attach( Type =>'TEXT',
                  Data =>"A snapshot of the system as of $date"
                );

$message->attach( Type =>'x-gzip',
                  Path =>"$backupRoot/$backupTar",
                  Disposition => 'attachment'
                );

# Not being used until I figure out if I am routinely going to be making updates
$message->send;
