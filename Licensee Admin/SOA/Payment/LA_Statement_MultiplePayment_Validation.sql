/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Statement_MultiplePayment_Validation]
	@PaymentData	NVARCHAR(MAX),
	@Environment    VARCHAR(10),
	@Template		TINYINT, -- 1: Automate transfer, 0: Cross currency transfer
	@ErrCode		INT = 0 OUTPUT,
	@ErrMsg			NVARCHAR(200) = '' OUTPUT
AS

/*
	Created: 20230908@Danny
	DB: DBCUST.bodb_Licensee
	Task: Upload payment - Validation
   
	Revisions: 
		- 20230908@Danny: Initialize SP [#193656]
		- 20240812@Danny: Add Biller info [#209161]
		- 20240920@Danny: Change to use Customer table Instead of CustInfo [#211108]
		- 20250219@Danny: Integrate Double S System Inc group Licensees [RedmineID: #217961]
		- 20250421@Eddie: Add Biller info [RedmineID: #221990]
		- 20250428@Eddie: Add Biller info [RedmineID: #225376]
		- 20250507@Danny: Add Biller info [RedmineID: #222972]
		- 20250624@Eddie: Add Business Unit [RedmineID: #231003]

	Param's Explanation:
	Received Date format is mm/dd/yyyy

	-- Cross currency transfer mode
	@PaymentData = 
	'<Root>
		<PaymentItem>
			<RowId>2</RowId>
			<PaymentNo>ZL OR-111</PaymentNo>
			<ReceivedDate>02/10/2023</ReceivedDate>
			<Biller>ZL</Biller>
			<FromCustomer>PHL-LSEE-12BET EUR</FromCustomer>
			<ToCustomer>VNM-HENRY CASH CNY</ToCustomer>
			<FromAmount>200.00</FromAmount>
			<ToAmount>100.00</ToAmount>
			<RebatePayment>N</RebatePayment>
			<BusinessUnit>906CL</BusinessUnit>
			<Description>LICA-ZL OR-111 Software Data and Licensing Fee for Jan 2023</Description>
		</PaymentItem>
		<PaymentItem>
			<RowId>3</RowId>
			<PaymentNo>ZL OR-109</PaymentNo>
			<ReceivedDate>02/10/2023</ReceivedDate>
			<Biller>ZL</Biller>
			<FromCustomer>PHL-LSEE-12BET EUR</FromCustomer>
			<ToCustomer>VNM-HENRY CASH CNY</ToCustomer>
			<FromAmount>200.00</FromAmount>
			<ToAmount>100.00</ToAmount>
			<RebatePayment>Y</RebatePayment>
			<BusinessUnit>911LG</BusinessUnit>
			<Description>LICC-ZL OR-109 Software Data and Licensing Fee for Jan 2023</Description>
		</PaymentItem>
	</Root>'

	-- automate transfer mode				
	@PaymentData =
		'<Root>
			<PaymentItem>
				<RowId>2</RowId>
				<PaymentNo>ZL OR-111</PaymentNo>
				<ReceivedDate>02/10/2023</ReceivedDate>
				<Biller>ZL</Biller>
				<FromCustomer>PHL-LSEE-12BET EUR</FromCustomer>
				<ToCustomer>PHL-MNL-CASH EUR</ToCustomer>
				<Amount>200.00</Amount>
				<ActualRate>1.00</ActualRate>
				<RebatePayment>N</RebatePayment>
				<BusinessUnit>906CL</BusinessUnit>
				<Description>LICA-ZL OR-111 Software Data and Licensing Fee for Jan 2023</Description>
			</PaymentItem>
			<PaymentItem>
				<RowId>3</RowId>
				<PaymentNo>ZL OR-109</PaymentNo>
				<ReceivedDate>02/10/2023</ReceivedDate>
				<Biller>ZL</Biller>
				<FromCustomer>PHL-LSEE-12BET EUR</FromCustomer>
				<ToCustomer>PHL-MNL-CASH EUR</ToCustomer>
				<Amount>200.00</Amount>
				<ActualRate>1.00</ActualRate>
				<RebatePayment>Y</RebatePayment>
				<BusinessUnit>911LG</BusinessUnit>
				<Description>LICC-ZL OR-109 Software Data and Licensing Fee for Jan 2023</Description>
			</PaymentItem>
		</Root>'

*/

