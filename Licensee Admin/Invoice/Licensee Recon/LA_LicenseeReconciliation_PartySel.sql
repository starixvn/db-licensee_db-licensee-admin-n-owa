/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_PartySel](
	@BillingDate DATE = NULL,
	@IncludeAll BIT = 0
)
AS
/*	Header:
	Task : Get list of licensee for Reconciliation report
	DB: DBLIC.bodb_Licensee

	Revisions: 
		- 20190723@Bruce: Create Sp [#111586]
		- 20190927@Bruce: Include fromdate, todate of charge info [#120220]
		- 20191015@Bruce: Get billing group by billing date [#122229]
		- 20210323@Percy: Support duo base currency [RedmineID: #152089]
*/
BEGIN
	SET NOCOUNT ON

	IF @BillingDate IS NULL
		SET @BillingDate = CONVERT(DATE, GETDATE())
	
	DECLARE @LastDayOfMonth DATE = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, 0, @BillingDate) + 1, 0))

	DECLARE @UnOfficialGroup INT = 1000
	DECLARE @UnIdentifiedGroup INT = 1002

	-- Get Licensee
	CREATE TABLE #Licensees (CustId INT, LicenseeName VARCHAR(50), ParentId INT, PartyId INT, LicenseeCode VARCHAR(50), BaseCurrencyId INT, StartDate DATE, EndDate DATE, IsBillingCurrency BIT)
	
	INSERT INTO #Licensees (PartyId, LicenseeName, LicenseeCode, BaseCurrencyId, ParentId, IsBillingCurrency)
	SELECT DISTINCT p.PartyId, p.PartyName AS LicenseeName, UPPER(bc.LicenseeCode), bc.BaseCurrencyId
		,CASE WHEN p.PartyType = 5 THEN @UnofficialGroup END AS ParentId
		,CASE WHEN bc.ToDate >= @LastDayOfMonth THEN 1 ELSE 0 END AS IsBillingCurrency
	FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyId = pd.PartyId
		LEFT JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId
	WHERE @LastDayOfMonth >= bc.FromDate
		AND p.PartyType IN (1, 5)
		AND pd.IsDeposit = 1

	-- Get CustId from Licensee Code
	DECLARE @LicenseeCodes TABLE (CustId INT, LicenseeName VARCHAR(50), LicenseeCode VARCHAR(50), BaseCurrencyId INT, IsBillingCurrency BIT)
	WHERE @LastDayOfMonth BETWEEN FromDate AND ToDate
	FROM @LicenseeCodes lc

	UPDATE l
	SET l.CustId = lc.CustId
	FROM #Licensees l
		INNER JOIN @LicenseeCodes lc ON l.LicenseeCode = lc.LicenseeCode

	INSERT INTO @LicenseeCodes (CustId, LicenseeName, IsBillingCurrency)
	SELECT DISTINCT CustId, LicenseeName, CASE WHEN ToDate >= @LastDayOfMonth THEN 1 ELSE 0 END AS IsBillingCurrency
	FROM DBCUST.bodb_Licensee.dbo.LicenseeTransferCode WITH (NOLOCK)
	WHERE @LastDayOfMonth >= FromDate

	UPDATE lc
	SET lc.LicenseeCode = UPPER(c.UserName), lc.BaseCurrencyId = c.Currency
	FROM @LicenseeCodes lc
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON lc.CustId = c.CustId

	DELETE @LicenseeCodes WHERE LicenseeCode IS NULL

	UPDATE l
	SET l.CustId = lc.CustId
	FROM #Licensees l
		INNER JOIN @LicenseeCodes lc ON l.LicenseeCode = lc.LicenseeCode AND l.IsBillingCurrency = lc.IsBillingCurrency

	-- Exists Licensee Code but not have party, put in Unidentified group
	INSERT INTO #Licensees (CustId, LicenseeName, LicenseeCode, BaseCurrencyId, ParentId, IsBillingCurrency)
	SELECT CustId, LicenseeName, LicenseeCode, BaseCurrencyId, @UnIdentifiedGroup, IsBillingCurrency
	FROM @LicenseeCodes lc
	WHERE lc.CustId NOT IN (SELECT ISNULL(l.CustId, 0) FROM #Licensees l)
		AND lc.LicenseeName NOT IN (SELECT ISNULL(l.LicenseeName, '') FROM #Licensees l)

	-- Billing Group
	DECLARE @partyList TABLE (PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT)

	INSERT INTO @partyList (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel
	
	DELETE @partyList WHERE ParentId = 999 OR (PartyId = 999 AND ParentId = 0) -- Remove credit licensees

	UPDATE l
	SET l.ParentId = ISNULL(pl.ParentId, @UnIdentifiedGroup) -- licensees don't have group, put them to UnIdefined group
	FROM #Licensees l
		LEFT JOIN @partyList pl ON l.PartyId = pl.PartyId AND pl.ParentId > 0
	WHERE l.ParentId IS NULL

	DECLARE @billingGroup TABLE (GroupId INT)
	INSERT INTO @billingGroup (GroupId)
	SELECT DISTINCT ParentId FROM #Licensees

	-- Get FromDate, ToDate from charge rate
	;WITH CTE_ChargeRate AS (
		SELECT c.FromParty AS PartyId
			,MIN(DATEADD(MONTH, DATEDIFF(MONTH, 0, c.FromDate), 0)) AS StartMonth
			,MAX(DATEADD(DAY,-1,DATEADD(MONTH, DATEDIFF(MONTH, 0, c.ToDate) + 1, 0))) AS EndMonth
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping s WITH (NOLOCK) ON c.ChargeId = s.ChargeId AND s.SystemId = 2 -- LA
		WHERE c.ToParty IN (SELECT GroupId FROM @billingGroup)
		GROUP BY c.FromParty
			
	)
	UPDATE l
	SET l.StartDate = c.StartMonth, l.EndDate = c.EndMonth
	FROM #Licensees l
		INNER JOIN CTE_ChargeRate c ON l.PartyId = c.PartyId

	DECLARE @DefaultStartDate DATE, @DefaultEndDate DATE
	SELECT  @DefaultStartDate = MIN(StartDate), @DefaultEndDate = MAX(EndDate) FROM #Licensees

	-- Select data
	SELECT ISNULL(l.PartyId, -l.CustId) AS PartyId
		, l.ParentId
		, l.LicenseeName
		, l.BaseCurrencyId
		, e.Code AS BaseCurrencyCode
		, ISNULL(NULLIF(l.LicenseeCode, ''), CONVERT(VARCHAR(50), l.PartyId)) AS LicenseeCode
		, ISNULL(l.StartDate, @defaultStartDate) AS StartDate
		, ISNULL(l.EndDate, @defaultEndDate) AS EndDate
		, l.CustId
		, l.IsBillingCurrency
	FROM #Licensees l
		INNER JOIN bodb02.dbo.Exchange e WITH(NOLOCK) ON l.BaseCurrencyId = e.ExchangeId
	WHERE (ISNULL(l.CustId, 0) > 0 OR ISNULL(l.PartyId, 0) > 0)
	
	UNION ALL
	SELECT PartyId, 0, PartyName, 0, '', '', @defaultStartDate, @defaultEndDate, 0, 1 FROM @partyList
	WHERE ParentId = 0 AND PartyId IN (SELECT GroupId FROM @billingGroup)
	UNION ALL
	SELECT @UnofficialGroup, 0, 'Non-Official Licensees', 0, '', '', @defaultStartDate, @defaultEndDate, 0, 1 FROM @billingGroup WHERE GroupId = @UnofficialGroup
	UNION ALL
	SELECT @UnidentifiedGroup, 0, 'Unidentified', 0, '', '', @defaultStartDate, @defaultEndDate, 0, 1 FROM @billingGroup WHERE GroupId = @UnidentifiedGroup

	DROP TABLE #Licensees
	DROP TABLE #Licensees
END
GO