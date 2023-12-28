# OTRS-Ticket-Auto-Allocation
- Built for Znuny LTS / Znuny Features
- OTRS / Znuny - Auto assigning incoming ticket (from email) to the agent (onwer/responsible).  

		- Agent (Online or Offline ) with the less ticket ownership/responsible will get the ticket allocate to him / her.  
		- Agent within Out Of Office time frame will not get ticket allocate to him /her.
		- Note: Ticket filtering has been removed from module file. Filtering should be make at Ganeric Agent itself.
		
		
1. .OPM will auto create 1 Generic Agent (owner assignment) to execute this module on ticket create. If not, create it manually.

	OWNER AUTO ASSIGNMENT 

	- Name: ZZZTicket AutoAllocation
	- Event Based Execution  
		-- Ticket::TicketCreate    

	- Select Tickets  
		-- Ticket#: * 
		-- State: new
		-- Agent/Owner: Admin OTRS
		-- Ticket unlock : unlock 
  
	- Execute Custom Module  
		-- Module
			--- Kernel::System::GenericAgent::TicketAutoAllocation  
		-- Param 1 key => value
			--- Allocation => Owner
		-- Param 2 key => value
			--- Online => Yes


Generic Agent Keys and Value

    Allocation => (Owner|Resposible) #allocate ticket to owner or responsible
    Online => (Yes|No) #allocate ticket to online agent only or all agent.

2. IMPORTANT!!

If you are updating the addon, update the Generic Agent to match the structure above!.