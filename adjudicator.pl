#!/usr/bin/perl
###########################################################################
#
# Adjudicator.pl
# A fully functional adjudication program for the game Diplomacy*
# 
# Created by Chris Doten
# Begun 10.10.00
# Last modified 7.20.02
#
# All code copyright Chris Doten, 2002. It may not be used for any purpose
# without his express written permission.
#
# *Diplomacy is a registered trademark of Hasboro.
#
###########################################################################

########################################################################
### Included Modules 
########################################################################

#use Diplomacy;
use Carp;
use strict;
#use DatabaseTools;

########################################################################
### Global Variables
########################################################################

# The game ID, used to uniquely identify this instance
my $gameID = undef;

if( scalar( @ARGV ) != 1 ) {
	croak "This program needs to be called with a game ID.\n";
} else {
	
	# Get rid of any ickyness
	$gameID = $ARGV[0];
	$gameID =~ /(\w+)/;
	$gameID = $1;
}

# Database Info
my $database = 'diplomacy';
my $dbUser = 'dotenc';
my $dbPassword = 'sysspice';

# The types of order that can be issued
my $move = 'move';
my $support = 'support';
my $convoy = 'convoy';
my $hold = 'hold';
my $disband = 'disband';
my $build = 'build';

# The special territory for dislodged units
my $limbo = 'limbo';

# The types of phases
my $retreatPhase = 'retreat';
my $movePhase = 'move';
my $adjustPhase = 'adjust';

# The order in which zones of movement should be resolved
my $resolveOrder = ['water','land'];

# A variable to control if the adjudicator writes back to the database
# Set to 1 to prevent execution from doing anything
my $doNotWriteToDB = 0;

##############################################################
### The Outline of Execution
##############################################################

# Get the connection to the DB
my $dbh = DB::Connect( $database, $dbUser, $dbPassword );

# Get everything initialized from the DB
my( $territories, $powers, $units, $mapID, $turn, $phase ) = Setup( $gameID, $dbh );

# Resolve the orders
$units = Execute( $units, $territories, $powers, $phase );

# Report on what transpired
Report( $units );

# Write it out to DB
WriteToDB( $units, $territories, $mapID, $gameID, $turn, $phase, $dbh );

# And we're done with the db
DB::Disconnect( $dbh );

###############################################################
### The Subroutines
###############################################################

##############################################################
# Setup
##############################################################

sub Setup {

	print "<h2>Setting Up Game</h2>\n";

	my ( $gameID, $dbh ) = @_;

	# Pull the phase info from the DB
	my( $turn, $phase ) = LoadGameTurn( $gameID, $dbh );

	# Make sure our phase is legal
	print "<h1>Loading $phase phase turn $turn...</h1>\n";

	unless( ( $phase eq $movePhase ) or ( $phase eq $retreatPhase ) or ( $phase eq $adjustPhase ) ) {
		die "There is not a phase type $phase!";
	}

	# Get the map
	my ( $territories, $mapID ) = LoadTerritories( $gameID, $dbh );

	# Get the players
	my $powers = LoadPowers( $gameID, $territories, $dbh );

	# Get the unit positions and moves
	my $units = LoadOrders( $gameID, $territories, $powers, $turn, $dbh );

	# Display the current status of the game
	ShowOrders( $units, $territories, $powers );
	ShowConfig( $territories, $powers );
	
	# And report back in
	return( $territories, $powers, $units, $mapID, $turn, $phase );

} # End Setup


#############################################################
#  LoadGameTurn
#############################################################
#  LoadGameTurn pulls in the current turn info

sub LoadGameTurn {

	my ( $gameID, $dbh ) = @_;

	my $turnQuery = "SELECT phase, turn FROM games WHERE id='$gameID'";
	my $turnSth = $dbh->prepare( $turnQuery );
       	if (!$turnSth) {
		croak "Error in $turnQuery:" . $dbh->errstr . "\n";
       	}
       	if (!$turnSth->execute) {
		croak "Error in execution of $turnQuery:" . $turnSth->errstr . "\n";
       	}	
	my $turnRef = $turnSth->fetchrow_hashref();

	my $phase = $turnRef->{phase};
	my $turn = $turnRef->{turn};

	unless( $phase ) {

		print "There does not appear to be a game $gameID in the database!\n";
		exit 1;
	}

	return ( $turn, $phase );
	
} # End LoadGameTurn


#############################################################
#  LoadTerritories
#############################################################
#  LoadTerritories reads in the territories for the current game

sub LoadTerritories {
	
	print "<h2>Loading Map</h2>\n";

	my( $gameID, $dbh ) = @_;
	my %territories;
	my %terrAdj;

	if( !$dbh ) {
		croak "no dbh!";
	}

	# Figure out what the map number is

	my $mapQuery = "SELECT map_id FROM games WHERE id='$gameID'";
	my $mapSth = $dbh->prepare( $mapQuery );
       	if (!$mapSth) {
		croak "Error in $mapQuery:" . $dbh->errstr . "\n";
       	}
       	if (!$mapSth->execute) {
		croak "Error in execution of $mapQuery:" . $mapSth->errstr . "\n";
       	}	
	my $gamesRef = $mapSth->fetchrow_hashref();
	my $mapID = $gamesRef->{map_id};

	# Get the list of territories from the DB

	my $query = "SELECT * FROM map_territories WHERE map_id=$mapID";

	my $sth = DB::Process( $query, $dbh, 0 );

	while( my $ref = $sth->fetchrow_hashref  ) {

		# For each of the territories, set the variables.
		my $id = $ref->{'id'};
		my $canonical = $ref->{'canon'};
		my $type = $ref->{'type'};
		my $fullName = $ref->{'name'};
		my $supply = $ref->{'is_supply'};
		
		if( Check::Territory( $canonical, $type, \%territories ) ) {
			$territories{ $canonical } = new Territory( $id, $canonical, $type, $fullName, $supply );
		} else {
			croak "The territory $canonical is not valid.\n";

		}

		# Now go get the territories adjacent to this one.
		my @adjacencies;

		my $query = "SELECT * FROM map_adjacencies WHERE terr_id=$id";
		my $sth = DB::Process( $query, $dbh, 0);
		
		while( my $ref = $sth->fetchrow_hashref() ) {

			my $adjTerrID = $ref->{'adj_terr_id'};
			# Get the canonical name of the territory
			my $query = "SELECT canon FROM map_territories WHERE id=$adjTerrID";
			my $sth = DB::Process( $query, $dbh, 0 );
		
			my $adjTerrRef = $sth->fetchrow_hashref();
			my $adjCanon = $adjTerrRef->{'canon'};

			#print "Here's an adjacent territory: ", $adjCanon, "\n";
	
			push( @adjacencies, $adjCanon );
		}

		# Make sure it hasn't been set already
		if( $terrAdj{ $canonical } ) { 
			croak "Territory $canonical is inthe list more than once!\n"; 
		} else {
			$terrAdj{ $canonical } = \@adjacencies;
		}
	}

	

	my $canon;
	foreach $canon ( sort keys %terrAdj ) {

		my $adjacencies = $terrAdj{ $canon };

		if( Check::Adjacencies( $canon, $adjacencies, \%territories ) ) {
			$territories{ $canon }->adjacencies( @$adjacencies ); 
		} else {
			croak "The adjacencies for $canon were not valid.\n";	
		}
	}

	# Make sure you have that very odd Limbo territory.
	# It is the only ones the adjudicator requires.

	unless( $territories{ $limbo } ) {

		croak "The map $mapID does not have a $limbo territory! The adjudicator cannot function properly.";

	}

	return( \%territories, $mapID );
}


#############################################################
#  LoadPowers
#############################################################
#  LoadPowers pulls in the Great Powers and players for a game

