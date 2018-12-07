/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE dbo.LA_GetReportSettings
	@ReportSettingName		NVARCHAR(100)
AS
/*	Created: 20181203@Parsons
	Task: LA-Licensee Performance Alert
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20181203@Parsons: LA - Licensee Performance Alert [#104918]

	Param's Explanation:
	EXEC LA_GetReportSettings @ReportSettingName = N'LicenseePerformanceAlert'
*/
BEGIN
	SET NOCOUNT ON;

	SELECT ConfigReportSetting
	FROM dbo.LA_ReportSettings WITH(NOLOCK) 
	WHERE @ReportSettingName = ReportSettingName
END
GO