/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20240513@Danny
	DB: DBCUST-bodb_Licensee
	Task: Update remaining amount existing Payment
*/
USE bodb_licensee

DECLARE @UserID INT 

SELECT TOP 1 @UserID = UserID FROM  LA_User WITh(NOLOCK) WHERE  Username = 'starixIT' 

CREATE TABLE #tmp_Payment 
( 
	[LicenseeCode] [varchar](50) NULL,
	[PaymentNo] [varchar](50) NULL,
	[TransferRefno] [bigint] NULL,
	[ReceivedDate] [date] NULL,
	[RebatePayment] [VARCHAR](10) NULL,
	[Amount] [money] NULL,
	[RemainingAmount] [money] NULL,
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
	FROM dbo.OAS_PartyBaseCurrency op WITH(NOLOCK)
	INNER JOIN CustDB.dbo.custInfo ci WITH(NOLOCK) ON op.LicenseeCode = ci.username
	INNER JOIN dbo.LicenseeTransferCode lt  WITH(NOLOCK) ON ci.custid = lt.CustID
	WHERE t.LicenseeCode = op.LicenseeCode
) u


SELECT  *
INTO #tmp_Payment_invalid
FROM #tmp_Payment
WHERE CustID IS NULL 
	OR WinlostDate IS NULL 
	OR PartyID IS NULL 
	OR CurrencyId IS NULL
	OR TransferRefno IS NULL
	--OR Amount <> RemainingAmount

-- Check input data
IF EXISTS (	SELECT TOP 1 1 FROM
			#tmp_Payment_invalid
		)
BEGIN
	SELECT 'Input is invalid!!', * FROM  #tmp_Payment_invalid
	RETURN
END
ELSE
BEGIN

	INSERT INTO [dbo].[LA_Payment] 
	(
		[PaymentNo],
		[ReceivedDate],
		[Type],
		[PartyID],
		[CurrencyId],
		[Amount],
		[RemainingAmount],
		[TransferRefno],
		[StatusId],
		[Environment],
		[CreatedDate],
		[CreatedBy],
		[ModifyDate],
		[ModifiedBy],
		[Remark]
	)
	SELECT [PaymentNo],
		[ReceivedDate],
		CASE WHEN RebatePayment = 'N' THEN 0 ELSE 2 END [Type],
		[PartyID],
		[CurrencyId],
		[Amount],
		[RemainingAmount],
		[TransferRefno],
		0,
		'LOCAL',
		GETDATE(),
		@UserID,
		GETDATE(),
		@UserID,
		CASE WHEN Amount < 0 THEN 'Payment made' ELSE 'Payment received' END [Remark]
	FROM #tmp_Payment
END

DROP TABLE #tmp_Payment
