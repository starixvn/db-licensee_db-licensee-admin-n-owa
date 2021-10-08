/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_NAPByProductSel]
	@PartyIds			VARCHAR(MAX)
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
*/

BEGIN
	SET NOCOUNT ON

	-- Get agent list
	DECLARE @tblSite TABLE (Site VARCHAR(100))
	INSERT INTO @tblSite (Site)
	SELECT l.LicenseeName
	FROM dbo.Licensees l WITH (NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON l.LicenseeId = p.OldRefId AND p.PartyType IN (1, 5)
	WHERE p.PartyId IN (SELECT CONVERT(INT, val) FROM bodb02.dbo.strSplit(@PartyIds, ','))

	DECLARE @recommend TABLE (recommend INT)
	INSERT INTO @recommend (recommend)
	SELECT c.custid
	FROM @tblSite t
		INNER JOIN bodb02.dbo.Dep_CustSuper s WITH (NOLOCK) ON t.Site = s.Site
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON s.custid = c.srecommend
	WHERE c.roleid = 2
		AND s.currency <> 20

	-- Get Exchange
	DECLARE @Exchange TABLE (ExchangeId INT, ExchangeDate SMALLDATETIME, Rate FLOAT)
	INSERT INTO @Exchange (ExchangeId, ExchangeDate, Rate)
	SELECT ExchangeId, ExchangeDate, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @BaseCurrencyName)

	-- Get Product List
	DECLARE @ProductCodes VARCHAR(MAX)
	SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductPrefix FROM bodb_Licensee.dbo.Product3rd WITH (NOLOCK) WHERE ProductId NOT IN (3, 16, 25)
	SELECT  @ProductCodes = 'SB,' + @ProductCodes

	DECLARE @Products TABLE (GroupProductId INT, ProductId INT, ProductName VARCHAR(50), Sporttype INT, IsBA BIT)
	INSERT INTO @Products (GroupProductId, ProductId, ProductName, Sporttype, IsBA)
	SELECT 3, 3, 'BA', 0, 1
	UNION ALL SELECT 25, 25, 'Cashout', -1, 0
	UNION ALL
	SELECT DISTINCT ISNULL(g.GroupProductId, p.ProductId), ISNULL(g.ProductId, p.ProductId), ISNULL(g.ProductName, p.ProductName), f.SportType, 0 AS IsBA
	FROM bodb02.dbo.f_LicWinLoss_ProductSportType_Sel(@ProductCodes) f
		CROSS APPLY dbo.LA_f_Products3rd(f.ProductCode) p
		LEFT JOIN dbo.LA_f_GroupProduct() g ON p.ProductId = g.ProductId

	-- Get AmountToCompany data
	CREATE TABLE #tmpData (WinlostDate SMALLDATETIME, Currency INT, Sporttype INT, IsBA BIT, AmountToCompany MONEY)
	INSERT INTO #tmpData (WinlostDate, Currency, Sporttype, IsBA, AmountToCompany)
	SELECT b.WinlostDate, b.Currency, CASE WHEN b.bettype IN (911, 912, 913, 914) THEN -1 ELSE b.sporttype END, b.isBA
		,-SUM(ISNULL(b.swinlost, 0) + ISNULL(b.mwinlost, 0) + ISNULL(b.awinlost, 0) + ISNULL(b.winlost, 0) + ISNULL(b.scomm, 0)) AS AmountToCompany
	FROM bodb_LicenseeReport.dbo.rptLicWinloss2 b WITH (NOLOCK)
		INNER JOIN @recommend r ON b.recommend = r.recommend
	WHERE b.WinlostDate BETWEEN @FromDate AND @ToDate
		AND b.roleId = 2
		AND b.statusId IN (111, 112, 113, 114, 115)
		AND b.bettype NOT IN (901, 902, 911, 912)
	GROUP BY b.recommend, b.WinlostDate, b.Currency, CASE WHEN b.bettype IN (911, 912, 913, 914) THEN -1 ELSE b.sporttype END, b.isBA -- group by on index recommend

	-- Return data
		-- Note: Saba promotion treat ProductId is max, always on bottom
	SELECT CONVERT(INT, CASE WHEN p.ProductId = 37 THEN 1000 ELSE p.ProductId END) AS ProductId, p.ProductName, t.AmountToCompany
	FROM (
		SELECT p.GroupProductId, CONVERT(MONEY, SUM(-t.AmountToCompany * e.Rate)) AS AmountToCompany
		FROM #tmpData t
			INNER JOIN @Products p ON t.Sporttype = p.Sporttype AND t.IsBA = p.IsBA
			INNER JOIN @Exchange e ON t.Currency = e.ExchangeId AND t.WinlostDate = e.ExchangeDate
		GROUP BY GroupProductId
	) t
		INNER JOIN (SELECT DISTINCT ProductId, ProductName FROM @Products) p ON t.GroupProductId = p.ProductId
	ORDER BY CASE WHEN p.ProductId = 37 THEN 1 ELSE 0 END, p.ProductId

	DROP TABLE #tmpData
END
GO