sub LoadPowers {

	print "<h2>Loading the Great Powers</h2>\n";

	my ( $gameID, $territories, $dbh ) = @_;
	my %powers;
	my $playerRef;

	# Pull all the info on the players for the game
	my $query = "SELECT users.full_name as player_name, map_powers.name as 
		     power_name, map_powers.canon as power_canon, 
		     map_powers.adjective_name as power_adjective, 
		     game_players.id as player_id
		     FROM users, game_players, map_powers 
		     WHERE game_id=$gameID
		     AND game_players.power_id=map_powers.id 
		     AND users.id=game_players.user_id";

	my $sth = DB::Process( $query, $dbh, 0 );
 

	while( $playerRef = $sth->fetchrow_hashref() )
	{

		my $playerID = $playerRef->{player_id};
		my $playerName = $playerRef->{player_name};
		my $powerCanon = $playerRef->{power_canon};
		my $powerName = $playerRef->{power_name};
		my $powerAdj = $playerRef->{power_adjective};
	
		if( Check::Power( $powerCanon, \%powers ) ) {
	
       			$powers{ $powerCanon } = new Power( $playerID, $powerName, $playerName, $powerAdj );

		} else {
			croak "The power $powerCanon is not valid.\n";
		}

	}
	
	return( \%powers );
}


#############################################################
#  LoadOrders
#############################################################
#  LoadOrders reads in the current turn of move orders

sub LoadOrders {

	print "<h2>Loading orders submitted</h2>\n";
 
	my( $gameID, $territories, $powers, $turn, $dbh ) = @_;

	my %units;

	# Pull all the info on the units for the game
	my $query = "SELECT game_units.unit_id, game_units.type,
		     game_orders.action, map_territories.canon as position,
		     b.canon as target_terr, game_units.player_id,
		     c.canon as destination_terr, map_powers.canon as power_name
		     FROM game_units, game_orders, map_territories, map_powers,
		     game_players
		     LEFT JOIN map_territories AS b
		     ON game_orders.target_terr_id=b.id
		     LEFT JOIN map_territories AS c 
		     ON game_orders.destination_terr_id=c.id
		     WHERE game_units.unit_id=game_orders.unit_id
		     AND map_territories.id=game_orders.position
		     AND map_powers.id=game_players.power_id
		     AND game_players.id=game_units.player_id
		     AND map_powers.id=game_players.power_id
		     AND game_players.id=game_units.player_id
		     AND game_units.game_id=$gameID
		     AND game_orders.turn=$turn";

	my $sth = DB::Process( $query, $dbh, 0 );

	my $unitRef;
	while( $unitRef = $sth->fetchrow_hashref() ) {

		my $unit;
		my $unitType = $unitRef->{type};
		my $unitID = $unitRef->{unit_id};
		my $territory = $unitRef->{position};
		my $tarTerr = $unitRef->{target_terr};
		my $destTerr = $unitRef->{destination_terr};
		my $power = $unitRef->{power_name};
		my $action = $unitRef->{action};
		my $comments;

		# If they did not submit an action, it defaults to hold.
		unless( $action ) {
			$comments = "In the absence of orders, the $unitType in $territory held in place.\n";
			$action = $hold;

		}

		# If they aren't holding and did not submit a target territory,
		# they reset to hold
		if( !$tarTerr and ( $action ne $hold ) ) {
			$comments = $comments . "The $unitType in $territory did not recieve a target, and is defaulting to a holding action.\n";
			$action = $hold;
		}

		# If they are supporting a move, but it isn't adjacent,
		# they reset to hold.
		# If they are supporting a hold, but it isn't adjacent,
		# they reset to hold.

		if( $action eq $support ) {

			if( $destTerr ) {

				unless( $$territories{ $territory }->isAdjacent( $destTerr ) ) {

					$comments = $comments . "As $territory was not adjacent to $destTerr, the $unitType could not support a move to there. It is defaulting to a holding action.\n";
					$action = $hold;
					$destTerr = undef;
					$tarTerr = undef;
				}
			} else {

				unless( $$territories{ $territory }->isAdjacent( $tarTerr ) ) {
					$comments = $comments . "As $territory was not adjacent to $tarTerr, the $unitType could not support to there. It is defaulting to a holding action.\n";
					$action = $hold;
					$tarTerr = undef;
				}
			}

		}

		# You would think at this point I would check if a move was
		# valid. We actually can't because of convoys; most convoys
		# would appear to be illegal. However, we also can't check for
		# a valid convoy, as they may have not had that order slurped
		# in yet. So that step is checked in GetActionGroups after
		# all orders have been read in.

		# If the fundamentals are not correct, die in flaming death.
	    if( Check::Orders( $power, $unitType, $territory, $action, $tarTerr, $destTerr, \%units, $territories, $powers ) ) {

			$unit = new Unit( $unitID, $power, $unitType, $territory, $action, $tarTerr, $destTerr ); 
		} else {
			croak "The order for $territory was not valid.\n";
		}
	
		# Add in the notes for the owner to read.
		$unit->addComments( $comments );

		my $key = $unit->ID;

		$units{ $key } = $unit;	

		$$territories{ $territory }->occupier( $key ); 

	} 
	
	return \%units;

} # End LoadOrders

######################################################################
# ShowConfig
######################################################################
# ShowConfig prints out the configuration the program has slurped in.

sub ShowConfig {

	#print "ShowConfig!\n";

	my( $territories, $powers ) = @_;

	print "<h2>The Great Powers and their puppetmasters:</h2>\n";

	my $key;
	foreach $key ( sort keys %$powers ) {
		print "\t", $$powers{ $key }->name, " is ruled by the iron fist of ", $$powers{ $key }->player, " (they are ", $$powers{ $key }->adjective, " over there)\n"; 
	}
	print "\n";

	print "The theater in which we are playing:\n";

	foreach $key (sort keys %$territories ) {
		print "\t", $$territories{ $key }->fullName, ", a ";
		print $$territories{ $key }->type, " territory, is adjacent to ",
		join( ", ", $$territories{ $key }->adjacencies ), "\n";
		
	}

	print "\n";

} # End ShowConfig


######################################################################
# ShowOrders
######################################################################
# Does rather as one would expect.

sub ShowOrders {

	#print "ShowOrders!\n";
	
	my( $units, $territories, $powers ) = @_;
	
	print "<h2>Orders for this turn:</h2>\n";

	my $key;
	foreach( sort{ $$units{ $a }->power cmp $$units{ $b }->power }
			keys %$units ) {
		$key = $_;
		print "\t", $$powers{ $$units{ $key }->power }->adjective, " ", $$units{ $key }->type, 
		 " ", $$units{ $key }->location, " ", $$units{ $key }->action, 
		 " ";
		unless( ( $$units{ $key }->action eq $hold ) or ( $$units{ $key }->action eq $disband ) ) {
			unless( $$units{ $key }->destinationTerritory ) {
				print " to ", 
			}
			print $$units{ $key }->targetTerritory;
		 	if( $$units{ $key }->destinationTerritory ) {
				print " to ", $$units{ $key }->destinationTerritory;
			}
		}

		print "\n";
	}
	print "\n";

	print "Territories with units at the start of the turn:\n";
	
	my $territory;
	foreach $territory ( sort keys( %$territories ) ) {

		if( $$territories{ $territory }->occupier() ) {

			my $unitID = $$territories{ $territory }->occupier();
	
			print "\t$territory is held by a ",
			 $$powers{ $$units{ $$territories{ $territory }->occupier() }->power }->adjective, " ", $$units{ $unitID }->type, "\n";
		}
	}
	print "\n";	

	print "Territories under attack!\n";
	my $unit;
	foreach $unit( sort keys( %$units ) ) {

		if( $$units{ $unit }->action eq $move ) {
			print "\t", $$units{ $unit }->targetTerritory, 
			 " is under attack from ", $$units{ $unit }->location,
			 "\n";
		}
	}

} # End ShowOrders


