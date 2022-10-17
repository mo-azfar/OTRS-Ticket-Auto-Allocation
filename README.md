# OTRS-Ticket-Auto-Allocation
- Built for OTRS CE v 6.0.x / Znuny LTS / Znuny Features (Up to 6.4.x)
 
- OTRS / Znuny - Auto assigning incoming ticket (from email) to the agent.  
- Online Agent (based on session) with the less ticket ownership will get the ticket allocate to him / her.  
- Agent within Out Of Office time frame will not get ticket allocate to him /her.
- Only work when ticket in State "new" || Lock status "unlock" || Current owner "root@localhost".  

1. Admin must create a new Generic Agent (GA) with option to execute custom module.  

- Name: Anything
- Event Based Execution 
	-- Ticket::TicketCreate  
- Select Tickets
	-- Ticket#: *

- Execute Custom Module 
	-- Kernel::System::GenericAgent::TicketAutoAllocation  