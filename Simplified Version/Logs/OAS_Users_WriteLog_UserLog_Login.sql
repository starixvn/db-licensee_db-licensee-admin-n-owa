/*<info serverAlias="DBCUST-bodb_CustomerLog,DBLOG-bodb_CustomerLog" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[OAS_Users_WriteLog_UserLog_Login]
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
	Created by: [20111215@Kos]
	Task: Insert login count statistic
	DB: DBCUST.bodb_CustomerLog, DBLOG.bodb_CustomerLog
	
	Revisions:
		- 20190510@Percy: Move SP to DBCUST.bodb_CustomerLog, DBLOG.bodb_CustomerLog [RedmineID: #103658]
	
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

	INSERT INTO dbo.OAS_UserLog_Login
	(  
		UserID,
		IP,
		LogDate,
		Doing,
		DomainName,
		BrowserName,
		Platform,
		CountryCode,
		Duration
	)
	VALUES
	(
		@UserID,
		@LoginIP,
		GETDATE(),
		@Doing,
		@DomainName,
		@BrowserName,
		@Platform,
		@CountryCode,
		@Duration
	)
END
GO