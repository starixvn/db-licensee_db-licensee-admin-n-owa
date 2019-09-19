/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_UserSettingGet]
	@Id				INT
AS
/*
	Created: 20190916@Parsons
	Task : Save query filters in LPID report [#FeatureId 119536]
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190916@Parsons: add new sp

	Param's Explannation: 
*/
BEGIN
	SET NOCOUNT ON

	SELECT Id, [Name], [Data]
	FROM LA_UserSettings WITH(NOLOCK)
	WHERE Id = @Id
END
GO