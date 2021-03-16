/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_GenerateAmountForSoftwareFee]
	@PartyId			INT,
	@BillerId			INT,
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@ProductCodes		VARCHAR(500),
	@Environment		VARCHAR(50),
	@ErrCode			INT				= 0		OUTPUT,
	@ErrMsg				NVARCHAR(1000)	= ''	OUTPUT,
	@BaseCurrency		VARCHAR(10)		= 'EUR'	OUTPUT,
	@InvoiceTemplateName VARCHAR(200)	= ''	OUTPUT
WITH RECOMPILE
AS

/*	Header:
	Created: 2018.10.04 - Parsons
	Task : Generate amount for software fee
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20181004@Parsons: Integrate AG setup fee into invoices [#98485]
		- 20190123@Parsons: Improve AG prepayment and discount setting [#104620]
	    - 20190416@Parsons: Integrate-PP-Promotion-Prize [#109014]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20190911@Bruce: Support Exchange product in invoices [#119846]
		- 20191017@Parsons: Non-peak hour promotion [#119538]
		- 20191209@Parsons: PP tournament [#123958] 
		- 20200505@Parsons: Special handling for INH market [#128570] 
		- 20200714@Parsons: Implement PP Jackpot [RedmineID: #137306] 
		- 20201028@Parsons: Arcadia Gaming - Add Bonus feature [#143597]
		- 20201130@Parsons: Saba.club - Offer Freebet tickets [#141423]
		- 20210201@Parsons: Saba.club - Integrate Slot Game [#147977]
		- 20210314@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @AmountTypeSoftwareFee INT = 1,
		@AmountTypeDiscount INT = 4,
		@AmountTypeRebate INT = 6,
		@DeductAgainstInvoice INT = 24,
		@DeductSabaPromotion INT = 29,
		@DeductPPPrizes INT = 30,
		@PP_Contribution_InvItemType INT = 31,
		@PP_JackpotPrize_InvItemType INT = 32

	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
	DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1

	DECLARE	@FinalResult TABLE(
			ProductId		INT,
			ProductCode		VARCHAR(100),
			ProductName		VARCHAR(500),
			Remark			NVARCHAR(4000),
			InvoiceAmount	MONEY,
			AmountType		TINYINT,
			Rate			MONEY,
			DeductMonthlyFees	MONEY,
			RemainingAmount	MONEY)

	-- Region: Get base Currency
	DECLARE @BaseCurrencyId INT 
	SELECT TOP 1 @BaseCurrencyId = BaseCurrencyId
	FROM OAS_PartyBaseCurrency WITH(NOLOCK)
	WHERE PartyID = @PartyId AND FromDate <= @ToDate AND ToDate >= @FromDate
	
	IF(@BaseCurrencyId IS NULL)
	BEGIN
		SET @BaseCurrencyId = 6 -- default EUR
	END
	
	DECLARE @BaseCurrencyTable AS TABLE(CurrencyId INT, CurrencyName VARCHAR(10))
	INSERT	INTO @BaseCurrencyTable(CurrencyId, CurrencyName)
	EXECUTE dbo.LA_SelBaseCurrency
	
	SELECT	@BaseCurrency = CurrencyName
	FROM	@BaseCurrencyTable
	WHERE	@BaseCurrencyId = CurrencyId
	
	-- End Region	

	-- Region: Get template
	DECLARE @sql NVARCHAR(MAX)
	DECLARE @tblInvoiceTemplates TABLE (InvoiceTemplateName NVARCHAR(10))

	SELECT @sql = 'SELECT InvoiceTemplateName
					FROM OPENQUERY(DBCUST, ''SELECT InvoiceTemplateName FROM bodb_Licensee.dbo.LA_f_GetInvoiceTemplate('
																							+ CONVERT(VARCHAR(10), @PartyId)
																							+ ', ' + CONVERT(VARCHAR(10), @BillerId)
																							+ ', ' + CONVERT(VARCHAR(10), @AmountTypeSoftwareFee)
																							+ ')'')'
	INSERT INTO @tblInvoiceTemplates (InvoiceTemplateName)
	EXEC (@sql)

	SELECT @InvoiceTemplateName = InvoiceTemplateName FROM @tblInvoiceTemplates
	-- End Region

	-- Region: Get exchange rate info
	CREATE TABLE #Exchange (
			ExchangeDate	DATE,
			ExchangeID		INT,
			CurrencyCode	VARCHAR(10),
			Rate			FLOAT
	)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)
	
	-- End region

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
	INSERT INTO #AmountToCompany(PartyId,ProductId,Winloss,Fee,NegativeFee,Minfee,IsChargedByMinFee,Discount,DiscountRate,DiscountRemark,Rebate,RebateRate,RebateRemark)
	EXEC dbo.LA_AmountToCompanySel @FromDate,@ToDate,@PartyId,@ProductCodes,@BaseCurrency

	-- Region: Get party charge rate info	
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			BettypeRef  INT,
			Rate		MONEY,
			TypeId		SMALLINT,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, BettypeRef, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, ProductID, Bettype, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyId, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId NOT IN (1, 15) --exclude RB, CB
	)

	-- exclude products have calculated
	DELETE @PartyChargeInfo WHERE ProductID IN (SELECT a.ProductId FROM #AmountToCompany a)

	-- Get ChargeInfo for CB
	DECLARE @CommChargeType INT = 6
	DECLARE @CashInShareChargeType INT = 7

	DECLARE @BAProductId INT = 3
	DECLARE @CBProductId INT = 15
	DECLARE @COProductId INT = 25
	DECLARE @BXProductId INT = 31
	DECLARE @PPProductId INT = 32

	IF(CHARINDEX('CB', @ProductCodes) > 0 AND EXISTS(SELECT TOP 1 1 FROM bodb02.dbo.strSplit(@ProductCodes, ',') WHERE val = 'CB'))
	BEGIN
		INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, TypeId, FromDate, ToDate)
		SELECT	ci.FromParty,
				CASE WHEN ISNULL(pd.IsDeposit, 0) = 1 THEN p.OldRefID ELSE lb.LabelID END AS LicenseeId,
				@CBProductId,
				ci.Rate,
				ci.ChargeType,
				CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
				CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
		FROM dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
			LEFT JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
			LEFT JOIN dbo.Labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
		WHERE FromParty = @PartyId
			AND ProductID = @CBProductId
			AND ChargeType IN (@CommChargeType,@CashInShareChargeType)
			AND @FromDate <= ci.ToDate
			AND ci.FromDate <= @ToDate
	END
	-- End Get ChargeInfo for CB

	-- check payer exchange & minfee exchange
	--
	IF EXISTS (
		SELECT TOP 1 m.PartyId
		FROM LA_MinFee m WITH(NOLOCK)
		WHERE m.PartyId = @PartyId
			AND m.FeeTypeId = 1 -- 1 = minfee
			AND m.FromDate <= @ToDate AND m.ToDate >= @FromDate AND @BaseCurrencyId <> m.CurrencyId
	)
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = 'Please check the Exchange settings of Payer''s minfee or minfee group. Exchange of minfee or minfees in group should be the same with Payer''s exchange.'
		SELECT ProductId,
			ProductCode,
			ProductName,
			InvoiceAmount,
			AmountType,
			Rate,
			DeductMonthlyFees,
			RemainingAmount,
			Remark 
		FROM @FinalResult

		DROP TABLE #Exchange
		DROP TABLE #AmountToCompany
		RETURN
	END

	-- check payer exchange & discount exchange
	--
	DECLARE @DiscountCurrencyId INT = (
		SELECT TOP 1 h.CurrencyId
		FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupHeader h WITH(NOLOCK) ON a.DiscountGroupId=h.DiscountGroupId
		INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON h.DiscountGroupId=p.DiscountGroupId
		INNER JOIN #AmountToCompany c ON c.PartyId = a.PartyID AND c.ProductId=p.ProductId
		WHERE h.DiscountGroupType != 2 -- rebate
			AND h.FromDate <= @ToDate
			AND h.ToDate >= @FromDate
			AND a.PartyID = @PartyId
			AND a.IsApplyDiscount = 1
			AND ISNULL(c.DiscountRate,0) > 0
			AND p.CalculationType IN (0,10) -- 0: discount, 10: discount & calculate
		ORDER BY h.ToDate DESC
	)

	IF @DiscountCurrencyId IS NOT NULL AND @DiscountCurrencyId != @BaseCurrencyId
	BEGIN
		SELECT @ErrCode = 2, @ErrMsg = 'Please check the Exchange settings of Payer''s discount. Exchange of discount must be the same with Payer''s exchange.'
		SELECT ProductId,
			ProductCode,
			ProductName,
			InvoiceAmount,
			AmountType,
			Rate,
			DeductMonthlyFees,
			RemainingAmount,
			Remark 
		FROM @FinalResult

		DROP TABLE #Exchange
		DROP TABLE #AmountToCompany

		RETURN
	END

	-- Region: Get Amount by Product (The remaining products)
	CREATE	TABLE #TempData (
			LicenseeId		INT, 
			PartyId			INT, 
			rptDate			DATETIME, 
			CurrencyId		INT, 
			WinLoss			MONEY, 
			AComm			MONEY, 
			ProductId		TINYINT,
			BettypeRef		INT, 
			AmountToCompany MONEY,
			IsApplyMinFee	BIT)
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,WinLoss,AComm,ProductId,BettypeRef)
	(
		SELECT	b.SiteID,
				p.PartyId, 
				b.rptDate, 
				b.CurrencyID, 
				SUM(ISNULL(b.MemberWL, 0)) Winloss, 
				SUM(ISNULL(b.CommissionA, 0)) AS AComm, 
				p.ProductId,
				r.BettypeRef
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				LEFT JOIN dbo.Sport_Bettype_Reference r ON b.Bettype = r.Bettype
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.Bettype = -1 OR r.BettypeRef = p.BettypeRef)
													AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate			
				AND b.StatusId NOT IN (-1, 101, 102, 103)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
				AND b.ProductId NOT IN (@CBProductId, @COProductId)
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId, r.BettypeRef
	)
	
	UPDATE	#TempData
	SET		AmountToCompany =	CASE  
									WHEN td.ProductId = @BAProductId THEN (-td.WinLoss * p.Rate - td.AComm) * e.Rate
									WHEN td.ProductId <> @BAProductId THEN (-td.WinLoss * p.Rate) * e.Rate
									ELSE 0 
								END
	FROM	#TempData td 
			INNER JOIN @PartyChargeInfo p 
				ON td.LicenseeId = p.LicenseeId 
				AND ((td.ProductId = p.ProductID AND td.ProductId NOT IN (SELECT DISTINCT Productid FROM dbo.LA_Product3rdSub WITH(NOLOCK)))
						OR 
					(td.ProductId = p.ProductID AND td.BettypeRef = p.BettypeRef AND td.ProductId IN (SELECT DISTINCT Productid FROM dbo.LA_Product3rdSub WITH(NOLOCK))))
				AND td.rptDate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN #Exchange e ON td.rptDate = e.ExchangeDate AND td.CurrencyId = e.ExchangeID
	-- End region	
	
	-- Region: Get Amount By Product CB
	CREATE TABLE #TempDataCB (
		rptDate				DATETIME,
		LicenseeId			INT,
		PartyId				INT,
		ProductId			INT,
		CurrencyId			INT,
		Turnover			MONEY,
		TurnoverForCommision MONEY,
		TurnoverExchanged	MONEY,
		WinningPrize		MONEY,
		CashOut				MONEY,
		CommisionShare		MONEY,
		CashInShare			MONEY,
		CashInAmount		MONEY
	)
		
	INSERT INTO #TempDataCB (rptDate, LicenseeId, PartyId, ProductId, CurrencyId, Turnover, TurnoverForCommision, WinningPrize, CashOut, CashInAmount)
	SELECT	rptDate,
			b.SiteID,
			cb.PartyId,
			b.ProductId,
			CurrencyId,
			SUM(Turnover) Turnover,
			SUM(CASE WHEN ISNULL(b.TicketType, 0) = 0 THEN b.Turnover ELSE b.ExtraAmount END) TurnoverForCommision,
			SUM(ISNULL(WinPrizeAmount,0)) WinningPrize,
			SUM(ISNULL(CashOutAmount,0)) CashOut,
			SUM(ISNULL(BuyBackAmount,0)) CashInAmount
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
	JOIN @PartyChargeInfo cb ON b.SiteID = cb.LicenseeId AND b.ProductId = cb.ProductID AND b.rptDate BETWEEN cb.FromDate AND cb.ToDate
	WHERE	b.ProductId = @CBProductId AND 
		b.StatusId NOT IN (-1, 101, 102, 103) AND
		CustomerCategory NOT IN (27, 28) AND 
		CurrencyId <> 20 AND 
		cb.TypeId = @CommChargeType -- to remove duplicate we use one of (6,7)
	GROUP BY rptdate, CurrencyId, b.SiteID, cb.PartyId, b.ProductId
	
	UPDATE #TempDataCB
	SET CommisionShare = td.TurnoverForCommision * cm.Rate, CashInShare = td.CashInAmount * ci.Rate
	FROM #TempDataCB td
	JOIN @PartyChargeInfo AS cm ON cm.ProductID = @CBProductId AND cm.TypeId = @CommChargeType AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate)
	JOIN @PartyChargeInfo AS ci ON cm.ProductID = @CBProductId AND ci.TypeId = @CashInShareChargeType AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate)
	
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,ProductId, AmountToCompany)
	SELECT LicenseeId, PartyId, rptDate, CurrencyId, ProductId, (Turnover - WinningPrize - Cashout - CommisionShare - CashInShare) * e.Rate
	FROM #TempDataCB tcb
	INNER JOIN #Exchange e ON tcb.rptDate = e.ExchangeDate AND tcb.CurrencyId = e.ExchangeID	
	-- End region: Get Amount By Product CB
	
	-- Region: Get Amount By Product CO
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,ProductId, AmountToCompany)
	(
		SELECT
			d.LicenseeId,			
			d.PartyId,
			d.Winlostdate,
			d.Currency,
			@COProductId,
			(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) * e.Rate AS AmountToCompany
		FROM (
			SELECT p.LicenseeId, p.PartyId, b.Winlostdate, b.Currency,
				SUM(b.BuyBackAmt) AS BuyBackAmountSB,
				SUM(b.BABuyBackAmt) AS BuyBackAmountBA,
				SUM(b.TicketPayout) AS TicketsPayout,					
				SUM(b.BuyBackAmt  * p.Rate) AS CashoutCommission	
			FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON b.SiteId = p.LicenseeId AND b.ProductId = p.ProductID AND b.Winlostdate BETWEEN p.FromDate AND p.ToDate
			WHERE b.Winlostdate BETWEEN p.FromDate AND p.ToDate									
				AND b.ProductID = 25	
				AND b.Currency <> 20
				AND b.RoleID = 1 -- Member Level			
			GROUP BY p.LicenseeId, p.PartyId, b.Winlostdate, b.Currency
		) d
		INNER JOIN #Exchange e ON d.Winlostdate = e.ExchangeDate AND d.Currency = e.ExchangeID	
	)
	-- End region: Get Amount By Product CO

	DECLARE @InvoiceData	TABLE(
			PartyId			INT,
			ProductId		INT, 
			InvoiceAmount	MONEY, 
			AmountType		TINYINT,
			Rate			MONEY,
			Remark			NVARCHAR(4000))

	-- Region: fee
	INSERT INTO @InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType)
	SELECT d.PartyId, d.ProductId, d.Fee, @AmountTypeSoftwareFee
	FROM #AmountToCompany d
	-- End Region: fee

	-- product dont have minfee
	INSERT INTO @InvoiceData(PartyId,ProductId,InvoiceAmount,AmountType)
	(
		SELECT	td.PartyId,
				td.ProductId,
				SUM(td.AmountToCompany),
				@AmountTypeSoftwareFee
		FROM	#TempData td 
		WHERE	td.ProductId NOT IN (SELECT td2.ProductId FROM @InvoiceData td2)
		GROUP	BY td.PartyId, td.ProductId
	)

	-- Region: Discount
	INSERT INTO @InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType, Rate, Remark)
	SELECT d.PartyId, d.ProductId, d.Discount, @AmountTypeDiscount, d.DiscountRate, d.DiscountRemark
	FROM #AmountToCompany d WHERE d.Discount > 0
	-- End Region

	-- Region: Select data	
	INSERT INTO @FinalResult(ProductId,ProductCode,ProductName,InvoiceAmount,AmountType,Rate,Remark)
	(
		SELECT	id.ProductId,
				CASE 
					WHEN id.ProductId = 0 THEN 'SB' 
					ELSE p.ProductPrefix
					END AS ProductCode,
				CASE 
					WHEN id.ProductId = 0 THEN 'Sportsbook' 
					ELSE p.ProductName
					END AS ProductName,
				CASE
					WHEN id.InvoiceAmount > 0 OR id.ProductId IN (@BAProductId, @CBProductId, @COProductId, @PPProductId,@BXProductId) THEN id.InvoiceAmount
					ELSE 0
				END AS InvoiceAmount,
				id.AmountType,
				id.Rate,
				id.Remark
		FROM	@InvoiceData id
				LEFT JOIN dbo.Product3rd p WITH(NOLOCK) ON id.ProductId = p.Productid
	)
	
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

		DECLARE @AmfAmount MONEY
		SELECT @AmfAmount = CASE WHEN MIN(Amount) < 0 THEN 0 ELSE MIN(Amount) END
		FROM (VALUES(@SBAfterDiscount), (@ProgratedMinfee),(@RemainingAmf))v(Amount)

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

	-- Region insert Promotion amount
	IF(EXISTS(SELECT TOP 1 1 FROM @FinalResult WHERE ProductId = 0))
	BEGIN
		DECLARE @PromotionAmount MONEY
		SELECT @PromotionAmount = SUM(p.MemberWL * e.Rate)
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct p WITH (NOLOCK) 
			INNER JOIN dbo.LA_f_ChargeInfo(@PartyId, @FromDate, @ToDate, 'SB', 'OA', 1) pc ON p.SiteID = pc.LicenseeId
			INNER JOIN #Exchange e ON p.RptDate = e.ExchangeDate AND p.CurrencyID = e.ExchangeID
			WHERE p.RptDate BETWEEN @FromDate AND @ToDate AND p.ProductID = 37 -- Saba promotion
		
		IF(ISNULL(@PromotionAmount, 0) > 0)
		BEGIN
			INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, AmountType, InvoiceAmount, RemainingAmount)
			VALUES(0,'','',@DeductSabaPromotion,@PromotionAmount,0)
		END
	END
	-- End region insert Promotion amount
	-- Region PP: Tournament Prizes, Promotion, Contribution, Jackpot Prize  
	IF(EXISTS(SELECT TOP 1 1 FROM @FinalResult WHERE ProductId = 32))
	BEGIN
		DECLARE @PP_Contribution_Bettype SMALLINT = 4297,
				@PP_JackpotPrize_Bettype SMALLINT = 4298,
				@PPTournament_Bettype SMALLINT = 4299,
				@PromotionPrize_Bettype SMALLINT = 4300
		;WITH cte_Pragmatic_ExtraAmount AS
		(
			SELECT b.Bettype, SUM(CASE WHEN b.Bettype = @PP_Contribution_Bettype THEN -b.GrossWL ELSE b.MemberWL END  * e.Rate) AS ExtraAmount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN dbo.LA_f_ChargeInfo(@PartyId, @FromDate, @ToDate, 'PP', 'OA', 1) pc ON b.SiteID = pc.LicenseeId
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
			WHERE b.Bettype IN (@PP_Contribution_Bettype, @PP_JackpotPrize_Bettype, @PPTournament_Bettype, @PromotionPrize_Bettype)
				AND b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.[StatusId] NOT IN (-1, 101, 102, 103)
			GROUP BY b.Bettype
		)
		INSERT INTO @FinalResult(ProductId,ProductCode,ProductName,AmountType,InvoiceAmount,RemainingAmount)
		SELECT 0, '', '', CASE 
								WHEN Bettype = @PP_Contribution_Bettype THEN @PP_Contribution_InvItemType
								WHEN Bettype = @PP_JackpotPrize_Bettype THEN @PP_JackpotPrize_InvItemType
								ELSE  @DeductPPPrizes
							END, SUM(ExtraAmount), 0
		FROM cte_Pragmatic_ExtraAmount
		GROUP BY CASE 
					WHEN Bettype = @PP_Contribution_Bettype THEN @PP_Contribution_InvItemType
					WHEN Bettype = @PP_JackpotPrize_Bettype THEN @PP_JackpotPrize_InvItemType
					ELSE  @DeductPPPrizes
				 END
		
	END
	-- End region Deduct promotion prizes
 
	-- Region Arcadia Gaming: Bonus amount
	IF(EXISTS(SELECT TOP 1 1 FROM @FinalResult WHERE ProductId = 34))
	BEGIN
		DECLARE @BonusAmount MONEY
		SELECT @BonusAmount = SUM(p.MemberWL * e.Rate)
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct p WITH (NOLOCK) 
			INNER JOIN dbo.LA_f_ChargeInfo(@PartyId, @FromDate, @ToDate, 'CC', 'OA', 1) pc ON p.SiteID = pc.LicenseeId
			INNER JOIN #Exchange e ON p.RptDate = e.ExchangeDate AND p.CurrencyID = e.ExchangeID
			WHERE p.RptDate BETWEEN @FromDate AND @ToDate AND p.ProductID = 34 AND p.Bettype = 1906 -- Arcadia Gaming

		IF(ISNULL(@BonusAmount, 0) > 0)
		BEGIN
			INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, AmountType, InvoiceAmount, RemainingAmount)
			VALUES(0,'','',33,@BonusAmount,0)
		END
	END
	-- End region

	-- Region Saba.club
	DECLARE @Saba_clubProductID INT = 42
	IF(EXISTS(SELECT TOP 1 1 FROM @FinalResult WHERE ProductId = @Saba_clubProductID))
	BEGIN
		DECLARE @SBC_Contribution_Bettype SMALLINT = 1698,
				@SBC_JackpotPrize_Bettype SMALLINT = 1699
		;WITH cte_SabaClub_ExtraAmount AS
		(
			SELECT b.Bettype, ISNULL(b.TicketType, 0) TicketType, SUM(CASE WHEN b.Bettype = @SBC_Contribution_Bettype THEN -b.GrossWL ELSE b.MemberWL END * e.Rate) AS ExtraAmount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN dbo.LA_f_ChargeInfo(@PartyId, @FromDate, @ToDate, 'SBC', 'OA', 1) pc ON b.SiteID = pc.LicenseeId
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
			WHERE (ISNULL(b.TicketType, 0) = 2 OR b.Bettype IN (@SBC_Contribution_Bettype, @SBC_JackpotPrize_Bettype))
				AND b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.[StatusId] NOT IN (-1, 101, 102, 103)
			GROUP BY b.Bettype, ISNULL(b.TicketType, 0)
		)
		INSERT INTO @FinalResult(ProductId,ProductCode,ProductName,AmountType,InvoiceAmount,RemainingAmount)
		SELECT 0, '', '', CASE 
								WHEN Bettype = @SBC_Contribution_Bettype THEN 35
								WHEN Bettype = @SBC_JackpotPrize_Bettype THEN 36
								ELSE 34
							END, SUM(ExtraAmount), 0
		FROM cte_SabaClub_ExtraAmount
		GROUP BY CASE 
					WHEN Bettype = @SBC_Contribution_Bettype THEN 35
					WHEN Bettype = @SBC_JackpotPrize_Bettype THEN 36
					ELSE 34
				 END
		HAVING SUM(ExtraAmount) > 0
	END
	-- End region

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

	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #TempDataCB
	DROP TABLE #AmountToCompany
	DROP TABLE #credit

END
GO