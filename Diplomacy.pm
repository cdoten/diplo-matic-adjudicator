#########################################################################
#
# Diplomacy.pm
#
# A Perl module for creation of object-oriented constructs used in the game 
# Diplomacy
#
# Created by Chris Doten
# Begun 10.10.00
# 
#########################################################################


#########################################################################
#
#  Power
#
#########################################################################

package Power;

use strict;

my $powerCount = 0;

sub new {
	my $proto = shift;
	my $class = ref( $proto ) || $proto;
	my $playerID = shift;
	my $powerName = shift;
	my $player = shift;
	my $adjective = shift;
	++$powerCount;

	my $power = {};
	$power->{ID} = $playerID;
	$power->{NAME} = $powerName;
	$power->{PLAYER} = $player;
	$power->{ADJECTIVE} = $adjective;
	$power->{NUMBER} = $powerCount;

	bless( $power, $class );
	return $power;
}

sub ID {
	my $self = shift;
	return $self->{ID};
}

sub name {
	my $self = shift;
	return $self->{NAME};
}

sub player {

	my $self = shift;
	return $self->{PLAYER};
}

sub adjective {
	my $self = shift;
	return $self->{ADJECTIVE};
}

sub number {
	my $self = shift;
	return $self->{NUMBER};
}


#########################################################################
#
#  Territory
#
#########################################################################

package Territory;

use strict;

my $terrCount = 0;

sub new {

	my $proto = shift;
	my $class = ref( $proto ) || $proto; 
	my $id = shift;
	my $name = shift;
	my $type = shift;
	my $fullName = shift;
	my $supply = shift;

	++$terrCount;

	my $territory = {};
	$territory->{ID} = $id;
	$territory->{NAME} = $name;
	$territory->{FULLNAME} = $fullName;
	$territory->{TYPE} = $type;
	$territory->{OCCUPIER} = '';
	$territory->{ADJACENCIES} = [];
	$territory->{NUMBER} = $terrCount;
	$territory->{ATTACKERS} = [];
	$territory->{SUPPLY} = $supply;
	$territory->{RETREATABLE} = 1;
	$territory->{HOMELAND} = '';

	bless ( $territory, $class );
	return $territory;
}

sub ID {
	my $self = shift;
	return $self->{ID};
}

sub number {
	my $self = shift;
	return $self->{NUMBER};
}

sub type {

	my $self = shift;
	return $self->{TYPE};
}

sub fullName {
	my $self = shift;
	return $self->{FULLNAME};
}

sub name {
	my $self = shift;
	return $self->{NAME};
}

sub homeland {
	my $self = shift;
	if( @_ ) { $self->{HOMELAND} = shift; }
	return $self->{HOMELAND};
}

sub adjacencies {

	my $self = shift;
	if( @_ ) { @{ $self->{ADJACENCIES} } = @_; }
	return @{ $self->{ADJACENCIES} };
}

sub isAdjacent {

	my $self = shift;
	my $territory = shift;
	my $adjacentTerritory;
	foreach $adjacentTerritory ( @{ $self->{ADJACENCIES} } ) {

		if( $adjacentTerritory eq $territory ) {
			return 1;
		}
	}
	# It isn't in there.
	return 0;
}

sub isSupply {
	my $self = shift;
	return $self->{SUPPLY};
}

sub noRetreat {
	my $self = shift;
	$self->{RETREATABLE} = 0;
	return $self->{RETREATABLE};
}

sub retreatStatus {
	my $self = shift;
	return $self->{RETREATABLE};
}

sub occupier {
	my $self = shift;
	if( @_ ) { $self->{OCCUPIER} = shift }
	return $self->{OCCUPIER};
}

sub attackerCount {
	my $self = shift;
	return scalar( @{ $self->{ATTACKERS} } );
}

sub getAttackers {
	my $self = shift;
	if ( scalar( @{ $self->{ATTACKERS} } ) == 1 ) {
		return $self->{ATTACKERS}[0]
	} else {
		return @{ $self->{ATTACKERS} };
	}	
}

sub clearAttackers { 
	my $self = shift;
	$self->{ATTACKERS} = [];
}

sub newAttacker {
	my $self = shift;
	my $attacker = shift;
	push( @{ $self->{ATTACKERS} }, $attacker );
	return $self->{ATTACKERS};
}

# End of Territory

####################################################################
#
#  Unit Package
#
####################################################################

package Unit;

use strict;

my $unitCount = 0;

