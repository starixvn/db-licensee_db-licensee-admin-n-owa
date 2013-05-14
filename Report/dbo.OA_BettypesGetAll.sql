ALTER PROCEDURE [dbo].[OA_BetTypesGetAll]
	@ShowSB BIT = 1,
	@ShowRB BIT = 0,
	@ShowNG BIT = 0,
	@ShowBA BIT = 0,
	@ShowLC BIT = 0,
	@ShowVS	BIT = 0
AS
/*    
 Created : Kos    
 Date : 2011-11-22  
    Task : Get all bettypes  
    DB  : DB052.bodb02    
     
    Revisions:      
    - 20111212@Henry: Add prefix NG to number game bettype
    - 20120111@Henry: remove Total corners, 2nd HDP, 2nd Over/Under, Substitutes, Next Goal, Next Corner since they were not offered any more
    - 20120821@Henry: add showLC to filter Live Casino bettype
    - 20120905@Henry: add Virtual Sports
	- 20120912@Jim : correct bettype name ( for virtual sport) 
*/  

BEGIN  
	SET NOCOUNT ON   
	SELECT 
		typeid AS Bettype,
		CASE WHEN typeid BETWEEN 81 AND 120 THEN 'NG - ' + typenamee 
			 WHEN typeid BETWEEN 1201 AND 1299 THEN 'VS - '+typenamee
			 ELSE typenamee END AS BettypeName
	FROM bettype WITH (NOLOCK)
	WHERE 
		typeid NOT IN (11,17,18,19,22,23) --currently not offer Total corners, 2nd HDP, 2nd Over/Under, Substitutes, Next Goal, Next Corner
		AND
		(
			((@ShowSB=1 OR @ShowBA=1) AND (typeid < 31	OR typeid BETWEEN 121 AND 999))
			OR
			(@ShowRB=1 AND typeid BETWEEN 31 AND 33)
			OR
			(@ShowNG=1 AND typeid BETWEEN 81 AND 120)
			OR
			(@ShowLC=1 AND typeid BETWEEN 1101 AND 1199)
			OR
			(@ShowVS=1 AND typeid BETWEEN 1201 AND 1299)
		)
	
END  


GO
GRANT EXECUTE ON [dbo].[OA_BetTypesGetAll] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OA_BetTypesGetAll] TO [vnteam]   