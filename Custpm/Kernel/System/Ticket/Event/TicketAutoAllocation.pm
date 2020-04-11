# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --
#TODO: filter out user based on configuration
#TODO: additional allocation filtering based on online session
package Kernel::System::Ticket::Event::TicketAutoAllocation;

use strict;
use warnings;

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);

use Data::Dumper;
use Fcntl qw(:flock SEEK_END);

our @ObjectDependencies = (
    'Kernel::System::Ticket',
    'Kernel::System::Log',
	'Kernel::System::Group',
	'Kernel::System::Queue',
);

=head1 NAME

Kernel::System::ITSMConfigItem::Event::DoHistory - Event handler that does the history

=head1 SYNOPSIS

All event handler functions for history.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $DoHistoryObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem::Event::DoHistory');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    
	#my $parameter = Dumper(\%Param);
    #$Kernel::OM->Get('Kernel::System::Log')->Log(
    #    Priority => 'error',
    #    Message  => $parameter,
    #);
	
	local $Kernel::OM = Kernel::System::ObjectManager->new(
        'Kernel::System::Log' => {
            LogPrefix => 'AutoAllocation',  # not required, but highly recommend
        },
    );
	
	# check needed param
    if ( !$Param{TicketID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need TicketID for this operation',
        );
        return;
    }

    #my $TicketID = $Param{Data}->{TicketID};  ##This one if using sysconfig ticket event
	my $TicketID = $Param{TicketID};  ##This one if using GenericAgent ticket event
	my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
	my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
	
	# get ticket details
	my %Ticket = $TicketObject->TicketGet(
		TicketID => $TicketID,
		UserID   => 1,
		);
	
	#print Dumper \%Ticket; 
	#print "\n\n";
	
	#stop if ticket currently NOT NEW, LOCKED, OR HAS AN OWNER
	if ( $Ticket{State} ne "new" || $Ticket{Lock} ne "unlock" || $Ticket{OwnerID} ne 1 )
	{
		$LogObject->Log(
			Priority => 'info',
			Message  => "Not this ticket: $TicketID\n\n",
		);
		exit;
	}
	
	my $GroupID = $Kernel::OM->Get('Kernel::System::Queue')->GetQueueGroupID( QueueID => $Ticket{QueueID} );
	
	#get rw users based on group the ticket resides in
	my %Users = $Kernel::OM->Get('Kernel::System::Group')->PermissionGroupGet(
			GroupID => $GroupID,
			Type    => 'rw', # ro|move_into|create|note|owner|priority|rw
		);
	
	my %Workloads;
	foreach my $UserID (keys %Users)
	{
		my $out = grep { /out of office/ } $Users{$UserID};
		next if $out eq 1; #remove user out of office
		next if $Users{$UserID} eq 'root@localhost'; #remove user root
		
		my @TicketIDs = $TicketObject->TicketSearch(
			# result (required)
			Result => 'COUNT',
			StateType    => ['open', 'new', 'pending reminder', 'pending auto'],
			OwnerIDs => [$UserID],
			UserID => 1,
		);
		
		#User ID => Ticket Count
		$Workloads{$UserID} = $TicketIDs[0];
	
	}    
	
	#search for min ticket count.
	use List::Util qw( min max );
	my $min = min values %Workloads ;
	
	for my $OwnerID ( keys %Workloads ) 
	{
		my $val = $Workloads{$OwnerID};
		next if $val ne $min;
		#print "Key $OwnerID || Value $val\n\n";
		
		#assign ticket to this user id $_
		my $SetOwner = $TicketObject->TicketOwnerSet(
			TicketID  => $TicketID,
			NewUserID => $OwnerID,
			UserID    => 1,
		);
		
		if ($SetOwner eq 1)
		{
			my $Success = $TicketObject->HistoryAdd(
				Name         => "Owner has been set to $Users{$OwnerID} by Auto Allocation",
				HistoryType  => 'OwnerUpdate', # see system tables
				TicketID     => $TicketID,
				CreateUserID => 1,
			);
		}
		
		#break after 1st match
		last if ($val eq $min);
	}
   
}

1;

