 set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go


ALTER   PROCEDURE [dbo].[OA_LiveCasinoGetGameType]
AS
/*    
	Created: 20130508@Jim
    Task : Add Game types filter for Live Casino Win Loss report 
    DB  : DB052.bodb02    
     
    Revisions:      
		-20130719@Jim: add more bettype live baccarat , live 
*/  

BEGIN  
	SET NOCOUNT ON   
	SELECT 
		typeid 	  AS Bettype,
		typenamee AS GametypeName
	FROM bettype WITH (NOLOCK)
	WHERE 
		typeid IN (1101,1102,1103,1104)
	/*
	1101:Party Baccarat
	1102:Party Roulette
	1103:Live Baccarat
	1104:Live Roulette
	*/
END  
GO
GRANT EXECUTE ON [dbo].[OA_LiveCasinoGetGameType] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_LiveCasinoGetGameType]TO [vnteam]
