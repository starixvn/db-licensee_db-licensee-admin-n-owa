USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_CreateUser]    Script Date: 9/8/2014 4:56:49 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_FunctionLicenseesModify    Script Date: 12/2/2011 10:33:03 AM ******/

ALTER PROCEDURE [dbo].[LA_CreateUser]
	 @UserID		INT OUTPUT
	,@GroupID		int
	,@UserName	nvarchar(50)
	,@DisplayName	nvarchar(50)
	,@UserPwd		varchar(50)=''
	,@UserSalt	varchar(50)=''
	,@IsActive	bit
	,@PartyIDs	VARCHAR(5500) --'1,2,3,4'
	,@FunctionIDs	VARCHAR(5500) --'12,15,18'
	,@Creator		INT
	,@Language	VARCHAR(20) = 'en-us'
	,@LoginIP		VARCHAR(30)=''
	,@ErrCode		INT = 0 OUTPUT  
	,@ErrMsg		NVARCHAR(1000) = '' OUTPUT 
AS
/*  
 * Created: 20140820@Florent
 * Task : Create new User and grant permission
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/

SET NOCOUNT ON
BEGIN
    --check username
  --  IF EXISTS (SELECT TOP 1 1 FROM dbo.LA_User u WITH (NOLOCK) WHERE u.UserName = @UserName)
  --  BEGIN
	 --   SELECT @ErrCode=101, @ErrMsg='User Name existing in system, please check again!'
		--RETURN
  --  END

    --insert general info
    EXEC dbo.LA_UserModify 
	    @UserID		= @UserID OUTPUT
	   ,@GroupID		= @GroupID
	   ,@UserName		= @UserName
	   ,@DisplayName	= @DisplayName
	   ,@UserPwd		= @UserPwd
	   ,@UserSalt		= @UserSalt
	   ,@IsActive		= @IsActive
	   ,@Creator		= @Creator
	   ,@Language		= @Language
	   ,@LoginIP		= @LoginIP
	   ,@ErrCode		= @ErrCode
	   ,@ErrMsg		= @ErrMsg

    --rollback
    IF @@error <> 0
    BEGIN
	   select '1'
	   DELETE dbo.LA_User WITH (ROWLOCK) WHERE UserID = @UserID
	   RETURN
    END

    --Insert User - Function permission

    EXEC dbo.LA_UserFunctionModify
		@UserID		= @UserID
	    ,@FunctionIDs	= @FunctionIDs
	    ,@Creator		= @Creator
	    ,@Language	= @Language
	    ,@LoginIP		= @LoginIP
	    ,@ErrCode		= @ErrCode
	    ,@ErrMsg		= @ErrMsg
    --rolback
    IF @@error <> 0
    BEGIN
	   select 2
	   DELETE dbo.LA_User WITH (ROWLOCK) WHERE UserID = @UserID
	   DELETE dbo.LA_UserFunction WITH (ROWLOCK) WHERE UserID = @UserID
	   RETURN
    END
    --insert User Party Permisstion
    EXEC dbo.LA_UserPartyModify
		@UserID		= @UserID
	    ,@PartyIDs	= @PartyIDs
	    ,@Creator		= @Creator
	    ,@Language	= @Language
	    ,@LoginIP		= @LoginIP
	    ,@ErrCode		= @ErrCode
	    ,@ErrMsg		= @ErrMsg
    --rollback
    IF @@error <> 0
    BEGIN
	   select 3
	   DELETE dbo.LA_User WITH (ROWLOCK) WHERE UserID = @UserID
	   DELETE dbo.LA_UserFunction WITH (ROWLOCK) WHERE UserID = @UserID
	   DELETE dbo.LA_UserParty WITH (ROWLOCK) WHERE UserID = @UserID
	   RETURN
    END
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_CreateUser] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_CreateUser] TO bodbAdminNet 

