/*<info serverAlias="DBCUST-bodb_Licensee"></info>*/
/*
	Created: 20250626@Eddie
	DB: DBCUST-bodb_Licensee
	Task: Add new column 'BusinessUnit' [RedmineID: #231003]
*/
USE bodb_Licensee
GO

ALTER TABLE dbo.LA_Payment ADD BusinessUnit VARCHAR(50)
GO