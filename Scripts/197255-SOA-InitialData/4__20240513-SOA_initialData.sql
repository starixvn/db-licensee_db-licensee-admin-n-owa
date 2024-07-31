/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20240610@Danny
	DB: DBCUST-bodb_Licensee
	Task: Update remaining amount existing invoice
*/
USE bodb_Licensee
DECLARE  @Environment VARCHAR(50) = 'PRO'

-- update remaining data of New invoices -- 512 rows
UPDATE t
SET t.RemainingAmount = ROUND(Amount,2)
FROM LA_InvoiceHeader t WITH(ROWLOCK, UPDLOCK) 
WHERE t.InvoiceDate >= '2024-05-01' AND Environment = @Environment AND InvoiceType IN  (1,3,6,7,4,5) AND StatusId = 0

-- update remaining data of AMF Invoice Type  -- 40 rows
UPDATE t
SET t.RemainingAmount = ROUND(Amount,2)
FROM LA_InvoiceHeader t WITH(ROWLOCK, UPDLOCK) 
WHERE Environment = @Environment AND InvoiceType = 12 AND StatusId = 0


-- Update status of remaining invoices -- 21786 rows
CREATE TABLE #tmp_headerID (InvoiceHeaderID INT)

WHILE EXISTS (SELECT TOP 1 1 FROM LA_InvoiceHeader WITH(NOLOCK) WHERE StatusId = 0 AND Environment = @Environment AND  InvoiceType IN  (1,3,6,7,4,5) AND RemainingAmount = 0 )
BEGIN
	TRUNCATE TABLE #tmp_headerID

	INSERT INTO #tmp_headerID (InvoiceHeaderID)
	SELECT TOP 1200 InvoiceHeaderID FROM LA_InvoiceHeader WITH(NOLOCK) 
	WHERE StatusId = 0 
	AND Environment = @Environment 
	AND  InvoiceType IN  (1,3,6,7,4,5)
	AND RemainingAmount = 0

	UPDATE t
	SET		t.StatusId = 1 -- Close
	FROM LA_InvoiceHeader t WITH(ROWLOCK, UPDLOCK)
	INNER JOIN #tmp_headerID u ON t.InvoiceHeaderID = u.InvoiceHeaderID
END


DROP TABLE #tmp_headerID

GO
