USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OAS_LiveCasinoGetGameType]    Script Date: 01/13/2014 22:49:25 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER  PROCEDURE [dbo].[OAS_LiveCasinoGetGameType]
AS
/*    
	Created: 20130508@Jim
    Task : Add Game types filter for Live Casino Win Loss report 
    DB  : DB052.bodb02    
     
    Revisions:      
		-- 20140114@Jim: return all GameType of Live Casino
*/  

BEGIN  
	SET NOCOUNT ON   
	SELECT 
		typeid 	  AS Bettype,
		typenamee AS GametypeName
	FROM bettype WITH (NOLOCK)
	WHERE 
		typeid BETWEEN 1101 AND 1199 
	ORDER BY typenamee ASC
	/*
	1101:Baccarat
	1102:Roulette
	*/
END
GO
GRANT EXECUTE ON [dbo].[OAS_LiveCasinoGetGameType] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_LiveCasinoGetGameType] TO [vnteam] AS [dbo]