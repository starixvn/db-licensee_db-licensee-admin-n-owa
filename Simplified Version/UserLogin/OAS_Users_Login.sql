ALTER PROCEDURE [dbo].[OAS_Users_Login]	
	@Username VARCHAR(50)
AS

/*
 *	Created by	: [20111512@Kos]
 *	Task		: Get user and password for the login user
 *	DB			: DB052.bodb_Licensee
 *	Revisions	:
 *
 *	Param's Explanation:  
 *		- @Username		: Username
 */

SET NOCOUNT ON

SELECT UserID,
	Username,
	UserPwd,
	UserSalt,
	DisplayName,
	Role,
	IsActive,
	IsTest  
FROM dbo.OAS_Users WITH (NOLOCK)
WHERE Username = @Username


GO
GRANT EXECUTE ON [dbo].[OAS_Users_Login] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Users_Login] TO [vnteam]  