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

	-- Remove credit licensees
	--
	DELETE @partyList WHERE ParentId = 999 OR (PartyId = 999 AND ParentId = 0)

	-- select data
	--
	SELECT p.PartyId, p.PartyName, d.BaseCurrencyId, p.ParentId
		, e.Code AS BaseCurrencyCode
		, CASE WHEN ISNULL(d.LicenseeCode,'') = '' THEN CAST(p.PartyID AS VARCHAR(10)) ELSE d.LicenseeCode END LicenseeCode
	FROM @partyList p
	INNER JOIN dbo.OAS_Party p2 WITH(NOLOCK) ON p.PartyId=p2.PartyID
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyId=d.PartyID
	INNER JOIN bodb02.dbo.Exchange e WITH(NOLOCK) ON d.BaseCurrencyId=e.exchangeid
	WHERE d.IsDeposit = 1 AND p.ParentId > 0
	UNION ALL
	SELECT PartyId, PartyName,0,0,'','' FROM @partyList WHERE ParentId = 0
END
GO