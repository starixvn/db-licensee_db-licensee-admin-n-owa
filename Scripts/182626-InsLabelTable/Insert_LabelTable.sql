/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20230220@Danny
	DB: DBCUST.bodb_Licensee
	Task: Split 789y Site [#182626]
	Description: Insert Into Labels 
*/
USE bodb_Licensee
GO

INSERT INTO Labels (LicenseeID, LabelID, LabelName, AffectedDate, IsKPISummary)
SELECT	18 AS LicenseeID -- PIH
		, siteid + 1000 AS LabelID
		, Site AS LabelName
		, CONVERT(DATE,GETDATE()) AS AffectedDate
		, 0 IsKPISummary
FROM CustDB.dbo.Site WITH(NOLOCK) WHERE SiteLabel = '789y' AND Site <> '789y'