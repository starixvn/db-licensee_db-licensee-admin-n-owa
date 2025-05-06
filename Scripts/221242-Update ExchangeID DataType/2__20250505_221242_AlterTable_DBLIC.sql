/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20250505@Danny
	DB: DBLIC.bodb_licenseeReport
	Description:  update exchangeID column data type
*/

USE bodb_licenseeReport

ALTER TABLE bettrans
ALTER COLUMN currency INT ;


