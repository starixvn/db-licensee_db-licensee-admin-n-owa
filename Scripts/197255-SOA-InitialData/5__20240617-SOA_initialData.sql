/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20240617@Danny
	DB: DBCUST-bodb_Licensee
	Task: Update remaining amount existing invoice
*/
USE bodb_Licensee
DECLARE  @Environment VARCHAR(50) = 'PRO'

UPDATE t
SET t.RemainingAmount = 0,
	t.StatusId = 1 -- Close
FROM LA_Payment t WITH(ROWLOCK, UPDLOCK) 
WHERE PaymentId IN (571, 573) AND Environment = @Environment

UPDATE t
SET t.RemainingAmount = 0,
	t.StatusId = 1 -- Close
FROM LA_InvoiceHeader t WITH(ROWLOCK, UPDLOCK) 
WHERE InvoiceHeaderId = 26548 AND Environment = @Environment




GO
