/*<info serverAlias="DBCUST-CustDB" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[OAS_Users_WriteLog_UserLog_Login_Wrapper]
	@UserID			INT,
	@LoginIP		VARCHAR(50) = '',
	@DomainName		NVARCHAR(253) = NULL,
	@Doing			VARCHAR(300),
	@BrowserName	NVARCHAR(255) = NULL,
	@Platform		NVARCHAR(255) = NULL,
	@CountryCode	VARCHAR(64) = NULL,
	@Duration		INT = NULL
AS

/*
	Created: 20190510@Percy
	Task: Insert login count statistic
	DB: DBCUST.CustDB
	
	Revisions:
		- 20190510@Percy: Initiliaze SP [RedmineID: #103658]
	
	Param's Explanation:
		- @UserID: Main account login
		- @LoginIP: IP user login
		- @DomainName: Domain user login
		- @Doing:
		- @BrowserName: Browser name user using
		- @Platform: Platform user login
		- @CountryCode: Country code user login
		- @Duration: Time process login
*/

BEGIN
	SET NOCOUNT ON

	BEGIN TRY
		EXEC DBLOG.bodb_CustomerLog.dbo.OAS_Users_WriteLog_UserLog_Login
			@UserID			= @UserID,
			@LoginIP		= @LoginIP,
			@DomainName		= @DomainName,
			@Doing			= @Doing,
			@BrowserName	= @BrowserName,
			@Platform		= @Platform,
			@CountryCode	= @CountryCode,
			@Duration		= @Duration
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.OAS_Users_WriteLog_UserLog_Login
			@UserID			= @UserID,
			@LoginIP		= @LoginIP,
			@DomainName		= @DomainName,
			@Doing			= @Doing,
			@BrowserName	= @BrowserName,
			@Platform		= @Platform,
			@CountryCode	= @CountryCode,
			@Duration		= @Duration
	END CATCH
END
GO