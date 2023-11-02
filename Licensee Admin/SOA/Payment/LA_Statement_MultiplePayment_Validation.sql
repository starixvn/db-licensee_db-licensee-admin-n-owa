/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
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

	Param's Explanation:
	Received Date format is mm/dd/yyyy

	-- Cross currency transfer mode
	@PaymentData = 
	'<Root>
		<PaymentItem>
			<RowId>2</RowId>
			<PaymentNo>ZL OR-111</PaymentNo>
			<ReceivedDate>02/10/2023</ReceivedDate>
			<FromCustomer>PHL-LSEE-12BET EUR</FromCustomer>
			<ToCustomer>VNM-HENRY CASH CNY</ToCustomer>
			<FromAmount>200.00</FromAmount>
			<ToAmount>100.00</ToAmount>
			<RebatePayment>N</RebatePayment>
			<Description>LICA-ZL OR-111 Software Data and Licensing Fee for Jan 2023</Description>
		</PaymentItem>
		<PaymentItem>
			<RowId>3</RowId>
			<PaymentNo>ZL OR-109</PaymentNo>
			<ReceivedDate>02/10/2023</ReceivedDate>
			<FromCustomer>PHL-LSEE-12BET EUR</FromCustomer>
			<ToCustomer>VNM-HENRY CASH CNY</ToCustomer>
			<FromAmount>200.00</FromAmount>
			<ToAmount>100.00</ToAmount>
			<RebatePayment>Y</RebatePayment>
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
				<FromCustomer>PHL-LSEE-12BET EUR</FromCustomer>
				<ToCustomer>PHL-MNL-CASH EUR</ToCustomer>
				<Amount>200.00</Amount>
				<ActualRate>1.00</ActualRate>
				<RebatePayment>N</RebatePayment>
				<Description>LICA-ZL OR-111 Software Data and Licensing Fee for Jan 2023</Description>
			</PaymentItem>
			<PaymentItem>
				<RowId>3</RowId>
				<PaymentNo>ZL OR-109</PaymentNo>
				<ReceivedDate>02/10/2023</ReceivedDate>
				<FromCustomer>PHL-LSEE-12BET EUR</FromCustomer>
				<ToCustomer>PHL-MNL-CASH EUR</ToCustomer>
				<Amount>200.00</Amount>
				<ActualRate>1.00</ActualRate>
				<RebatePayment>Y</RebatePayment>
				<Description>LICC-ZL OR-109 Software Data and Licensing Fee for Jan 2023</Description>
			</PaymentItem>
		</Root>'

*/

