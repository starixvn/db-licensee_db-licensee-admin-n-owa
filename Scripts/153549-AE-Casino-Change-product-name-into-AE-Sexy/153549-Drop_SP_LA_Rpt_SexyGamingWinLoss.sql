/*<info serverAlias="DBLIC-bodb_Licensee"></info>*/

/*
	Created: 20210422@Mason
	Task: Change product name into AE Sexy [RedmineID: #153549]
	Database: DBLIC-bodb_Licensee
	Description: Drop SP LA_Rpt_SexyGamingWinLoss
*/

USE bodb_licensee
GO

IF EXISTS (SELECT 1 FROM dbo.sysobjects WHERE ID = object_id('LA_Rpt_SexyGamingWinLoss') AND OBJECTPROPERTY(ID, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE LA_Rpt_SexyGamingWinLoss
END
GO