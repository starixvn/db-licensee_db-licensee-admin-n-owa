/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_User_ReCheckIn]     
	@On_UserID		INT,    
	@IsKickedOut	BIT = 0 OUTPUT    
AS    

/*
	Creator: 20140820@Florent
	Task: ReCheckIN
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20140820@Florent: Initialize SP
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