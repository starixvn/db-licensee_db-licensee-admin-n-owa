/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20240513@Danny
	DB: DBCUST-bodb_Licensee
	Task: Update remaining amount existing Payment
*/
USE bodb_Licensee


-- Update value
UPDATE t
SET		t.StatusId = 1, -- Close
		t.RemainingAmount = 0
FROM LA_Payment t WITH(ROWLOCK, UPDLOCK)
WHERE t.StatusId = 0 AND Environment = 'PRO'



CREATE TABLE #tmp_Payment 
(
	LicenseeCode	VARCHAR(100),
	PaymentNo		VARCHAR(50),
	Refno			BIGINT,
	Amount			MONEY,
	RemainingAmount	MONEY,
	PartyID			INT
)

-- Insert data here
INSERT INTO #tmp_Payment (LicenseeCode, PaymentNo, Refno, Amount, RemainingAmount) VALUES ('PHL-LSEE-365ONLINE CNY','BHC OR-9595',16075483037564940,88033.82,88033.82)
INSERT INTO #tmp_Payment (LicenseeCode, PaymentNo, Refno, Amount, RemainingAmount) VALUES ('PHL-LSEE-WANBO CNY','BHC OR-9577',16075482232258574,14190.4,14190.4)
INSERT INTO #tmp_Payment (LicenseeCode, PaymentNo, Refno, Amount, RemainingAmount) VALUES ('PHL-LSEE-LEGENDWIN EUR','BHC OR-9516',15753895213793293,500.46,500.46)

-- Update PartyID from LicenseeCode
UPDATE  t
SET		t.PartyID = u.PartyID
FROM	#tmp_Payment t
OUTER APPLY (
	SELECT TOP 1 op.PartyID FROM OAS_PartyBaseCurrency op WITH(NOLOCK)
	WHERE t.LicenseeCode = op.LicenseeCode
) u

SELECT t.*
INTO #tmp_Payment_invalid
FROM #tmp_Payment t
LEFT JOIN LA_Payment li WITH(NOLOCK) ON li.PaymentNo = t.PaymentNo AND li.TransferRefno = t.Refno AND li.PartyID = t.PartyID  AND li.Environment = 'PRO'
WHERE t.PartyID IS NULL OR li.PartyID IS NULL OR ROUND(ABS(t.RemainingAmount),2) > ROUND(ABS(li.Amount),2)


IF EXISTS (SELECT TOP 1 1 FROM #tmp_Payment_invalid)
BEGIN
	SELECT 'Invalid input',* FROM #tmp_Payment_invalid
	RETURN
END
ELSE
BEGIN
	UPDATE li
	SET li.RemainingAmount = t.RemainingAmount,
		li.StatusID = 0
	FROM LA_Payment li WITH(ROWLOCK, UPDLOCK)
	INNER JOIN #tmp_Payment t ON li.PaymentNo = t.PaymentNo AND li.TransferRefno = t.Refno AND li.PartyID = t.PartyID
	WHERE li.StatusID = 1 AND li.Environment = 'PRO'
END


DROP TABLE #tmp_Payment