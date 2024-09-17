/*<info serverAlias="DBLIC-bodb_licensee" selecters="wsv_nap" isFunction="1" isNested="1"></info>*/
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
		- 20220222@Danny: Allbet - Promotion integration [#167510]
		- 20221024@Danny: MG-RNG - Tournament Prize [#176986]
		- 20230223@Danny: SG - Promotion prize integration And Use SportBettypeMatrix  [#183739]
		- 20230223@Danny: Integrate Casino promotion [#194808]
		- 20240911@Sally: Support Odds Boost Voucher [#209884]
*/

RETURN
	WITH t AS
	(
		SELECT DISTINCT x.BetType, x.SubProduct, p.ProductID, p3.Productid AS ProductID_3rd
		FROM bodb02.dbo.SportBettypeMatrix x WITH(NOLOCK)
		INNER JOIN bodb02.dbo.Products p WITH(NOLOCK) ON x.ProductID = p.ProductID
		LEFT JOIN Product3rd p3 WITH(NOLOCK) ON p.ProductPrefix = p3.ProductPrefix
		WHERE x.SubProduct IN ('Tips','Jackpot Contribution','Jackpot Prize','Prize','Lucky Draw','Bonus','Odds Spread Adjustment','Promotion','Casino Promotion','Odds Boost Adjustment' )
	)
	SELECT	CONVERT(INT, CASE WHEN ProductID = 1 THEN 0 ELSE ProductID_3rd END) AS ProductId
			, CONVERT(INT, Bettype) AS Bettype
			, CONVERT(SMALLINT,CASE WHEN SubProduct = 'Tips' THEN 1 
									WHEN SubProduct = 'Jackpot Contribution' THEN 2
									WHEN SubProduct = 'Jackpot Prize' THEN 3
									WHEN SubProduct = 'Prize' THEN 4
									WHEN SubProduct = 'Lucky Draw' THEN 5
									WHEN SubProduct = 'Bonus' THEN 6
									WHEN SubProduct = 'Odds Spread Adjustment' THEN 7
									WHEN SubProduct = 'Promotion' THEN 8
									WHEN SubProduct = 'Casino Promotion' THEN 10
									WHEN SubProduct = 'Odds Boost Adjustment' THEN 11
									END
					 ) AS TypeId
			,CONVERT(VARCHAR(100), SubProduct) AS TypeName
	FROM t

GO