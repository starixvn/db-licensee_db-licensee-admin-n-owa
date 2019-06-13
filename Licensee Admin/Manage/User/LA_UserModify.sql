USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_UserModify]    Script Date: 9/8/2014 4:59:36 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_UserModify] 
	 @UserID		INT OUTPUT
	,@GroupID		INT
	,@UserName	NVARCHAR(50)
	,@DisplayName	NVARCHAR(50)
	,@UserPwd		VARCHAR(50)	 = ''
	,@UserSalt	VARCHAR(50)	 = ''
	,@IsActive	BIT
	,@Creator		INT
	,@Language	VARCHAR(20)	 = 'en-us'
	,@LoginIP		VARCHAR(30)	 = ''
	,@ErrCode		INT			 = 0 OUTPUT
	,@ErrMsg		NVARCHAR(1000)	 = '' OUTPUT
AS
/*  
 * Created: 20140820@Florent
 * Task : Add or modify a user
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
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
		SELECT @LogSPDataOld = '<LA_UsersModify CustID="' + coalesce(cast(@UserID AS VARCHAR(10)), space(1)) + '" ' + 'UserName="' + coalesce(cast(UserName AS VARCHAR(20)), space(1)) + '" ' + 'DisplayName="' + coalesce(cast(DisplayName AS VARCHAR(20)), space(1)
) + '" ' + 'StatusID="' + coalesce(cast(StatusID AS VARCHAR(20)), space(1)) + '" ' + 'ModifiedDate="' + coalesce(cast(ModifiedDate AS VARCHAR(20)), space(1)) + '" ' + 'Language="' + coalesce(cast(@Language AS VARCHAR(20)), space(1)) + '" ' + 'UserID="' + 
coalesce(cast(@Creator AS VARCHAR(20)), space(1)) + '" ' + 'IP="' + coalesce(cast(@LoginIP AS VARCHAR(30)), space(1)) + '" />'
		FROM dbo.LA_User WITH (NOLOCK)
		WHERE UserID = @UserID

		IF @UserPwd <> ''
			AND @UserSalt <> ''
		BEGIN
			UPDATE dbo.LA_User
			WITH (
					UPDLOCK
					,ROWLOCK
					)

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
			UPDATE dbo.LA_User
			WITH (
					UPDLOCK
					,ROWLOCK
					)

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

	SELECT @LogSPData = '<LA_UsersModify CustID="' + coalesce(cast(@UserID AS VARCHAR(10)), space(1)) + '" ' + 'UserName="' + coalesce(cast(@UserName AS VARCHAR(20)), space(1)) + '" ' + 'DisplayName="' + coalesce(cast(@DisplayName AS VARCHAR(20)), space(1)) 
+ '" ' + 'StatusID="' + coalesce(cast(@IsActive AS VARCHAR(20)), space(1)) + '" ' + 'ModifiedDate="' + coalesce(cast(GETDATE() AS VARCHAR(20)), space(1)) + '" ' + 'Language="' + coalesce(cast(@Language AS VARCHAR(20)), space(1)) + '" ' + 'UserID="' + coal
esce(cast(@Creator AS VARCHAR(20)), space(1)) + '" ' + 'IP="' + coalesce(cast(@LoginIP AS VARCHAR(30)), space(1)) + '" />'

	SET @endRun = getdate()
	SET @duration = datediff(millisecond, @startRun, @endRun)

	IF LEN(ISNULL(@LogSPDataOld, '')) = 0
	BEGIN
		SELECT @LogSPData = REPLACE(@LogSPData, 'LA_UsersModify', 'LA_UsersModify_Create')

		EXEC dbo.OA_WriteLog_UserLog_RunSP @UserID = @Creator
			,@CustID = @UserID
			,@SPName = 'LA_UsersModify_Create'
			,
			--@ActionID = 0,  
			@TrackingValue = @LogSPData
			,@TrackingValue2 = @LogSPDataOld
			,@duration = @duration
	END
	ELSE
	BEGIN
		EXEC dbo.OA_WriteLog_UserLog_RunSP @UserID = @Creator
			,@CustID = @UserID
			,@SPName = 'LA_UsersModify'
			,
			--@ActionID = 0,  
			@TrackingValue = @LogSPData
			,@TrackingValue2 = @LogSPDataOld
			,@duration = @duration
	END
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_UserModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserModify] TO bodbAdminNet 
