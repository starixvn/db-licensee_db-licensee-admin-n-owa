/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_PartySel]
AS
/*	Header:
	Task : Get list of licensee for Reconciliation report
	DB: DBLIC.bodb_Licensee

	Revisions: 
		- 20190723@Bruce: Create Sp [#111586]
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

	UPDATE l SET
		l.ParentId = (CASE WHEN p.PartyType = 5 THEN @UnofficialGroup ELSE NULL END),
		l.BaseCurrencyId = d.BaseCurrencyId,
		l.PartyId = d.PartyID
	FROM #licensees l
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.LicenseeCode = l.LicenseeCode
	INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON d.PartyId = p.PartyId
	WHERE d.StatusId = 1 AND p.PartyType IN (1,5)

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

	DELETE @partyList WHERE ParentId = 999 OR (PartyId = 999 AND ParentId = 0) -- Remove credit licensees

	-- map billing group
	--
	UPDATE l SET ParentId = pl.ParentId
	FROM #licensees l
	INNER JOIN @partyList pl ON l.PartyId = pl.PartyId
	WHERE pl.ParentId > 0

	-- licensees don't have group
	-- put them to Undefined group
	--
	UPDATE #licensees SET ParentId = @UnidentifiedGroup WHERE ParentId IS NULL

	DECLARE @billingGroup TABLE(GroupId INT)
	INSERT INTO @billingGroup SELECT DISTINCT ParentId FROM #licensees

	-- select data
	--
	SELECT ISNULL(l.PartyId, -l.Custid) PartyId
		, l.ParentId
		, l.LicenseeName
		, l.BaseCurrencyId
		, e.Code AS BaseCurrencyCode
		, l.LicenseeCode
	FROM #licensees l
	INNER JOIN bodb02.dbo.Exchange e WITH(NOLOCK) ON l.BaseCurrencyId=e.exchangeid
	UNION ALL
	SELECT PartyId, 0, PartyName, 0, '', '' FROM @partyList
	WHERE ParentId = 0 AND PartyId IN (SELECT GroupId FROM @billingGroup)
	UNION ALL
	SELECT @UnofficialGroup, 0, 'Non-Official Licensees',0, '', '' FROM @billingGroup WHERE GroupId = @UnofficialGroup
	UNION ALL
	SELECT @UnidentifiedGroup, 0, 'Unidentified',0, '', '' FROM @billingGroup WHERE GroupId = @UnidentifiedGroup

	DROP TABLE #licensees
END
GO