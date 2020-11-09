/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/

/*
	Created: 20201026@Parsons
	Task: Enhance Number Game Win Loss Report [RedmineID: #142969]
	Database: DBLIC.bodb_LicenseeReport
	Description: Change structure of table bettrans, rpt_Betting

*/
USE bodb_LicenseeReport
GO

 --#1. bettrans: BetID, epositiontaking 
ALTER TABLE dbo.bettrans
	ADD BetID  BIGINT CONSTRAINT DF_bettrans_BetID DEFAULT (0) NULL
GO

ALTER TABLE dbo.bettrans
	ADD epositiontaking  SMALLMONEY CONSTRAINT DF_bettrans_epositiontaking DEFAULT (0) NULL
GO

 --#2. rpt_Betting: WinLossE, CommissionE
ALTER TABLE dbo.rpt_Betting
	ADD WinLossE MONEY CONSTRAINT DF_rpt_Betting_WinLossE DEFAULT (0) NULL
GO

ALTER TABLE dbo.rpt_Betting
	ADD CommissionE MONEY CONSTRAINT DF_rpt_Betting_CommissionE DEFAULT (0) NULL
GO