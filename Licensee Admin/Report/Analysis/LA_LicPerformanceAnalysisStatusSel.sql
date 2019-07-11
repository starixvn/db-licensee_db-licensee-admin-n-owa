/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet,dwrs2" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_LicPerformanceAnalysisStatusSel]
AS

/*  Created: 20190307@Bruce
	Task: check generating status
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190307@Bruce: Create SP
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
*/

BEGIN
	SET NOCOUNT ON

	SELECT [Value] AS [Status]
	FROM DBCUST.bodb_Licensee.dbo.LA_SystemSettings WITH (NOLOCK)
	WHERE [Key] = 'LicenseePerformanceAnalysis_GeneratingStatus'
END
GO