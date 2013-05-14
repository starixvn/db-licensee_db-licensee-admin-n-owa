   
CREATE PROCEDURE [dbo].[OAS_Users_GetAll]   
AS  
  
/*  
 * Created by : [20111512@Kos]  
 * Task  : Get all users  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 */  
  
SET NOCOUNT ON  
  
SELECT  
	 u.UserID,  
	 u.Username,  
	 u.DisplayName,    
	 u.Role,    
	 u.IsActive,  
	 u.CreatedDate,  
	 u.ModifiedDate,  
	 u.Creator,  
	 ISNULL(p.Username, '') AS CreatorName  
FROM  
	 dbo.OAS_Users AS u WITH (NOLOCK)  
	 LEFT JOIN   
	 dbo.OAS_Users AS p WITH (NOLOCK)   
	 ON u.Creator = p.UserID  
   
GO
GRANT EXECUTE ON [dbo].[OAS_Users_GetAll] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Users_GetAll] TO [vnteam]      
  
  