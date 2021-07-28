/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_NAPByProductSel]
	@PartyId			INT
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

	-- Get agent list
	DECLARE @Site VARCHAR(20)
	SELECT  @Site = l.LicenseeName
	FROM dbo.Licensees l WITH (NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON l.LicenseeId = p.OldRefId AND p.PartyType IN (1, 5)
	WHERE p.PartyId = @PartyId

	DECLARE @recommend TABLE (recommend INT)
	INSERT INTO @recommend (recommend)
	SELECT c.custid
	FROM bodb02.dbo.Customer c WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Dep_CustSuper s WITH (NOLOCK) ON c.srecommend = s.custid
	WHERE s.site = @Site AND c.roleid = 2
		AND s.currency <> 20

	-- Get Exchange
	DECLARE @Exchange TABLE (ExchangeId INT, ExchangeDate SMALLDATETIME, Rate FLOAT)
	INSERT INTO @Exchange (ExchangeId, ExchangeDate, Rate)
	SELECT ExchangeId, ExchangeDate, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @BaseCurrencyName)

	-- Get Product List
	DECLARE @ProductCodes VARCHAR(MAX)
	SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductPrefix FROM bodb_Licensee.dbo.Product3rd WITH (NOLOCK)
	SELECT  @ProductCodes = 'SB,' + @ProductCodes

	DECLARE @Products TABLE (ProductId INT, ProductName VARCHAR(50), Sporttype INT, IsBA BIT)
	INSERT INTO @Products (ProductId, ProductName, Sporttype, IsBA)
	SELECT 3, 'BA', 0, 1 WHERE ',' + @ProductCodes + ',' LIKE '%,BA,%'
	UNION ALL
	SELECT
		CASE WHEN f.ProductCode = 'SB' THEN 0 ELSE p.ProductId END
		,CASE WHEN f.ProductCode = 'SB' THEN 'Sportsbook' ELSE p.ProductName END
		,f.SportType
		,0 AS IsBA
	FROM bodb02.dbo.f_LicWinLoss_ProductSportType_Sel(@ProductCodes) f
		LEFT JOIN dbo.Product3rd p WITH (NOLOCK) ON f.ProductCode = p.ProductPrefix

	-- Get AmountToCompany data
	CREATE TABLE #tmpData (recommend INT, Currency INT, WinlostDate SMALLDATETIME, Sporttype INT, IsBA BIT, LicenseeWL MONEY, AmountToCompany MONEY)
	INSERT INTO #tmpData (recommend, Currency, WinlostDate, Sporttype, IsBA, AmountToCompany)
	SELECT b.recommend, b.Currency, b.WinlostDate, b.sporttype, b.isBA
		,-SUM(ISNULL(b.swinlost, 0) + ISNULL(b.mwinlost, 0) + ISNULL(b.awinlost, 0) + ISNULL(b.winlost, 0) + ISNULL(b.scomm, 0)) AS AmountToCompany
	FROM bodb_LicenseeReport.dbo.rptLicWinloss2 b WITH (NOLOCK)
		INNER JOIN @recommend r ON b.recommend = r.recommend
	WHERE b.WinlostDate BETWEEN @FromDate AND @ToDate
		AND b.roleId = 2
		AND b.statusId IN (111, 112, 113, 114, 115)
		AND b.bettype NOT IN (901, 902, 911, 912)
	GROUP BY b.recommend, b.Currency, b.WinlostDate, b.sporttype, b.isBA

	-- Return data
	SELECT p.ProductId, p.ProductName, CONVERT(MONEY, SUM(t.AmountToCompany * e.Rate)) AS AmountToCompany
	FROM #tmpData t
		INNER JOIN @Products p ON t.Sporttype = p.Sporttype AND t.IsBA = p.IsBA
		INNER JOIN @Exchange e ON t.Currency = e.ExchangeId AND t.WinlostDate = e.ExchangeDate
	GROUP BY p.ProductId, p.ProductName
	ORDER BY p.ProductId

	DROP TABLE #tmpData
END
GO