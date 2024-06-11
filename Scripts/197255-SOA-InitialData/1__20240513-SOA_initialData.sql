/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20240513@Danny
	DB: DBCUST-bodb_Licensee
	Task: Update remaining amount existing invoice
*/
USE bodb_Licensee


GO

CREATE TABLE #tmp_Inv 
(
	OfficialInvoiceNo NVARCHAR(50),
	Amount			MONEY,
	RemainingAmount	MONEY
)

-- Insert data here
INSERT INTO #tmp_Inv (OfficialInvoiceNo, Amount, RemainingAmount) VALUES ('BHC INV 16208',49890.7,39680.13)				
INSERT INTO #tmp_Inv (OfficialInvoiceNo, Amount, RemainingAmount) VALUES ('BHC INV 16569',21511.5929,10432.41)				
INSERT INTO #tmp_Inv (OfficialInvoiceNo, Amount, RemainingAmount) VALUES ('ZL INV 4375',2331.2,5.2)				


UPDATE li
SET li.RemainingAmount = t.RemainingAmount
FROM LA_InvoiceHeader li WITH(ROWLOCK, UPDLOCK)
INNER JOIN #tmp_Inv t ON li.OfficialInvoiceNo = t.OfficialInvoiceNo
WHERE li.StatusID = 0 AND li.Environment = 'PRO'


DROP TABLE #tmp_Inv