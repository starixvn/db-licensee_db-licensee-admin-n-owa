/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[OAS_LiveCasinoGetGameType]
AS
/*    
	Created: 20130508@Jim
    Task: Add Game types filter for Live Casino Win Loss report 
    DB: DBEXT.bodb02    
     
    Revisions:      
		- 20140114@Jim: return all GameType of Live Casino
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