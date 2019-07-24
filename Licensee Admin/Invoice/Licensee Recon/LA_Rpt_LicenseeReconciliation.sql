/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

declare--ALTER PROCEDURE [dbo].LA_Rpt_LicenseeReconciliation
	@PartyIds			VARCHAR(4000) = '',
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@Environment		VARCHAR(50)
--AS
/*	Header:
	Created: 2018.10.04 - Parsons
	Task : Generate amount for software fee
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20190723@Bruce: Create Sp
*/select @PartyIds='14,15,16',
	@FromDate='20190501',
	@ToDate	 ='20190531',
	@Environment=''
BEGIN
	SET NOCOUNT ON
	
	DECLARE @AmountTypeSoftwareFee INT = 1,
		@AmountTypeDiscount INT = 4,
		@AmountTypeRebate INT = 6,
		@DeductAgainstInvoice INT = 24

	DECLARE @DaysInMonth INT = DATEDIFF(day, @FromDate, @ToDate) + 1

	-- supported products
	-- 
	DECLARE @supportedProducts VARCHAR(100) = 'SB,NG,VS,AGC,GD,KN,CS,BA,AB,CO,CB,VS2,PP,VB,FW,LT,BX'
	DECLARE @productList TABLE(ProductId INT, Code VARCHAR(5))
	INSERT INTO @productList
	SELECT ProductID, ProductPrefix FROM dbo.LA_f_Products3rd(@supportedProducts)

	-- get all party list
	--
	DECLARE @partyList AS TABLE(
		PartyId		INT,
		PartyName	VARCHAR(50),
		BrandName	VARCHAR(50),
		ParentId	INT,
		BaseCurrencyId	INT
	)
	INSERT INTO @partyList(PartyId,PartyName,BrandName,ParentId)
	EXEC dbo.LA_PartyListSel

	-- remove unrelated-parties
	--
	DELETE @partyList WHERE ParentId = 0 OR (
		ISNULL(@PartyIds,'') <> '' AND
		PartyID NOT IN (SELECT val FROM dbo.strSplit(@PartyIds,','))
	)

	-- get billing currency
	--
	UPDATE a SET BaseCurrencyId = b.BaseCurrencyId
	FROM @partyList a 
	INNER JOIN dbo.OAS_PartyDetail b WITH(NOLOCK) ON a.PartyId=b.PartyID

	-- get base currency list
	--
	DECLARE @baseCurrencyList AS TABLE (CurrencyId INT, Code VARCHAR(5))
	INSERT INTO @baseCurrencyList(CurrencyId,Code)
	SELECT e.exchangeid,e.Code FROM bodb02.dbo.Exchange e WITH(NOLOCK)
	WHERE e.exchangeid IN (SELECT DISTINCT BaseCurrencyId FROM @partyList)

	-- get amount to company,discount,rebate(only for some supported products)
	CREATE TABLE #AmountToCompany (
		PartyId			INT,
		ProductId		INT,
		Winloss			MONEY,
		Fee				MONEY,
		Discount		MONEY,
		DiscountRate	MONEY,
		DiscountRemark	NVARCHAR(4000),
		Rebate			MONEY,
		RebateRate		MONEY,
		RebateRemark	NVARCHAR(4000),
		NegativeFee		MONEY,
		Minfee			MONEY,
		IsChargedByMinFee BIT
	)

	WHILE EXISTS(SELECT TOP 1 1 FROM @baseCurrencyList)
	BEGIN
		DECLARE @BaseCurrencyCode VARCHAR(5) = (SELECT TOP 1 Code FROM @baseCurrencyList)
		
		INSERT INTO #AmountToCompany(PartyId,ProductId,Winloss,Fee,NegativeFee,Minfee,IsChargedByMinFee,Discount,DiscountRate,DiscountRemark,Rebate,RebateRate,RebateRemark)
		EXEC dbo.LA_AmountToCompanySel @FromDate,@ToDate,@PartyIds,@supportedProducts,@BaseCurrencyCode
		
		DELETE @baseCurrencyList WHERE Code = @BaseCurrencyCode
	END
	/*
	-- get AMF, AG and prepayment
	DECLARE @InvoiceItemTypes TABLE([Key] VARCHAR(50), [Value] INT)
	DECLARE @AdvanceMinFee VARCHAR(50) = 'AdvanceMinFee', @PrepaymentKey VARCHAR(50) = 'Prepayment', @AGPrepayment VARCHAR(50) = 'AGPrepayment'

	INSERT INTO @InvoiceItemTypes ([Key], [Value])
	SELECT @AdvanceMinFee, value
		FROM (VALUES(3), (5), (7), (21)) AS T1(value)
	UNION ALL
	SELECT @PrepaymentKey, value
		FROM (VALUES(22), (23), (24)) AS T2(value)
	UNION ALL
	SELECT @AGPrepayment, value
		FROM (VALUES(25), (26), (27)) AS T3(value)

	DECLARE @tblInvoiceAmounts TABLE (Income MONEY, Expense MONEY, InvItemTypeId INT)
	SELECT @sql = 'SELECT Income, Expense, InvItemTypeId
					FROM OPENQUERY(DBCUST, ''SELECT Income, Expense, InvItemTypeId FROM bodb_Licensee.dbo.LA_f_GetInvoiceAmount(' 
																							+ CONVERT(VARCHAR(10), @PartyId)
																							+ ', 0'
																							+ ', ''''' + ISNULL(@Environment, '') + ''''''
																							+ ')'')'
	INSERT INTO @tblInvoiceAmounts (Income, Expense, InvItemTypeId)
	EXEC (@sql)
	
	SELECT SUM(ISNULL(s.Income,0) - ISNULL(s.Expense,0)) AS Amount, s.InvItemTypeId, invT.[Key] AS InvItemTypeKey 
	INTO #credit
	FROM @tblInvoiceAmounts s
		INNER JOIN @InvoiceItemTypes invT ON s.InvItemTypeId = invT.Value
	GROUP BY s.InvItemTypeId, invT.[Key]

	DECLARE @RemainingAmf MONEY = ISNULL((SELECT SUM(Amount) FROM #credit WHERE InvItemTypeKey = @AdvanceMinFee), 0)
	DECLARE @RemainingAG MONEY = ISNULL((SELECT SUM(Amount) FROM #credit WHERE InvItemTypeKey = @AGPrepayment), 0)
	DECLARE @Prepayment MONEY = ISNULL((SELECT SUM(Amount) FROM #credit WHERE InvItemTypeKey = @PrepaymentKey), 0)

	-- insert zero amount
	INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, InvoiceAmount, AmountType)
	SELECT p.ProductID, p.ProductPrefix, p.ProductName, 0, @AmountTypeSoftwareFee
	FROM (SELECT DISTINCT pci.ProductID, pd.ProductPrefix, pd.ProductName 
		FROM @PartyChargeInfo pci
		INNER JOIN dbo.LA_f_Products3rd('') pd ON pci.ProductID = pd.ProductID
		LEFT JOIN @FinalResult r ON pci.ProductID = r.ProductId
		WHERE r.ProductId IS NULL) p

	-- insert amf
	IF @RemainingAmf > 0 
	BEGIN
		DECLARE @ProgratedMinfee MONEY = ISNULL((SELECT TOP 1 MinFee FROM #AmountToCompany WHERE ProductId = 0),0)
		DECLARE @SBAfterDiscount MONEY = ISNULL((
			SELECT SUM(CASE WHEN AmountType = @AmountTypeSoftwareFee THEN InvoiceAmount ELSE -InvoiceAmount END)
			FROM @FinalResult
			WHERE ProductId = 0 AND AmountType IN (@AmountTypeSoftwareFee, @AmountTypeDiscount) 
		),0)
		DECLARE @AmfAmount MONEY = (CASE WHEN @RemainingAmf < @ProgratedMinfee THEN @RemainingAmf ELSE @ProgratedMinfee END)
		SET @AmfAmount = (CASE WHEN @AmfAmount < @SBAfterDiscount THEN @AmfAmount ELSE @SBAfterDiscount END)
		SET @AmfAmount = (CASE WHEN @AmfAmount < 0 THEN 0 ELSE @AmfAmount END)

		UPDATE @FinalResult SET DeductMonthlyFees = @AmfAmount, RemainingAmount = @RemainingAmf
		WHERE AmountType = @AmountTypeSoftwareFee AND ProductId = 0 -- SB
	END

	-- insert AG setup fees
	DECLARE @AGMonthlyFee MONEY
	SELECT @AGMonthlyFee = SUM(CASE WHEN AmountType = @AmountTypeSoftwareFee THEN InvoiceAmount ELSE -InvoiceAmount END)
	FROM @FinalResult 
	WHERE ProductId = 10 AND AmountType IN (@AmountTypeSoftwareFee, @AmountTypeDiscount)
	IF (@AGMonthlyFee > 0 AND @RemainingAG > 0)
	BEGIN
		DECLARE @AGAmount MONEY = (CASE WHEN @RemainingAG < @AGMonthlyFee THEN @RemainingAG ELSE @AGMonthlyFee END)

		UPDATE @FinalResult SET DeductMonthlyFees = @AGAmount, RemainingAmount = @RemainingAG
		WHERE AmountType = @AmountTypeSoftwareFee AND ProductId = 10 -- AG
	END

	IF @Prepayment>0
	BEGIN
		INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, AmountType, InvoiceAmount, RemainingAmount)
		VALUES(0,'','',@DeductAgainstInvoice,0,@Prepayment)
	END

	SELECT	f.ProductId,
			f.ProductCode,
			f.ProductName,
			f.InvoiceAmount,
			f.AmountType,
			f.Rate,
			f.DeductMonthlyFees,
			f.RemainingAmount,
			f.Remark
	FROM	@FinalResult f
	ORDER BY f.AmountType, f.ProductId

	SELECT @ErrCode = 0, @ErrMsg = ''
	*/
	select * from #AmountToCompany
	DROP TABLE #AmountToCompany

END
GO