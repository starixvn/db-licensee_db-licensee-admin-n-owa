/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE dbo.LA_SystemSettingsBriefSel
AS
/*	Created: 20190108@Bruce
	Task: LA-Licensee Performance Alert
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20190108@Bruce: create sp [#104918]
*/
BEGIN
	SET NOCOUNT ON;

	SELECT [Key], LEFT([Value], 100) AS [Value]
	FROM dbo.LA_SystemSettings WITH(NOLOCK)
END
GO