/*<info serverAlias="DBCUST-bodb_CustomerLog,DBLOG-bodb_CustomerLog" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[LA_WriteLog_UserLog_RunSP]
	@UserID				INT
	,@CustID			INT
	,@ActionID			INT
	,@Doing				NVARCHAR(MAX) = NULL
	,@TrackingValue		NVARCHAR(MAX) = NULL
	,@TrackingValue2	NVARCHAR(MAX) = NULL
	,@Duration			INT
AS

/*
	Created: 20190510@Percy
	DB: DBCUST.bodb_CustomerLog, DBLOG.bodb_CustomerLog
	Task: LA - SP Log

	Revisions:
		- 20190510@Percy: Initialize SP [RedmineID: #103658]
*/

BEGIN
	SET NOCOUNT ON

	INSERT INTO dbo.LA_UserLog_RunSP
	(
		UserID
		,CustID
		,ActionID
		,Doing
		,TrackingValue
		,TrackingValue2,
		Duration
	)
	VALUES
	(
		@UserID
		,@CustID
		,@ActionID
		,@Doing
		,@TrackingValue
		,@TrackingValue2,
		@Duration
	)
END
GO