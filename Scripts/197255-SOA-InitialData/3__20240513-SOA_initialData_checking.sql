/*<info serverAlias="DBARC-bodb_Archive"></info>*/
/*
	Created: 20240513@Danny
	DB: DBARC-bodb_Archive
	Task: Update remaining amount existing Payment
*/
USE bodb_Archive

CREATE TABLE #tmp_Payment 
( 
	[LicenseeCode] [varchar](50) NULL,
	[PaymentNo] [varchar](50) NULL,
	[TransferRefno] [bigint] NULL,
	[ReceivedDate] [date] NULL,
	[RebatePayment] [VARCHAR](10) NULL,
	[Amount] [money] NULL,
	[RemainingAmount] [money] NULL,

	[Remark] [nvarchar](500) NULL,
	[WinlostDate] [date] NULL,
	[CustID][int] NULL,
	[PartyID] [int] NULL,
	[CurrencyId] [int] NULL
)

-- Insert data here
INSERT INTO #tmp_Payment (LicenseeCode,PaymentNo,TransferRefno,ReceivedDate,RebatePayment,Amount,RemainingAmount,WinlostDate) VALUES ('PHL-LSEE-MACAOBET EUR','ZL OR-3000',15894484257341440,'2024-05-16','N',200,200,'2024-05-16')
INSERT INTO #tmp_Payment (LicenseeCode,PaymentNo,TransferRefno,ReceivedDate,RebatePayment,Amount,RemainingAmount,WinlostDate) VALUES ('PHL-LSEE-Mirabet EUR','ZL OR-3000',15894484257341440,'2024-05-16','N',300,300,'2024-05-16')

-- Update some info
UPDATE  t
SET		t.PartyID = u.PartyID,
		t.CurrencyId = u.BaseCurrencyId,
		t.CustID = u.CustID
FROM	#tmp_Payment t
OUTER APPLY (
	SELECT TOP 1 op.PartyID, op.BaseCurrencyId , lt.CustID
	FROM DBCUST.bodb_licensee.dbo.OAS_PartyBaseCurrency op WITH(NOLOCK)
	INNER JOIN bodb02.dbo.custInfo ci WITH(NOLOCK) ON op.LicenseeCode = ci.username
	INNER JOIN  DBCUST.bodb_licensee.dbo.LicenseeTransferCode lt  WITH(NOLOCK) ON ci.custid = lt.CustID
	WHERE t.LicenseeCode = op.LicenseeCode
) u


select * from #tmp_Payment

-- Check input data
IF EXISTS (	SELECT TOP 1 1 
			FROM #tmp_Payment
			WHERE CustID IS NULL 
				OR WinlostDate IS NULL 
				OR PartyID IS NULL 
				OR CurrencyId IS NULL
				OR TransferRefno IS NULL
				OR Amount <> RemainingAmount
		)
BEGIN
	SELECT 'Input is invalid!!'
	RETURN
END


-- Check refno

DECLARE @Refnos VARCHAR(MAX)
DECLARE @Refnos_bk VARCHAR(MAX)

DECLARE @MBU TABLE (BalanceUpDay SMALLDATETIME, MoveBetsDay SMALLDATETIME)
INSERT INTO @MBU (BalanceUpDay, MoveBetsDay)
EXEC DBTXN.bodb02.dbo.Age_SelBalanceUpDay

DECLARE @BalanceUpDay SMALLDATETIME, @MoveBetsDay SMALLDATETIME
SELECT  @BalanceUpDay = BalanceUpDay, @MoveBetsDay = MoveBetsDay FROM @MBU

IF EXISTS (

	SELECT	TOP 1 1 
	FROM	#tmp_Payment t
	OUTER APPLY (
		SELECT tr.refno 
		FROM bodb02.dbo.Transfer tr WITH(NOLOCK) 
		WHERE t.CustID = tr.CustId AND t.WinlostDate = tr.WinlostDate AND tr.Bettype = 21003
	) tr
	WHERE t.WinlostDate >= @BalanceUpDay AND tr.refno IS NULL
)
BEGIN
	SELECT 'Refno Input is invalid!!'
	RETURN
END


IF EXISTS (

	SELECT	TOP 1 1 
	FROM	#tmp_Payment t
	OUTER APPLY (
		SELECT tr.refno 
		FROM dbo.Transfer_Coll_bk tr WITH(NOLOCK) 
		WHERE t.CustID = tr.CustId AND t.WinlostDate = tr.WinlostDate AND tr.Bettype = 21003
	) tr
	WHERE t.WinlostDate < @BalanceUpDay AND tr.refno IS NULL
)
BEGIN
	SELECT 'Refno bk range Input is invalid!!'
	RETURN
END

	SELECT 'Input is valid!!'


DROP TABLE #tmp_Payment
