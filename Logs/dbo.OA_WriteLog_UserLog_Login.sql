ALTER PROCEDURE [dbo].[OA_WriteLog_UserLog_Login]
    @UserID INT,  
    @LoginIP VARCHAR(50)='', 
    @DomainName NVARCHAR(253) = NULL,
    @Doing VARCHAR(300),
    @BrowserName NVARCHAR(255) = NULL,
    @Platform NVARCHAR(255) = NULL,
    @CountryCode VARCHAR(64) = NULL,
    @Duration INT = NULL		 
AS  
/*  
Creator:  20111020@Henry

Task: Insert login count statistic  
DB: DB052.bodb_Licensee  
 
  
Revisions:  
 
 
 
Param's Explanation:  
    • @UserID: main account login.  
    • @DomainName: Domain user login.  
    • @LoginIP: IP user login.  
    • @BrowserName: Browser user using.  
    • @Platform: Platform user login. 
    • @CountryCode: CountryCode user login.  
    • @Duration: Time process login
*/  
  
  
SET NOCOUNT ON  
	
	INSERT INTO OA_UserLog_Login (UserID,IP,LogDate,Doing,DomainName,BrowserName,Platform,CountryCode,Duration)
	values
	(
		@UserID,  
		@LoginIP, 
		GETDATE(),  
		@Doing,
		@DomainName,
		@BrowserName,
		@Platform,
		@CountryCode,
		@Duration
	)
	



GO
GRANT EXECUTE ON [dbo].[OA_WriteLog_UserLog_Login] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_WriteLog_UserLog_Login] TO [vnteam] 