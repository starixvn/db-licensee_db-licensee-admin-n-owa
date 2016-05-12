USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_UserLogin]    Script Date: 9/8/2014 4:58:59 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_UserLogin    Script Date: 10/21/2011 7:48:20 PM ******/
ALTER PROCEDURE [dbo].[LA_UserLogin]	
	@UserName varchar(50)
AS

/*
	Created by: 20140820@Florent
	Task: Get user and password for the login user
	DB: DB052.bodb_Licensee
	Revisions:
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
GRANT VIEW DEFINITION ON [dbo].[LA_UserLogin] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserLogin] TO bodbAdminNet 
