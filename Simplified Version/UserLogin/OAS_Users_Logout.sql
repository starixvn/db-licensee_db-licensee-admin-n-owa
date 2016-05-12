ALTER PROCEDURE [dbo].[OAS_Users_Logout]
	@On_UserID INT
AS

/*
 *	Created by	: [20111512@Kos]
 *	Task		: OAS user logout
 *	DB			: DB052.bodb_Licensee
 *	Revisions	:
 *
 *	Param's Explanation:  
 *		- @On_UserID		: User ID
 */

SET NOCOUNT ON

DELETE 
FROM OAS_OnUser 
WHERE on_userid = @On_UserID 

GO
GRANT EXECUTE ON [dbo].[OAS_Users_Logout] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Users_Logout] TO [vnteam] 