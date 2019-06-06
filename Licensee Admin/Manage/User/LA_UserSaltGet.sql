/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_UserSaltGet]  
	@UserName varchar(50)
AS  
/*
	Created: 20140822@Florent
	Task : Sel Pwd Salt
	DB: DBCUST.bodb_Licensee  
	
	Revisions:
		- 20140822@Florent: Initialize SP
*/  
BEGIN  
SET NOCOUNT ON;  

	SELECT UserSalt  
	FROM dbo.LA_User WITH(NOLOCK)  
	WHERE Username = @UserName  

END
GO