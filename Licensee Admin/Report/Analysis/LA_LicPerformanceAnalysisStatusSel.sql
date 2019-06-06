/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet,dwrs2" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_LicPerformanceAnalysisStatusSel]
AS
/*  Created: 20190307@Bruce
	Task : check generating status
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190307@Bruce: Create SP
*/
BEGIN
	SELECT [Value] AS [Status]
	FROM dbo.LA_SystemSettings
	WHERE [Key] = 'LicenseePerformanceAnalysis_GeneratingStatus'
END