    
  
CREATE PROCEDURE [dbo].[OAS_Users_ReCheckIn]       
 @On_UserID  INT,      
 @IsKickedOut BIT = 0 OUTPUT      
AS      
      
/*  
 * Created by : [20111512@Kos]  
 * Task  : Recheck in user  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 *  
 * Param's Explanation:    
 *  - @On_UserID : User ID  
 *  - @IsKickedOut : Is kicked out or not (output)  
 */  
  
SET NOCOUNT ON      
      
IF EXISTS (SELECT 1 FROM OAS_OnUser WITH (NOLOCK) WHERE On_UserID = @On_UserID AND isKickedOut = 1)      
BEGIN      
	SELECT @IsKickedOut = 1      
END      
ELSE     
BEGIN      
	 SELECT @IsKickedOut = 0      
   
	 UPDATE OAS_OnUser WITH (ROWLOCK, UPDLOCK)   
	 SET reload_time = GETDATE()       
	 WHERE on_userid = @On_UserID      
	       
	 IF @@ROWCOUNT = 0      
	 SELECT @IsKickedOut = 1      
END  
GO
GRANT EXECUTE ON [dbo].[OAS_Users_ReCheckIn] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Users_ReCheckIn] TO [vnteam]    
  