ALTER PROCEDURE [dbo].[SpNamesClearSuffix]
	  @RunOn	VARCHAR(10)
	, @Project	VARCHAR(50)
	, @SpSuffix	VARCHAR(20)
AS
/*
 * Created: 20111031@Lewis
 * Task : Clear all suffix of SpNames' whose suffix is identical to @SpSuffix
 * DB: DB052.bodb_Licensee
 *  
 * Revisions:
 Param's Explanation:
*/
SET NOCOUNT ON
	
BEGIN

	UPDATE SpNames
	SET
		SpValue = SpKey
	WHERE
		RunOn	=		@RunOn
	AND	Project	=		@Project
	AND	SpValue LIKE	'%' + @SpSuffix

END

GO
GRANT EXECUTE ON [dbo].[SpNamesClearSuffix] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[SpNamesClearSuffix] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[SpNamesClearSuffix] TO [vnteam]