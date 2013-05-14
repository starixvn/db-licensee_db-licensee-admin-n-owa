ALTER PROCEDURE [dbo].[SpNamesUpdateSuffix]
	  @RunOn		VARCHAR(10)
	, @Project		VARCHAR(50)
	, @SpKeyList	VARCHAR(1000)
	, @SpSuffix		VARCHAR(20)		= ''
AS
/*
 * Created: 20111102@Lewis
 * Task : Update suffix of an SpName list
 * DB: DB052.bodb_Licensee
 *  
 * Revisions:
 Param's Explanation:
*/
SET NOCOUNT ON
	
BEGIN

	DELETE SpNames WITH (ROWLOCK,UPDLOCK)
	WHERE SpKey IN (SELECT val FROM dbo.strSplit(@SpKeyList, ';'))

	INSERT SpNames (RunOn, Project, SpKey, SpValue)
	SELECT @RunOn, @Project, val, val + @SpSuffix FROM dbo.strSplit(@SpKeyList, ';')

END

GO
GRANT EXECUTE ON [dbo].[SpNamesUpdateSuffix] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[SpNamesUpdateSuffix] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[SpNamesUpdateSuffix] TO [vnteam]