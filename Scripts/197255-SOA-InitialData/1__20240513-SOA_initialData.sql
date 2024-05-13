/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20240513@Danny
	DB: DBCUST-bodb_Licensee
	Task: Update remaining amount existing invoice
*/
USE bodb_Licensee

ALTER TABLE LA_InvoiceHeader Add RemainingAmount MONEY DEFAULT 0 -- Add new column 

/*
-- update status for all invoice

-- add 

CREATE TABLE #tmp_headerID (InvoiceHeaderID INT)

WHILE EXISTS (SELECT TOP 1 1 FROM LA_InvoiceHeader WITH(NOLOCK) WHERE StatusId = 0 AND Environment = 'LOCAL' AND  InvoiceType IN  (1,3,6,7,4,5) )
BEGIN
	TRUNCATE TABLE #tmp_headerID

	INSERT INTO #tmp_headerID (InvoiceHeaderID)
	SELECT TOP 1200 InvoiceHeaderID FROM LA_InvoiceHeader WITH(NOLOCK) WHERE StatusId = 0 AND Environment = 'LOCAL' AND  InvoiceType IN  (1,3,6,7,4,5)

	UPDATE t
	SET		t.StatusId = 1 -- Close
	FROM LA_InvoiceHeader t WITH(ROWLOCK, UPDLOCK)
	INNER JOIN #tmp_headerID u ON t.InvoiceHeaderID = u.InvoiceHeaderID
END

DROP TABLE #tmp_headerID

*/

GO

CREATE TABLE #tmp_Inv 
(
	OfficialInvoiceNo NVARCHAR(50),
	Amount			MONEY,
	RemainingAmount	MONEY
)

-- Insert data here
INSERT INTO #tmp_Inv (OfficialInvoiceNo, Amount, RemainingAmount) VALUES ('IWV 12058',52.3797,10.99)
INSERT INTO #tmp_Inv (OfficialInvoiceNo, Amount, RemainingAmount) VALUES ('Jo012',-50044.5603,-20000.01)
INSERT INTO #tmp_Inv (OfficialInvoiceNo, Amount, RemainingAmount) VALUES ('IWV 12065',-600,-100)
INSERT INTO #tmp_Inv (OfficialInvoiceNo, Amount, RemainingAmount) VALUES ('BoP4444644',-1,-2.99)
INSERT INTO #tmp_Inv (OfficialInvoiceNo, Amount, RemainingAmount) VALUES ('DNW031',20,30.99)
INSERT INTO #tmp_Inv (OfficialInvoiceNo, Amount, RemainingAmount) VALUES ('SF015',20000,100.99)
INSERT INTO #tmp_Inv (OfficialInvoiceNo, Amount, RemainingAmount) VALUES ('IWV 12072',4600.15,4600.15)

SELECT t.* INTO #tmp_Inv_invalid
FROM #tmp_Inv t 
LEFT JOIN  LA_InvoiceHeader li WITH(NOLOCK) ON li.OfficialInvoiceNo = t.OfficialInvoiceNo AND li.StatusId = 0
WHERE li.OfficialInvoiceNo IS NULL OR ROUND(ABS(t.RemainingAmount),2) > ROUND(ABS(li.Amount),2)


IF EXISTS (SELECT TOP 1 1 FROM #tmp_Inv_invalid)
BEGIN
	SELECT 'Invalid input',* FROM #tmp_Inv_invalid
	RETURN
END
ELSE
BEGIN
	UPDATE li
	SET li.RemainingAmount = t.RemainingAmount
	FROM LA_InvoiceHeader li WITH(ROWLOCK, UPDLOCK)
	INNER JOIN #tmp_Inv t ON li.OfficialInvoiceNo = t.OfficialInvoiceNo
	WHERE li.StatusID = 0

END

DROP TABLE #tmp_Inv