USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_UserLogout]    Script Date: 9/8/2014 4:59:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_UserLogout    Script Date: 10/21/2011 7:48:20 PM ******/
ALTER PROCEDURE [dbo].[LA_UserLogout]
	@On_UserID INT
AS
/*
	Creator:  20140820@Florent
	Task: OA User Logout
	DB: DB052.bodb_Licensee

*/

SET NOCOUNT ON
BEGIN
    DELETE FROM dbo.LA_OnUser WHERE on_userid = @On_UserID
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_UserLogout] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserLogout] TO bodbAdminNet 
