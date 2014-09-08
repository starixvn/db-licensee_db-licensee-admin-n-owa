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
*/  

CREATE TABLE #Bettype (Bettype INT)
BEGIN
		IF @ProductCode = 'SB'
			OR @ProductCode = 'BA'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid < 31
				OR typeid BETWEEN 121 AND 999
				OR typeid BETWEEN 1301 AND 1399
		END

		IF @ProductCode = 'RB'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 31 AND 33
		END

		IF @ProductCode = 'NG'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 81 AND 120
		END

		IF @ProductCode = 'LC'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 1101 AND 1199
		END

		IF @ProductCode = 'VS'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 1201 AND 1299
		END

		IF @ProductCode = 'CS'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid = 71
		END
	END

BEGIN  
	SET NOCOUNT ON   
	SELECT 
		typeid AS Bettype,
		CASE WHEN typeid BETWEEN 81 AND 120 THEN 'NG - ' + typenamee 
			 WHEN typeid BETWEEN 1201 AND 1299 THEN 'VS - '+typenamee
			 ELSE typenamee END AS BettypeName
	FROM dbo.bettype b WITH (NOLOCK) 
		INNER JOIN #Bettype bt ON b.typeid = bt.Bettype
	WHERE 
		typeid NOT IN (11,17,18,19,22,23) --currently not offer Total corners, 2nd HDP, 2nd Over/Under, Substitutes, Next Goal, Next Corner		
	
END  
DROP TABLE #Bettype
GO
GRANT VIEW DEFINITION ON [dbo].[LA_BetTypesGetAll] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_BetTypesGetAll] TO bodbAdminNet 

