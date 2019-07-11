/*<info serverAlias="DBCUST-CustDB" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/   
ALTER PROCEDURE [dbo].[OAS_Users_WriteLog_UserLog_RunSP_Wrapper]
	@UserID			INT,
	@CustID			INT = 0,
	@SPName			VARCHAR(50) = NULL,
	@Doing			VARCHAR(4000) = NULL,
	@ActionID		INT = NULL,
	@TrackingValue	NVARCHAR(MAX) = NULL,
	@TrackingValue2 NVARCHAR(MAX) = NULL,
	@Duration		INT = NULL
AS

/*
	Created by: [20111512@Kos]
	Task: Write run store procedure log
	DB: DBCUST.CustDB
	
	Revisions:
		- 20190510@Percy: Initiliaze SP [RedmineID: #103658]

	Param's Explanation:
		- @UserID: UserId perform this action
		- @CustID:
		- @SPName: Store procedure name
		- @Doing:
		- @ActionID: Log action Id
		- @TrackingValue: XML string format
		- @TrackingValue2:
		- @Duration:
*/

BEGIN
	SET NOCOUNT ON

	IF @SPName LIKE '%_xtest'
		SELECT @SPName = LEFT(@SPName, LEN(@SPName) - 6)
	ELSE IF @SPName LIKE '%_xpre'
			OR @SPName LIKE '%_UAT1'
			OR @SPName LIKE '%_UAT2'
			OR @SPName LIKE '%_UAT3'
			OR @SPName LIKE '%_UAT4'
		SELECT @SPName = LEFT(@SPName, LEN(@SPName) - 5)

	SELECT @ActionID = ISNULL(@ActionID, 0)

	IF @ActionID = 0
	BEGIN
		SELECT @ActionID = ActionID FROM DBLOG.bodb_CustomerLog.dbo.OAS_LogAction WITH (NOLOCK) WHERE SPName = @SPName
	END

	BEGIN TRY
		EXEC DBLOG.bodb_CustomerLog.dbo.OAS_Users_WriteLog_UserLog_RunSP
			@UserID			= @UserID,
			@CustID			= @CustID,
			@SPName			= @SPName,
			@Doing			= @Doing,
			@ActionID		= @ActionID,
			@TrackingValue	= @TrackingValue,
			@TrackingValue2 = @TrackingValue2,
			@Duration		= @Duration
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.OAS_Users_WriteLog_UserLog_RunSP
			@UserID			= @UserID,
			@CustID			= @CustID,
			@SPName			= @SPName,
			@Doing			= @Doing,
			@ActionID		= @ActionID,
			@TrackingValue	= @TrackingValue,
			@TrackingValue2 = @TrackingValue2,
			@Duration		= @Duration
	END CATCH
END
GO