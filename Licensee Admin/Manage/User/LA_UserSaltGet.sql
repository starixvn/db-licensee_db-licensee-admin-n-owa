USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_UserSaltGet]    Script Date: 9/8/2014 5:02:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_UserSaltGet    Script Date: 10/21/2011 7:48:20 PM ******/
ALTER PROCEDURE [dbo].[LA_UserSaltGet]  
 @UserName varchar(50)
AS  
/*  
 * Created: 20140822@Florent
 * Task : Sel Pwd Salt
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/  
BEGIN  
SET NOCOUNT ON;  

	SELECT UserSalt  
	FROM dbo.LA_User WITH(NOLOCK)  
	WHERE Username = @UserName  

END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_UserSaltGet] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserSaltGet] TO bodbAdminNet 

