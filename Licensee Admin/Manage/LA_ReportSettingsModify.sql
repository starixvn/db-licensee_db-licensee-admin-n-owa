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
	DB: DB052.bodb_Licensee

	Revisions:
		- 20181130@Parsons: LA - Licensee Performance Alert [#104918]

	Param's Explanation:
	EXEC LA_ModifyReportSettings @ReportSettingName = N'1234', @ConfigReportSetting = '234' 
*/
BEGIN
	SET NOCOUNT ON;

	;WITH cte_reportSettings AS 
	(
		SELECT @ReportSettingName AS ReportSettingName, @ConfigReportSetting AS ConfigReportSetting
	)
	MERGE dbo.LA_ReportSettings WITH(ROWLOCK) AS t
	USING cte_reportSettings AS s
	ON t.ReportSettingName = s.ReportSettingName
	WHEN MATCHED THEN 
		UPDATE SET t.ConfigReportSetting = s.ConfigReportSetting
	WHEN NOT MATCHED BY TARGET THEN 
		INSERT (ReportSettingName, ConfigReportSetting) 
		VALUES (s.ReportSettingName, s.ConfigReportSetting)	
	;

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Modify failed. Please try again.' , @ErrCode = 504
		RETURN
	END
END
GO