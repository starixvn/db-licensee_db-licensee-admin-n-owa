/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeBillingDataByProduct]
	@PartyIds			VARCHAR(MAX)
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(10)
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
		- 20210923@Danny: Rollback code: filter licensee status from OIC [#162115]
		- 20210812@Percy: Integrate Bitcoin - apply core function GroupProduct [RedmineID: #159691]
		- 20210909@Percy: Support Prorate min fee of Group Min Fee: apply core SP [RedmineID: #157652]
*/

BEGIN
	SET NOCOUNT ON

	-- Get Party List
	CREATE TABLE #tmp_PartyList (PartyId INT, PartyName VARCHAR(100), BranchName VARCHAR(100), ParentId INT, ParentName VARCHAR(100))
	INSERT INTO #tmp_PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC dbo.LA_PartyListSel

	-- Remove credit licensees
	DELETE #tmp_PartyList
	WHERE (PartyId = 999 OR ParentId = 999) -- Credit licensees
		OR (ParentId > 0 AND ',' + @PartyIds + ',' NOT LIKE '%,' + CONVERT(VARCHAR(20), PartyId) + ',%')
	
	UPDATE p
	SET p.ParentName = REPLACE(pr.PartyName, ' Licensees', '')
	FROM #tmp_PartyList p
		INNER JOIN #tmp_PartyList pr ON p.ParentId = pr.PartyId AND p.ParentId <> 0

	DELETE #tmp_PartyList WHERE ParentId = 0

	-- Get Product List
	CREATE TABLE #tmp_Products (ProductId INT, ProductName VARCHAR(50), ProductCode VARCHAR(10))
	INSERT INTO #tmp_Products (ProductId, ProductName, ProductCode)
	SELECT p.ProductId, p.ProductName, p.ProductCode
	FROM (
		SELECT ProductId, ProductName, ProductCode FROM (VALUES (0, 'Sportsbook', 'SB'), (-3, 'Discount', ''), (-2, 'Rebate', ''),  (-99, 'Total', '')) t (ProductId, ProductName, ProductCode)
		UNION ALL SELECT ProductId, ProductName, ProductPrefix FROM dbo.Product3rd WITH (NOLOCK) WHERE ProductId <> 16 AND (EndOfSupportDate IS NULL OR EndOfSupportDate >= @FromDate) AND OfferSite IN (0, 2) -- Deposit only
	) p
		LEFT JOIN dbo.LA_f_GroupProduct() g ON p.ProductId = g.ProductId AND g.ProductId <> g.GroupProductId
	WHERE g.ProductId IS NULL

	DECLARE @ProductCodes VARCHAR(MAX)
	SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM #tmp_Products

	DECLARE @Result TABLE
	(
		PartyId INT, ProductId INT, ProductCode VARCHAR(10), LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
		,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000)
	)
	INSERT INTO @Result
	(
		PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
		,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark
	)
	EXEC dbo.LA_AmountToCompanyByProduct
		@PartyIds = @PartyIds
		,@ProductCodes = @ProductCodes
		,@FromDate = @FromDate
		,@ToDate = @ToDate
		,@BaseCurrencyName = @BaseCurrencyName

	-- Final Result
	CREATE TABLE #tmp_Result (PartyId INT, ProductId INT, LicensingFee MONEY)
	INSERT INTO #tmp_Result (PartyId, ProductId, LicensingFee)
	SELECT PartyId, ProductId, LicensingFee
	FROM (
		SELECT r.PartyId
			,CASE WHEN r.ProductId = 37 THEN -1 ELSE r.ProductId END AS ProductId
			,CASE WHEN r.ProductId = 37 THEN -r.LicensingFee ELSE r.LicensingFee + r.ExtraAmount END AS LicensingFee
		FROM @Result r
		WHERE r.GrossLicensingFee <> 0 OR r.LicensingFee <> 0
		UNION ALL SELECT PartyId, -3, -SUM(Discount) FROM @Result GROUP BY PartyId HAVING SUM(Discount) <> 0
		UNION ALL SELECT PartyId, -2, -SUM(Rebate) FROM @Result GROUP BY PartyId HAVING SUM(Rebate) <> 0
	) t
	WHERE t.LicensingFee <> 0

	INSERT INTO #tmp_Result (PartyId, ProductId, LicensingFee)
	SELECT PartyId, -99, SUM(LicensingFee) FROM #tmp_Result GROUP BY PartyId

	-- Return data
	UPDATE #tmp_Products SET ProductId = -1, ProductName = 'SB Promotion', ProductCode = '' WHERE ProductId = 37

	DECLARE @ProductList VARCHAR(MAX), @SQL VARCHAR(MAX)
	SELECT  @ProductList = COALESCE(@ProductList + ', ', '') + '[' + ProductName + ']' FROM #tmp_Products ORDER BY ProductId

	SELECT @SQL = '
	;WITH CTE_Result AS (
		SELECT PartyId, ' + @ProductList + '
		FROM (
			SELECT r.PartyId, r.LicensingFee, p.ProductName
			FROM #tmp_Result r
				INNER JOIN #tmp_Products p ON r.ProductId = p.ProductId
		) t
		PIVOT (
			MAX(LicensingFee) FOR ProductName IN (' + @ProductList + ')
		) p
	)
	SELECT p.ParentName AS GroupName, p.PartyName AS LicenseeName, ' + @ProductList + '
	FROM #tmp_PartyList p
		INNER JOIN CTE_Result r ON p.PartyId = r.PartyId
	ORDER BY p.ParentName, p.PartyName'

	EXEC (@SQL)

	DROP TABLE #tmp_PartyList
	DROP TABLE #tmp_Products
	DROP TABLE #tmp_Result
END
GO