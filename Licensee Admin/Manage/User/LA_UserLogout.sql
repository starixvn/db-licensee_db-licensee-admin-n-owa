/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_UserLogout]
	@On_UserID INT
AS

/*
	Creator: 20140820@Florent
	Task: OA User Logout
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20140820@Florent: Initialize SP
*/

BEGIN
	SET NOCOUNT ON

    DELETE dbo.LA_OnUser WITH (ROWLOCK, UPDLOCK) WHERE on_userid = @On_UserID
END
GO