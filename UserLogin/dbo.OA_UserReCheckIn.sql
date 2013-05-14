ALTER PROCEDURE [dbo].[OA_User_ReCheckIn]     
	@On_UserID INT,    
	@IsKickedOut BIT = 0 OUTPUT    
AS    
SET NOCOUNT ON    


/*
	Creator:  20111020@Henry
	Task: ReCheckIN
	DB: DB052.bodb_Licensee

	Revisions:
		

*/
    
   
   
Declare @OUTPUT TABLE (IsKickedOut bit)
Declare @_On_UserID INT

SET @_On_UserID = @On_UserID

update OA_OnUser with (ROWLOCK)
set reload_time = getdate() 
OUTPUT DELETED.IsKickedOut INTO @OUTPUT
where on_userid = @_On_UserID


IF @@ROWCOUNT = 0
	SELECT @IsKickedOut = 1
ELSE IF EXISTS (SELECT 1 FROM @OUTPUT WHERE IsKickedOut = 1)
	SELECT @IsKickedOut = 1
ELSE
	SET @IsKickedOut = 0    
    


GO
GRANT EXECUTE ON [dbo].[OA_User_ReCheckIn] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OA_User_ReCheckIn] TO [vnteam]  