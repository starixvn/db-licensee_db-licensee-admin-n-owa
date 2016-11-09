USE [bodb_licensee]
GO

CREATE PROCEDURE [dbo].[LA_PartyListNonOfficialSel]
AS
/*
	Created: 20161109@bruce.bui
	Task : Get list of non-official payer
	DB: DB052.bodb_Licensee

	Revisions:
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

	SELECT p.PartyID, p.PartyName, d.BrandName, 1000 AS ParentID
	FROM dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID = d.PartyID
	WHERE p.PartyType = 5 -- 5: non-official licensee
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_PartyListNonOfficialSel] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_PartyListNonOfficialSel] TO bodbAdminNet
