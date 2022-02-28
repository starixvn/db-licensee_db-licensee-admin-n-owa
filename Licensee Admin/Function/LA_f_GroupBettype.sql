/*<info serverAlias="DBLIC-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE [bodb_Licensee]
GO

ALTER FUNCTION [dbo].[LA_f_GroupBettype]()
RETURNS TABLE
AS

/*
	Created: 20210909@Percy
	DB: DBLIC-bodb_Licensee
	Task: Core function - Group special bettypes

	Revisions:
		- 20210909@Percy: Initialize function [RedmineID: #157652]
		- 20220110@Danny: SG - Jackpot prize integration [#167089]
*/

RETURN
	-- 1: Tips
	SELECT CONVERT(INT, 11) AS ProductId, CONVERT(INT, 1706) AS Bettype, CONVERT(SMALLINT, 1) AS TypeId, CONVERT(VARCHAR(100), 'Tips') AS TypeName -- GD Tips
	UNION ALL SELECT 39, 3007, 1, 'Tips' -- SAG Tips
	-- 2: Jackpot Contribution
	UNION ALL SELECT 32, 4297, 2, 'Jackpot Contribution'
	UNION ALL SELECT 42, 1698, 2, 'Jackpot Contribution'
	UNION ALL SELECT 66, 3898, 2, 'Jackpot Contribution'
	UNION ALL SELECT 36, 4599, 2, 'Jackpot Contribution'

	-- 3: Jackpot Prize
	UNION ALL SELECT 32, 4298, 3, 'Jackpot Prize'
	UNION ALL SELECT 42, 1699, 3, 'Jackpot Prize'
	UNION ALL SELECT 66, 3899, 3, 'Jackpot Prize'
	UNION ALL SELECT 36, 4600, 3, 'Jackpot Prize'
	-- 4: Prize
	UNION ALL SELECT 32, 4299, 4, 'Prize'
	UNION ALL SELECT 32, 4300, 4, 'Prize'
	-- 5: Lucky Draw
	UNION ALL SELECT 45, 3150, 5, 'Lucky Draw'
	-- 6: Bonus
	UNION ALL SELECT 34, 1906, 6, 'Bonus'
	-- 7: OddsSpread Adjustment
	UNION ALL SELECT 0, 999, 7, 'OddsSpread Adjustment'
GO