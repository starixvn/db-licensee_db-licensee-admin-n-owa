USE bodb_licensee
GO

CREATE PROC dbo.[LA_AnalysisFileUpd]
AS
/*
	Created: BRUCE
	Date: 2017-10-18
	Task: Licensee Analysis (support raw data) #redmind: https://nexdev.net/issues/78294
	DB: bodb_licensee

	Revisions:
		- 20170919@Bruce: create SP
*/
BEGIN
	SET NOCOUNT ON
END
GO

GRANT EXECUTE ON [dbo].LA_AnalysisFileUpd TO [bodbLicenseeNet] AS [dbo]
go

GRANT EXECUTE ON [dbo].LA_AnalysisFileUpd TO [bodbAdminNet] AS [dbo]
go

GRANT VIEW DEFINITION ON [dbo].LA_AnalysisFileUpd TO [vnteam] AS [dbo]
go