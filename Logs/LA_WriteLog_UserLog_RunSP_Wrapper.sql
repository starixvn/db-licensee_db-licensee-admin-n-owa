/*<info serverAlias="DBCUST-CustDB" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [CustDB]
GO

ALTER PROCEDURE [dbo].[LA_WriteLog_UserLog_RunSP_Wrapper]
	@UserID				INT
	,@CustID			INT
	,@SPName			VARCHAR(1000)
	,@TrackingValue		NVARCHAR(MAX) = NULL
	,@TrackingValue2	NVARCHAR(MAX) = NULL
	,@Duration			INT
	,@ActionID			INT = 0
	,@IP				VARCHAR(45) = NULL
AS

/*
	Created: 20190510@Percy
	DB: DBCUST.CustDB
	Task: LA - SP Log Wrapper

	Revisions:
		- 20190510@Percy: Initialize SP [RedmineID: #103658]
		- 20230307@Danny: Add @ActionID input param [RedmineID: #175125]
*/

BEGIN
	SET NOCOUNT ON

	IF @ActionID = 0
	BEGIN
		SELECT  @ActionID = ActionID FROM DBLOG.bodb_CustomerLog.dbo.LA_LogAction WITH (NOLOCK) WHERE SPName = @SPName
	END

	BEGIN TRY
		EXEC DBLOG.bodb_CustomerLog.dbo.LA_WriteLog_UserLog_RunSP
			@UserID				= @UserID
			,@CustID			= @CustID
			,@ActionID			= @ActionID
			,@TrackingValue		= @TrackingValue
			,@TrackingValue2	= @TrackingValue2
			,@Duration			= @Duration
			,@IP				= @IP
			,@SPName			= @SPName
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.LA_WriteLog_UserLog_RunSP
			@UserID				= @UserID
			,@CustID			= @CustID
			,@ActionID			= @ActionID
			,@TrackingValue		= @TrackingValue
			,@TrackingValue2	= @TrackingValue2
			,@Duration			= @Duration
			,@IP				= @IP
			,@SPName			= @SPName
	END CATCH
END
GO