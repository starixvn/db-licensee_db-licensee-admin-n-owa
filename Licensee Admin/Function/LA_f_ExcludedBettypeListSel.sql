/*<info serverAlias="DBLIC-bodb_Licensee" selecters="wsv_nap" isFunction="1" isNested="1"></info>*/
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
		- 20220218@Danny: Allbet - Promotion integration [#167510]
		- 20221024@Danny: MG-RNG - Tournament Prize [#176986]
		- 20230217@Danny: SG - Promotion prize integration [#183739]
		- 20240911@Sally: Support Odds Boost Voucher [#209884]

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
		SELECT 0 AS ProductID, BettypeID, [Description]
		FROM (VALUES(997, 'SB - Boosted Odds')) AS v(BettypeID, [Description]) --SB
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
		FROM (VALUES(4599, 'SG Jackpot Contribution'), (4600, 'SG Jackpot Prize'), (4598, 'SG Promotion Prize')) AS v(BettypeID, [Description]) -- SG
			UNION ALL
		SELECT 21 AS ProductID, BettypeID, [Description]
		FROM (VALUES(2499, 'Promotion')) AS v(BettypeID, [Description]) -- Allbet
				UNION ALL
		SELECT 73 AS ProductID, BettypeID, [Description]
		FROM (VALUES(8695, 'Tournament Prize')) AS v(BettypeID, [Description]) -- MG-RNG
	)
	INSERT INTO @Result (ProductID, BettypeID, [Description])
	SELECT r.* 
	FROM cte_Data r
	LEFT JOIN STRING_SPLIT(@ProductIDs, ',') p ON r.ProductID = p.value 
	LEFT JOIN STRING_SPLIT(@ExceptedBettypeIDs, ',') b ON r.BettypeID = b.value
	WHERE (@ProductIDs = '' OR p.value IS NOT NULL) AND 
		  (@ExceptedBettypeIDs = '' OR b.value IS NULL)

	RETURN
END
GO