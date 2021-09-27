/*<info serverAlias="DBLIC-bodb_licensee"></info>*/

/*
	Created: 20210923@Danny
	DB: DBLIC.bodb_licensee
	Description: Rename SP
*/

USE bodb_licensee
GO

EXEC sp_rename 'dbo.LA_PartyListTerminatedSel', 'DEL_LA_PartyListTerminatedSel'; 
EXEC sp_rename 'dbo.LA_LicenseeStatusListSel', 'DEL_LA_LicenseeStatusListSel'; 