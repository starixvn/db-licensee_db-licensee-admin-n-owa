/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
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
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20181130@Parsons: LA - Licensee Performance Alert [#104918]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
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

	EXEC CustBD.dbo.WriteLog_UserLog_UserControl_Wrapper
		@CustID		= 0
		,@Doing		= @Doing
		,@UserID	= @UserID
		,@TypeID	= 0
		,@ActionID	= 5534
		,@Duration	= 0

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = ERROR_MESSAGE() , @ErrCode = 504
	END
END
GO