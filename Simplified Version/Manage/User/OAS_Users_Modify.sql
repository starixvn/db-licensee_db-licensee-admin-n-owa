/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO 

ALTER PROCEDURE [dbo].[OAS_Users_Modify]
	@UserID			INT				OUTPUT,
	@Username		NVARCHAR(50),
	@DisplayName	NVARCHAR(50),
	@Role			TINYINT,
	@UserPwd		VARCHAR(50)		= '',
	@UserSalt		VARCHAR(50)		= '',
	@IsActive		BIT,
 @IsTest  BIT,  
	@CreatedDate	DATETIME,
	@ModifiedDate	DATETIME,
	@Creator		INT,
	@Language		VARCHAR(20)		= 'en-us',
	@LoginIP		VARCHAR(30)		= '',
	@ErrCode		INT				= 0 OUTPUT,
	@ErrMsg			NVARCHAR(1000)	= '' OUTPUT
AS

/*
	Created by: [20111512@Kos]
	Task: Create or modify a user
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190510@Percy: Move SP to DBCUST.bodb_Licensee [RedmineID: #103658]

	Param's Explanation:
		- @UserID: User ID (output)
		- @Username: Username
		- @DisplayName: Display name
		- @Role: Role (1 : Admin, 2 : User)
		- @UserPwd: Password
		- @UserSalt: User salt
 *  - 		  @IsTest  : Is user a test user 
		- @IsActive: Is active or not
		- @CreatedDate: Created date
		- @ModifiedDate: Modified date
		- @Creator: Creator user ID
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
	IF EXISTS(SELECT 1 FROM dbo.OAS_Users WITH (NOLOCK) WHERE UserID = @UserID)
	BEGIN
		SELECT @LogSPDataOld = '<OAS_Users_Modify CustID="' + COALESCE(CAST(@UserID AS VARCHAR(10)), SPACE(1)) + '" ' +
													'UserName="' + COALESCE(CAST(UserName AS VARCHAR(20)), SPACE(1)) + '" ' +
													'DisplayName="' + COALESCE(CAST(DisplayName AS VARCHAR(20)), SPACE(1)) + '" ' +
													'Role="' + COALESCE(CAST(Role AS VARCHAR(20)), SPACE(1)) + '" ' +
													'IsActive="' + COALESCE(CAST(IsActive AS VARCHAR(20)), SPACE(1)) + '" ' +
		  'IsTest="' + COALESCE(CAST(IsTest AS VARCHAR(20)), SPACE(1)) + '" ' +    
													'ModifiedDate="' + COALESCE(CAST(ModifiedDate AS VARCHAR(20)), SPACE(1)) + '" ' +
													'Language="' + COALESCE(CAST(@Language AS VARCHAR(20)), SPACE(1)) + '" ' +
													'UserID="' + COALESCE(CAST(@Creator AS VARCHAR(20)), SPACE(1)) + '" ' +
													'IP="' + COALESCE(CAST(@LoginIP AS VARCHAR(30)), SPACE(1)) + '" />'
		FROM dbo.OAS_Users WITH (NOLOCK)
		WHERE UserID = @UserID
		   
		-- check if update password
		IF @UserPwd <> '' AND @UserSalt <> ''
		BEGIN
			UPDATE dbo.OAS_Users WITH (UPDLOCK, ROWLOCK)
			SET	Username		= @Username,
				DisplayName		= @DisplayName,
				Role			= @Role,
				IsActive		= @IsActive,
			   IsTest = @IsTest,
				ModifiedDate	= @ModifiedDate,
				UserPwd			= @UserPwd,
				UserSalt		= @UserSalt
			WHERE UserID = @UserID
		END
		ELSE
		BEGIN
			UPDATE dbo.OAS_Users WITH (UPDLOCK, ROWLOCK)
			SET UserName = @UserName,
				DisplayName = @DisplayName,
				Role = @Role,
				IsActive = @IsActive,
			   	IsTest = @IsTest,
				ModifiedDate = @ModifiedDate
			WHERE UserID = @UserID
		END

		IF @@ERROR > 0
		BEGIN
			SELECT @ErrCode = 100, @ErrMsg = 'Fail to update information of the UserID ' + CONVERT(VARCHAR(10), @UserID)
			RETURN
		END
	END
	ELSE
	BEGIN
		-- check if password and salt are valid
		IF @UserPwd = '' OR @UserSalt = ''
		BEGIN
			SELECT @ErrCode = 101, @ErrMsg = 'Password or Password Salt could not be left blank!'
			RETURN
		END
		ELSE
		BEGIN
			INSERT INTO dbo.OAS_Users 
			(
				Username,
				UserPwd,
				DisplayName,
				Role,
				UserSalt,
				IsActive,
			   IsTest,  
				Creator,
				CreatedDate,
				ModifiedDate
			)
			VALUES
			(
				@Username,
				@UserPwd,
				@DisplayName,
				@Role,
				@UserSalt,
				@IsActive,
			   @IsTest,  
				@Creator,
				@CreatedDate,
				@ModifiedDate
			)

			SET @UserID = SCOPE_IDENTITY()

			IF @@ERROR > 0
			BEGIN
				SELECT @ErrCode = 102, @ErrMsg = 'Fail to insert information of the UserID ' + CONVERT(VARCHAR(10), @UserID)
				RETURN
			END
		END
	END

	SELECT @LogSPData = '<OAS_Users_Modify CustID="'+ COALESCE(CAST(@UserID AS VARCHAR(10)), SPACE(1)) + '" ' +
											'UserName="' + COALESCE(CAST(@UserName AS VARCHAR(20)), SPACE(1)) + '" ' +
											'DisplayName="' + COALESCE(CAST(@DisplayName AS VARCHAR(20)), SPACE(1)) + '" ' +
											'Role="' + COALESCE(CAST(@Role AS VARCHAR(20)), SPACE(1)) + '" ' +
											'IsActive="' + COALESCE(CAST(@IsActive AS VARCHAR(20)), SPACE(1)) + '" ' +
 'IsTest="' + COALESCE(CAST(@IsTest AS VARCHAR(20)), SPACE(1)) + '" ' +    
											'ModifiedDate="' + COALESCE(CAST(@ModifiedDate AS VARCHAR(20)), SPACE(1)) + '" ' +
											'Language="' + COALESCE(CAST(@Language AS VARCHAR(20)), SPACE(1)) + '" ' +
											'UserID="' + COALESCE(CAST(@Creator AS VARCHAR(20)), SPACE(1)) + '" ' +
											'IP="' + COALESCE(CAST(@LoginIP AS VARCHAR(30)), SPACE(1)) + '" />'
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	EXEC CustDB.dbo.OAS_Users_WriteLog_UserLog_RunSP_Wrapper
		@UserID			= @Creator,
		@CustID			= @UserID,
		@SPName			='OAS_Users_Modify',
		@TrackingValue	= @LogSPData,
		@TrackingValue2 = @LogSPDataOld,
		@duration		= @duration
END
GO