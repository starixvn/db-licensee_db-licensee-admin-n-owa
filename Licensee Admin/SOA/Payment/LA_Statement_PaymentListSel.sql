/*<info serverAlias="DBACC-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Statement_PaymentListSel]
	@PaymentNo			VARCHAR(50)		= '',
	@RefNo				BIGINT			= NULL,
	@PayerIds			VARCHAR(MAX)	= '',
	@PaymentTypes		VARCHAR(100) = '', --: 0: Collection , 1: Rebate, 2: TransferOverPayment
	@ReceivedFromDate	DATE,
	@ReceivedToDate		DATE,
	@UploadedFromDate	DATE,
	@UploadedToDate		DATE,
	@IsHideVoidedPayment BIT = 1,
	@IsOnlyDisplayNAPReversedPayment BIT = 0

AS

/*
	Created: 20240507@Danny
	DB: DBACC.bodb_Licensee
	Task:  Payment dashboard
   
	Revisions: 
		- 20240507@Danny: Initialize SP [#206990]

	Param's Explanation:

	EXEC LA_Statement_PaymentListSel
		@PaymentNo = '',
		@RefNo = NULL,
		@ReceivedFromDate = '2023-01-01',
		@ReceivedToDate = '2024-08-01',
		@UploadedFromDate = '2023-01-01',
		@UploadedToDate = '2024-08-01',
		@PaymentTypes = '0,1,2',
		@PayerIds = '697,14,20,493,70,558,316,459,771,772,307,15,142,95,8564,39,8470,353,58,8483,460,7207,2954,43,457,486,8464,898,4053,1932,7430,101,4042,4082,699,97,7378,698,4079',
		@IsHideVoidedPayment = 1,
		@IsOnlyDisplayNAPReversedPayment = 0
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @PayerTab TABLE (PartyID INT)
	INSERT INTO @PayerTab (PartyID)
	SELECT CAST(value AS INT) FROM STRING_SPLIT(@PayerIds,',')

	DECLARE @PaymentTypeTab TABLE (PaymentType TINYINT)
	INSERT INTO @PaymentTypeTab(PaymentType)
	SELECT CAST(value AS INT) FROM STRING_SPLIT(@PaymentTypes,',')

	DECLARE @BalanceUpDay	SMALLDATETIME, @MoveBetsDay		SMALLDATETIME
		
	DECLARE @tblMoveBetBalanceUp AS TABLE (BalanceUpDay SMALLDATETIME, MoveBetsDay SMALLDATETIME)
	INSERT INTO @tblMoveBetBalanceUp(BalanceUpDay,MoveBetsDay)
	EXEC bodb02.dbo.Age_SelBalanceUpDay

	SELECT @BalanceUpDay = BalanceUpDay, @MoveBetsDay = MoveBetsDay FROM @tblMoveBetBalanceUp

	-- Get all payment
	DROP TABLE IF EXISTS  #tmp_LA_Payment
	CREATE TABLE #tmp_LA_Payment
	(
		PaymentId		INT,
		PaymentNo		VARCHAR(50),
		RefNo			BIGINT,
		Biller			NVARCHAR(10),
		PayerName		VARCHAR(50),
		PaymentType		TINYINT,
		PaymentTypeName	NVARCHAR(100),
		PaymentStatus	NVARCHAR(20),
		CurrencyName	VARCHAR(12),
		PaymentAmount	MONEY,
		RemainingAmount MONEY,
		ReceivedDate	DATETIME,
		UploadedDate	DATETIME,
		PaymentWinlostDate	DATETIME,
		IsAllowVoid		BIT DEFAULT 0,
		ModifiedUser	VARCHAR(50),
		ModifyDate		DATETIME,
		IsReversedbyNAP BIT DEFAULT 0,
		AffectedLicensees NVARCHAR(100)
	)

	CREATE INDEX idx_#tmp_LA_Payment_UploadedDate ON #tmp_LA_Payment(UploadedDate)

	INSERT INTO #tmp_LA_Payment(
		PaymentId, 
		PaymentNo, 
		RefNo, 
		Biller,
		PayerName, 
		PaymentType, 
		PaymentTypeName, 
		PaymentStatus, 
		CurrencyName, 
		PaymentAmount, 
		RemainingAmount, 
		ReceivedDate, 
		UploadedDate,
		PaymentWinlostDate,
		ModifiedUser,
		ModifyDate
	)
	SELECT	lp.PaymentId,
			lp.PaymentNo,
			lp.TransferRefno AS RefNo,
			bi.BillerNameAbbreviation AS Biller,
			op.PartyName AS Payer,
			lp.Type AS PaymentType,
			CASE WHEN lp.Type = 0 THEN 'Payment'
				 WHEN lp.Type = 1 THEN 'Transfer between 2 licensees'
				 WHEN lp.Type = 2 THEN 'Rebate Payment' END PaymentTypeName,
			CASE WHEN lp.StatusId = 0 THEN 'Active'
				 WHEN lp.StatusId = 1 THEN 'Closed'
				 WHEN lp.StatusId = -1 THEN 'Voided' END PaymentStatus,
			e.Code AS Currency,
			lp.Amount AS PaymentAmount,
			lp.RemainingAmount AS RemainingAmount,
			lp.ReceivedDate AS ReceivedDate,
			lp.CreatedDate AS UploadedDate,
			CONVERT(DATE,lp.CreatedDate) AS PaymentWinlostDate,
			lu.Username AS ModifiedUser,
			CASE WHEN lp.StatusId = -1  THEN lp.ModifyDate ELSE NULL END ModifyDate
	FROM	LA_Payment lp WITH(NOLOCK)
	INNER JOIN OAS_Party op WITH(NOLOCK) ON lp.PartyID = op.PartyID
	INNER JOIN bodb02.dbo.Exchange e WITH(NOLOCK) ON lp.CurrencyId = e.ExchangeID
	INNER JOIN LA_BillerInfo bi WITH(NOLOCK) ON bi.PartyId = lp.BillerId
	LEFT JOIN LA_User lu WITH(NOLOCK) ON lu.UserID = lp.ModifiedBy AND lp.StatusId = -1 
	WHERE ( @PaymentNo = '' OR lp.PaymentNo = @PaymentNo)
	AND (@RefNo IS NULL OR lp.TransferRefno = @RefNo)
	AND  (lp.PartyID IN (SELECT z.PartyID FROM @PayerTab z) OR @PayerIds = '')
	AND lp.Type IN (SELECT x.PaymentType FROM @PaymentTypeTab x)
	AND lp.ReceivedDate BETWEEN @ReceivedFromDate AND @ReceivedToDate
	AND lp.CreatedDate >= @UploadedFromDate AND   lp.CreatedDate < DATEADD(DAY,1,@UploadedToDate)
	AND ( 
			(lp.StatusId <> -1 AND @IsHideVoidedPayment = 1)
			OR 
			@IsHideVoidedPayment = 0
		)

	-- Update AffectedLicensees
	BEGIN
		UPDATE  #tmp_LA_Payment SET AffectedLicensees = PayerName WHERE PaymentType IN (0,2)

		UPDATE t
		SET  t.AffectedLicensees = u.AffectedLicensees
		FROM #tmp_LA_Payment t 
		CROSS APPLY (
			SELECT STRING_AGG(op.PartyName,', ') AffectedLicensees
			FROM	LA_Payment u WITH(NOLOCK) 
			INNER JOIN OAS_party op WITH(NOLOCK) ON u.PartyID = op.PartyID
			WHERE u.TransferRefno = t.RefNo AND u.PaymentNo = t.PaymentNo AND  u.Type = 1
		) u
		WHERE t.PaymentType = 1
	END

	-- UPDATE NAP status
	IF EXISTS (SELECT TOP 1 1 FROM #tmp_LA_Payment WHERE PaymentWinlostDate >= @BalanceUpDay)
	BEGIN
		UPDATE t
		SET t.IsReversedbyNAP = 1
		FROM #tmp_LA_Payment t
		WHERE EXISTS (
			SELECT TOP 1 1  FROM bodb02.dbo.Transfer_Coll tc WITH(NOLOCK)
			WHERE tc.WinlostDate = t.PaymentWinlostDate AND tc.TransDesc LIKE '(Reversal)%' AND tc.refno = t.RefNo
		)
		AND t.PaymentWinlostDate >= @BalanceUpDay
	END

	IF EXISTS (SELECT TOP 1 1 FROM #tmp_LA_Payment WHERE PaymentWinlostDate < @BalanceUpDay)
	BEGIN
		UPDATE t
		SET t.IsReversedbyNAP = 1
		FROM #tmp_LA_Payment t
		WHERE EXISTS (
			SELECT TOP 1 1  FROM bodb_Archive.dbo.Transfer_Coll_BK tc WITH(NOLOCK)
			WHERE tc.WinlostDate = t.PaymentWinlostDate AND tc.TransDesc LIKE '(Reversal)%' AND tc.refno = t.RefNo
		)
		AND t.PaymentWinlostDate < @BalanceUpDay
	END

	-- Update IsAllowVoid
	UPDATE t
	SET t.IsAllowVoid = 1
	FROM #tmp_LA_Payment t
	WHERE t.IsReversedbyNAP = 1 AND t.PaymentAmount = t.RemainingAmount

	DELETE FROM #tmp_LA_Payment
	WHERE @IsOnlyDisplayNAPReversedPayment = 1 AND IsReversedbyNAP = 0

	-- Result
	SELECT	PaymentId,
			PaymentNo,
			PayerName,
			PaymentType,
			PaymentTypeName,
			PaymentStatus,
			PaymentAmount,
			RemainingAmount,
			ReceivedDate,
			UploadedDate,
			IsReversedbyNAP,
			IsAllowVoid,
			ModifiedUser,
			ModifyDate,
			RefNo,
			Biller,
			AffectedLicensees,
			CurrencyName
	FROM #tmp_LA_Payment


	
END
GO