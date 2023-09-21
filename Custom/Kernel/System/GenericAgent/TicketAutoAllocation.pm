# --
# Copyright (C) 2022 mo-azfar, https://github.com/mo-azfar/OTRS-Ticket-Auto-Allocation
#
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --
package Kernel::System::GenericAgent::TicketAutoAllocation;

use strict;
use warnings;

our @ObjectDependencies;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );
	
	$Self->{Debug} = $Param{Debug} || 0;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    
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

	my $TicketID = $Param{TicketID};  
	my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
	my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');
	my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
	
	# get ticket details
	my %Ticket = $TicketObject->TicketGet(
		TicketID => $TicketID,
		UserID   => 1,
	);
	
	#stop if ticket currently NOT NEW, LOCKED, OR HAS AN OWNER
	if ( $Ticket{State} ne "new" || $Ticket{Lock} ne "unlock" || $Ticket{OwnerID} ne 1 )
	{
		$LogObject->Log(
			Priority => 'info',
			Message  => "Not this ticket: $TicketID\n\n",
		);
		return;
	}
	
	my $GroupID = $Kernel::OM->Get('Kernel::System::Queue')->GetQueueGroupID( QueueID => $Ticket{QueueID} );
	
	#get possible owner
	my %Users = $Kernel::OM->Get('Kernel::System::Group')->PermissionGroupGet(
		GroupID => $GroupID,
		Type    => 'owner',
	);
	
	#get online users
	my $SessionMaxIdleTime = $Kernel::OM->Get('Kernel::Config')->Get('SessionMaxIdleTime');
    my %Online   = ();
    my @Sessions = $SessionObject->GetAllSessionIDs();
	
	for my $SessionID (@Sessions) {
        my %Data = $SessionObject->GetSessionIDData(
            SessionID => $SessionID,
        );
        if (
            $Data{UserType} eq 'User'
            && $Data{UserLastRequest}
            && $Data{UserLastRequest} + $SessionMaxIdleTime
            > $Kernel::OM->Create('Kernel::System::DateTime')->ToEpoch()
            && $Data{UserFirstname}
            && $Data{UserLastname}
            )
        {
            $Online{ $Data{UserID} } = "$Data{UserFullname}";
        }
    }
	
	#get intersection between group users and online
	my @common = ();
	foreach (keys %Users) {
		push(@common, $_) if exists $Online{$_};
	}
	
	#check workloads
	my %Workloads;
	foreach my $UserID (@common)
	{
		#remove system user
		next if $UserID eq 1;
		
		#check out of office users
		my %UserOOO = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
			UserID        => $UserID,
			Valid         => 1,       
			NoOutOfOffice => 1,       
		);
		
		$UserOOO{OutOfOffice} ||= 0;
		
		if ( $UserOOO{OutOfOffice} eq 1 )
		{
			my $CurSystemDTObject = $Kernel::OM->Create('Kernel::System::DateTime');
			
			my $StartDate = $Kernel::OM->Create('Kernel::System::DateTime',
				ObjectParams => {
					Year     => $UserOOO{OutOfOfficeStartYear},
					Month    => $UserOOO{OutOfOfficeStartMonth},
					Day      => $UserOOO{OutOfOfficeStartDay},
					Hour     => 00,
					Minute   => 00,
					Second   => 00,
				}
			);
			
			my $EndDate = $Kernel::OM->Create('Kernel::System::DateTime',
				ObjectParams => {
					Year     => $UserOOO{OutOfOfficeEndYear},
					Month    => $UserOOO{OutOfOfficeEndMonth},
					Day      => $UserOOO{OutOfOfficeEndDay},
					Hour     => 23,
					Minute   => 59,
					Second   => 59,
				}
			);
			
			#out of office detected, remove user
			if ( $StartDate < $CurSystemDTObject && $EndDate > $CurSystemDTObject ) {
				#remove user with out of office activated with ooo date within current date
				next;
			}	
			
		}
			
		my @TicketIDs = $TicketObject->TicketSearch(
			Result => 'COUNT',
			StateType    => ['open', 'new', 'pending reminder', 'pending auto'],
			OwnerIDs => [$UserID],
			UserID => 1,
		);
			
		#User ID => Ticket Count
		$Workloads{$UserID} = $TicketIDs[0];
		
	}
	
	use List::Util qw( min max );
	my $min = min values %Workloads ;
	
	for my $OwnerID ( keys %Workloads ) 
	{
		my $val = $Workloads{$OwnerID};
		if ($val eq $min)
		{
			#assign ticket to this user id $_
			my $SetOwner = $TicketObject->TicketOwnerSet(
				TicketID  => $TicketID,
				NewUserID => $OwnerID,
				UserID    => 1,
			);
			
			if ($SetOwner eq 1)
			{
				my $Success = $TicketObject->HistoryAdd(
					Name         => "Owner has been set to $Online{$OwnerID} by Auto Allocation",
					HistoryType  => 'OwnerUpdate', # see system tables
					TicketID     => $TicketID,
					CreateUserID => 1,
				);
			}
			
			#break after 1st match
			last if ($val eq $min);	
		}
		
	}
	
   return 1;
}

1;