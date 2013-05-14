   
CREATE PROCEDURE [dbo].[OAS_Users_UpdatePassword]    
 @AdminID INT,  
 @UserID  INT,   
 @OldPwd  VARCHAR(50),     
 @NewPwd  VARCHAR(50),     
 @UserSalt VARCHAR(50),     
 @Language VARCHAR(20)  = 'en-US',    
 @LoginIP VARCHAR(20),    
 @ErrCode INT    = 0   OUTPUT,    
 @ErrMsg  NVARCHAR(4000) = ''  OUTPUT      
AS    
  
/*  
 * Created by : [20111512@Kos]  
 * Task  : update user password  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 *  
 * Param's Explanation:    
 *  - @AdminID : Admin ID (for write log)  
 *  - @UserID : User ID  
 *  - @OldPwd : Old password  
 *  - @NewPwd : New password  
 *  - @UserSalt : User salt  
 *  - @Language : Language  
 *  - @LoginIP : Login IP address  
 *  - @ErrCode : Error code (output)  
 *  - @ErrMsg : Error message (output)  
 */  
  
BEGIN    
  
 SET NOCOUNT ON;    
   
 DECLARE   
  @startRun  DATETIME,   
  @endRun   DATETIME,    
  @duration  INT,  
  @LogSPData  VARCHAR(5000),  
  @LogSPDataOld VARCHAR(5000)  
    
 SET @startRun = GETDATE()  
   
 /* check if old password is valid */  
 IF EXISTS(SELECT 1 FROM dbo.OAS_Users WITH (NOLOCK) WHERE UserID = @UserID AND UserPwd <> @OldPwd)  
 BEGIN  
	  SELECT   
	   @ErrMsg =   
		CASE @Language   
		 WHEN 'en-us' THEN 'Wrong password.'    
		 WHEN 'zh-cn' THEN N'Wrong password.'    
		 WHEN 'zh-tw' THEN N'Wrong password.'    
		 WHEN 'ja' THEN N'Wrong password.'    
		 WHEN 'TH' THEN N'Wrong password.'    
		 WHEN 'KO' THEN N'Wrong password.'    
		 ELSE N'Wrong password.'    
		END,   
	   @ErrCode = 101      
	  RETURN   
 END  
  
 /* check if user is active */  
 IF EXISTS(SELECT 1 FROM dbo.OAS_Users WITH (NOLOCK) WHERE UserID = @UserID and IsActive = 0)  
 BEGIN  
	  SELECT   
	   @ErrMsg =   
		CASE @Language   
		 WHEN 'en-us' THEN 'This user is not active.'    
		 WHEN 'zh-cn' THEN N'This user is not active.'    
		 WHEN 'zh-tw' THEN N'This user is not active.'    
		 WHEN 'ja' THEN N'This user is not active.'    
		 WHEN 'TH' THEN N'This user is not active.'    
		 WHEN 'KO' THEN N'This user is not active.'    
		 ELSE N'This user is not active.'    
		END,  
	   @ErrCode = 102  
	  RETURN   
 END  
   
 /* update password */     
 UPDATE dbo.OAS_Users WITH(UPDLOCK,ROWLOCK)  
 SET   
  UserPwd = @NewPwd,     
  UserSalt = @UserSalt    
 WHERE UserID = @UserID  
     
 IF (@@ERROR > 0)    
 BEGIN  
	  SELECT   
	   @ErrCode = 100,   
	   @ErrMsg = 'Cannot change password'    
	  RETURN  
 END  
  
 /* write log */  
 SELECT @LogSPData ='<OAS_Users_UpdatePassword CustID="' + COALESCE(CAST(@UserID AS VARCHAR(10)), SPACE(1)) + '" ' +    
  'UserID="' + COALESCE(CAST(@AdminID AS VARCHAR(20)), SPACE(1)) + '" ' +    
  'Language="' + COALESCE(CAST(@Language AS VARCHAR(20)), SPACE(1)) + '" ' +    
  'IP="' + COALESCE(CAST(@LoginIP AS VARCHAR(30)), SPACE(1)) + '" />'    
  
 SET @endRun = GETDATE()    
 SET @duration = DATEDIFF(millisecond, @startRun, @endRun)     
  
 EXEC dbo.OAS_Users_WriteLog_UserLog_RunSP    
  @UserID = @AdminID,     
  @CustID = @UserID,  
  @SPName = 'OAS_Users_UpdatePassword',  
  --@ActionID = 0,    
  @TrackingValue = @LogSPData,    
  @TrackingValue2 = @LogSPDataOld,    
  @duration = @duration  
    
 SET NOCOUNT OFF  
  
END  
  
  
GO
GRANT EXECUTE ON [dbo].[OAS_Users_UpdatePassword] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Users_UpdatePassword] TO [vnteam]    
  
  