/*<info serverAlias="DBCUST-bodb_Licensee"></info>*/

/*
	Created: 20250319@Eddie
	DB: DBCUST-bodb_Licensee
	Task: Add new column PlatformId and initial data [RedmineId : #217740]
*/
USE bodb_Licensee
GO

ALTER TABLE dbo.OAS_Party ADD PlatformId TINYINT NULL
GO

--Initial data

UPDATE op WITH (ROWLOCK, UPDLOCK)
SET op.PlatformId = CASE WHEN op.PartyType IN (1, 5) THEN 1 ELSE op.PlatformId END
FROM dbo.OAS_Party op
GO