sub new {
	my $proto = shift;
	my $class = ref( $proto ) || $proto;

	my $unitID = shift;
	my $power = shift;
	my $type = shift;
	my $location = shift;
	my $action = shift;
	my $targetTerritory = shift;
	my $destTerritory = shift;

	++$unitCount;

	my $unit = {};
	$unit->{ID} = $unitID;
	$unit->{POWER} = $power;
	$unit->{TYPE} = $type;
	$unit->{LOCATION} = $location;
	$unit->{ACTION} = $action;
	$unit->{TARGET} = [];
	$unit->{STRENGTH} = 1;
	$unit->{COMMENTS} = "";
	$unit->{ROUTED} = 0;
	$unit->{DESTROYED} = 0;
	$unit->{RESOLVED} = 0;
	$unit->{RETREATS} = [];
	$unit->{TARGETTERRITORY} = $targetTerritory;
	$unit->{DESTINATIONTERRITORY} = $destTerritory;

	bless( $unit, $class );
	return $unit;
}

sub ID {

	my $self = shift;
	return $self->{ID};
}

sub power {
	
	my $self = shift;
	return $self->{POWER};
}

sub location {

	my $self = shift;
	if( @_ ) { $self->{LOCATION} = shift }
	return $self->{LOCATION};
}

sub type {

	my $self = shift;
	return $self->{TYPE};
}

sub strength {

	my $self = shift;
	if( @_ ) { 
		my $strength = shift;
		$self->{STRENGTH} = $strength; 
	}	
	return $self->{STRENGTH};
}

sub increaseStrength {

	my $self = shift;
	if( @_ ) { 
		my $increase = shift;
		$self->{STRENGTH} = ( $self->{STRENGTH} + $increase ) 
	}
	return $self->{STRENGTH};
}

sub comments {

	my $self = shift;
	return $self->{COMMENTS};
}


sub addComments {

	my $self = shift;
	if( @_ ) {
		my $newComments = shift;
		if( $self->{COMMENTS} ) {
 			$self->{COMMENTS} = $self->{COMMENTS} . $newComments;
		} else {
			$self->{COMMENTS} = $newComments
		}
	}	
	return $self->{COMMENTS};
}

sub destroyed {

	my $self = shift;
	if( @_ ) { $self->{DESTROYED} = shift }
	return $self->{DESTROYED};
}

sub routed {
	my $self = shift;
	if( @_ ) { $self->{ROUTED} = shift }
	return $self->{ROUTED};
}

sub retreats {
	my $self = shift;
	if( @_ ) { @{ $self->{RETREATS} } = @_; }
	return @{ $self->{RETREATS} };
}

sub resolved {

	my $self = shift;
	if( @_ ) { $self->{RESOLVED} = shift }
	return $self->{RESOlVED};
}

sub action {
	my $self = shift;
	if( @_ ) { $self->{ACTION} = shift }
	return $self->{ACTION};
}

sub targetTerritory {
	my $self = shift;
	return $self->{TARGETTERRITORY};
} 

sub destinationTerritory {
	my $self = shift;
	return $self->{DESTINATIONTERRITORY};
}

# End of Unit


##########################################################################
# Check
##########################################################################

package Check;

use strict;
use Carp;

# Land constants
my $water = 'water';
my $land = 'land';
my $impassable = 'impassable';

# Order constants
my $move = 'move';
my $hold = 'hold';
my $support = 'support';
my $convoy = 'convoy';
my $disband = 'disband';

# Unit constants:
my $army = 'army';
my $navy = 'fleet';

# Convoy- specific constants:
my $convoyVia = $water;
my $convoyUnit = $army;

# And their associated associated arrays:
my %unitTypes = ( $army => $land, $navy => $water );
my %types = ( $water => $water, $land => $land, $impassable => $impassable );
my %moves = ( $move => $move, $hold => $hold, $support => $support, $convoy => $convoy, $disband => $disband );

sub Territory {

	my( $ID, $type, $territories ) = @_;

	if( exists( $$territories{ $ID } ) ) {
		carp "The territory $ID already exists!\n";
		return 0;
	}

	unless( exists( $types{ $type } ) ) {
		carp "The territory $ID has an invalid type of $type!\n";
		return 0;
	}

	return 1;

} # End Territory

sub Power {

	my( $name, $player, $powers ) = @_;

	if( exists( $$powers{ $name } ) ) {
		carp "The power $name already exists!\n";
		return 0;
	}

	return 1;
} # End Powers

sub Homes {

	my ( $power, $homes, $powers, $territories ) = @_;

	unless( exists( $$powers{ $power } ) ) {
		carp "The power $power does not exist!\n";
		return 0;
	}

	foreach ( @$homes ) {
		unless( exists( $$territories{ $_ } ) ) {
			carp "The territory $_ cannot be a homeland for $power as it does not exist!\n";
			return 0;
		}

		# Also make sure it is not already someone's h.s.h.
		if( $$territories{ $_ }->homeland ) {
			carp "The territory $_ cannot be a homeland for $power as it is already a homeland for ", $$territories{ $_ }->homeland, "!\n";
			return 0;

		}
	}

	return 1;
} # End Homes


