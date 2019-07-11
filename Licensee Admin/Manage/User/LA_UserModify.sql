/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_UserModify] 
	 @UserID		INT OUTPUT
	,@GroupID		INT
	,@UserName		nvarchar(50)
	,@DisplayName	NVARCHAR(50)
	,@UserPwd		VARCHAR(50)	 = ''
	,@UserSalt		varchar(50)=''
	,@IsActive		bit
	,@Creator		INT
	,@Language		varchar(20) = 'en-us'
	,@LoginIP		VARCHAR(30)	 = ''
	,@ErrCode		INT			 = 0 OUTPUT
	,@ErrMsg		NVARCHAR(1000)	 = '' OUTPUT
AS
/*
	Created: 20140820@Florent
	Task : Add or modify a user
	DB: DBCUST.bodb_Licensee  
	
	Revisions:
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
*/
SET NOCOUNT ON

DECLARE @startRun	DATETIME
	,@endRun		DATETIME
	,@duration	INT
	,@LogSPData	VARCHAR(5000)
	,@LogSPDataOld VARCHAR(5000)

SET @startRun = GETDATE()

BEGIN
	IF EXISTS (
			SELECT TOP 1 1
			FROM dbo.LA_User WITH (NOLOCK)
			WHERE UserID = @UserID
			)
	BEGIN
		SELECT @LogSPDataOld = '<LA_UsersModify CustID="' + coalesce(cast(@UserID AS VARCHAR(10)), space(1)) + '" '
											+ 'UserName="' + coalesce(cast(UserName AS VARCHAR(20)), space(1)) + '" '
											+ 'DisplayName="' + coalesce(cast(DisplayName AS VARCHAR(20)), space(1)) + '" '
											+ 'StatusID="' + coalesce(cast(StatusID AS VARCHAR(20)), space(1)) + '" '
											+ 'ModifiedDate="' + coalesce(cast(ModifiedDate AS VARCHAR(20)), space(1)) + '" '
											+ 'Language="' + coalesce(cast(@Language AS VARCHAR(20)), space(1)) + '" '
											+ 'UserID="' + coalesce(cast(@Creator AS VARCHAR(20)), space(1)) + '" '
											+ 'IP="' + coalesce(cast(@LoginIP AS VARCHAR(30)), space(1)) + '" />'
		FROM dbo.LA_User WITH (NOLOCK)
		WHERE UserID = @UserID

		IF @UserPwd <> ''
			AND @UserSalt <> ''
		BEGIN
			UPDATE dbo.LA_User WITH (UPDLOCK)
			SET UserName = @UserName
				,DisplayName = @DisplayName
				,StatusID = @IsActive
				,ModifiedDate = GETDATE()
				,UserPwd = @UserPwd
				,UserSalt = @UserSalt
				,GroupID = @GroupID
			WHERE UserID = @UserID
		END
		ELSE
		BEGIN
			UPDATE dbo.LA_User WITH (UPDLOCK)
			SET UserName = @UserName
				,DisplayName = @DisplayName
				,StatusID = @IsActive
				,ModifiedDate = GETDATE()
				,GroupID = @GroupID
			WHERE UserID = @UserID
		END

		IF @@Error > 0
		BEGIN
			SELECT @ErrCode = 100
				,@ErrMsg = 'Fail to update information of the UserID ' + CONVERT(VARCHAR(10), @UserID)

			RETURN
		END
	END
	ELSE
	BEGIN
		IF @UserPwd = ''
			OR @UserSalt = ''
		BEGIN
			SELECT @ErrCode = 101
				,@ErrMsg = 'Password or Password Salt could not be left blank!'

			RETURN
		END
		ELSE
		BEGIN
			INSERT INTO dbo.LA_User (
				GroupID
				,Username
				,UserPwd
				,DisplayName
				,UserSalt
				,StatusID
				,Creator
				,CreatedDate
				,ModifiedDate
				)
			VALUES (
				@GroupID
				,@Username
				,@UserPwd
				,@DisplayName
				,@UserSalt
				,@IsActive
				,@Creator
				,GETDATE()
				,GETDATE()
				)
		END

		SET @UserID = SCOPE_IDENTITY()

		IF @@Error > 0
		BEGIN
			SELECT @ErrCode = 102
				,@ErrMsg = 'Fail to insert information of the UserID ' + CONVERT(VARCHAR(10), @UserID)

			RETURN
		END
	END

	SELECT @LogSPData = '<LA_UsersModify CustID="' + coalesce(cast(@UserID AS VARCHAR(10)), space(1)) + '" '
									+ 'UserName="' + coalesce(cast(@UserName AS VARCHAR(20)), space(1)) + '" '
									+ 'DisplayName="' + coalesce(cast(@DisplayName AS VARCHAR(20)), space(1)) + '" '
									+ 'StatusID="' + coalesce(cast(@IsActive AS VARCHAR(20)), space(1)) + '" '
									+ 'ModifiedDate="' + coalesce(cast(GETDATE() AS VARCHAR(20)), space(1)) + '" '
									+ 'Language="' + coalesce(cast(@Language AS VARCHAR(20)), space(1)) + '" '
									+ 'UserID="' + coalesce(cast(@Creator AS VARCHAR(20)), space(1)) + '" '
									+ 'IP="' + coalesce(cast(@LoginIP AS VARCHAR(30)), space(1)) + '" />'

	SET @endRun = getdate()
	SET @duration = datediff(millisecond, @startRun, @endRun)

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserID				= @Creator  
		,@CustID			= @UserID
		,@SPName			= 'LA_UsersModify'
		,@TrackingValue		= @LogSPData
		,@TrackingValue2	= @LogSPDataOld
		,@Duration			= @Duration
END
GO