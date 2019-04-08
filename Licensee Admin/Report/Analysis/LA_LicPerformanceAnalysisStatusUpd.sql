/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].LA_LicPerformanceAnalysisStatusUpd (@Status VARCHAR(50))
AS
/*  Created: 20190307@Bruce
	Task : check generating status
	DB: DBLIC.bodb_Licensee
	Revisions:
		- 20190307@Bruce: Create SP

	Parameters:
		@Status:
			DONE		- Generating has done
			PROCESSING	- Generating is in-progress
*/
BEGIN
	UPDATE dbo.LA_SystemSettings WITH(UPDLOCK,ROWLOCK) SET [Value] = @Status WHERE [Key] = 'LicenseePerformanceAnalysis_GeneratingStatus'
END