   
  
CREATE PROCEDURE [dbo].[OAS_Users_GetSalt]    
 @Username VARCHAR(50)  
AS    
  
/*  
 * Created by : [20111512@Kos]  
 * Task  : Get user salt  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 *  
 * Param's Explanation:    
 *  - @Username  : Username  
 */  
  
SET NOCOUNT ON  
  
SELECT UserSalt    
FROM dbo.OAS_Users WITH (NOLOCK)    
WHERE Username = @Username     
GO
GRANT EXECUTE ON [dbo].[OAS_Users_GetSalt] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Users_GetSalt] TO [vnteam]  