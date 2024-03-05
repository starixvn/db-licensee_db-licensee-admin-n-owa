/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240304@Danny
	DB: DBCUST.bodb_Licensee
	Task: Add new credit site [#201756]
	Description: Correct VS3 setting chargeRate
*/
USE bodb_Licensee
GO


UPDATE  OAS_ChargeInfo WITH(ROWLOCK)
SET ToParty = 1
WHERE ChargeID = 10305 AND ProductID = 77 AND FromParty = 15  AND ToParty = 13


UPDATE  OAS_ChargeInfo WITH(ROWLOCK)
SET ToParty = 98
WHERE ChargeID = 10300 AND ProductID = 77 AND FromParty = 17  AND ToParty = 13