/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20251003@Winston
	DB: DBCUST.bodb_licensee
	Description: Update payment info
*/



--Update in LA_Payment table
UPDATE LA_Payment WITH(ROWLOCK, UPDLOCK) 
SET 
	StatusId = 0, 
	RemainingAmount = Amount 
WHERE 
	PaymentId IN (7488,7489,7490,7491) 
	AND Environment = 'Pro' 
	AND StatusId = 1

--Update in LA_InvoiceHeader table
UPDATE LA_InvoiceHeader WITH(ROWLOCK, UPDLOCK) 
SET 
	StatusId = 0, 
	RemainingAmount = Amount 
WHERE 
	InvoiceHeaderId IN (37552,37554,37555,37556) 
	AND Environment = 'Pro' 
	AND StatusId = 1

--Delete in LA_Allocation table
DELETE FROM LA_Allocation WITH(ROWLOCK, UPDLOCK)
WHERE 
	AllocationID in (7626,7627,7629,7630)
	AND Environment = 'Pro'








