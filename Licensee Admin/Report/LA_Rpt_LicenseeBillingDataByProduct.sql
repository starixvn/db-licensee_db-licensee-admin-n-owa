/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeBillingDataByProduct]
	@PartyIds			VARCHAR(MAX)
	,@FromDate			DATE
	,@ToDate			DATE
	,@BaseCurrencyName	VARCHAR(10)
	,@LicenseeStatusIds	VARCHAR(100)
	,@PlatformId		TINYINT = 0
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
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20211110@Danny: Filter by OIC statuses and hide Terminated/Suspended licensees who has no bet ticket [#159296]
		- 20220218@Percy: Hide terminated/suspended licensees with amount = 0 [RedmineID: #161429]
		- 20220315@Percy: Separate Sponsorship from Saba Promotion [RedmineID: #167121]
		- 20221226@Danny: Integrate Player tips [#180703]
		- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
	
	Parameter explanation:
		@LicenseeStatusIds
			1	Up Coming
			2	Soft Launch
			3	Active
			4	Terminated
			5	Cancelled
			6	Suspended
			999 Unrecognized
*/

BEGIN
	SET NOCOUNT ON

	-- Get Party List
	CREATE TABLE #tmp_PartyList (PartyId INT, PartyName VARCHAR(100), BranchName VARCHAR(100), ParentId INT, ParentName VARCHAR(100), StatusID INT, SuspendedDate DATE, TerminatedDate DATE)
	INSERT INTO #tmp_PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC dbo.LA_PartyListSel

	CREATE TABLE #tmp_licenseeOIC (RegisteredLicenseeName NVARCHAR(50), LicenseeStatusId TINYINT)
	INSERT INTO #tmp_licenseeOIC (RegisteredLicenseeName, LicenseeStatusId)
	SELECT	RegisteredLicenseeName, LicenseeStatusId
	FROM	DBOIC.bodb_OIC.dbo.licensee WITH(NOLOCK)

	-- Remove credit licensees
	DELETE #tmp_PartyList
	WHERE (PartyId = 999 OR ParentId = 999) -- Credit licensees
		OR (ParentId > 0 AND ',' + @PartyIds + ',' NOT LIKE '%,' + CONVERT(VARCHAR(20), PartyId) + ',%')
	
	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = p.PartyName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END
	
	UPDATE p
	SET p.ParentName = REPLACE(pr.PartyName, ' Licensees', '')
	FROM #tmp_PartyList p
		INNER JOIN #tmp_PartyList pr ON p.ParentId = pr.PartyId AND p.ParentId <> 0

	DELETE #tmp_PartyList WHERE ParentId = 0

	-- Handle statusID 
	DECLARE @statusTab TABLE (StatusId INT)
	INSERT INTO @statusTab (StatusId)
	SELECT CAST (val AS INT) FROM dbo.strSplit(@LicenseeStatusIds,',')

	UPDATE t
	SET t.StatusId = CASE	WHEN la.IsDeposit = 0 THEN 3 -- Active (Credit)
							WHEN oic.LicenseeStatusId IS NULL THEN 999 -- 999: Unrecognized dummy status
							ELSE oic.LicenseeStatusId END
		,t.SuspendedDate = pd.SuspendedDate
		,t.TerminatedDate = pd.TerminatedDate
	FROM #tmp_PartyList t
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON t.PartyId = p.PartyID
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyId = pd.PartyId
		INNER JOIN dbo.Licensees la WITH (NOLOCK) ON la.LicenseeId = p.OldRefId
		LEFT JOIN #tmp_licenseeOIC oic WITH (NOLOCK) ON oic.RegisteredLicenseeName = la.LicenseeName	

	DELETE FROM #tmp_PartyList WHERE StatusId NOT IN (SELECT x.StatusId FROM @statusTab x)

	-- Get Product List
	CREATE TABLE #tmp_Products (ProductId INT, ProductName VARCHAR(50), ProductCode VARCHAR(10))
	INSERT INTO #tmp_Products (ProductId, ProductName, ProductCode)
	SELECT p.ProductId, p.ProductName, p.ProductCode
	FROM (
		SELECT ProductId, ProductName, ProductCode FROM (VALUES (0, 'Sportsbook', 'SB'), (-102, 'Discount', ''), (-101, 'Rebate', ''),  (-999, 'Total', '')) t (ProductId, ProductName, ProductCode)
		UNION ALL SELECT ProductId, ProductName, ProductPrefix FROM dbo.Product3rd WITH (NOLOCK) WHERE ProductId NOT IN (16) AND (EndOfSupportDate IS NULL OR EndOfSupportDate >= @FromDate) AND OfferSite IN (0, 2) -- Deposit only
	) p
		LEFT JOIN dbo.LA_f_GroupProduct('',@FromDate,@ToDate) g ON p.ProductId = g.ProductId AND g.ProductId <> g.GroupProductId
	WHERE g.ProductId IS NULL

	DECLARE @ProductCodes VARCHAR(MAX)
	SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM #tmp_Products WHERE ProductCode <> ''

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
		,@LicensingFeeTypeIds = '0,8' -- 0 = Normal Licensing Fee, 8 = BetCount
	
	-- Final Result
	CREATE TABLE #tmp_Result (PartyId INT, ProductId INT, LicensingFee MONEY, BetCount INT)

	INSERT INTO #tmp_Result (PartyId, ProductId, LicensingFee, BetCount)
	SELECT PartyId, ProductId, LicensingFee, BetCount
	FROM (
		SELECT r.PartyId, r.ProductId
			,SUM(CASE WHEN r.LicensingFeeTypeId = 8 THEN 0 ELSE r.LicensingFee + r.ExtraAmount END) AS LicensingFee
			,SUM(CASE WHEN r.LicensingFeeTypeId = 8 THEN ExtraAmount ELSE 0 END) AS BetCount
		FROM @Result r
		WHERE r.ProductId NOT IN (37, 74)
		GROUP BY r.PartyId, r.ProductId
		UNION ALL SELECT PartyId, -102, -SUM(Discount), 0 FROM @Result GROUP BY PartyId HAVING SUM(Discount) <> 0
		UNION ALL SELECT PartyId, -101, -SUM(Rebate), 0 FROM @Result GROUP BY PartyId HAVING SUM(Rebate) <> 0
	) t

	INSERT INTO #tmp_Result (PartyId, ProductId, LicensingFee, BetCount)
	SELECT r.PartyId, t.ProductId, t.LicensingFee, 0
	FROM (SELECT PartyId, LicensingFee, ExtraAmount FROM @Result WHERE ProductId = 37 AND LicensingFeeTypeId = 0) r
		CROSS APPLY (
			SELECT -30 AS ProductId, -LicensingFee AS LicensingFee -- SB Promotion
			UNION ALL SELECT -20, -ExtraAmount -- Sponsorship
		) t

	INSERT INTO #tmp_Result (PartyId, ProductId, LicensingFee, BetCount)
	SELECT r.PartyId, t.ProductId, t.LicensingFee, 0
	FROM (SELECT PartyId, LicensingFee, ExtraAmount FROM @Result WHERE ProductId = 74 AND LicensingFeeTypeId = 0) r
		CROSS APPLY (
			 SELECT -10 AS ProductId , ExtraAmount AS LicensingFee -- Tips
		) t

	-- Remove suspended/terminated licensees with amount = 0
	;WITH CTE_Party AS (
		SELECT PartyId FROM #tmp_PartyList WHERE TerminatedDate < @FromDate OR SuspendedDate < @FromDate
	)
	DELETE r
	FROM #tmp_Result r
		INNER JOIN CTE_Party p ON r.PartyId = p.PartyId
	WHERE r.LicensingFee = 0 AND r.BetCount = 0

	-- Sum for total
	INSERT INTO #tmp_Result (PartyId, ProductId, LicensingFee)
	SELECT PartyId, -999, SUM(LicensingFee) FROM #tmp_Result GROUP BY PartyId
	
	-- Return data
	UPDATE #tmp_Products SET ProductId = -30, ProductName = 'SB Promotion', ProductCode = '' WHERE ProductId = 37
	UPDATE #tmp_Products SET ProductId = -10, ProductName = 'Player Tips', ProductCode = '' WHERE ProductId = 74
	
	INSERT INTO #tmp_Products (ProductId, ProductName, ProductCode)
	VALUES (-20, 'Sponsorship', '')

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
	DROP TABLE #tmp_licenseeOIC
END
GO
