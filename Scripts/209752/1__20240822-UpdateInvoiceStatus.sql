/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20240617@Danny
	DB: DBCUST-bodb_Licensee
	Task: Update remaining amount existing invoice
*/
USE bodb_Licensee
DECLARE  @Environment VARCHAR(50) = 'PRO'

UPDATE t
SET t.StatusId = 0 -- Open
FROM LA_InvoiceHeader t WITH(ROWLOCK, UPDLOCK) 
WHERE InvoiceHeaderId = 28583 
AND Environment = @Environment AND statusid = -1

UPDATE t
SET t.StatusId = NULL -- Open
FROM LA_InvoiceStatement  t WITH(ROWLOCK, UPDLOCK) 
WHERE InvoiceHeaderId = 28583 
 AND statusid = -1

GO
