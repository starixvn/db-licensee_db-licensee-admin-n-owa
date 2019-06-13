   
  
  
CREATE PROCEDURE [dbo].[OAS_Users_GetByUserID]   
 @UserID INT  
AS  
  
/*  
 * Created by : [20111512@Kos]  
 * Task  : Get user information by user ID  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 *  
 * Param's Explanation:    
 *  - @UserID : User ID  
 */  
  
SET NOCOUNT ON  
  
SELECT   
	 u.UserID,  
	 u.Username,  
	 u.DisplayName,  
	 u.Role,  
	 u.IsActive,
	 u.IsTest,
	 u.Creator,  
	 u.CreatedDate,  
	 u.ModifiedDate,  
	 pu.Username AS CreatorName  
FROM   
	 dbo.OAS_Users u WITH (NOLOCK)  
	 INNER JOIN   
	 dbo.OAS_Users pu WITH (NOLOCK)   
	 ON u.Creator = pu.UserID  
WHERE u.UserID = @UserID  
GO
GRANT EXECUTE ON [dbo].[OAS_Users_GetByUserID] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Users_GetByUserID] TO [vnteam]      
    
  
  
  