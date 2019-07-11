/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO 

ALTER PROCEDURE [dbo].[OAS_Users_Logout]
	@On_UserID INT
AS

/*
	Created by: [20111512@Kos]
	Task: OAS user logout
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190510@Percy: Move SP to DBCUST.bodb_Licensee [RedmineID: #103658]
	
	Param's Explanation:
		- @On_UserID: User ID
*/

BEGIN
	SET NOCOUNT ON

	DELETE dbo.OAS_OnUser WITH (ROWLOCK, UPDLOCK)
	WHERE on_userid = @On_UserID 
END
GO