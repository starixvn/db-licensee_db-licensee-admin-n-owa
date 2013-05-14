 set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go


ALTER  PROCEDURE [dbo].[OAS_LiveCasinoGetGameType]
AS
/*    
	Created: 20130508@Jim
    Task : Add Game types filter for Live Casino Win Loss report 
    DB  : DB052.bodb02    
     
    Revisions:      
   
*/  

BEGIN  
	SET NOCOUNT ON   
	SELECT 
		typeid 	  AS Bettype,
		typenamee AS GametypeName
	FROM bettype WITH (NOLOCK)
	WHERE 
		typeid =1101
	/*
	1101:Baccarat
	1102:Roulette
	*/
END  

GO
GRANT EXECUTE ON [dbo].[OAS_LiveCasinoGetGameType] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_LiveCasinoGetGameType] TO [vnteam]  