#############################################################
# Execute 
#############################################################
# Execute takes the game information, and finds out what
# happened. It behaves very differently with retreat rounds; 
# that makes for a much simpler concept.
# If this is an adjustment phase, there is no adjudication required.

sub Execute {

	my( $units, $territories, $powers, $phase ) = @_;

	print "<h2>Executing $phase orders for this turn</h2>\n";

	# If it's an adjustment phase, we don't need any of this rigamarole.
	unless( $phase eq $adjustPhase ) {

		# Find out which units are moving
		my( $moving, $supporting, $convoying ) = GetActionGroups( $units );
	
		# Cut supports
		if( $phase eq $movePhase ) {
			CutSupports( $units, $territories, $powers, $moving, $supporting );
		}
	
		# Find out what territories have conflicts
		my $conflicts = GetConflicts( $units, $territories, $moving );

		if( $phase eq $movePhase ) {
	
			# Sum supports
			SumSupports( $units, $territories, $supporting, $moving, $powers );
	
			# Eliminate all but one attacker on all spaces
			Winnow( $units, $territories, $conflicts, $powers );
		
			# Eliminate any convoys that will be disrupted
			CancelConvoys( $units, $territories, $conflicts );
	
			# Move units doing circular position rotation
			MoveLoops( $units, $territories, $moving, $conflicts );
		
			# Resolve all remaining orders
			Resolve( $units, $territories, $powers, $conflicts, 0, $resolveOrder );
	
			# Dispose of the defeated
			Rout( $units );
	
		} elsif( $phase eq $retreatPhase ) {
	
			# This is a retreat round. Any conflicts = disbanded units.
			ResolveRetreats( $units, $conflicts, $territories );
		
		}
	
	}

	# Return what the units think now
	return $units;

} # End Execute


#############################################################################
# GetActionGroups 
#############################################################################
# GetActionGroups groups units into moving and supporting for later processing
# It also does some error checking for valid moves.

sub GetActionGroups {

	my $units = shift;
	my %moving;
	my %supporting;
	my %convoying;

	foreach ( keys %$units ) {
		my $ID = $_;
		my $unit = $$units{ $ID };

		if( $unit->action eq $move ) {
	
			# The unit is going places
			# Check to make sure it's not delusional.
	
			if( $$territories{ $unit->location }->isAdjacent( $unit->targetTerritory ) or ( $unit->location eq $limbo ) ){
				$moving{ $ID } = $unit;	
			} else {

				# It's not adjacent - perhaps the sea route?
				# This is necissary to see if it is actually
				# moving there for summing supports.
	
				# print "I'm checking if this is a valid convoy with the list of territories and units, moving from ", $unit->location, " to ", $unit->targetTerritory, "\n";
				my $canConvoy = Check::Convoy( $territories, $units, $unit->location, $unit->targetTerritory);
	
				if( $canConvoy ) {
	
					$moving{ $ID } = $unit;
					#print "\tThe convoy will succeed - if all goes well. The unit may proceed.\n";
	
				} else {
	
					my $comments = "\tThe unit in " . $unit->location . " was attempting an impossible move to " . $unit->targetTerritory . ", and wasn't convoyed there. It failed and switched to a holding action.\n";
				
					$unit->addComments( $comments );
					$$units{ $ID }->action( $hold );
	
				}
			} 
		
		} elsif( $unit->action eq $support ) {

			# The unit is supporting an action - for now
			$supporting{ $ID } = $unit;
	
		} elsif( $unit->action eq $convoy ) { 
			
			# The unit hopes to convoy an army across the big blue
			$convoying{ $ID } = $unit;

		} elsif( $unit->action eq $hold ) {
			
			# So they're holding. Big whoop.

		} elsif( $unit->action eq $disband ) {

			# They're suicidal. Move on.

		} else {
	
			# There shouldn't be any other options. Sorry.
			croak "I don't know how to ", $unit->action, "\n";
		}
	}

	return \%moving, \%supporting, \%convoying;

} # End GetActionGroups


#############################################################################
# CutSupports
#############################################################################
# CutSupports checks the target territory for all moving units, and if that
# unit is supporting an action, their support is cut, their action becoming
# instead a hold.

sub CutSupports {

	#print "CutSupports!\n";
	
	print "<h2>Cutting all supports from units under attack</h2>\n";
	
	my( $units, $territories, $powers, $moving, $supporting ) = @_;
		
	foreach ( keys %$moving ) {

		my $unit = $$units{ $_ };
		my $target = $unit->targetTerritory;
		my $occupier = $$territories{ $target }->occupier;

		unless( $occupier ) {
			# The target space not occupied. Tough to hurt them.
			next;
		}

		unless( $$supporting{ $occupier } ) {

			# The occupier is not supporting, so you
			# can't cut the support, now can you?
			next;
		}

		$occupier = $$units{ $occupier };

		# So they are supporting.
		# Check if it's against one of your fellow countrymen.

		if( $unit->power eq $occupier->power ) {
			print "You can't attack your own unit, you bad person! The order has been belayed.\n";
			$unit->action( $hold );
			# Move along...
			next;
		}

		# Check if it's against your own space
		my $supportVsMe = IsSupportVsMe( $units, $territories, $occupier->ID, $unit->location);

		unless( $supportVsMe ) {

			# The occupier of the target space is attempting to 
			# support an attack. (that is not into the units' 
			# space, nor of the unit's power)  That support was cut
			# by the move.

			# Change the action to a hold
			$occupier->action( $hold );
			$unit->action( $hold );

			# Make a note of that, Watson
				
			print "\tCutting the support from ", $occupier->location, " to ", $occupier->targetTerritory, "\n";

			my $supportInfo;
			if( $occupier->destinationTerritory ) {
				# The unit is supporting a move
				$supportInfo = $occupier->targetTerritory . ' to ' . $occupier->destinationTerritory;	
			} else{
				# Just supporting a territory
				$supportInfo = $occupier->targetTerritory;
			}
	
			my $comments = "Support for $supportInfo was cut by an attack by a " . $$powers{ $unit->power }->adjective . " " . $unit->type . " from " . $unit->location . "\n";

			# PrintInfo( $occupier, $comments );
			$occupier->addComments( $comments );

			# They ain't supporting no more. 
			delete( $$supporting{ $occupier->ID } );

			# And let the cutter know
			$comments = "The move to " . $target .  " prevented the support of the " . $$powers{ $occupier->power }->adjective . " " . $occupier->type . " in " . $occupier->location . " from helping $supportInfo\n";

			# PrintInfo( $unit, $comments );
			$unit->addComments( $comments );
		}
		
		# Prolly should add comments on why support
		# failed, etc.
	}
} # End CutSupports


########################################################################
# IsSupportVsMe
########################################################################

sub IsSupportVsMe {
	
	#print "IsSupportVsMe\n";

	my ( $units, $territories, $targetUnitID, $home ) = @_;

	#print "The target unit is now $targetUnitID!";

	my $targetUnit = $$units{ $targetUnitID };
		
	if ( $targetUnit->destinationTerritory ) {
		
		# The supporting unit belives its support is attacking
		my $supportedUnitPlace = $targetUnit->targetTerritory;
		
		my $supportedUnit = $$territories{ $supportedUnitPlace }->occupier;
		
		my $supportedTarget = $$units{ $supportedUnit }->targetTerritory;
	
		if( $home eq $supportedTarget ) {
			# The unit is supporting an attack on your space
			# Can't cut it. Sorry.
			print "\tThe unit from $home failed to cut the support from ", $targetUnit->location, ", as it is an attack on itself.\n";
			return 1;
		}
	}

	return 0;

} # End IsSupportVsMe


########################################################################
# PrintInfo
########################################################################
# Given a unit, PrintInfo prints out what it knows about it.

