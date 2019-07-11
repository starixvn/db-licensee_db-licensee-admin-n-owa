/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO 

ALTER PROCEDURE [dbo].[OAS_Users_GetSalt]
	@Username VARCHAR(50)
AS

/*
	Created by: [20111512@Kos]
	Task: Get user salt
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190510@Percy: Move SP to DBCUST.bodb_Licensee [RedmineID: #103658]
	
	Param's Explanation:
		- @Username: Username
*/

BEGIN
	SET NOCOUNT ON

	SELECT UserSalt
	FROM dbo.OAS_Users WITH (NOLOCK)
	WHERE Username = @Username
END
GO