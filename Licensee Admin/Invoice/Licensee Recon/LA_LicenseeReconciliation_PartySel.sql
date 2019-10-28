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
		- 20191015@Bruce: Get billing group by billing date [#112229]
*/
BEGIN
	SET NOCOUNT ON
	
	-- get licensees have mapped in oas_party
	--
	SELECT CustId, LicenseeName
		, CAST(NULL AS INT) ParentId
		, CAST(NULL AS INT) PartyId
		, CAST(NULL AS VARCHAR(50)) LicenseeCode
		, CAST(NULL AS INT) BaseCurrencyId
		, CAST(NULL AS DATE) StartDate
		, CAST(NULL AS DATE) EndDate
	INTO #licensees
	FROM DBCUST.bodb_licensee.dbo.LicenseeTransferCode tc WITH(NOLOCK)
	WHERE tc.StatusId = 1

	UPDATE l SET 
		LicenseeCode = UPPER(c.username),
		BaseCurrencyId = c.currency
	FROM #licensees l
	INNER JOIN bodb02.dbo.Customer c WITH(NOLOCK) ON l.CustId=c.CustId

	DECLARE @UnofficialGroup INT = 1000
	DECLARE @UnidentifiedGroup INT = 1002
	
	-- official licensees
	--
	UPDATE l SET
		l.LicenseeName = p.Partyname,
		l.BaseCurrencyId = d.BaseCurrencyId,
		l.PartyId = d.PartyID
	FROM #licensees l
	INNER JOIN dbo.Licensees ls WITH(NOLOCK) ON l.LicenseeName = ls.LicenseeName
	INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.OldRefID = ls.LicenseeID
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.PartyID = p.PartyID
	WHERE d.StatusId = 1 AND p.PartyType = 1

	-- non-official licensees
	--
	UPDATE l SET
		l.ParentId = @UnofficialGroup,
		l.LicenseeName = p.Partyname,
		l.BaseCurrencyId = d.BaseCurrencyId,
		l.PartyId = d.PartyID
	FROM #licensees l
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.LicenseeCode = l.LicenseeCode
	INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = d.PartyID
	WHERE d.StatusId = 1 AND p.PartyType = 5

	IF @IncludeAll = 1
	BEGIN
		INSERT INTO #licensees(LicenseeName, BaseCurrencyId, PartyId,CustId, ParentId)
		SELECT p.PartyName, d.BaseCurrencyId, p.PartyID,0, CASE WHEN p.PartyType = 5 THEN @UnofficialGroup ELSE NULL END
		FROM dbo.OAS_PartyDetail d
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = d.PartyID
		WHERE p.PartyType IN (1,5)
			AND d.IsDeposit = 1
			AND p.PartyID NOT IN (SELECT l.PartyId FROM #licensees l WHERE l.PartyId > 0)
	END
	-- get charge rate
	--
	SELECT c.FromParty, c.ToParty,c.FromDate, c.ToDate
		,DATEADD(MONTH, DATEDIFF(MONTH, 0, c.FromDate), 0) StartMonth
		,DATEADD(DAY,-1,DATEADD(MONTH, DATEDIFF(MONTH, 0, c.ToDate) + 1, 0)) EndMonth
	INTO #chargeRate
	FROM dbo.OAS_ChargeInfo c WITH(NOLOCK)
	INNER JOIN dbo.LA_ChargeInfo_SystemMapping s WITH(NOLOCK) ON c.ChargeID=s.ChargeID AND s.SystemID=2
	INNER JOIN #licensees l ON l.PartyId = c.FromParty
	WHERE l.PartyId IS NOT NULL

	-- Billing group
	-- get party list in LA system
	--
	DECLARE @partyList TABLE(
		PartyId				INT,
		PartyName			VARCHAR(50),
		BrandName			VARCHAR(50),
		ParentId			INT
	)

	INSERT INTO @partyList(PartyId,PartyName,BrandName,ParentId)
	EXEC dbo.LA_PartyListSel

	IF @BillingDate IS NULL
	BEGIN
		DELETE @partyList WHERE ParentId = 999 OR (PartyId = 999 AND ParentId = 0) -- Remove credit licensees
	END
	ELSE
	BEGIN
		DELETE @partyList WHERE ParentId > 0

		;WITH a AS (
			SELECT c.FromParty, c.ToParty,ROW_NUMBER() OVER (PARTITION BY c.FromParty ORDER BY c.FromDate DESC) Number
			FROM #chargeRate c
			WHERE @BillingDate BETWEEN StartMonth AND EndMonth
				AND c.ToParty IN (SELECT b.PartyId FROM @partyList b)
		)
		INSERT INTO @partyList(PartyId,ParentId)
		SELECT FromParty,ToParty FROM a WHERE a.Number = 1
	END

	-- map billing group
	--
	UPDATE l SET ParentId = pl.ParentId
	FROM #licensees l
	INNER JOIN @partyList pl ON l.PartyId = pl.PartyId
	WHERE pl.ParentId > 0 AND l.ParentId IS NULL

	-- licensees don't have group
	-- put them to Undefined group
	--
	UPDATE #licensees SET ParentId = @UnidentifiedGroup WHERE ParentId IS NULL

	DECLARE @billingGroup TABLE(GroupId INT)
	INSERT INTO @billingGroup SELECT DISTINCT ParentId FROM #licensees

	-- get licensee's end date
	--
	;WITH a AS (
		SELECT c.FromParty,MIN(c.StartMonth) FromDate, MAX(c.EndMonth) ToDate
		FROM #chargeRate c
		WHERE c.ToParty IN (SELECT GroupId FROM @billingGroup)
		GROUP BY c.FromParty
	)
	UPDATE l SET EndDate = a.todate, StartDate=a.FromDate
	FROM #licensees l INNER JOIN a ON a.FromParty=l.PartyId

	DECLARE @defaultEndDate DATE = (SELECT MAX(EndDate) FROM #licensees)
	DECLARE @defaultStartDate DATE = (SELECT MIN(StartDate) FROM #licensees)

	-- select data
	--
	SELECT ISNULL(l.PartyId, -l.CustId) PartyId
		, l.ParentId
		, l.LicenseeName
		, l.BaseCurrencyId
		, e.Code AS BaseCurrencyCode
		, UPPER(l.LicenseeCode) LicenseeCode
		, ISNULL(l.StartDate,@defaultStartDate) StartDate
		, ISNULL(l.EndDate,@defaultEndDate) EndDate
		, l.CustId
	FROM #licensees l
	INNER JOIN bodb02.dbo.Exchange e WITH(NOLOCK) ON l.BaseCurrencyId=e.exchangeid
	WHERE (ISNULL(l.CustId,0) > 0 OR ISNULL(l.PartyId,0)>0) AND (@BillingDate IS NULL OR @BillingDate >= ISNULL(l.StartDate,@defaultStartDate))
	UNION ALL
	SELECT PartyId, 0, PartyName, 0, '', '',@defaultStartDate,@defaultEndDate,0 FROM @partyList
	WHERE ParentId = 0 AND PartyId IN (SELECT GroupId FROM @billingGroup)
	UNION ALL
	SELECT @UnofficialGroup, 0, 'Non-Official Licensees',0, '', '',@defaultStartDate,@defaultEndDate,0 FROM @billingGroup WHERE GroupId = @UnofficialGroup
	UNION ALL
	SELECT @UnidentifiedGroup, 0, 'Unidentified',0, '', '',@defaultStartDate,@defaultEndDate,0 FROM @billingGroup WHERE GroupId = @UnidentifiedGroup

	DROP TABLE #licensees
	DROP TABLE #chargeRate
END
GO
