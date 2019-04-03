/*<info serverAlias="DBLIC-bodb_LicenseeReport" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_LicenseeReport]
GO

CREATE PROCEDURE [dbo].[LA_IsDataReady] 
AS
/*

	Created: 20190403@Bruce
	Task:  check data of sum rpt_betting done yet 
	Revision: 
		- 20190403@Bruce: Copy Task_rptBetting_CheckDataReady

*/

BEGIN 
	SET NOCOUNT ON;

	DECLARE 
		@Today DATE = GETDATE(),
		@MaxDate DATE = (SELECT MAX(RptDate) FROM dbo.rpt_Betting WITH (NOLOCK)),
		@IsDataYesterdayReady BIT = 0,
		@IsStagingBettrans VARCHAR(200) = (
			SELECT TOP 1 VValue 
			FROM bodb02.dbo.SystemSettings WITH (NOLOCK) 
			WHERE VName = 'IsStagingBettrans'
		)
 
	---Has data at sum table and all steps of the Job are done
	SET @IsDataYesterdayReady = (CASE
		WHEN @MaxDate >= DATEADD (DAY, -1, @Today) AND @IsStagingBettrans = '0' THEN 1
		ELSE 0
	END)

	SELECT @IsDataYesterdayReady AS IsDataYesterdayReady
END 
GO 
 
 