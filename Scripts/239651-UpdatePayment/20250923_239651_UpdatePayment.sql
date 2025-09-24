/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250923@Winston
	DB: DBCUST.bodb_licensee
	Description: Update payment info
*/



--Update in LA_Payment table
UPDATE LA_Payment WITH(ROWLOCK, UPDLOCK) 
SET 
	StatusId = 0, 
	RemainingAmount = Amount 
WHERE 
	PaymentId IN (7146) 
	AND Environment = 'Pro' 
	AND StatusId = 1

--Update in LA_InvoiceHeader table
UPDATE LA_InvoiceHeader WITH(ROWLOCK, UPDLOCK) 
SET 
	StatusId = 0, 
	RemainingAmount = Amount 
WHERE 
	InvoiceHeaderId IN (37609) 
	AND Environment = 'Pro' 
	AND StatusId = 1

--Delete in LA_Allocation table
DELETE FROM LA_Allocation WITH(ROWLOCK, UPDLOCK)
WHERE 
	AllocationID in (7152) 
	AND Environment = 'Pro'








