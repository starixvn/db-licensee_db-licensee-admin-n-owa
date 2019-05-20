/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO 

ALTER PROCEDURE [dbo].[OAS_Users_UpdatePassword]
	@AdminID	INT,
	@UserID		INT,
	@OldPwd		VARCHAR(50),
	@NewPwd		VARCHAR(50),
	@UserSalt	VARCHAR(50),
	@Language	VARCHAR(20) = 'en-US',
	@LoginIP	VARCHAR(20),
	@ErrCode	INT = 0 OUTPUT,
	@ErrMsg		NVARCHAR(4000) = '' OUTPUT
AS

/*
	Created by: [20111512@Kos]
	Task: update user password
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190510@Percy: Move SP to DBCUST.bodb_Licensee [RedmineID: #103658]
	
	Param's Explanation:    
		- @AdminID: Admin ID (for write log)
		- @UserID: User ID
		- @OldPwd: Old password
		- @NewPwd: New password
		- @UserSalt: User salt
		- @Language: Language
		- @LoginIP: Login IP address
		- @ErrCode: Error code (output)
		- @ErrMsg: Error message (output)
*/

BEGIN
	SET NOCOUNT ON

	DECLARE
		@startRun		DATETIME,
		@endRun			DATETIME,
		@duration		INT,
		@LogSPData		VARCHAR(5000),
		@LogSPDataOld	VARCHAR(5000)
	
	SET @startRun = GETDATE()
   
	/* check if old password is valid */
	IF EXISTS(SELECT 1 FROM dbo.OAS_Users WITH (NOLOCK) WHERE UserID = @UserID AND UserPwd <> @OldPwd)
	BEGIN
		SELECT @ErrCode = 101, @ErrMsg = N'Wrong password.'
		RETURN
	END
	
	/* check if user is active */
	IF EXISTS(SELECT 1 FROM dbo.OAS_Users WITH (NOLOCK) WHERE UserID = @UserID and IsActive = 0)
	BEGIN
		SELECT @ErrCode = 102, @ErrMsg = N'This user is not active.'
		RETURN
	END

	/* update password */
	UPDATE dbo.OAS_Users WITH (ROWLOCK)
	SET UserPwd		= @NewPwd,
		UserSalt	= @UserSalt
	WHERE UserID = @UserID

	IF @@ERROR > 0
	BEGIN
		SELECT @ErrCode = 100, @ErrMsg = N'Cannot change password'
		RETURN
	END

	/* write log */
	SELECT @LogSPData ='<OAS_Users_UpdatePassword CustID="' + COALESCE(CAST(@UserID AS VARCHAR(10)), SPACE(1)) + '" ' +
												'UserID="' + COALESCE(CAST(@AdminID AS VARCHAR(20)), SPACE(1)) + '" ' +
												'Language="' + COALESCE(CAST(@Language AS VARCHAR(20)), SPACE(1)) + '" ' +
												'IP="' + COALESCE(CAST(@LoginIP AS VARCHAR(30)), SPACE(1)) + '" />'
  
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
  
	EXEC CustDB.dbo.OAS_Users_WriteLog_UserLog_RunSP_Wrapper
		@UserID			= @AdminID,
		@CustID			= @UserID,
		@SPName			= 'OAS_Users_UpdatePassword',
		@TrackingValue	= @LogSPData,
		@TrackingValue2 = @LogSPDataOld,
		@duration		= @duration
END  
GO