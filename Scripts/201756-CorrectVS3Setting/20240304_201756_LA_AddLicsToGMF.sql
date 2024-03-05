/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240304@Danny
	DB: DBCUST.bodb_Licensee
	Task: Add new credit site [#201756]
	Description: Add new licensee to GMF
*/
USE bodb_Licensee
GO


INSERT INTO LA_GroupMinFeeAssignment (GroupMinFeeID, PartyID, IsPrimary)
SELECT 105, -- KeenOcean group_Aug2023
	   1009, -- ac88sw
		0
