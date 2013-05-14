ALTER PROCEDURE [dbo].[OA_UserLogout]
	@On_UserID INT
AS
SET NOCOUNT ON

/*
	Creator:  20111020@Henry
	Task: OA User Logout
	DB: DB052.bodb_Licensee

*/

Delete from OA_OnUser WHERE on_userid = @On_UserID


GO
GRANT EXECUTE ON [dbo].[OA_UserLogout] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OA_UserLogout] TO [vnteam] 