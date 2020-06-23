/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Task: Special handling for INH market [RedmineID: #128570]
	Database: DBCUST.bodb_licensee
	Description: Change structure of table LA_DiscountGroupAssignment LA site
*/

USE bodb_Licensee
GO

-- #1 add IsSpecialTreatment column
--
ALTER TABLE dbo.LA_DiscountGroupAssignment
	ADD IsSpecialTreatment BIT CONSTRAINT DF_LA_DiscountGroupAssignment_IsSpecialTreatment DEFAULT ((0)) NULL
GO

-- #2 initial value
--
UPDATE dbo.LA_DiscountGroupAssignment SET IsSpecialTreatment = 0 WHERE IsSpecialTreatment IS NULL

-- #3 alter IsSpecialTreatment NOT NULL
--
ALTER TABLE dbo.LA_DiscountGroupAssignment ALTER COLUMN IsSpecialTreatment BIT NOT NULL
GO