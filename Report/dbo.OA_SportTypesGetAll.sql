
ALTER  PROCEDURE [dbo].[OA_SportTypesGetAll]
	@ShowSB BIT = 0,
	@ShowRB BIT = 0,
	@ShowNG BIT = 0,
	@ShowBA BIT = 0,
	@ShowLC BIT = 0,
	@ShowVS	BIT = 0
AS
/*    
 Created : Jim   
 Date : 2012-12-02  
    Task : LicenseeAdmin - Add sports+bet types filter to current reports - Licensee Win Loss report
    DB  : DB052.bodb02    
     
    Revisions:      
    
*/  

BEGIN  
	SET NOCOUNT ON   
	SELECT Sporttype,SportName
	FROM dbo.Sports WITH (NOLOCK)  
	WHERE 
		(
			((@ShowSB=1 OR @ShowBA=1) AND Sporttype <100)
			OR (@ShowVS=1 AND Sporttype BETWEEN 180 AND 189)
			OR (@ShowNG=1 AND Sporttype=161)
			OR (@ShowRB=1 AND Sporttype=151)
			OR (@ShowLC=1 AND Sporttype=162)
		)
	ORDER BY sporttype ASC 
END   
GO
GRANT EXECUTE ON [dbo].[OA_SportTypesGetAll] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_SportTypesGetAll]TO [vnteam]