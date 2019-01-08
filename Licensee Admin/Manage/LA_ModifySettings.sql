/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE dbo.LA_ModifySettings
	@Key		VARCHAR(100),
	@Value		VARCHAR(8000),
	@ErrCode	INT = 0				OUTPUT, 
	@ErrMsg		VARCHAR(4000)= ''	OUTPUT
AS
/*	Created: 20181130@Parsons
	Task: LA-Licensee Performance Alert
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20181130@Parsons: LA - Licensee Performance Alert [#104918]

	Param's Explanation:
	EXEC LA_ModifyReportSettings @Key = N'1234', @Value = '234' 
*/
BEGIN
	SET NOCOUNT ON;
	SELECT @ErrMsg = '' , @ErrCode = 0

	IF(EXISTS(SELECT TOP 1 1 FROM dbo.LA_Settings WITH(NOLOCK) WHERE @Key = [Key]))
	BEGIN
		UPDATE dbo.LA_Settings 
		SET [Value] = @Value
		WHERE @Key = [Key]
	END
	ELSE
	BEGIN
		INSERT dbo.LA_Settings ([Key], [Value])
		VALUES (@Key, @Value)
	END

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = ERROR_MESSAGE() , @ErrCode = 504
	END
END
GO