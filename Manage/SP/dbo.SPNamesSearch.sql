ALTER PROCEDURE [dbo].[SpNamesSearch]
	  @SpKey	VARCHAR(100)	= '%' -- Ex: OA_UserCheckIn
	, @RunOn	VARCHAR(10)		= '%' -- Ex: 201
	, @Project	VARCHAR(50)		= '%' -- Ex: OWA

AS
/*  
 * Created: 20111109@Lewis
 * Task : Search SpName by SpKey, RunOn and Project
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
		sp.SpKey	LIKE '%' + LTRIM(RTRIM(@SpKey)) + '%'
	AND
		sp.RunOn	LIKE '%' + LTRIM(RTRIM(@RunOn)) + '%'
	AND
		sp.Project	LIKE '%' + LTRIM(RTRIM(@Project)) + '%'

END

GO
GRANT EXECUTE ON [dbo].[SpNamesSearch] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[SpNamesSearch] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[SpNamesSearch] TO [vnteam]