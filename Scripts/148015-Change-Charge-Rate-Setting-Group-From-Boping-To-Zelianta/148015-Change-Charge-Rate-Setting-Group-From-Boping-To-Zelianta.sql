/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20201230@Parsons
	Task: [ig128s] Change Charge Rate Setting Group From Boping To Zelianta [RedmineID: #148015]
	DB: DBCUST.bodb_licensee
	Description: [ig128s] Change-Charge-Rate-Setting-Group-From-Boping-To-Zelianta
*/

USE bodb_licensee
GO

UPDATE OAS_ChargeInfo WITH(ROWLOCK)
SET ToParty = 98
WHERE ChargeID IN (4948,4949,4950,4951)