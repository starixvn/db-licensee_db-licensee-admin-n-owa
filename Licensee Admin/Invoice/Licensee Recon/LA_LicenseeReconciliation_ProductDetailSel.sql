/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_ProductDetailSel]
	@PartyIds			VARCHAR(MAX)
	,@ProductId			INT
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@BaseCurrencyName	VARCHAR(10) = 'EUR'
AS

/*
	Created: 20210727@Percy
	DB: DBLIC-bodb_Licensee
	Task: Get data from NAP

	Revisions: 
		- 20210727@Percy: Initialize SP [RedmineID: #155593]
		- 20210812@Percy: Integrate Bitcoin - apply core function GroupProduct [RedmineID: #159691]
		- 20211115@Percy: Return IsShowOddsSpread [RedmineID: #164411]
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20211212@Percy: Set OddsSpread = 0 if negative value [RedmineID: #165849]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @Products TABLE (GroupProductId INT, ProductId INT, ProductCode VARCHAR(20))
	INSERT INTO @Products (GroupProductId, ProductId, ProductCode)
	SELECT GroupProductId, ProductId, ProductCode
	FROM dbo.LA_f_GroupProduct('',@FromDate,@ToDate)
	WHERE GroupProductId = @ProductId

	DECLARE @ProductCode VARCHAR(MAX)
	SELECT  @ProductCode = COALESCE(@ProductCode + ',', '') + ProductCode FROM @Products WHERE GroupProductId = ProductId

	DECLARE @tblSite TABLE (SiteId INT, Site VARCHAR(100))
	INSERT INTO @tblSite (SiteId, Site)
	SELECT l.LicenseeId, l.LicenseeName
	FROM dbo.Licensees l WITH (NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON l.LicenseeId = p.OldRefId AND p.PartyType IN (1, 5)
	WHERE p.PartyId IN (SELECT CONVERT(INT, val) FROM bodb02.dbo.strSplit(@PartyIds, ','))

	-- Get Exchange
	DECLARE @Exchange TABLE (ExchangeId INT, ExchangeDate SMALLDATETIME, Rate FLOAT)
	INSERT INTO @Exchange (ExchangeId, ExchangeDate, Rate)
	SELECT ExchangeId, ExchangeDate, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @BaseCurrencyName)

	-- Get bettype group: Contribution, Promotion, Prize, ...
	DECLARE @Bettype TABLE (Bettype INT, TypeId TINYINT)
	INSERT INTO @Bettype (Bettype, TypeId)
	SELECT Bettype, 1 AS TypeId FROM (VALUES (4297), (1698), (3898)) b (Bettype) -- Contribution
	UNION ALL
	SELECT Bettype, 2 AS TypeId FROM (VALUES (4299), (4300), (1906), (3150)) b (Bettype) -- Promotion
	UNION ALL
	SELECT Bettype, 3 AS TypeId FROM (VALUES (4298), (1699), (3899)) b (Bettype) -- JackpotPrize
	UNION ALL
	SELECT Bettype, 4 AS TypeId FROM (VALUES (999)) b (Bettype) -- OddsSpread Adjustment
	
	INSERT INTO @Bettype (Bettype, TypeId)
	SELECT s.Bettype, 2 AS TypeId -- Promotion (include Free bets)
	FROM (
		SELECT DISTINCT Bettype
		FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
		WHERE SportType IN (150, 173)
	) s
		LEFT JOIN @Bettype b ON s.BetType = b.Bettype
	WHERE b.Bettype IS NULL

	-- I. LA
	BEGIN
		-- Get charge rate
		DECLARE @ChargeInfo TABLE (ChargeId INT, ChargeType TINYINT, PartyId INT, LicenseeId INT, Bettype INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME, Rate FLOAT)
		INSERT INTO @ChargeInfo (ChargeId, ChargeType, PartyId, LicenseeId, FromDate, ToDate, Rate, Bettype)
		SELECT DISTINCT ChargeId, ChargeType, PartyId, LicenseeId, FromDate, ToDate, DI_Rate AS Rate
			,CASE
				WHEN ProductId = 11 AND ChargeType = 12 THEN 1706 -- GD Tip
				WHEN ProductId = 39 AND ChargeType = 12 THEN 3007 -- SA Tip
				ELSE Bettype END
		FROM dbo.LA_f_ChargeInfo (@PartyIds, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE DI_Rate > 0

		-- Get Winloss data
		CREATE TABLE #tmpLAData (WinlostDate SMALLDATETIME, Currency INT, SiteId INT, Bettype INT, LicenseeWL MONEY, Contribution MONEY, Promotion MONEY, JackpotPrize MONEY, OddsSpread MONEY)
		INSERT INTO #tmpLAData (WinlostDate, Currency, SiteId, Bettype, LicenseeWL, Contribution, Promotion, JackpotPrize, OddsSpread)
		SELECT r.rptDate, r.CurrencyId, r.SiteId
			,CASE WHEN r.Bettype IN (1706, 3007) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END AS Bettype
			,SUM(CASE WHEN b.Bettype IS NOT NULL OR r.TicketType = 2 THEN 0 ELSE -ISNULL(r.MemberWL, 0) END) AS LicenseeWL
			,SUM(CASE WHEN b.TypeId = 1 THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS Contribution
			,SUM(CASE WHEN b.TypeId = 2 OR r.TicketType = 2 THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS Promotion
			,SUM(CASE WHEN b.TypeId = 3 THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS JackpotPrize
			,SUM(CASE WHEN b.TypeId = 4 THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS OddsSpread
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
			INNER JOIN @tblSite s ON r.SiteId = s.SiteId
			LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.Bettype = r.Bettype
			LEFT JOIN @Bettype b ON b.Bettype = r.Bettype
		WHERE r.rptDate BETWEEN @FromDate AND @ToDate
			AND r.ProductId IN (SELECT p.ProductId FROM @Products p)
			AND r.StatusId NOT IN (-1, 101, 102, 103)
			AND r.CustomerCategory NOT IN (27, 28)
			AND r.CurrencyId <> 20
			AND r.ProductId <> 25 -- CO
		GROUP BY r.rptDate, r.CurrencyId, r.SiteId
			,CASE WHEN r.Bettype IN (1706, 3007) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END
	END

	-- II. NAP
	BEGIN
		-- Get agent list
		DECLARE @recommend TABLE (recommend INT)
		INSERT INTO @recommend (recommend)
		SELECT c.custid
		FROM @tblSite t
			INNER JOIN bodb02.dbo.Dep_CustSuper s WITH (NOLOCK) ON t.Site = s.Site
			INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON s.custid = c.srecommend
		WHERE c.roleid = 2
			AND s.currency <> 20

		-- Get AmountToCompany data
		CREATE TABLE #tmpNAPData (WinlostDate SMALLDATETIME, Currency INT, Bettype INT, apositiontaking FLOAT, LicenseeWL MONEY, AmountToCompany MONEY)
		INSERT INTO #tmpNAPData (WinlostDate, Currency, Bettype, apositiontaking, LicenseeWL, AmountToCompany)
		SELECT b.WinlostDate, b.Currency, b.Bettype, b.apositiontaking
			,-SUM(ISNULL(b.winlost, 0)) AS LicenseeWL
			,SUM(ISNULL(b.swinlost, 0) + ISNULL(b.mwinlost, 0) + ISNULL(b.awinlost, 0) + ISNULL(b.winlost, 0) + ISNULL(b.scomm, 0)) AS AmountToCompany
		FROM bodb_LicenseeReport.dbo.rptLicWinloss2 b WITH (NOLOCK)
			INNER JOIN @recommend r ON b.recommend = r.recommend
			INNER JOIN (
				SELECT DISTINCT CONVERT(SMALLINT, SportType) AS SportType
				FROM bodb02.dbo.f_LicWinLoss_ProductSportType_Sel(@ProductCode)
			) f ON b.sporttype = f.SportType
		WHERE b.WinlostDate BETWEEN @FromDate AND @ToDate
			AND b.roleId = 2
			AND b.statusId IN (111, 112, 113, 114, 115)
			AND b.bettype NOT IN (901, 902, 903, 904, 911, 912, 913, 914)
			AND b.IsBA = 0
		GROUP BY b.recommend, b.WinlostDate, b.Currency, b.Bettype, b.apositiontaking -- group by on index recommend
	END

	-- Final Result
	BEGIN
		DECLARE @Result TABLE (Func VARCHAR(10), LicenseeWL MONEY, ChargeRate SMALLMONEY, LicensingFee MONEY
				,Contribution MONEY, ContributionDiscount MONEY, Promotion MONEY, JackpotPrize MONEY, OddsSpread MONEY, IsShowOddsSpread TINYINT)
	
		-- LA
		INSERT INTO @Result (Func, LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize, OddsSpread, IsShowOddsSpread)
		SELECT 'LA', LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize, OddsSpread, 1 AS IsShowOddsSpread
		FROM (
			SELECT
				CONVERT(SMALLMONEY, ISNULL(bc.Rate, c.Rate)) AS ChargeRate
				,CONVERT(MONEY, SUM(t.LicenseeWL * e.Rate)) AS LicenseeWL
				,CONVERT(MONEY, SUM(-t.LicenseeWL * ISNULL(bc.Rate, c.Rate) * e.Rate)) AS LicensingFee
				,CONVERT(MONEY, SUM(t.Contribution * e.Rate)) AS Contribution
				,CONVERT(MONEY, SUM(t.Contribution * e.Rate * ISNULL(bc.Rate, c.Rate))) AS ContributionDiscount
				,CONVERT(MONEY, SUM(t.Promotion * e.Rate)) AS Promotion
				,CONVERT(MONEY, SUM(t.JackpotPrize * e.Rate)) AS JackpotPrize
				,CONVERT(MONEY, SUM(-t.OddsSpread * e.Rate)) AS OddsSpread
			FROM #tmpLAData t
				INNER JOIN @Exchange e ON t.Currency = e.ExchangeId AND t.WinlostDate = e.ExchangeDate
				INNER JOIN @ChargeInfo c ON t.SiteId = c.LicenseeId AND (t.Bettype = c.Bettype OR c.Bettype = -1) AND t.WinlostDate BETWEEN c.FromDate AND c.ToDate
				LEFT JOIN dbo.LA_ChargeRateByCurrency bc WITH (NOLOCK) ON c.ChargeId = bc.ChargeId AND t.Currency = bc.CurrencyId
			GROUP BY CONVERT(SMALLMONEY, ISNULL(bc.Rate, c.Rate))
		) d
		
		IF @@ROWCOUNT = 0
			INSERT INTO @Result (Func, LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize, OddsSpread, IsShowOddsSpread)
			SELECT 'LA', 0, 0, 0, 0, 0, 0, 0, 0, 0

		ELSE IF EXISTS (SELECT 1 FROM @Result WHERE Func = 'LA' HAVING SUM(-OddsSpread) <= 0)  -- Set OddsSpread = 0 if value is negative (show Negative value (-))
			UPDATE @Result SET OddsSpread = 0, IsShowOddsSpread = 0 WHERE Func = 'LA'

		-- NAP
		;WITH CTE_tmpData AS (
			SELECT
				CONVERT(INT, ISNULL(b.TypeId, 0)) AS TypeId
				,CONVERT(SMALLMONEY, ISNULL(1.0 - t.apositiontaking, 0)) AS HousePT
				,CONVERT(MONEY, SUM(t.LicenseeWL * e.Rate)) AS LicenseeWL
				,CONVERT(MONEY, SUM(t.AmountToCompany * e.Rate)) AS CompanyWL
			FROM #tmpNAPData t
				INNER JOIN @Exchange e ON t.Currency = e.ExchangeId AND t.WinlostDate = e.ExchangeDate
				LEFT JOIN @Bettype b ON t.Bettype = b.Bettype
			GROUP BY
				CONVERT(INT, ISNULL(b.TypeId, 0))
				,CONVERT(SMALLMONEY, ISNULL(1.0 - t.apositiontaking, 0))
		), CTE_Data AS (
			SELECT TypeId, HousePT, LicenseeWL, CompanyWL, ROW_NUMBER() OVER(ORDER BY TypeId) AS RN
			FROM CTE_tmpData
		)
		INSERT INTO @Result (Func, LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize, OddsSpread, IsShowOddsSpread)
		SELECT 'NAP', ISNULL(d.LicenseeWL, 0), ISNULL(d.HousePT, 0), ISNULL(d.CompanyWL, 0)
			,ISNULL(t.Contribution, 0) AS Contribution
			,CONVERT(MONEY, 0) AS ContributionDiscount
			,ISNULL(t.Promotion, 0) AS Promotion
			,ISNULL(t.JackpotPrize, 0) AS JackpotPrize
			,ISNULL(t.OddsSpread, 0) AS OddsSpread
			,1 AS IsShowOddsSpread
		FROM CTE_Data d
			FULL OUTER JOIN (
				SELECT
					 SUM(CASE WHEN TypeId = 1 THEN -CompanyWL ELSE 0 END) AS Contribution
					,SUM(CASE WHEN TypeId = 2 THEN CompanyWL ELSE 0 END) AS Promotion
					,SUM(CASE WHEN TypeId = 3 THEN CompanyWL ELSE 0 END) AS JackpotPrize
					,SUM(CASE WHEN TypeId = 4 THEN CompanyWL ELSE 0 END) AS OddsSpread
				FROM CTE_Data
				WHERE TypeId IS NOT NULL
			) t ON d.TypeId = 0 AND d.RN = 1
		WHERE ISNULL(d.TypeId, 0) = 0

		IF @@ROWCOUNT = 0
			INSERT INTO @Result (Func, LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize, OddsSpread, IsShowOddsSpread)
			SELECT 'NAP', 0, 0, 0, 0, 0, 0, 0, 0, 0
		ELSE IF NOT EXISTS (SELECT 1 FROM @Result WHERE Func = 'NAP' AND OddsSpread <> 0)
			UPDATE @Result SET IsShowOddsSpread = 0 WHERE Func = 'NAP'
	END

	-- Return data
	DECLARE @IsShowOddsSpread BIT
	SELECT  @IsShowOddsSpread = MAX(IsShowOddsSpread) FROM @Result
	SELECT  @IsShowOddsSpread = ISNULL(@IsShowOddsSpread, 0)

		-- LA
	SELECT LicenseeWL, ChargeRate, LicensingFee AS ServiceFee
		,-Contribution AS Contribution, ContributionDiscount, Promotion, JackpotPrize, OddsSpread AS OddsSpreadAdjustment, @IsShowOddsSpread AS IsShowOddsSpread
	FROM @Result
	WHERE Func = 'LA'
	
		-- NAP
	SELECT LicenseeWL, ChargeRate AS HousePT, LicensingFee AS CompanyWL
		,-Contribution AS Contribution, ContributionDiscount, Promotion, JackpotPrize, OddsSpread AS OddsSpreadAdjustment, @IsShowOddsSpread AS IsShowOddsSpread
	FROM @Result
	WHERE Func = 'NAP'

		-- Variance
	SELECT
		CONVERT(MONEY, ISNULL(l.LicensingFee, 0) - ISNULL(n.LicensingFee, 0)) AS CompanyWL
		,CONVERT(MONEY, ISNULL(l.Contribution, 0) - ISNULL(n.Contribution, 0)) AS Contribution
		,CONVERT(MONEY, ISNULL(l.ContributionDiscount, 0) - ISNULL(n.ContributionDiscount, 0)) AS ContributionDiscount
		,CONVERT(MONEY, ISNULL(l.Promotion, 0) - ISNULL(n.Promotion, 0)) AS Promotion
		,CONVERT(MONEY, ISNULL(l.JackpotPrize, 0) - ISNULL(n.JackpotPrize, 0)) AS JackpotPrize
		,CONVERT(MONEY, ISNULL(l.OddsSpread, 0) - ISNULL(n.OddsSpread, 0)) AS OddsSpreadAdjustment
	FROM (
		SELECT
			SUM(LicensingFee) AS LicensingFee
			,SUM(Contribution) AS Contribution
			,SUM(ContributionDiscount) AS ContributionDiscount
			,SUM(Promotion) AS Promotion
			,SUM(JackpotPrize) AS JackpotPrize
			,SUM(OddsSpread) AS OddsSpread
		FROM @Result
		WHERE Func = 'LA'
	) l
		FULL OUTER JOIN (
			SELECT
				SUM(LicensingFee) AS LicensingFee
				,SUM(Contribution) AS Contribution
				,SUM(ContributionDiscount) AS ContributionDiscount
				,SUM(Promotion) AS Promotion
				,SUM(JackpotPrize) AS JackpotPrize
				,SUM(OddsSpread) AS OddsSpread
			FROM @Result
			WHERE Func = 'NAP'
		) n ON 1 = 1

	DROP TABLE #tmpLAData
	DROP TABLE #tmpNAPData
END
GO