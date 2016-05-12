USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_SporttypeGetVirtualSport]    Script Date: 9/8/2014 5:06:24 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_SporttypeGetVirtualSport]
AS
/*    
 Created : Florent    
 Base on : OA_SporttypeGetVirtualSport
 Date : 2014-08-28  
    Task : Get all sport types for virtual sport 
    DB  : DB052.bodb02    
     
    Revisions:      
    
*/  

BEGIN  
	SET NOCOUNT ON   

	SELECT Sporttype,SportName  
	FROM Sports WITH (NOLOCK)  
	WHERE sporttype BETWEEN 180 AND 199
	ORDER BY sporttype ASC 
END  

GO
GRANT VIEW DEFINITION ON [dbo].[LA_SporttypeGetVirtualSport] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_SporttypeGetVirtualSport] TO bodbAdminNet 

