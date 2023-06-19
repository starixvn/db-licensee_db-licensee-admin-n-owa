/*<info serverAlias="DBCUST-bodb_CustomerLog,DBLOG-bodb_CustomerLog" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[LA_WriteLog_UserLog_RunSP]
	@UserID				INT
	,@CustID			INT
	,@ActionID			INT
	,@TrackingValue		NVARCHAR(MAX) = NULL
	,@TrackingValue2	NVARCHAR(MAX) = NULL
	,@Duration			INT
	,@SPName			VARCHAR(1000) = NULL
	,@IP				VARCHAR(45) = NULL
AS

/*
	Created: 20190510@Percy
	DB: DBCUST.bodb_CustomerLog, DBLOG.bodb_CustomerLog
	Task: LA - SP Log

	Revisions:
		- 20190510@Percy: Initialize SP [RedmineID: #103658]
		- 20230307@Danny: Store SPName info into SPname column [RedmineID: #175125]
*/

BEGIN
	SET NOCOUNT ON

	INSERT INTO dbo.LA_UserLog_RunSP
	(
		UserID
		,CustID
		,ActionID
		,TrackingValue
		,TrackingValue2
		,Duration
		,SPName
		,IP
	)
	VALUES
	(
		@UserID
		,@CustID
		,@ActionID
		,@TrackingValue
		,@TrackingValue2
		,@Duration
		,@SPName
		,@IP
	)
END
GO