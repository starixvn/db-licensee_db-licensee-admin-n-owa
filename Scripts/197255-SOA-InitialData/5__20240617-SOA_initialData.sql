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
FROM LA_InvoiceHeader t WITH(ROWLOCK, UPDLOCK) 
WHERE InvoiceHeaderId IN 
(
17877,
19142,
18165,
18820,
19144,
19148,
19668,
20033,
20443,
20929,
23564,
22705,
17860,
12868,
11802,
13788,
15075
)AND Environment = @Environment

GO
