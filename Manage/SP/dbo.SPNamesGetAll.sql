ALTER PROCEDURE [dbo].[SpNamesGetAll]
	  @RunOn	VARCHAR(10)
	, @Project	VARCHAR(50)
AS
/*  
 * Created: 20111031@Lewis
 * Task : Get all SpName on a specific server (RunOn) and project
 * DB: DB052.bodb_Licensee
 *  
 * Revisions:
 Param's Explanation:
*/
SET NOCOUNT ON
	
BEGIN

	SELECT sp.ID
		 , sp.RunOn
		 , sp.Project
		 , sp.SpKey
		 , sp.SpValue
	FROM
		dbo.SpNames AS sp (NOLOCK)
	WHERE
		sp.RunOn	= @RunOn
	AND
		sp.Project	= @Project

END 

GO
GRANT EXECUTE ON [dbo].[SpNamesGetAll] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[SpNamesGetAll] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[SpNamesGetAll] TO [vnteam]