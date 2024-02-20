/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240220@Danny
	DB: DBCUST.bodb_Licensee
	Task: Add new credit site [#201026]
	Description: Insert Into Labels 
*/
USE bodb_Licensee
GO

INSERT INTO Labels (LicenseeID, LabelID, LabelName, AffectedDate, IsKPISummary)
SELECT	18 AS LicenseeID -- PIH
		, siteid + 1000 AS LabelID
		, Site AS LabelName
		, CASE WHEN Site = '7a5555' THEN '2024-01-01' ELSE '2024-01-17' END  AS AffectedDate
		, 0 IsKPISummary
FROM CustDB.dbo.Site WITH(NOLOCK) WHERE Site IN ('7a5555','777777')