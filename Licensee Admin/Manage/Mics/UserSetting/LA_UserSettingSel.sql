/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_UserSettingSel]
	@UserId			INT = 0,
	@FunctionKey	NVARCHAR(100) = ''
AS
/*
	Created: 20190911@Parsons
	Task : Save query filters in LPID report [#FeatureId 119536]
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190911@Parsons: add new sp

	Param's Explannation: 
*/
BEGIN
	SET NOCOUNT ON

	SELECT Id, [Name], [Data]
	FROM [dbo].[LA_UserSettings] WITH(NOLOCK)
	WHERE (@UserId = 0 OR UserId = @UserId)
		AND (@FunctionKey = '' OR FunctionKey = @FunctionKey)
	ORDER BY [Name]
END
GO