sub PrintInfo {
	
	#print "PrintInfo!\n";
	
	my( $unit, $comments ) = @_;

	print "\tA ", $unit->power, " ", $unit->type, " in ", $unit->location, 
	 " reports: ", $comments;	

} # End PrintInfo 


###########################################################################
# GetConflicts
###########################################################################
# GetConflicts looks for spaces that are in contention and marks them
# It checks for units moving to occupied spaces and multiple units moving
# to the same space 

sub GetConflicts {

	print "<h2>Calculating conflicts</h2>\n";

	my( $units, $territories, $moving ) = @_;
	my %conflicts;

	my $ID;
	foreach $ID ( keys %$moving ) {

		my $target = $$units{ $ID }->targetTerritory;
		my $targetTerritory = $$territories{ $target };	

		unless( $conflicts{ $target } ) {

			# Enter the territory into the conflicts list
			$conflicts{ $target } = $targetTerritory;
		} 

		# Add a new attacker to the space
		$conflicts{ $target }->newAttacker( $ID ); 
		
	}

	my $war;
	foreach $war ( keys %conflicts ) {
		print "\tThere is chaos in the territory ", $conflicts{ $war }->fullName, "!\n";
	}
	
	return \%conflicts;

} # End GetConflicts 


###########################################################################
# Winnow 
###########################################################################
# Winnow removes all but the strongest attacker per space

sub Winnow {

	print "<h2>Removing weaker attackers</h2>\n";

	my ( $units, $territories, $conflicts, $powers ) = @_;

	foreach ( keys %$conflicts ) {
		my $battlefield = $$conflicts{ $_ };	

		if( $battlefield->attackerCount > 1 ) {
	
			# There is more than one unit targeting this space
		
			print "\tThere is more than one unit targeting ", $battlefield->fullName, ".\n";

			my $offense = PickStrongest( $battlefield->name, $conflicts, $units, $powers );

			# Delete not-strongest units
			$battlefield->clearAttackers;
			if( $offense ) { 
				#print "The offense is : ", $$units{ $offense }->location . "\n";
				# If there's a stronger attacker, add them back
				$battlefield->newAttacker( $offense );
			}
		} 
	
	}

} # End Winnow


#############################################################################
# PickStrongest
#############################################################################
# PickStrongest selects the strongest attacker on a given space, or returns
# nothing if they are tied (standoff situation). If they are tied, the 
# battlefield is marked as non-retreatable.

sub PickStrongest {

	print "<h2>Selecting strongest attacker</h2>\n";

	my ( $battlefield, $conflicts, $units, $powers ) = @_;

	my @attackers = $$conflicts{ $battlefield }->getAttackers;

	my $highStrength = 0;
	my @strongestAttacker = undef;
	my $comments = undef;
	
	my $offense = undef;
		
	foreach ( @attackers ) {
		my $attacker = $$units{ $_ };

		# Check and see if they're tougher than the leader
		if( $attacker->strength > $highStrength ) {

			print "This unit from ", $attacker->location, " is now strongest.\n";

			if( $strongestAttacker[0] ) {
		
				# There is already someone as the
				# ranking strongman - perhaps tied.
				print "But someone else now has that title.\n";

				my $oldAttacker;
				foreach ( @strongestAttacker ) {
	
					$oldAttacker = $$units{ $_ };

					$comments = "Attack failed because a stronger " . $$powers{ $attacker->power }->adjective . " " .  $attacker->type . " from " . $attacker->location . " overpowered us!\n";
					$oldAttacker->addComments( $comments );
					PrintInfo( $oldAttacker, $comments );
					$oldAttacker->action( $hold );
					
					# Reset their strength to 1- the move failed.
					$oldAttacker->strength( 1 );
				}
			}
		
			@strongestAttacker = undef;
			$strongestAttacker[0] = $attacker->ID;
			$highStrength = $attacker->strength;
		
			$offense = $attacker->ID;
			
			#print "The offense is now $offense\n";
								
		} elsif( $attacker->strength < $highStrength ) {

			# An earlier attacker is stronger. 
			my $strongAttacker = $$units{ $offense };
	
			$comments = "Attack failed because a stronger " . $$powers{ $strongAttacker->ID }->adjective . " " . $strongAttacker->type . " from " . $strongAttacker->location . " overpowered us!\n";

			$attacker->addComments( $comments );
			PrintInfo( $attacker, $comments );

			$attacker->action( $hold );
			
			# Cancel their supports.
			$attacker->strength( 1 );
			
			# The offense remains the same.
		
		} else {
				
			# The unit is tied with the current strongest
	
			print "This unit from ", $attacker->location, " is tied for strongest.\n";
			# Tell any units currently equal
			
			foreach ( @strongestAttacker ) { 
				my $oldAttacker = $$units{ $_ };	

				$comments = "The attack to " . $oldAttacker->targetTerritory . " was stood off by an equally powerful " . $$powers{ $attacker->power }->adjective . " " . $attacker->type . " attacking from " . $attacker->location . ".\n";
	
				$oldAttacker->addComments( $comments );

				# Tell the new attacker about the tie

				$comments = "The attack to " . $attacker->targetTerritory . " was stood off by an equally powerful " . $$powers{ $oldAttacker->power }->adjective . " " . $oldAttacker->type . " attacking from " . $oldAttacker->location . ".\n";

				$attacker->addComments( $comments );
				
				$oldAttacker->action( $hold );
				
				# Reset the supports
				$oldAttacker->strength( 1 );

			}

			$attacker->action( $hold );
			
			# Reset the supports
			$attacker->strength( 1 );

			push( @strongestAttacker, $attacker->ID );
					
			# There is currently no offense, as they're tied.
			$offense = undef;

		} # End strength testing this unit

	} # End of testing all attackers
	
	if( $offense ) {
		print "\tThe strongest attacker was from " . $$units{ $offense }->location . ".\n";
	} else { 
	
		# There was a bounce- province can't be retreated to.
		
		# Mark the province as non-retreatable
		$$conflicts{ $battlefield }->noRetreat;	
		
		print "\tThe attackers stood each other off.\n";
	
	}
	return $offense;

} # End PickStrongest


###########################################################################
# CancelConvoys
###########################################################################
# CancelConvoys has one rather selfevident purpose in life: to 
# any convoys that are overpowered. This is necissary to make the logic
# of the rest of the game work properly.

sub CancelConvoys {

	print "<h2>Canceling invalid convoys</h2>\n";

	my( $units, $territories, $conflicts ) = @_;

	foreach( keys %$conflicts ) {
		my $battlefield = $$territories{ $_ };

		my $occupier = $$units{ $battlefield->occupier };
		if( $occupier and ( $occupier->action eq $convoy ) ) {
		
			# The unit is convoying. Could be trouble.
			
			if( $$units{ $battlefield->getAttackers }->strength > $occupier->strength ) {
				# It's over- this fleet is outta here. 
				# The dislodging will come later, just cancel
				# any convoys.
				
				print "\tCanceling the convoy in ", $occupier->location, " as it was overpowered.\n";
				$occupier->action( $hold );
			}
		}
	}
		
} # End CancelConvoys 


###########################################################################
# Move
###########################################################################
# Given a unit and the territories, Move, well, moves it.

