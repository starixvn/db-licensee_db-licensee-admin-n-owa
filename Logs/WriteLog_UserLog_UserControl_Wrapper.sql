/*<info serverAlias="DBCUST-CustDB" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [CustDB]
GO

ALTER PROCEDURE [dbo].[WriteLog_UserLog_UserControl_Wrapper]
	@CustID		INT
	,@Doing		NVARCHAR(MAX) = NULL
	,@UserID	INT = NULL
	,@TypeID	TINYINT = 0
	,@ActionID	INT = NULL
	,@Duration	INT = NULL
AS

/*
	Created: 20190510@Percy
	DB: DBCUST.CustDB
	Task: SP Log Wrapper

	Revisions:
		- 20190510@Percy: Initialize SP [RedmineID: #103658]
*/

BEGIN
	SET NOCOUNT ON

	BEGIN TRY
		EXEC DBLOG.bodb_CustomerLog.dbo.WriteLog_UserLog_UserControl
			@CustID		= @CustID
			,@Doing		= @Doing
			,@UserID	= @UserID
			,@TypeID	= @TypeID
			,@ActionID	= @ActionID
			,@Duration	= @Duration
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_UserControl
			@CustID		= @CustID
			,@Doing		= @Doing
			,@UserID	= @UserID
			,@TypeID	= @TypeID
			,@ActionID	= @ActionID
			,@Duration	= @Duration
	END CATCH
END
GO