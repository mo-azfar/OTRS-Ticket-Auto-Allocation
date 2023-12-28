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
	
    #check ticket id
    if ( !$Param{TicketID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need TicketID for this operation',
        );
        return;
    }

    # check needed param
    # Allocation = Owner | Responsible
    # Online = Yes | No
    for my $Needed ( qw( Allocation Online ) )
	{
        if ( !$Param{New}->{$Needed} ) 
        {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need Parameter $Needed and its value for this operation!",
            );
            return;
        }
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
	
	my $GroupID = $Kernel::OM->Get('Kernel::System::Queue')->GetQueueGroupID( QueueID => $Ticket{QueueID} );
	
    my $AllocationType;
    my $SearchParam;
    my $HistoryName;
    my $HistoryType;

    if ( $Param{New}->{'Allocation'} eq 'Owner' )
    {
        $AllocationType = 'owner';
        $SearchParam = 'OwnerIDs';
        $HistoryName = 'Owner';
        $HistoryType = 'OwnerUpdate';
    }
    elsif ( $Param{New}->{'Allocation'} eq 'Responsible' )
    {
        $AllocationType = 'rw';
        $SearchParam = 'ResponsibleIDs';
        $HistoryName = 'Responsible';
        $HistoryType = 'ResponsibleUpdate';
    }
    else
    {
        $LogObject->Log(
			Priority => 'error',
			Message  => "Wrong Allocation value ($Param{New}->{'Allocation'}) on ticket: $TicketID\n\n",
		);
		return;
    }

	#get possible owner / responsible
	my %Users = $Kernel::OM->Get('Kernel::System::Group')->PermissionGroupGet(
		GroupID => $GroupID,
		Type    => $AllocationType,
	);
	
    my @common = ();

    #check online user
    if ( $Param{New}->{'Online'} eq 'Yes' )
    {
        my $SessionMaxIdleTime = $Kernel::OM->Get('Kernel::Config')->Get('SessionMaxIdleTime');
        my %Online   = ();
        my @Sessions = $SessionObject->GetAllSessionIDs();
        
        for my $SessionID (@Sessions) 
        {
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
	    foreach (keys %Users) {
		    push(@common, $_) if exists $Online{$_};
        }
    }
    elsif ( $Param{New}->{'Online'} eq 'No' ) 
    {
        foreach (keys %Users) {
		    push(@common, $_);
        }
    }
    else
    {
        $LogObject->Log(
			Priority => 'error',
			Message  => "Wrong Online value ($Param{New}->{'Online'}) on ticket: $TicketID\n\n",
		);
		return;
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
			$SearchParam => [$UserID],
			UserID => 1,
		);
			
		#User ID => Ticket Count
		$Workloads{$UserID} = $TicketIDs[0];
		
	}

	use List::Util qw( min max );
	my $min = min values %Workloads ;
	
	for my $AllocationID ( keys %Workloads ) 
	{
		my $val = $Workloads{$AllocationID};
		if ($val eq $min)
		{
			my $SetAllocation;
            if ( $Param{New}->{'Allocation'} eq 'Owner' )
            {
                #assign ticket owner to this user id $_
                $SetAllocation = $TicketObject->TicketOwnerSet(
                    TicketID  => $TicketID,
                    NewUserID => $AllocationID,
                    UserID    => 1,
                );
            }
            elsif ( $Param{New}->{'Allocation'} eq 'Responsible' )
            {
                #assign ticket resposible to this user id $_
                $SetAllocation = $TicketObject->TicketResponsibleSet(
                    TicketID  => $TicketID,
                    NewUserID => $AllocationID,
                    UserID    => 1,
                );
            }
			
			if ( $SetAllocation )
			{
				my $UserObject = $Kernel::OM->Get('Kernel::System::User');
                my $Name = $UserObject->UserName(
                    UserID => $AllocationID,
                );
                
                my $Success = $TicketObject->HistoryAdd(
					Name         => "$HistoryName has been set to $Name by Auto Allocation",
					HistoryType  => $HistoryType, # see system tables
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