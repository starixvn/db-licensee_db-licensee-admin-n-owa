/*<info serverAlias="DBLIC-bodb_Licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_Licensee
GO

ALTER FUNCTION [dbo].[LA_f_ExcludedBettypeListSel] 
(
	 @ProductIDs	 		VARCHAR(500) = '',
	 @ExceptedBettypeIDs	VARCHAR(500) = ''
)
RETURNS @Result TABLE 
(
	ProductID INT, BettypeID INT, [Description] VARCHAR(100)
)
AS
/*	Created: 20201020@Parsons
	Task : Select list of excluded bettypes
	DB: DBLIC.bodb_Licensee
	
	Revisions:
		- 20201023@Parsons: LA Arcadia Gaming Add Bonus [#143597]  
		- 20210501@Parsons: Saba Club - Integrate Slot Game [#147977]  
		- 20210306@Danny: AE Sexy - Support Lucky Draw [#152141]
		- 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
		- 20220110@Danny: SG - Jackpot prize integration [#167089]

	Param's Explanation:
		@ProductIDs: Filter by list of products 
		@ExceptedBettypeIDs: Do not return these bettype. 
			Ex: SELECT * FROM LA_f_ExcludedBettypeListSel('', '4297')
*/

BEGIN
	;WITH cte_Data AS
	(
		SELECT 0 AS ProductID, BettypeID, [Description]
		FROM (VALUES(999, 'SB - Adjusted Odds')) AS v(BettypeID, [Description]) --SB
			UNION ALL
		SELECT 11 AS ProductID, BettypeID, [Description]
		FROM (VALUES(1706, 'GD Tips')) AS v(BettypeID, [Description]) -- GD
			UNION ALL
		SELECT 13 AS ProductID, BettypeID, [Description]
		FROM (VALUES(901,''),(902,''),(903,''),(904,'')) AS v(BettypeID, [Description]) --Bettrade
			UNION ALL
		SELECT 25 AS ProductID, BettypeID, [Description]
		FROM (VALUES(911,''),(912,''),(913,''),(914,'')) AS v(BettypeID, [Description]) --Cashout
			UNION ALL
		SELECT 32 AS ProductID, BettypeID, [Description]
		FROM (VALUES(4300, 'PP Prize'), (4299, 'PP Prize'), (4298, 'PP Jackpot Prize'), (4297, 'PP Jackpot Contribution')) AS v(BettypeID, [Description]) -- Pragmatic
		UNION ALL
			SELECT 34 AS ProductID, BettypeID, [Description]
		FROM (VALUES(1906, 'CC Bonus')) AS v(BettypeID, [Description]) -- CardClub (aka Arcadia Gaming)
			UNION ALL
		SELECT 39 AS ProductID, BettypeID, [Description]
		FROM (VALUES(3007, 'SAG Tips')) AS v(BettypeID, [Description]) -- SAG
			UNION ALL
		SELECT 42 AS ProductID, BettypeID, [Description]
		FROM (VALUES(1698, 'SBC Jackpot Contribution'), (1699, 'SBC Jackpot Prize')) AS v(BettypeID, [Description]) -- SBC
			UNION ALL
		SELECT 45 AS ProductID, BettypeID, [Description]
		FROM (VALUES(3150, 'Lucky Draw')) AS v(BettypeID, [Description]) -- AESexy Lucky Draw
			UNION ALL
		SELECT 66 AS ProductID, BettypeID, [Description]
		FROM (VALUES(3898, 'VGA Jackpot Contribution'), (3899, 'VGA Jackpot Prize')) AS v(BettypeID, [Description]) -- VGA
			UNION ALL
		SELECT 36 AS ProductID, BettypeID, [Description]
		FROM (VALUES(4599, 'SG Jackpot Contribution'), (4600, 'SG Jackpot Prize')) AS v(BettypeID, [Description]) -- SG
	)
	INSERT INTO @Result (ProductID, BettypeID, [Description])
	SELECT r.* 
	FROM cte_Data r
	LEFT JOIN bodb02.dbo.strSplit(@ProductIDs, ',') p ON r.ProductID = p.val 
	LEFT JOIN bodb02.dbo.strSplit(@ExceptedBettypeIDs, ',') b ON r.BettypeID = b.val
	WHERE (@ProductIDs = '' OR p.val IS NOT NULL) AND 
		  (@ExceptedBettypeIDs = '' OR b.val IS NULL)

	RETURN
END
GO