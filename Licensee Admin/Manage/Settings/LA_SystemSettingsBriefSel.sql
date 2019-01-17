/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE dbo.LA_SystemSettingsBriefSel
AS
/*	Created: 20190108@Bruce
	Task: LA-Licensee Performance Alert
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20190108@Bruce: create sp [#104918]
*/
BEGIN
	SET NOCOUNT ON;

	SELECT [Key], LEFT([Value], 100) AS [Value]
	FROM dbo.LA_SystemSettings WITH(NOLOCK)
END
GO