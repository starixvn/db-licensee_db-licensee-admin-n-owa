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
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @ProductCode VARCHAR(50)
	
	IF @ProductId = 0 -- SB
		SET @ProductCode = 'SB'
	ELSE
		SELECT @ProductCode = ProductPrefix FROM dbo.Product3rd WITH (NOLOCK) WHERE ProductId = @ProductId

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
	SELECT DISTINCT Bettype, 2 AS TypeId -- Promotion (include Free bets)
	FROM bodb02.dbo.SportBettypeMatrix WITH (NOLOCK)
	WHERE SportType IN (150, 173)
	UNION ALL
	SELECT Bettype, 3 AS TypeId FROM (VALUES (4298), (1699), (3899)) b (Bettype) -- JackpotPrize

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
			,SUM(CASE WHEN b.Bettype IS NOT NULL THEN 0 ELSE -ISNULL(r.MemberWL, 0) END) AS LicenseeWL
			,SUM(CASE WHEN b.TypeId = 1 THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS Contribution
			,SUM(CASE WHEN b.TypeId = 2 THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS Promotion
			,SUM(CASE WHEN b.TypeId = 3 THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS JackpotPrize
			,SUM(CASE WHEN b.TypeId = 4 THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS OddsSpread
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
			INNER JOIN @tblSite s ON r.SiteId = s.SiteId
			LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.Bettype = r.Bettype
			LEFT JOIN @Bettype b ON b.Bettype = r.Bettype
		WHERE r.rptDate BETWEEN @FromDate AND @ToDate
			AND r.ProductId = @ProductId
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
			,-SUM(ISNULL(b.swinlost, 0) + ISNULL(b.mwinlost, 0) + ISNULL(b.awinlost, 0) + ISNULL(b.winlost, 0) + ISNULL(b.scomm, 0)) AS AmountToCompany
		FROM bodb_LicenseeReport.dbo.rptLicWinloss2 b WITH (NOLOCK)
			INNER JOIN @recommend r ON b.recommend = r.recommend
			INNER JOIN (
				SELECT CONVERT(SMALLINT, SportType) AS SportType
				FROM bodb02.dbo.f_LicWinLoss_ProductSportType_Sel(@ProductCode)
			) f ON b.sporttype = f.SportType
		WHERE b.WinlostDate BETWEEN @FromDate AND @ToDate
			AND b.roleId = 2
			AND b.statusId IN (111, 112, 113, 114, 115)
			AND b.bettype NOT IN (901, 902, 911, 912)
		GROUP BY b.recommend, b.WinlostDate, b.Currency, b.Bettype, b.apositiontaking -- group by on index recommend
	END

	-- Final Result
	BEGIN
		DECLARE @Result TABLE (Func VARCHAR(10), LicenseeWL MONEY, ChargeRate SMALLMONEY, LicensingFee MONEY, Contribution MONEY, ContributionDiscount MONEY, Promotion MONEY, JackpotPrize MONEY)
	
		-- LA
		INSERT INTO @Result (Func, LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize)
		SELECT 'LA', LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize
		FROM (
			SELECT
				CONVERT(SMALLMONEY, ISNULL(bc.Rate, c.Rate)) AS ChargeRate
				,CONVERT(MONEY, SUM(t.LicenseeWL * e.Rate)) AS LicenseeWL
				,CONVERT(MONEY, SUM(t.LicenseeWL * ISNULL(bc.Rate, c.Rate) * e.Rate)) AS LicensingFee
				,CONVERT(MONEY, SUM(Contribution * e.Rate)) AS Contribution
				,CONVERT(MONEY, SUM(Contribution * e.Rate * ISNULL(bc.Rate, c.Rate))) AS ContributionDiscount
				,CONVERT(MONEY, SUM(Promotion * e.Rate)) AS Promotion
				,CONVERT(MONEY, SUM(JackpotPrize * e.Rate)) AS JackpotPrize
			FROM #tmpLAData t
				INNER JOIN @Exchange e ON t.Currency = e.ExchangeId AND t.WinlostDate = e.ExchangeDate
				INNER JOIN @ChargeInfo c ON t.SiteId = c.LicenseeId AND (t.Bettype = c.Bettype OR c.Bettype = -1) AND t.WinlostDate BETWEEN c.FromDate AND c.ToDate
				LEFT JOIN dbo.LA_ChargeRateByCurrency bc WITH (NOLOCK) ON c.ChargeId = bc.ChargeId AND t.Currency = bc.CurrencyId
			GROUP BY CONVERT(SMALLMONEY, ISNULL(bc.Rate, c.Rate))
		) d

		-- NAP
		;WITH CTE_Data AS (
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
		)
		INSERT INTO @Result (Func, LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize)
		SELECT 'NAP', d.LicenseeWL, d.HousePT, d.CompanyWL
			,ISNULL(t.Contribution, 0) AS Contribution
			,CONVERT(MONEY, 0) AS ContributionDiscount
			,ISNULL(t.Promotion, 0) AS Promotion
			,ISNULL(t.JackpotPrize, 0) AS JackpotPrize
		FROM CTE_Data d
			LEFT JOIN (
				SELECT
					 SUM(CASE WHEN TypeId = 1 THEN CompanyWL ELSE 0 END) AS Contribution
					,SUM(CASE WHEN TypeId = 2 THEN CompanyWL ELSE 0 END) AS Promotion
					,SUM(CASE WHEN TypeId = 3 THEN CompanyWL ELSE 0 END) AS JackpotPrize
				FROM CTE_Data
				WHERE TypeId IS NOT NULL
			) t ON 1=1
		WHERE d.TypeId = 0
	END

	-- Return data
		-- LA
	SELECT LicenseeWL, ChargeRate, LicensingFee AS ServiceFee, Contribution, ContributionDiscount, Promotion, JackpotPrize
	FROM @Result
	WHERE Func = 'LA'
	
		-- NAP
	SELECT LicenseeWL, ChargeRate AS HousePT, LicensingFee AS CompanyWL, Contribution, ContributionDiscount, Promotion, JackpotPrize
	FROM @Result
	WHERE Func = 'NAP'

		-- Variance
	SELECT
		CONVERT(MONEY, ISNULL(l.LicensingFee, 0) - ISNULL(n.LicensingFee, 0)) AS CompanyWL
		,CONVERT(MONEY, ISNULL(l.Contribution, 0) - ISNULL(n.Contribution, 0)) AS Contribution
		,CONVERT(MONEY, ISNULL(l.ContributionDiscount, 0) - ISNULL(n.ContributionDiscount, 0)) AS ContributionDiscount
		,CONVERT(MONEY, ISNULL(l.Promotion, 0) - ISNULL(n.Promotion, 0)) AS Promotion
		,CONVERT(MONEY, ISNULL(l.JackpotPrize, 0) - ISNULL(n.JackpotPrize, 0)) AS JackpotPrize
	FROM (
		SELECT
			SUM(LicensingFee) AS LicensingFee
			,SUM(Contribution) AS Contribution
			,SUM(ContributionDiscount) AS ContributionDiscount
			,SUM(Promotion) AS Promotion
			,SUM(JackpotPrize) AS JackpotPrize
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
			FROM @Result
			WHERE Func = 'NAP'
		) n ON 1 = 1

	DROP TABLE #tmpLAData
	DROP TABLE #tmpNAPData
END
GO