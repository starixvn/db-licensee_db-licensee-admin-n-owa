ALTER PROCEDURE [dbo].[OA_SportsGetAll]
AS
/*    
 Created : Kos    
 Date : 2011-11-22  
    Task : Get all sport types  
    DB  : DB052.bodb02    
     
    Revisions:      
    20120314@Henry: get only sports <= 99
*/  

BEGIN  
	SET NOCOUNT ON   

	SELECT Sporttype,SportName  
	FROM Sports WITH (NOLOCK)  
	WHERE sporttype <= 99
END  


GO
GRANT EXECUTE ON [dbo].[OA_SportsGetAll] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OA_SportsGetAll] TO [vnteam]  