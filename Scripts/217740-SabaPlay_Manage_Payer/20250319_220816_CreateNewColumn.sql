/*<info serverAlias="DBCUST-bodb_Licensee,DBLIC-bodb_Licensee,DBACC-bodb_Licensee"></info>*/

/*
	Created: 20250319@Eddie
	DB: DBLIC-bodb_Licensee
	Task: Add new column PlatformId and initial data [RedmineId : #217740]
*/
USE bodb_Licensee
GO

ALTER TABLE dbo.OAS_Party
	ADD PlatformId TINYINT NOT NULL CONSTRAINT [DF_OAS_Party_PlatformId] DEFAULT ((0))
GO

--Initial data

UPDATE op WITH (ROWLOCK, UPDLOCK)
SET op.PlatformId = CASE op.PartyType WHEN 1 THEN 1 -- Saba Sports
									  WHEN 5 THEN 1 -- Saba Sports
					ELSE 0 END
FROM dbo.OAS_Party op
GO