/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210811@Danny
	DB: DBCUST.bodb_licensee
	Description: Rename SP
*/

USE bodb_licensee
GO
EXEC sp_rename 'dbo.LA_PartyListTerminatedSel', 'DEL_LA_PartyListTerminatedSel'; 