sub Adjacencies {

	my( $place, $adjacencies, $territories ) = @_;

	if( scalar( @$adjacencies ) < 1 ) {
		carp "The territory $place does not appear to be adjacent to anything!\n";
		return 0;
	}

	foreach( @$adjacencies ) {

		unless( exists( $$territories{ $_ } ) ) {
			carp "The territory $_ cannot be adjacent to $place because it does not exist!\n";
			return 0;
		}
	}

	return 1;

} # End Adjacencies

sub Orders {

	# I want to do other sanity checking at some point; fleets inland, etc.

	my ( $power, $unitType, $territory, $action, $tarTerr, $destTerr, $units, $territories, $powers ) = @_;
	
	# Check that the power exists
	unless( exists( $$powers{ $power } ) ) {
		
		carp "The $unitType in $territory cannot be assigned to $power as there is no such power!\n";
		return 0;
	}

	# Check that the unit type is valid
	unless( exists( $unitTypes{ $unitType } ) ) {
		carp "There is no such unit type as $unitType!\n";
		return 0;
	}

	# Check that the territory exists
	unless( exists( $$territories{ $territory } ) ) { 
		carp "The $power $unitType cannot be assigned to $territory, as it does not exist!\n";
		return 0;
	}
	
	# Check that the territory is not already occupied
	# CAN'T DO IT, AS LIMBO OFTEN HAS MULTIPLES!
	#	if( $$territories{ $territory }->occupier ) {
	#	carp "The territory $territory cannot have $unitType from $power in it, as it is already occupied!\n";
	#	return 0;
	#}

	# Check that there is an action, and it's valid
	unless( $action ) {
		carp "The $power $unitType in $territory was not given an action!\n";
		return 0;
	} elsif( !exists( $moves{ $action } ) ) {
		carp "The $power $unitType in $territory was told to $action, which is not a possibility!\n";
		return 0;
	}

	# If moving, check that the destination exists

	if( $action eq $move ) {

		unless( exists( $$territories{ $tarTerr } ) ) {
			carp "The $power $unitType in $territory cannot $action to $tarTerr, because $tarTerr does not exist!\n";
			return 0;
		} 
		 
	} elsif( $action eq $support ) {

		# If they're supporting, make sure that checks out.

		unless( exists( $$territories{ $tarTerr } ) ) {
			carp "The $power $unitType in $territory cannot $action to $tarTerr, because it does not exist!\n";
			return 0;
		} 

		# If they are supporting a move, make sure it is to a valid spot

		if( $destTerr ) {

			unless( exists( $$territories{ $destTerr } ) ) {
				carp "The $power $unitType in $territory cannot support a move from $tarTerr to $destTerr, as $destTerr does not exist!\n";
				return 0;
			}

		}
	}

	return 1;

} # End Orders


sub Convoy {
	
	my( $territories, $units, $departure, $destination, $location, $returnValue ) = undef;
	
	if( scalar( @_ ) == 6 ) {
		# It was called recusively
		( $territories, $units, $departure, $destination, $location, $returnValue ) = @_;
	} else {
		# First time here.
		( $territories, $units, $departure, $destination ) = @_;
		$location = $departure;
		$returnValue = 0;
	}

	my $desiredConvoy = [ $convoyUnit, $departure, $move, $destination ];
	print "Attempting Convoy of $departure to $destination.\n";

	my $adjacency = undef;
	foreach $adjacency ( $$territories{ $location }->adjacencies ) {

		#print "Contemplating $adjacency... ";
		unless( $$territories{ $adjacency }->type eq $convoyVia ) {
			#print "Nope. Not water.\n";

			# It's not water, and won't be convoying much at all.
			next;
		}

		unless( $$territories{ $adjacency }->occupier ) {
			# It ain't occupied, and again seems an unlikely convoyer.
			#print "Nope. Not occupied.\n";
			next;
		}

		my $potentialConvoy = $$units{ $$territories{ $adjacency }->occupier };
		unless( $potentialConvoy->action eq $convoy ) {
			#print "Nope. Not convoying.\n";
			# They don't care to convoy.
			next;
		}

		unless( ( $potentialConvoy->targetTerritory eq $departure ) 
		       and ( $potentialConvoy->destinationTerritory eq $destination ) ) {
			# They are not convoying from the desired start to
			# the desired finish.
			print "Nope. They're convoying from ", $potentialConvoy->targetTerritory, " to ", $potentialConvoy->destinationTerritory, "\n";
			next;
		}

		if( $$territories{ $adjacency }->isAdjacent( $destination ) ) {

			print "Yep, that'll work.\n";
			# This fleet is adjacent to the proposed destination
			# as well as being willing and able to convoy. It's in.
			return 1;
		} else {

			print "Might be OK- looking for adjacent possibilites.\n";
			# It looks good, but it's not adjacent. Try the places
			# adjacent to here.
			$returnValue = Check::Convoy( $territories, $units, $departure, $destination, $adjacency, $returnValue );
		}

		# And return whatever the answer is
		print "Returning $returnValue!\n";
		return $returnValue;
	}
} # End Convoy


return 1;
