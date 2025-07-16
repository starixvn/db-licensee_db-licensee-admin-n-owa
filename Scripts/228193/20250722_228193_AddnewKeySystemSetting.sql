/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20250722@Danny
	DB: DBCUST.bodb_licensee
	Task: Add new key on Manage System Settings function [RedmineID: #228193]
*/
USE bodb_licensee
GO


INSERT INTO dbo.LA_SystemSettings ([Key], [Value])
VALUES ('AllowEditPayToSupplierRate', '{}')
GO