sub Move {

	print "<h2>Moving Units</h2>\n";
	my( $unit, $territories, $conflicts ) = @_;

	my $to = $unit->targetTerritory;
	my $from = $unit->location;

	print "\tMoving unit ", $unit->ID, " from $from to $to.\n";

	# Comment what happened
	my $comments =  "The move from $from to $to succeeded.\n";
	$unit->addComments( $comments );

	# Mark the territory moved from as unnocupied.
	$$territories{ $from }->occupier( undef );

	# If the place being vacated is a battlefield, the defender is gone
	if( $$conflicts{ $from } ) {
		$$conflicts{ $from }->occupier( undef );
	}

	# If the unit had been routed from a previous home, it no longer
	# matters, as they were moving anyway
	if( $unit->routed ) {
		$unit->routed( 0 );
		print "This unit is NO LONGER ROUTED! ", $unit->routed, "\n";
	} else {
		# Since they weren't routed, they had a home. But they aren't
		# there now.
		# Mark the territory moved from as unnocupied.
       		$$territories{ $from }->occupier( undef );

		# If the place being vacated is a battlefield, the defender 
		# is gone as well
		if( $$conflicts{ $from } ) {
			$$conflicts{ $from }->occupier( undef );
		}
	}


	# Move the unit
	$unit->location( $to );
	
	# Once a unit has moved, its supports are no longer valid.
	$unit->strength( 1 );

	# Set the occupier of the destination territory to the new unit
	$$territories{ $to }->occupier( $unit->ID );

} # End Move


###########################################################################
# MoveLoops
###########################################################################
# MoveLoops looks for a loop (a->b->c...->a) in the moves. If there
# is such without any complications, it exchanges their positions.
# This routine is crucial, as Resolve assumes that there are no unterminated
# chains of movement, or loops.

sub MoveLoops {
		
	#print "MoveLoops!\n";
	my( $units, $territories, $moving, $conflicts ) = @_;
	my $start = undef;
	my $chain = [];

	my $ID; 
	foreach $ID ( keys %$moving ) {

		unless( exists( $$moving{ $ID } ) ) {
			# The unit is no longer in the moving list
			next;
		}

	 	my $unit = $$moving{ $ID };
		my $target = $unit->targetTerritory;

		unless( $$territories{ $target }->occupier ) {
			
			# The territory this unit is moving to is not occupied.
			# Therefore it ain't a loop. Next!
			next;
		}

		my $targetUnit = $$units{ $$territories{ $target }->occupier };

		unless( $targetUnit->targetTerritory ) {
			# The unit in the territory this unit is attacking
			# is not moving. Therefore, this can't be a move chain.
			next;
		}

		if( $targetUnit->targetTerritory eq $unit->location ) {

			# If they are going by convoy, it's OK.
			# This is one of the trickiest bits of the rulebook.
			if( Check::Convoy( $territories, $units, $unit->location, $unit->targetTerritory ) and Check::Convoy( $territories, $units, $targetUnit->location, $targetUnit->targetTerritory ) ) {
				
				Move( $unit, $territories, $conflicts );
				delete( $$conflicts{ $unit->location } );
				delete( $$moving{ $unit->location } );

				Move( $targetUnit, $territories, $conflicts );
				delete( $$conflicts{ $targetUnit->location } );
				delete( $$moving{ $targetUnit->location } );

				next;
			}
		
			# The two units are attacking each other. Not a 
			# permitted swap. 
			# Change any not-stronger units to hold.

			
			if( $unit->strength == $targetUnit->strength ) {

				print "The units from ", $unit->location, " and ", $targetUnit->location, " stood each other off.\n";
				$targetUnit->action( $hold );
				$unit->action( $hold );
			} elsif( $unit->strength > $targetUnit->strength ) {

				print "The unit from ", $unit->location, " overpowered the unit from ", $targetUnit->location, "\n";
				$targetUnit->action( $hold );

			} else { 

				print "The unit from ", $targetUnit->location, " overpowered the unit from ", $unit->location, "\n";
				$unit->action( $hold );
			}
			next;
		}

		$start = $unit->location;
		$chain = CheckLoop( $units, $territories, $unit );	
		if( ( @$chain[0] )  and ( pop( @$chain ) eq 'yes' ) ) {
			print "\tWe've got a loop: ",
			 join( " to unit ", @$chain), "!\n";

			foreach $unit ( @$chain ) { 
	
				Move( $$units{ $unit }, $territories, $conflicts );
				delete( $$moving{ $unit } );
			}

		}
		@$chain = undef;
	}

} # End MoveLoops


###########################################################################
# CheckLoop
###########################################################################
# CheckLoop is designed to be called recursively to look for a loop.

sub CheckLoop {
	
	#print "CheckLoop!\n";
	my( $units, $territories, $unit, $start, $chain ) = undef;

	if( scalar( @_ ) == 5 ) {
		# This was called recursively.
		( $units, $territories, $unit, $start, $chain ) = @_;
	} else {
		# It's the first time here.
		( $units, $territories, $unit ) = @_;
		$start = $unit->location;
		$chain = [];
	}

	my $target = $unit->targetTerritory;

	if( $target eq $start ) {
		
		push @$chain, $$units{ $$territories{ $target }->occupier }->ID;
		push @$chain, 'yes';
		return $chain
	
	} elsif( $$territories{ $target }->occupier ) {
		
		if( $$units{ $$territories{ $target }->occupier }->action eq $move ) {
			# The unit is moving into a territory being vacated
		
			$unit = $$units{ $$territories{ $target }->occupier };
			push @$chain, $unit->ID;
			$chain = CheckLoop( $units, $territories, $unit, $start, $chain );
		}
	}

	return $chain;

} # End CheckLoop


##############################################################################
# SumSupports
##############################################################################
# SumSupports ranks the complete strength of a given unit by including 
# supports

sub SumSupports {

	print "<h2>Calculating Supports</h2>\n";

	my( $units, $territories, $supports, $moving, $powers ) = @_;
	
	my $ID;
	foreach $ID ( keys %$supports ) {

		my $unit = $$supports{ $ID };

		my $supportedLocation = $unit->targetTerritory;
		my $supportedDestination = $unit->destinationTerritory;

		my $supportedID = $$territories{ $supportedLocation }->occupier; 
		my $supportedUnit = undef;

		# Check and see if the support target is there.
		if( $supportedID ) {

			$supportedUnit = $$units{ $supportedID };

		} else { 

			# The target isn't actually there.
			my $comments = "The attempted support of $supportedLocation failed as they didn't seem to be there.\n";
			$unit->addComments( $comments );

			# Get out of here.
			return;
		}	
		
		if( $supportedDestination ) {
	 
			# Make sure the target is moving, and to that space.

			if( $$moving{ $supportedID } and ( $supportedUnit->targetTerritory eq $supportedDestination ) ) {
					
				# The action is successful. Add in the support
				$supportedUnit->increaseStrength( 1 );

				# Make a note of it
				my $comments = "The support of " . $$powers{ $supportedUnit->power }->name . "'s " . $supportedUnit->type . " in $supportedLocation to $supportedDestination succeeded.\n";
				$unit->addComments( $comments );

				# And get it out of here. 
				delete( $$supports{ $ID } );

			} else {

				# The unit isn't moving now. Let them know.

				my $comments = "The attempted support of $supportedLocation to $supportedDestination failed as they did not seem to be moving to $supportedDestination.\n";
				$unit->addComments( $comments );
			}
	
		} elsif( $supportedLocation ) {
			# They must be supporting a stationary territory.

			if( $supportedUnit->action ne $move ) {

				# The action is successful. Add in the support
				$supportedUnit->increaseStrength( 1 );

				# Make a note of it
				my $comments = "The support of " . $$powers{ $supportedUnit->power }->name . "'s " . $supportedUnit->type . " $supportedLocation succeeded.\n";

				$unit->addComments( $comments );

				# And get it out of here.
				delete( $$supports{ $ID } );

			} else {
				
				# The unit isn't holding now.
			
				my $comments = "The attempted support of " . $$powers{ $supportedUnit->power }->name . "'s"  . $supportedUnit->type . " $supportedLocation failed as they did not seem to be stationary.\n";
				$unit->addComments( $comments );
			}

		} else {
			# They claim to be supporting, but don't say where to. 
			print "The unit in ", $unit->location, " claimed to be suppporting, but did not say where to.\n";
		}
	}

} # End SumSupports


#############################################################################
# Resolve
#############################################################################
# Resolve the conflicts on the board
# Something weird I do here- it's not entirely correct, but I have it first
# resolve naval issues, then land. This takes care of most problems of 
# order, as naval combats can affect the land but not vice versa.

