/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

--ALTER PROCEDURE [dbo].[LA_Inv_MultipleGenerationTemporaryInvoiceSel]
DECLARE	@PartyIds			VARCHAR(500),
	@FromDate			DATE,
	@ToDate				DATE,
	@Environment		VARCHAR(10),
	@ErrCode			INT				= 0,--		OUTPUT,
	@ErrMsg				NVARCHAR(1000)	= ''--	OUTPUT
--AS
SELECT @Environment='LOCAL',@PartyIds='14,364,15,74,24',@FromDate='2020-11-01 00:00:00',@ToDate='2020-11-30 00:00:00'
--SELECT @PartyIds = '14,15,24,74', @FromDate = '2020-11-01', @ToDate = '2020-11-30', @Environment = 'LOCAL'
/*	Header:
	Created: 2021.03.02 - Parsons
	Task : Support a function to export all invoices at once: Generate Multiple Temporary Invoice
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20210302@Parsons: Create new sp [#147006]
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @InvoiceTypeSoftwareFee INT = 1, @InvoiceTypeRebate INT = 3, @InvoiceTypeHostingFee INT = 8,
		@SportsBookProductId INT = 0, @BAProductId INT = 3, @CBProductId INT = 15, @COProductId INT = 25, @ExchangeProductId INT = 31, @PPProductId INT = 32,
		@PP_Contribution SMALLINT = 4297, @PP_JackpotPrize SMALLINT = 4298, @PPTournament SMALLINT = 4299, @PromotionPrize SMALLINT = 4300, @ArcadiaGamingBonus SMALLINT = 1906, @SBC_Contribution SMALLINT = 1698, @SBC_JackpotPrize SMALLINT = 1699,

		@DeductAgainstInvoice INT = 24,
		@DeductSabaPromotion INT = 29,
		@DeductPPPrizes INT = 30,
		@PP_Contribution_InvItemType INT = 31,
		@PP_JackpotPrize_InvItemType INT = 32

	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
	DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1

	DECLARE @ProductCodes VARCHAR(500) = 'SB,NG,VS,AGC,GD,KN,CS,BA,AB,CO,CB,VS2,PP,VB,FW,LT,BX,CC,SG,VRG,SAG,I4D,TG,SBC,SXG,PGS,JK,WM,VS3,GDG,BGG,MXG'

	-- Region: Get Party Settings
	DECLARE @PartySettings TABLE(IndexNumber INT, PartyID INT, PartyName VARCHAR(100), BillerId INT, BillerName VARCHAR(100), ProductCodes VARCHAR(100), BaseCurrencyId INT, BaseCurrencyName VARCHAR(10), InvoiceLanguage VARCHAR(50), InvoiceSymbol NVARCHAR(20), InvoiceNumber INT, InvTemplateName VARCHAR(50))

	INSERT INTO @PartySettings(IndexNumber, PartyID, PartyName, BaseCurrencyId, BaseCurrencyName, InvoiceLanguage)
	SELECT p.rank, p.val, op.PartyName, ISNULL(pd.BaseCurrencyId, 6), ISNULL(e.Code, 'EUR'), pd.InvoiceLanguage
	FROM strSplit(@PartyIds, ',') p
	LEFT JOIN OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = p.val
	LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON e.exchangeid = pd.BaseCurrencyId
	LEFT JOIN bodb_licensee.dbo.OAS_Party op WITH(NOLOCK) ON p.val = op.PartyID

	DECLARE @InvoiceSettings TABLE(PartyID INT, BillerId INT,BillerName VARCHAR(100),InvTypeId Smallint, ProductCodes VARCHAR(100), InvTemplateName VARCHAR(50))
	INSERT INTO @InvoiceSettings(PartyID,BillerId,BillerName, InvTypeId, InvTemplateName, ProductCodes)
	SELECT ivs.FromPartyId, ivs.ToPartyId AS BillerID, b.BillerName, InvTypeId, t.InvTemplateName, STUFF((SELECT ',' + CASE WHEN t2.ProductId = 0 THEN 'SB' ELSE ProductPrefix END
																	  FROM LA_InvoiceSetting t2
																	  LEFT JOIN dbo.Product3rd p WITH(NOLOCK) ON t2.ProductId = p.Productid
																	  WHERE ivs.InvTypeId = 1 AND t2.FromPartyId = ivs.FromPartyId AND t2.ToPartyId = ivs.ToPartyId AND t2.InvTypeId = ivs.InvTypeId
																	  FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, '') AS ProductCodes
	FROM LA_InvoiceSetting ivs WITH(NOLOCK)
	INNER JOIN strSplit(@PartyIds, ',') p on ivs.FromPartyId = p.val
	INNER JOIN OAS_Party op WITH(NOLOCK) ON ivs.ToPartyId = op.PartyID
	INNER JOIN DBCUST.bodb_licensee.dbo.LA_BillerInfo b WITH (NOLOCK) ON ivs.ToPartyId = b.PartyID	
	INNER JOIN dbo.LA_InvoiceTemplate t WITH(NOLOCK) ON ivs.InvTempId = t.InvTemplateId
	WHERE InvTypeId IN (1, 3, 6)
	AND ((p.val= 14 and ivs.ToPartyId = 265) OR (p.val= 364 and ivs.ToPartyId = 265) OR (p.val= 15 and ivs.ToPartyId = 362) OR (p.val= 24 and ivs.ToPartyId = 122) OR (p.val= 74 and ivs.ToPartyId = 116))-- Remove this later
	GROUP BY ivs.FromPartyId, ivs.ToPartyId, b.BillerName, InvTypeId, InvTemplateName

	--SELECT '@InvoiceSettings', * FROM @InvoiceSettings ORDER BY PartyID, BillerId -- PARS
	UPDATE  s
	SET BillerId = ivs.BillerId,
		BillerName = ivs.BillerName,
		ProductCodes = ivs.ProductCodes,
		s.InvTemplateName = ivs.InvTemplateName
	FROM @PartySettings s
	INNER JOIN @InvoiceSettings ivs ON s.PartyID = ivs.PartyID

	-- SELECT '@PartySettings', * FROM @PartySettings -- PARS
	-- End Region Get Party Settings

	DECLARE @FinalResult TABLE (PartyId INT,InvoiceHeaderId BIGINT, InvoiceSymbol NVARCHAR(20),InvoiceNumber INT,BillerId INT,LicensingFee MONEY, Discount MONEY,InvoiceType TINYINT, InvoicePath NVARCHAR(255))
	-- #Region: Get issued invoices
	INSERT INTO @FinalResult(PartyId, InvoiceHeaderId, InvoiceSymbol, InvoiceNumber, BillerId, LicensingFee, InvoiceType, InvoicePath)
	SELECT h.PartyId,h.InvoiceHeaderId,h.InvoiceSymbol,h.InvoiceNumber,h.BillerId,h.Amount,h.InvoiceType,h.InvoicePath
	FROM @PartySettings ps
	INNER JOIN LA_InvoiceHeader h WITH(NOLOCK) ON ps.PartyId = h.PartyId AND ps.BillerId = h.BillerId
	WHERE h.StatusId = 0 AND h.Environment = @Environment
		AND InvoiceType IN (@InvoiceTypeSoftwareFee, @InvoiceTypeRebate, @InvoiceTypeHostingFee)
		AND (h.FromDate = @FromDate AND h.ToDate = @ToDate)

	;WITH cte_DiscountAmount AS
	(
		SELECT r.PartyId, r.InvoiceType, r.InvoiceHeaderId, SUM(d.Expense) DiscountAmount
		FROM @FinalResult r
		INNER JOIN LA_InvoiceStatement d WITH(NOLOCK) ON r.InvoiceHeaderId = d.InvoiceHeaderId
		WHERE r.InvoiceType = @InvoiceTypeSoftwareFee AND d.InvItemTypeId = 4 -- DISCOUNT
		GROUP BY r.PartyId, r.InvoiceType, r.InvoiceHeaderId
	)
	UPDATE r
	SET r.Discount = d.DiscountAmount,
		LicensingFee -= d.DiscountAmount
	FROM @FinalResult r
	INNER JOIN cte_DiscountAmount d ON r.PartyId = d.PartyId AND r.InvoiceType = r.InvoiceType
	-- #End region: Get issued invoices

	-- Region #Exchange
	BEGIN
		CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeID INT, CurrencyCode	VARCHAR(10),Rate FLOAT, BaseCurrencyId INT)
		DECLARE @tempCurrencyName VARCHAR(10), @tempCurrencyId INT

		DECLARE @BaseCurrencyTable AS TABLE(CurrencyId INT, CurrencyName VARCHAR(10), IsCalculatedExchange BIT, IsCalculationAmountToCompany BIT)
		INSERT	INTO @BaseCurrencyTable(CurrencyId, CurrencyName)
		SELECT DISTINCT BaseCurrencyId, BaseCurrencyName
		FROM @PartySettings

		WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencyTable WHERE ISNULL(IsCalculatedExchange, 0) = 0)
		BEGIN
			SELECT TOP 1 @tempCurrencyId = CurrencyId, @tempCurrencyName = CurrencyName FROM @BaseCurrencyTable b WHERE ISNULL(IsCalculatedExchange, 0) = 0

			INSERT INTO #Exchange(ExchangeDate, ExchangeId, CurrencyCode, Rate, BaseCurrencyId)
			SELECT ExchangeDate, ExchangeId, Code, BaseCurrencyRate, @tempCurrencyId
			FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrencyName)

			UPDATE @BaseCurrencyTable SET IsCalculatedExchange = 1 WHERE CurrencyId = @tempCurrencyId 
		END
	END
	-- End region #Exchange

	-- Region: Get amount to company,discount,rebate(only for some supported products)
	BEGIN
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
		DECLARE @Temp_PartyIds VARCHAR(500)
		WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencyTable WHERE ISNULL(IsCalculationAmountToCompany, 0) = 0)
		BEGIN
			SELECT TOP 1 @tempCurrencyId = CurrencyId, @tempCurrencyName = CurrencyName FROM @BaseCurrencyTable b WHERE ISNULL(IsCalculationAmountToCompany, 0) = 0

			SELECT @Temp_PartyIds = COALESCE(@Temp_PartyIds + ', ', '') + CAST(PartyID AS VARCHAR(20))
			FROM @PartySettings
			WHERE BaseCurrencyId = @tempCurrencyId

			INSERT INTO #AmountToCompany(PartyId,ProductId,Winloss,Fee,NegativeFee,Minfee,IsChargedByMinFee,Discount,DiscountRate,DiscountRemark,Rebate,RebateRate,RebateRemark)
			EXEC dbo.LA_AmountToCompanySel @FromDate,@ToDate,@Temp_PartyIds,@ProductCodes,@tempCurrencyName

			UPDATE @BaseCurrencyTable SET IsCalculationAmountToCompany = 1 WHERE CurrencyId = @tempCurrencyId 
			SET @Temp_PartyIds = ''
		END
	END
	-- End Region: Get amount to company,discount,rebate(only for some supported products)

	-- Region: Party charge info
	DECLARE @PartyChargeInfo AS TABLE (ChargeId	INT, PartyId INT, LicenseeId INT, ProductID	INT, Rate DECIMAL(7,5), FromDate SMALLDATETIME, ToDate SMALLDATETIME, Bettype INT)
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Bettype, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, ProductID, Bettype, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId NOT IN (1, 15) --exclude RB, CB
	)
	-- End region: Party charge info

	-- Region: Get Amount by Product (The remaining products)
	CREATE	TABLE #TempData (PartyId INT, ProductId TINYINT, WinLoss MONEY,AComm MONEY, PComm MONEY, AmountToCompany MONEY, ExtraAmount MONEY)

	;WITH cte_DataSource AS
	(
	  SELECT	p.PartyId, p.ProductId, b.rptDate,b.CurrencyID,
				SUM(b.MemberWL) AS WinLoss,
				SUM(ISNULL(b.CommissionA, 0)) AComm,
				SUM(ISNULL(b.CommissionP, 0)) PComm,
				SUM(-b.MemberWL * ISNULL(cr.Rate, p.Rate) - 
					(CASE  WHEN b.ProductId = @BAProductId THEN ISNULL(b.CommissionA, 0)
						   WHEN b.ProductID = @ExchangeProductId THEN ISNULL(b.CommissionA, 0) + ISNULL(b.CommissionP, 0)
					       ELSE 0
				     END)) AS AmountToCompany,
				0 AS ExtraAmount
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
				LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeId = cr.ChargeID AND b.CurrencyId = cr.CurrencyID
				LEFT JOIN bodb_licensee.dbo.LA_f_ExcludedBettypeListSel('','') eb ON b.Bettype = eb.BettypeID
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND eb.BettypeID IS NULL
				AND	ISNULL(b.TicketType, 0) <> 2 -- Free_Bets_TicketType
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund 
		GROUP BY p.PartyId, p.ProductId, b.rptDate,b.CurrencyID

		UNION ALL

		SELECT	p.PartyId, p.ProductId, b.rptDate,b.CurrencyID,
				0 WinLoss,
				0 AComm,
				0 PComm,
				0 AmountToCompany,
				SUM(CASE WHEN b.Bettype IN (@PP_Contribution, @SBC_Contribution) THEN ISNULL(-b.GrossWL, 0)
						 WHEN b.Bettype IN (@PPTournament,@PromotionPrize,@PP_JackpotPrize,@ArcadiaGamingBonus,@SBC_JackpotPrize) OR ISNULL(b.TicketType, 0) = 2 THEN ISNULL(-b.MemberWL, 0)
						 ELSE 0
					END) AS ExtraAmount
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
				LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeId = cr.ChargeID AND b.CurrencyId = cr.CurrencyID
				LEFT JOIN bodb_licensee.dbo.LA_f_ExcludedBettypeListSel('','') eb ON b.Bettype = eb.BettypeID
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND (ISNULL(b.TicketType, 0) = 2 OR eb.BettypeID IS NOT NULL)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund 
		GROUP BY p.PartyId, p.ProductId, b.rptDate, b.CurrencyID
	)

	INSERT INTO #TempData (PartyId,ProductId,WinLoss,AComm,PComm,AmountToCompany,ExtraAmount)
	(
		SELECT	b.PartyId, b.ProductId,
				SUM(WinLoss * e.Rate)		AS WinLoss,
				SUM(b.AComm * e.Rate)		AS AComm,
				SUM(b.PComm * e.Rate)		AS PComm,
				SUM(AmountToCompany * e.Rate)	AS AmountToCompany,
				SUM(ExtraAmount * e.Rate)		AS ExtraAmount
		FROM	cte_DataSource b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		GROUP BY b.PartyId, b.ProductId
	)
	-- insert zero winloss for case: product don't have any ticket
	INSERT INTO #TempData (PartyId,ProductId,WinLoss,AComm,PComm,AmountToCompany)
	SELECT PartyId,ProductID,0,0,0,0
	FROM @PartyChargeInfo
	-- End region: Get Amount by Product (The remaining products)

	---- Get ChargeInfo for CB
	--DECLARE @CommChargeType INT = 6
	--DECLARE @CashInShareChargeType INT = 7

	--IF(CHARINDEX('CB', @ProductCodes) > 0 AND EXISTS(SELECT TOP 1 1 FROM bodb02.dbo.strSplit(@ProductCodes, ',') WHERE val = 'CB'))
	--BEGIN
	--	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, TypeId, FromDate, ToDate)
	--	SELECT	ci.FromParty,
	--			CASE WHEN ISNULL(pd.IsDeposit, 0) = 1 THEN p.OldRefID ELSE lb.LabelID END AS LicenseeId,
	--			@CBProductId,
	--			ci.Rate,
	--			ci.ChargeType,
	--			CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
	--			CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
	--	FROM dbo.OAS_Party p WITH(NOLOCK)
	--		INNER JOIN dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
	--		LEFT JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
	--		LEFT JOIN dbo.Labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
	--	WHERE FromParty = @PartyId
	--		AND ProductID = @CBProductId
	--		AND ChargeType IN (@CommChargeType,@CashInShareChargeType)
	--		AND @FromDate <= ci.ToDate
	--		AND ci.FromDate <= @ToDate
	--END
	---- End Get ChargeInfo for CB

	-- Sum products
	BEGIN
		DECLARE @SumByProducts TABLE(PartyId INT, AComm MONEY, PComm MONEY,AmountToCompany MONEY, ProductId INT, Discount MONEY, Rebate MONEY, ExtraAmount MONEY)
		
		-- sum by product
		INSERT INTO @SumByProducts (PartyId,ProductId,AComm,PComm,AmountToCompany,ExtraAmount)
		SELECT	t.PartyId,t.ProductId
				,SUM(AComm)
				,SUM(PComm)
				,SUM(AmountToCompany)
				,SUM(ExtraAmount)
		FROM #TempData t
		INNER JOIN @PartySettings ps ON t.PartyId = ps.PartyID
		INNER JOIN LA_InvoiceSetting ivs WITH(NOLOCK) ON ps.PartyID = ivs.FromPartyId AND ps.BillerId = ivs.ToPartyId 
		WHERE t.ProductId = ivs.ProductId
		GROUP BY t.PartyId, t.ProductId
		
		-- apply minfee
		UPDATE s 
		SET AmountToCompany = m.Fee + ISNULL(ExtraAmount, 0),
			Discount = m.Discount,
			Rebate = m.Rebate
		FROM @SumByProducts s
		INNER JOIN #AmountToCompany m ON m.PartyId = s.PartyId AND m.ProductId = s.ProductId

	END

	-- Region: Licensing Fee
	INSERT INTO @FinalResult(PartyId, InvoiceType, LicensingFee)
	SELECT d.PartyId, @InvoiceTypeSoftwareFee, SUM(CASE WHEN AmountToCompany > 0 OR ProductId IN (@BAProductId, @CBProductId, @COProductId, @PPProductId, @ExchangeProductId) THEN AmountToCompany ELSE 0 END) AS Amount
	FROM @SumByProducts d
	INNER JOIN @InvoiceSettings ivs ON d.PartyId = ivs.PartyID
	LEFT JOIN @FinalResult r ON d.PartyId = r.PartyId AND r.InvoiceType = @InvoiceTypeSoftwareFee
	WHERE r.PartyId IS NULL AND ivs.InvTypeId = @InvoiceTypeSoftwareFee --AND ivs.ProductCodes 
	GROUP BY d.PartyId
	-- End Region: Licensing Fee

	-- Region: Discount
	;WITH cte_DiscountAmount AS
	(
		SELECT r.PartyId, r.InvoiceType, r.InvoiceHeaderId, SUM(d.Discount) DiscountAmount
		FROM @FinalResult r
		INNER JOIN @SumByProducts d ON r.PartyId = d.PartyId
		WHERE r.InvoiceType = @InvoiceTypeSoftwareFee AND ISNULL(r.InvoiceHeaderId, 0) = 0  AND d.Discount > 0
		GROUP BY r.PartyId, r.InvoiceType, r.InvoiceHeaderId
	)
	UPDATE r
	SET r.Discount = d.DiscountAmount
	FROM @FinalResult r
	INNER JOIN cte_DiscountAmount d ON r.PartyId = d.PartyId AND r.InvoiceType = r.InvoiceType
	-- End Region: Discount

	-- Region: Rebate
	INSERT INTO @FinalResult(PartyId, InvoiceType, LicensingFee)
	SELECT d.PartyId,  @InvoiceTypeRebate, -SUM(d.Rebate)
	FROM @SumByProducts d
	INNER JOIN @InvoiceSettings ivs ON d.PartyId = ivs.PartyID
	LEFT JOIN @FinalResult r ON d.PartyId = r.PartyId AND r.InvoiceType = @InvoiceTypeRebate
	WHERE ivs.InvTypeId = @InvoiceTypeRebate AND r.PartyId IS NULL AND d.Rebate > 0 
	GROUp BY d.PartyId
	-- End Region: Rebate

		--select * from #TempData ORDER BY PartyId, ProductId -- pars 
		--select * from #AmountToCompany ORDER BY PartyId, ProductId -- pars
		--select * from @SumByProducts ORDER BY PartyId, ProductId -- pars
		--select '@FinalResult', * from @FinalResult ORDER BY PartyId-- pars
	---- Region: Select data

	--Region: Get AMF, AG and prepayment
	BEGIN
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
	
		INSERT INTO @tblInvoiceAmounts (Income, Expense, InvItemTypeId)
		SELECT s.Income, s.Expense, s.InvItemTypeId
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
			INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
			INNER JOIN @PartyChargeInfo p ON h.PartyId = p.PartyId
		WHERE ISNULL(h.StatusId, 0) = 0 AND h.Environment = @Environment
	
		SELECT SUM(ISNULL(s.Income,0) - ISNULL(s.Expense,0)) AS Amount, s.InvItemTypeId, invT.[Key] AS InvItemTypeKey 
		INTO #credit
		FROM @tblInvoiceAmounts s
			INNER JOIN @InvoiceItemTypes invT ON s.InvItemTypeId = invT.Value
		GROUP BY s.InvItemTypeId, invT.[Key]

		DECLARE @RemainingAmf MONEY = ISNULL((SELECT SUM(Amount) FROM #credit WHERE InvItemTypeKey = @AdvanceMinFee), 0)
		DECLARE @RemainingAG MONEY = ISNULL((SELECT SUM(Amount) FROM #credit WHERE InvItemTypeKey = @AGPrepayment), 0)
		DECLARE @Prepayment MONEY = ISNULL((SELECT SUM(Amount) FROM #credit WHERE InvItemTypeKey = @PrepaymentKey), 0)
	
		-- insert amf
		IF @RemainingAmf > 0
		BEGIN
			print 'cte_ProgratedMinfee'
			/*; WITH cte_ProgratedMinfee AS
			(
				SELECT PartyId, MinFee 
				FROM #AmountToCompany WHERE ProductId = @SportsBookProductId
			)
			/*, cte_SBAfterDiscount AS 
			(
				SELECT PartyId,  SUM(CASE WHEN InvoiceType = @InvoiceTypeSoftwareFee THEN InvoiceAmount ELSE -InvoiceAmount END) AS Amount
				FROM @SumByProducts
				WHERE ProductId = @SportsBookProductId AND InvoiceType IN (@InvoiceTypeSoftwareFee, @InvoiceTypeDiscount)
				GROUP BY PartyId
			)*/
			SELECT 'cte_ProgratedMinfee', * FROM cte_ProgratedMinfee*/
			/*
			DECLARE @AmfAmount MONEY
			SELECT @AmfAmount = CASE WHEN MIN(Amount) < 0 THEN 0 ELSE MIN(Amount) END
			FROM (VALUES(@SBAfterDiscount), (@ProgratedMinfee),(@RemainingAmf))v(Amount)

			--INSERT INTO @FinalResult() 
			SELECT @AmfAmount, RemainingAmount = @RemainingAmf
			WHERE InvoiceType = @InvoiceTypeSoftwareFee AND ProductId = @SportsBookProductId*/
		END

		-- insert AG setup fees
		--DECLARE @AGMonthlyFee MONEY
		--SELECT @AGMonthlyFee = SUM(CASE WHEN InvoiceType = @InvoiceTypeSoftwareFee THEN InvoiceAmount ELSE -InvoiceAmount END)
		--FROM @FinalResult 
		--WHERE ProductId = 10 AND InvoiceType IN (@InvoiceTypeSoftwareFee, @InvoiceTypeDiscount)
		--IF (@AGMonthlyFee > 0 AND @RemainingAG > 0)
		--BEGIN
		--	DECLARE @AGAmount MONEY = (CASE WHEN @RemainingAG < @AGMonthlyFee THEN @RemainingAG ELSE @AGMonthlyFee END)

		--	UPDATE @FinalResult SET DeductMonthlyFees = @AGAmount, RemainingAmount = @RemainingAG
		--	WHERE InvoiceType = @InvoiceTypeSoftwareFee AND ProductId = 10 -- AG
		--END

		--IF @Prepayment > 0
		--BEGIN
		--	INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, InvoiceType, InvoiceAmount, RemainingAmount)
		--	VALUES(0,'','',@DeductAgainstInvoice,0,@Prepayment)
		--END
	END
	--End Region: Get AMF, AG and prepayment

	--#Region InvoiceNo
	BEGIN
		;WITH cte_PartyInvoiceNo AS
		(
			SELECT ps.PartyID, ps.PartyName, ps.BillerId, ps.BillerName, iv.InvoiceSymbol, iv.InvoiceNumber
			FROM @PartySettings ps
			CROSS APPLY
			(
				SELECT TOP 1 iv.InvoiceSymbol, MAX(iv.InvoiceNumber) InvoiceNumber
				FROM LA_InvoiceHeader iv WITH(NOLOCK)
				WHERE iv.StatusId = 0 AND iv.Environment = @Environment
						AND InvoiceType IN (@InvoiceTypeSoftwareFee, @InvoiceTypeRebate, @InvoiceTypeHostingFee)
						AND iv.BillerId = ps.BillerID
				GROUP BY iv.InvoiceSymbol, CreatedDateTime--, iv.PartyId, iv.BillerId, CreatedDateTime
				ORDER BY CreatedDateTime DESC
			) iv
		)
		UPDATE ps
		SET ps.InvoiceSymbol = cte.InvoiceSymbol,
			ps.InvoiceNumber = cte.InvoiceNumber
		FROM @PartySettings ps
		INNER JOIN cte_PartyInvoiceNo cte ON ps.PartyID = cte.PartyID
	END
	--#EndRegion InvoiceNo
	SELECT * FROM @PartySettings
	/*
		1. Theo BillerID
		2. Theo IndexOrder
		3. Skip IssuedInvoice (Có InvoiceHeaderId > 0)
	*/
	SELECT	r.PartyId, ps.PartyName, r.InvoiceType AS ItemType, ps.BillerId, ps.BillerName, r.InvoiceHeaderId, r.InvoiceSymbol, r.InvoiceNumber, 
			r.InvoicePath, ps.BaseCurrencyId, ps.BaseCurrencyName, ps.ProductCodes, ps.InvoiceLanguage, ps.InvTemplateName,
			SUM(CASE WHEN r.InvoiceType = @InvoiceTypeRebate THEN 0 ELSE r.LicensingFee END) LicensingFee,
			SUM(ISNULL(r.Discount, 0))		Discount,
			SUM(CASE WHEN r.InvoiceType = @InvoiceTypeRebate THEN r.LicensingFee ELSE 0 END) Rebate
			--r.DeductMonthlyFees
	FROM @FinalResult r
		 INNER JOIN @PartySettings ps ON r.PartyId = ps.PartyID
	GROUP BY ps.IndexNumber, r.PartyId, ps.PartyName, r.InvoiceType, ps.BillerId, ps.BillerName, r.InvoiceHeaderId, r.InvoiceSymbol, r.InvoiceNumber, 
			r.InvoicePath, ps.BaseCurrencyId, ps.BaseCurrencyName, ps.ProductCodes, ps.InvoiceLanguage, ps.InvTemplateName
	ORDER BY ps.IndexNumber
	
	SELECT @ErrCode = 0, @ErrMsg = ''

	/*Note
		1. Bo sung CO, CB, v.vv
		2. Symbol thi chi can check theo Biller (SP tham khao LA_Inv_InvoiceBillerInfoGet)
			- Step 1: Get latest InvoiceSymbol & InvoiceNumber
			- Step 2: Update dua theo order number
		3. Check setting ben Payer de bik gen invoice type nao (Limit Licensing Fee (Software Fee --> Product), Rebate & Hosting Fee) -> DONE
		4. Hosting Fee

		FAQ:
		1. Get issued invoices
			- Co bi change BillerId khong? if yes, khong can filter tren billerId
			- Date chinh xac hay giao nhau?
		2. 
	*/
	DROP TABLE #Exchange
	DROP TABLE #TempData
	--DROP TABLE #TempDataCB
	DROP TABLE #AmountToCompany
	DROP TABLE #credit

END
GO