/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_UserLogin]	
	@UserName varchar(50)
AS

/*
	Created by: 20140820@Florent
	Task: Get user and password for the login user
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20140820@Florent: Initialize SP
*/

SET NOCOUNT ON

	SELECT UserID
		,UserName
		,UserPwd
		,UserSalt
		,DisplayName
		,GroupID
		,StatusID AS IsActive
	FROM dbo.LA_User WITH(NOLOCK)
	WHERE UserName=@UserName

GO