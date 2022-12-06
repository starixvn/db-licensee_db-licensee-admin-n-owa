/*<info serverAlias="DBLIC-bodb_licensee,DBCUST-bodb_Licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
CREATE FUNCTION [dbo].[LA_f_CryptoPartyListSel]
(
)
RETURNS TABLE
AS

/*
	Created: 20221004@Danny
	DB: DBLIC-bodb_Licensee, DBCUST-bodb_Licensee
	Task: LA - Get Party List that support crypto currency

	Revisions:
		- 20221004@Danny Initialize function [RedmineID: #177718]
		- 20221205@Danny Remove Hx9candy From Crypto Licensee List [RedmineID: #181279]
*/
RETURN
	SELECT PartyId
	FROM dbo.OAS_Party WITH (NOLOCK)
	WHERE PartyName IN ('CandyA18')
GO
