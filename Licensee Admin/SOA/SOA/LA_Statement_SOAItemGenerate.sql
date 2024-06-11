/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Statement_SOAItemGenerate]
	@BaseCurrency		VARCHAR(10) = 'EUR',
	@InvoiceSymbol		NVARCHAR(20) = '',
	@InvoiceNumber		INT = 0,
	@InvoiceDate		DATETIME = NULL,
	@InvoiceTypeId		SMALLINT = NULL,
	@Amount				MONEY = NULL,
	@StatementXml		NVARCHAR(MAX) = NULL, 
	@BillerId			INT = NULL,
	@PartyId			INT = NULL,
	@Environment		VARCHAR(10)		= 'LOCAL'
AS

/*
	Created: 20231122@Danny
	DB: DBCUST.bodb_Licensee
	Task:  payment allocation 
   
	Revisions: 
		- 20230908@Danny: Initialize SP [#194603]

	Param's Explanation:
	DECLARE 
	@StatementXml NVARCHAR(MAX) = 
		N'<Statements>
			<Statement>
				<Description>2024年4月的平台授权费</Description>
				<Reference>Jo003</Reference>
				<Amount>100</Amount>
				<ItemType>12</ItemType>
				<ProductCode />
			</Statement>
			<Statement>
				<Description>2024年4月的平台授权费</Description>
				<Reference>LN11211</Reference>
				<Amount>200</Amount>
				<ItemType>12</ItemType>
				<ProductCode />
			</Statement>
		</Statements>'

	EXEC LA_Statement_SOAItemGenerate
		@BaseCurrency	 = 'EUR',
		@InvoiceSymbol		 = N'CR',
		@InvoiceNumber		 = 16,
		@InvoiceDate		 = '2024-04-02',
		@InvoiceTypeId		 = 4,
		@Amount				 = -300.0000,
		@StatementXml		 = @StatementXml, 
		@BillerId			 = 833,
		@PartyId			 = 14,
		@Environment		  = 'LOCAL'

*/

