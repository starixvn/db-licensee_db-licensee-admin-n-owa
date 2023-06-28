/*<info serverAlias="DBCUST-bodb_licensee,DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PartyListNonOfficialSel]
AS
/*
	Created: 20161109@bruce.bui
	Task : Get list of non-official payer
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20161109@Bruce: Initialize SP
		- 20221109@Malcolm: add LicenseeCode, BaseCurrencyId [RedmineID : 175860]
		- 20230623@Danny: Deploy SP on DBLIC [RedmineID : 187219]

	Params:
	Example:
		EXEC dbo.LA_PartyListNonOfficialSel
*/
BEGIN
	SET NOCOUNT ON

	-- current settings:
	--
	-- 1	: ONEWorks Licensees
	-- 11	: Boping Licensees
	-- 98	: Zelianta Licensees
	-- 999	: Credit Licensees

	-- new settings
	--
	-- 1000	: Non-Official Licensees

	SELECT p.PartyID, p.PartyName, d.BrandName, 1000 AS ParentID, n.LicenseeCode, n.BaseCurrencyId AS BaseCurrency
	FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID = d.PartyID
		OUTER APPLY (
			SELECT TOP(1) o.BaseCurrencyId, o.LicenseeCode
			FROM dbo.OAS_PartyBaseCurrency o WITH(NOLOCK)
			WHERE o.PartyID = p.PartyID
			ORDER BY o.ToDate DESC
		) AS n
	WHERE p.PartyType = 5 -- 5: non-official licensee
	
	UNION ALL

	SELECT 1000, 'Non-Official Licensees', '', 0, '', 0
END
GO