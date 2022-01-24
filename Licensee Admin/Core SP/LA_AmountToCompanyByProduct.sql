/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_AmountToCompanyByProduct]
	@PartyIds				VARCHAR(MAX)
	,@ProductCodes			VARCHAR(MAX)
	,@Currencies			VARCHAR(MAX) = ''
	,@FromDate				DATETIME
	,@ToDate				DATETIME
	,@IsConvertExRate		BIT = 1
	,@LicensingFeeTypeIds	VARCHAR(1000) = '0'
	,@BaseCurrencyName		VARCHAR(10) = 'EUR'
	,@Environment			VARCHAR(50) = 'LOCAL'
AS

/*
	Created: 20210909@Percy
	DB: DBLIC-bodb_Licensee
	Task: Core SP - AmountToCompany By Product

	Revisions:
		- 20210909@Percy: Initialize SP [RedmineID: #157652]
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20211101@Percy: Calculate discount base on Licensee Win Loss [RedmineID: #162158]
		- 20211110@Danny: Add @LicensingFeeTypeIds = 8 (betcount)  [#159296]
		- 20211212@Percy: Set OddsSpread = 0 if negative value [RedmineID: #165849]
		- 20220105@Percy: Don't check negative AMF amount [RedmineID: #167039]


	Param's Explanation:
		. @Currencies: '' = all or '2,3,4,...'
		. @IsConvertExRate: 0 = keep data original
		. @LicensingFeeTypeIds
			0 = Normal Licensing Fee
			1 = Contribution
			2 = Jackpot Prize
			3 = Prize
			4 = Bonus
			5 = Lucky Draw
			6 = Free Bets
			7 = Contribution Discount
			8 = Betcount
			9 = OddsSpead Adjustment

*/

