/*<info serverAlias="DBLIC-bodb_licensee"></info>*/
/*
	Created: 20250609@Eddie
	Task : Delete SP for removing mix mode [RedmineID: #228189]
*/
USE bodb_licensee
GO

EXEC sp_rename 'SH_LaunchSabaPlayLicensee_PayerListSel', 'DEL_SH_LaunchSabaPlayLicensee_PayerListSel'
GO