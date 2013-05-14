   
CREATE PROCEDURE [dbo].[OAS_Users_WriteLog_UserLog_RunSP]    
  @UserID   INT,    
  @CustID   INT    = 0,    
  @SPName   VARCHAR(50)  = NULL, -- USE FOR OLD FORMAT AND WILL REMOVE LATER    
  @Doing   VARCHAR(4000) = NULL, --    
  @ActionID   INT    = NULL,     
  @TrackingValue NVARCHAR(MAX) = NULL,    
  @TrackingValue2 NVARCHAR(MAX) = NULL,    
  @Duration   INT    = NULL    
AS  
  
/*  
 * Created by : [20111512@Kos]  
 * Task  : Write run store procedure log  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 *  
 * Param's Explanation:    
 *  - @UserID   : UserId perform this action   
 *  - @CustID   :   
 *  - @SPName   : Store procedure name  
 *  - @Doing   :   
 *  - @ActionID   : Log action Id  
 *  - @TrackingValue : XML string format  
 *  - @TrackingValue2 :   
 *  - @Duration   :   
 */  
    
BEGIN    
   
SET NOCOUNT ON;        
  
INSERT INTO dbo.OAS_UserLog_RunSP  
	(   
	 UserID,     
	 CustID,     
	 --SPName,    
	 Doing,    
	 ActionID,     
	 TrackingValue,    
	 TrackingValue2,    
	 Duration    
	)    
SELECT    
	 @UserID,     
	 @CustID,     
	 --@SPName,    
	 @Doing,    
	 ActionId,     
	 @TrackingValue,    
	 @TrackingValue2,    
	 @Duration    
FROM dbo.OAS_LogAction WITH (NOLOCK)   
WHERE SPName = @SPName  
  
END  
GO
GRANT EXECUTE ON [dbo].[OAS_Users_WriteLog_UserLog_RunSP] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Users_WriteLog_UserLog_RunSP] TO [vnteam]   
  
  
  
  