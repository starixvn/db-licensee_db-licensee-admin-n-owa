   
CREATE PROCEDURE [dbo].[OAS_Users_ResetPassword]  
 @AdminID INT,   
 @UserID  INT,   
 @Pwd  VARCHAR(50),  
 @UserSalt VARCHAR(50),     
 @Language VARCHAR(20)  = 'en-us',  
 @LoginIP VARCHAR(30)  = '',  
 @ErrCode INT    = 0   OUTPUT,    
 @ErrMsg  NVARCHAR(1000) = ''  OUTPUT    
AS  
  
/*  
 * Created by : [20111512@Kos]  
 * Task  : Reset user password  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 *  
 * Param's Explanation:    
 *  - @AdminID : Admin ID (for write log)  
 *  - @UserID : User ID  
 *  - @Pwd  : Password  
 *  - @UserSalt : User salt  
 *  - @Language : Language  
 *  - @LoginIP : Login IP address  
 *  - @ErrCode : Error code (output)  
 *  - @ErrMsg : Error message (output)  
 */  
  
SET NOCOUNT ON  
  
DECLARE   
 @startRun  DATETIME,  
 @endRun   DATETIME,  
 @duration  INT,  
 @LogSPData  VARCHAR(5000),  
 @LogSPDataOld VARCHAR(5000)    
   
SET @startRun = GETDATE()    
  
-- check if user exists  
IF NOT EXISTS (SELECT 1 FROM OAS_Users (NOLOCK) WHERE UserID = @UserID)  
BEGIN  
	 SELECT   
	  @ErrMsg = CASE @Language   
	   WHEN 'en-us' THEN 'This user does not exist!'  
	   WHEN 'zh-cn' THEN 'This user does not exist!'  
	   WHEN 'zh-tw' THEN 'This user does not exist!'  
	   WHEN 'Ja' THEN 'This user does not exist!'  
	   WHEN 'TH' THEN 'This user does not exist!'  
	   WHEN 'KO' THEN 'This user does not exist!'  
	   ELSE 'This user does not exist!'  
	   END,  
	  @ErrCode = 102   
		RETURN      
END  
  
-- update password   
UPDATE dbo.OAS_Users WITH (ROWLOCK,UPDLOCK)  
SET   
 UserPwd = @Pwd,     
 UserSalt = @UserSalt    
WHERE   
 UserID = @UserID  
   
IF @@Error > 0  
BEGIN  
 SELECT   
  @ErrCode = 1,   
  @ErrMsg = 'Fail to reset password'  
 RETURN  
END  
  
-- write log  
SELECT @LogSPData ='<OAS_Users_ResetPassword CustID="' + COALESCE(CAST(@UserID as varchar(50)), SPACE(1)) + '" ' +    
 'UserID="' + COALESCE(CAST(@AdminID as varchar(20)), SPACE(1)) + '" ' +    
 'Language="' + COALESCE(CAST(@Language as varchar(20)), SPACE(1)) + '" ' +    
 'IP="' + COALESCE(CAST(@LoginIP as varchar(30)), SPACE(1)) + '" />'    
  
SET @endRun = GETDATE()    
SET @duration = DATEDIFF(millisecond, @startRun, @endRun)     
---------------------------    
EXEC dbo.OAS_Users_WriteLog_UserLog_RunSP    
 @UserID = @AdminID,     
 @CustID = @UserID,    
 @SPName = 'OAS_Users_ResetPassword',  
 @ActionID = 2,    
 @TrackingValue = @LogSPData,    
 @TrackingValue2 = @LogSPDataOld,    
 @duration = @duration  
  
GO
GRANT EXECUTE ON [dbo].[OAS_Users_ResetPassword] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Users_ResetPassword] TO [vnteam]    
  
  
  
  
  