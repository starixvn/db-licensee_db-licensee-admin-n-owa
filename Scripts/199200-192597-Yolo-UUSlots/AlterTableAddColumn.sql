/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20240409@Danny
	DB: DBLIC-bodb_licenseeReport
	Description: Alter table add more column
*/

USE bodb_licenseeReport
GO


ALTER TABLE [dbo].[rpt_ThirdPartyWL_ExtraGMT] ADD
	MWinloss	MONEY DEFAULT NULL,
	MComm		MONEY DEFAULT NULL,
	SWinloss	MONEY DEFAULT NULL,
	SComm		MONEY DEFAULT NULL,
	EWinloss	MONEY DEFAULT NULL,
	EComm		MONEY DEFAULT NULL,
	HouseTurnover MONEY DEFAULT NULL