BEGIN
	SET NOCOUNT ON

	DECLARE @PaymentList TABLE ( RowId			INT
								,PaymentNo		VARCHAR(50)
								,ReceivedDate	VARCHAR(10)
								,Biller			NVARCHAR(10)
								,FromCustomer	VARCHAR(30)
								,ToCustomer		VARCHAR(30)
								,Amount			VARCHAR(20)
								,ToAmount		VARCHAR(20)
								,ActualRate		VARCHAR(20)
								,RebatePayment	VARCHAR(1)
								,Description	NVARCHAR(200)
								,BusinessUnit	VARCHAR(50)
	)
	
	BEGIN TRY
		DECLARE @Payment_XML XML = CONVERT(XML, @PaymentData)

		IF @Template = 1
		BEGIN
			INSERT INTO @PaymentList (RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ActualRate, RebatePayment, Description, BusinessUnit)
			SELECT CAST (RowId AS INT)  RowId
				,PaymentNo
				,ReceivedDate
				,Biller
				,FromCustomer
				,ToCustomer
				,Amount
				,ActualRate
				,RebatePayment
				,Remark
				,BusinessUnit
			FROM (
				SELECT
					LTRIM(RTRIM(t.c.value('(RowId/text())[1]', 'VARCHAR(20)'))) 		 AS RowId
					,LTRIM(RTRIM(t.c.value('(PaymentNo/text())[1]', 'VARCHAR(50)'))) 	 AS PaymentNo
					,LTRIM(RTRIM(t.c.value('(ReceivedDate/text())[1]', 'VARCHAR(20)')))  AS ReceivedDate
					,LTRIM(RTRIM(t.c.value('(Biller/text())[1]', 'NVARCHAR(10)'))) 		 AS Biller
					,LTRIM(RTRIM(t.c.value('(FromCustomer/text())[1]', 'VARCHAR(30)')))  AS FromCustomer
					,LTRIM(RTRIM(t.c.value('(ToCustomer/text())[1]', 'VARCHAR(30)'))) 	 AS ToCustomer
					,LTRIM(RTRIM(t.c.value('(Amount/text())[1]', 'VARCHAR(20)'))) 		 AS Amount
					,LTRIM(RTRIM(t.c.value('(ActualRate/text())[1]', 'VARCHAR(100)'))) 	 AS ActualRate
					,LTRIM(RTRIM(t.c.value('(RebatePayment/text())[1]', 'VARCHAR(1)')))  AS RebatePayment
					,LTRIM(RTRIM(t.c.value('(Description/text())[1]', 'NVARCHAR(200)'))) AS Remark
					,LTRIM(RTRIM(t.c.value('(BusinessUnit/text())[1]', 'VARCHAR(50)')))  AS BusinessUnit
				FROM @Payment_XML.nodes('Root/PaymentItem') t(c)
			) a
			OPTION (OPTIMIZE FOR (@Payment_XML = NULL))
			
		END

		IF @Template = 0
		BEGIN
			
			INSERT INTO @PaymentList (RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ToAmount, RebatePayment, Description, BusinessUnit)
			SELECT CAST (RowId AS INT)  RowId
				,PaymentNo
				,ReceivedDate
				,Biller
				,FromCustomer
				,ToCustomer
				,Amount
				,ToAmount
				,RebatePayment
				,Remark
				,BusinessUnit
			FROM (
				SELECT
					LTRIM(RTRIM(t.c.value('(RowId/text())[1]', 'VARCHAR(20)'))) 		 AS RowId
					,LTRIM(RTRIM(t.c.value('(PaymentNo/text())[1]', 'VARCHAR(50)'))) 	 AS PaymentNo
					,LTRIM(RTRIM(t.c.value('(ReceivedDate/text())[1]', 'VARCHAR(10)')))  AS ReceivedDate
					,LTRIM(RTRIM(t.c.value('(Biller/text())[1]', 'NVARCHAR(10)'))) 		 AS Biller
					,LTRIM(RTRIM(t.c.value('(FromCustomer/text())[1]', 'VARCHAR(30)')))  AS FromCustomer
					,LTRIM(RTRIM(t.c.value('(ToCustomer/text())[1]', 'VARCHAR(30)'))) 	 AS ToCustomer
					,LTRIM(RTRIM(t.c.value('(FromAmount/text())[1]', 'VARCHAR(20)'))) 	 AS Amount
					,LTRIM(RTRIM(t.c.value('(ToAmount/text())[1]', 'VARCHAR(20)'))) 	 AS ToAmount
					,LTRIM(RTRIM(t.c.value('(RebatePayment/text())[1]', 'VARCHAR(1)')))  AS RebatePayment
					,LTRIM(RTRIM(t.c.value('(Description/text())[1]', 'NVARCHAR(200)'))) AS Remark
					,LTRIM(RTRIM(t.c.value('(BusinessUnit/text())[1]', 'VARCHAR(50)')))  AS BusinessUnit
				FROM @Payment_XML.nodes('Root/PaymentItem') t(c)
			) a
			OPTION (OPTIMIZE FOR (@Payment_XML = NULL))
		END

	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 100,  @ErrMsg = 'Wrong format XML'
	END CATCH

	-- Check input data
	BEGIN

	DECLARE @tblInfo TABLE (
		RowId			INT
		,PaymentNo		VARCHAR(50)
		,ReceivedDate	VARCHAR(10)
		,Biller			NVARCHAR(10)
		,FromCustomer	VARCHAR(30)
		,ToCustomer		VARCHAR(30)
		,Amount			VARCHAR(20)
		,ToAmount		VARCHAR(20)
		,ActualRate		VARCHAR(20)
		,RebatePayment	VARCHAR(1)
		,Description	NVARCHAR(200)
		,BusinessUnit	VARCHAR(50)
		,FromCurrName	NVARCHAR(50)
		,ToCurrName		NVARCHAR(50)
		,FromCurrCode	VARCHAR(12)
		,ToCurrCode		VARCHAR(12)
		,FromActualRate	FLOAT
		,ToActualRate	FLOAT
		,FromPayerID	INT
		,ToPayerID		INT
		,FromCurrencyID	INT
		,ToCurrencyID	INT
		,MinActualrate	SMALLMONEY
		,MaxActualrate	SMALLMONEY
		,FromCustID		INT
		,ToCustID		INT
		,CurrentExRate  FLOAT
		,MultipliedBy	INT
		,CurrencyName	VARCHAR(50)
		,SystemExRate	MONEY
		,TransExrate	MONEY
		,isFinanceAcc	BIT	
	)

	DECLARE @tblSucc TABLE (
		RowId			INT
		,PaymentNo		VARCHAR(50)
		,ReceivedDate	VARCHAR(10)
		,Biller			NVARCHAR(10)
		,FromCustomer	VARCHAR(30)
		,ToCustomer		VARCHAR(30)
		,Amount			VARCHAR(20)
		,ToAmount		VARCHAR(20)
		,ActualRate		VARCHAR(20)
		,RebatePayment	VARCHAR(1)
		,Description	NVARCHAR(200)
		,BusinessUnit	VARCHAR(50)
		,FromCustID		INT
		,ToCustID		INT
		-- Automate transfer
		,MinActualrate	SMALLMONEY
		,MaxActualrate	SMALLMONEY
		,MultipliedBy	INT
		,CurrencyName	VARCHAR(50)
		,FromCurrName	NVARCHAR(50)
		,ToCurrName		NVARCHAR(50)
		,FromCurrCode	VARCHAR(12)
		,ToCurrCode		VARCHAR(12)
		,Remark			NVARCHAR(200)
		,CurrentExRate  FLOAT
		-- Cross currency transfer
		,SystemExRate	MONEY
		,TransExrate	MONEY
	)

	DECLARE @tblFail TABLE (
		RowId			INT
		,PaymentNo		VARCHAR(50)
		,ReceivedDate	VARCHAR(10)
		,Biller			NVARCHAR(10)
		,FromCustomer	VARCHAR(30)
		,ToCustomer		VARCHAR(30)
		,Amount			VARCHAR(20)
		,ToAmount		VARCHAR(20)
		,ActualRate		VARCHAR(20)
		,RebatePayment	VARCHAR(1)
		,Description	NVARCHAR(200)
		,BusinessUnit	VARCHAR(50)
		,ErrorMessage	NVARCHAR(500)
	)

	INSERT INTO @tblInfo(RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ToAmount, ActualRate, RebatePayment, Description, BusinessUnit, FromCurrName, ToCurrName, FromCurrCode, ToCurrCode, FromActualRate, ToActualRate, FromPayerID, ToPayerID, FromCurrencyID, ToCurrencyID, MinActualrate, MaxActualrate, FromCustID, ToCustID, CurrentExRate, MultipliedBy, CurrencyName, SystemExRate, TransExrate, isFinanceAcc)
	SELECT t.RowId			 
		  ,t.PaymentNo		
		  ,t.ReceivedDate	
		  ,t.Biller
		  ,t.FromCustomer	
		  ,t.ToCustomer	
		  ,t.Amount		 
		  ,t.ToAmount		
		  ,t.ActualRate	
		  ,t.RebatePayment	
		  ,t.Description	
		  ,t.BusinessUnit	
		  ,e1.currency		
		  ,e2.currency	
		  ,e1.Code			
		  ,e2.Code			
		  ,e1.actualrate	
		  ,e2.actualrate
		  ,p1.PartyID
		  ,p2.PartyID
		  ,e1.ExchangeId
		  ,e2.ExchangeId
		  ,er.MinActualRate
		  ,er.MaxActualRate
		  ,c1.custid 
		  ,c2.custid
		  ,CASE WHEN e1.Currency = e2.Currency THEN 1 
				WHEN e2.Code = 'MYR' THEN e1.actualrate 
				WHEN e1.Code = 'MYR' THEN 1/e2.actualrate 
		   ELSE e1.actualrate/e2.actualrate END CurrentExRate
		  ,CASE WHEN e2.Code = 'MYR' THEN e1.MultipliedBy 
				WHEN e1.Code = 'MYR' THEN e2.MultipliedBy
		   ELSE e1.MultipliedBy END
		  ,CASE WHEN c2.currency = 2 THEN e1.currency 
				WHEN c1.currency = 2 THEN e2.currency
		   ELSE e1.currency END
		  ,e1.actualrate/e2.actualrate AS SystemExRate
	      ,CONVERT(MONEY,t.ToAmount) / CONVERT(MONEY,t.Amount) AS TransExrate	
		  ,CASE WHEN r1.cnt + r2.cnt + r3.cnt + r4.cnt = 0 THEN 0 ElSE 1 END isFinanceAcc
	FROM @PaymentList  t
		LEFT JOIN bodb02.dbo.Customer c1 WITH (NOLOCK) on t.FromCustomer = c1.Username
		LEFT JOIN bodb02.dbo.Customer c2 WITH (NOLOCK) ON t.ToCustomer = c2.Username
		LEFT JOIN bodb02.dbo.Exchange e1 WITH (NOLOCK) ON c1.currency = e1.exchangeid
		LEFT JOIN bodb02.dbo.Exchange e2 WITH (NOLOCK) ON c2.currency = e2.exchangeid
		LEFT JOIN DBTXN.bodb02.dbo.Acc_ExchangeRate er WITH (NOLOCK) ON er.FromExchangeID = e1.exchangeid AND er.ToExchangeID = e2.exchangeid
		OUTER APPLY ( SELECT TOP 1 PartyID FROM dbo.OAS_PartyBaseCurrency op WITH (NOLOCK) WHERE op.LicenseeCode = t.FromCustomer) p1
		OUTER APPLY ( SELECT TOP 1 PartyID FROM dbo.OAS_PartyBaseCurrency op WITH (NOLOCK) WHERE op.LicenseeCode = t.ToCustomer ) p2
		OUTER APPLY ( SELECT COUNT(1) AS cnt FROM bodb02.dbo.custAgent a (NOLOCK) WHERE c2.recommend = a.custid AND c2.roleid = 1 AND a.isInternal = 1 ) r1
		OUTER APPLY ( SELECT COUNT(1) AS cnt FROM bodb02.dbo.custAgent a (NOLOCK) WHERE c2.custid = a.custid AND a.isInternal = 1 ) r2
		OUTER APPLY ( SELECT COUNT(1) AS cnt FROM bodb02.dbo.CustMaster a (NOLOCK) WHERE c2.custid = a.custid AND a.isInternal = 1 ) r3
		OUTER APPLY ( SELECT COUNT(1) AS cnt FROM bodb02.dbo.CustSuper a (NOLOCK) WHERE c2.custid = a.custid AND a.isInternal = 1 ) r4

	IF @Template = 1 --Automate transfer
	BEGIN
		-- Valid 
		INSERT INTO @tblSucc(RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ToAmount, ActualRate, RebatePayment, Description, BusinessUnit, MinActualrate, MaxActualrate, MultipliedBy, CurrencyName, FromCurrName, ToCurrName, FromCurrCode, ToCurrCode, SystemExRate, TransExrate, CurrentExRate, FromCustID, ToCustID)
		SELECT RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ToAmount, ActualRate, RebatePayment, Description, BusinessUnit, MinActualrate, MaxActualrate, MultipliedBy, CurrencyName, FromCurrName, ToCurrName, FromCurrCode, ToCurrCode, SystemExRate, TransExrate, CurrentExRate, FromCustID, ToCustID
		FROM @tblInfo AS t
		WHERE ISNUMERIC(t.Amount) = 1 AND ISNUMERIC(t.ActualRate) = 1 AND ISDATE(ReceivedDate) = 1
		  AND CAST(t.ActualRate AS FLOAT) > 0
		  AND CAST(t.Amount AS FLOAT) <> 0
		  AND t.FromCustID IS NOT NULL
		  AND t.ToCustID IS NOT NULL
		  AND t.FromCustID <> t.ToCustID
		  AND (LEN(SUBSTRING(t.Amount, CHARINDEX('.',t.Amount ) + 1, LEN(t.Amount))) <= 2  OR CHARINDEX('.',t.Amount ) = 0) -- Amount has less than 2 decimal digits
		  AND LEN(t.Description) <= 200
		  AND (
				(t.RebatePayment = 'Y' AND CAST(t.Amount AS FLOAT) < 0 AND ToPayerID IS NULL)
				OR 
				( (t.RebatePayment IS NULL OR t.RebatePayment <> 'Y') AND CAST(t.Amount AS FLOAT) <> 0 )
		      )
		  AND (  	
				(FromCurrName = ToCurrName AND CAST(ActualRate AS FLOAT) = 1)
				OR (FromCurrCode = ToCurrCode AND FromCurrName <> ToCurrName)
				OR ( FromCurrCode = 'MYR' AND ToCurrCode <> 'MYR')
				OR ( ToCurrCode = 'MYR' AND FromCurrCode <> 'MYR')
		      )
		  AND FromPayerID IS NOT NULL
		  AND (
				(ToPayerID IS NULL AND isFinanceAcc = 1)
				OR
				ToPayerID IS NOT NULL 
			  )
		  AND Biller IN ('BHC', 'ZL', 'JS', 'DSS', 'RHL', 'FSL', 'IS')
		  AND ( 
				ISNULL(t.BusinessUnit, '') = ''
		        OR
				EXISTS( SELECT 1 FROM bodb02.dbo.f_Transfer_GetBUList() AS f WHERE f.BusinessUnit = t.BusinessUnit )
		  )
	
		-- Invalid
		INSERT INTO @tblFail(RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ToAmount, ActualRate, RebatePayment, Description, BusinessUnit, ErrorMessage)
		SELECT RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer,  Amount, ToAmount, ActualRate, RebatePayment, Description, BusinessUnit,
		   CASE WHEN ISNUMERIC(Amount) = 0 OR ISNUMERIC(ActualRate) = 0 OR CAST(ActualRate AS FLOAT) <= 0 OR CAST(Amount AS FLOAT) = 0 THEN 'Invalid Amount or Actual Rate.'
				WHEN LEN(SUBSTRING(Amount, CHARINDEX('.', Amount ) + 1, LEN(Amount))) > 2 AND CHARINDEX('.', Amount) > 0 THEN 'Invalid Amount. Amount have 2 decimal digits only.'
				WHEN ISDATE(ReceivedDate) = 0 THEN 'Invalid Received Date.' 
				WHEN RebatePayment = 'Y' AND CAST(Amount AS MONEY) > 0 THEN 'Invalid Rebate Payment. Amount has to less than 0.'
				WHEN RebatePayment = 'Y' AND FromPayerID IS NOT NULL AND ToPayerID IS NOT NULL THEN 'Rebate Payment could not be a transfer overpayment.'
				WHEN Biller NOT IN ('BHC', 'ZL', 'JS', 'DSS', 'RHL', 'FSL', 'IS') OR Biller IS NULL THEN 'Invalid Biller entered. Please ensure the Biller is in (BHC, ZL, JS, DSS, RHL, FSL, IS).'
				WHEN ISNULL(FromCustomer,'') = '' AND ISNULL(ToCustomer,'') = '' THEN 'Username cannot be blank.' 
				WHEN FromCustomer = ToCustomer THEN 'From Cust must different To Cust.'
				WHEN LEN(Description) > 200 THEN 'Maximum length of Description is 200 characters.'	
				WHEN FromCurrName = ToCurrName AND CAST(ActualRate AS FLOAT) <> 1 THEN 'Same currency name, but actual rate is different 1.'
				WHEN FromCurrCode <> ToCurrCode AND FromCurrCode <> 'MYR' AND ToCurrCode <> 'MYR' THEN 'From Cust and To Cust must belong same currency code.'
				WHEN FromPayerID IS NULL THEN 'Invalid From Cust.'
				WHEN FromPayerID IS NOT NULL AND ToPayerID IS NULL AND EXISTS (SELECT 1 FROM dbo.LA_Payment p WITH (NOLOCK) WHERE p.PaymentNo = PaymentNo AND p.Type IN (0,2)) THEN 'Payment No exists in the system.'
				WHEN FromPayerID IS NOT NULL AND ToPayerID IS NULL	AND isFinanceAcc = 0 THEN 'Invalid To Cust.'
				WHEN NOT EXISTS( SELECT 1 FROM bodb02.dbo.f_Transfer_GetBUList() AS f WHERE f.BusinessUnit = t.BusinessUnit) AND ISNULL(t.BusinessUnit, '') <> '' THEN 'Invalid Business Unit'
		   ELSE 'Invalid From Cust or To Cust.' END AS Reason
		FROM @tblInfo AS t
		WHERE RowId NOT IN (SELECT RowId FROM @tblSucc)

		-- Valid 
		SELECT RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ActualRate, RebatePayment, BusinessUnit AS BU, Description, FromCustID, ToCustID,
		   CASE WHEN (
						(FromCurrCode = 'MYR' AND ToCurrCode <> 'MYR') 
						OR (ToCurrCode = 'MYR' AND FromCurrCode <> 'MYR')
						OR (FromCurrCode = ToCurrCode)
					)
					AND CAST(CurrentExRate AS MONEY) <> CAST( ActualRate AS MONEY)	 
					AND MultipliedBy <> 1 THEN 'Different system actual rate (' + FORMAT(CAST(CurrentExRate AS MONEY),'F4','en-us') + ')' + CHAR(13) + 'Transaction with exchange rate having "Multiplied by" (Currency ' + CurrencyName + ', Multiplied by = ' + CAST(MultipliedBy AS VARCHAR(20)) + ')'		    
				WHEN (
						(FromCurrCode = 'MYR' AND ToCurrCode <> 'MYR') 
						OR (ToCurrCode = 'MYR' AND FromCurrCode <> 'MYR')
						OR (FromCurrCode = ToCurrCode)
					) 
					AND ActualRate NOT BETWEEN CurrentExRate - MinActualrate * CurrentExRate AND CurrentExRate + MinActualrate * CurrentExRate THEN 'Exceed limit range (' + FORMAT(CurrentExRate - MinActualrate * CurrentExRate, 'F4', 'en-us') + ' - ' + FORMAT(CurrentExRate + MinActualrate * CurrentExRate, 'F4', 'en-us') + ')'
				WHEN FromCurrCode = ToCurrCode AND FromCurrName <> ToCurrName AND CAST(CurrentExRate AS MONEY) <> CAST( ActualRate AS MONEY) THEN 'Different system actual rate (' + FORMAT(CAST(CurrentExRate AS MONEY),'F4','en-us') + ')'
				WHEN (
						(FromCurrCode = 'MYR' AND ToCurrCode <> 'MYR') 
						OR (ToCurrCode = 'MYR' AND FromCurrCode <> 'MYR')
					) 
					AND CAST(CurrentExRate AS MONEY) <> CAST( ActualRate AS MONEY) THEN 'Different system actual rate (' + FORMAT(CAST(CurrentExRate AS MONEY), 'F4', 'en-us') + ')'
				WHEN MultipliedBy <> 1 THEN 'Transaction with exchange rate having "Multiplied by" (Currency ' +CurrencyName + ', Multiplied by = ' + CAST(MultipliedBy AS VARCHAR(20)) + ')'
		   END Remark
		FROM @tblSucc
		ORDER BY RowId

		-- Invalid
		SELECT RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ActualRate, RebatePayment, BusinessUnit AS BU, Description, ErrorMessage
		FROM @tblFail
		ORDER BY RowId

	END

	IF @Template = 0 --Cross transfer
	BEGIN
		-- Valid 
		INSERT INTO @tblSucc(RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ToAmount, ActualRate, RebatePayment, Description, BusinessUnit, MinActualrate, MaxActualrate, MultipliedBy, CurrencyName, FromCurrName, ToCurrName, FromCurrCode, ToCurrCode, SystemExRate, TransExrate, FromCustID, ToCustID)
		SELECT RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ToAmount, ActualRate, RebatePayment, Description, BusinessUnit, MinActualrate, MaxActualrate, MultipliedBy, CurrencyName, FromCurrName, ToCurrName, FromCurrCode, ToCurrCode, SystemExRate, TransExrate, FromCustID, ToCustID
		FROM @tblInfo AS t
		WHERE ISNUMERIC(t.Amount) = 1 AND ISDATE(ReceivedDate) = 1
		  AND ( 
				(CONVERT(MONEY, t.Amount) > 0 AND CONVERT(MONEY, t.ToAmount) > 0) 
				OR 
				(CONVERT(MONEY, t.Amount) < 0 AND CONVERT(MONEY, t.ToAmount) < 0)
			) -- check if same sign
		  AND CONVERT(MONEY, t.Amount) <> 0
		  AND CONVERT(MONEY, t.ToAmount) <> 0
		  AND t.FromCustID IS NOT NULL
		  AND t.ToCustID IS NOT NULL
		  AND t.FromCustID <> t.ToCustID
		  AND (LEN(SUBSTRING(t.Amount, CHARINDEX('.', t.Amount ) + 1, LEN(t.Amount))) <= 2 OR CHARINDEX('.', t.Amount ) = 0) -- Amount has less than 2 decimal digits
		  AND (LEN(SUBSTRING(t.ToAmount, CHARINDEX('.', t.ToAmount ) + 1, LEN(t.ToAmount))) <= 2 OR CHARINDEX('.', t.ToAmount) = 0) -- Amount has less than 2 decimal digits
		  AND LEN(t.Description) <= 200
		  AND (
				(t.RebatePayment = 'Y' AND CAST(t.Amount AS FLOAT) < 0 AND CAST(t.ToAmount AS FLOAT) < 0 AND t.ToPayerID IS NULL)
				OR 
				( (t.RebatePayment IS NULL OR t.RebatePayment <> 'Y') AND CAST(t.Amount AS FLOAT) <> 0 AND CAST(t.ToAmount AS FLOAT) <> 0 )
			)
		  AND t.RebatePayment IN ('Y', 'N')
		  AND t.FromCurrencyID <> t.ToCurrencyID
		  AND FromPayerID IS NOT NULL
		  AND (
				(ToPayerID IS NULL AND isFinanceAcc = 1)
				OR ToPayerID IS NOT NULL 	
			)
		  AND Biller IN ('BHC', 'ZL', 'JS', 'DSS', 'RHL', 'FSL', 'IS')
		  AND ( 
				ISNULL(t.BusinessUnit, '') = ''
		        OR
				EXISTS( SELECT 1 FROM bodb02.dbo.f_Transfer_GetBUList() AS f WHERE f.BusinessUnit = t.BusinessUnit )
		  )

		-- Invalid
		INSERT INTO @tblFail(RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ToAmount, ActualRate, RebatePayment, Description, BusinessUnit, ErrorMessage)
		SELECT RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount, ToAmount, ActualRate, RebatePayment, Description, BusinessUnit,
		   CASE WHEN ISNUMERIC(Amount) = 0 OR ISNUMERIC(ToAmount) = 0 OR CONVERT(MONEY, Amount) = 0 OR CONVERT(MONEY,ToAmount) = 0 THEN 'Invalid Amount. From Amount and To Amount should not be equal to 0.'
				WHEN (CONVERT(MONEY, Amount) > 0 AND CONVERT(MONEY,ToAmount) < 0) OR (CONVERT(MONEY, Amount) < 0 AND CONVERT(MONEY,ToAmount) > 0) THEN 'Invalid Amount. From Amount and To Amount have to be the same sign.'
				WHEN (LEN(SUBSTRING(Amount, CHARINDEX('.', Amount ) + 1, LEN(Amount))) > 2 AND CHARINDEX('.',Amount) > 0)
				  OR (LEN(SUBSTRING(ToAmount, CHARINDEX('.', ToAmount ) + 1, LEN(ToAmount))) > 2 AND CHARINDEX('.',ToAmount) > 0 ) THEN 'Invalid Amount. From Amount and To Amount have 2 decimal digits only.'
				WHEN ISDATE(ReceivedDate) = 0 THEN 'Invalid Received Date.'
				WHEN Biller NOT IN ('BHC', 'ZL', 'JS', 'DSS', 'RHL', 'FSL', 'IS') OR Biller IS NULL THEN 'Invalid Biller entered. Please ensure the Biller is in (BHC, ZL, JS, DSS, RHL, FSL, IS).'
				WHEN RebatePayment = 'Y' AND ( CAST(Amount AS MONEY) > 0 OR CAST(ToAmount AS MONEY) > 0 ) THEN 'Invalid Rebate Payment. From Amount and To Amount have to less than 0.'
				WHEN RebatePayment = 'Y' AND FromPayerID IS NOT NULL AND ToPayerID IS NOT NULL THEN 'Rebate Payment could not be a transfer overpayment.'
				WHEN ISNULL(FromCustomer,'') = '' OR ISNULL(ToCustomer,'') = '' THEN 'Username cannot be blanked.' 
				WHEN FromCustomer = ToCustomer THEN 'From Cust and To Cust must be different.'
				WHEN LEN(Description) > 200 THEN 'Maximum length of Description is 200 characters'
				WHEN FromCurrencyID = ToCurrencyID THEN 'From Cust and To Cust must be different currency.'
				WHEN FromActualRate = 0 OR ToActualRate = 0 THEN 'Invalid Exchange Rate.'
				WHEN FromPayerID IS NULL THEN 'Invalid From Cust.'
				WHEN FromPayerID IS NOT NULL AND ToPayerID IS NULL AND EXISTS (SELECT 1 FROM dbo.LA_Payment p WITH (NOLOCK) WHERE p.PaymentNo = PaymentNo AND p.Type IN (0,2)) THEN 'Payment No exists in the system.'
				WHEN FromPayerID IS NOT NULL AND ToPayerID IS NULL AND isFinanceAcc = 0 THEN 'Invalid To Cust.'
				WHEN NOT EXISTS( SELECT 1 FROM bodb02.dbo.f_Transfer_GetBUList() AS f WHERE f.BusinessUnit = t.BusinessUnit) AND ISNULL(t.BusinessUnit, '') <> '' THEN 'Invalid Business Unit'
		   ELSE 'Invalid From Cust or To Cust.' END AS Reason
		FROM @tblInfo AS t
		WHERE RowId NOT IN (SELECT RowId FROM @tblSucc)

		-- Valid
		SELECT RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount AS FromAmount, ToAmount, RebatePayment, BusinessUnit AS BU, Description, SystemExRate, TransExrate, FromCustID, ToCustID
		FROM @tblSucc
		ORDER BY RowId

		-- Invalid
		SELECT RowId, PaymentNo, ReceivedDate, Biller, FromCustomer, ToCustomer, Amount AS FromAmount, ToAmount, RebatePayment, BusinessUnit AS BU, Description, ErrorMessage
		FROM @tblFail
		ORDER BY RowId

	END
	END
END
GO