/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE dbo.LA_Statement_AgingReport
	@BillerIds			VARCHAR(4000) = '',
	@PayerIds			VARCHAR(MAX)  = '',
	@AsOfDate			DATE,
	@PlatformId			TINYINT = 0,
	@IsExcludePayment	BIT = 0,
	@Environment		VARCHAR(10)		= 'LOCAL',
	@GroupBy			TINYINT = 0 -- 0: Group by Biller, 1: Group by Payer
AS
/*
	Created: 20240819@Danny
	DB: DBLIC.bodb_Licensee
	Task:  aging report
   
	Revisions: 
		- 20241209@Danny: Initialize SP [#206240]
		- 20250306@Danny: Enhancement [#219206]
		- 20250409@Danny: Return CurrencyId column [#221841]
		- 20250421@Eddie: Support Platform for SabaPlay [RemineID: #221990]

	Param's Explanation:
		- @PlatformId : 
			1 : Saba Sports
			2 : White Label China View
			3 : JollySports
			99: SabaPlay
	EXEC LA_Statement_AgingReport 
		@BillerIds			 = '192,181,295,189,281,318,178,106,112,833,298,307,113,173,293,187,287,233,310,362,279,8637,270,290,788,428,288,188,125,265,317,666,291,116,222,274,182,208,302,494,309,286,426,280,223,123,297,177,8504,289,197,423,277,8581,320',
		@PayerIds			  = '14',
		@AsOfDate			 = '2025-03-31',
		@IsExcludePayment	= 0,
		@Environment		= 'LOCAL',
		@GroupBy			= 0

*/
BEGIN
	SET NOCOUNT ON

	DECLARE 
			@StatementDate			 DATE = @AsOfDate,
			@Start_Aging_0_to_30	 DATE,
			@End_Aging_0_to_30		 DATE,
			@Start_Aging_31_to_60	 DATE,
			@End_Aging_31_to_60		 DATE,
			@Start_Aging_61_to_90	 DATE,
			@End_Aging_61_to_90		 DATE,
			@Start_AgingMore_Than_90 DATE,
			@End_AgingMore_Than_90	 DATE


	DROP TABLE IF EXISTS #tmp_BillerID
	CREATE TABLE #tmp_BillerID (BillerID INT)
	INSERT INTO #tmp_BillerID (BillerID) SELECT CAST(VALUE AS INT) FROM STRING_SPLIT(@BillerIds,',')

	DROP TABLE IF EXISTS #All_Doc_By_Party
	CREATE TABLE #All_Doc_By_Party 
	(
		BillerID				INT,
		PayerID					INT,
		Payer					NVARCHAR(100),
		CurrencyID				INT,
		DocumentID				INT,
		DocumentNo				VARCHAR(50),
		DocumentTypeID			SMALLINT,
		DocumentDetailTypeID	SMALLINT,
		DocumentDate			DATE,
		OrgAmount				MONEY,
		RemainingAmount			MONEY, 
		StatusID				SMALLINT
	)

	DROP TABLE IF EXISTS #D_C_Inv_Detail
	CREATE TABLE #D_C_Inv_Detail 
	( 
		DocumentID		INT, 
		DocumentDate	DATE, 
		Refno			VARCHAR(50), 
		RefAmount		MONEY, 
		RefStatusID		SMALLINT, 
		RefInvDate	    DATE,
		RefInvType		SMALLINT
	)

	DROP TABLE IF EXISTS #Result
	CREATE TABLE #Result 
	(
		BillerID				INT,
		PayerID					INT,
		Payer					NVARCHAR(100),
		CurrencyID				INT,
		DocumentID				INT,
		DocumentNo				VARCHAR(50),
		DocumentTypeID			SMALLINT,
		DocumentDetailTypeID	SMALLINT,
		DocumentDate			DATE,
		[0_30]					MONEY,
		[31_60]					MONEY,
		[61_90]					MONEY,
		[90+]					MONEY
	)

	IF EOMONTH(@StatementDate) = @StatementDate
	BEGIN
		SELECT @Start_Aging_0_to_30		=	DATEADD(DAY,1,EOMONTH(@StatementDate,-1))
	END
	ELSE
	BEGIN
		SELECT @Start_Aging_0_to_30 =	DATEADD(MONTH,-1,DATEADD(DAY,1,EOMONTH(@StatementDate,-1)))
	END

	SELECT @End_Aging_0_to_30   =	@StatementDate
	SELECT @End_Aging_31_to_60   =	DATEADD(DAY,-1,@Start_Aging_0_to_30)
	SELECT @Start_Aging_31_to_60 =	DATEADD(DAY,1,EOMONTH(@End_Aging_31_to_60,-1))
	SELECT @End_Aging_61_to_90	 =	DATEADD(DAY,-1,@Start_Aging_31_to_60)
	SELECT @Start_Aging_61_to_90 =	DATEADD(DAY,1,EOMONTH(@End_Aging_61_to_90,-1))
	SELECT @End_AgingMore_Than_90 =	DATEADD(DAY,-1,@Start_Aging_61_to_90)
	SELECT @Start_AgingMore_Than_90 = DATEADD(DAY,1,EOMONTH(@End_AgingMore_Than_90,-1))

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PayerIds = STRING_AGG(CONVERT(VARCHAR(50), t.PartyID), ',')
		FROM (
			SELECT p.PartyID
			FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
				INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
				INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
			WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PayerIds, ','))
			  AND @PlatformId <> 99
			
			UNION ALL
			
			SELECT p.PartyID
			FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
			WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PayerIds, ','))
			  AND p.PlatformId = 2
			  AND @PlatformId = 99
		) AS t
	END

	DROP TABLE IF EXISTS #tmp_PartyID
	CREATE TABLE #tmp_PartyID (PartyID INT)
	INSERT INTO #tmp_PartyID (PartyID) SELECT CAST(VALUE AS INT) FROM STRING_SPLIT(@PayerIds,',')

	-- Get all documents
	BEGIN
		INSERT INTO #All_Doc_By_Party 
		(
			BillerID			,
			PayerID				,
			Payer				,
			CurrencyID			,
			DocumentID			,
			DocumentNo			,
			DocumentTypeID		,  -- 0: Inv, 1: Payment
			DocumentDetailTypeID,  -- InvTypeID, PaymentTypeID
			DocumentDate		,
			OrgAmount			,
			RemainingAmount		, 
			StatusID			
		)
		SELECT  li.BillerId,
				li.PartyId,
				ISNULL(CASE WHEN li.InvoiceType NOT IN (4,5) THEN CASE WHEN inv.ActiveAddress = 1 THEN opd.CompanyName ELSE opd.CompanyName2 END
					        WHEN li.InvoiceType  IN (4,5) THEN CASE WHEN inv1.ActiveAddress = 1 THEN opd.CompanyName ELSE opd.CompanyName2   END
						END,op.PartyName) Payer,
				li.CurrencyId,
				li.InvoiceHeaderId, 
				li.OfficialInvoiceNo,
				0 AS DocumentTypeID,
				li.InvoiceType AS DocumentDetailTypeID,
				li.InvoiceDate,
				ROUND(li.Amount,2) AS OrgAmount,
				ROUND(ISNULL(li.RemainingAmount,li.Amount),2) RemainingAmount,
				li.StatusId
		FROM	dbo.LA_InvoiceHeader li WITH(NOLOCK)
		INNER JOIN #tmp_PartyID p ON li.PartyId = p.PartyID
		INNER JOIN #tmp_BillerID b ON li.BillerID = b.BillerID
		OUTER APPLY 
		(
				SELECT MAX(ls.ActiveAddress) ActiveAddress
				FROM LA_InvoiceSetting ls WITH(NOLOCK)
				WHERE ls.FromPartyId = li.PartyId AND ls.ToPartyId = li.BillerId AND ls.InvTypeId = li.InvoiceType
				AND li.InvoiceType NOT IN (4,5)
		) inv
		OUTER APPLY 
		(
				SELECT MAX(ls.ActiveAddress) ActiveAddress
				FROM LA_InvoiceStatement lis WITH(NOLOCK)
				INNER JOIN LA_InvoiceHeader lih WITH(NOLOCK) ON lis.refno = lih.OfficialInvoiceNo AND lih.StatusID <> -1
				INNER JOIN LA_InvoiceSetting ls WITH(NOLOCK) ON ls.FromPartyId = lih.PartyId AND ls.ToPartyId = lih.BillerId AND ls.InvTypeId = lih.InvoiceType
				WHERE  li.InvoiceType IN (4,5) AND lis.InvoiceHeaderId = li.InvoiceHeaderId
		) inv1
		INNER JOIN OAS_Party op WITH(NOLOCK) ON op.PartyID = li.PartyId
		INNER JOIN OAS_PartyDetail opd WITH(NOLOCK) ON opd.PartyID = op.PartyID
		WHERE	li.Environment = @Environment AND li.InvoiceDate <= @StatementDate
				AND li.StatusId <> -1 
		
		IF @IsExcludePayment = 0 
		BEGIN
			INSERT INTO #All_Doc_By_Party 
			(
				BillerID			,
				PayerID				,
				Payer				,
				CurrencyID			,
				DocumentID			,
				DocumentNo			,
				DocumentTypeID		,  -- 0: Inv, 1: Payment
				DocumentDetailTypeID,  -- InvTypeID, PaymentTypeID
				DocumentDate		,
				OrgAmount			,
				RemainingAmount		, 
				StatusID			
			)
			
			SELECT  lp.BillerId,
					lp.PartyID,
					ISNULL(CASE WHEN lp.Type = 2 THEN CASE WHEN inv.ActiveAddress = 2 THEN opd.CompanyName2
													WHEN inv.ActiveAddress = 1 THEN opd.CompanyName END
						 ELSE opd.CompanyName END,op.PartyName),
					lp.CurrencyId,
					lp.PaymentId, 
					lp.PaymentNo,
					1 AS DocumentTypeID,
					lp.Type AS DocumentDetailTypeID,
					lp.ReceivedDate,
					-lp.Amount AS OrgAmount,
					-ISNULL(lp.RemainingAmount,lp.Amount) RemainingAmount,
					lp.StatusId
			FROM	dbo.LA_Payment lp WITH(NOLOCK)
			INNER JOIN #tmp_PartyID p ON lp.PartyId = p.PartyID
			INNER JOIN #tmp_BillerID b ON lp.BillerID = b.BillerID
			OUTER APPLY 
			(
					SELECT MAX(ls.ActiveAddress) ActiveAddress
					FROM LA_InvoiceSetting ls WITH(NOLOCK)
					WHERE ls.FromPartyId = lp.PartyId AND ls.ToPartyId = lp.BillerId AND ls.InvTypeId = 3
			) inv
			INNER JOIN OAS_Party op WITH(NOLOCK) ON op.PartyID = lp.PartyId
			INNER JOIN OAS_PartyDetail opd WITH(NOLOCK) ON opd.PartyID = op.PartyID
			WHERE	lp.Environment = @Environment AND lp.ReceivedDate <= @StatementDate AND lp.StatusId = 0
			
		END

		IF EXISTS (SELECT TOP 1 1 FROM #All_Doc_By_Party WHERE DocumentTypeID = 0 AND DocumentDetailTypeID IN (4,5) AND StatusID = 0)
		BEGIN
			INSERT INTO #D_C_Inv_Detail( DocumentID, DocumentDate, Refno, RefAmount, RefStatusID, RefInvDate, RefInvType)
			SELECT t.DocumentID, t.DocumentDate, st.RefNo, ISNULL(st.Income,0) -  ISNULL(st.Expense,0), m.StatusID, m.DocumentDate, m.DocumentDetailTypeID
			FROM  #All_Doc_By_Party t
			INNER JOIN dbo.LA_InvoiceStatement st WITH(NOLOCK) ON t.DocumentID = st.InvoiceHeaderId
			INNER JOIN #All_Doc_By_Party m ON st.RefNo = m.DocumentNo AND m.StatusID <> -1
			WHERE t.DocumentTypeID = 0 AND t.DocumentDetailTypeID IN (4,5) AND t.StatusID <> -1
		END

	END

	INSERT INTO #Result (
		BillerID				,
		PayerID					,
		Payer					,
		CurrencyID				,
		DocumentID				,
		DocumentNo				,
		DocumentTypeID			,
		DocumentDetailTypeID	,
		DocumentDate			,
		[0_30]					,
		[31_60]					,
		[61_90]					,
		[90+]					
			
	)
	SELECT  BillerID			,
			PayerID				,
			Payer				,
			CurrencyID			,
			DocumentID			,
			DocumentNo			,
			DocumentTypeID		,  
			DocumentDetailTypeID,  
			DocumentDate		,
			CASE WHEN  DocumentDate BETWEEN @Start_Aging_0_to_30 AND @End_Aging_0_to_30 THEN RemainingAmount ELSE 0 END [0_30], 
			CASE WHEN  DocumentDate BETWEEN @Start_Aging_31_to_60 AND @End_Aging_31_to_60 THEN RemainingAmount ELSE 0 END [31_60],
			CASE WHEN  DocumentDate BETWEEN @Start_Aging_61_to_90 AND @End_Aging_61_to_90 THEN RemainingAmount ELSE 0 END [61_90],
			CASE WHEN  DocumentDate <= @End_AgingMore_Than_90 THEN RemainingAmount ELSE 0 END [90+]
		
	FROM #All_Doc_By_Party
	WHERE  (
			(DocumentTypeID = 0 AND DocumentDetailTypeID IN (4,5) AND RemainingAmount <> OrgAmount ) -- Partial Allocate
			OR
			(DocumentTypeID = 0 AND DocumentDetailTypeID NOT IN (4,5))
			OR
			(DocumentTypeID = 1)
	) AND StatusID = 0


	IF EXISTS (	SELECT	TOP 1 1 
				FROM	#All_Doc_By_Party 
				WHERE	DocumentTypeID = 0 AND DocumentDetailTypeID IN (4,5) 
						AND RemainingAmount = OrgAmount 
							AND StatusID = 0
				)
	BEGIN

		INSERT INTO #Result (
			BillerID				,
			PayerID					,
			Payer					,
			CurrencyID				,
			DocumentID				,
			DocumentNo				,
			DocumentTypeID			,
			DocumentDetailTypeID	,
			DocumentDate			,
			[0_30]					,
			[31_60]					,
			[61_90]					,
			[90+]					
			
		 )
		SELECT  BillerID			,
			PayerID				,
			Payer				,
			CurrencyID			,
			DocumentID			,
			DocumentNo			,
			DocumentTypeID		,  
			DocumentDetailTypeID,  
			DocumentDate		,
			d.[0_30], 
			d.[31_60],
			d.[61_90],
			d.[90+]
		
		FROM #All_Doc_By_Party  x
		OUTER APPLY 
		(
			SELECT	 SUM (CASE WHEN (t.RefInvDate BETWEEN @Start_Aging_0_to_30 AND @End_Aging_0_to_30 AND t.RefStatusID = 0 )
								OR (t.DocumentDate BETWEEN @Start_Aging_0_to_30 AND @End_Aging_0_to_30 AND t.RefStatusID = 1)
								THEN t.RefAmount ELSE 0 END) [0_30],
					 SUM (CASE WHEN (t.RefInvDate BETWEEN @Start_Aging_31_to_60 AND @End_Aging_31_to_60 AND t.RefStatusID = 0 )
							OR (t.DocumentDate BETWEEN @Start_Aging_31_to_60 AND @End_Aging_31_to_60 AND t.RefStatusID = 1 )
								THEN t.RefAmount ELSE 0 END) [31_60],
					 SUM (CASE WHEN  (t.RefInvDate BETWEEN @Start_Aging_61_to_90 AND @End_Aging_61_to_90 AND t.RefStatusID = 0)
							OR (t.DocumentDate BETWEEN @Start_Aging_61_to_90 AND @End_Aging_61_to_90 AND t.RefStatusID = 1)
							THEN t.RefAmount ELSE 0 END) [61_90],
					 SUM (CASE WHEN  (t.RefInvDate <= @End_AgingMore_Than_90 AND t.RefStatusID = 0)
							OR (t.DocumentDate <= @End_AgingMore_Than_90 AND t.RefStatusID = 1)
						THEN t.RefAmount ELSE 0 END) [90+]
				 
			FROM	#D_C_Inv_Detail t
			WHERE	t.DocumentID = x.DocumentID
			GROUP BY t.DocumentID
		) d
		WHERE	x.DocumentTypeID = 0 AND x.DocumentDetailTypeID IN (4,5) 
				AND x.RemainingAmount = x.OrgAmount  AND x.StatusID = 0
	
	END

	IF @GroupBy = 0
	BEGIN
		SELECT
			lb.CompanyName Biller, 
			r.Payer, 
			r.BillerID,
			r.PayerID,
			r.CurrencyID,
			 e.Code AS Currency,
			 r.DocumentNo,
			 r.DocumentDate,
			 r.[0_30] Amount_0_to_30_Days,
			 r.[31_60] Amount_31_to_60_Days,
			 r.[61_90] Amount_61_to_90_Days,
			 r.[90+] Amount_More_Than_90_Days
		FROM #Result r
		INNER JOIN OAS_Party op WITH(NOLOCK) ON op.PartyID = r.PayerID
		INNER JOIN OAS_PartyDetail opd WITH(NOLOCK) ON op.PartyID =  opd.PartyID
		INNER JOIN LA_BillerInfo lb WITH(NOLOCK) ON lb.PartyId = r.BillerID
		INNER JOIN bodb02.dbo.Exchange e WITH(NOLOCK) ON r.CurrencyID = e.ExchangeId
		ORDER BY lb.CompanyName, e.Code DESC, r.Payer,  r.DocumentDate
	END
	ELSE 
	BEGIN
		SELECT 
			 r.Payer, 
			 lb.BillerNameAbbreviation Biller, 
			r.BillerID,
			r.PayerID,
			r.CurrencyID,
			 e.Code AS Currency,
			 r.DocumentNo,
			 r.DocumentDate,
			 r.[0_30] Amount_0_to_30_Days,
			 r.[31_60] Amount_31_to_60_Days,
			 r.[61_90] Amount_61_to_90_Days,
			 r.[90+] Amount_More_Than_90_Days
		FROM #Result r
		INNER JOIN OAS_Party op WITH(NOLOCK) ON op.PartyID = r.PayerID
		INNER JOIN OAS_PartyDetail opd WITH(NOLOCK) ON op.PartyID =  opd.PartyID
		INNER JOIN LA_BillerInfo lb WITH(NOLOCK) ON lb.PartyId = r.BillerID
		INNER JOIN bodb02.dbo.Exchange e WITH(NOLOCK) ON r.CurrencyID = e.ExchangeId
		ORDER BY  r.Payer, e.Code DESC,  lb.BillerNameAbbreviation, r.DocumentDate, r.DocumentNo
	END
		
END
GO
