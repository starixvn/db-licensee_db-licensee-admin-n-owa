ALTER PROCEDURE [dbo].[SPNamesDelete]
	@ID	INT
AS
/*
 * Created: 20111110@Lewis
 * Task : Delete SpName which have ID equals to @ID
 * DB: DB052.bodb_Licensee
 *  
 * Revisions:
 Param's Explanation:
*/
SET NOCOUNT ON
	
BEGIN

	DELETE	SpNames WITH (ROWLOCK,UPDLOCK)
	WHERE	ID = @ID

END

GO
GRANT EXECUTE ON [dbo].[SPNamesDelete] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[SPNamesDelete] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[SPNamesDelete] TO [vnteam]