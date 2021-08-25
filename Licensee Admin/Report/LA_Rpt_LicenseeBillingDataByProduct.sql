/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeBillingDataByProduct]
	@PartyIds			VARCHAR(MAX)
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(10)
	,@LicenseeStatus	VARCHAR(100) = ''
AS

/*
	Created: 20210510@Percy
	DB: DBLIC-bodb_Licensee
	Task: Win Loss by Product - Billing data

	Revisions:
		- 20210510@Percy: Initialize SP [RedmineID: #150878]
		- 20210618@Danny: AE Sexy - Support Lucky Draw [#152141]
		- 20210720@Sophia: Add Saba Promotion - 17005 - Promotion for Licensee [Redmine: #155388]
		- 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
		- 20210823@Danny: filter licensee status from OIC [#159296]

*/

BEGIN
	SET NOCOUNT ON

	DECLARE @BaseCurrencies TABLE (CurrencyId INT, CurrencyName VARCHAR(10))
	INSERT INTO @BaseCurrencies (CurrencyId, CurrencyName)
	EXEC dbo.LA_SelBaseCurrency

	DECLARE @BaseCurrencyId INT
	SELECT  @BaseCurrencyId = CurrencyId FROM @BaseCurrencies WHERE CurrencyName = @BaseCurrencyName

	-- Get Party List
	CREATE TABLE #PartyList (PartyId INT, LicenseeId INT, PartyName VARCHAR(100), BranchName VARCHAR(100), ParentId INT, ParentName VARCHAR(100), GroupMinFeeId INT, IsSelected BIT DEFAULT(0), StatusId TINYINT)
	INSERT INTO #PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC dbo.LA_PartyListSel

	-- Remove credit licensees
	DELETE #PartyList WHERE (PartyId = 999 OR ParentId = 999)

	-- Handle Licensee status
	CREATE TABLE #statusTab  (StatusId TINYINT)
	INSERT INTO #statusTab (StatusId)
	SELECT CAST (val AS TINYINT) FROM dbo.strSplit(@LicenseeStatus,',')

	UPDATE p
	SET    p.StatusId = ISNULL(oic.LicenseeStatusId,0) -- 0: Unrecognized
	FROM  #PartyList p
		INNER JOIN dbo.OAS_Party op   WITH (NOLOCK) ON op.PartyID = p.PartyId
		INNER JOIN dbo.Licensees la WITH (NOLOCK) ON op.OldRefID = la.LicenseeId
		LEFT JOIN  bodb_OIC.dbo.licensee oic WITH (NOLOCK) ON oic.RegisteredLicenseeName = la.LicenseeName									
	
	-- Keep Parties who same group min fee
	DECLARE @GroupMinFeeSetting TABLE (PartyId INT, GroupMinFeeId SMALLINT, IsPrimary BIT)
	INSERT INTO @GroupMinFeeSetting (PartyId, GroupMinFeeId, IsPrimary)
	SELECT PartyId, GroupMinFeeId, IsPrimary
	FROM (
		SELECT a.PartyId, h.GroupMinFeeId, a.IsPrimary, ROW_NUMBER() OVER(PARTITION BY a.PartyID ORDER BY h.ToDate DESC) AS RN
		FROM bodb_Licensee.dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK)
			INNER JOIN bodb_Licensee.dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
		WHERE @FromDate <= h.ToDate AND @ToDate >= h.FromDate
	) r
	WHERE RN = 1

	UPDATE p
	SET p.GroupMinFeeId = ISNULL(g.GroupMinFeeId, -p.PartyId)
	FROM #PartyList p
		LEFT JOIN @GroupMinFeeSetting g ON p.PartyId = g.PartyId
	
	UPDATE #PartyList SET IsSelected = 1 WHERE ',' + @PartyIds + ',' LIKE '%,' + CONVERT(VARCHAR(20), PartyId) + ',%'

	DELETE p
	FROM #PartyList p
	WHERE p.ParentId > 0
		AND p.GroupMinFeeId NOT IN (SELECT t.GroupMinFeeId FROM #PartyList t WHERE t.IsSelected = 1)

	UPDATE p
	SET p.ParentName = REPLACE(pr.PartyName, ' Licensees', ''), p.LicenseeId = pt.OldRefId
	FROM #PartyList p
		INNER JOIN #PartyList pr ON p.ParentId = pr.PartyId
		INNER JOIN dbo.OAS_Party pt WITH (NOLOCK) ON p.PartyId = pt.PartyId
	WHERE p.ParentId <> 0

	DELETE #PartyList WHERE ParentId = 0

	SET @PartyIds = NULL
	SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM #PartyList

	-- Get Product List
	CREATE TABLE #Products (ProductId INT, ProductName VARCHAR(50), ProductCode VARCHAR(10))
	INSERT INTO #Products (ProductId, ProductName, ProductCode)
	SELECT ProductId, ProductName, ProductCode FROM (VALUES (0, 'Sportsbook', 'SB'), (-3, 'Discount', ''), (-2, 'Rebate', ''),  (-1, 'SB Promotion', ''),  (-99, 'Total', '')) t (ProductId, ProductName, ProductCode)
	UNION ALL SELECT ProductId, ProductName, ProductPrefix FROM dbo.Product3rd WITH (NOLOCK) WHERE ProductId NOT IN (16, 37) AND (EndOfSupportDate IS NULL OR EndOfSupportDate >= @FromDate) AND OfferSite IN (0, 2) -- Deposit only

	-- Get Charge Rate
	DECLARE @ProductCode VARCHAR(MAX)
	SELECT  @ProductCode = COALESCE(@ProductCode + ',', '') + ProductCode FROM #Products WHERE ProductId >= 0

	DECLARE @PartyChargeInfo TABLE (ChargeId INT, PartyId INT, LicenseeId INT, ProductId INT, BettypeRef INT, Rate FLOAT, FromDate DATE, ToDate DATE, ChargeType TINYINT)
	INSERT INTO @PartyChargeInfo (ChargeId, PartyId, LicenseeId, ProductId, Rate, FromDate, ToDate, ChargeType, BettypeRef)
	SELECT ChargeId, PartyId, LicenseeId, ProductId, DI_Rate, FromDate, ToDate, ChargeType
		,CASE
			WHEN ProductId = 11 AND ChargeType = 12 THEN 1706 -- GD Tip
			WHEN ProductId = 39 AND ChargeType = 12 THEN 3007 -- SA Tip
			ELSE Bettype END
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCode, 'OA', 1)
	WHERE ProductId <> 1 AND DI_Rate > 0

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
	CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
	INSERT INTO #Exchange (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeId, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	-- Get Win Loss Data
	CREATE TABLE #TempData (
		LicenseeId INT, rptDate DATE, ProductId INT, BettypeRef INT DEFAULT(-1), CurrencyId INT
		,MemberWL MONEY DEFAULT(0), MemberComm MONEY DEFAULT(0), AgentWL MONEY DEFAULT(0), AgentComm MONEY DEFAULT(0)
		,Contribution MONEY DEFAULT(0), JackpotPrize MONEY DEFAULT(0), ExtraAmount MONEY DEFAULT(0), OddsSpread MONEY DEFAULT(0)
		,PayOut MONEY DEFAULT(0), CommShare MONEY DEFAULT(0), CashInShare MONEY DEFAULT(0)
	)

	-- CO
	DECLARE @FDate SMALLDATETIME = @FromDate, @TDate SMALLDATETIME = @ToDate
	INSERT INTO #TempData (LicenseeId, rptDate, ProductId, CurrencyId, MemberWL, PayOut)
	SELECT r.SiteId, CONVERT(DATE, r.WinlostDate) AS rptDate, 25, r.Currency
		,SUM(r.BuyBackAmt) AS MemberWL
		,SUM(r.TicketPayout - r.BuyBackAmt - r.BABuyBackAmt) AS Payout
	FROM bodb_LicenseeReport.dbo.rptLicCashoutSummary r WITH (NOLOCK)
	WHERE r.WinlostDate BETWEEN @FDate AND @TDate								
		AND r.Currency <> 20
		AND r.RoleId = 1 -- Member
	GROUP BY r.SiteId, CONVERT(DATE, r.WinlostDate), r.Currency
	
	INSERT INTO #TempData (LicenseeId, rptDate, ProductId, CurrencyId, BettypeRef, MemberWL, MemberComm, AgentWL, AgentComm, Contribution, JackpotPrize, ExtraAmount, OddsSpread, PayOut, CommShare, CashInShare)
	SELECT r.SiteId, r.rptDate, r.ProductId, r.CurrencyId
		,CASE WHEN r.Bettype IN (901, 1706, 3007, 17005) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END
		,SUM(CASE WHEN (r.ProductId IN (32, 43, 42, 66) AND ISNULL(r.TicketType, 0) = 2) OR r.Bettype IN (902, 903, 904, 999, 4299, 4300, 4297, 4298, 1698, 1699, 1906, 3150, 3898, 3899) THEN 0 ELSE ISNULL(r.MemberWL, 0) END) AS MemberWL
		,SUM(ISNULL(r.CommissionP, 0)) AS MemberComm
		,SUM(ISNULL(r.GrossWL, 0)) AS AgentWL
		,SUM(ISNULL(r.CommissionA, 0)) AS AgentComm
		,SUM(CASE WHEN r.Bettype IN (4297, 1698, 3898) THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS Contribution
		,SUM(CASE WHEN r.Bettype IN (4298, 1699, 3899) THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS JackpotPrize
		,SUM(CASE WHEN r.Bettype IN (4300, 4299, 1906, 3150) OR (r.ProductId IN (32, 43, 42, 66) AND ISNULL(r.TicketType, 0) = 2) THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS ExtraAmount
		,SUM(CASE WHEN r.Bettype = 999 THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS OddsSpread
		,SUM(CASE WHEN r.ProductId = 15 THEN ISNULL(r.Turnover, 0) - ISNULL(r.WinPrizeAmount, 0) - ISNULL(r.CashOutAmount, 0) ELSE 0 END) AS PayOut
		,SUM(CASE WHEN r.ProductId = 15 THEN CASE WHEN ISNULL(r.TicketType, 0) = 0 THEN ISNULL(r.Turnover, 0) ELSE ISNULL(r.ExtraAmount, 0) END ELSE 0 END) AS CommShare
		,SUM(CASE WHEN r.ProductId = 15 OR r.Bettype = 901 THEN ISNULL(r.BuyBackAmount, 0) ELSE 0 END) AS CashInShare
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
		LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.Bettype = r.Bettype
	WHERE r.rptDate BETWEEN @FromDate AND @ToDate
		AND r.StatusId NOT IN (-1, 101, 102, 103)
		AND r.CustomerCategory NOT IN (27, 28)
		AND r.CurrencyId <> 20
		AND r.ProductId <> 25 -- CO
	GROUP BY r.SiteId, r.rptDate, r.CurrencyId, r.ProductId
		,CASE WHEN r.Bettype IN (901, 1706, 3007, 17005) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END

	CREATE TABLE #tmpResult (PartyId INT, ProductId INT, rptDate DATE, LicenseeAmount MONEY, ExtraAmount MONEY DEFAULT(0), IsApplyMinFee BIT DEFAULT (1))
	INSERT INTO #tmpResult (PartyId, ProductId, rptDate, LicenseeAmount, ExtraAmount)
	SELECT pl.PartyId, t.ProductId, t.rptDate
		,SUM((CASE
				WHEN t.BettypeRef IN (1706, 3007) THEN 0
				WHEN t.ProductId = 3 THEN -(t.MemberWL + t.AgentComm)
				WHEN (t.ProductId = 15 AND cp.LicenseeId IS NULL) OR (t.ProductId <> 15 AND p.LicenseeId IS NULL) THEN 0
				WHEN t.ProductId = 15 THEN t.PayOut - t.CommShare * cp.CommShareRate - t.CashInShare * cp.CashInShareRate
				ELSE (-MemberWL - Contribution) * ISNULL(cr.Rate, p.Rate) + PayOut + OddsSpread END
		) * e.Rate) AS LicenseeAmount
		,SUM(CASE
				WHEN p.LicenseeId IS NULL THEN 0
				WHEN t.BettypeRef IN (1706, 3007) THEN -MemberWL * ISNULL(cr.Rate, p.Rate)
				ELSE (Contribution - JackpotPrize - ExtraAmount - CASE WHEN t.ProductId = 31 THEN (AgentComm + MemberComm) ELSE 0 END) * e.Rate END
		) AS ExtraAmount
	FROM #TempData t
		INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate
		INNER JOIN #PartyList pl ON t.LicenseeId = pl.LicenseeId
		LEFT JOIN @CBChargeRate cp ON t.LicenseeId = cp.LicenseeId AND t.ProductId = 15 AND t.rptDate = cp.rptDate
		LEFT JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.ProductId = p.ProductId AND t.BettypeRef = p.BettypeRef AND t.rptDate BETWEEN p.FromDate AND p.ToDate
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = p.ChargeId AND t.CurrencyId = cr.CurrencyId
	WHERE t.ProductId NOT IN (13, 37)
	GROUP BY pl.PartyId, t.ProductId, t.rptDate

	-- BT
	INSERT INTO #tmpResult (PartyId, ProductId, rptDate, LicenseeAmount)
	SELECT p.PartyId, 13, t.rptDate, SUM((CASE WHEN t.BettypeRef = 901 THEN -t.MemberWL WHEN t.ProductId = 13 THEN 0 ELSE t.MemberWL END - t.CashInShare * p.Rate) * e.Rate) AS LicenseeAmount
	FROM #TempData t
		INNER JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId = 13
		INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate
	WHERE t.ProductId IN (0, 3, 13)
	GROUP BY p.PartyId, t.rptDate

	-- SB Promotion
	INSERT INTO #tmpResult (PartyId, ProductId, rptDate, LicenseeAmount)
	SELECT p.PartyId, -1, t.rptDate, SUM(CASE WHEN t.BettypeRef = 17005 THEN t.AgentWL ELSE t.MemberWL END * e.Rate) AS LicenseeAmount
	FROM #TempData t
		INNER JOIN @PartyChargeInfo p ON t.LicenseeId = p.LicenseeId AND t.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId = 0
		INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate
	WHERE t.ProductId = 37
	GROUP BY p.PartyId, t.rptDate

	-- Licensee Min Fee
	BEGIN
		DECLARE @F_Date DATE = @FDate, @T_Date DATE = @TDate
		DECLARE @FirstDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate), 0)
		DECLARE @LastDate DATE = DATEADD(DAY, -1, DATEADD(MONTH, 1, @FirstDate))
		DECLARE @DaysInMonth INT = DATEDIFF(DAY, @FirstDate, @LastDate) + 1

		DECLARE @MinFee TABLE (FeeTypeId TINYINT, GroupMinFeeId SMALLINT, PartyId INT, ProductId INT, IsPrimary BIT, FromDate DATE, ToDate DATE, IndividualMinFee MONEY, ProrateMinFee MONEY, WaivedFee MONEY, LicenseeFee MONEY, ActualFee MONEY)
		INSERT INTO @MinFee (FeeTypeId, GroupMinFeeId, PartyId, ProductId, IsPrimary, IndividualMinFee, FromDate, ToDate)
		SELECT m.FeeTypeId, -m.PartyId, m.PartyId, m.ProductId, 0, m.FeeAmount * ISNULL(e.Rate, 0)
			,CASE WHEN @F_Date > m.FromDate THEN @F_Date ELSE m.FromDate END AS FromDate
			,CASE WHEN @T_Date < m.ToDate THEN @T_Date ELSE m.ToDate END AS ToDate
		FROM dbo.LA_MinFee m WITH (NOLOCK)
			LEFT JOIN #Exchange e ON m.CurrencyId = e.ExchangeId AND e.ExchangeDate = @T_Date
		WHERE m.FeeTypeId IN (1, 2) AND @FirstDate <= m.ToDate AND @LastDate >= m.FromDate

		UPDATE m
		SET m.GroupMinFeeId = g.GroupMinFeeId, m.IsPrimary = g.IsPrimary, m.IndividualMinFee = 0
		FROM @MinFee m
			INNER JOIN @GroupMinFeeSetting g ON m.PartyId = g.PartyId

		INSERT INTO @MinFee (FeeTypeId, GroupMinFeeId, PartyId, ProductId, IsPrimary, IndividualMinFee, FromDate, ToDate)
		SELECT 1, g.GroupMinFeeId, g.PartyId, g.ProductId, g.IsPrimary, 0, g.FromDate, g.ToDate
		FROM (
			SELECT r.GroupMinFeeId, r.PartyId, r.ProductId, r.IsPrimary
				,CASE WHEN @F_Date > r.FromDate THEN @F_Date ELSE r.FromDate END AS FromDate
				,CASE WHEN @T_Date < r.ToDate THEN @T_Date ELSE r.ToDate END AS ToDate
			FROM (
				SELECT a.PartyId, d.ProductId, h.GroupMinFeeId, a.IsPrimary, h.FromDate, h.ToDate, ROW_NUMBER() OVER(PARTITION BY a.PartyId, d.ProductId ORDER BY h.ToDate DESC) AS RN
				FROM dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK)
					INNER JOIN dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
					INNER JOIN dbo.LA_GroupMinFeeDetail d WITH (NOLOCK) ON a.GroupMinFeeId = d.GroupMinFeeId
				WHERE @FromDate <= h.ToDate AND @ToDate >= h.FromDate
			) r
			WHERE r.RN = 1
		) g
			LEFT JOIN @MinFee m ON g.PartyId = m.PartyId
		WHERE m.PartyId IS NULL

		UPDATE t
		SET t.IsApplyMinFee = 0
		FROM #tmpResult t
			INNER JOIN @MinFee m ON t.PartyId = m.PartyId AND t.ProductId = m.ProductId AND t.rptDate BETWEEN m.FromDate AND m.ToDate
		WHERE m.FeeTypeId = 2

		UPDATE m1
		SET m1.ProrateMinFee = (
					(
						SELECT TOP 1 m2.IndividualMinFee
						FROM @MinFee m2
						WHERE m2.FeeTypeId = 1 AND m1.PartyId = m2.PartyId AND m1.ProductId = m2.ProductId
					) / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
			,m1.WaivedFee = ISNULL(
					(
						SELECT SUM(r.LicenseeAmount)
						FROM #tmpResult r
						WHERE m1.PartyId = r.PartyId AND m1.ProductId = r.ProductId AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
					), 0)
		FROM @MinFee m1
		WHERE m1.FeeTypeId = 2

		UPDATE m1
		SET m1.ProrateMinFee = ROUND(
								(m1.IndividualMinFee / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1)
								- ISNULL((
									SELECT SUM(m2.ProrateMinFee)
									FROM @MinFee m2
									WHERE m2.FeeTypeId = 2 AND m1.PartyId = m2.PartyId AND m1.ProductId = m2.ProductId
									), 0)
								, 2)
			,m1.WaivedFee = ISNULL((
									SELECT SUM(m2.WaivedFee)
									FROM @MinFee m2
									WHERE m2.FeeTypeId = 2 AND m1.PartyId = m2.PartyId AND m1.ProductId = m2.ProductId
									HAVING SUM(m2.WaivedFee) > 0
								), 0)
			,m1.LicenseeFee = ISNULL((
									SELECT SUM(r.LicenseeAmount)
									FROM #tmpResult r
									WHERE m1.PartyId = r.PartyId AND m1.ProductId = r.ProductId AND r.IsApplyMinFee = 1 AND r.rptDate BETWEEN m1.FromDate AND m1.ToDate
								), 0)
		FROM @MinFee m1
		WHERE m1.FeeTypeId = 1

		DELETE @MinFee WHERE FeeTypeId = 2

		UPDATE @MinFee SET ActualFee = CASE WHEN LicenseeFee < ProrateMinFee THEN ProrateMinFee ELSE LicenseeFee END + WaivedFee

		-- Group min fee
		DECLARE @GroupMinFee TABLE (GroupMinFeeId INT, ProductId INT, GroupMinFee MONEY DEFAULT(0), AmountToCompany MONEY DEFAULT(0), LicenseeFee MONEY DEFAULT(0), Rebate MONEY DEFAULT(0), Discount MONEY DEFAULT(0))
		INSERT INTO @GroupMinFee (GroupMinFeeId, ProductId, GroupMinFee)
		SELECT t.GroupMinFeeId, t.ProductId, t.MinimumFee * e.Rate
		FROM (
			SELECT GroupMinFeeId, ProductId, CurrencyId, MinimumFee, ROW_NUMBER() OVER(PARTITION BY GroupMinFeeId ORDER BY ToDate DESC) AS RN
			FROM dbo.LA_GroupMinFeeDetail WITH (NOLOCK)
			WHERE @F_Date BETWEEN FromDate AND ToDate
		) t
			INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeId AND e.ExchangeDate = @T_Date
		WHERE t.RN = 1

		-- AmountToCompany
		UPDATE g
		SET g.AmountToCompany = ISNULL(m.AmountToCompany, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(CASE WHEN m.LicenseeFee > 0 THEN m.LicenseeFee ELSE 0 END + m.WaivedFee) AS AmountToCompany
				FROM @MinFee m
				WHERE g.GroupMinFeeId = m.GroupMinFeeId AND g.ProductId = m.ProductId
			) m
		
		-- Include left over min fee into primary licensees
		UPDATE m
		SET m.ActualFee = CASE
								WHEN g.AmountToCompany >= g.GroupMinFee THEN ActualFee
								WHEN m.LicenseeFee < 0 THEN g.GroupMinFee - g.AmountToCompany
								ELSE m.LicenseeFee + g.GroupMinFee - g.AmountToCompany END
		FROM @MinFee m
			INNER JOIN @GroupMinFee g ON g.GroupMinFeeId = m.GroupMinFeeId AND m.ProductId = g.ProductId
		WHERE m.IsPrimary = 1

		-- Licensee Fee & Licensee Min Fee
		UPDATE g
		SET g.LicenseeFee = ISNULL(m.ActualFee, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(m.ActualFee) AS ActualFee
				FROM @MinFee m
				WHERE g.GroupMinFeeId = m.GroupMinFeeId AND g.ProductId = m.ProductId
			) m

		-- Rebate & Discount
		DECLARE @Discount_PartyIds VARCHAR(MAX), @Discount_ProductCodes VARCHAR(MAX)
		DECLARE @DiscountGroup TABLE (PartyId INT, ProductId INT, ProductCode VARCHAR(50))
		INSERT INTO @DiscountGroup (PartyId, ProductId)
		SELECT PartyId, ProductId
		FROM (
			SELECT da.PartyId, dp.ProductId, ROW_NUMBER() OVER(PARTITION BY da.PartyId, dp.ProductId ORDER BY dh.ToDate DESC) AS RN
			FROM bodb_Licensee.dbo.LA_DiscountGroupHeader dh WITH (NOLOCK)
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment da WITH (NOLOCK) ON da.DiscountGroupId = dh.DiscountGroupId
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dp WITH (NOLOCK) ON dp.DiscountGroupId = dh.DiscountGroupId
			WHERE dh.FromDate <= @ToDate AND dh.ToDate >= @FromDate
		) t
		WHERE RN = 1

		UPDATE d
		SET d.ProductCode = p.ProductCode
		FROM @DiscountGroup d
			INNER JOIN #Products p ON d.ProductId = p.ProductId

		DELETE @DiscountGroup WHERE ProductCode IS NULL

		;WITH CTE_PartyId AS (SELECT DISTINCT PartyId FROM @DiscountGroup)
		SELECT @Discount_PartyIds = COALESCE(@Discount_PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM CTE_PartyId

		;WITH CTE_ProductCode AS (SELECT DISTINCT ProductCode FROM @DiscountGroup)
		SELECT @Discount_ProductCodes = COALESCE(@Discount_ProductCodes + ',', '') + ProductCode FROM CTE_ProductCode

		DECLARE @DiscountData TABLE (PartyId INT, ProductId INT, Fee MONEY, Discount MONEY, Rebate MONEY, IsChargedByMinFee BIT, IsChargedByGroupMinFee BIT)
		INSERT INTO @DiscountData (PartyId, ProductId, Fee, Discount, Rebate, IsChargedByMinFee, IsChargedByGroupMinFee)
		EXEC dbo.LA_AmountToCompanyByDiscountCurrencySel
			@FromDate			= @F_Date
			,@ToDate			= @T_Date
			,@PartyIds			= @Discount_PartyIds
			,@ProductCodes		= @Discount_ProductCodes
			,@BaseCurrencyName	= @BaseCurrencyName
			,@BaseCurrencyId	= @BaseCurrencyId
			,@CurrencyId		= 0

		DECLARE @Result TABLE (PartyId INT, ProductId INT, GroupMinFeeId INT, IsPrimary BIT DEFAULT(0), LicenseeAmount MONEY DEFAULT(0), ExtraAmount MONEY DEFAULT(0), Rebate MONEY DEFAULT(0), Discount MONEY DEFAULT(0))
		;WITH CTE_tempResult AS (
			SELECT PartyId, ProductId, SUM(LicenseeAmount) AS LicenseeAmount, SUM(ExtraAmount) AS ExtraAmount
			FROM #tmpResult
			GROUP BY PartyId, ProductId
		), CTE_Result AS (
			SELECT
				PartyId = ISNULL(t.PartyId, m.PartyId)
				,ProductId = ISNULL(t.ProductId, m.ProductId)
				,GroupMinFeeId = ISNULL(m.GroupMinFeeId, -t.PartyId)
				,LicenseeAmount = ISNULL(t.LicenseeAmount, 0)
				,ExtraAmount = ISNULL(t.ExtraAmount, 0)
			FROM CTE_tempResult t
				FULL OUTER JOIN @MinFee m ON t.PartyId = m.PartyId AND t.ProductId = m.ProductId			
		)
		INSERT INTO @Result (PartyId, ProductId, GroupMinFeeId, LicenseeAmount, ExtraAmount)
		SELECT r.PartyId, r.ProductId, r.GroupMinFeeId, r.LicenseeAmount, r.ExtraAmount
		FROM CTE_Result r
			INNER JOIN (SELECT PartyId, ProductId FROM @PartyChargeInfo UNION SELECT PartyId, 15 FROM @CBChargeRate) p ON p.PartyId = r.PartyId AND p.ProductId = r.ProductId

		DELETE @Result WHERE GroupMinFeeId IS NULL

		UPDATE s
		SET s.IsPrimary			= m.IsPrimary
			,s.LicenseeAmount	= CASE WHEN m.PartyId IS NULL THEN s.LicenseeAmount ELSE m.ActualFee END
			,s.Rebate			= ISNULL(d.Rebate, 0)
			,s.Discount			= ISNULL(d.Discount, 0)
		FROM @Result s
			LEFT JOIN @MinFee m ON m.PartyId = s.PartyId AND m.ProductId = s.ProductId
			LEFT JOIN @DiscountData d ON d.PartyId = s.PartyId AND d.ProductId = s.ProductId

		UPDATE g
		SET g.Rebate = ISNULL(d.Rebate, 0), g.Discount = ISNULL(d.Discount, 0)
		FROM @GroupMinFee g
			CROSS APPLY (
				SELECT SUM(s.Rebate) AS Rebate, SUM(s.Discount) AS Discount
				FROM @Result s
				WHERE s.GroupMinFeeId = g.GroupMinFeeId AND s.ProductId = g.ProductId
			) d

		UPDATE s
		SET s.LicenseeAmount = s.LicenseeAmount + (g.GroupMinFee - (g.LicenseeFee - g.Discount))
		FROM @Result s
			INNER JOIN @GroupMinFee g ON s.GroupMinFeeId = g.GroupMinFeeId
		WHERE s.GroupMinFeeId > 0
			AND (g.LicenseeFee - g.Discount) < g.GroupMinFee
			AND s.IsPrimary = 1
	END

	-- Final Result
	CREATE TABLE #Result (PartyId INT, ProductId INT, LicenseeFee MONEY)
	INSERT INTO #Result (PartyId, ProductId, LicenseeFee)
	SELECT r.PartyId, r.ProductId
		-- Keep Nagative Amount for Joint Venture Parties
		,CASE WHEN r.ProductId IN (3, 15, 25, 31) OR jvp.PartyId IS NOT NULL THEN r.LicenseeAmount
			WHEN r.LicenseeAmount < 0 THEN 0
			ELSE r.LicenseeAmount END + r.ExtraAmount
	FROM @Result r
		LEFT JOIN dbo.LA_f_JVPartyListSel() jvp ON r.PartyId = jvp.PartyId
	UNION ALL SELECT PartyId, -3, -SUM(Discount) FROM @Result GROUP BY PartyId
	UNION ALL SELECT PartyId, -2, -SUM(Rebate) FROM @Result GROUP BY PartyId
	UNION ALL SELECT PartyId, -1, -SUM(LicenseeAmount) FROM #tmpResult WHERE ProductId = -1 GROUP BY PartyId

	INSERT INTO #Result (PartyId, ProductId, LicenseeFee)
	SELECT PartyId, -99, SUM(LicenseeFee)
	FROM #Result
	GROUP BY PartyId

	-- Return data
	DECLARE @ProductList VARCHAR(MAX), @SQL VARCHAR(MAX)
	SELECT  @ProductList = COALESCE(@ProductList + ', ', '') + '[' + ProductName + ']' FROM #Products ORDER BY ProductId

	SELECT @SQL = '
	;WITH CTE_Result AS (
		SELECT PartyId, ' + @ProductList + '
		FROM (
			SELECT r.PartyId, r.LicenseeFee, p.ProductName
			FROM #Result r
				INNER JOIN #Products p ON r.ProductId = p.ProductId
		) t
		PIVOT (
			MAX(LicenseeFee) FOR ProductName IN (' + @ProductList + ')
		) p
	)
	SELECT p.ParentName AS GroupName, p.PartyName AS LicenseeName, ' + @ProductList + '
	FROM #PartyList p
		INNER JOIN CTE_Result r ON p.PartyId = r.PartyId AND p.IsSelected = 1
	WHERE  p.StatusId  IN (SELECT x.StatusId FROM #statusTab x) 
	ORDER BY p.ParentName, p.PartyName'

	EXEC (@SQL)

	DROP TABLE #statusTab
	DROP TABLE #Exchange
	DROP TABLE #PartyList
	DROP TABLE #Products
	DROP TABLE #Result
	DROP TABLE #TempData
	DROP TABLE #tmpResult
END
GO