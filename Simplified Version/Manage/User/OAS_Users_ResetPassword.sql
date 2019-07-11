/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO 

ALTER PROCEDURE [dbo].[OAS_Users_ResetPassword]
	@AdminID	INT,
	@UserID		INT,
	@Pwd		VARCHAR(50),
	@UserSalt	VARCHAR(50),
	@Language	VARCHAR(20)  = 'en-us',
	@LoginIP	VARCHAR(30)  = '',
	@ErrCode	INT    = 0   OUTPUT,
	@ErrMsg		NVARCHAR(1000) = ''  OUTPUT
AS

/*
	Created by: [20111512@Kos]
	Task: Reset user password
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190510@Percy: Move SP to DBCUST.bodb_Licensee [RedmineID: #103658]

	Param's Explanation:
		- @AdminID: Admin ID (for write log)
		- @UserID: User ID
		- @Pwd: Password
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
   
	-- check if user exists
	IF NOT EXISTS (SELECT 1 FROM dbo.OAS_Users (NOLOCK) WHERE UserID = @UserID)
	BEGIN
		SELECT @ErrCode = 102, @ErrMsg = N'This user does not exist!'
		RETURN
	END

	-- update password   
	UPDATE dbo.OAS_Users WITH (ROWLOCK)  
	SET UserPwd		= @Pwd,
		UserSalt	= @UserSalt
	WHERE UserID = @UserID
	
	IF @@ERROR > 0
	BEGIN
		SELECT @ErrCode = 1, @ErrMsg = N'Fail to reset password'
		RETURN
	END
	
	-- write log
	SELECT @LogSPData ='<OAS_Users_ResetPassword CustID="' + COALESCE(CAST(@UserID as varchar(50)), SPACE(1)) + '" ' +
												'UserID="' + COALESCE(CAST(@AdminID as varchar(20)), SPACE(1)) + '" ' +
												'Language="' + COALESCE(CAST(@Language as varchar(20)), SPACE(1)) + '" ' +
												'IP="' + COALESCE(CAST(@LoginIP as varchar(30)), SPACE(1)) + '" />'
  
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	EXEC CustDB.dbo.OAS_Users_WriteLog_UserLog_RunSP_Wrapper
		@UserID			= @AdminID,
		@CustID			= @UserID,
		@SPName			= 'OAS_Users_ResetPassword',
		@ActionID		= 2,
		@TrackingValue	= @LogSPData,
		@TrackingValue2 = @LogSPDataOld,
		@duration		= @duration
END
GO