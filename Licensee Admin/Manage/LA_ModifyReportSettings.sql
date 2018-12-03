/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE dbo.LA_ModifyReportSettings
	@ReportSettingName		NVARCHAR(100),
	@ConfigReportSetting	NVARCHAR(MAX),
	@ErrCode			INT = 0				OUTPUT, 
	@ErrMsg				VARCHAR(4000)= ''	OUTPUT
AS
/*	Created: 20181130@Parsons
	Task: LA-Licensee Performance Alert
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20181130@Parsons: LA - Licensee Performance Alert [#104918]

	Param's Explanation:
	EXEC LA_ModifyReportSettings @ReportSettingName = N'1234', @ConfigReportSetting = '234' 
*/
BEGIN
	SET NOCOUNT ON;

	IF(EXISTS(SELECT TOP 1 1 FROM dbo.LA_ReportSettings WITH(ROWLOCK) WHERE @ReportSettingName = ReportSettingName))
	BEGIN
		UPDATE dbo.LA_ReportSettings 
		SET ConfigReportSetting = @ConfigReportSetting
		WHERE @ReportSettingName = ReportSettingName
	END
	ELSE
	BEGIN
		INSERT dbo.LA_ReportSettings (ReportSettingName, ConfigReportSetting) 
		VALUES (@ReportSettingName, @ConfigReportSetting)	
	END

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = ERROR_MESSAGE() , @ErrCode = 504
		RETURN
	END
END
GO