sub Resolve {

	print "<h2>Resolving Conflicts</h2>\n";

	my ( $units, $territories, $powers, $conflicts, $iteration, $resolveOrder ) = @_;

#	print "Current conflicts: ", join( ' ', keys( %$conflicts ) ), "\n";

	my $offense = undef;
	my $resolveNow = shift @$resolveOrder;

	if( $iteration > 10 ) { croak "Loopy!"; }

	unless( $resolveNow ) {
		print "Resolve is trying to resolve nothing from array resolveOrder! Probably in a loop!\n";
		@$resolveOrder = ( 'water', 'land' );
		$resolveNow = shift @$resolveOrder;

		print join( ' ', keys( %$conflicts ) );

	}
	
	#print "\tNow resolving units placed in/on $resolveNow.\n";

	foreach ( keys %$conflicts ) {

		my $battlefield = $$conflicts{ $_ };

		# Check and see if the time has come for this type of move
		unless(	$battlefield->type eq $resolveNow ) {
			#print "It's not the turn for ", $battlefield->type, " yet, now is the time for $resolveNow.\n";
			next;
		}	

		print "\tCleaning up the mess in ", $battlefield->fullName, "\n";

		# Set the offense and defense- realizing neither may exist now
		my $defense = $battlefield->occupier;
		if ( $defense ) {

			$defense = $$units{ $defense };
			# Otherwise, there's no defender. 
			print "The defense is ", $defense->location, " and they are planning to ", $defense->action, "\n";
			
			# If the defense is moving, wait- they may vacate.
			if( $defense->action eq $move ) {
				print "Waiting on this battle because ", $defense->location, " is moving to ", $defense->targetTerritory, ".\n";
				next;
			}

		} 

		my $offense = $battlefield->getAttackers;
		if( $offense ) {
			# print "The offense is $offense\n";
			$offense = $$units{ $offense };

			# If the space is not adjacent, then it is attempting
			# a convoy. Check and see if it's still there.
			# OR IT'S JUST A MISTAKE- Can't assume that.

			unless( $battlefield->isAdjacent( $offense->location ) ) {
				my $canConvoy = Check::Convoy( $territories, $units, $offense->location, $battlefield->name );
				
				unless( $canConvoy ) {

					# A link in the convoy has been
					# dislodged
					print "Sorry pal, you are stuck on shore without any transportation.\n";

					$offense->action( $hold );

					# Reset the supports
					$offense->strength( 1 );

					delete( $$conflicts{ $battlefield->name } );
					next;

				}
			}


		} else {

			# There is no longer an attacking power; 
			# there was a standoff in attackers

			if( $defense ) {

				my $comments = "Though your garrison in " . $battlefield->fullName . " was beleagured from all sides, it did not fall as the opposing armies stood each other off.\n";
				$defense->addComments( $comments );
			}
			# Otherwise, there's no one to tell.	

			# And move on... 
			delete(  $$conflicts{ $battlefield->name } );		
			next;
		}
			
		if( $defense ) {
			
			# You can't dislodge your own units, so don't even try.
	
			unless( $defense->power ne $offense->power ) {

				print "You are attacking your own unit!\n";
				# Cancel the attack.
				$offense->action( $hold );
				
				# Cut the supports
				$offense->strength( 1 );
				
				delete( $$conflicts{ $battlefield->name } );
				next;
			}

			my $fallen = DukeItOut( $defense, $offense, $powers );
			if( $fallen ) {
				
				# The territory has fallen!
				# Get rid of the loser
				Dislodged( $units, $territories, $powers, $conflicts, $defense );

				# Move the winner
				Move( $offense, $territories, $conflicts );
				delete( $$conflicts{ $battlefield->name } );
				next;
		
			} else {
	
				# Otherwise the defenders have held out.
				
				delete( $$conflicts{ $battlefield->name } ); 
				next;
			}

		} else {
			
			# The defender appears to have left.

			my $comments = "The territory " . $battlefield->fullName. " was undefended.\n";
			$offense->addComments( $comments );

			# Move them
			Move( $offense, $territories, $conflicts );

		} 
	
		delete $$conflicts{ $battlefield->name };

	} # End of all battlefields	
	
	# But we might have skipped some.
	
	$iteration++;
	if( keys %$conflicts ) {
		# Here we go again...

		#print "Resolving again...\n";
		Resolve( $units, $territories, $powers, $conflicts, $iteration, $resolveOrder ); 
	};
	
} # End Resolve

##########################################################################
# DukeItOut
##########################################################################

sub DukeItOut {
	
	my( $defense, $offense, $powers ) = @_;
	print "<h2>Resolving Combat</h2>\n";

	# We've still got a defender. Better duke it out.

	print "Offensive strength: ", $offense->strength, " ";
	print "Offensive target dest: ", $offense->targetTerritory, " ";
	print "Defensive strength: ", $defense->strength, "\n";
	
	if( $offense->strength > $defense->strength ) {

		# They've broken through the lines! We've been routed!
	
		my $comments = "Our " . $offense->type . " from " . $offense->location . " was victorious in the battle of " . $offense->targetTerritory . " vanquishing the " . $$powers{ $defense->power }->adjective . " rabble.\n";

		$offense->addComments( $comments );
	
		$comments = "Our valiant forces in " . $defense->location . " were defeated by the evil " . $$powers{ $offense->power }->adjective . " " . $offense->type . " from " . $offense->location . "! The noble defenders were forced out.\n"; 

		$defense->addComments( $comments );
		$offense->action( $hold );
		
		# Reset their supports
		$offense->strength( 1 );

		return 1;
		
	} else {

		# The defenders have held out.
		# Make a note of that, Watson

		my $comments = "Though our " . $offense->type . " from " . $offense->location . " was relentless in the assault on the " . $$powers{ $defense->power }->adjective . " dogs in " . $offense->targetTerritory . ", our attack failed.\n";

		$offense->addComments( $comments );

		$comments = "Thanks to the astonishing heroism of our " . $defense->type . " the brutal " . $$powers{ $offense->power }->adjective . " attack from " . $offense->location . " on " . $defense->location . " was beaten back.\n";			
		$defense->addComments( $comments );

		# Change the action of the unit
		$offense->action( $hold );
		
		# Reset their supports
		$offense->strength( 1 );

		# Consider informing supporters
		
		return 0;
	}
	
} # End DukeItOut


############################################################################
# Dislodged
############################################################################
# Deals with dislodging a unit, saves possible retreats, etc. However,
# more retreat processing needs to happen at the end of the turn to remove
# occupied provinces and ones with bounces.

sub Dislodged {

	print "<h2>Dislodging Unit</h2>\n";
	my ( $units, $territories, $powers, $conflicts, $dispossessed ) = @_;
	
	my $dislodgedFrom = $dispossessed->location;
	print "\tDislodging the unit of late from $dislodgedFrom.\n";

	# If they were hoping to convoy, they ain't anymore.
	if( $dispossessed->action eq $convoy ) {

		$dispossessed->action( $hold );
	}

	$dispossessed->routed( 1 );

	# They ain't doin' whatever they were doing now.
	$dispossessed->action( $hold );

	# Get the places adjacent to the battlefield
	my @retreats = $$territories{ $dislodgedFrom }->adjacencies;
	
	# Read them into a hash to delete the attacker's home
	my %retreats;
	foreach ( @retreats ) { $retreats{ $_ } = 1 }
	
	# Find out who the attacker was
	my $attacker = $$conflicts{ $dislodgedFrom }->getAttackers;

	# Can't retreat to provinces attacked from, even if vacant
	my $attackerFrom = $$units{ $attacker }->location;
	delete $retreats{ $attackerFrom };

	# Put them back into a (shorter) array
	undef @retreats;
	my $index = 0;
	foreach ( keys %retreats ) {
		$retreats[$index] = $_;
		$index++;
	}

	# Show the info on where they may retreat to.
	my $retreatCount = scalar( @retreats );
	# print "Retreat count: $retreatCount\n";
	my ( $retreatInfo, $lastLocale ) = undef;
	if( $retreatCount < 1 ) {
		$retreatInfo = "nowhere, unless it be hell. Your forces have no place to run. They have been annihilated.";
 	} elsif( $retreatCount == 1 ) {
		$retreatInfo = "in " . $retreats[0] . ".";
	} else {
		# The push/pop shenanigans are just to make it pretty.
		$lastLocale = pop( @retreats );
		$retreatInfo = "in " . join( ', ', @retreats ) . ", or $lastLocale.";
		push( @retreats, $lastLocale );
	}
	
	my $comments = $$powers{ $dispossessed->power }->name . ", your forces were routed from $dislodgedFrom. They may regroup $retreatInfo\n";
	$dispossessed->addComments( $comments );

	# Save the possible retreats.
	$dispossessed->retreats( @retreats ); 

} # End Dislodged


