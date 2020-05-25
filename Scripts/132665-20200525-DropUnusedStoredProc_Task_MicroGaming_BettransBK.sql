/*<info serverAlias="DBRPT-bodb_report"></info>*/

/*
	Created: 20200525@Parsons
	Task: Integrate Sexy Gaming for deposit licensees [RedmineID: #132665]
	Database: DBRPT-bodb_report
	Description: drop unused store procedure
*/

USE bodb_report
GO

IF EXISTS (SELECT 1 FROM dbo.sysobjects WHERE ID = object_id('Task_MicroGaming_BettransBK') AND OBJECTPROPERTY(ID, N'IsProcedure') = 1)
BEGIN
	DROP PROCEDURE Task_MicroGaming_BettransBK
END
GO