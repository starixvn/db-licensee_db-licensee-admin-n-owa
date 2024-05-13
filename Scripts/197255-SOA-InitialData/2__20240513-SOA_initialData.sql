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
WHERE t.StatusId = 0 AND Environment = 'LOCAL'



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
INSERT INTO #tmp_Payment (LicenseeCode, PaymentNo, Refno, Amount, RemainingAmount) VALUES ('PHL-LSEE-Gamingsoft EUR','BCH OR 132',13065205958049792,-100.84,-100.84)
INSERT INTO #tmp_Payment (LicenseeCode, PaymentNo, Refno, Amount, RemainingAmount) VALUES ('PHL-LSEE-Gamingsoft EUR','BCH OR 111',12835008595361792,-9.73,-9.73)
INSERT INTO #tmp_Payment (LicenseeCode, PaymentNo, Refno, Amount, RemainingAmount) VALUES ('PHL-LSEE-Gamingsoft EUR','BCH OR 113',12899325194272768,100.58,50.99)
INSERT INTO #tmp_Payment (LicenseeCode, PaymentNo, Refno, Amount, RemainingAmount) VALUES ('PHL-LSEE-12BET EUR','BCH OR 113',12899325194272768,-100.58,-60.99)

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
LEFT JOIN LA_Payment li WITH(NOLOCK) ON li.PaymentNo = t.PaymentNo AND li.TransferRefno = t.Refno AND li.PartyID = t.PartyID 
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
	WHERE li.StatusID = 1
END


DROP TABLE #tmp_Payment