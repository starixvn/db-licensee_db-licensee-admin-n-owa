/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210811@Danny
	DB: DBCUST.bodb_licensee
	Description: Rename SP
*/

USE bodb_licensee
GO

EXEC sp_rename 'dbo.LA_PartyListTerminatedSel', 'DEL_LA_PartyListTerminatedSel'; 
EXEC sp_rename 'dbo.LA_PayerInfoSel', 'DEL_LA_PayerInfoSel'; 
EXEC sp_rename 'dbo.LA_PayerListSel', 'DEL_LA_PayerListSel'; 
EXEC sp_rename 'dbo.LA_PayerSettingDetailSel', 'DEL_LA_PayerSettingDetailSel'; 
EXEC sp_rename 'dbo.LA_GroupMinFee_AvailablePartyListSel', 'DEL_LA_GroupMinFee_AvailablePartyListSel'; 
EXEC sp_rename 'dbo.LA_PayerSettingSel', 'DEL_LA_PayerSettingSel';
