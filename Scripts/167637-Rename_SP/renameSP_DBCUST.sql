/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210923@Danny
	DB: DBCUST.bodb_licensee
	Description: Rename SP
*/

USE bodb_licensee
GO

EXEC sp_rename 'dbo.LA_GroupMinFeeGet', 'DEL_LA_GroupMinFeeGet'; 