BEGIN
	SET NOCOUNT ON

	DECLARE @SOAType				SMALLINT = 0, --1: SOA for reseller, 0: SOA for invoice
			@CurrencyID				INT,
			@StatementDate			DATETIME,
			@Start_Aging_0_to_30	DATE,
			@End_Aging_0_to_30		DATE,
			@Start_Aging_31_to_60	DATE,
			@End_Aging_31_to_60		DATE,
			@Start_Aging_61_to_90	DATE,
			@End_Aging_61_to_90		DATE,
			@Start_AgingMore_Than_90 DATE,
			@End_AgingMore_Than_90	DATE,
			@RefInvoiceTypeID		INT
	
	IF EOMONTH(@InvoiceDate) = @InvoiceDate
	BEGIN
		SELECT @Start_Aging_0_to_30		=	DATEADD(DAY,1,EOMONTH(@InvoiceDate,-1))
	END
	ELSE
	BEGIN
		SELECT @Start_Aging_0_to_30 =	DATEADD(MONTH,-1,DATEADD(DAY,1,EOMONTH(@InvoiceDate,-1)))
	END

	SELECT @End_Aging_0_to_30   =	@InvoiceDate
	SELECT @End_Aging_31_to_60   =	DATEADD(DAY,-1,@Start_Aging_0_to_30)
	SELECT @Start_Aging_31_to_60 =	DATEADD(DAY,1,EOMONTH(@End_Aging_31_to_60,-1))
	SELECT @End_Aging_61_to_90	 =	DATEADD(DAY,-1,@Start_Aging_31_to_60)
	SELECT @Start_Aging_61_to_90 =	DATEADD(DAY,1,EOMONTH(@End_Aging_61_to_90,-1))
	SELECT @End_AgingMore_Than_90 =	DATEADD(DAY,-1,@Start_Aging_61_to_90)
	SELECT @Start_AgingMore_Than_90 = DATEADD(DAY,1,EOMONTH(@End_AgingMore_Than_90,-1))

	IF @BaseCurrency IS NULL
	BEGIN
		-- Get current billing currency of licensee
		SELECT TOP 1 @CurrencyID = BaseCurrencyId
		FROM OAS_PartyBaseCurrency WITH(NOLOCK)
		WHERE PartyID = @PartyId AND FromDate <= GETDATE() AND ToDate >= GETDATE()
	END

	CREATE TABLE #All_Doc_By_Party 
	(
		DocumentID				INT,
		DocumentNo				VARCHAR(50),
		DocumentTypeID			SMALLINT,
		DocumentDetailTypeID	SMALLINT,
		DocumentDate			DATE,
		Description				NVARCHAR(500),
		OrgAmount				MONEY,
		RemainingAmount			MONEY, 
		StatusID				SMALLINT,
		SOAType					BIT 
	)
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

	CREATE TABLE #SOA_Doc_List(
		DocumentID				INT,
		DocumentNo				VARCHAR(50),
		DocumentTypeID			SMALLINT,
		DocumentDetailTypeID	SMALLINT,
		DocumentDate			DATE,
		Description				NVARCHAR(500),
		Amount					MONEY, --Inv Amt
		Payment					MONEY, --Payment Amt
		Balance					MONEY,
		OrgAmount				MONEY
	)

	DECLARE @InvoiceNo NVARCHAR(50) = CONVERT(NVARCHAR(15), @InvoiceNumber)
	SELECT  @InvoiceNo = @InvoiceSymbol + CASE WHEN @InvoiceNumber < 100 THEN RIGHT('00' + @InvoiceNo, 3) ELSE @InvoiceNo END

	BEGIN 
		-- Detect SOA Type
		IF @InvoiceTypeId IN (4,5)
		BEGIN
			DECLARE @Statement TABLE (ItemType SMALLINT, Amount MONEY, Description NVARCHAR(500), Reference NVARCHAR(100))
			DECLARE @Statement_XML XML
			IF ISNULL(@StatementXml, '') <> ''
			BEGIN
				SELECT @Statement_XML = CONVERT(XML, @StatementXml)

				INSERT INTO @Statement (ItemType, Amount, Description, Reference)
				SELECT s.ItemType, s.Amount, s.Description, s.Reference
				FROM (
					SELECT
						t.c.value('(ItemType/text())[1]', 'SMALLINT') AS ItemType
						,t.c.value('(Amount/text())[1]', 'MONEY') AS Amount
						,t.c.value('(Description/text())[1]', 'NVARCHAR(500)') AS Description
						,t.c.value('(Reference/text())[1]', 'NVARCHAR(100)') AS Reference
						,t.c.value('(ProductCode/text())[1]', 'VARCHAR(50)') AS ProductCode
					FROM @Statement_XML.nodes('Statements/Statement') t(c)
				) s
				OPTION (OPTIMIZE FOR (@Statement_XML = NULL))
			END

			SELECT	TOP 1 @RefInvoiceTypeID = d.InvoiceType
			FROM	dbo.LA_InvoiceHeader d WITH(NOLOCK)
			WHERE EXISTS (
						SELECT TOP 1 1
						FROM @Statement st
						WHERE st.Reference = d.OfficialInvoiceNo 
					) 
		END

		SELECT @SOAType = CASE  WHEN @RefInvoiceTypeID IN (1,6,7) OR @InvoiceTypeId IN (1,6,7) THEN 0
								WHEN @RefInvoiceTypeID = 3 OR @InvoiceTypeID  = 3 THEN 1
								ELSE -1 END,
				@StatementDate = @InvoiceDate
						
		DECLARE @tmpBaseCurrencyList TABLE (CurrencyId INT, Code VARCHAR(10))
		INSERT INTO @tmpBaseCurrencyList (CurrencyId, Code)
		EXEC dbo.LA_SelBaseCurrency

		SELECT @CurrencyID = CurrencyId FROM @tmpBaseCurrencyList WHERE Code = @BaseCurrency
	END

	IF @SOAType NOT IN (0,1) RETURN

	-- Get all documents
	BEGIN

		INSERT INTO #All_Doc_By_Party 
		(
			DocumentID			,
			DocumentNo			,
			DocumentTypeID		,  -- 0: Inv, 1: Payment
			DocumentDetailTypeID,  -- InvTypeID, PaymentTypeID
			DocumentDate		,
			Description			,
			OrgAmount			,
			RemainingAmount		, 
			StatusID			,
			SOAType		
		)
		SELECT 0 AS DocumentID, -- Fake DocumentID
				@InvoiceNo AS DocumentNo,
				0 AS DocumentTypeID,
				@InvoiceTypeId AS DocumentDetailTypeID,
				@InvoiceDate AS DocumentDate,
				CASE WHEN @InvoiceTypeId = 1 THEN @InvoiceNo + ' Software & data licensing & data transmission fees for ' + FORMAT (@InvoiceDate, 'yyyy-MM-dd') -- Software Data & Licensing Fees
					WHEN @InvoiceTypeId = 3 THEN @InvoiceNo + ' Rebates on Access Fees for ' + FORMAT (@InvoiceDate, 'yyyy-MM-dd') -- Rebate
					WHEN @InvoiceTypeId = 7 THEN @InvoiceNo + ' Setup Fee invoice' -- Setup Fees
					WHEN @InvoiceTypeId = 6 THEN @InvoiceNo + ' Rack hosting fee for ' + FORMAT (@InvoiceDate, 'yyyy-MM-dd') -- Hosting Fees
					ELSE ''
				END Description,
				@Amount OrgAmount,
				@Amount RemainingAmount,
				0 AS StatusID,
				@SOAType

		
		INSERT INTO #All_Doc_By_Party 
		(
			DocumentID			,
			DocumentNo			,
			DocumentTypeID		,  -- 0: Inv, 1: Payment
			DocumentDetailTypeID,  -- InvTypeID, PaymentTypeID
			DocumentDate		,
			Description			,
			OrgAmount			,
			RemainingAmount		, 
			StatusID			,
			SOAType		
		)
		SELECT  li.InvoiceHeaderId, 
				li.OfficialInvoiceNo,
				0 AS DocumentTypeID,
				li.InvoiceType AS DocumentDetailTypeID,
				li.InvoiceDate,
				CASE WHEN li.InvoiceType = 1 THEN li.OfficialInvoiceNo + ' Software & data licensing & data transmission fees for ' + FORMAT (li.InvoiceDate, 'yyyy-MM-dd') -- Software Data & Licensing Fees
					 WHEN li.InvoiceType = 3 THEN li.OfficialInvoiceNo + ' Rebates on Access Fees for ' + FORMAT (li.InvoiceDate, 'yyyy-MM-dd') -- Rebate
					 WHEN li.InvoiceType = 7 THEN li.OfficialInvoiceNo + ' Setup Fee invoice' -- Setup Fees
					 WHEN li.InvoiceType = 6 THEN li.OfficialInvoiceNo + ' Rack hosting fee for ' + FORMAT (li.InvoiceDate, 'yyyy-MM-dd') -- Hosting Fees
					 ELSE ''
				END Description,
				ROUND(li.Amount,2) AS OrgAmount,
				ROUND(ISNULL(li.RemainingAmount,li.Amount),2) RemainingAmount,
				li.StatusId,
				CASE  WHEN li.InvoiceType = 3 THEN 1  ELSE 0 END SOAType
		FROM	dbo.LA_InvoiceHeader li WITH(NOLOCK)
		WHERE	li.PartyId = @PartyId AND li.Environment = @Environment  AND li.CurrencyId = @CurrencyID  AND li.InvoiceDate <= @StatementDate
				AND StatusId <> -1
				AND li.OfficialInvoiceNo <> @InvoiceNo
		UNION ALL

		SELECT  lp.PaymentId, 
				lp.PaymentNo,
				1 AS DocumentTypeID,
				lp.Type AS DocumentDetailTypeID,
				lp.ReceivedDate,
				lp.PaymentNo + ' ' + lp.Remark Description,
				lp.Amount AS OrgAmount,
				ISNULL(lp.RemainingAmount,lp.Amount) RemainingAmount,
				lp.StatusId,
				CASE WHEN lp.Type IN (0,1) THEN 0
				     WHEN lp.Type = 2 THEN 1
					 ELSE NULL END SOAType
		FROM	dbo.LA_Payment lp WITH(NOLOCK)
		WHERE	lp.PartyId = @PartyId AND lp.Environment = @Environment  AND lp.CurrencyId = @CurrencyID AND lp.ReceivedDate <= @StatementDate
				AND lp.StatusId = 0

		IF EXISTS (SELECT TOP 1 1 FROM #All_Doc_By_Party WHERE DocumentTypeID = 0 AND DocumentDetailTypeID IN (4,5) AND StatusID = 0 AND SOAType = @SOAType)
		BEGIN

			IF @InvoiceTypeId IN (4,5)
			BEGIN
				/* (ItemType, Amount, Description, Reference) */
				INSERT INTO #D_C_Inv_Detail( DocumentID, DocumentDate, Refno, RefAmount, RefStatusID, RefInvDate, RefInvType)
				SELECT	0, @InvoiceDate, Reference AS Refno,  CASE WHEN @InvoiceTypeId = 4 THEN -1 ELSE 1 END *  s.Amount, li.StatusId, li.InvoiceDate, li.InvoiceType
				FROM	@Statement s
				INNER JOIN dbo.LA_InvoiceHeader li WITH(NOLOCK) ON s.Reference = li.OfficialInvoiceNo AND li.StatusId <> -1	
			END

			INSERT INTO #D_C_Inv_Detail( DocumentID, DocumentDate, Refno, RefAmount, RefStatusID, RefInvDate, RefInvType)
			SELECT t.DocumentID, t.DocumentDate, st.RefNo, ISNULL(st.Income,0) -  ISNULL(st.Expense,0), m.StatusID, m.DocumentDate, m.DocumentDetailTypeID
			FROM  #All_Doc_By_Party t
			INNER JOIN dbo.LA_InvoiceStatement st WITH(NOLOCK) ON t.DocumentID = st.InvoiceHeaderId
			INNER JOIN #All_Doc_By_Party m ON st.RefNo = m.DocumentNo AND m.StatusID = 0
			WHERE t.DocumentTypeID = 0 AND t.DocumentDetailTypeID IN (4,5) AND t.StatusID = 0 AND t.SOAType = @SOAType

			UPDATE t
			SET  t.Description =  CASE WHEN x.SOAType = 0 THEN t.DocumentNo +  ' Software & data licensing & data transmission fees for ' + x.Desc_
									   ELSE t.DocumentNo + ' Rebates on Access Fees for ' + FORMAT (t.DocumentDate, 'yyyy-MM-dd') END,
				 t.SOAType =  x.SOAType
			FROM #All_Doc_By_Party t
			CROSS APPLY (
				SELECT STRING_AGG(FORMAT(u.RefInvDate, 'yyyy-MM-dd'),', ') AS Desc_,
					   MAX(CASE WHEN u.RefInvType IN (1,6,7) THEN 0
								WHEN u.RefInvType = 3 THEN 1
								ELSE NULL END)  SOAType
				FROM #D_C_Inv_Detail u
				WHERE u.DocumentID = t.DocumentID 
			) x
			WHERE t.DocumentTypeID = 0 AND t.DocumentDetailTypeID IN (4,5) AND t.StatusID = 0 AND t.SOAType = @SOAType
		END

	END

	-- Get all document available 
	BEGIN

		DECLARE @FirstDateOfYear DATETIME  
		SELECT @FirstDateOfYear = DATEADD(yy, DATEDIFF(yy, 0, @InvoiceDate), 0) 

		-- Get all available docs 
		INSERT INTO #SOA_Doc_List (
			DocumentID		,
			DocumentNo		,
			DocumentTypeID		,
			DocumentDetailTypeID,
			DocumentDate	,
			Description		,
			Amount			, 
			Payment			,
			OrgAmount		
		)
		SELECT a.DocumentID, 
			   a.DocumentNo, 
			   a.DocumentTypeID, 
			   a.DocumentDetailTypeID,
			   a.DocumentDate, 
			   a.Description,
			   CASE WHEN a.DocumentTypeID = 0 THEN a.RemainingAmount ELSE NULL END Amount,
			   CASE WHEN a.DocumentTypeID = 1 THEN a.RemainingAmount ELSE NULL END Payment,
			   a.OrgAmount
		FROM  #All_Doc_By_Party a
		WHERE   SOAType = @SOAType AND a.StatusID = 0

		INSERT INTO #SOA_Doc_List (DocumentID, DocumentNo, DocumentTypeID, DocumentDate, Description, Amount, Payment, Balance)
		SELECT -10000,'BBF' ,-1, @FirstDateOfYear, 'Balance brought forward', ROUND(SUM(ISNULL(Amount,0) - ISNULL(Payment,0)),2), NULL, ROUND(SUM(ISNULL(Amount,0) - ISNULL(Payment,0)),2)
		FROM #SOA_Doc_List
		WHERE DocumentDate < @FirstDateOfYear


		DECLARE @ItemResult TABLE (
			DocumentDate			DATE ,
			DocumentTypeID			SMALLINT,
			DocumentDetailTypeID	SMALLINT,
			Description				NVARCHAR(500), 
			DocumentNo				VARCHAR(50),
			Amount					MONEY , 
			Payment					MONEY, 
			Balance					MONEY, 
			Type					TINYINT,
			InvoiceNo				VARCHAR(50),
			PaymentNo				VARCHAR(50),
			InvoiceDate				VARCHAR(1000),
			ReferenceInvoiceDate	VARCHAR(1000),
			PayerName				VARCHAR(50),
			Rn INT
		)

		; WITH t AS
		(
			SELECT *, ROW_NUMBER() OVER (ORDER BY  DocumentDate, DocumentTypeID) as _No FROM #SOA_Doc_List WHERE DocumentDate >= @FirstDateOfYear
		), u AS
		(
			SELECT DocumentID, DocumentNo, DocumentTypeID, DocumentDetailTypeID ,DocumentDate, Description, Amount, Payment, ISNULL(Balance,0) Balance, _No FROM t WHERE _No = 1
			UNION ALL 
			SELECT t.DocumentID, t.DocumentNo, t.DocumentTypeID, t.DocumentDetailTypeID, t.DocumentDate, t.Description, t.Amount, t.Payment, u.Balance - ISNULL(t.Payment,0) + ISNULL(t.Amount,0), t._No  FROM t 
			INNER JOIN u ON  u._No = t._No - 1

		)  INSERT INTO @ItemResult (DocumentDate, DocumentTypeID, DocumentDetailTypeID, Description, DocumentNo, Amount, Payment, Balance, Type,
			InvoiceNo,PaymentNo,InvoiceDate,ReferenceInvoiceDate,PayerName,Rn)
		 SELECT DocumentDate,DocumentTypeID, DocumentDetailTypeID, Description, DocumentNo, Amount, Payment, Balance, 
				CASE WHEN DocumentTypeID = -1 THEN 0
					 WHEN DocumentTypeID = 0 AND DocumentDetailTypeID = 1 AND @SOAType = 0 THEN 1
					 WHEN DocumentTypeID = 0 AND DocumentDetailTypeID = 4 AND @SOAType = 0 THEN 9
					 WHEN DocumentTypeID = 0 AND DocumentDetailTypeID = 5 AND @SOAType = 0 THEN 11
					 WHEN DocumentTypeID = 0 AND DocumentDetailTypeID = 3 AND @SOAType = 1 THEN 2
					 WHEN DocumentTypeID = 0 AND DocumentDetailTypeID = 4 AND @SOAType = 1 THEN 10
					 WHEN DocumentTypeID = 0 AND DocumentDetailTypeID = 5 AND @SOAType = 1 THEN 12
					 WHEN DocumentTypeID = 0 AND DocumentDetailTypeID = 6 THEN 3
					 WHEN DocumentTypeID = 0 AND DocumentDetailTypeID = 7 THEN 4
					 WHEN DocumentTypeID = 1 AND DocumentDetailTypeID IN (0,2) AND Payment > 0 THEN 5
					 WHEN DocumentTypeID = 1 AND DocumentDetailTypeID IN (0,2) AND Payment < 0 THEN 6
					 WHEN DocumentTypeID = 1 AND DocumentDetailTypeID = 1 AND CHARINDEX('Transfer from', Description) > 0 THEN 7
					 WHEN DocumentTypeID = 1 AND DocumentDetailTypeID = 1 AND CHARINDEX('Transfer to', Description) > 0 THEN 8
				END Type,
				CASE WHEN  DocumentTypeID = 0 THEN DocumentNo ELSE NULL END InvoiceNo, 
				CASE WHEN  DocumentTypeID = 1 THEN DocumentNo ELSE NULL END PaymentNo, 
				CASE WHEN DocumentTypeID = 0 AND DocumentDetailTypeID NOT IN (4,5) THEN DocumentDate ELSE NULL END AS InvoiceDate,
				CASE WHEN DocumentTypeID = 0 AND DocumentDetailTypeID IN (4,5) THEN SUBSTRING(Description, CHARINDEX('for', Description) + 4, LEN(Description)) ELSE NULL END AS ReferenceInvoiceDate,
				CASE WHEN DocumentTypeID = 1 AND DocumentDetailTypeID = 1 THEN CASE WHEN CHARINDEX('Transfer to', Description) > 0 THEN SUBSTRING(Description, CHARINDEX('Transfer to', Description) + 12, LEN(Description))
																					WHEN CHARINDEX('Transfer from', Description) > 0 THEN SUBSTRING(Description, CHARINDEX('Transfer from', Description) + 14, LEN(Description))
																					ELSE NULL END 
																		  ELSE NULL END PayerName,
				_No FROM u
		 OPTION (MAXRECURSION 0)


		 SELECT  DocumentDate, Amount, Payment, Balance, Type,
			InvoiceNo,PaymentNo,InvoiceDate,ReferenceInvoiceDate,PayerName FROM	@ItemResult  ORDER BY  Rn


		-- Aging
		DECLARE @TotalDue MONEY, @Amount_0_to_30_Days MONEY, @Amount_31_to_60_Days MONEY, @Amount_61_to_90_Days MONEY, @Amount_More_Than_90_Days MONEY
		DECLARE  @cnt_0_to_30_Days INT, @cnt_31_to_60_Days MONEY, @cnt_61_to_90_Days MONEY, @cnt_More_Than_90_Days MONEY

		SELECT TOP 1 @TotalDue = Balance FROM @ItemResult ORDER BY Rn DESC

		SELECT  @Amount_0_to_30_Days	= SUM (CASE WHEN  DocumentDate BETWEEN @Start_Aging_0_to_30 AND @End_Aging_0_to_30 THEN ISNULL(Amount,0) - ISNULL(Payment,0) ELSE 0 END),
				@Cnt_0_to_30_Days		= SUM (CASE WHEN  DocumentDate BETWEEN @Start_Aging_0_to_30 AND @End_Aging_0_to_30 THEN 1 ELSE 0 END),
				@Amount_31_to_60_Days	= SUM (CASE WHEN  DocumentDate BETWEEN @Start_Aging_31_to_60 AND @End_Aging_31_to_60 THEN ISNULL(Amount,0) - ISNULL(Payment,0) ELSE 0 END),
				@Cnt_31_to_60_Days		= SUM (CASE WHEN  DocumentDate BETWEEN @Start_Aging_31_to_60 AND @End_Aging_31_to_60 THEN 1 ELSE 0 END),
				@Amount_61_to_90_Days	= SUM (CASE WHEN  DocumentDate BETWEEN @Start_Aging_61_to_90 AND @End_Aging_61_to_90 THEN ISNULL(Amount,0) - ISNULL(Payment,0) ELSE 0 END),
				@Cnt_61_to_90_Days		= SUM (CASE WHEN  DocumentDate BETWEEN @Start_Aging_61_to_90 AND @End_Aging_61_to_90 THEN 1 ELSE 0 END),
				@Amount_More_Than_90_Days = SUM (CASE WHEN  DocumentDate <= @End_AgingMore_Than_90 THEN ISNULL(Amount,0) - ISNULL(Payment,0) ELSE 0 END),
				@Cnt_More_Than_90_Days	= SUM (CASE WHEN  DocumentDate <= @End_AgingMore_Than_90 THEN 1 ELSE 0 END)
		FROM	#SOA_Doc_List
		WHERE   (
					(DocumentTypeID = 0 AND DocumentDetailTypeID IN (4,5) AND Amount <> OrgAmount ) -- Partial Allocate
					OR
					(DocumentTypeID = 0 AND DocumentDetailTypeID NOT IN (4,5))
					OR
					(DocumentTypeID = 1)
				)

		IF EXISTS (	SELECT	TOP 1 1 
					FROM	#All_Doc_By_Party 
					WHERE	DocumentTypeID = 0 AND DocumentDetailTypeID IN (4,5) 
							AND RemainingAmount = OrgAmount 
							AND SOAType = @SOAType AND StatusID = 0
				  )
		BEGIN
			SELECT  
				@Amount_0_to_30_Days	= ISNULL(@Amount_0_to_30_Days,0) + SUM (CASE WHEN t.RefInvDate BETWEEN @Start_Aging_0_to_30 AND @End_Aging_0_to_30 THEN t.RefAmount ELSE 0 END),
				@Cnt_0_to_30_Days		= ISNULL(@Cnt_0_to_30_Days,0) + SUM (CASE WHEN  t.RefInvDate BETWEEN @Start_Aging_0_to_30 AND @End_Aging_0_to_30 THEN 1 ELSE 0 END),
				@Amount_31_to_60_Days	=  ISNULL(@Amount_31_to_60_Days,0) + SUM (CASE WHEN  RefInvDate BETWEEN @Start_Aging_31_to_60 AND @End_Aging_31_to_60 THEN t.RefAmount ELSE 0 END),
				@Cnt_31_to_60_Days		= ISNULL(@Cnt_31_to_60_Days,0) + SUM (CASE WHEN  t.RefInvDate BETWEEN @Start_Aging_31_to_60 AND @End_Aging_31_to_60 THEN 1 ELSE 0 END),
				@Amount_61_to_90_Days	=  ISNULL(@Amount_61_to_90_Days,0) +SUM (CASE WHEN  RefInvDate BETWEEN @Start_Aging_61_to_90 AND @End_Aging_61_to_90 THEN t.RefAmount ELSE 0 END),
				@Cnt_61_to_90_Days		= ISNULL(@Cnt_61_to_90_Days,0) + SUM (CASE WHEN  t.RefInvDate BETWEEN @Start_Aging_61_to_90 AND @End_Aging_61_to_90 THEN 1 ELSE 0 END),
				@Amount_More_Than_90_Days = ISNULL(@Amount_More_Than_90_Days,0) + SUM (CASE WHEN  RefInvDate < @End_AgingMore_Than_90 THEN t.RefAmount ELSE 0 END),
				@Cnt_More_Than_90_Days	= ISNULL(@Cnt_More_Than_90_Days,0) + SUM (CASE WHEN  t.RefInvDate < @End_AgingMore_Than_90 THEN 1 ELSE 0 END)
			FROM #D_C_Inv_Detail t
			WHERE EXISTS (
				SELECT	TOP 1 1 
				FROM	#SOA_Doc_List x
				WHERE	x.DocumentTypeID = 0 AND x.DocumentDetailTypeID IN (4,5) 
						AND x.Amount = x.OrgAmount 
						AND x.DocumentID = t.DocumentID
						
			)
			
		END
		
		SELECT @TotalDue AS TotalDue, 
				@TotalDue AS Amount, 
				CASE WHEN @Amount_0_to_30_Days = 0 AND @Cnt_0_to_30_Days = 0 THEN  NULL ELSE @Amount_0_to_30_Days END Amount_0_to_30_Days, 
				CASE WHEN @Amount_31_to_60_Days = 0 AND @Cnt_31_to_60_Days = 0 THEN  NULL ELSE @Amount_31_to_60_Days END  Amount_31_to_60_Days, 
				CASE WHEN @Amount_61_to_90_Days = 0 AND @cnt_61_to_90_Days = 0 THEN  NULL ELSE @Amount_61_to_90_Days  END Amount_61_to_90_Days, 
				CASE WHEN @Amount_More_Than_90_Days = 0AND @Cnt_More_Than_90_Days = 0 THEN  NULL ELSE @Amount_More_Than_90_Days END Amount_More_Than_90_Days
		
	END

END
GO