##############################################################################
# Rout
##############################################################################

sub Rout {

	print "<h2>Routing Unit</h2>\n";

	my $units = shift;
	foreach ( keys %$units ) {
		my $unit = $$units{ $_ };
		
		if( $unit->routed ) {
			print "\tRouting the unit formerly in ", $unit->location, "\n";
			my $retreats = '';
			if( $unit->retreats ) {
				$retreats = ' ' . join( ' ', $unit->retreats );
			}
	
			# Limbo is a special place for units that need
			# to be resolved.
			$unit->location( $limbo );
		}
	}

} # End rout


##############################################################################
# ResolveRetreats
##############################################################################

sub ResolveRetreats {

	print "<h2>Resolving Retreats</h2>\n";

	my( $units, $conflicts, $territories ) = @_;

	my $coward;
	my $battlefield;

	foreach $battlefield ( keys %$conflicts ) {
	
		# Any conflict where two units are attempting to retreat
		# to the same space or the spot is occupied mean the retreat
		# fails. Sorry; they're destroyed.

		if( $$conflicts{ $battlefield }->occupier ) {

			print "The territory was already occupied.\n";
			$coward = $$territories{ $battlefield }->getAttackers;
			print "The unit $coward will be forced to disband.\n";
			delete ( $$units{ $coward } );
			delete ( $$conflicts{ $battlefield } );

		} elsif( $$conflicts{ $battlefield }->attackerCount > 1 ) {

			print "Two units tried to retreat to $battlefield!";
			my @attackers = $$territories{ $battlefield }->getAttackers;

			foreach $coward ( @attackers ) {

				print "The unit $coward will be forced to disband.\n";
				delete( $$units{ $coward } );
			}		

			delete( $$conflicts{ $battlefield } );

		} 
	}

	# Other than that, they should be OK. Move 'em.

	foreach( keys %$conflicts ) {
		
		my $unit = $$territories{ $_ }->getAttackers;
		print "I'm going to move $_ now!\n";
		Move( $$units{ $unit }, $territories, $conflicts );
	}

} # End ResolveRetreats


##############################################################################
# Report 
##############################################################################

sub Report {

	print "<h2>Final Report</h2>\n";

	my $units = shift @_;

	print "The final positions at the end of this turn are:\n";

	my $unit;
	foreach ( sort { $$units{ $a }->power cmp $$units{ $b }->power } 
			keys %$units ) {

		$unit = $$units{ $_ };
		print $unit->power, " ", $unit->type, " ", $unit->location, "\n"; 
		if( $unit->comments ) {
			print "\tDispatches: ", $unit->comments;
		}
	}
	print "\n";
	
} # End Report


##############################################################################
# WriteToDB
##############################################################################
# This wraps up the adjudication, taking what it understands of the current
# game status and putting it in the database

sub WriteToDB {

	print "<h2>Saving Results</h2>\n";
	my( $units, $territories, $mapID, $gameID, $turn, $phase, $dbh ) = @_;

	if( $doNotWriteToDB ) {
		print "Database writing disabled. The DB will not be updated.\n";
	}

	# This controls when (after moves or retreats) to calculate adjustments
	my $adjustNow = 0;

	# Very different actions are required depending on the turn type.
	# Do what is needed.

	if( $phase eq $movePhase ) {

		( $adjustNow, $turn ) = MovePhaseProcessing( $units, $territories, $gameID, $turn, $dbh, $doNotWriteToDB );

	} elsif( $phase eq $retreatPhase ) {

		$adjustNow = RetreatPhaseProcessing( $units, $territories, $gameID, $turn, $dbh, $doNotWriteToDB );
		
	} elsif( $phase eq $adjustPhase ) {

		AdjustPhaseProcessing( $gameID, $dbh, $doNotWriteToDB );
		
	} else {
		# Don't know what to do!
		croak "I don't understand the phase $phase!";
	}


	# If this is an adjustment turn and now is the time to deal with it
	# then update who owns the supply centers

	if( $adjustNow ) {
	
		# This assumes that ALL supply centers are in the 
		# table, be they occupied or no.
		foreach( keys %$units ) {

		 	my $position = $$territories{ $$units{ $_ }->location }->ID;
		
			my $playerID = $$powers{ $$units{ $_ }->power }->ID;

			if( $$territories{ $$units{ $_ }->location }->isSupply ) {

				print "Updating the ownership of " . $$territories{ $$units{ $_ }->location }->name . " to " . $$units{ $_ }->power . "\n";

				my $query = "UPDATE game_supply_centers
					     SET player_id=$playerID
					     WHERE game_id=$gameID 
					     AND terr_id=$position
					     AND turn=$turn";

				DB::Process( $query, $dbh, $doNotWriteToDB );
	
			}
		}

		# Since there are adjustments, we need to have an adjust phase

		my $query = "UPDATE games
			     SET phase='$adjustPhase'
			     WHERE id=$gameID";
		DB::Process( $query, $dbh, $doNotWriteToDB );

	}

	print "DB update completed.";
	
} # End WriteToDB


#############################################################################
# MovePhaseProcessing
#############################################################################
# Deal with DB interactions in a move phase
#

