USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_User_ReCheckIn]    Script Date: 9/8/2014 4:57:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_User_ReCheckIn]     
	@On_UserID	INT,    
	@IsKickedOut	BIT = 0 OUTPUT    
AS    

/*
	Creator:  20140820@Florent
	Task: ReCheckIN
	DB: DB052.bodb_Licensee

	Revisions:
		

*/
SET NOCOUNT ON  
BEGIN
    DECLARE @OUTPUT TABLE (IsKickedOut bit)
    DECLARE @_On_UserID INT

    SET @_On_UserID = @On_UserID

    UPDATE dbo.LA_OnUser WITH (ROWLOCK)
    SET reload_time = GETDATE() 
    OUTPUT DELETED.IsKickedOut INTO @OUTPUT
    WHERE on_userid = @_On_UserID


    IF @@ROWCOUNT = 0
	    SELECT @IsKickedOut = 1
    ELSE IF EXISTS (SELECT 1 FROM @OUTPUT WHERE IsKickedOut = 1)
	    SELECT @IsKickedOut = 1
    ELSE
	    SET @IsKickedOut = 0    
    
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_User_ReCheckIn] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_User_ReCheckIn] TO bodbAdminNet 
