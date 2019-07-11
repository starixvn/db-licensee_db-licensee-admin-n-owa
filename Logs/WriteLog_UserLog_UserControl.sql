/*<info serverAlias="DBCUST-bodb_CustomerLog,DBLOG-bodb_CustomerLog" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[WriteLog_UserLog_UserControl]
	@CustID		INT
	,@Doing		NVARCHAR(MAX) = NULL
	,@UserID	INT = NULL
	,@TypeID	TINYINT = 0
	,@ActionID	INT = NULL
	,@Duration	INT = NULL
AS

/*
	Created: 20110526@Tom
	Task: Write User Log on User Control
	DB: DBCUST,bodb_CustomerLog, DBLOG.bodb_CustomerLog

	Revisions:
		- 20120606@Sophia: Change datatype of @Doing to NVARCHAR(MAX)
*/

BEGIN
	SET NOCOUNT ON

	INSERT INTO dbo.UserLog_UserControl
	(
		[CustID]
		,[LogDate]
		,[UserID]
		,[TypeID]
		,[ActionID]
		,[Duration]
		,[Doing]
	)
	VALUES
	(
		@CustID
		,GETDATE()
		,@UserID
		,@TypeID
		,@ActionID
		,@Duration
		,@Doing
	)
END
GO