sub MovePhaseProcessing {

	my( $units, $territories, $gameID, $turn, $dbh, $doNotWriteToDB ) = @_;

	print "<h2>Processing Movement Phase</h2>\n";

	# We've just finished a move turn
	
	# Increment the game turn
	my $prevTurn = $turn;
	$turn++;

	# Tracking if there were retreats
	my $anyRetreats = 0;

	# Figure out if we should run adjustements now or later
	my $adjustNow = 0;

	# Add new set of data to game_orders for each unit
	foreach ( keys %$units ) {

		my $ID = $$units{ $_ }->ID;

		# If they've been routed, we have to deal with them.
		if( $$units{ $_ }->routed ) {

			print "The unit ", $$units{ $_ }->ID, " has been routed, and can retreat to ", join( ' ', $$units{ $_ }->retreats ), ".\n";

			### IS THIS SUFFICENT? should probably 
			# deal specifically with these routed units
			unless( $$units{ $_ }->retreats ) {

				print "The unit has nowhere to retreat\n";
			}

			# Insert the unit into the retreats table with
			# every possible retreat territory. 
			# Do not permit territories that are occupied or had bounces.

			foreach( $$units{ $_ }->retreats ) {

				my $terr = $_;

				# Get the ID of the territory.
	
				my $terrID = $$territories{ $terr }->ID;
				
				# If it's occupied, skip it.
				if( $$territories{ $terr }->occupier ) { next; }
				
				# If it is non-retreatable (because of a bounce) skip it.
				unless( $$territories{ $terr }->retreatStatus ) { next; }
				
				my $query = "INSERT INTO game_retreats VALUES( $gameID, $ID, $terrID )"; 
				DB::Process( $query, $dbh, $doNotWriteToDB );
			}

			$anyRetreats = 1;
		}	 

		my $position = $$territories{ $$units{ $_ }->location }->ID;
		my $comments = $dbh->quote( $$units{ $_ }->comments );

		# Keep a record of what happened to this unit this turn
		my $query = "UPDATE game_orders 
			     SET comments=$comments
			     WHERE game_id=$gameID AND turn=$prevTurn
			     AND unit_id=$ID";
		DB::Process( $query, $dbh, $doNotWriteToDB );
			
		$query = "INSERT INTO game_orders VALUES( $ID, $turn, $gameID, $position, NULL, NULL, NULL, NULL )";
		DB::Process( $query, $dbh, $doNotWriteToDB );
	}

	# See if we need to adjust units

	my $query = "SELECT adjust FROM calendars, calendar_seasons
		     WHERE calendars.id=1
		     AND calendar_seasons.calendar_id=calendars.id
		     AND calendar_seasons.number=MOD( $prevTurn, calendars.seasons )";

	my $sth = DB::Process( $query, $dbh, $doNotWriteToDB );
	my $ref = $sth->fetchrow_hashref();
	my $adjust = $ref->{adjust};

	if( $anyRetreats ) {

		# Since there were retreats, they need to be resolved 
		# before the next move phase. Set the turn phase.

		my $query = "UPDATE games 
			     SET phase='$retreatPhase' 
			     WHERE id=$gameID";
		DB::Process( $query, $dbh, $doNotWriteToDB );

	} elsif( $adjust ) {

		# We don't have any retreats to deal with, but do
		# need to do builds next phase. Set the flag.

		$adjustNow = 1;

	} else {
		
		# This is the end of the turn (no retreats or adjusts) so we
		# can increment the turn.
		
		# Otherwise, we need to increment after the retreats or adjusts
		
		my $turnQuery = "UPDATE games SET turn='$turn' WHERE id='$gameID'";
		DB::Process( $turnQuery, $dbh, $doNotWriteToDB );
	}

	# Next, update the supply centers for the new turn

	# First, carry over all the current supply centers.
	$query = "CREATE TEMPORARY TABLE supply_temp 
		     ( game_id int, turn int, terr_id int, player_id int )";
	DB::Process( $query, $dbh, $doNotWriteToDB );

	# Populate the temp table with the most recent supply info
	$query = "INSERT INTO supply_temp 
		  SELECT * FROM game_supply_centers
		  WHERE game_id = $gameID and turn = $prevTurn";
	DB::Process( $query, $dbh, $doNotWriteToDB );
		
	# Update the turn in the temp table
	$query = "UPDATE supply_temp SET turn=$turn WHERE game_id=$gameID";
	DB::Process( $query, $dbh, $doNotWriteToDB );

	# Insert the updated info back in	
	$query = "INSERT INTO game_supply_centers
		     SELECT * FROM supply_temp WHERE game_id=$gameID";
	DB::Process( $query, $dbh, $doNotWriteToDB );


	return ( $adjustNow, $turn );

} # End MovePhaseProcessing


#############################################################################
# RetreatPhaseProcessing
#############################################################################
# Deal with DB interactions in a retreat phase
#

sub RetreatPhaseProcessing {

	my( $units, $territories, $gameID, $turn, $dbh, $doNotWriteToDB ) = @_;

	print "<h2>Processing Retreat Phase</h2>\n";

	# Keep track of if we need to adjust now or not.
	my $adjustNow = 0;
	
	# Note what the last turn was
	my $prevTurn = $turn - 1;

	# We have just adjudicated a retreat phase

	# Go through all the units, writing their position out.
	foreach( keys %$units ) {
		
		my $ID = $$units{ $_ }->ID;

		# If they are still in limbo, kill 'em.
		if( $$units{ $_ }->location eq $limbo ) {

			print "Unit $ID did not retreat. Deleting...";
			my $query = "DELETE FROM game_orders
				     WHERE game_id=$gameID
				     AND turn=$turn AND unit_id=$ID";
			DB::Process( $query, $dbh, $doNotWriteToDB );

		} else { 

			my $position = $$territories{ $$units{ $_ }->location }->ID;

			my $query = "UPDATE game_orders 
				     SET position=$position,
				     action=NULL, target_terr_id=NULL
				     WHERE unit_id=$ID AND turn=$turn";

			DB::Process( $query, $dbh, $doNotWriteToDB );
		}
	}

	# Finally, make sure to remove all units from this game in the 
	# retreat table

	my $query = "DELETE FROM game_retreats WHERE game_id = $gameID";
	DB::Process( $query, $dbh, $doNotWriteToDB );

	# See if we need to adjust units

	$query = "SELECT adjust FROM calendars, calendar_seasons 
		  WHERE calendars.id=1 
		  AND calendar_seasons.calendar_id=calendars.id 
		  AND calendar_seasons.number=MOD( $prevTurn, calendars.seasons )";

	my $sth = DB::Process( $query, $dbh, $doNotWriteToDB );
	my $ref = $sth->fetchrow_hashref();
 	my $adjust = $ref->{adjust};

	# Set the phase to move- unless we're in build mode.
	# And increment the turn number.
	
	if( $adjust ) {

		$adjustNow = 1;

	} else {

		my $query = "UPDATE games SET phase='$movePhase', turn='$turn+1'
 		     	     WHERE id=$gameID";
		DB::Process( $query, $dbh, $doNotWriteToDB );

	}

	return $adjustNow;

} # End RetreatPhaseProcessing


#############################################################################
# AdjustPhaseProcessing
#############################################################################
# Deal with DB interactions in an adjustment phase
#

sub AdjustPhaseProcessing {

	my( $gameID, $dbh, $doNotWriteToDB ) = @_;

	print "<h2>Processing Adjustment Phase</h2>\n";

	# It was an adjustment phase, and we need to put new builds
	# on the map and delete disbanded units.

	my $query = "SELECT * FROM game_adjustments 
		     WHERE game_id=$gameID";

	my $sth = DB::Process( $query, $dbh, 0);

	my $ref;
	while( $ref = $sth->fetchrow_hashref() ) {

		my $action = $ref->{action};

		if( $action eq $build ) {
		
			# They have commissioned a new unit. Add it.
		
			my $type = $ref->{type};	
			my $playerID = $ref->{player_id};
			my $position = $ref->{terr_id};

			my $query = "INSERT INTO game_units
				     VALUES ( NULL, $gameID, '$type', $playerID )";
			my $sth = DB::Process( $query, $dbh, $doNotWriteToDB );
		
			# Get the new ID of the unit
			my $unitID = $dbh->{'mysql_insertid'};

			$query = "INSERT INTO game_orders
				  VALUES ( $unitID, $turn, $gameID, $position, NULL, NULL, NULL, NULL )";
			DB::Process( $query, $dbh, $doNotWriteToDB );
		
		} elsif( $action eq $disband ) {

			# Someone's removed a unit. Kill it.

			my $unitID = $ref->{unit_id};

			my $query = "DELETE FROM game_orders 
				     WHERE game_id=$gameID 
				     AND unit_id=$unitID
				     AND turn=$turn";
			DB::Process( $query, $dbh, $doNotWriteToDB );

		} else {
			
			croak "I don't understand the action $action!\n";
		}

	}

	# Now that adjustment has been resolved, we can
	# clear the adjustment flag as well as clear out the DB, 
	# and advance the turn and phase.

	$query = "DELETE FROM game_adjustments WHERE game_id=$gameID";

	DB::Process( $query, $dbh, $doNotWriteToDB );

	$query = "UPDATE games SET phase='$movePhase', turn='$turn+1' 
		     WHERE id=$gameID";
	
	DB::Process( $query, $dbh, $doNotWriteToDB );

} # End AdjustPhaseProcessing

# And that's all, folks!
