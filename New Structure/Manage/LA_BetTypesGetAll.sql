USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_BetTypesGetAll]    Script Date: 9/8/2014 5:07:48 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_BetTypesGetAll]
	@ProductCode VARCHAR(10) = 'SB'
AS
/*    
 Created : FLorent	    
 Date : 2014-09-03  
    Task : Get all bettypes  
    Base on : OA_BetTypesGetAll
    DB  : DB052.bodb02    
     
    Revisions:
	- 20150302@Florent: Fix bettype of VS same name and use function LA_f_BettypeProductMapping
*/  

CREATE TABLE #Bettype (Bettype INT)
BEGIN		
	INSERT INTO #Bettype(Bettype)
	(
		SELECT Bettype 
		FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)
	)
END

BEGIN  
	SET NOCOUNT ON   
	SELECT 
		typeid AS Bettype,
		CASE WHEN typeid BETWEEN 81 AND 120 THEN 'NG - ' + b.typenamee 
			 WHEN typeid BETWEEN 1201 AND 1299 THEN 'VS - ' + b.typenamee +
				CASE WHEN b.typeid = 1204 THEN ' (Soccer)'
					 WHEN b.typeid = 1235 THEN ' (Tennis)'
					 ELSE ''
				END
			 ELSE b.typenamee END AS BettypeName
	FROM dbo.bettype b WITH (NOLOCK) 
		INNER JOIN #Bettype bt ON b.typeid = bt.Bettype
	WHERE 
		typeid NOT IN (11,17,18,19,22,23) --currently not offer Total corners, 2nd HDP, 2nd Over/Under, Substitutes, Next Goal, Next Corner		
	
END  
DROP TABLE #Bettype
GO
GRANT VIEW DEFINITION ON [dbo].[LA_BetTypesGetAll] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_BetTypesGetAll] TO bodbAdminNet 

