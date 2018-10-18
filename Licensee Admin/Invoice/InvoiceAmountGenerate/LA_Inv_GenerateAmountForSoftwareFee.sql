/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
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
	@BaseCurrency		NVARCHAR(20)	= 'EUR'	OUTPUT,
	@InvoiceTemplateName VARCHAR(200)	= ''	OUTPUT
WITH RECOMPILE
AS
/*	Header:
	Created: 2018.10.04 - Parsons
	Task : Generate amount for software fee
	DB: DB052.bodb_Licensee
   
	Revisions: 
		+ 20181004@Parsons: Integrate AG setup fee into invoices [#98485]
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @AmountTypeSoftwareFee INT = 1,
		@AmountTypeDiscount INT = 4,
		@AmountTypeRebate INT = 6,
		@DeductAgainstInvoice INT = 24

	-- Region: Check Invoice Type is Rebate
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
	SET		@BaseCurrencyId = ISNULL((	SELECT TOP 1 opd.BaseCurrencyId
										FROM dbo.OAS_PartyDetail opd WITH(NOLOCK)	
										WHERE	opd.PartyID = @PartyId
									), 6)
	
	DECLARE @BaseCurrencyTable AS TABLE(CurrencyId INT, CurrencyName VARCHAR(10))
	INSERT	INTO @BaseCurrencyTable(CurrencyId, CurrencyName)
	EXECUTE bodb_Licensee.dbo.LA_SelBaseCurrency
	
	SELECT	@BaseCurrency = CurrencyName
	FROM	@BaseCurrencyTable
	WHERE	@BaseCurrencyId = CurrencyId
	
	-- End Region	

	-- Region: Get template
	SELECT @InvoiceTemplateName = ( SELECT	TOP 1 t.InvTemplateName
									FROM	dbo.LA_InvoiceSetting i WITH(NOLOCK)
											INNER JOIN dbo.LA_InvoiceTemplate t WITH(NOLOCK) ON i.InvTempId = t.InvTemplateId
									WHERE	i.FromPartyId = @PartyId
											AND i.ToPartyId = @BillerId
											AND i.InvTypeId = @AmountTypeSoftwareFee)
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

	-- get amount to company,discount,rebate(only for some supported products
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
	DECLARE @CBProductId INT = 15
	DECLARE @COProductId INT = 25

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, TypeId, FromDate, ToDate)
	SELECT	ci.FromParty,
			CASE WHEN ISNULL(pd.IsDeposit, 0) = 1 THEN p.OldRefID ELSE lb.LabelID END AS LicenseeId,
			@CBProductId,
			ci.Rate,
			ci.ChargeType,
			CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
			CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
	FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
		LEFT JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
		LEFT JOIN bodb_licensee.dbo.Labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
	WHERE EXISTS(SELECT val FROM bodb02.dbo.strSplit(@ProductCodes, ',') WHERE val = 'CB')
		AND FromParty = @PartyId
		AND ProductID = @CBProductId
		AND ChargeType IN (@CommChargeType,@CashInShareChargeType)
		AND @FromDate <= ci.ToDate
		AND ci.FromDate <= @ToDate
	-- End Get ChargeInfo for CB

	-- check payer exchange & minfee exchange
	--
	DECLARE @PartyGroups TABLE(PartyId INT, CurrencyId INT)
	INSERT INTO @PartyGroups(PartyId, CurrencyId)
	(
		SELECT d.PartyId, d.BaseCurrencyId
		FROM dbo.LA_PartyGroup g WITH(NOLOCK)
		INNER JOIN dbo.LA_PartyGroupAssignment a WITH(NOLOCK) ON a.PartyGroupId=g.PartyGroupId
		INNER JOIN dbo.LA_PartyGroupAssignment b WITH(NOLOCK) ON a.PartyGroupId=b.PartyGroupId
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.PartyID=b.PartyId
		WHERE a.PartyId = @PartyId
	)
	IF NOT EXISTS (SELECT TOP 1 1 FROM @PartyGroups)
	BEGIN
		INSERT INTO @PartyGroups(PartyId, CurrencyId) VALUES (@PartyId, @BaseCurrencyId)
	END

	IF EXISTS (
		SELECT TOP 1 m.PartyId
		FROM @PartyGroups p
		INNER JOIN dbo.LA_MinFee m WITH(NOLOCK) ON m.PartyId=p.PartyID AND m.FeeTypeId = 1 -- 1 = minfee
		WHERE m.FromDate <=@ToDate AND m.ToDate >= @FromDate AND p.CurrencyId <> m.CurrencyId
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
		RETURN
	END

	-- check payer exchange & discount exchange
	--
	DECLARE @DiscountCurrency INT = (
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

	IF @DiscountCurrency IS NOT NULL AND @DiscountCurrency != @BaseCurrencyId
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
		RETURN
	END

	-- Region: Get Amount by Product
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
									WHEN td.ProductId = 3 THEN (-td.WinLoss * p.Rate - td.AComm) * e.Rate
									WHEN td.ProductId <> 3 THEN (-td.WinLoss * p.Rate) * e.Rate
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
	-- End Region

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

	-- Region: Rebate
	INSERT INTO @InvoiceData(PartyId, ProductId, InvoiceAmount, AmountType, Rate, Remark)
	SELECT d.PartyId, d.ProductId, Rebate, @AmountTypeRebate, d.RebateRate, d.RebateRemark
	FROM #AmountToCompany d WHERE d.Rebate > 0
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
					WHEN id.InvoiceAmount > 0 OR id.ProductId = 3 OR id.ProductId = @CBProductId OR id.ProductId = @COProductId THEN id.InvoiceAmount
					ELSE 0
				END AS InvoiceAmount,
				id.AmountType,
				id.Rate,
				id.Remark
		FROM	@InvoiceData id
				LEFT JOIN dbo.Product3rd p WITH(NOLOCK) ON id.ProductId = p.Productid
	)

	INSERT INTO @FinalResult(ProductId,ProductCode,ProductName,InvoiceAmount,AmountType,Rate,Remark)
	(
		SELECT	-1,
				(	SELECT	f.ProductCode + ',' 
					FROM	@FinalResult f 
					WHERE f.AmountType = id.AmountType AND f.Rate=id.Rate FOR XML PATH('')) 
				AS ProductCode,
				(	SELECT	f.ProductName + ',' 
					FROM	@FinalResult f 
					WHERE f.AmountType = id.AmountType AND f.Rate=id.Rate FOR XML PATH('')) 
				AS ProductName,
				SUM(id.InvoiceAmount),
				id.AmountType,
				id.Rate,
				id.Remark
		FROM	@FinalResult id
		WHERE	id.AmountType > @AmountTypeSoftwareFee
		GROUP BY id.AmountType, id.Rate, id.Remark
	)	
	UPDATE	@FinalResult
	SET		ProductCode = LEFT(ProductCode, LEN(ProductCode) - 1),
			ProductName = LEFT(ProductName, LEN(ProductName) - 1)
	WHERE	ProductId = -1
	
	-- get AMF, AG and prepayment
	DECLARE @AG INT = 25, @DeductAG INT = 26
	SELECT SUM(ISNULL(Income,0) - ISNULL(Expense,0)) Amount, s.InvItemTypeId
	INTO #credit
	FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
	INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
	WHERE s.InvItemTypeId IN (3,5,7,21,22,23,24,@AG,@DeductAG)
		AND s.RefPartyId = @PartyId
		AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
		AND h.Environment = @Environment
	GROUP BY s.InvItemTypeId

	DECLARE @RemainingAmf MONEY = ISNULL((SELECT SUM(Amount) FROM #credit WHERE InvItemTypeId IN (3,5,7,21)),0)
	DECLARE @RemainingAG MONEY = ISNULL((SELECT SUM(Amount) FROM #credit WHERE InvItemTypeId IN (@AG, @DeductAG)),0)
	DECLARE @Prepayment MONEY = ISNULL((SELECT SUM(Amount) FROM #credit WHERE InvItemTypeId IN (22,23,24)),0)

	-- insert zero amount
	INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, InvoiceAmount, AmountType)
	SELECT pd.ProductID, pd.ProductPrefix, pd.ProductName, 0, @AmountTypeSoftwareFee
	FROM (SELECT DISTINCT pci.ProductID 
		FROM @PartyChargeInfo pci
		LEFT JOIN @FinalResult r ON pci.ProductID = r.ProductId
		WHERE r.ProductId IS NULL) p
	JOIN dbo.LA_f_Products3rd('') pd ON p.ProductID = pd.ProductID

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

		UPDATE @FinalResult SET DeductMonthlyFees = @AmfAmount, RemainingAmount = @RemainingAmf - @AmfAmount
		WHERE AmountType = @AmountTypeSoftwareFee AND ProductId = 0 -- SB
	END

	-- insert AG setup fees
	DECLARE @AGMonthlyFee MONEY
	SELECT @AGMonthlyFee = SUM(ISNULL(InvoiceAmount, 0)) FROM @FinalResult WHERE ProductId = 10 -- AG Casino
	IF (@AGMonthlyFee > 0 AND @RemainingAG > 0)
	BEGIN
		DECLARE @AGAmount MONEY = (CASE WHEN @RemainingAG < @AGMonthlyFee THEN @RemainingAG ELSE @AGMonthlyFee END)

		UPDATE @FinalResult SET DeductMonthlyFees = @AGAmount, RemainingAmount = @RemainingAG - @AGAmount
		WHERE AmountType = @AmountTypeSoftwareFee AND ProductId = 10 -- AG
	END

	DECLARE @TotalAmount MONEY = (
		SELECT SUM((CASE WHEN AmountType=@AmountTypeDiscount THEN -InvoiceAmount ELSE InvoiceAmount END) - ISNULL(DeductMonthlyFees,0))
		FROM @FinalResult
		WHERE ProductId != -1	-- not summarized row
			AND AmountType IN (@AmountTypeSoftwareFee, @AmountTypeDiscount)
	)

	IF @Prepayment>0
	BEGIN
		SET @TotalAmount = CASE WHEN @TotalAmount<0 THEN 0 ELSE @TotalAmount END
		DECLARE @RemainingPrepayment MONEY = @Prepayment - @TotalAmount
		INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, AmountType, InvoiceAmount, RemainingAmount)
		VALUES(0,'','',@DeductAgainstInvoice,
			CASE WHEN @RemainingPrepayment >=0 THEN -@TotalAmount ELSE -@Prepayment END,
			CASE WHEN @RemainingPrepayment >=0 THEN @RemainingPrepayment ELSE 0 END)
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
	WHERE f.ProductId != -1	-- not summarized row
	ORDER BY f.AmountType, f.ProductId

	SELECT @ErrCode = 0, @ErrMsg = ''

	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #TempDataCB
	DROP TABLE #AmountToCompany

END
GO