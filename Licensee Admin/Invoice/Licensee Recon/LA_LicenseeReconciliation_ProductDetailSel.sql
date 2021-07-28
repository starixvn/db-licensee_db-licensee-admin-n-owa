/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_ProductDetailSel]
	@PartyId			INT
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

	DECLARE @PartyIds VARCHAR(20), @ProductCode VARCHAR(20), @SiteId INT, @SiteName VARCHAR(50)
	SELECT  @PartyIds = CONVERT(VARCHAR(20), @PartyId)
	
	IF @ProductId = 0 -- SB
		SET @ProductCode = 'SB'
	ELSE
		SELECT @ProductCode = ProductPrefix FROM dbo.Product3rd WITH (NOLOCK) WHERE ProductId = @ProductId

	SELECT @SiteId = l.LicenseeId, @SiteName = l.LicenseeName
	FROM dbo.Licensees l WITH (NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON l.LicenseeId = p.OldRefId AND p.PartyType IN (1, 5)
	WHERE p.PartyId = @PartyId

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
		DECLARE @ChargeInfo TABLE (ChargeId INT, ChargeType TINYINT, Bettype INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME, Rate FLOAT)
		INSERT INTO @ChargeInfo (ChargeId, ChargeType, FromDate, ToDate, Rate, Bettype)
		SELECT DISTINCT ChargeId, ChargeType, FromDate, ToDate, DI_Rate AS Rate
			,CASE
				WHEN ProductId = 11 AND ChargeType = 12 THEN 1706 -- GD Tip
				WHEN ProductId = 39 AND ChargeType = 12 THEN 3007 -- SA Tip
				ELSE Bettype END
		FROM dbo.LA_f_ChargeInfo (@PartyIds, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE DI_Rate > 0

		-- Get Winloss data
		CREATE TABLE #tmpLAData (WinlostDate SMALLDATETIME, Currency INT, Bettype INT, LicenseeWL MONEY, Contribution MONEY, Promotion MONEY, JackpotPrize MONEY, OddsSpread MONEY)
		INSERT INTO #tmpLAData (WinlostDate, Currency, Bettype, LicenseeWL, Contribution, Promotion, JackpotPrize, OddsSpread)
		SELECT r.rptDate, r.CurrencyId
			,CASE WHEN r.Bettype IN (1706, 3007) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END AS Bettype
			,SUM(CASE WHEN b.Bettype IS NOT NULL THEN 0 ELSE -ISNULL(r.MemberWL, 0) END) AS LicenseeWL
			,SUM(CASE WHEN b.TypeId = 1 THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS Contribution
			,SUM(CASE WHEN b.TypeId = 2 THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS Promotion
			,SUM(CASE WHEN b.TypeId = 3 THEN ISNULL(r.MemberWL, 0) ELSE 0 END) AS JackpotPrize
			,SUM(CASE WHEN b.TypeId = 4 THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) AS OddsSpread
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
			LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH (NOLOCK) ON sbr.Bettype = r.Bettype
			LEFT JOIN @Bettype b ON b.Bettype = r.Bettype
		WHERE r.rptDate BETWEEN @FromDate AND @ToDate
			AND r.SiteId = @SiteId
			AND r.ProductId = @ProductId
			AND r.StatusId NOT IN (-1, 101, 102, 103)
			AND r.CustomerCategory NOT IN (27, 28)
			AND r.CurrencyId <> 20
			AND r.ProductId <> 25 -- CO
		GROUP BY r.rptDate, r.CurrencyId
			,CASE WHEN r.Bettype IN (1706, 3007) THEN r.Bettype ELSE ISNULL(sbr.BettypeRef, -1) END
	END

	-- II. NAP
	BEGIN
		-- Get agent list
		DECLARE @recommend TABLE (recommend INT)
		INSERT INTO @recommend (recommend)
		SELECT c.custid
		FROM bodb02.dbo.Customer c WITH (NOLOCK)
			INNER JOIN bodb02.dbo.Dep_CustSuper s WITH (NOLOCK) ON c.srecommend = s.custid
		WHERE s.site = @SiteName AND c.roleid = 2

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

	-- Return data
		-- LA
	SELECT ROW_NUMBER() OVER(ORDER BY ChargeRate) AS RowId
		,LicenseeWL, ChargeRate, LicensingFee, Contribution, ContributionDiscount, Promotion, JackpotPrize
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
			INNER JOIN @ChargeInfo c ON (t.Bettype = c.Bettype OR c.Bettype = -1) AND t.WinlostDate BETWEEN c.FromDate AND c.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency bc WITH (NOLOCK) ON c.ChargeId = bc.ChargeId AND t.Currency = bc.CurrencyId
		GROUP BY CONVERT(SMALLMONEY, ISNULL(bc.Rate, c.Rate))
	) d
	ORDER BY RowId

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
	SELECT ROW_NUMBER() OVER(ORDER BY d.HousePT) AS RowId
		,d.LicenseeWL, d.HousePT, d.CompanyWL
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
	ORDER BY RowId

	DROP TABLE #tmpLAData
	DROP TABLE #tmpNAPData
END
GO