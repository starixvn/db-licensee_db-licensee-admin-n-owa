/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="1"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_AmountToCompanyByProduct]
	@PartyIds				VARCHAR(MAX)
	,@ProductCodes			VARCHAR(MAX)
	,@Currencies			VARCHAR(MAX) = ''
	,@FromDate				DATETIME
	,@ToDate				DATETIME
	,@IsConvertExRate		BIT = 1
	,@IncludeTierRebate		BIT = 1
	,@LicensingFeeTypeIds	VARCHAR(1000) = '0'
	,@BaseCurrencyName		VARCHAR(10) = 'EUR'
	,@Environment			VARCHAR(50) = 'LOCAL'
	,@IsUsePreviousSetting	BIT = 0
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
		- 20220210@Percy: Offer Tier Rebate [RedmineID: #163495]
		- 20220315@Percy: Separate Sponsorship from Saba Promotion [RedmineID: #167121]
		- 20220222@Danny: Allbet - Promotion integration [#167510]
		- 20220506@Percy: Add new rebate type: Rebate on Licensee WL [RedmineID: #1732342]
		- 20220418@Percy: Add Credit note for AMF [RedmineID: #164139]
		- 20220817@Danny: hardcode for N8B, N8G (charge Rate And Discount rate are same) [RedmineID: #175153]
		- 20221115@Danny: get tier rebate rate by FromDate input [RedmineID: #180445]
		- 20221024@Danny: MG-RNG - Tournament Prize [#176986]
		- 20221213@Danny: Change fomular Calculate rebate base on Licensee Fee [RedmineID: #181546]
		- 20221226@Danny: Integrate Player tips [#180703]
		- 20230111@Danny: Discount group - Support many sportsbook charge rates [RedmineID: #169160]
		- 20230519@Danny: New commercial terms for 12B [RedmineID: #186543]
		- 20231005@Danny: Change charge rate and tier rebate for Alek group from Oct 2023 [RedmineID: #194561]
		- 20231110@Danny: Adjust fomular tier rebate [RedmineID: #196685]
		- 20230223@Danny: Integrate Casino promotion [#194808]
		- 20240321@Danny: Change fomular AGC Deduct prepayment [#197268]
		- 20240520@Danny: support closed status invoice [RedmineID: #194603]
		- 20240612@Danny: return figures with 2 decimal digits [RedmineID: #206415]
		- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
		- 20241008@Danny: return extra amount figures with 4 decimal digits  [RedmineID: #211925]
		- 20240918@Sally: Support Odds Boost Voucher [#209884]
		- 20240625@Danny: Rebate on Licensing Fee for specific currencies [RedmineID: #206143]
		- 20240625@Danny: Rebate for 3rd product is incorrect issue [RedmineID: #214929]

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
			10 = Promotion
			11 = Licensee Winloss
			13 = Casino promotion
			14 = Odds Boost Adjustment
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FromDate_Setting	DATETIME
	DECLARE @ToDate_Setting		DATETIME
	DECLARE @ProductCodes_org   VARCHAR(MAX)

	SELECT @ProductCodes_org = @ProductCodes

	IF @ToDate > CONVERT(DATE, GETDATE())
		SET @ToDate = CONVERT(DATE, GETDATE())

	IF @IsUsePreviousSetting = 1 -- Hard code to get 09-2023 setting (Alek group)
	BEGIN
		SELECT @FromDate_Setting = '2023-09-01'
		SELECT @ToDate_Setting = '2023-09-30'
	END

	ELSE 
	BEGIN
		SELECT @FromDate_Setting =  @FromDate
		SELECT @ToDate_Setting = @ToDate
	END

	-- Licensee : N8B, N8G 
	DECLARE @ExcludeCompareDiscountAndFee_PartyList TABLE (PartyId INT)
	INSERT INTO @ExcludeCompareDiscountAndFee_PartyList(PartyId)
	SELECT PartyId FROM dbo.OAS_Party WITH (NOLOCK) WHERE PartyName IN ('Bwing (N8B)','Goal123 (N8G)')

	DECLARE @CutOff_RebateOnLicfee  DATETIME = '2022-11-01'
	DECLARE @CutOff_TierRebate  DATETIME = '2023-10-01'

	DECLARE @ExchangeTerm_CutOffDate	SMALLDATETIME
	SELECT @ExchangeTerm_CutOffDate = f.CutoffDate FROM dbo.LA_f_GetCutOffDate() f WHERE f.TypeName = 'ExchangeTerms'
	
	-- Get Product List
	CREATE TABLE #Products (ProductId INT, ProductName VARCHAR(50), ProductCode VARCHAR(10), IsSelected BIT)
	INSERT INTO #Products (ProductId, ProductName, ProductCode, IsSelected)
	SELECT ProductId, ProductName, ProductPrefix, 1
	FROM dbo.LA_f_Products3rd(@ProductCodes)
	WHERE ProductId NOT IN (16, 37, 74)

	IF EXISTS (SELECT 1 FROM #Products WHERE ProductId = 0) OR EXISTS (SELECT 1 FROM STRING_SPLIT(@ProductCodes_org,',') WHERE value = 'SPR(CS)')
		INSERT INTO #Products (ProductId, ProductName, ProductCode, IsSelected)
		VALUES (37, 'Saba Promotion', 'SPR', 1)

	IF EXISTS (SELECT 1 FROM #Products WHERE ProductId = 0)
		INSERT INTO #Products (ProductId, ProductName, ProductCode, IsSelected)
		VALUES (74, 'Player Tips', 'TIP', 1)


	-- Get Party List
	CREATE TABLE #PartyList (PartyId INT, LicenseeId INT, BaseCurrencyId INT, IsDeposit BIT, IsSelected BIT)
	INSERT INTO #PartyList (PartyId, IsSelected)
	SELECT DISTINCT value, 1 FROM STRING_SPLIT (@PartyIds, ',')

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

	-- Insert parties/products with same discount/tier rebate group
	DECLARE @DiscountGroup TABLE (PartyId INT, ProductId INT)
	IF @IsUsePreviousSetting = 0
	BEGIN
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
				
				AND a.DiscountGroupId = da.DiscountGroupId
		)
	END
	ELSE
	BEGIN
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
			WHERE dh.FromDate <= @ToDate_Setting AND dh.ToDate >= @FromDate_Setting
				AND a.DiscountGroupId = da.DiscountGroupId 
				)
	END

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

	IF @IsUsePreviousSetting = 0
	BEGIN
		INSERT INTO @PartyChargeInfo (ChargeId, PartyId, LicenseeId, ProductId, FromDate, ToDate, ChargeType, BettypeRef, Rate)
		SELECT ChargeId, PartyId, LicenseeId, ProductId, FromDate, ToDate, ChargeType
			,CASE
				WHEN ProductId = 11 AND ChargeType = 12 THEN 1706 -- GD Tip
				WHEN ProductId = 39 AND ChargeType = 12 THEN 3007 -- SA Tip
				ELSE -1 END
			,CASE WHEN IsDeposit = 1 OR ProductId = 0 THEN DI_Rate ELSE 0 END -- Credit Rate/Fee = 0 (Exclude SB)
		FROM dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, @ProductCodes)
	END
	ELSE -- Cheat Alek group from to.....
	BEGIN
		INSERT INTO @PartyChargeInfo (ChargeId, PartyId, LicenseeId, ProductId, FromDate, ToDate, ChargeType, BettypeRef, Rate)
		SELECT ChargeId, PartyId, LicenseeId, ProductId, @FromDate, @ToDate, ChargeType -- Cheat get old setting 
			,CASE
				WHEN ProductId = 11 AND ChargeType = 12 THEN 1706 -- GD Tip
				WHEN ProductId = 39 AND ChargeType = 12 THEN 3007 -- SA Tip
				ELSE -1 END
			,CASE WHEN IsDeposit = 1 OR ProductId = 0 THEN DI_Rate ELSE 0 END -- Credit Rate/Fee = 0 (Exclude SB)
		FROM dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate_Setting, @ToDate_Setting, @ProductCodes)
	END

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
		,Promotion MONEY DEFAULT(0), CasinoPromotion MONEY DEFAULT(0)
		,FullOddsSpreadAmount MONEY DEFAULT(0)
		,OddsBoostBonus MONEY DEFAULT(0)
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
		AND r.Currency NOT IN (SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
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
			,SUM(CASE WHEN ProductId = 0 THEN ISNULL(ValidBetAmount,0) ELSE 0 END) AS ValidBetAmount
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
		WHERE rptDate BETWEEN @FromDate AND @ToDate
			AND StatusId NOT IN (-1, 101, 102, 103)
			AND CustomerCategory NOT IN (27, 28)
			AND CurrencyId NOT IN (SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
			AND ProductId <> 25 -- CO
		GROUP BY rptDate, SiteId, ProductId, CurrencyId, Bettype, CASE WHEN ISNULL(TicketType, 0) = 2 THEN 2 ELSE 0 END
		UNION SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL -- sum first
	)
	INSERT INTO #TempData (rptDate, LicenseeId, ProductId, CurrencyId, BettypeRef, MemberWL, MemberComm, AgentWL, AgentComm
		,Tips, Contribution, JackpotPrize, Prize, LuckyDraw, Bonus, OddsSpread, FreeBets, PayOut, CommShare, CashInShare, Betcount, Promotion, CasinoPromotion
		,FullOddsSpreadAmount, OddsBoostBonus)
	SELECT r.rptDate, r.SiteId, g.GroupProductId, r.CurrencyId
		,CASE WHEN r.Bettype IN (901, 1706, 3007, 17005, 17006) THEN r.Bettype ELSE -1 END
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
		,SUM(CASE WHEN b.TypeId = 8 THEN MemberWL ELSE 0 END) AS Promotion
		,SUM(CASE WHEN b.TypeId = 10 THEN MemberWL ELSE 0 END) AS CasinoPromotion
		,SUM(CASE WHEN b.TypeId = 7 THEN r.ValidBetAmount ELSE 0 END) AS FullOddsSpreadAmount 
		,SUM(CASE WHEN b.TypeId = 11 THEN r.ValidBetAmount ELSE 0 END) AS OddsBoostBonus -- 11: Odds Boost Adjustment
	FROM CTE_tempData r
		INNER JOIN @Products g ON r.ProductId = g.ProductId AND r.rptDate BETWEEN g.FromDate AND g.ToDate
		LEFT JOIN dbo.LA_f_GroupBettype() b ON r.Bettype = b.Bettype
	GROUP BY r.rptDate, r.SiteId, g.GroupProductId, r.CurrencyId
		,CASE WHEN r.Bettype IN (901, 1706, 3007, 17005, 17006) THEN r.Bettype ELSE -1 END

	CREATE TABLE #tmpResult (rptDate DATE, PartyId INT, ProductId INT, CurrencyId INT
		,GrossLicenseeAmount MONEY, LicenseeWL MONEY, LicenseeAmount MONEY, ExtraAmount MONEY DEFAULT(0), OddsSpread MONEY
		,Contribution MONEY, JackpotPrize MONEY, Prize MONEY, Bonus MONEY, LuckyDraw MONEY, FreeBets MONEY
		,ContributionDiscount MONEY, BasedLicenseeWL MONEY, BasedLicenseeAmount MONEY, BasedOddsSpread MONEY, BetCount INT, Promotion MONEY
		,FullOddsSpreadAmount MONEY, BasedFullOddsSpreadAmount MONEY, OddsBoostBonus MONEY) -- Based Amount: for get exactly min fee, discount

	INSERT INTO #tmpResult (rptDate, PartyId, ProductId, CurrencyId, GrossLicenseeAmount, LicenseeWL, LicenseeAmount, ExtraAmount
		,OddsSpread, Contribution, JackpotPrize, Prize, Bonus, LuckyDraw, FreeBets, ContributionDiscount, BasedLicenseeWL, BasedLicenseeAmount, BasedOddsSpread, BetCount, Promotion	
		,FullOddsSpreadAmount, BasedFullOddsSpreadAmount, OddsBoostBonus)
	SELECT t.rptDate, pl.PartyId, t.ProductId, t.CurrencyId
		,SUM((CASE
				WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
				WHEN t.BettypeRef IN (1706, 3007) THEN -t.Tips * ISNULL(cr.Rate, p.Rate)
				WHEN t.ProductId = 3 THEN -(t.MemberWL + t.AgentComm)
				WHEN (t.ProductId = 15 AND cp.LicenseeId IS NULL) OR (t.ProductId <> 15 AND p.LicenseeId IS NULL) THEN 0
				WHEN t.ProductId = 15 THEN t.PayOut - t.CommShare * cp.CommShareRate - t.CashInShare * cp.CashInShareRate
				WHEN t.ProductId = 31 THEN  CASE WHEN @FromDate < @ExchangeTerm_CutOffDate THEN -t.MemberWL * ISNULL(cr.Rate, p.Rate) - (t.AgentComm + t.MemberComm) ELSE  -(t.MemberWL+t.MemberComm) * ISNULL(cr.Rate, p.Rate) END
				ELSE (-t.MemberWL 
						+ (CASE WHEN p.LicenseeId IS NULL THEN 0
								WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
							ELSE t.OddsBoostBonus END
						)
					 )* ISNULL(cr.Rate, p.Rate)
				+ t.PayOut + t.Contribution - t.JackpotPrize - t.Prize - t.Bonus - t.FreeBets - t.Promotion -LuckyDraw END
			) * e.Rate
		) AS GrossLicenseeAmount
		,SUM((-t.MemberWL 							
				 + (CASE WHEN p.LicenseeId IS NULL THEN 0
						 WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
					ELSE t.OddsBoostBonus END
				 )
			)* e.Rate
		) AS LicenseeWL 
		,SUM((CASE
				WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
				WHEN t.BettypeRef IN (1706, 3007) THEN 0
				WHEN t.ProductId = 3 THEN -(t.MemberWL + t.AgentComm)
				WHEN (t.ProductId = 15 AND cp.LicenseeId IS NULL) OR (t.ProductId <> 15 AND p.LicenseeId IS NULL) THEN 0
				WHEN t.ProductId = 15 THEN t.PayOut - t.CommShare * cp.CommShareRate - t.CashInShare * cp.CashInShareRate
				WHEN t.ProductId = 31 THEN  CASE WHEN @FromDate < @ExchangeTerm_CutOffDate THEN -t.MemberWL * ISNULL(cr.Rate, p.Rate) - (t.AgentComm + t.MemberComm) ELSE  -(t.MemberWL+t.MemberComm) * ISNULL(cr.Rate, p.Rate) END
				ELSE (-t.MemberWL 
						+ (CASE WHEN p.LicenseeId IS NULL THEN 0
								WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
							ELSE t.OddsBoostBonus END)
						- t.Contribution
					) * ISNULL(cr.Rate, p.Rate) 
					+ t.PayOut END		
		) * e.Rate) AS LicenseeAmount -- ServiceFee
		,SUM(CASE
				WHEN p.LicenseeId IS NULL THEN 0
				WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
				WHEN t.BettypeRef IN (1706, 3007) THEN -t.Tips * ISNULL(cr.Rate, p.Rate)
				ELSE (t.Contribution - t.JackpotPrize - t.Prize - t.Bonus - t.FreeBets -t.Promotion - LuckyDraw) END * e.Rate
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
		,SUM(-t.MemberWL 							
				 + (CASE WHEN p.LicenseeId IS NULL THEN 0
						 WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
					ELSE t.OddsBoostBonus END
				 )
		) AS BasedLicenseeWL
		,SUM(CASE
				WHEN t.BettypeRef IN (1706, 3007) THEN 0
				WHEN t.ProductId = 3 THEN -(t.MemberWL + t.AgentComm)
				WHEN (t.ProductId = 15 AND cp.LicenseeId IS NULL) OR (t.ProductId <> 15 AND p.LicenseeId IS NULL) THEN 0
				WHEN t.ProductId = 15 THEN t.PayOut - t.CommShare * cp.CommShareRate - t.CashInShare * cp.CashInShareRate
				ELSE (-t.MemberWL 
							+ (CASE WHEN p.LicenseeId IS NULL THEN 0
									WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
								ELSE t.OddsBoostBonus END)
							- t.Contribution 
			) * ISNULL(cr.Rate, p.Rate) + t.PayOut END
		) AS BasedLicenseeAmount
		,SUM(CASE
				WHEN p.LicenseeId IS NULL THEN 0
				WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
				ELSE t.OddsSpread END
		) AS BasedOddsSpread
		,SUM(t.BetCount) AS BetCount
		,SUM(t.Promotion * e.Rate) AS Promotion
		,SUM(CASE WHEN p.LicenseeId IS NULL THEN 0
						 WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
					ELSE t.FullOddsSpreadAmount END * e.Rate
		) AS FullOddsSpreadAmount 
		,SUM(CASE WHEN p.LicenseeId IS NULL THEN 0
						 WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
					ELSE t.FullOddsSpreadAmount END 
		) AS BasedFullOddsSpreadAmount
		,SUM(CASE
				WHEN p.LicenseeId IS NULL THEN 0
				WHEN pl.IsDeposit = 0 AND t.ProductId <> 0 THEN 0
				ELSE t.OddsBoostBonus END * e.Rate
		) AS OddsBoostBonus
	FROM #TempData t
		INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND e.BaseCurrencyId = 0
		INNER JOIN #PartyList pl ON t.LicenseeId = pl.LicenseeId
		LEFT JOIN @CBChargeRate cp ON t.LicenseeId = cp.LicenseeId AND t.ProductId = 15 AND t.rptDate = cp.rptDate
		LEFT JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.ProductId = p.ProductId AND t.BettypeRef = p.BettypeRef AND t.rptDate BETWEEN p.FromDate AND p.ToDate
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = p.ChargeId AND t.CurrencyId = cr.CurrencyId
	WHERE t.ProductId NOT IN (13, 37, 74)
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
	IF EXISTS (SELECT TOP 1 1 FROM #Products WHERE ProductId = 37) 
	BEGIN
		IF EXISTS (SELECT 1 FROM STRING_SPLIT(@ProductCodes_org,',') WHERE value = 'SB')
			INSERT INTO #tmpResult (rptDate, PartyId, ProductId, CurrencyId, GrossLicenseeAmount, LicenseeAmount, BasedLicenseeAmount, ExtraAmount, BetCount)
			SELECT t.rptDate, p.PartyId, 37, t.CurrencyId
				,SUM(CASE WHEN t.BettypeRef = 17005 THEN t.AgentWL ELSE t.MemberWL END * e.Rate) AS GrossLicenseeAmount
				,SUM(CASE WHEN t.BettypeRef = 17005 THEN 0 ELSE t.MemberWL END * e.Rate) AS LicenseeAmount
				,SUM(CASE WHEN t.BettypeRef = 17005 THEN 0 ELSE t.MemberWL END) AS BasedLicenseeAmount
				,SUM(CASE WHEN t.BettypeRef = 17005 THEN t.AgentWL ELSE 0 END * e.Rate) AS ExtraAmount
				,SUM(t.BetCount) AS BetCount
			FROM #TempData t
				INNER JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId = 0
				INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND e.BaseCurrencyId = 0
			WHERE t.ProductId = 37 AND t.BettypeRef <> 17006
			GROUP BY t.rptDate, p.PartyId, t.CurrencyId

		-- Casino Promotion -- -37
		IF EXISTS (SELECT 1 FROM STRING_SPLIT(@ProductCodes_org,',') WHERE value = 'SPR(CS)')
			INSERT INTO #tmpResult (rptDate, PartyId, ProductId, CurrencyId, GrossLicenseeAmount, LicenseeAmount, BasedLicenseeAmount, ExtraAmount, BetCount)
			SELECT t.rptDate, p.PartyId, -37, t.CurrencyId
				,SUM(CASE WHEN t.BettypeRef = 17006 THEN t.AgentWL ELSE t.MemberWL END * e.Rate) AS GrossLicenseeAmount
				,SUM(CASE WHEN t.BettypeRef = 17006 THEN 0 ELSE t.MemberWL END * e.Rate) AS LicenseeAmount
				,SUM(CASE WHEN t.BettypeRef = 17006 THEN 0 ELSE t.MemberWL END) AS BasedLicenseeAmount
				,SUM(CASE WHEN t.BettypeRef = 17006 THEN t.CasinoPromotion ELSE 0 END * e.Rate) AS ExtraAmount
				,SUM(t.BetCount) AS BetCount
			FROM #TempData t
				INNER JOIN #PartyList p ON t.LicenseeId = p.LicenseeId -- AND t.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId = 0
				INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND e.BaseCurrencyId = 0
			WHERE t.ProductId = 37 AND t.BettypeRef = 17006
			GROUP BY t.rptDate, p.PartyId, t.CurrencyId
	END

	-- Player tips (share between House And Licensee) ExtraAmount => Tips sharing (house)
	INSERT INTO #tmpResult (rptDate, PartyId, ProductId, CurrencyId, GrossLicenseeAmount, LicenseeAmount, BasedLicenseeAmount, ExtraAmount, BetCount)
	SELECT t.rptDate, p.PartyId, 74, t.CurrencyId
		,SUM(t.AgentWL  * e.Rate) AS GrossLicenseeAmount
		,SUM(t.AgentWL  * e.Rate) AS LicenseeAmount
		,SUM(t.AgentWL) AS BasedLicenseeAmount
		,SUM((-t.MemberWL - t.AgentWL) * e.Rate) AS ExtraAmount
		,SUM(t.BetCount) AS BetCount
	FROM #TempData t
		INNER JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId = 0
		INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND e.BaseCurrencyId = 0
	WHERE t.ProductId = 74
	GROUP BY t.rptDate, p.PartyId, t.CurrencyId

	IF ISNULL(@Currencies, '') <> ''
		DELETE #tmpResult WHERE ',' + @Currencies + ',' NOT LIKE '%,' + CONVERT(VARCHAR(20), CurrencyId) + ',%'

	UPDATE t
	SET t.BasedLicenseeWL = t.BasedLicenseeWL * e.Rate
		,t.BasedOddsSpread = t.BasedOddsSpread * e.Rate
		,t.BasedLicenseeAmount = t.BasedLicenseeAmount * e.Rate
		,t.BasedFullOddsSpreadAmount = t.BasedFullOddsSpreadAmount * e.Rate
	FROM #tmpResult t
		INNER JOIN (SELECT DISTINCT PartyId, BaseCurrencyId FROM #PartyList) pl ON t.PartyId = pl.PartyId
		INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND pl.BaseCurrencyId = e.BaseCurrencyId

	DELETE #Exchange WHERE BaseCurrencyId <> 0

	-- Include OddsSpread into Licensing Fee if value is positive
	UPDATE t
	SET t.GrossLicenseeAmount	= t.GrossLicenseeAmount + CASE WHEN r.BasedOddsSpread <= 0 THEN 0 ELSE t.OddsSpread END
		,t.LicenseeAmount		= t.LicenseeAmount		+ CASE WHEN r.BasedOddsSpread <= 0 THEN 0 ELSE t.OddsSpread END
		,t.BasedLicenseeAmount	= t.BasedLicenseeAmount + CASE WHEN r.BasedOddsSpread <= 0 THEN 0 ELSE t.BasedOddsSpread END
		,t.LicenseeWL			= t.LicenseeWL			+ CASE WHEN r.BasedOddsSpread <= 0 THEN 0 ELSE t.FullOddsSpreadAmount END
		,t.BasedLicenseeWL		= t.BasedLicenseeWL		+ CASE WHEN r.BasedOddsSpread <= 0 THEN 0 ELSE t.BasedFullOddsSpreadAmount END -- LicenseeWL Orig (Before Boost Odds) = [LicenseeWL After Odds Booost + FullOddsSpreadAmount + Full OddsBoostBonus]
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
		CREATE TABLE #tmpDiscountGroup 
		(
			DiscountGroupId		SMALLINT
			,DiscountGroupType	TINYINT 
			,BaseCurrencyId		INT
			,PartyId			INT
			,Remark				NVARCHAR(4000)
			,IsApplyDiscount	BIT
			,IsSpecialTreatment BIT
			,ProductId			INT
			,CalculationType	TINYINT
			,CurrencyId			INT
			,CurrencyCalculationType TINYINT
			,DiscountRate		FLOAT DEFAULT (0)
			,ChargeRateByCurrency  FLOAT DEFAULT (0))

		IF @IsUsePreviousSetting = 0
		BEGIN
			INSERT INTO #tmpDiscountGroup (DiscountGroupId, DiscountGroupType, BaseCurrencyId, PartyId, Remark, IsApplyDiscount, IsSpecialTreatment, ProductId, CalculationType, CurrencyId, CurrencyCalculationType)
			SELECT DiscountGroupId, DiscountGroupType, BaseCurrencyId, PartyId, Remark, IsApplyDiscount, IsSpecialTreatment, ProductId, CalculationType, CurrencyId, CurrencyCalculationType
			FROM (
				SELECT h.DiscountGroupId, h.DiscountGroupType, h.CurrencyId AS BaseCurrencyId, a.PartyId, a.IsApplyDiscount, a.IsSpecialTreatment, p.ProductId, p.CalculationType, c.CurrencyId, c.CalculationType AS CurrencyCalculationType
					,CASE WHEN h.FromDate < @F_Date THEN @F_Date ELSE h.FromDate END AS FromDate
					,CASE WHEN h.ToDate > @T_Date THEN @T_Date ELSE h.ToDate END AS ToDate
					,CASE WHEN h.DiscountGroupType IN (2, 12, 22, 32) THEN h.Remark ELSE a.Remark END AS Remark
					,ROW_NUMBER() OVER(PARTITION BY a.PartyId, p.ProductId, c.CurrencyId, CASE WHEN h.DiscountGroupType IN (2, 12, 22, 32) THEN h.DiscountGroupType ELSE 1 END ORDER BY h.ToDate DESC) AS RN
				FROM #PartyList pl
					INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON pl.PartyId = a.PartyId
					INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
					INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON a.DiscountGroupId = p.DiscountGroupId
					LEFT JOIN dbo.LA_DiscountGroupCurrency c WITH (NOLOCK) ON a.DiscountGroupId = c.DiscountGroupId AND a.PartyId = c.PartyId
				WHERE h.FromDate < @T_Date AND h.ToDate >= @F_Date
					AND (h.DiscountGroupType IN (2, 12, 22, 32) OR c.DiscountGroupId IS NOT NULL)
					AND p.ProductId NOT IN (37, 74)
			) t
			WHERE RN = 1
		END
		ELSE -- Cheat Alek group from to.....
		BEGIN
			DECLARE @F_Date_setting DATE = @FromDate_Setting, @T_Date_setting DATE = @ToDate_Setting

			INSERT INTO #tmpDiscountGroup (DiscountGroupId, DiscountGroupType, BaseCurrencyId, PartyId, Remark, IsApplyDiscount, IsSpecialTreatment, ProductId, CalculationType, CurrencyId, CurrencyCalculationType)
			SELECT DiscountGroupId, DiscountGroupType, BaseCurrencyId, PartyId, Remark, IsApplyDiscount, IsSpecialTreatment, ProductId, CalculationType, CurrencyId, CurrencyCalculationType
			FROM (
				SELECT h.DiscountGroupId, h.DiscountGroupType, h.CurrencyId AS BaseCurrencyId, a.PartyId, a.IsApplyDiscount, a.IsSpecialTreatment, p.ProductId, p.CalculationType, c.CurrencyId, c.CalculationType AS CurrencyCalculationType
					,CASE WHEN h.FromDate < @F_Date THEN @F_Date ELSE h.FromDate END AS FromDate
					,CASE WHEN h.ToDate > @T_Date THEN @T_Date ELSE h.ToDate END AS ToDate
					,CASE WHEN h.DiscountGroupType IN (2, 12, 22) THEN h.Remark ELSE a.Remark END AS Remark
					,ROW_NUMBER() OVER(PARTITION BY a.PartyId, p.ProductId, c.CurrencyId, CASE WHEN h.DiscountGroupType IN (2, 12, 22) THEN h.DiscountGroupType ELSE 1 END ORDER BY h.ToDate DESC) AS RN
				FROM #PartyList pl
					INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON pl.PartyId = a.PartyId
					INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
					INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON a.DiscountGroupId = p.DiscountGroupId
					LEFT JOIN dbo.LA_DiscountGroupCurrency c WITH (NOLOCK) ON a.DiscountGroupId = c.DiscountGroupId AND a.PartyId = c.PartyId
				WHERE
				    ( h.FromDate < @T_Date_setting AND h.ToDate >= @F_Date_setting
					AND (h.DiscountGroupType IN (2, 22) OR c.DiscountGroupId IS NOT NULL)
					AND p.ProductId NOT IN (37, 74)
					) OR
					(
						 h.FromDate < @T_Date AND h.ToDate >= @F_Date
					AND (h.DiscountGroupType = 12 OR c.DiscountGroupId IS NOT NULL)
					AND p.ProductId NOT IN (37, 74)
					)
			) t
			WHERE RN = 1
		END

		DECLARE @tmpResult TABLE (PartyId INT, ProductId INT, GroupMinFeeId INT, GroupId INT, IsPrimary BIT, FeeTypeId TINYINT
			,ProrateMinFee MONEY, SecondaryLicensingFee MONEY, NonMinFee MONEY, LicensingFee MONEY, LicenseeWL MONEY
			,BasedProrateMinFee MONEY, BasedSecondaryLicensingFee MONEY, BasedNonMinFee MONEY, BasedLicensingFee MONEY, BasedLicenseeWL MONEY
			,WLToDiscount MONEY, Discount MONEY DEFAULT(0)
			,GrossLicensingFee MONEY, ExtraAmount MONEY, IsWaived BIT DEFAULT(0), IsChargedByMinFee BIT DEFAULT(0), OddsBoostBonus MONEY)
		
		INSERT INTO @tmpResult (PartyId, ProductId, GroupMinFeeId, GroupId, IsPrimary, FeeTypeId
			,ProrateMinFee, SecondaryLicensingFee, NonMinFee, LicensingFee, LicenseeWL
			,BasedProrateMinFee, BasedSecondaryLicensingFee, BasedNonMinFee, BasedLicensingFee, BasedLicenseeWL
			,WLToDiscount, GrossLicensingFee, ExtraAmount,OddsBoostBonus)
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
			,SUM(ISNULL(r.OddsBoostBonus, 0)) AS OddsBoostBonus
		FROM #tmpResult r
			FULL OUTER JOIN #tmpMinFee t ON r.PartyId = t.PartyId AND r.ProductId = t.ProductId AND r.rptDate BETWEEN t.FromDate AND t.ToDate
			LEFT JOIN #tmpDiscountGroup d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId
											AND (d.CurrencyId = 0 OR r.CurrencyId = d.CurrencyId)
											AND (d.IsSpecialTreatment = 0 OR r.CurrencyId <> 51)
											AND d.DiscountGroupType IN (3, 13)
											AND d.CurrencyCalculationType IN (2, 3) -- apply discount
		GROUP BY ISNULL(r.PartyId, t.PartyId), ISNULL(r.ProductId, t.ProductId), t.GroupMinFeeId, t.GroupId, t.IsPrimary, t.FeeTypeId, t.FromDate, t.ToDate

		DECLARE @tmpWLToDiscountByCurrency TABLE (
			PartyId INT, 
			ProductId INT, 
			WLToDiscount MONEY, 
			CurrencyID INT, 
			Discount MONEY DEFAULT(0), 
			DiscountRate  FLOAT DEFAULT (0), 
			LicenseeAmount MONEY, 
			ChargeRateByCurrency MONEY DEFAULT(0),
			GroupMinFeeId INT, 
			GroupId INT, 
			IsPrimary BIT, 
			FeeTypeId TINYINT
		)

		INSERT INTO @tmpWLToDiscountByCurrency (PartyId, ProductId, WLToDiscount, CurrencyID, LicenseeAmount, GroupMinFeeId, GroupId, IsPrimary, FeeTypeId)
		SELECT	ISNULL(r.PartyId, t.PartyId) PartyId
				,ISNULL(r.ProductId, t.ProductId) ProductId
				,SUM(CASE WHEN d.PartyId IS NOT NULL THEN ISNULL(r.LicenseeWL, 0) ELSE 0 END) AS WLToDiscount
				,r.CurrencyId
				,SUM(r.LicenseeWL)
				,t.GroupMinFeeId, t.GroupId, t.IsPrimary, t.FeeTypeId
		FROM #tmpResult r
			FULL OUTER JOIN  #tmpMinFee t ON r.PartyId = t.PartyId AND r.ProductId = t.ProductId AND r.rptDate BETWEEN t.FromDate AND t.ToDate
			LEFT JOIN #tmpDiscountGroup d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId
											AND (d.CurrencyId = 0 OR r.CurrencyId = d.CurrencyId)
											AND (d.IsSpecialTreatment = 0 OR r.CurrencyId <> 51)
											AND d.DiscountGroupType IN (3, 13)
											AND d.CurrencyCalculationType IN (2, 3) -- apply discount
		GROUP BY ISNULL(r.PartyId, t.PartyId), ISNULL(r.ProductId, t.ProductId), r.CurrencyId, t.GroupMinFeeId, t.GroupId, t.IsPrimary, t.FeeTypeId, t.FromDate, t.ToDate

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
			,LicenseeAmount MONEY, BasedLicenseeAmount MONEY, DiscountRate FLOAT DEFAULT (0), RebateRate FLOAT DEFAULT(0), TierDiffRebate MONEY DEFAULT(0), ChargeRateAfterDiscount FLOAT DEFAULT NULL)
			
		-- Discount before min fee: NOT discount for all currencies
		INSERT INTO @tmpDiscount (DiscountGroupId, DiscountGroupType, BaseCurrencyId, PartyId, Remark, IsApplyDiscount, ProductId, CalculationType, LicenseeAmount, BasedLicenseeAmount)
		SELECT d.DiscountGroupId, d.DiscountGroupType, d.BaseCurrencyId, d.PartyId, d.Remark, d.IsApplyDiscount, d.ProductId, d.CalculationType
			,SUM(CASE WHEN d.DiscountGroupType IN (1, 11) THEN r.LicenseeAmount ELSE r.LicenseeWL END)
			,SUM(CASE WHEN d.DiscountGroupType IN (1, 11) THEN r.BasedLicenseeAmount ELSE r.BasedLicenseeWL END)
		FROM #tmpResult r
			INNER JOIN #tmpDiscountGroup d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId
				AND (d.CurrencyId = 0 OR r.CurrencyId = d.CurrencyId)
				AND (d.IsSpecialTreatment = 0 OR r.CurrencyId <> 51)
		WHERE d.DiscountGroupType IN (1, 3, 11, 13) -- Discount
			AND (d.CurrencyId <> 0 OR d.IsSpecialTreatment = 1) -- NOT all currencies
			AND (d.DiscountGroupType IN (1, 11) OR d.CurrencyCalculationType IN (1, 3))
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
		WHERE d.DiscountGroupType IN (1, 3, 11, 13) -- Discount
		GROUP BY d.DiscountGroupId, d.DiscountGroupType, d.BaseCurrencyId, d.PartyId, d.Remark, d.IsApplyDiscount, d.ProductId, d.CalculationType

		-- Group discount
		UPDATE td
		SET td.DiscountRate = dr.Rate, td.ChargeRateAfterDiscount = dr.ChargeRateAfterDiscount
		FROM @tmpDiscount td
			INNER JOIN (
				SELECT d.DiscountGroupId, d.Rate, d.ChargeRateAfterDiscount
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
		SET td.DiscountRate = dr.Rate, td.ChargeRateAfterDiscount = dr.ChargeRateAfterDiscount
		FROM @tmpDiscount td
			INNER JOIN (
				SELECT d.DiscountGroupId, t.PartyId, d.Rate, d.ChargeRateAfterDiscount
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

		UPDATE td
		SET td.DiscountRate = CASE WHEN (ISNULL(lc.Rate,p.Rate) - t.ChargeRateAfterDiscount) >= 0 THEN ISNULL(lc.Rate,p.Rate) - t.ChargeRateAfterDiscount  ELSE 0 END, td.ChargeRateByCurrency = ISNULL(lc.Rate,p.Rate)
		FROM #tmpDiscountGroup td
		LEFT JOIN @PartyChargeInfo p ON p.ProductId = td.ProductId AND p.PartyId = td.PartyId
		LEFT JOIN LA_ChargeRateByCurrency lc WITH(NOLOCK) ON p.ChargeId = lc.ChargeID AND td.CurrencyId = lc.CurrencyID
		INNER JOIN @tmpDiscount t ON td.DiscountGroupId = t.DiscountGroupId AND t.ChargeRateAfterDiscount >= 0
		WHERE td.DiscountGroupType IN (3, 13) AND td.CurrencyCalculationType IN (2, 3)

		-- Update DiscountRate by Currency
		UPDATE t 
		SET t.DiscountRate = u.DiscountRate
		FROM @tmpWLToDiscountByCurrency t
		INNER JOIN #tmpDiscountGroup u ON t.PartyId = u.PartyId AND t.ProductId = u.ProductId  AND t.CurrencyID = u.CurrencyId AND u.DiscountGroupType IN (3, 13)

		-- Update ChargeRateByCurrency
		UPDATE t 
		SET  t.ChargeRateByCurrency = ISNULL(lc.Rate,p.Rate)
		FROM @tmpWLToDiscountByCurrency t
		LEFT JOIN @PartyChargeInfo p ON p.ProductId = t.ProductId AND p.PartyId = t.PartyId
		LEFT JOIN LA_ChargeRateByCurrency lc WITH(NOLOCK) ON p.ChargeId = lc.ChargeID AND t.CurrencyId = lc.CurrencyID

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
		
		UPDATE r
		SET r.Discount = CASE WHEN x.Discount > 0 THEN x.Discount ELSE 0 END
		FROM @tmpResult r
			INNER JOIN @tmpDiscount d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId 
			OUTER APPLY (
				SELECT TOP 1 t.PartyId
				FROM @tmpResult t
				WHERE t.GroupMinFeeId = r.GroupMinFeeId AND t.FeeTypeId = r.FeeTypeId
					AND t.IsChargedByMinFee = 1 AND t.IsPrimary = 1 AND t.FeeTypeId = 1
					AND t.GroupMinFeeId > 0 AND r.IsPrimary = 0
			) t
			OUTER APPLY (
				SELECT SUM(tc.WLToDiscount * tc.DiscountRate) AS Discount
				FROM @tmpWLToDiscountByCurrency tc
				WHERE tc.PartyId = r.PartyId  
					AND ISNULL(tc.GroupMinFeeId,0) = ISNULL(r.GroupMinFeeId,0) 
					AND ISNULL(tc.GroupId,0) = ISNULL(r.GroupId,0) 
					AND ISNULL(tc.IsPrimary,0) = ISNULL(r.IsPrimary,0)
					AND ISNULL(tc.FeeTypeId,0) = ISNULL(r.FeeTypeId,0)
			) x
		WHERE d.DiscountGroupType IN (3, 13) -- discount on licensee winloss
			AND r.IsChargedByMinFee = 0 -- if licensee is charged by min fee, discount = 0
			AND t.PartyId IS NULL -- if primary is charged by min fee, discount of secondary = 0
			AND d.ChargeRateAfterDiscount >= 0 

	END
	
	DECLARE @Result TABLE
	(
		PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, LicenseeWL MONEY, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
		,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), DiscountType TINYINT
		,TierRebate MONEY, TierRebateRate MONEY, WLRebate MONEY, WLRebateRate MONEY, FeeRebate MONEY, FeeRebateRate MONEY, TotalRebate MONEY, RebateRemark NVARCHAR(4000)
		,ProrateMinFee MONEY, SecondaryLicensingFee MONEY, NonMinFee MONEY, IsGroupMinFee BIT, FeeRebateByCurr MONEY
		,ExtraInfo NVARCHAR(4000)
		,OddsBoostBonus MONEY
	)
	/*
		DiscountType: 0 = no discount, 1 = discount by licensing fee, 2 = discount by licensee winloss
	*/

	IF EXISTS (SELECT 1 FROM STRING_SPLIT(@LicensingFeeTypeIds, ',') WHERE CONVERT(INT, value) = 0) -- Normal Licensing Fee
	BEGIN
		INSERT INTO @Result (PartyId, ProductId, LicensingFeeTypeId, LicenseeWL, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, DiscountType, ProrateMinFee, SecondaryLicensingFee, NonMinFee, IsGroupMinFee, OddsBoostBonus)
		SELECT t.PartyId, t.ProductId, 0 AS LicensingFeeTypeId, t.LicenseeWL, t.GrossLicensingFee, t.LicensingFee, t.ExtraAmount, t.IsChargedByGroupMinFee, t.IsChargedByMinFee
			,CASE WHEN d.DiscountGroupType IN (1, 11) THEN d.Discount ELSE t.Discount END, ISNULL(d.DiscountRate, 0)
			,CASE WHEN ISNULL(d.DiscountRate, 0) + ISNULL(d.ChargeRateAfterDiscount, 0) = 0 THEN '' ELSE ISNULL(d.DiscountRemark, '') END
			,CASE
				WHEN d.DiscountGroupType IN (1, 11) AND d.Discount > 0 THEN 1
				WHEN d.DiscountGroupType IN (3, 13) AND t.Discount > 0 THEN 2
				ELSE 0 END AS DiscountType
			,t.ProrateMinFee, t.SecondaryLicensingFee, t.NonMinFee, t.IsGroupMinFee, OddsBoostBonus
		FROM (
			SELECT r.PartyId, r.ProductId
				,SUM(r.LicenseeWL) AS LicenseeWL
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
				,SUM(ISNULL(r.OddsBoostBonus, 0)) AS OddsBoostBonus
			FROM @tmpResult r
				INNER JOIN #Products pd ON r.ProductId = pd.ProductId AND pd.IsSelected = 1
			GROUP BY r.PartyId, r.ProductId
		) t
			LEFT JOIN (
				SELECT PartyId, ProductId, DiscountGroupType
					,SUM(ISNULL(LicenseeAmount * DiscountRate, 0)) AS Discount
					,MAX(ISNULL(DiscountRate, 0)) AS DiscountRate
					,MAX(ISNULL(Remark, '')) AS DiscountRemark
					,MAX(ISNULL(ChargeRateAfterDiscount, 0)) AS ChargeRateAfterDiscount
				FROM @tmpDiscount
				GROUP BY PartyId, ProductId, DiscountGroupType
			) d ON t.PartyId = d.PartyId AND t.ProductId = d.ProductId

		UPDATE @Result SET Discount = 0, DiscountRate = 0, DiscountRemark = '', DiscountType = 0 
		WHERE	Discount > LicensingFee 
				AND PartyId NOT IN (SELECT x.PartyId FROM @ExcludeCompareDiscountAndFee_PartyList x) -- Exclude  N8B, N8G 

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
					,a.IsAdjustDone = CASE WHEN a.RemaingAmount + t.Discount >= 0 THEN 1 ELSE a.IsAdjustDone END
				FROM @AdjustGroupMinFee a
					CROSS APPLY (
						SELECT TOP 1 t.PartyId, t.Discount FROM @tmpResult t
						WHERE a.GroupMinFeeId = t.GroupMinFeeId AND a.ProductId = t.ProductId
							AND (t.GroupMinFeeId > 0 OR (t.FeeTypeId = 1 AND t.GroupMinFeeId < 0))
						ORDER BY t.Discount DESC, t.IsPrimary DESC
					) t
				WHERE a.IsAdjustDone = 0
					
				UPDATE r
				SET r.Discount = a.tmpDiscount
				FROM @tmpResult r
					INNER JOIN @AdjustGroupMinFee a ON r.PartyId = a.tmpPartyId AND r.ProductId = a.ProductId AND r.GroupMinFeeId = a.GroupMinFeeId
				WHERE r.GroupMinFeeId > 0 OR (r.FeeTypeId = 1 AND r.GroupMinFeeId < 0)
					AND a.IsAdjustDone IS NOT NULL
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

		-- Rebate on Lic WL/Fee
		INSERT INTO @tmpDiscount (DiscountGroupId, DiscountGroupType, PartyId, ProductId, Remark)
		SELECT DiscountGroupId, DiscountGroupType, PartyId, ProductId, Remark FROM #tmpDiscountGroup WHERE DiscountGroupType IN (2, 22)

		-- Tier Rebate
		IF EXISTS (SELECT 1 FROM #tmpDiscountGroup WHERE DiscountGroupType = 12)
		BEGIN
			INSERT INTO @tmpDiscount (DiscountGroupId, DiscountGroupType, BaseCurrencyId, PartyId, ProductId, LicenseeAmount, BasedLicenseeAmount)
			SELECT d.DiscountGroupId, 12, d.BaseCurrencyId, d.PartyId, d.ProductId, SUM(r.LicenseeWL) AS LicenseeWL, SUM(r.BasedLicenseeWL) AS BasedLicenseeWL
			FROM #tmpDiscountGroup d
				INNER JOIN @tmpResult r ON d.PartyId = r.PartyId AND d.ProductId = r.ProductId
			WHERE d.DiscountGroupType = 12
			GROUP BY d.DiscountGroupId, d.BaseCurrencyId, d.PartyId, d.ProductId
			HAVING (SUM(r.LicenseeWL) > 0 AND SUM(r.BasedLicenseeWL) > 0 AND @FromDate <  @CutOff_TierRebate )
					OR (SUM(r.LicensingFee) > 0 AND @FromDate >=  @CutOff_TierRebate)

			BEGIN
				; WITH t AS
				(
				SELECT  t.DiscountGroupId,
						t.ProductId,
						t.PartyId,
						MAX(dd.rate) RebateRate,
						SUM(twl.LicenseeAmount * (twl.ChargeRateByCurrency - ISNULL(twl.DiscountRate, 0) - ISNULL(rd.Rate, 0) - s.Rate) ) AS TierDiffRebate
				FROM @tmpDiscount t
					INNER JOIN (
						SELECT DiscountGroupId, ProductId, FLOOR(SUM(BasedLicenseeAmount)) AS LicenseeWL
						FROM @tmpDiscount
						WHERE DiscountGroupType = 12
						GROUP BY DiscountGroupId, ProductId
					) a ON t.DiscountGroupId = a.DiscountGroupId AND t.ProductId = a.ProductId
					INNER JOIN dbo.LA_f_TierRebateSetting(@FromDate) s ON t.BaseCurrencyId = s.BaseCurrencyId AND a.LicenseeWL BETWEEN s.FromAmount AND s.ToAmount
					INNER JOIN dbo.LA_DiscountGroupDetail dd WITH (NOLOCK) ON t.DiscountGroupId = dd.DiscountGroupId
					INNER JOIN @PartyChargeInfo p ON t.PartyId = p.PartyId AND t.ProductId = p.ProductId AND p.BettypeRef = -1
					LEFT JOIN @tmpDiscount d ON t.PartyId = d.PartyId AND t.ProductId = d.ProductId AND d.DiscountGroupType IN (1, 3, 11, 13)
					LEFT JOIN @tmpDiscount r ON t.PartyId = r.PartyId AND t.ProductId = r.ProductId AND r.DiscountGroupType = 22
					LEFT JOIN dbo.LA_DiscountGroupDetail rd WITH (NOLOCK) ON r.DiscountGroupId = rd.DiscountGroupId
					LEFT JOIN @tmpWLToDiscountByCurrency twl ON t.PartyId = twl.PartyId AND twl.ProductId = t.ProductId
				WHERE t.DiscountGroupType = 12 AND t.LicenseeAmount > 0 AND t.BasedLicenseeAmount > 0
				GROUP BY t.DiscountGroupId, t.ProductId, t.PartyId
				)
				UPDATE  td
				SET td.RebateRate = t.RebateRate,
					td.TierDiffRebate = CASE WHEN t.TierDiffRebate < 0 THEN 0 ELSE t.TierDiffRebate END
				FROM @tmpDiscount td
				INNER JOIN t ON td.DiscountGroupId = t.DiscountGroupId AND td.ProductId = t.ProductId AND td.PartyId = t.PartyId

			END
		END

		-- Rebate on Licensing Fee for some specific currencies
		IF EXISTS (SELECT 1 FROM #tmpDiscountGroup WHERE DiscountGroupType = 32)
		BEGIN
			;WITH data_ AS
			(
				SELECT   tmp.PartyId, 
						tmp.ProductId, 
						tmp.CurrencyId, 
						SUM(ISNULL(tmp.LicenseeAmount,0)) LicenseeAmount,
						SUM(ISNULL(tmp.ExtraAmount,0)) ExtraAmount
				FROM     #tmpResult tmp
				WHERE tmp.ProductID IN (0,37) -- SB, SPR only
				GROUP BY  tmp.PartyId, tmp.ProductId, tmp.CurrencyId
			),t AS
			(
				SELECT tmp.PartyId, 
						tmp.ProductId, 
						tmp.CurrencyId, 
						tmp.LicenseeAmount, 
						tmp.ExtraAmount,
						lgd.Rate AS RebatebyCurrRate,
						ISNULL(d.WLToDiscount,0) * ISNULL(d.DiscountRate,0) AS DiscountByCurr
				FROM data_ tmp
				LEFT JOIN #tmpDiscountGroup td ON tmp.PartyId = td.PartyId 
												AND tmp.CurrencyId = td.CurrencyId 
												AND tmp.ProductId = td.ProductId
												AND td.DiscountGroupType = 32 
				LEFT JOIN LA_DiscountGroupDetail lgd WITH(NOLOCK) ON td.DiscountGroupId = lgd.DiscountGroupId
				LEFT JOIN @tmpWLToDiscountByCurrency d ON tmp.PartyId = d.PartyId
												AND tmp.CurrencyId = d.CurrencyID
												AND tmp.ProductId = d.ProductId
			), figure AS
			(
				SELECT t.PartyId, 
					   MAX(t.RebatebyCurrRate) RebatebyCurrRate,
					   SUM(t.LicenseeAmount) TotalSBfeeByChargeRate,
					   SUM(CASE WHEN t.RebatebyCurrRate <> 0 THEN ISNULL(t.LicenseeAmount,0) ELSE 0 END) SbFeeByRebateSetting,
					   SUM(CASE WHEN t.RebatebyCurrRate <> 0 THEN ISNULL(t.DiscountByCurr,0) ELSE 0 END) SbDiscountByRebateSetting,
					   SUM(CASE WHEN t.RebatebyCurrRate <> 0 THEN ISNULL(t_37.LicenseeAmount,0) ELSE 0 END)  SPRbyRebateSetting,
					   SUM(ISNULL(t_37.ExtraAmount,0)) AS Sponsorship
				FROM  t
				OUTER APPLY (
					SELECT  t_37.*
					FROM t t_37 
					WHERE t.PartyID = t_37.PartyID AND t.CurrencyId = t_37.CurrencyId AND t_37.ProductId = 37
				)t_37
				WHERE t.ProductId = 0 
				GROUP BY t.PartyId
			)
			UPDATE r
			SET r.FeeRebateByCurr =  CASE WHEN r.LicensingFee > 0 THEN 
						CASE WHEN  rs.SbFeeByRebateSetting - CASE WHEN r.Discount > 0 THEN rs.SbDiscountByRebateSetting ELSE 0 END - rs.SPRbyRebateSetting - rs.Sponsorship <= 0 THEN 0 
							 WHEN (rs.SbFeeByRebateSetting - CASE WHEN r.Discount > 0 THEN rs.SbDiscountByRebateSetting ELSE 0 END - rs.SPRbyRebateSetting - rs.Sponsorship)  * RebatebyCurrRate > (r.LicensingFee - r.Discount) THEN r.LicensingFee - r.Discount 
							 ELSE (rs.SbFeeByRebateSetting - CASE WHEN r.Discount > 0 THEN rs.SbDiscountByRebateSetting ELSE 0 END - rs.SPRbyRebateSetting - rs.Sponsorship) * RebatebyCurrRate END ELSE 0 END	
			FROM @Result r
			LEFT JOIN figure rs ON r.PartyId = rs.PartyId 
			WHERE r.ProductID = 0 
		END

		DELETE @tmpDiscount WHERE DiscountGroupType NOT IN (2, 12, 22, 32)

		-- Remove non-selected licensees
		DELETE r
		FROM @Result r
			LEFT JOIN (SELECT DISTINCT PartyId FROM #PartyList WHERE IsSelected = 1) p ON r.PartyId = p.PartyId
		WHERE p.PartyId IS NULL

		-- Update Final Rebate Rate, Amount
		UPDATE r
		SET r.TierRebate = CASE WHEN ISNULL(d.TierDiffRebate, 0) < 0 THEN 0 ELSE ISNULL(d.TierDiffRebate, 0) END
			,r.TierRebateRate = ISNULL(d.TierRebateRate, 0)
			,r.WLRebate = CASE WHEN r.LicenseeWL < 0 THEN 0 ELSE r.LicenseeWL * ISNULL(d.WLRebateRate, 0) END
			,r.WLRebateRate = ISNULL(d.WLRebateRate, 0)
			,r.FeeRebate =  (r.LicensingFee - r.Discount) * ISNULL(d.FeeRebateRate, 0)
			,r.FeeRebateRate = ISNULL(d.FeeRebateRate, 0)
			,r.RebateRemark = d.RebateRemark
		FROM @Result r
			OUTER APPLY (
				SELECT
					SUM(CASE WHEN d.DiscountGroupType = 2 THEN ISNULL(dd.Rate, 0) ELSE 0 END) AS FeeRebateRate
					,SUM(CASE WHEN d.DiscountGroupType = 12 THEN ISNULL(dd.Rate, 0) ELSE 0 END) AS TierRebateRate
					,SUM(CASE WHEN d.DiscountGroupType = 22 THEN ISNULL(dd.Rate, 0) ELSE 0 END) AS WLRebateRate
					,SUM(ISNULL(d.TierDiffRebate, 0)) AS TierDiffRebate
					,MAX(ISNULL(d.Remark, N'')) AS RebateRemark
				FROM @tmpDiscount d
					INNER JOIN dbo.LA_DiscountGroupDetail dd WITH (NOLOCK) ON d.DiscountGroupId = dd.DiscountGroupId
				WHERE r.PartyId = d.PartyId AND r.ProductId = d.ProductId
			) d

		UPDATE r
		SET r.FeeRebate = CASE WHEN @FromDate >= @CutOff_RebateOnLicfee THEN CASE WHEN r.LicensingFee - r.Discount -  ISNULL(t.GrossLicensingFee, 0) - r.OddsBoostBonus < 0
																   THEN 0 ELSE (r.LicensingFee - r.Discount - ISNULL(t.GrossLicensingFee, 0) - r.OddsBoostBonus) * ISNULL(r.FeeRebateRate, 0) END  -- ServiceFee - Discount - SB Promotion - OddsBoostBonus 
								ELSE r.FeeRebate END
			,r.TierRebate = r.TierRebate
							+ CASE WHEN @FromDate < @CutOff_TierRebate THEN
									CASE
										WHEN r.GrossLicensingFee < 0 THEN 0
										WHEN r.GrossLicensingFee - r.Discount - ISNULL(t.GrossLicensingFee, 0) - r.TierRebate - r.WLRebate < 0 THEN 0
										ELSE r.GrossLicensingFee - r.Discount - ISNULL(t.GrossLicensingFee, 0) - r.TierRebate - r.WLRebate
									END 
							  ELSE 
									CASE
										WHEN r.LicensingFee - r.Discount - ISNULL(t.GrossLicensingFee, 0) - r.TierRebate - r.WLRebate - r.OddsBoostBonus < 0 THEN 0
										ELSE r.LicensingFee - r.Discount - ISNULL(t.GrossLicensingFee, 0) - r.TierRebate - r.WLRebate - r.OddsBoostBonus
									END  -- ServiceFee - Discount - SB Promotion - OddsBoostBonus 
							  END* r.TierRebateRate
			,r.TotalRebate = r.WLRebate + ISNULL(r.FeeRebateByCurr,0)
							+ CASE WHEN @FromDate >= @CutOff_RebateOnLicfee THEN CASE WHEN r.LicensingFee - r.Discount -  ISNULL(t.GrossLicensingFee, 0) - r.OddsBoostBonus < 0
																   THEN 0 ELSE (r.LicensingFee - r.Discount - ISNULL(t.GrossLicensingFee, 0) - r.OddsBoostBonus) * ISNULL(r.FeeRebateRate, 0) END
								ELSE r.FeeRebate END
							+ CASE
								WHEN @IncludeTierRebate = 0 THEN 0
								ELSE r.TierRebate
									+ CASE WHEN @FromDate < @CutOff_TierRebate THEN
										CASE
											WHEN r.GrossLicensingFee < 0 THEN 0
											WHEN r.GrossLicensingFee - r.Discount - ISNULL(t.GrossLicensingFee, 0) - r.TierRebate - r.WLRebate < 0 THEN 0
											ELSE r.GrossLicensingFee - r.Discount - ISNULL(t.GrossLicensingFee, 0) - r.TierRebate - r.WLRebate
										END 
									  ELSE 
										CASE
											WHEN r.LicensingFee - r.Discount - ISNULL(t.GrossLicensingFee, 0) - r.TierRebate - r.WLRebate - r.OddsBoostBonus < 0 THEN 0
											ELSE r.LicensingFee - r.Discount - ISNULL(t.GrossLicensingFee, 0) - r.TierRebate - r.WLRebate - r.OddsBoostBonus
										END  -- WLRebate + FeeRebatee + TierRebate
									  END* r.TierRebateRate 
								END 
		FROM @Result r
			LEFT JOIN @Result t ON r.PartyId = t.PartyId AND r.ProductId = 0 AND t.ProductId = 37
	
		-- For no data
		INSERT INTO @Result (
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, WLRebate, WLRebateRate, FeeRebate, FeeRebateRate, TotalRebate, RebateRemark
		)
		SELECT p.PartyId, p.ProductId, 0, 0, 0, 0, 0, 0, 0, 0, '', 0, 0, 0, 0, 0, ''
		FROM (
			SELECT DISTINCT PartyId, ProductId FROM @PartyChargeInfo
			UNION SELECT DISTINCT PartyId, 15 AS ProductId FROM @CBChargeRate
		) p
			INNER JOIN (SELECT DISTINCT PartyId FROM #PartyList WHERE IsSelected = 1) pl ON p.PartyId = pl.PartyId
			INNER JOIN #Products pd ON p.ProductId = pd.ProductId AND pd.IsSelected = 1
			LEFT JOIN @Result r ON p.PartyId = r.PartyId AND p.ProductId = r.ProductId
		WHERE r.PartyId IS NULL
	END

	IF EXISTS (SELECT 1 FROM STRING_SPLIT(@LicensingFeeTypeIds, ',') WHERE CONVERT(INT, value) > 0) -- special bettype
	BEGIN
		IF EXISTS (SELECT TOP 1 1 FROM #Products WHERE ProductId = 37) AND EXISTS (SELECT 1 FROM STRING_SPLIT(@ProductCodes_org,',') WHERE value = 'SPR(CS)')
			INSERT INTO #Products (ProductId, ProductName, ProductCode, IsSelected)
			SELECT -37, 'Casino Promotion', 'SPR(CS)', 1
	

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
				,SUM(ISNULL(t.Promotion, 0)) AS Promotion
				,SUM(ISNULL(t.LicenseeWL, 0)) AS LicenseeWL
				,SUM(ISNULL(CASE WHEN t.ProductId = -37 THEN t.ExtraAmount ELSE 0 END , 0)) AS CasinoPromotion
				,SUM(ISNULL(t.OddsBoostBonus, 0)) AS OddsBoostBonus
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
				UNION ALL SELECT 10, Promotion WHERE Promotion <> 0
				UNION ALL SELECT 11, LicenseeWL
				UNION ALL SELECT 13, CasinoPromotion WHERE CasinoPromotion <> 0
				UNION ALL SELECT 14, OddsBoostBonus WHERE OddsBoostBonus <> 0
			) t
		WHERE ',' + @LicensingFeeTypeIds + ',' LIKE '%,' + CONVERT(VARCHAR(10), t.LicensingFeeTypeId) + ',%'
	END

	IF EXISTS (SELECT 1 FROM STRING_SPLIT(@LicensingFeeTypeIds, ',') WHERE CONVERT(INT, value) < 0) -- deduction
	BEGIN
		DECLARE @Deductions TABLE (PartyId INT, RemainingAMF MONEY, RemainingAGPrepayment MONEY, RemainingPrepayment MONEY)

		;WITH CTE_InvItemTypes AS (
			SELECT CONVERT(SMALLINT, InvItemTypeId) AS InvItemTypeId, CONVERT(VARCHAR(50), 'AdvanceMinFee') AS InvItemTypeName
			FROM (VALUES (3), (5), (7), (21), (46)) AS t (InvItemTypeId) -- AdvanceMinFee (AMF)
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
			WHERE ISNULL(h.StatusId, 0) <> -1 AND h.Environment = @Environment
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
				LEFT JOIN @Result r1 ON r1.PartyId = r.PartyId AND r1.ProductId = r.ProductId AND r1.LicensingFeeTypeId = 1
				LEFT JOIN @Result r2 ON r2.PartyId = r.PartyId AND r2.ProductId = r.ProductId AND r2.LicensingFeeTypeId = 2
				LEFT JOIN @Result r3 ON r3.PartyId = r.PartyId AND r3.ProductId = r.ProductId AND r3.LicensingFeeTypeId = 3
				CROSS APPLY (
					SELECT r.LicensingFee - r.Discount + ISNULL(r1.ExtraAmount,0) - ISNULL(r2.ExtraAmount,0) - ISNULL(r3.ExtraAmount,0) AS DeductedAGPrepayment
					UNION ALL SELECT d.RemainingAGPrepayment
				) t
			WHERE r.ProductId = 10 AND r.LicensingFeeTypeId = 0 -- AG Casino
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

	-- Recalculate fee rebate and total rebate base on Casino promotion value ( Just apply for Product <> 'SB')
	IF EXISTS (SELECT TOP 1 1 FROM @tmpResult WHERE ProductId = -37)
	BEGIN
		DECLARE @RecalFeeRebate TABLE (DiscountGroupId INT, PartyId INT, IsConvertRebateToZero BIT, ProductID INT, FeeRebateRate MONEY)
		
		; WITH u AS
		(
			SELECT td.DiscountGroupId, td.PartyId, td.ProductId , r.FeeRebate, r.TotalRebate, r.GrossLicensingFee, r.FeeRebateRate
			FROM @tmpDiscount td
			INNER JOIN @Result r ON td.PartyId = r.PartyId AND td.ProductId = r.ProductId AND r.LicensingFeeTypeId = 0
			WHERE td.DiscountGroupType = 2 AND td.ProductId <> 0
		), u_Sum AS
		(
			SELECT DiscountGroupId, PartyId, SUM(GrossLicensingFee) AS GrossLicensingFee_NonSport, MAX(FeeRebateRate) FeeRebateRate
			FROM u
			GROUP BY DiscountGroupId, PartyId
		), x AS
		(
			SELECT	u.DiscountGroupId, 
					u.PartyId, 
					u.GrossLicensingFee_NonSport, 
					tr.ExtraAmount AS CasinoPromotion, 
					CASE WHEN u.GrossLicensingFee_NonSport <= ISNULL(tr.ExtraAmount,0) THEN 1 ELSE 0 END IsConvertRebateToZero
			FROM u_Sum u INNER JOIN @tmpResult tr ON u.PartyId = tr.PartyId AND tr.ProductId = -37
		)
		INSERT INTO @RecalFeeRebate (DiscountGroupId, PartyId, IsConvertRebateToZero, ProductID, FeeRebateRate)
		SELECT	x.DiscountGroupId, x.PartyId, x.IsConvertRebateToZero , u.ProductId, u.FeeRebateRate
		FROM	x
		INNER JOIN  u ON x.DiscountGroupId = u.DiscountGroupId AND x.PartyId = u.PartyId

		UPDATE r
		SET r.FeeRebate = 0, r.TotalRebate = r.TotalRebate - r.FeeRebate
		FROM @Result r
		INNER JOIN @RecalFeeRebate f ON r.PartyId = f.PartyId AND r.ProductId = f.ProductID
		WHERE f.IsConvertRebateToZero = 1 AND r.LicensingFeeTypeId = 0

		UPDATE r
		SET r.FeeRebate = -r.ExtraAmount * f.FeeRebateRate,  r.TotalRebate = -r.ExtraAmount * f.FeeRebateRate, r.FeeRebateRate = f.FeeRebateRate
		FROM @Result r
		CROSS APPLY (
			SELECT MAX(f.FeeRebateRate)  FeeRebateRate FROM @RecalFeeRebate f
			WHERE f.PartyId = r.PartyId AND f.IsConvertRebateToZero = 0 
			) f

		WHERE r.LicensingFeeTypeId = 13 AND r.ProductId = -37
	END

	-- Single value discount
	; WITH t AS (
		SELECT x.ProductId ,x.PartyId ,COUNT (DISTINCT DiscountRate) AS rn
		FROM @tmpWLToDiscountByCurrency x 
		WHERE x.ChargeRateByCurrency  <> 0
		GROUP BY 	x.ProductId ,x.PartyId --, x.ChargeRateByCurrency 
	)
	UPDATE r
	SET	r.DiscountRate = x.DiscountRate
	FROM @Result r
	INNER JOIN t ON r.ProductId = t.ProductId AND r.PartyId = t.PartyId AND t.rn = 1
	INNER JOIN  @tmpWLToDiscountByCurrency x  ON x.ProductId = t.ProductId AND t.PartyId = x.PartyId  AND x.DiscountRate <> 0
	WHERE r.LicensingFeeTypeId = 0 AND r.Discount > 0  

	-- Multiple values discount
	; WITH t AS (
		SELECT x.ProductId ,x.PartyId ,COUNT (DISTINCT DiscountRate) AS rn
		FROM @tmpWLToDiscountByCurrency x 
		WHERE x.ChargeRateByCurrency  <> 0
		GROUP BY 	x.ProductId ,x.PartyId 
	)
	UPDATE r
	SET	r.ExtraInfo = ex.ExtraInfo
	FROM @Result r
	INNER JOIN t ON r.ProductId = t.ProductId AND r.PartyId = t.PartyId AND t.rn >= 2
	CROSS APPLY (
	SELECT (
		SELECT DISTINCT CAST(x.DiscountRate AS MONEY) DiscountRate, x.ChargeRateByCurrency
		FROM @tmpWLToDiscountByCurrency x 
		WHERE x.ProductId =t.ProductId AND x.PartyId = t.PartyId  AND x.ChargeRateByCurrency<>0
		FOR JSON PATH ) AS ExtraInfo
	) ex
	WHERE r.LicensingFeeTypeId = 0 AND r.Discount > 0 

	SELECT
		r.PartyId, 
		r.ProductId, 
		LicensingFeeTypeId, 
		ROUND(GrossLicensingFee,2) GrossLicensingFee, 
		ROUND(LicensingFee,2) LicensingFee, 
		ExtraAmount ExtraAmount , IsChargedByGroupMinFee, IsChargedByMinFee,
		ROUND(r.Discount,2) Discount, r.DiscountRate, DiscountRemark, 
		ROUND(ISNULL(TotalRebate,0),2) AS Rebate, 
		ISNULL(ISNULL(NULLIF(WLRebateRate, 0), NULLIF(FeeRebateRate, 0)), 0) AS RebateRate, 
		RebateRemark,
		r.ExtraInfo
	FROM @Result r
	

	DROP TABLE #Exchange
	DROP TABLE #PartyList
	DROP TABLE #Products
	DROP TABLE #TempData
	DROP TABLE #tmpDiscountGroup
	DROP TABLE #tmpMinFee
	DROP TABLE #tmpResult
END
GO
