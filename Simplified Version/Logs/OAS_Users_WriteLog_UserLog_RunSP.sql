/*<info serverAlias="DBCUST-bodb_CustomerLog,DBLOG-bodb_CustomerLog" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/   
ALTER PROCEDURE [dbo].[OAS_Users_WriteLog_UserLog_RunSP]
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
	DB: DBCUST.bodb_CustomerLog, DBLOG.bodb_CustomerLog
	
	Revisions:
		- 20190510@Percy: Move SP to DBCUST.bodb_CustomerLog, DBLOG.bodb_CustomerLog [RedmineID: #103658]

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
	SET NOCOUNT ON;

	INSERT INTO dbo.OAS_UserLog_RunSP
	(
		UserID,
		CustID,
		Doing,
		ActionID,
		TrackingValue,
		TrackingValue2,
		Duration
	)
	SELECT
		@UserID,
		@CustID,
		@Doing,
		ActionId,
		@TrackingValue,
		@TrackingValue2,
		@Duration
	FROM dbo.OAS_LogAction WITH (NOLOCK)
	WHERE SPName = @SPName
END
GO