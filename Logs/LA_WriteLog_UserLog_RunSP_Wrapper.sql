/*<info serverAlias="DBCUST-CustDB" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [CustDB]
GO

ALTER PROCEDURE [dbo].[LA_WriteLog_UserLog_RunSP_Wrapper]
	@UserID				INT
	,@CustID			INT
	,@SPName			VARCHAR(1000)
	,@Doing				NVARCHAR(MAX) = NULL
	,@TrackingValue		NVARCHAR(MAX) = NULL
	,@TrackingValue2	NVARCHAR(MAX) = NULL
	,@Duration			INT
AS

/*
	Created: 20190510@Percy
	DB: DBCUST.CustDB
	Task: LA - SP Log Wrapper

	Revisions:
		- 20190510@Percy: Initialize SP [RedmineID: #103658]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @ActionID INT = 0
	SELECT  @ActionID = ActionID FROM DBLOG.bodb_CustomerLog.dbo.LA_LogAction WITH (NOLOCK) WHERE SPName = @SPName

	BEGIN TRY
		EXEC DBLOG.bodb_CustomerLog.dbo.LA_WriteLog_UserLog_RunSP
			@UserID				= @UserID
			,@CustID			= @CustID
			,@ActionID			= @ActionID
			,@Doing				= @Doing
			,@TrackingValue		= @TrackingValue
			,@TrackingValue2	= @TrackingValue2
			,@Duration			= @Duration
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.LA_WriteLog_UserLog_RunSP
			@UserID				= @UserID
			,@CustID			= @CustID
			,@ActionID			= @ActionID
			,@Doing				= @Doing
			,@TrackingValue		= @TrackingValue
			,@TrackingValue2	= @TrackingValue2
			,@Duration			= @Duration
	END CATCH
END
GO