BEGIN
	SET NOCOUNT ON

	IF @ToDate > CONVERT(DATE, GETDATE())
		SET @ToDate = CONVERT(DATE, GETDATE())

	-- Get Product List
	CREATE TABLE #Products (ProductId INT, ProductName VARCHAR(50), ProductCode VARCHAR(10), IsSelected BIT)
	INSERT INTO #Products (ProductId, ProductName, ProductCode, IsSelected)
	SELECT ProductId, ProductName, ProductPrefix, 1
	FROM dbo.LA_f_Products3rd(@ProductCodes)
	WHERE ProductId NOT IN (16, 37)

	IF EXISTS (SELECT 1 FROM #Products WHERE ProductId = 0)
		INSERT INTO #Products (ProductId, ProductName, ProductCode, IsSelected)
		VALUES (37, 'Saba Promotion', 'SPR', 1)

	-- Get Party List
	CREATE TABLE #PartyList (PartyId INT, LicenseeId INT, BaseCurrencyId INT, IsDeposit BIT, IsSelected BIT)
	INSERT INTO #PartyList (PartyId, IsSelected)
	SELECT DISTINCT val, 1 FROM dbo.strSplit (@PartyIds, ',')

	-- Insert parties with same min fee group
	INSERT INTO #PartyList (PartyId, IsSelected)
	SELECT t.PartyId, 0
	FROM (
		SELECT DISTINCT m.PartyId
		FROM dbo.LA_GroupMinFeeAssignment m WITH (NOLOCK)
		WHERE EXISTS (
			SELECT 1
			FROM #PartyList pl
				INNER JOIN dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK) ON pl.PartyId = a.PartyId
				INNER JOIN dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
			WHERE h.FromDate <= @ToDate AND h.ToDate >= @FromDate
				AND a.GroupMinFeeId = m.GroupMinFeeId
		)
	) t
		LEFT JOIN #PartyList pl ON t.PartyId = pl.PartyId
	WHERE pl.PartyId IS NULL

	-- Insert parties/products with same discount group
	DECLARE @DiscountGroup TABLE (PartyId INT, ProductId INT)
	INSERT INTO @DiscountGroup (PartyId, ProductId)
	SELECT DISTINCT a.PartyId, p.ProductId
	FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON a.DiscountGroupId = p.DiscountGroupId
	WHERE EXISTS (
		SELECT 1
		FROM #PartyList pl
			INNER JOIN dbo.LA_DiscountGroupAssignment da WITH (NOLOCK) ON pl.PartyId = da.PartyId
			INNER JOIN dbo.LA_DiscountGroupHeader dh WITH (NOLOCK) ON da.DiscountGroupId = dh.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct dp WITH (NOLOCK) ON da.DiscountGroupId = dp.DiscountGroupId
			INNER JOIN #Products pd ON dp.ProductId = pd.ProductId
		WHERE dh.FromDate <= @ToDate AND dh.ToDate >= @FromDate
			AND dh.DiscountGroupType <> 2 -- 2 = Rebate
			AND a.DiscountGroupId = da.DiscountGroupId
	)

	INSERT INTO #PartyList (PartyId, IsSelected)
	SELECT t.PartyId, 0
	FROM (SELECT DISTINCT PartyId FROM @DiscountGroup) t
		LEFT JOIN #PartyList pl ON t.PartyId = pl.PartyId
	WHERE pl.PartyId IS NULL

	UPDATE pl
	SET pl.LicenseeId = p.OldRefId, pl.IsDeposit = pd.IsDeposit, pl.BaseCurrencyId = ISNULL(bc.BaseCurrencyId, 6)
	FROM #PartyList pl
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON pl.PartyId = p.PartyId AND p.PartyType = 1
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pl.PartyId = pd.PartyId
		OUTER APPLY (
			SELECT TOP 1 bc.BaseCurrencyId
			FROM dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK)
			WHERE bc.PartyId = pl.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
			ORDER BY bc.ToDate DESC
		) bc

	-- Credit Licensee
	INSERT INTO #PartyList (PartyId, LicenseeId, BaseCurrencyId, IsDeposit, IsSelected)
	SELECT pl.PartyId, l.LabelId, pl.BaseCurrencyId, pl.IsDeposit, pl.IsSelected
	FROM #PartyList pl
		INNER JOIN dbo.Labels l WITH (NOLOCK) ON pl.LicenseeId = l.LicenseeId
	WHERE pl.IsDeposit = 0

	INSERT INTO #Products (ProductId, ProductCode, IsSelected)
	SELECT t.ProductId, lp.ProductPrefix, 0
	FROM (SELECT DISTINCT ProductId FROM @DiscountGroup) t
		INNER JOIN dbo.LA_f_Products3rd('') lp ON t.ProductId = lp.ProductId
		LEFT JOIN #Products p ON t.ProductId = p.ProductId
	WHERE p.ProductId IS NULL

	SET @PartyIds = NULL
	;WITH CTE_PartyId AS (SELECT DISTINCT PartyId FROM #PartyList)
	SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM CTE_PartyId

	SET @ProductCodes = NULL
	SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM #Products

	-- Get Charge Rate
	DECLARE @PartyChargeInfo TABLE (ChargeId INT, PartyId INT, LicenseeId INT, ProductId INT, BettypeRef INT, Rate FLOAT, FromDate DATE, ToDate DATE, ChargeType TINYINT)
	INSERT INTO @PartyChargeInfo (ChargeId, PartyId, LicenseeId, ProductId, FromDate, ToDate, ChargeType, BettypeRef, Rate)
	SELECT ChargeId, PartyId, LicenseeId, ProductId, FromDate, ToDate, ChargeType
		,CASE
			WHEN ProductId = 11 AND ChargeType = 12 THEN 1706 -- GD Tip
			WHEN ProductId = 39 AND ChargeType = 12 THEN 3007 -- SA Tip
			ELSE -1 END
		,CASE WHEN IsDeposit = 1 OR ProductId = 0 THEN DI_Rate ELSE 0 END -- Credit Rate/Fee = 0 (Exclude SB)
	FROM dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, @ProductCodes)

	-- For CB Charge Rate
	DECLARE @MinCBDate DATE, @MaxCBDate DATE
	SELECT  @MinCBDate = MIN(FromDate), @MaxCBDate = MAX(ToDate) FROM @PartyChargeInfo WHERE ProductId = 15

	DECLARE @CBChargeRate TABLE (PartyId INT, LicenseeId INT, rptDate DATE, CommShareRate FLOAT, CashInShareRate FLOAT)
	;WITH CTE_rptDate AS (
		SELECT @MinCBDate AS rptDate
		UNION ALL SELECT DATEADD(DAY, 1, rptDate) FROM CTE_rptDate WHERE rptDate < @MaxCBDate
	)
	INSERT INTO @CBChargeRate (PartyId, LicenseeId, rptDate, CommShareRate, CashInShareRate)
	SELECT DISTINCT ISNULL(cr.PartyId, sr.PartyId), ISNULL(cr.LicenseeId, sr.LicenseeId), r.rptDate, ISNULL(cr.Rate, 0), ISNULL(sr.Rate, 0)
	FROM CTE_rptDate r
		LEFT JOIN @PartyChargeInfo cr ON r.rptDate BETWEEN cr.FromDate AND cr.ToDate AND cr.ProductId = 15 AND cr.ChargeType = 6
		LEFT JOIN @PartyChargeInfo sr ON r.rptDate BETWEEN sr.FromDate AND sr.ToDate AND sr.ProductId = 15 AND sr.ChargeType = 7
	WHERE cr.ProductId IS NOT NULL OR sr.ProductId IS NOT NULL
	OPTION (MAXRECURSION 0)

	DELETE @PartyChargeInfo WHERE ProductId = 15

	-- Get Exchange Rate
	CREATE TABLE #Exchange (BaseCurrencyId INT, ExchangeId INT, Rate FLOAT)
	INSERT INTO #Exchange (BaseCurrencyId, ExchangeID, Rate)
	SELECT 0, ExchangeId, CASE WHEN @IsConvertExRate = 1 THEN BaseCurrencyRate ELSE 1 END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@ToDate, @ToDate, @BaseCurrencyName)

	;WITH CTE_Exchange AS (
		SELECT DISTINCT BaseCurrencyId FROM #PartyList
	)
	INSERT INTO #Exchange (BaseCurrencyId, ExchangeID, Rate)
	SELECT c.BaseCurrencyId, f.ExchangeId, f.BaseCurrencyRate
	FROM CTE_Exchange c
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON c.BaseCurrencyId = e.ExchangeId
		CROSS APPLY bodb02.dbo.LA_f_ExchangeDailySel(@ToDate, @ToDate, e.Code) f

	-- Get Win Loss Data
	CREATE TABLE #TempData (
		rptDate DATE, LicenseeId INT, ProductId INT, BettypeRef INT DEFAULT(-1), CurrencyId INT
		,MemberWL MONEY DEFAULT(0), MemberComm MONEY DEFAULT(0), AgentWL MONEY DEFAULT(0), AgentComm MONEY DEFAULT(0)
		,Tips MONEY DEFAULT(0), Contribution MONEY DEFAULT(0), JackpotPrize MONEY DEFAULT(0), Prize MONEY DEFAULT(0)
		,LuckyDraw MONEY DEFAULT(0), Bonus MONEY DEFAULT(0), OddsSpread MONEY DEFAULT(0), FreeBets MONEY DEFAULT(0)
		,PayOut MONEY DEFAULT(0), CommShare MONEY DEFAULT(0), CashInShare MONEY DEFAULT(0), Betcount INT DEFAULT(0)
	)

	-- CO
	DECLARE @FDate SMALLDATETIME = @FromDate, @TDate SMALLDATETIME = @ToDate
	INSERT INTO #TempData (rptDate, LicenseeId, ProductId, CurrencyId, MemberWL, PayOut, Betcount)
	SELECT CONVERT(DATE, r.WinlostDate) AS rptDate, r.SiteId, 25, r.Currency
		,SUM(r.BuyBackAmt) AS MemberWL
		,SUM(r.TicketPayout - r.BuyBackAmt - r.BABuyBackAmt) AS Payout
		,SUM(r.NumOfCashoutTrans) AS Betcount
	FROM bodb_LicenseeReport.dbo.rptLicCashoutSummary r WITH (NOLOCK)
	WHERE r.WinlostDate BETWEEN @FDate AND @TDate								
		AND r.Currency <> 20
		AND r.RoleId = 1 -- Member
	GROUP BY CONVERT(DATE, r.WinlostDate), r.SiteId, r.Currency

	DECLARE @Products TABLE (GroupProductId INT, ProductId INT, FromDate DATE, ToDate DATE)
	INSERT INTO @Products (GroupProductId, ProductId, FromDate, ToDate)
	SELECT GroupProductId, ProductId, FromDate, ToDate FROM dbo.LA_f_GroupProduct(@ProductCodes,@FromDate,@ToDate) 

	;WITH CTE_tempData AS (
		SELECT rptDate, SiteId, ProductId, CurrencyId, Bettype, CASE WHEN ISNULL(TicketType, 0) = 2 THEN 2 ELSE 0 END AS TicketType
			,SUM(ISNULL(MemberWL, 0)) AS MemberWL
			,SUM(ISNULL(CommissionP, 0)) AS CommissionP
			,SUM(ISNULL(GrossWL, 0)) AS GrossWL
			,SUM(ISNULL(CommissionA, 0)) AS CommissionA
			,SUM(CASE WHEN ProductId = 15 THEN ISNULL(Turnover, 0) - ISNULL(WinPrizeAmount, 0) - ISNULL(CashOutAmount, 0) ELSE 0 END) AS PayOut
			,SUM(CASE WHEN ProductId = 15 THEN CASE WHEN ISNULL(TicketType, 0) = 0 THEN ISNULL(Turnover, 0) ELSE ISNULL(ExtraAmount, 0) END ELSE 0 END) AS CommShare
			,SUM(CASE WHEN ProductId = 15 OR Bettype = 901 THEN ISNULL(BuyBackAmount, 0) ELSE 0 END) AS CashInShare
			,SUM(ISNULL(BetCount,0)) AS BetCount
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
		WHERE rptDate BETWEEN @FromDate AND @ToDate
			AND StatusId NOT IN (-1, 101, 102, 103)
			AND CustomerCategory NOT IN (27, 28)
			AND CurrencyId <> 20
			AND ProductId <> 25 -- CO
		GROUP BY rptDate, SiteId, ProductId, CurrencyId, Bettype, CASE WHEN ISNULL(TicketType, 0) = 2 THEN 2 ELSE 0 END
		UNION SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL -- sum first
	)
	INSERT INTO #TempData (rptDate, LicenseeId, ProductId, CurrencyId, BettypeRef, MemberWL, MemberComm, AgentWL, AgentComm
		,Tips, Contribution, JackpotPrize, Prize, LuckyDraw, Bonus, OddsSpread, FreeBets, PayOut, CommShare, CashInShare, Betcount)
	SELECT r.rptDate, r.SiteId, g.GroupProductId, r.CurrencyId
		,CASE WHEN r.Bettype IN (901, 1706, 3007, 17005) THEN r.Bettype ELSE -1 END
		,SUM(CASE WHEN r.TicketType = 2 OR b.Bettype IS NOT NULL THEN 0 ELSE r.MemberWL END) AS MemberWL
		,SUM(r.CommissionP) AS MemberComm
		,SUM(r.GrossWL) AS AgentWL
		,SUM(r.CommissionA) AS AgentComm
		,SUM(CASE WHEN b.TypeId = 1 THEN r.MemberWL ELSE 0 END) AS Tips
		,SUM(CASE WHEN b.TypeId = 2 THEN -r.GrossWL ELSE 0 END) AS Contribution
		,SUM(CASE WHEN b.TypeId = 3 THEN r.MemberWL ELSE 0 END) AS JackpotPrize
		,SUM(CASE WHEN b.TypeId = 4 THEN r.MemberWL ELSE 0 END) AS Prize
		,SUM(CASE WHEN b.TypeId = 5 THEN r.MemberWL ELSE 0 END) AS LuckyDraw
		,SUM(CASE WHEN b.TypeId = 6 THEN r.MemberWL ELSE 0 END) AS Bonus
		,SUM(CASE WHEN b.TypeId = 7 THEN -r.GrossWL ELSE 0 END) AS OddsSpread
		,SUM(CASE WHEN r.TicketType = 2 THEN r.MemberWL ELSE 0 END) AS FreeBets
		,SUM(r.PayOut) AS PayOut
		,SUM(r.CommShare) AS CommShare
		,SUM(r.CashInShare) AS CashInShare
		,SUM(r.BetCount) AS BetCount
	FROM CTE_tempData r
		INNER JOIN @Products g ON r.ProductId = g.ProductId AND r.rptDate BETWEEN g.FromDate AND g.ToDate
		LEFT JOIN dbo.LA_f_GroupBettype() b ON r.Bettype = b.Bettype
	GROUP BY r.rptDate, r.SiteId, g.GroupProductId, r.CurrencyId
		,CASE WHEN r.Bettype IN (901, 1706, 3007, 17005) THEN r.Bettype ELSE -1 END

	CREATE TABLE #tmpResult (rptDate DATE, PartyId INT, ProductId INT, CurrencyId INT
		,GrossLicenseeAmount MONEY, LicenseeWL MONEY, LicenseeAmount MONEY, ExtraAmount MONEY DEFAULT(0), OddsSpread MONEY
		,Contribution MONEY, JackpotPrize MONEY, Prize MONEY, Bonus MONEY, LuckyDraw MONEY, FreeBets MONEY
		,ContributionDiscount MONEY, BasedLicenseeWL MONEY, BasedLicenseeAmount MONEY, BasedOddsSpread MONEY, BetCount INT) -- Based Amount: for get exactly min fee, discount
	INSERT INTO #tmpResult (rptDate, PartyId, ProductId, CurrencyId, GrossLicenseeAmount, LicenseeWL, LicenseeAmount, ExtraAmount
		,OddsSpread, Contribution, JackpotPrize, Prize, Bonus, LuckyDraw, FreeBets, ContributionDiscount, BasedLicenseeWL, BasedLicenseeAmount, BasedOddsSpread, BetCount)
	SELECT t.rptDate, pl.PartyId, t.ProductId, t.CurrencyId
		,SUM((CASE
				WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
				WHEN t.BettypeRef IN (1706, 3007) THEN -t.Tips * ISNULL(cr.Rate, p.Rate)
				WHEN t.ProductId = 3 THEN -(t.MemberWL + t.AgentComm)
				WHEN (t.ProductId = 15 AND cp.LicenseeId IS NULL) OR (t.ProductId <> 15 AND p.LicenseeId IS NULL) THEN 0
				WHEN t.ProductId = 15 THEN t.PayOut - t.CommShare * cp.CommShareRate - t.CashInShare * cp.CashInShareRate
				ELSE -t.MemberWL * ISNULL(cr.Rate, p.Rate)
					+ t.PayOut + t.Contribution - t.JackpotPrize - t.Prize - t.Bonus - t.FreeBets END
				- CASE WHEN t.ProductId = 31 THEN (t.AgentComm + t.MemberComm) ELSE 0 END
		) * e.Rate) AS GrossLicenseeAmount
		,SUM(-t.MemberWL * e.Rate) AS LicenseeWL
		,SUM((CASE
				WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
				WHEN t.BettypeRef IN (1706, 3007) THEN 0
				WHEN t.ProductId = 3 THEN -(t.MemberWL + t.AgentComm)
				WHEN (t.ProductId = 15 AND cp.LicenseeId IS NULL) OR (t.ProductId <> 15 AND p.LicenseeId IS NULL) THEN 0
				WHEN t.ProductId = 15 THEN t.PayOut - t.CommShare * cp.CommShareRate - t.CashInShare * cp.CashInShareRate
				ELSE (-t.MemberWL - t.Contribution) * ISNULL(cr.Rate, p.Rate) + t.PayOut END
				- CASE WHEN t.ProductId = 31 THEN (t.AgentComm + t.MemberComm) ELSE 0 END
		) * e.Rate) AS LicenseeAmount
		,SUM(CASE
				WHEN p.LicenseeId IS NULL THEN 0
				WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
				WHEN t.BettypeRef IN (1706, 3007) THEN -t.Tips * ISNULL(cr.Rate, p.Rate)
				ELSE (t.Contribution - t.JackpotPrize - t.Prize - t.Bonus - t.FreeBets) END * e.Rate
		) AS ExtraAmount
		,SUM(CASE
				WHEN p.LicenseeId IS NULL THEN 0
				WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
				ELSE t.OddsSpread END * e.Rate
		) AS OddsSpread
		,SUM(t.Contribution * e.Rate) AS Contribution
		,SUM(t.JackpotPrize * e.Rate) AS JackpotPrize
		,SUM(t.Prize * e.Rate) AS Prize
		,SUM(t.Bonus * e.Rate) AS Bonus
		,SUM(t.LuckyDraw * e.Rate) AS LuckyDraw
		,SUM(t.FreeBets * e.Rate) AS FreeBets
		,SUM(t.Contribution * ISNULL(cr.Rate, p.Rate) * e.Rate) AS ContributionDiscount
		,SUM(-t.MemberWL) AS BasedLicenseeWL
		,SUM(CASE
				WHEN t.BettypeRef IN (1706, 3007) THEN 0
				WHEN t.ProductId = 3 THEN -(t.MemberWL + t.AgentComm)
				WHEN (t.ProductId = 15 AND cp.LicenseeId IS NULL) OR (t.ProductId <> 15 AND p.LicenseeId IS NULL) THEN 0
				WHEN t.ProductId = 15 THEN t.PayOut - t.CommShare * cp.CommShareRate - t.CashInShare * cp.CashInShareRate
				ELSE (-t.MemberWL - t.Contribution) * ISNULL(cr.Rate, p.Rate) + t.PayOut END) AS BasedLicenseeAmount
		,SUM(CASE
				WHEN p.LicenseeId IS NULL THEN 0
				WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
				ELSE t.OddsSpread END
		) AS BasedOddsSpread
		,SUM(t.BetCount) AS BetCount
	FROM #TempData t
		INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND e.BaseCurrencyId = 0
		INNER JOIN #PartyList pl ON t.LicenseeId = pl.LicenseeId
		LEFT JOIN @CBChargeRate cp ON t.LicenseeId = cp.LicenseeId AND t.ProductId = 15 AND t.rptDate = cp.rptDate
		LEFT JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.ProductId = p.ProductId AND t.BettypeRef = p.BettypeRef AND t.rptDate BETWEEN p.FromDate AND p.ToDate
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = p.ChargeId AND t.CurrencyId = cr.CurrencyId
	WHERE t.ProductId NOT IN (13, 37)
		AND (cp.LicenseeId IS NOT NULL OR p.LicenseeId IS NOT NULL)
	GROUP BY t.rptDate, pl.PartyId, t.ProductId, t.CurrencyId
	
	-- BT
	INSERT INTO #tmpResult (rptDate, PartyId, ProductId, CurrencyId, GrossLicenseeAmount, LicenseeAmount, BasedLicenseeAmount, BetCount)
	SELECT t.rptDate, p.PartyId, 13, t.CurrencyId
		,SUM((CASE WHEN t.BettypeRef = 901 THEN -t.MemberWL WHEN t.ProductId = 13 THEN 0 ELSE t.MemberWL END - t.CashInShare * p.Rate) * e.Rate) AS GrossLicenseeAmount
		,SUM((CASE WHEN t.BettypeRef = 901 THEN -t.MemberWL WHEN t.ProductId = 13 THEN 0 ELSE t.MemberWL END - t.CashInShare * p.Rate) * e.Rate) AS LicenseeAmount
		,SUM((CASE WHEN t.BettypeRef = 901 THEN -t.MemberWL WHEN t.ProductId = 13 THEN 0 ELSE t.MemberWL END - t.CashInShare * p.Rate)) AS BasedLicenseeAmount
		,SUM(t.Betcount) AS Betcount
	FROM #TempData t
		INNER JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId = 13
		INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND e.BaseCurrencyId = 0
	WHERE t.ProductId IN (0, 3, 13)
	GROUP BY t.rptDate, p.PartyId, t.CurrencyId

	-- SB Promotion
	INSERT INTO #tmpResult (rptDate, PartyId, ProductId, CurrencyId, GrossLicenseeAmount, LicenseeAmount, BasedLicenseeAmount, BetCount)
	SELECT t.rptDate, p.PartyId, 37, t.CurrencyId
		,SUM(CASE WHEN t.BettypeRef = 17005 THEN t.AgentWL ELSE t.MemberWL END * e.Rate) AS GrossLicenseeAmount
		,SUM(CASE WHEN t.BettypeRef = 17005 THEN t.AgentWL ELSE t.MemberWL END * e.Rate) AS LicenseeAmount
		,SUM(CASE WHEN t.BettypeRef = 17005 THEN t.AgentWL ELSE t.MemberWL END) AS BasedLicenseeAmount
		,SUM(t.BetCount) AS BetCount
	FROM #TempData t
		INNER JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId = 0
		INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND e.BaseCurrencyId = 0
	WHERE t.ProductId = 37
	GROUP BY t.rptDate, p.PartyId, t.CurrencyId

	IF ISNULL(@Currencies, '') <> ''
		DELETE #tmpResult WHERE ',' + @Currencies + ',' NOT LIKE '%,' + CONVERT(VARCHAR(20), CurrencyId) + ',%'

	UPDATE t
	SET t.BasedLicenseeWL = t.BasedLicenseeWL * e.Rate
		,t.BasedOddsSpread = t.BasedOddsSpread * e.Rate
		,t.BasedLicenseeAmount = t.BasedLicenseeAmount * e.Rate
	FROM #tmpResult t
		INNER JOIN (SELECT DISTINCT PartyId, BaseCurrencyId FROM #PartyList) pl ON t.PartyId = pl.PartyId
		INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND pl.BaseCurrencyId = e.BaseCurrencyId

	DELETE #Exchange WHERE BaseCurrencyId <> 0

	-- Include OddsSpread into Licensing Fee if value is positive
	UPDATE t
	SET t.GrossLicenseeAmount = t.GrossLicenseeAmount + CASE WHEN r.BasedOddsSpread <= 0 THEN 0 ELSE t.OddsSpread END
		,t.LicenseeAmount = t.LicenseeAmount + CASE WHEN r.BasedOddsSpread <= 0 THEN 0 ELSE t.OddsSpread END
		,t.BasedLicenseeAmount = t.BasedLicenseeAmount + CASE WHEN r.BasedOddsSpread <= 0 THEN 0 ELSE t.BasedOddsSpread END
	FROM #tmpResult t
		INNER JOIN (
			SELECT PartyId, ProductId, SUM(BasedOddsSpread) AS BasedOddsSpread
			FROM #tmpResult
			WHERE BasedOddsSpread <> 0
			GROUP BY PartyId, ProductId
		) r ON t.PartyId = r.PartyId AND t.ProductId = r.ProductId

	-- Min Fee, Rebate & Discount
	BEGIN
		-- Min Fee
		CREATE TABLE #tmpMinFee (PartyId INT, ProductId INT, GroupId INT, GroupMinFeeId INT, FeeTypeId TINYINT, IsPrimary BIT
			,FromDate DATE, ToDate DATE, ProrateMinFee MONEY, BasedProrateMinFee MONEY)
		
		IF @Currencies = '' -- just apply min fee for all selected currencies
		BEGIN
			INSERT INTO #tmpMinFee (PartyId, ProductId, GroupId, GroupMinFeeId, FeeTypeId, IsPrimary, FromDate, ToDate, ProrateMinFee, BasedProrateMinFee)
			SELECT PartyId, ProductId, GroupId, GroupMinFeeId, FeeTypeId, IsPrimary, FromDate, ToDate, ProrateMinFee * ISNULL(e.Rate, 0), ProrateMinFee
			FROM dbo.LA_f_GetProrateMinFee(@PartyIds, @FromDate, @ToDate) m
				LEFT JOIN #Exchange e ON m.BaseCurrencyId = e.ExchangeId
		END

		-- Rebate & Discount
		DECLARE @F_Date DATE = @FDate, @T_Date DATE = @TDate
		CREATE TABLE #tmpDiscountGroup (DiscountGroupId SMALLINT, DiscountGroupType TINYINT, BaseCurrencyId INT
			,PartyId INT, Remark NVARCHAR(4000), IsApplyDiscount BIT, IsSpecialTreatment BIT, ProductId INT, CalculationType TINYINT, CurrencyId INT, CurrencyCalculationType TINYINT)
		INSERT INTO #tmpDiscountGroup (DiscountGroupId, DiscountGroupType, BaseCurrencyId, PartyId, Remark, IsApplyDiscount, IsSpecialTreatment, ProductId, CalculationType, CurrencyId, CurrencyCalculationType)
		SELECT DiscountGroupId, DiscountGroupType, BaseCurrencyId, PartyId, Remark, IsApplyDiscount, IsSpecialTreatment, ProductId, CalculationType, CurrencyId, CurrencyCalculationType
		FROM (
			SELECT h.DiscountGroupId, h.DiscountGroupType, h.CurrencyId AS BaseCurrencyId, a.PartyId, a.IsApplyDiscount, a.IsSpecialTreatment, p.ProductId, p.CalculationType, c.CurrencyId, c.CalculationType AS CurrencyCalculationType
				,CASE WHEN h.FromDate < @F_Date THEN @F_Date ELSE h.FromDate END AS FromDate
				,CASE WHEN h.ToDate > @T_Date THEN @T_Date ELSE h.ToDate END AS ToDate
				,CASE WHEN h.DiscountGroupType = 2 THEN h.Remark ELSE a.Remark END AS Remark
				,ROW_NUMBER() OVER(PARTITION BY a.PartyId, p.ProductId, c.CurrencyId, CASE WHEN h.DiscountGroupType = 2 THEN 2 ELSE 1 END ORDER BY h.ToDate DESC) AS RN
			FROM #PartyList pl
				INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON pl.PartyId = a.PartyId
				INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
				INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON a.DiscountGroupId = p.DiscountGroupId
				LEFT JOIN dbo.LA_DiscountGroupCurrency c WITH (NOLOCK) ON a.DiscountGroupId = c.DiscountGroupId AND a.PartyId = c.PartyId
			WHERE h.FromDate < @T_Date AND h.ToDate >= @F_Date
				AND (h.DiscountGroupType = 2 OR c.DiscountGroupId IS NOT NULL)
				AND p.ProductId <> 37
		) t
		WHERE RN = 1
		
		DECLARE @tmpResult TABLE (PartyId INT, ProductId INT, GroupMinFeeId INT, GroupId INT, IsPrimary BIT, FeeTypeId TINYINT
			,ProrateMinFee MONEY, SecondaryLicensingFee MONEY, NonMinFee MONEY, LicensingFee MONEY, LicenseeWL MONEY
			,BasedProrateMinFee MONEY, BasedSecondaryLicensingFee MONEY, BasedNonMinFee MONEY, BasedLicensingFee MONEY, BasedLicenseeWL MONEY
			,WLToDiscount MONEY, Discount MONEY DEFAULT(0)
			,GrossLicensingFee MONEY, ExtraAmount MONEY, IsWaived BIT DEFAULT(0), IsChargedByMinFee BIT DEFAULT(0))
		
		INSERT INTO @tmpResult (PartyId, ProductId, GroupMinFeeId, GroupId, IsPrimary, FeeTypeId
			,ProrateMinFee, SecondaryLicensingFee, NonMinFee, LicensingFee, LicenseeWL
			,BasedProrateMinFee, BasedSecondaryLicensingFee, BasedNonMinFee, BasedLicensingFee, BasedLicenseeWL
			,WLToDiscount, GrossLicensingFee, ExtraAmount)
		SELECT ISNULL(r.PartyId, t.PartyId), ISNULL(r.ProductId, t.ProductId), t.GroupMinFeeId, t.GroupId, t.IsPrimary, t.FeeTypeId
			,MAX(CASE WHEN t.FeeTypeId = 1 THEN t.ProrateMinFee ELSE 0 END) AS ProrateMinFee
			,0 AS SecondaryLicensingFee
			,SUM(CASE WHEN t.PartyId IS NULL THEN r.LicenseeAmount ELSE 0 END) AS NonMinFee
			,SUM(ISNULL(r.LicenseeAmount, 0)) AS LicensingFee
			,SUM(ISNULL(r.LicenseeWL, 0)) AS LicenseeWL
			,MAX(CASE WHEN t.FeeTypeId = 1 THEN t.BasedProrateMinFee ELSE 0 END) AS BasedProrateMinFee
			,0 AS BasedSecondaryLicensingFee
			,SUM(CASE WHEN t.PartyId IS NULL THEN r.BasedLicenseeAmount ELSE 0 END) AS BasedNonMinFee
			,SUM(ISNULL(r.BasedLicenseeAmount, 0)) AS BasedLicensingFee
			,SUM(ISNULL(r.BasedLicenseeWL, 0)) AS BasedLicenseeWL
			,SUM(CASE WHEN d.PartyId IS NOT NULL THEN ISNULL(r.LicenseeWL, 0) ELSE 0 END) AS WLToDiscount
			,SUM(ISNULL(r.GrossLicenseeAmount, 0)) AS GrossLicensingFee
			,SUM(ISNULL(r.ExtraAmount, 0)) AS ExtraAmount
		FROM #tmpResult r
			FULL OUTER JOIN #tmpMinFee t ON r.PartyId = t.PartyId AND r.ProductId = t.ProductId AND r.rptDate BETWEEN t.FromDate AND t.ToDate
			LEFT JOIN #tmpDiscountGroup d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId
											AND (d.CurrencyId = 0 OR r.CurrencyId = d.CurrencyId)
											AND (d.IsSpecialTreatment = 0 OR r.CurrencyId <> 51)
											AND d.DiscountGroupType IN (3, 13)
											AND d.CurrencyCalculationType IN (2, 3) -- apply discount
		GROUP BY ISNULL(r.PartyId, t.PartyId), ISNULL(r.ProductId, t.ProductId), t.GroupMinFeeId, t.GroupId, t.IsPrimary, t.FeeTypeId, t.FromDate, t.ToDate

		UPDATE r
		SET r.LicensingFee = CASE WHEN r.LicensingFee < 0 THEN 0 ELSE r.LicensingFee END
			,r.NonMinFee = CASE WHEN r.NonMinFee < 0 THEN 0 ELSE r.NonMinFee END
			,r.BasedLicensingFee = CASE WHEN r.BasedLicensingFee < 0 THEN 0 ELSE r.BasedLicensingFee END
			,r.BasedNonMinFee = CASE WHEN r.BasedNonMinFee < 0 THEN 0 ELSE r.BasedNonMinFee END
		FROM @tmpResult r
			LEFT JOIN dbo.LA_f_JVPartyListSel() jvp ON r.PartyId = jvp.PartyId
		WHERE jvp.PartyId IS NULL AND r.ProductId NOT IN (3, 15, 25, 31)

		UPDATE r
		SET r.SecondaryLicensingFee = t.LicensingFee, r.BasedSecondaryLicensingFee = t.BasedLicensingFee
		FROM @tmpResult r
			INNER JOIN (
				SELECT GroupMinFeeId, GroupId, ProductId, SUM(LicensingFee) AS LicensingFee, SUM(BasedLicensingFee) AS BasedLicensingFee
				FROM @tmpResult
				WHERE FeeTypeId = 1 AND IsPrimary = 0
				GROUP BY GroupMinFeeId, GroupId, ProductId
			) t ON r.GroupMinFeeId = t.GroupMinFeeId AND r.GroupId = t.GroupId AND r.ProductId = t.ProductId
		WHERE r.IsPrimary = 1 AND r.FeeTypeId = 1 AND r.GroupMinFeeId > 0

		UPDATE @tmpResult SET IsChargedByMinFee = 1 WHERE BasedProrateMinFee > BasedLicensingFee + BasedSecondaryLicensingFee
		
		DECLARE @tmpDiscount TABLE (DiscountGroupId SMALLINT, DiscountGroupType TINYINT, BaseCurrencyId INT, PartyId INT, Remark NVARCHAR(4000), IsApplyDiscount BIT, ProductId INT, CalculationType TINYINT
			,LicenseeAmount MONEY, BasedLicenseeAmount MONEY, DiscountRate FLOAT DEFAULT (0))
			
		-- Discount before min fee: NOT discount for all currencies
		INSERT INTO @tmpDiscount (DiscountGroupId, DiscountGroupType, BaseCurrencyId, PartyId, Remark, IsApplyDiscount, ProductId, CalculationType, LicenseeAmount, BasedLicenseeAmount)
		SELECT d.DiscountGroupId, d.DiscountGroupType, d.BaseCurrencyId, d.PartyId, d.Remark, d.IsApplyDiscount, d.ProductId, d.CalculationType
			,SUM(CASE WHEN d.DiscountGroupType IN (1, 11) THEN r.LicenseeAmount ELSE r.LicenseeWL END)
			,SUM(CASE WHEN d.DiscountGroupType IN (1, 11) THEN r.BasedLicenseeAmount ELSE r.BasedLicenseeWL END)
		FROM #tmpResult r
			INNER JOIN #tmpDiscountGroup d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId
				AND (d.CurrencyId = 0 OR r.CurrencyId = d.CurrencyId)
				AND (d.IsSpecialTreatment = 0 OR r.CurrencyId <> 51)
		WHERE d.DiscountGroupType <> 2 -- 2 = Rebate, Others = Discount
			AND (d.CurrencyId <> 0 OR d.IsSpecialTreatment = 1) -- NOT all currencies
		GROUP BY d.DiscountGroupId, d.DiscountGroupType, d.BaseCurrencyId, d.PartyId, d.Remark, d.IsApplyDiscount, d.ProductId, d.CalculationType
		
		-- Discount after min fee: discount for all currencies
		INSERT INTO @tmpDiscount (DiscountGroupId, DiscountGroupType, BaseCurrencyId, PartyId, Remark, IsApplyDiscount, ProductId, CalculationType, LicenseeAmount, BasedLicenseeAmount)
		SELECT d.DiscountGroupId, d.DiscountGroupType, d.BaseCurrencyId, d.PartyId, d.Remark, d.IsApplyDiscount, d.ProductId, d.CalculationType
			,SUM(CASE WHEN d.DiscountGroupType IN (1, 11) THEN r.LicenseeAmount ELSE r.LicenseeWL END)
			,SUM(CASE WHEN d.DiscountGroupType IN (1, 11) THEN r.BasedLicenseeAmount ELSE r.BasedLicenseeWL END)
		FROM (
			SELECT PartyId, ProductId
				,SUM(CASE WHEN IsChargedByMinFee = 1 THEN ProrateMinFee - SecondaryLicensingFee ELSE LicensingFee END) AS LicenseeAmount
				,SUM(CASE WHEN IsChargedByMinFee = 1 THEN BasedProrateMinFee - BasedSecondaryLicensingFee ELSE BasedLicensingFee END) AS BasedLicenseeAmount
				,SUM(LicenseeWL) AS LicenseeWL
				,SUM(BasedLicenseeWL) AS BasedLicenseeWL
			FROM @tmpResult
			GROUP BY PartyId, ProductId
		) r
			INNER JOIN #tmpDiscountGroup d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId AND d.CurrencyId = 0 AND d.IsSpecialTreatment = 0 -- all currencies
		WHERE d.DiscountGroupType <> 2 -- 2 = Rebate, Others = Discount
		GROUP BY d.DiscountGroupId, d.DiscountGroupType, d.BaseCurrencyId, d.PartyId, d.Remark, d.IsApplyDiscount, d.ProductId, d.CalculationType

		-- Group discount
		UPDATE td
		SET td.DiscountRate = dr.Rate
		FROM @tmpDiscount td
			INNER JOIN (
				SELECT d.DiscountGroupId, d.Rate
				FROM (
					SELECT DiscountGroupId, SUM(BasedLicenseeAmount) AS LicenseeAmount
					FROM @tmpDiscount
					WHERE CalculationType IN (1, 10) -- calculation products
						AND DiscountGroupType IN (11, 13) -- group discount
						AND BasedLicenseeAmount > 0
					GROUP BY DiscountGroupId
				) t
					INNER JOIN dbo.LA_DiscountGroupDetail d WITH (NOLOCK) ON t.DiscountGroupId = d.DiscountGroupId AND FLOOR(t.LicenseeAmount) BETWEEN d.FromAmount AND d.ToAmount
			) dr ON td.DiscountGroupId = dr.DiscountGroupId
		WHERE td.IsApplyDiscount = 1 AND td.CalculationType IN (0, 10) -- discounted products

		-- Individual discount
		UPDATE td
		SET td.DiscountRate = dr.Rate
		FROM @tmpDiscount td
			INNER JOIN (
				SELECT d.DiscountGroupId, t.PartyId, d.Rate
				FROM (
					SELECT DiscountGroupId, PartyId, SUM(BasedLicenseeAmount) AS LicenseeAmount
					FROM @tmpDiscount
					WHERE CalculationType IN (1, 10) -- calculation products
						AND DiscountGroupType IN (1, 3) -- individual discount
						AND BasedLicenseeAmount > 0
					GROUP BY DiscountGroupId, PartyId
				) t
					INNER JOIN dbo.LA_DiscountGroupDetail d WITH (NOLOCK) ON t.DiscountGroupId = d.DiscountGroupId AND FLOOR(t.LicenseeAmount) BETWEEN d.FromAmount AND d.ToAmount
			) dr ON td.DiscountGroupId = dr.DiscountGroupId AND td.PartyId = dr.PartyId
		WHERE td.IsApplyDiscount = 1 AND td.CalculationType IN (0, 10) -- discounted products

		UPDATE r
		SET r.LicensingFee = r.LicensingFee + CASE WHEN t.LicensingFee < t.ProrateMinFee THEN (t.ProrateMinFee - t.LicensingFee) ELSE 0 END
			,r.BasedLicensingFee = r.BasedLicensingFee + CASE WHEN t.BasedLicensingFee < t.BasedProrateMinFee THEN (t.BasedProrateMinFee - t.BasedLicensingFee) ELSE 0 END
			,r.IsChargedByMinFee = CASE WHEN t.BasedLicensingFee < t.BasedProrateMinFee THEN 1 ELSE 0 END
		FROM @tmpResult r
			INNER JOIN (
				SELECT GroupMinFeeId, GroupId, ProductId
					,MAX(ProrateMinFee) AS ProrateMinFee, SUM(LicensingFee) AS LicensingFee
					,MAX(BasedProrateMinFee) AS BasedProrateMinFee, SUM(BasedLicensingFee) AS BasedLicensingFee
				FROM @tmpResult
				WHERE FeeTypeId = 1
				GROUP BY GroupMinFeeId, GroupId, ProductId
			) t ON r.GroupMinFeeId = t.GroupMinFeeId AND r.GroupId = t.GroupId AND r.ProductId = t.ProductId
		WHERE r.IsPrimary = 1 AND r.FeeTypeId = 1
		
		-- Update discount amount for discount on licensee winloss
		UPDATE r
		SET r.Discount = r.WLToDiscount * d.DiscountRate
		FROM @tmpResult r
			INNER JOIN @tmpDiscount d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId
			OUTER APPLY (
				SELECT TOP 1 t.PartyId
				FROM @tmpResult t
				WHERE t.GroupMinFeeId = r.GroupMinFeeId AND t.FeeTypeId = r.FeeTypeId
					AND t.IsChargedByMinFee = 1 AND t.IsPrimary = 1 AND t.FeeTypeId = 1
					AND t.GroupMinFeeId > 0 AND r.IsPrimary = 0
			) t
		WHERE d.DiscountGroupType IN (3, 13) -- discount on licensee winloss
			AND r.IsChargedByMinFee = 0 -- if licensee is charged by min fee, discount = 0
			AND t.PartyId IS NULL -- if primary is charged by min fee, discount of secondary = 0
			AND r.LicenseeWL > 0 -- if licensee winloss is negative, discount = 0
	END

	DECLARE @Result TABLE
	(
		PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
		,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), DiscountType TINYINT, Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000)
		,ProrateMinFee MONEY, SecondaryLicensingFee MONEY, NonMinFee MONEY, IsGroupMinFee BIT
	)
	/*
		DiscountType: 0 = no discount, 1 = discount by licensing fee, 2 = discount by licensee winloss
	*/

	IF EXISTS (SELECT 1 FROM dbo.strSplit(@LicensingFeeTypeIds, ',') WHERE CONVERT(INT, val) = 0) -- Normal Licensing Fee
	BEGIN
		INSERT INTO @Result (PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, DiscountType, ProrateMinFee, SecondaryLicensingFee, NonMinFee, IsGroupMinFee)
		SELECT t.PartyId, t.ProductId, 0 AS LicensingFeeTypeId, t.GrossLicensingFee, t.LicensingFee, t.ExtraAmount, t.IsChargedByGroupMinFee, t.IsChargedByMinFee
			,CASE WHEN d.DiscountGroupType IN (1, 11) THEN d.Discount ELSE t.Discount END, ISNULL(d.DiscountRate, 0)
			,CASE WHEN ISNULL(d.DiscountRate, 0) = 0 THEN '' ELSE ISNULL(d.DiscountRemark, '') END
			,CASE
				WHEN d.DiscountGroupType IN (1, 11) AND d.Discount > 0 THEN 1
				WHEN d.DiscountGroupType IN (3, 13) AND t.Discount > 0 THEN 2
				ELSE 0 END AS DiscountType
			,t.ProrateMinFee, t.SecondaryLicensingFee, t.NonMinFee, t.IsGroupMinFee
		FROM (
			SELECT r.PartyId, r.ProductId
				,SUM(r.GrossLicensingFee) AS GrossLicensingFee
				,SUM(r.LicensingFee) AS LicensingFee
				,SUM(r.ExtraAmount) AS ExtraAmount
				,MAX(CASE WHEN r.GroupMinFeeId > 0 AND r.IsChargedByMinFee = 1 THEN 1 ELSE 0 END) AS IsChargedByGroupMinFee
				,MAX(CASE WHEN r.GroupMinFeeId < 0 AND r.IsChargedByMinFee = 1 THEN 1 ELSE 0 END) AS IsChargedByMinFee
				,SUM(r.ProrateMinFee) AS ProrateMinFee
				,SUM(r.SecondaryLicensingFee) AS SecondaryLicensingFee
				,SUM(r.NonMinFee) AS NonMinFee
				,MAX(CASE WHEN r.GroupMinFeeId > 0 THEN 1 ELSE 0 END) AS IsGroupMinFee
				,SUM(ISNULL(r.Discount, 0)) AS Discount
			FROM @tmpResult r
				INNER JOIN #Products pd ON r.ProductId = pd.ProductId AND pd.IsSelected = 1
			GROUP BY r.PartyId, r.ProductId
		) t
			LEFT JOIN (
				SELECT PartyId, ProductId, DiscountGroupType
					,SUM(ISNULL(LicenseeAmount * DiscountRate, 0)) AS Discount
					,MAX(ISNULL(DiscountRate, 0)) AS DiscountRate
					,MAX(ISNULL(Remark, '')) AS DiscountRemark
				FROM @tmpDiscount
				GROUP BY PartyId, ProductId, DiscountGroupType
			) d ON t.PartyId = d.PartyId AND t.ProductId = d.ProductId

		UPDATE @Result SET Discount = 0, DiscountRate = 0, DiscountRemark = '', DiscountType = 0 WHERE Discount > LicensingFee

		-- Adjust discount for discount by licensing fee
		BEGIN
			-- Step 1: Adjust for individual min fee (no waive)
			;WITH CTE_Party AS (
				SELECT DISTINCT a.PartyId, a.ProductId
				FROM @tmpResult a
				WHERE a.IsPrimary = 1 AND a.FeeTypeId = 1
					AND NOT EXISTS (
						SELECT 1 FROM @tmpResult b
						WHERE a.PartyId = b.PartyId AND a.ProductId = b.ProductId
							AND (b.FeeTypeId = 2 OR (b.GroupMinFeeId > 0 AND b.IsPrimary = 1))
					)
			), CTE_Discount AS (
				SELECT PartyId, ProductId, SUM(ProrateMinFee) AS ProrateMinFee, SUM(LicensingFee) AS LicensingFee, SUM(Discount) AS Discount
				FROM @Result
				WHERE DiscountType = 1
				GROUP BY PartyId, ProductId
			), CTE_AdjustedDiscount AS (
				SELECT p.PartyId, p.ProductId, SUM(ProrateMinFee) AS ProrateMinFee, SUM(LicensingFee - Discount) AS LicensingFee
				FROM CTE_Party p
					INNER JOIN CTE_Discount d ON p.PartyId = d.PartyId AND p.ProductId = d.ProductId
				GROUP BY p.PartyId, p.ProductId
				HAVING SUM(LicensingFee - Discount) < SUM(ProrateMinFee)
			)
			UPDATE r
			SET r.Discount = CASE WHEN r.Discount - (d.ProrateMinFee - d.LicensingFee) > 0 THEN r.Discount - (d.ProrateMinFee - d.LicensingFee) ELSE 0 END
				,r.LicensingFee = CASE WHEN r.Discount - (d.ProrateMinFee - d.LicensingFee) > 0 THEN r.LicensingFee ELSE r.LicensingFee + d.ProrateMinFee - d.LicensingFee - r.Discount END
				,r.IsChargedByMinFee = 1
			FROM @Result r
				INNER JOIN CTE_AdjustedDiscount d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId

			-- Step 2: Update Secondary Licensing Fee
			;WITH CTE_SecondaryLicensee AS (
				SELECT a.PartyId AS PrimaryId, b.PartyId, b.ProductId, SUM(b.LicensingFee) AS LicensingFee
				FROM (
					SELECT DISTINCT PartyId, ProductId, GroupMinFeeId
					FROM @tmpResult
					WHERE IsPrimary = 1 AND FeeTypeId = 1 AND GroupMinFeeId > 0
					) a
					CROSS APPLY (
						SELECT b.PartyId, b.ProductId, b.LicensingFee
						FROM @tmpResult b
						WHERE a.GroupMinFeeId = b.GroupMinFeeId AND a.ProductId = b.ProductId AND b.IsPrimary = 0
					) b
				GROUP BY a.PartyId, b.PartyId, b.ProductId
			), CTE_AdjustSecondaryLicensee AS (
				SELECT c.PrimaryId AS PartyId, c.ProductId, SUM(c.LicensingFee - r.Discount) AS LicensingFee
				FROM CTE_SecondaryLicensee c
					INNER JOIN @Result r ON c.PartyId = r.PartyId AND c.ProductId = r.ProductId
				WHERE r.DiscountType = 1
				GROUP BY c.PrimaryId, c.ProductId
			)
			UPDATE r
			SET r.SecondaryLicensingFee = c.LicensingFee
			FROM @Result r
				INNER JOIN CTE_AdjustSecondaryLicensee c ON r.PartyId = c.PartyId AND r.ProductId = c.ProductId

			-- Step 3: Adjust for group min fee (no waive)
			;WITH CTE_Party AS (
				SELECT DISTINCT a.PartyId, a.ProductId
				FROM @tmpResult a
				WHERE a.IsPrimary = 1 AND a.FeeTypeId = 1
					AND NOT EXISTS (SELECT 1 FROM @tmpResult b WHERE a.PartyId = b.PartyId AND a.ProductId = b.ProductId AND b.FeeTypeId = 2)
					AND EXISTS (SELECT 1 FROM @tmpResult c WHERE a.PartyId = c.PartyId AND a.ProductId = c.ProductId AND c.GroupMinFeeId > 0 AND c.IsPrimary = 1)
			)
			UPDATE r
			SET r.Discount
							= CASE
								WHEN r.Discount < ((r.ProrateMinFee + r.NonMinFee - r.SecondaryLicensingFee) - (r.LicensingFee - r.Discount)) THEN 0
								ELSE r.Discount - ((r.ProrateMinFee + r.NonMinFee - r.SecondaryLicensingFee) - (r.LicensingFee - r.Discount)) END
				,r.LicensingFee
							= r.LicensingFee
							- CASE
								WHEN r.Discount > ((r.ProrateMinFee + r.NonMinFee - r.SecondaryLicensingFee) - (r.LicensingFee - r.Discount)) THEN 0
								ELSE r.Discount - ((r.ProrateMinFee + r.NonMinFee - r.SecondaryLicensingFee) - (r.LicensingFee - r.Discount)) END
				,r.IsChargedByMinFee
							= CASE
								WHEN r.Discount < ((r.ProrateMinFee + r.NonMinFee - r.SecondaryLicensingFee) - (r.LicensingFee - r.Discount))
									AND ISNULL(m.IsChargedByMinFee, 0) = 1 THEN 1
								ELSE r.IsChargedByMinFee END
				,r.IsChargedByGroupMinFee
							= CASE
								WHEN r.Discount < ((r.ProrateMinFee + r.NonMinFee - r.SecondaryLicensingFee) - (r.LicensingFee - r.Discount))
									AND ISNULL(m.IsChargedByGroupMinFee, 0) = 1 THEN 1
								ELSE r.IsChargedByGroupMinFee END
			FROM @Result r
				INNER JOIN CTE_Party p ON r.PartyId = p.PartyId AND r.ProductId = p.ProductId
				LEFT JOIN (
					SELECT PartyId, ProductId
						,CONVERT(BIT, MAX(CASE WHEN GroupMinFeeId < 0 THEN 1 ELSE 0 END)) AS IsChargedByMinFee
						,CONVERT(BIT, MAX(CASE WHEN GroupMinFeeId > 0 THEN 1 ELSE 0 END)) AS IsChargedByGroupMinFee
					FROM #tmpMinFee WHERE FeeTypeId = 1 AND IsPrimary = 1
					GROUP BY PartyId, ProductId
				) m ON r.PartyId = m.PartyId AND r.ProductId = m.ProductId
			WHERE r.DiscountType = 1
				AND (r.ProrateMinFee + r.NonMinFee - r.SecondaryLicensingFee) > (r.LicensingFee - r.Discount)
		END

		-- Adjust discount for discount by licensee winloss
		BEGIN
			DECLARE @AdjustGroupMinFee TABLE (GroupMinFeeId INT, ProductId INT, RemaingAmount MONEY, tmpPartyId INT, tmpDiscount MONEY, IsAdjustDone BIT)
			INSERT INTO @AdjustGroupMinFee (GroupMinFeeId, ProductId)
			SELECT GroupMinFeeId, ProductId
			FROM @tmpResult t
			WHERE GroupMinFeeId > 0 OR (FeeTypeId = 1 AND GroupMinFeeId < 0)
				AND EXISTS (SELECT 1 FROM @Result r WHERE t.PartyId = r.PartyId AND t.ProductId = r.ProductId AND r.DiscountType = 2)
			GROUP BY GroupMinFeeId, ProductId

			UPDATE a
			SET a.RemaingAmount = t.RemaingAmount, a.IsAdjustDone = 0
			FROM @AdjustGroupMinFee a
				INNER JOIN (
					SELECT GroupMinFeeId, ProductId, SUM(LicensingFee - Discount - ProrateMinFee) AS RemaingAmount
					FROM @tmpResult
					WHERE GroupMinFeeId > 0 OR (FeeTypeId = 1 AND GroupMinFeeId < 0)
					GROUP BY GroupMinFeeId, ProductId
					HAVING SUM(LicensingFee - Discount - ProrateMinFee) < 0 AND SUM(Discount) > 0
				) t ON a.GroupMinFeeId = t.GroupMinFeeId AND a.ProductId = t.ProductId

			WHILE EXISTS (SELECT 1 FROM @AdjustGroupMinFee WHERE IsAdjustDone = 0)
			BEGIN
				UPDATE a
				SET a.tmpPartyId = t.PartyId
					,a.RemaingAmount = CASE WHEN a.RemaingAmount + t.Discount >= 0 THEN 0 ELSE a.RemaingAmount + t.Discount END
					,a.tmpDiscount = CASE WHEN a.RemaingAmount + t.Discount >= 0 THEN a.RemaingAmount + t.Discount ELSE 0 END
					,a.IsAdjustDone = CASE WHEN a.RemaingAmount + t.Discount >= 0 THEN 1 ELSE 0 END
				FROM @AdjustGroupMinFee a
					CROSS APPLY (
						SELECT TOP 1 t.PartyId, t.Discount FROM @tmpResult t
						WHERE a.GroupMinFeeId = t.GroupMinFeeId AND a.ProductId = t.ProductId
							AND (t.GroupMinFeeId > 0 OR (t.FeeTypeId = 1 AND t.GroupMinFeeId < 0))
						ORDER BY t.Discount DESC, t.IsPrimary DESC
					) t
					
				UPDATE r
				SET r.Discount = a.tmpDiscount
				FROM @tmpResult r
					INNER JOIN @AdjustGroupMinFee a ON r.PartyId = a.tmpPartyId AND r.ProductId = a.ProductId AND r.GroupMinFeeId = a.GroupMinFeeId
				WHERE r.GroupMinFeeId > 0 OR (r.FeeTypeId = 1 AND r.GroupMinFeeId < 0)
			END

			IF EXISTS (SELECT 1 FROM @AdjustGroupMinFee WHERE IsAdjustDone = 1)
				UPDATE r
				SET r.Discount = t.Discount
				FROM @Result r
					INNER JOIN (
						SELECT PartyId, ProductId, SUM(Discount) AS Discount
						FROM @tmpResult
						GROUP BY PartyId, ProductId
					) t ON r.PartyId = t.PartyId AND r.ProductId = t.ProductId
				WHERE r.DiscountType = 2
		END

		-- Remove non-selected licensees
		DELETE r
		FROM @Result r
			LEFT JOIN (SELECT DISTINCT PartyId FROM #PartyList WHERE IsSelected = 1) p ON r.PartyId = p.PartyId
		WHERE p.PartyId IS NULL
		
		-- Rebate
		UPDATE r
		SET r.Rebate = (r.LicensingFee - r.Discount) * ISNULL(dd.Rate, 0)
			,r.RebateRate = ISNULL(dd.Rate, 0)
			,r.RebateRemark = ISNULL(d.Remark, N'')
		FROM @Result r
			LEFT JOIN #tmpDiscountGroup d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId AND d.DiscountGroupType = 2 -- Rebate
			LEFT JOIN dbo.LA_DiscountGroupDetail dd WITH (NOLOCK) ON d.DiscountGroupId = dd.DiscountGroupId

		-- For no data
		INSERT INTO @Result (
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark
		)
		SELECT p.PartyId, p.ProductId, 0, 0, 0, 0, 0, 0, 0, 0, '', 0, 0, ''
		FROM (
			SELECT DISTINCT PartyId, ProductId FROM @PartyChargeInfo
			UNION SELECT DISTINCT PartyId, 15 AS ProductId FROM @CBChargeRate
		) p
			INNER JOIN (SELECT DISTINCT PartyId FROM #PartyList WHERE IsSelected = 1) pl ON p.PartyId = pl.PartyId
			INNER JOIN #Products pd ON p.ProductId = pd.ProductId AND pd.IsSelected = 1
			LEFT JOIN @Result r ON p.PartyId = r.PartyId AND p.ProductId = r.ProductId
		WHERE r.PartyId IS NULL
	END

	IF EXISTS (SELECT 1 FROM dbo.strSplit(@LicensingFeeTypeIds, ',') WHERE CONVERT(INT, val) > 0) -- special bettype
	BEGIN
		INSERT INTO @Result (PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount)
		SELECT r.PartyId, r.ProductId, t.LicensingFeeTypeId, 0 AS GrossLicensingFee, 0 AS LicensingFee, t.ExtraAmount
		FROM (
			SELECT t.PartyId, t.ProductId
				,SUM(ISNULL(t.Contribution, 0)) AS Contribution
				,SUM(ISNULL(t.JackpotPrize, 0)) AS JackpotPrize
				,SUM(ISNULL(t.Prize, 0)) AS Prize
				,SUM(ISNULL(t.Bonus, 0)) AS Bonus
				,SUM(ISNULL(t.LuckyDraw, 0)) AS LuckyDraw
				,SUM(ISNULL(t.FreeBets, 0)) AS FreeBets
				,SUM(ISNULL(t.ContributionDiscount, 0)) AS ContributionDiscount
				,SUM(ISNULL(t.OddsSpread, 0)) AS OddsSpread
				,SUM(ISNULL(t.BetCount, 0)) AS BetCount
			FROM #tmpResult t
				INNER JOIN (SELECT DISTINCT PartyId FROM #PartyList WHERE IsSelected = 1) p ON t.PartyId = p.PartyId
				INNER JOIN #Products pd ON t.ProductId = pd.ProductId AND pd.IsSelected = 1
			GROUP BY t.PartyId, t.ProductId
		) r
			CROSS APPLY (
				SELECT CONVERT(SMALLINT, 1) AS LicensingFeeTypeId, Contribution AS ExtraAmount WHERE Contribution <> 0
				UNION ALL SELECT 2, JackpotPrize WHERE JackpotPrize <> 0
				UNION ALL SELECT 3, Prize WHERE Prize <> 0
				UNION ALL SELECT 4, Bonus WHERE Bonus <> 0
				UNION ALL SELECT 5, LuckyDraw WHERE LuckyDraw <> 0
				UNION ALL SELECT 6, FreeBets WHERE FreeBets <> 0
				UNION ALL SELECT 7, ContributionDiscount WHERE ContributionDiscount <> 0
				UNION ALL SELECT 8, BetCount
				UNION ALL SELECT 9, OddsSpread WHERE OddsSpread <> 0
			) t
		WHERE ',' + @LicensingFeeTypeIds + ',' LIKE '%,' + CONVERT(VARCHAR(10), t.LicensingFeeTypeId) + ',%'
	END

	IF EXISTS (SELECT 1 FROM dbo.strSplit(@LicensingFeeTypeIds, ',') WHERE CONVERT(INT, val) < 0) -- deduction
	BEGIN
		DECLARE @Deductions TABLE (PartyId INT, RemainingAMF MONEY, RemainingAGPrepayment MONEY, RemainingPrepayment MONEY)

		;WITH CTE_InvItemTypes AS (
			SELECT CONVERT(SMALLINT, InvItemTypeId) AS InvItemTypeId, CONVERT(VARCHAR(50), 'AdvanceMinFee') AS InvItemTypeName
			FROM (VALUES (3), (5), (7), (21)) AS t (InvItemTypeId) -- AdvanceMinFee (AMF)
			UNION
			SELECT InvItemTypeId, 'Prepayment'
			FROM (VALUES (22), (23), (24)) AS t (InvItemTypeId) -- Prepayment
			UNION
			SELECT InvItemTypeId, 'AGPrepayment'
			FROM (VALUES (25), (26), (27)) AS t (InvItemTypeId) -- AGPrepayment
		), CTE_Deduction AS (
			SELECT s.RefPartyId, t.InvItemTypeName, SUM(ISNULL(s.Income, 0) - ISNULL(s.Expense, 0)) AS Amount
			FROM dbo.LA_InvoiceStatement s WITH (NOLOCK)
				INNER JOIN dbo.LA_InvoiceHeader h WITH (NOLOCK) ON h.InvoiceHeaderId = s.InvoiceHeaderId
				INNER JOIN CTE_InvItemTypes t ON s.InvItemTypeId = t.InvItemTypeId
			WHERE ISNULL(h.StatusId, 0) = 0 AND h.Environment = @Environment
				AND EXISTS (SELECT 1 FROM #PartyList p WHERE s.RefPartyId = p.PartyId AND p.IsSelected = 1)
			GROUP BY s.RefPartyId, t.InvItemTypeName
		)
		INSERT INTO @Deductions (PartyId, RemainingAMF, RemainingAGPrepayment, RemainingPrepayment)
		SELECT RefPartyId
			,SUM(CASE WHEN InvItemTypeName = 'AdvanceMinFee'	THEN Amount ELSE 0 END)
			,SUM(CASE WHEN InvItemTypeName = 'AGPrepayment'		THEN Amount ELSE 0 END)
			,SUM(CASE WHEN InvItemTypeName = 'Prepayment'		THEN Amount ELSE 0 END)
		FROM CTE_Deduction
		GROUP BY RefPartyId

		-- AMF: SB only
		IF EXISTS (SELECT 1 FROM @Deductions WHERE RemainingAMF > 0)
		BEGIN
			INSERT INTO @Result (PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount)
			SELECT r.PartyId, 0, -1, MAX(d.RemainingAMF), MIN(t.DeductedAMF) AS DeductedAMF, 0
			FROM @Result r
				INNER JOIN @Deductions d ON r.PartyId = d.PartyId
				CROSS APPLY (
					SELECT r.ProrateMinFee AS DeductedAMF
					UNION ALL SELECT d.RemainingAMF
					UNION ALL SELECT r.LicensingFee - r.Discount WHERE r.IsGroupMinFee = 0 -- just Individual Min Fee
				) t
			WHERE r.ProductId = 0 -- SB
			GROUP BY r.PartyId
			HAVING MIN(t.DeductedAMF) > 0
		END

		-- AG Prepayment: AG Casino only
		IF EXISTS (SELECT 1 FROM @Deductions WHERE RemainingAGPrepayment > 0)
		BEGIN
			INSERT INTO @Result (PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount)
			SELECT r.PartyId, 10, -1, MAX(d.RemainingAGPrepayment), MIN(t.DeductedAGPrepayment) AS DeductedAGPrepayment, 0
			FROM @Result r
				INNER JOIN @Deductions d ON r.PartyId = d.PartyId
				CROSS APPLY (
					SELECT r.LicensingFee - r.Discount AS DeductedAGPrepayment
					UNION ALL SELECT d.RemainingAGPrepayment
				) t
			WHERE r.ProductId = 10 -- AG Casino
			GROUP BY r.PartyId
			HAVING MIN(t.DeductedAGPrepayment) > 0
		END

		-- Prepayment
		BEGIN
			INSERT INTO @Result (PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount)
			SELECT PartyId, -99, -1, RemainingPrepayment, RemainingPrepayment, 0
			FROM @Deductions WHERE RemainingPrepayment > 0
		END
	END

	SELECT
		PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
		,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark
	FROM @Result

	DROP TABLE #Exchange
	DROP TABLE #PartyList
	DROP TABLE #Products
	DROP TABLE #TempData
	DROP TABLE #tmpDiscountGroup
	DROP TABLE #tmpMinFee
	DROP TABLE #tmpResult
END
GO