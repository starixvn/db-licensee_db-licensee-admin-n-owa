ALTER PROCEDURE [dbo].[OA_UsersGetByUsername]	
	@Username varchar(50)
AS

/*
	Created by: [20111004@Henry]
	Task: Get user information
	DB: DB052.bodb_Licensee
	Revisions:
*/

SET NOCOUNT ON

	SELECT UserID
		,GroupID
		,Username
		,UserPwd
		,DisplayName
		,UserSalt
		,IsActive
		,Creator
		,CreatedDate
		,ModifiedDate
	FROM dbo.OA_Users WITH(NOLOCK)
	WHERE Username=@Username
GO

GO
GRANT EXECUTE ON [dbo].[OA_UsersGetByUsername] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_UsersGetByUsername] TO [vnteam] 