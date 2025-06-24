/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20250506@Danny
	DB: DBLIC.bodb_licenseeReport
	Description: create new tables
*/



USE bodb_licenseeReport

ALTER TABLE SabaPlayPerformance ADD CurrencyRatio VARCHAR(MAX)

ALTER TABLE SabaPlay_Operators ADD CurrencyRatio VARCHAR(MAX)