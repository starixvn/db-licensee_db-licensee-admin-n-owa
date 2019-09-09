/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

CREATE PROCEDURE [dbo].[LA_LicenseeReconciliation_PartySel]
AS
/*	Header:
	Task : Get list of licensee for Reconciliation report
	DB: DBCUST-bodb_licensee

	Revisions: 
		- 20190723@Bruce: Create Sp [#111586]
*/
BEGIN
	SET NOCOUNT ON
	
	-- get licensees have mapped in oas_party
	--
	SELECT tc.CustId,d.LicenseeCode,d.BaseCurrencyId
		, CAST(NULL AS INT) ParentId
		, ISNULL(d.partyId, tc.CustId) PartyId
		, tc.LicenseeName AS PartyName
	INTO #licensees
	FROM bodb_licensee.dbo.LicenseeTransferCode tc WITH(NOLOCK)
	LEFT JOIN bodb_licensee.dbo.Licensees l WITH(NOLOCK) ON tc.LicenseeName=l.LicenseeName
	LEFT JOIN bodb_licensee.dbo.oas_party p WITH(NOLOCK) ON l.LicenseeID=p.OldRefID AND p.PartyType IN (1,5)
	LEFT JOIN bodb_licensee.dbo.oas_partydetail d WITH(NOLOCK) ON p.PartyID=d.PartyID
	WHERE tc.statusid=1
	
	-- for those licensees haven't mapped
	-- get data from dbo.customer
	--
	UPDATE l SET LicenseeCode = c.username, BaseCurrencyId = c.currency
	FROM #licensees l
	INNER JOIN CustDB.dbo.Customer c WITH(NOLOCK) ON l.CustId=c.CustId
	WHERE ISNULL(l.LicenseeCode,'') = ''

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

	INSERT INTO @partyList(PartyId,PartyName,BrandName,ParentId)
	EXEC dbo.LA_PartyListNonOfficialSel

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
	DECLARE @Unidentified INT = 1002
	UPDATE #licensees SET ParentId = @Unidentified WHERE ParentId IS NULL

	DECLARE @billingGroup TABLE(GroupId INT)
	INSERT INTO @billingGroup SELECT DISTINCT ParentId FROM #licensees

	-- select data
	--
	SELECT l.PartyId, l.BaseCurrencyId, l.ParentId,l.PartyName
		, e.Code AS BaseCurrencyCode
		, l.LicenseeCode
	FROM #licensees l
	INNER JOIN CustDB.dbo.Exchange e WITH(NOLOCK) ON l.BaseCurrencyId=e.exchangeid
	WHERE ISNULL(l.LicenseeCode,'') <> ''
	UNION ALL
	SELECT PartyId, 0, 0, PartyName, '', '' FROM @partyList
	WHERE ParentId = 0 AND PartyId IN (SELECT GroupId FROM @billingGroup)
	UNION ALL
	SELECT @Unidentified, 0, 0, 'Unidentified', '', '' FROM @billingGroup WHERE GroupId = @Unidentified

	DROP TABLE #licensees
END
GO