BEGIN
	SET NOCOUNT ON

	DECLARE @PaymentList TABLE (
		RowId			INT, 
		PaymentNo		VARCHAR(50), 
		ReceivedDate	VARCHAR(10), 
		FromCustomer	VARCHAR(30), 
		ToCustomer		VARCHAR(30), 
		Amount			VARCHAR(20), 
		ToAmount		VARCHAR(20), 
		ActualRate		VARCHAR(20), 
		RebatePayment	VARCHAR(1), 
		Description		NVARCHAR(200)
		)
	
	BEGIN TRY
		DECLARE @Payment_XML XML = CONVERT(XML, @PaymentData)

		IF @Template = 1
		BEGIN
			INSERT INTO @PaymentList (RowId, PaymentNo, ReceivedDate, FromCustomer, ToCustomer, Amount, ActualRate, RebatePayment, Description)
			SELECT CAST (RowId AS INT)  RowId
				,PaymentNo
				,ReceivedDate
				,FromCustomer
				,ToCustomer
				,Amount
				,ActualRate
				,RebatePayment
				,Remark
			FROM (
				SELECT
					LTRIM(RTRIM(t.c.value('(RowId/text())[1]', 'VARCHAR(20)'))) AS RowId
					,LTRIM(RTRIM(t.c.value('(PaymentNo/text())[1]', 'VARCHAR(50)'))) AS PaymentNo
					,LTRIM(RTRIM(t.c.value('(ReceivedDate/text())[1]', 'VARCHAR(20)'))) AS ReceivedDate
					,LTRIM(RTRIM(t.c.value('(FromCustomer/text())[1]', 'VARCHAR(30)'))) AS FromCustomer
					,LTRIM(RTRIM(t.c.value('(ToCustomer/text())[1]', 'VARCHAR(30)'))) AS ToCustomer
					,LTRIM(RTRIM(t.c.value('(Amount/text())[1]', 'VARCHAR(20)'))) AS Amount
					,LTRIM(RTRIM(t.c.value('(ActualRate/text())[1]', 'VARCHAR(100)'))) AS ActualRate
					,LTRIM(RTRIM(t.c.value('(RebatePayment/text())[1]', 'VARCHAR(1)'))) AS RebatePayment
					,LTRIM(RTRIM(t.c.value('(Description/text())[1]', 'NVARCHAR(200)'))) AS Remark
				FROM @Payment_XML.nodes('Root/PaymentItem') t(c)
			) a
			OPTION (OPTIMIZE FOR (@Payment_XML = NULL))
			
		END

		IF @Template = 0
		BEGIN
			
			INSERT INTO @PaymentList (RowId, PaymentNo, ReceivedDate, FromCustomer, ToCustomer, Amount, ToAmount, RebatePayment, Description)
			SELECT CAST (RowId AS INT)  RowId
				,PaymentNo
				,ReceivedDate
				,FromCustomer
				,ToCustomer
				,Amount
				,ToAmount
				,RebatePayment
				,Remark
			FROM (
				SELECT
					LTRIM(RTRIM(t.c.value('(RowId/text())[1]', 'VARCHAR(20)'))) AS RowId
					,LTRIM(RTRIM(t.c.value('(PaymentNo/text())[1]', 'VARCHAR(50)'))) AS PaymentNo
					,LTRIM(RTRIM(t.c.value('(ReceivedDate/text())[1]', 'VARCHAR(10)'))) AS ReceivedDate
					,LTRIM(RTRIM(t.c.value('(FromCustomer/text())[1]', 'VARCHAR(30)'))) AS FromCustomer
					,LTRIM(RTRIM(t.c.value('(ToCustomer/text())[1]', 'VARCHAR(30)'))) AS ToCustomer
					,LTRIM(RTRIM(t.c.value('(FromAmount/text())[1]', 'VARCHAR(20)'))) AS Amount
					,LTRIM(RTRIM(t.c.value('(ToAmount/text())[1]', 'VARCHAR(20)'))) AS ToAmount
					,LTRIM(RTRIM(t.c.value('(RebatePayment/text())[1]', 'VARCHAR(1)'))) AS RebatePayment
					,LTRIM(RTRIM(t.c.value('(Description/text())[1]', 'NVARCHAR(200)'))) AS Remark
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

	--New Payment No is duplicated (row #<row no1>, row #<row no2>...)
	DECLARE @tblDuplicatedPaymentNo TABLE(	
		RowId			INT,
		ErrorMessage	NVARCHAR(500)
	)

	DECLARE @tblInfo TABLE (
		RowId			INT, 
		PaymentNo		VARCHAR(50), 
		ReceivedDate	VARCHAR(10), 
		FromCustomer	VARCHAR(30), 
		ToCustomer		VARCHAR(30), 
		Amount			VARCHAR(20), 
		ToAmount		VARCHAR(20), 
		ActualRate		VARCHAR(20), 
		RebatePayment	VARCHAR(1), 
		Description		NVARCHAR(200),
		FromCurrName	NVARCHAR(50),
		ToCurrName		NVARCHAR(50),
		FromCurrCode	VARCHAR(12),
		ToCurrCode		VARCHAR(12),
		FromActualRate	FLOAT,
		ToActualRate	FLOAT,
		FromPayerID		INT,
		ToPayerID		INT,
		FromCurrencyID	INT,
		ToCurrencyID	INT,
		MinActualrate	SMALLMONEY, 	
		MaxActualrate	SMALLMONEY,
		FromCustID		INT,
		ToCustID		INT,
		CurrentExRate   FLOAT,
		MultipliedBy	INT,
		CurrencyName	VARCHAR(50),
		SystemExRate	MONEY,
		TransExrate		MONEY,
		isFinanceAcc	BIT
	)

	DECLARE @tblSucc TABLE (
		RowId			INT, 
		PaymentNo		VARCHAR(50), 
		ReceivedDate	VARCHAR(10), 
		FromCustomer	VARCHAR(30), 
		ToCustomer		VARCHAR(30), 
		Amount			VARCHAR(20), 
		ToAmount		VARCHAR(20), 
		ActualRate		VARCHAR(20), 
		RebatePayment	VARCHAR(1), 
		Description		NVARCHAR(200),
		FromCustID		INT,
		ToCustID		INT,
		-- Automate transfer
		MinActualrate	SMALLMONEY, 	
		MaxActualrate	SMALLMONEY,
		MultipliedBy	INT,
		CurrencyName	VARCHAR(50),
		FromCurrName	NVARCHAR(50),
		ToCurrName		NVARCHAR(50),
		FromCurrCode	VARCHAR(12),
		ToCurrCode		VARCHAR(12),
		Remark			NVARCHAR(200),
		CurrentExRate   FLOAT,
		-- Cross currency transfer
		SystemExRate	MONEY,
		TransExrate		MONEY
	)

	DECLARE @tblFail TABLE (
		RowId			INT, 
		PaymentNo		VARCHAR(50), 
		ReceivedDate	VARCHAR(10), 
		FromCustomer	VARCHAR(30), 
		ToCustomer		VARCHAR(30), 
		Amount			VARCHAR(20), 
		ToAmount		VARCHAR(20), 
		ActualRate		VARCHAR(20), 
		RebatePayment	VARCHAR(1), 
		Description		NVARCHAR(200),
		ErrorMessage	NVARCHAR(500)
	)

	INSERT INTO @tblInfo(RowId,PaymentNo,ReceivedDate,FromCustomer,ToCustomer,Amount,ToAmount,ActualRate,RebatePayment,Description,FromCurrName,ToCurrName,
			FromCurrCode,ToCurrCode,FromActualRate,ToActualRate,FromPayerID, ToPayerID,FromCurrencyID,ToCurrencyID,MinActualrate,MaxActualrate,FromCustID,ToCustID, 
			CurrentExRate,MultipliedBy, CurrencyName, SystemExRate, TransExrate, isFinanceAcc)
	SELECT	t.RowId			 
			,t.PaymentNo		
			,t.ReceivedDate	
			,t.FromCustomer	
			,t.ToCustomer	
			,t.Amount		 
			,t.ToAmount		
			,t.ActualRate	
			,t.RebatePayment	
			,t.Description	
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
			  ELSE e1.actualrate / e2.actualrate  END CurrentExRate
			 ,CASE WHEN e2.Code = 'MYR' THEN e1.MultipliedBy 
				 WHEN e1.Code = 'MYR' THEN e2.MultipliedBy
				 ELSE e1.MultipliedBy END
			,CASE WHEN c2.currency = 2 THEN e1.currency 
				 WHEN c1.currency = 2 THEN e2.currency
				 ELSE e1.currency END
			,e1.actualrate / e2.actualrate AS SystemExRate
			,CONVERT(MONEY,t.ToAmount) / CONVERT(MONEY,t.Amount) AS TransExrate	
			, CASE WHEN r1.cnt +  r2.cnt + r3.cnt + r4.cnt = 0 THEN 0 ElSE 1 END isFinanceAcc
	FROM	@PaymentList  t
	LEFT JOIN CustDB.dbo.custinfo c1 WITH (NOLOCK) on t.FromCustomer = c1.Username
	LEFT JOIN CustDB.dbo.custinfo c2 WITH (NOLOCK) ON t.ToCustomer = c2.Username
	LEFT JOIN CustDB.dbo.Exchange e1 WITH (NOLOCK) ON c1.currency = e1.exchangeid
	LEFT JOIN CustDB.dbo.Exchange e2 WITH (NOLOCK) ON c2.currency = e2.exchangeid
	LEFT JOIN DBTXN.bodb02.dbo.Acc_ExchangeRate er WITH (NOLOCK) ON er.FromExchangeID = e1.exchangeid and er.ToExchangeID = e2.exchangeid
	OUTER APPLY ( SELECT TOP 1 PartyID FROM OAS_PartyBaseCurrency op WITH (NOLOCK) WHERE op.LicenseeCode = t.FromCustomer) p1
	OUTER APPLY ( SELECT TOP 1 PartyID FROM OAS_PartyBaseCurrency op WITH (NOLOCK) WHERE op.LicenseeCode = t.ToCustomer ) p2
	OUTER APPLY ( SELECT COUNT(1) AS cnt  FROM  CustDB.dbo.custAgent a (NOLOCK) WHERE c2.recommend = a.custid AND c2.roleid = 1 AND a.isInternal = 1 ) r1
	OUTER APPLY ( SELECT COUNT(1) AS cnt  FROM  CustDB.dbo.custAgent a (NOLOCK) WHERE c2.custid = a.custid AND a.isInternal = 1 ) r2
	OUTER APPLY ( SELECT COUNT(1) AS cnt  FROM  CustDB.dbo.CustMaster a (NOLOCK) WHERE c2.custid = a.custid AND a.isInternal = 1 ) r3
	OUTER APPLY ( SELECT COUNT(1) AS cnt  FROM  CustDB.dbo.CustSuper a (NOLOCK) WHERE c2.custid = a.custid AND a.isInternal = 1 ) r4

	; WITH t AS
	(
		SELECT DISTINCT
			   STRING_AGG(CAST(RowId AS VARCHAR(10)),',') WITHIN GROUP (ORDER BY RowId)  AS RowIds,
			   'Payment No is duplicated ( '+ STRING_AGG('row #'+ CAST(RowId AS VARCHAR(10)),',') WITHIN GROUP (ORDER BY RowId) + ')' AS ErrorMessage
		FROM @tblInfo
		WHERE FromPayerID IS NOT NULL AND ToPayerID IS NULL
		GROUP BY PaymentNo
		HAVING COUNT(1) > 1
	)
	INSERT INTO @tblDuplicatedPaymentNo (RowId,ErrorMessage)
	SELECT p.RowId, d.ErrorMessage
	FROM @PaymentList p
	INNER JOIN  (
		SELECT x.RowId, t.ErrorMessage FROM t 
		CROSS APPLY (SELECT CAST (value AS INT) RowId  FROM STRING_SPLIT(t.RowIds,',')) x
	) d ON p.RowId = d.RowId


	IF @Template = 1 --Automate transfer
	BEGIN
		--  valid 
		INSERT INTO @tblSucc(RowId,PaymentNo,ReceivedDate,FromCustomer,ToCustomer,Amount,ToAmount,ActualRate,RebatePayment,Description,
			MinActualrate, MaxActualrate,MultipliedBy,CurrencyName,FromCurrName,ToCurrName,FromCurrCode,ToCurrCode,SystemExRate,TransExrate,CurrentExRate, FromCustID, ToCustID)
		SELECT	RowId,PaymentNo,ReceivedDate,FromCustomer,ToCustomer,Amount,ToAmount,ActualRate,RebatePayment,Description,
			 MinActualrate, MaxActualrate,MultipliedBy,CurrencyName,FromCurrName,ToCurrName,FromCurrCode,ToCurrCode,SystemExRate,TransExrate, CurrentExRate, FromCustID, ToCustID
		FROM	@tblInfo as t
		WHERE ISNUMERIC(t.Amount)=1 AND ISNUMERIC(t.ActualRate)=1 AND ISDATE(ReceivedDate) = 1
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
						OR	(FromCurrCode = ToCurrCode AND FromCurrName <> ToCurrName)
						OR ( FromCurrCode = 'MYR' AND ToCurrCode <> 'MYR')
						OR ( ToCurrCode = 'MYR' AND FromCurrCode <> 'MYR')
					)
				AND FromPayerID IS NOT NULL
				AND (
						(ToPayerID IS NULL AND NOT EXISTS (SELECT 1 FROM LA_Payment p WITH(NOLOCK) WHERE p.PaymentNo = t.PaymentNo AND p.Type IN (0,2)) AND isFinanceAcc = 1)
						OR
						ToPayerID IS NOT NULL 
					)
				AND NOT EXISTS (SELECT 1 FROM @tblDuplicatedPaymentNo dupRow WHERE dupRow.RowId = t.RowId) 

			
		-- Invalid
		INSERT INTO @tblFail(RowId,PaymentNo,ReceivedDate,FromCustomer,ToCustomer,Amount,ToAmount,ActualRate,RebatePayment,Description,ErrorMessage)
		SELECT	temp.RowId,temp.PaymentNo,temp.ReceivedDate,FromCustomer,ToCustomer,temp.Amount,ToAmount,ActualRate,RebatePayment,Description,
				CASE  WHEN dupRow.RowId IS NOT NULL THEN dupRow.ErrorMessage
					 WHEN ISNUMERIC(temp.Amount)=0 OR ISNUMERIC(ActualRate)=0 OR CAST(ActualRate AS FLOAT) <= 0 OR CAST(temp.Amount AS FLOAT) = 0 THEN 'Invalid Amount or Actual Rate.'
					 WHEN LEN(SUBSTRING(temp.Amount, CHARINDEX('.',temp.Amount ) + 1, LEN(temp.Amount))) > 2 AND CHARINDEX('.',temp.Amount) > 0 THEN 'Invalid Amount. Amount have 2 decimal digits only.'
					 WHEN ISDATE(temp.ReceivedDate) = 0 THEN 'Invalid Received Date.' 
					 WHEN RebatePayment = 'Y' AND CAST(temp.Amount AS MONEY) > 0 THEN 'Invalid Rebate Payment. Amount has to less than 0.'
					 WHEN RebatePayment = 'Y' AND FromPayerID IS NOT NULL AND ToPayerID IS NOT NULL THEN 'Rebate Payment could not be a transfer overpayment.'
					 --WHEN (RebatePayment <> 'Y' OR RebatePayment IS NULL) AND CAST(Amount AS MONEY) < 0 THEN 'Invalid Payment. Amount has to greater than 0.'
					 WHEN ISNULL(FromCustomer,'') ='' and ISNULL(ToCustomer,'') ='' THEN 'Username cannot be blank.' 
					 WHEN FromCustomer = ToCustomer THEN 'From Cust must different To Cust.' 
					 WHEN LEN(Description) > 200 THEN 'Maximum length of Description is 200 characters.' 	
					 WHEN FromCurrName = ToCurrName AND CAST(ActualRate AS FLOAT) <> 1 THEN 'Same currency name, but actual rate is different 1.'
					 WHEN FromCurrCode <> ToCurrCode AND FromCurrCode <> 'MYR' AND ToCurrCode <> 'MYR' THEN 'From Cust and To Cust must belong same currency code.'
					 WHEN FromPayerID IS NULL THEN 'Invalid From Cust.'
					 WHEN FromPayerID IS NOT NULL AND ToPayerID IS NULL AND EXISTS (SELECT 1 FROM LA_Payment p WITH(NOLOCK) WHERE p.PaymentNo = temp.PaymentNo AND p.Type IN (0,2)) THEN 'Payment No exists in the system.'
					 WHEN FromPayerID IS NOT NULL AND ToPayerID IS NULL	AND isFinanceAcc = 0 THEN 'Invalid To Cust'
	
					 ELSE 'Invalid From Cust or To Cust.' END AS Reason

		FROM (SELECT *  FROM @tblInfo WHERE RowId not in (SELECT RowId FROM @tblSucc)) AS temp
		LEFT JOIN @tblDuplicatedPaymentNo dupRow ON dupRow.RowId = temp.RowId

		-- Valid 
		SELECT RowId,PaymentNo,ReceivedDate,FromCustomer,ToCustomer,Amount,ActualRate,RebatePayment,Description,
			   CASE WHEN (
							(FromCurrCode = 'MYR' AND ToCurrCode <> 'MYR') 
							OR (ToCurrCode = 'MYR' AND FromCurrCode <> 'MYR')
							OR (FromCurrCode = ToCurrCode)
						 ) AND CAST(CurrentExRate AS MONEY) <> CAST( ActualRate AS MONEY)
						 
					AND  MultipliedBy <> 1 THEN 'Different system actual rate ('+FORMAT(CAST(CurrentExRate AS MONEY),'F4','en-us')+')' + CHAR(13) +
							'Transaction with exchange rate having "Multiplied by" (Currency '+CurrencyName+', Multiplied by = '+CAST(MultipliedBy AS VARCHAR(20))+')'		    
					WHEN (
							(FromCurrCode = 'MYR' AND ToCurrCode <> 'MYR') 
							OR (ToCurrCode = 'MYR' AND FromCurrCode <> 'MYR')
							OR (FromCurrCode = ToCurrCode)
						 ) AND  ActualRate  NOT BETWEEN CurrentExRate - MinActualrate * CurrentExRate AND CurrentExRate + MinActualrate * CurrentExRate
					THEN 'Exceed limit range ('+ FORMAT(CurrentExRate - MinActualrate * CurrentExRate ,'F4','en-us')+' - '+FORMAT(CurrentExRate + MinActualrate * CurrentExRate,'F4','en-us' )+')'
					WHEN FromCurrCode = ToCurrCode AND FromCurrName <> ToCurrName AND  CAST(CurrentExRate AS MONEY) <> CAST( ActualRate AS MONEY) THEN 'Different system actual rate ('+FORMAT(CAST(CurrentExRate AS MONEY),'F4','en-us')+')'
					WHEN (
							(FromCurrCode = 'MYR' AND ToCurrCode <> 'MYR') 
							OR (ToCurrCode = 'MYR' AND FromCurrCode <> 'MYR')
						 ) AND  CAST(CurrentExRate AS MONEY)  <> CAST( ActualRate AS MONEY)
					THEN 'Different system actual rate ('+FORMAT(CAST(CurrentExRate AS MONEY),'F4','en-us')+')'
					WHEN MultipliedBy <> 1 THEN 'Transaction with exchange rate having "Multiplied by" (Currency '+CurrencyName+', Multiplied by = '+CAST(MultipliedBy AS VARCHAR(20))+')'
					END Remark, FromCustID, ToCustID
		FROM @tblSucc
		ORDER BY RowId

		-- Invalid
		SELECT RowId,PaymentNo,ReceivedDate,FromCustomer,ToCustomer,Amount,ActualRate,RebatePayment,Description,ErrorMessage
		FROM @tblFail
		ORDER BY RowId

	END

	IF @Template = 0 --Cross transfer
	BEGIN
		-- Check valid 
		INSERT INTO @tblSucc(RowId,PaymentNo,ReceivedDate,FromCustomer,ToCustomer,Amount,ToAmount,ActualRate,RebatePayment,Description,
				MinActualrate, MaxActualrate,MultipliedBy,CurrencyName,FromCurrName,ToCurrName,FromCurrCode,ToCurrCode,SystemExRate,TransExrate, FromCustID, ToCustID)
		SELECT	RowId,PaymentNo,ReceivedDate,FromCustomer,ToCustomer,Amount,ToAmount,ActualRate,RebatePayment,Description,
				MinActualrate, MaxActualrate,MultipliedBy,CurrencyName,FromCurrName,ToCurrName,FromCurrCode,ToCurrCode,SystemExRate,TransExrate, FromCustID, ToCustID
		FROM	@tblInfo as t
		WHERE	ISNUMERIC(t.Amount)=1  AND ISDATE(ReceivedDate) = 1
				AND ( 
						(CONVERT(MONEY,t.Amount) > 0 AND CONVERT(MONEY,t.ToAmount) > 0) 
						OR 
						(CONVERT(MONEY,t.Amount) < 0 AND CONVERT(MONEY,t.ToAmount) < 0)
					) -- check if same sign
				AND CONVERT(MONEY,t.Amount) <> 0
				AND CONVERT(MONEY,t.ToAmount) <> 0
				AND t.FromCustID IS NOT NULL
				AND t.ToCustID IS NOT NULL
				AND t.FromCustID <> t.ToCustID
				AND (LEN(SUBSTRING(t.Amount, CHARINDEX('.',t.Amount ) + 1, LEN(t.Amount))) <= 2  OR CHARINDEX('.',t.Amount ) = 0) -- Amount has less than 2 decimal digits
				AND (LEN(SUBSTRING(t.ToAmount, CHARINDEX('.',t.ToAmount ) + 1, LEN(t.ToAmount))) <= 2  OR CHARINDEX('.',t.ToAmount ) = 0) -- Amount has less than 2 decimal digits
				AND LEN(t.Description) <= 200
				AND (
					(t.RebatePayment = 'Y' AND CAST(t.Amount AS FLOAT) < 0 AND CAST(t.ToAmount AS FLOAT) < 0 AND t.ToPayerID IS NULL)
						OR 
					( (t.RebatePayment IS NULL OR t.RebatePayment <> 'Y') AND CAST(t.Amount AS FLOAT) <> 0 AND CAST(t.ToAmount AS FLOAT) <> 0 )
					)
				AND t.RebatePayment IN ('Y','N')
				AND t.FromCurrencyID <> t.ToCurrencyID
				AND FromPayerID IS NOT NULL
				AND (
						(ToPayerID IS NULL AND NOT EXISTS (SELECT 1 FROM LA_Payment p WITH(NOLOCK) WHERE p.PaymentNo = t.PaymentNo AND p.Type IN (0,2))  AND isFinanceAcc = 1)
						OR ToPayerID IS NOT NULL 
						
					)
				AND NOT EXISTS (SELECT 1 FROM @tblDuplicatedPaymentNo dupRow WHERE dupRow.RowId = t.RowId)


		INSERT INTO @tblFail(RowId,PaymentNo,ReceivedDate,FromCustomer,ToCustomer,Amount,ToAmount,ActualRate,RebatePayment,Description,ErrorMessage)
		SELECT	temp.RowId,temp.PaymentNo,temp.ReceivedDate,FromCustomer,ToCustomer,temp.Amount,ToAmount,ActualRate,RebatePayment,Description,
				CASE WHEN dupRow.RowId IS NOT NULL THEN dupRow.ErrorMessage
					 WHEN ISNUMERIC(temp.Amount)=0 OR ISNUMERIC(ToAmount)= 0 OR CONVERT(MONEY,temp.Amount) = 0 OR CONVERT(MONEY,ToAmount) = 0 THEN 'Invalid Amount. From Amount and To Amount should not be equal to 0.' 
					 WHEN (CONVERT(MONEY,temp.Amount) > 0 AND CONVERT(MONEY,ToAmount) < 0) OR (CONVERT(MONEY,temp.Amount) < 0 AND CONVERT(MONEY,ToAmount) > 0) THEN 'Invalid Amount. From Amount and To Amount have to be the same sign.'
					 WHEN (LEN(SUBSTRING(temp.Amount, CHARINDEX('.',temp.Amount ) + 1, LEN(temp.Amount))) > 2 AND CHARINDEX('.',temp.Amount) > 0)   OR
						  (LEN(SUBSTRING(ToAmount, CHARINDEX('.',ToAmount ) + 1, LEN(ToAmount))) > 2  AND CHARINDEX('.',ToAmount) > 0 ) THEN 'Invalid Amount. From Amount and To Amount have 2 decimal digits only.'
					 WHEN ISDATE(temp.ReceivedDate) = 0 THEN 'Invalid Received Date.' 
					 WHEN RebatePayment = 'Y' AND ( CAST(temp.Amount AS MONEY) > 0 OR CAST(ToAmount AS MONEY) > 0 )  THEN 'Invalid Rebate Payment. From Amount and To Amount have to less than 0.'
					 WHEN RebatePayment = 'Y' AND FromPayerID IS NOT NULL AND ToPayerID IS NOT NULL THEN 'Rebate Payment could not be a transfer overpayment.'
					 WHEN ISNULL(FromCustomer,'') = ''  OR ISNULL(ToCustomer,'') = '' THEN 'Username cannot be blanked.' 
					 WHEN FromCustomer = ToCustomer THEN 'From Cust and To Cust must be different.' 
					 WHEN LEN(Description) > 200 THEN 'Maximum length of Description is 200 characters' 
					 WHEN FromCurrencyID = ToCurrencyID THEN 'From Cust and To Cust must be different currency.' 
					 WHEN FromActualRate = 0 OR ToActualRate = 0 THEN 'Invalid Exchange Rate.'
					 WHEN FromPayerID IS NULL THEN 'Invalid From Cust.'
					 WHEN FromPayerID IS NOT NULL AND ToPayerID IS NULL AND EXISTS (SELECT 1 FROM LA_Payment p WITH(NOLOCK) WHERE p.PaymentNo = temp.PaymentNo AND p.Type IN (0,2)) THEN 'Payment No exists in the system.'
					 WHEN FromPayerID IS NOT NULL AND ToPayerID IS NULL	AND isFinanceAcc = 0 THEN 'Invalid To Cust'
					 ELSE 'Invalid From Cust or To Cust.' END AS Reason
						 
		FROM  (SELECT * FROM @tblInfo WHERE RowId NOT IN (SELECT RowId FROM @tblSucc) ) AS temp 
		LEFT JOIN @tblDuplicatedPaymentNo dupRow ON dupRow.RowId = temp.RowId

		-- Valid
		SELECT RowId,PaymentNo,ReceivedDate,FromCustomer,ToCustomer,Amount AS FromAmount,ToAmount,RebatePayment,Description,SystemExRate,TransExrate,FromCustID, ToCustID
		FROM @tblSucc
		ORDER BY RowId

		-- Invalid
		SELECT RowId,PaymentNo,ReceivedDate,FromCustomer,ToCustomer,Amount AS FromAmount,ToAmount,RebatePayment,Description,ErrorMessage
		FROM @tblFail
		ORDER BY RowId


	END
	END
END
GO