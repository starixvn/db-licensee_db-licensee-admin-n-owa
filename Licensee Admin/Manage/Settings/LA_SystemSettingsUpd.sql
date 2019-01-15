/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE dbo.LA_SystemSettingsUpd
	@Key		VARCHAR(100),
	@Value		VARCHAR(8000),
	@UserId		INT,
	@ErrCode	INT = 0				OUTPUT, 
	@ErrMsg		VARCHAR(4000)= ''	OUTPUT
AS
/*	Created: 20181130@Parsons
	Task: LA-Licensee Performance Alert
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20181130@Parsons: LA - Licensee Performance Alert [#104918]
*/
BEGIN
	SET NOCOUNT ON;
	SELECT @ErrMsg = '' , @ErrCode = 0

	IF(EXISTS(SELECT TOP 1 1 FROM dbo.LA_SystemSettings WITH(NOLOCK) WHERE @Key = [Key]))
	BEGIN
		UPDATE dbo.LA_SystemSettings WITH(ROWLOCK,UPDLOCK)
		SET [Value] = @Value
		WHERE @Key = [Key]
	END
	ELSE
	BEGIN
		INSERT dbo.LA_SystemSettings ([Key], [Value])
		VALUES (@Key, @Value)
	END

	DECLARE @Doing NVARCHAR(MAX) = (SELECT @Key AS [Key], @Value AS [Value] FOR XML PATH(''))

	EXEC DBLOG.bodb_CustomerLog.dbo.WriteLog_UserLog_UserControl
		@custid = 0,
		@doing = @Doing,
		@userid = @UserId,
		@typeid = 0,
		@actionid = 5534,
		@duration = 0

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = ERROR_MESSAGE() , @ErrCode = 504
	END
END
GO