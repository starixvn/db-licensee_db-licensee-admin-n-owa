/*<info serverAlias="DBCUST-bodb_licensee,DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="1"></info>*/
CREATE PROCEDURE [dbo].[LA_PartyListSabaPlaySel]
AS
/*
	Created: 20250321@Eddie
	DB: DBLIC-bodb_Licensee,DBCUST-bodb_Licensee
	Task : Get list of SabaPlay payer

	Revisions:
		- 20250321@Eddie: Initialize SP [RedmineID: #217740]

	current settings:
			1	 : ONEWorks Licensees
			9	 : Cozni Licensees
			11	 : Boping Licensees
			98	 : Zelianta Licensees
			962	 : JollySports Licensees
			1235 : Double S Licensees
			999	 : Credit Licensees
			1000 : Non-Official Licensees
	Example:
		EXEC dbo.LA_PartyListSabaPlay
*/
BEGIN
	SET NOCOUNT ON

	SELECT p.PartyID, p.PartyName, d.BrandName, 9999 AS ParentID
	FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail d WITH (NOLOCK) ON p.PartyID = d.PartyID
	WHERE p.PartyType = 1 AND p.PlatformId = 2 -- only SabaPlay is launched licensee

	UNION ALL

	SELECT 9999, 'Reasternhold Licensees', '', 0
END
GO