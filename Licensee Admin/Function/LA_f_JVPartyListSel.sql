/*<info serverAlias="DBLIC-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE [bodb_Licensee]
GO

ALTER FUNCTION [dbo].[LA_f_JVPartyListSel]
(
)
RETURNS TABLE
AS

/*
	Created: 20210513@Percy
	DB: DBLIC-bodb_Licensee
	Task: LA - Get Joint Venture Party List (Keep Negative Licensee Fee)

	Revisions:
		20210513@Percy: Initialize SP [RedmineID: #154992]
*/

RETURN
	SELECT PartyId
	FROM dbo.OAS_Party WITH (NOLOCK)
	WHERE PartyName IN ('9w', '9wickets', '9Wsports')
GO