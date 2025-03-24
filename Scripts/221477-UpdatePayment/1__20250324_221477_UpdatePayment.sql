/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250324@Winston
	DB: DBCUST.bodb_licensee
	Description: Update payment info
*/



--Update in LA_Payment table
UPDATE LA_Payment WITH(ROWLOCK, UPDLOCK) 
SET 
	StatusId = 0, 
	RemainingAmount = Amount 
WHERE 
	PaymentId IN (1308,4547,4548,4549,4550,4551,4552) 
	AND Environment = 'Pro' 
	AND StatusId = 1

--Delete in LA_Allocation table
DELETE FROM LA_Allocation WITH(ROWLOCK, UPDLOCK)
WHERE 
	AllocationID in (4376,4375,4331,4330) 
	AND Environment = 'Pro'






