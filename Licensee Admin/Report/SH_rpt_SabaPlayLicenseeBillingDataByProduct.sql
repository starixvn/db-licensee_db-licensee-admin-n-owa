/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[SH_rpt_SabaPlayLicenseeBillingDataByProduct]
	@PartyIds			VARCHAR(MAX)
	,@FromDate			DATE
	,@ToDate			DATE
	,@BaseCurrencyName	VARCHAR(10)
	,@Environment		VARCHAR(50) = 'LOCAL'
AS

/*
	Created: 20250417@Danny
	DB: DBLIC-bodb_Licensee
	Task: SabaPLay - Win Loss by Product - Billing data

	Revisions:
		- 20250417@Danny: Initialize SP [RedmineID: #217738]
	
	Parameter explanation:

	EXEC SH_rpt_SabaPlayLicenseeBillingDataByProduct
		@PartyIds = '9095,9099,9104',
		@FromDate = '2025-03-01',
		@ToDate	  = '2025-03-31',
		@BaseCurrencyName = 'USD'
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @ProductIDs VARCHAR(MAX)

	-- Get Party List
	DROP TABLE IF EXISTS #tmp_PartyList
	CREATE TABLE #tmp_PartyList (PartyId INT, PartyName VARCHAR(100))
	INSERT INTO #tmp_PartyList (PartyId, PartyName)
	SELECT PartyId, PartyName
	FROM OAS_Party op WITH(NOLOCK)
	WHERE op.PartyID IN (
		SELECT CAST(value AS INT) FROM STRING_SPLIT(@PartyIds,',')
	) AND op.PartyType = 1 AND op.PlatformId = 2

	-- Get Product List
	DROP TABLE IF EXISTS #tmp_Products
	CREATE TABLE #tmp_Products (ProductId INT, ProductName NVARCHAR(200))
	INSERT INTO #tmp_Products (ProductId, ProductName)
	SELECT ProductID, ProductName FROM bodb_LicenseeReport.dbo.SabaPlay_Products WITH(NOLOCK)

	SELECT @ProductIDs = STRING_AGG(CAST(ProductId AS VARCHAR(MAX)),',')
	FROM #tmp_Products

	DROP TABLE IF EXISTS #Result
	CREATE TABLE #Result (PartyId INT, ProductId INT,LicensingFee MONEY,Discount MONEY)
	INSERT INTO #Result(PartyId, ProductId, LicensingFee, Discount)
	EXEC dbo.SH_SabaPLay_AmountToCompanyByProduct
		@PartyIds = @PartyIds
		,@ProductIDs = @ProductIDs
		,@FromDate = @FromDate
		,@ToDate = @ToDate
		,@BaseCurrencyName = @BaseCurrencyName
		,@Environment	= @Environment

	DECLARE @Columns NVARCHAR(MAX)
	DECLARE @SQL NVARCHAR(MAX) = ''
	SELECT  @Columns = COALESCE(@Columns + ', ', '') + '[' + ProductName + '],' + '[' + ProductName + '-Discount]' FROM #tmp_Products ORDER BY ProductId

	SELECT  @SQL = '
		SELECT ''Reasternhold'' GroupName ,PartyName, ' + @Columns + '
		FROM (
			SELECT 
				tp.PartyName,
				p.ProductName AS ColName,
				r.LicensingFee AS Value
			FROM #Result r
			INNER JOIN #tmp_Products p ON r.ProductId = p.ProductId
			INNER JOIN #tmp_PartyList tp ON r.PartyId = tp.PartyId
			UNION ALL
			SELECT 
				tp.PartyName,
				p.ProductName + ''-Discount'' AS ColName,
				r.Discount AS Value
			FROM #Result r
			INNER JOIN #tmp_Products p ON r.ProductId = p.ProductId
			INNER JOIN #tmp_PartyList tp ON r.PartyId = tp.PartyId
		) AS src
		PIVOT (
			SUM(Value)
			FOR ColName IN (' + @Columns + ')
		) AS pvt
	';

	EXEC (@SQL)

END
GO
