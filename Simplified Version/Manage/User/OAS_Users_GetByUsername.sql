   
  
ALTER PROCEDURE [dbo].[OAS_Users_GetByUsername]   
 @Username VARCHAR(50)  
AS  
  
/*  
 * Created by : [20111512@Kos]  
 * Task  : Get user information by username  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 *  
 * Param's Explanation:    
 *  - @Username  : Username  
 */  
  
SET NOCOUNT ON  
  
SELECT   
	 UserID,  
	 Username,  
	 UserPwd,  
	 DisplayName,  
	 Role,  
	 UserSalt,  
	 IsActive,  
	 IsTest,
	 Creator,  
	 CreatedDate,  
	 ModifiedDate  
FROM dbo.OAS_Users WITH (NOLOCK)  
WHERE Username = @Username
GO
GRANT EXECUTE ON [dbo].[OAS_Users_GetByUsername] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Users_GetByUsername] TO [vnteam]      