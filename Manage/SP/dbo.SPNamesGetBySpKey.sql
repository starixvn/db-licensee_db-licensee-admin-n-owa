ALTER PROCEDURE [dbo].[SpNamesGetBySpKey]
	  @SpKey		VARCHAR(100)
	, @RunOn		VARCHAR(10)
	, @Project		VARCHAR(50)
AS
/*  
 * Created: 20111031@Lewis
 * Task : Get an SpName by its ID, current server (RunOn) and Project
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
		sp.SpKey		= @SpKey
		AND sp.RunOn	= @RunOn
		AND sp.Project	= @Project

END

GO
GRANT EXECUTE ON [dbo].[SpNamesGetBySpKey] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[SpNamesGetBySpKey] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[SpNamesGetBySpKey] TO [vnteam]